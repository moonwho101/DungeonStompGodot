# OpenXR support: head-tracked view, controller locomotion, a controller-held player weapon rendered in a
# fixed MD2 pose (frame 0, never animated - the controller supplies all motion), physical swing melee and a
# world-space panel for the 2D UI. Only created when an OpenXR runtime is available; otherwise the desktop
# camera path is used unchanged.
#
# The game's existing `camera` keeps acting as the player body/head proxy (collision, saves, minimap and AI all
# read it). Each frame the rig moves the XR origin so the tracked head sits on that proxy, and copies the head
# orientation back onto it.
class_name XRRig
extends Node3D

const UNITS_PER_METER := 60.0 # CollisionWorld.EYE_HEIGHT (100 units) ~ 1.7 m
const STICK_DEADZONE := 0.15
const TURN_SPEED := 2.4 # rad/s, smooth turn on the right stick
const SWING_START_SPEED := 1.6 * UNITS_PER_METER # weapon tip speed (units/s) that starts a swing
const SWING_END_SPEED := 1.0 * UNITS_PER_METER # swing continues until the tip slows below this
const SWING_COOLDOWN := 0.25 # seconds after a swing ends before another can start
const HIT_PADDING := 6.0 # inflates monster boxes for blade hit tests
const LASER_LENGTH := 4.0 * UNITS_PER_METER

# Weapon fit in the hand. The MD2 frame-0 pose is measured to find the pommel -> tip axis, which is aligned with
# the controller grip pose -Z (through the closed fist); the blade's flat faces the palm (+X).
const WEAPON_SCALE := 0.85 # multiplier on the modellist scale
const WEAPON_GRIP_FRACTION := 0.18 # where along pommel -> tip the hand holds the weapon
const WEAPON_GRIP_FRACTION_OVERRIDES := {"weaponsorcerer": 0.4}
const WEAPON_OFFSET := Vector3.ZERO # extra anchor offset in grip space (units)
const WEAPON_ROT_DEG := Vector3.ZERO # extra anchor rotation in grip space (degrees)

const UI_SIZE := Vector2i(1920, 1080)
const UI_BASE_SIZE := Vector2i(1280, 720) # smaller layout canvas than desktop so text is readable on the panel
const UI_WIDTH := 1.6 * UNITS_PER_METER
const UI_DISTANCE := 1.5 * UNITS_PER_METER
const UI_FOLLOW_ANGLE := 0.6 # radians the head may turn away before the panels recentre
const UI_FOLLOW_SPEED := 4.0

# HUD overlays (stat bar, minimap, debug panel) each get their own panel placed at a fixed angle from where the
# player faces, like a VR dungeon crawler: info in the upper corners of view, stat bar low. Angles in degrees
# (yaw: + is right; pitch: + is up). The anchor is the quad corner/edge that sits at that angle.
const OVERLAY_DISTANCE := 1.4 * UNITS_PER_METER
const OVERLAY_PIXEL := UI_WIDTH / 1280.0 # world size of one overlay pixel (GameUI.HUD_SCALE sets the stat bar's pixels)
const OVERLAY_SUPERSAMPLE := 2 # render overlays at this multiple of their pixel size for sharp text
const DEBUG_PANEL_ANGLES := Vector2(-38.0, 20.0) # top-left corner of the debug panel
const MINIMAP_ANGLES := Vector2(38.0, 20.0) # top-right corner of the minimap
const STAT_BAR_ANGLES := Vector2(0.0, -30.0) # top edge (centre) of the stat bar

var game # Game (untyped to avoid a class cycle)
var simulated := false # --xr-simulate: build the rig without a runtime, using fixed head/hand poses
var origin: XROrigin3D
var head: XRCamera3D
var left_hand: XRController3D
var right_grip: XRController3D
var right_aim: XRController3D
var weapon_anchor: Node3D
var ui_viewport: SubViewport
var ui_panel: MeshInstance3D
var overlays: Array = [] # {control, viewport, quad, angles, anchor}
var laser: MeshInstance3D

var weapon_tip_local := Vector3.ZERO
var weapon_pommel_local := Vector3.ZERO
var swing_state := new_swing_state()

var _written_yaw := INF
var _last_local_head := Vector3.ZERO
var _has_last_head := false
var _prev_buttons: Dictionary = {}
var _sprint_toggle := false
var _panel_yaw := INF
var _panel_following := true
var _panel_was_menu := false
var _hud_yaw := INF
var _hud_following := true
var _prev_tip_origin := Vector3.ZERO
var _prev_pommel_origin := Vector3.ZERO
var _has_prev_tip := false
var _pointer_pressed := false
var _hit_this_swing: Array = []


# Returns a ready rig, or null when no OpenXR runtime/headset is available.
static func try_create(p_game) -> XRRig:
	var args := OS.get_cmdline_user_args()
	if "--no-xr" in args:
		return null
	var simulate := "--xr-simulate" in args
	if not simulate:
		var xr := XRServer.find_interface("OpenXR")
		if xr == null:
			return null
		if not xr.is_initialized() and not xr.initialize():
			return null
	var rig := XRRig.new()
	rig.name = "XRRig"
	rig.game = p_game
	rig.simulated = simulate
	print("XR rig simulated without a headset" if simulate else "OpenXR initialized: running in VR mode")
	return rig


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not simulated:
		get_viewport().use_xr = true
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)

	origin = XROrigin3D.new()
	origin.name = "XROrigin"
	origin.world_scale = UNITS_PER_METER
	add_child(origin)
	origin.current = true

	head = XRCamera3D.new()
	head.name = "XRHead"
	head.near = 1.0
	head.far = 3600.0
	origin.add_child(head)
	head.current = true

	left_hand = _controller("LeftHand", &"left_hand", &"grip")
	right_grip = _controller("RightHandGrip", &"right_hand", &"grip")
	right_aim = _controller("RightHandAim", &"right_hand", &"aim")

	weapon_anchor = Node3D.new()
	weapon_anchor.name = "WeaponAnchor"
	weapon_anchor.position = WEAPON_OFFSET
	weapon_anchor.rotation_degrees = WEAPON_ROT_DEG
	right_grip.add_child(weapon_anchor)

	_build_ui_panel()
	_build_laser()
	if simulated:
		# Standing head and a right hand held forward with the weapon raised.
		head.position = Vector3(0, CollisionWorld.EYE_HEIGHT, 0)
		right_grip.position = Vector3(18, CollisionWorld.EYE_HEIGHT - 35, -30)
		right_grip.rotation_degrees = Vector3(35, 10, 0)
		right_aim.transform = right_grip.transform
		left_hand.position = Vector3(-18, CollisionWorld.EYE_HEIGHT - 35, -30)


func _controller(node_name: String, tracker: StringName, pose: StringName) -> XRController3D:
	var c := XRController3D.new()
	c.name = node_name
	c.tracker = tracker
	c.pose = pose
	origin.add_child(c)
	return c


func _build_ui_panel() -> void:
	ui_viewport = SubViewport.new()
	ui_viewport.name = "UIViewport"
	ui_viewport.size = UI_SIZE
	ui_viewport.size_2d_override = UI_BASE_SIZE
	ui_viewport.size_2d_override_stretch = true
	ui_viewport.transparent_bg = true
	ui_viewport.disable_3d = true
	ui_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(ui_viewport)

	var quad := QuadMesh.new()
	quad.size = Vector2(UI_WIDTH, UI_WIDTH * float(UI_SIZE.y) / UI_SIZE.x)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.no_depth_test = true
	mat.disable_fog = true
	mat.render_priority = 10
	mat.albedo_texture = ui_viewport.get_texture()
	ui_panel = MeshInstance3D.new()
	ui_panel.name = "UIPanel"
	ui_panel.mesh = quad
	ui_panel.material_override = mat
	ui_panel.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ui_panel)


# Moves the game's HUD elements out of the full-screen UI onto their own world-space panels.
func attach_hud_overlays(ui) -> void:
	_add_overlay(ui.take_hud_panel(), STAT_BAR_ANGLES, Vector2(0.0, 1.0))
	_add_overlay(ui.take_minimap(), MINIMAP_ANGLES, Vector2(1.0, 1.0))
	_add_overlay(ui.take_info_panel(), DEBUG_PANEL_ANGLES, Vector2(-1.0, 1.0))


# anchor: which point of the quad sits at the given angles, in quad half-extents (-1..1; x right, y up).
func _add_overlay(control: Control, angles: Vector2, anchor: Vector2) -> void:
	var vp := SubViewport.new()
	vp.name = "%sViewport" % control.name
	vp.transparent_bg = true
	vp.disable_3d = true
	vp.size_2d_override_stretch = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	vp.add_child(control)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.no_depth_test = true
	mat.disable_fog = true
	mat.render_priority = 9 # below the menu panel
	mat.albedo_texture = vp.get_texture()
	var quad := MeshInstance3D.new()
	quad.name = "%sPanel" % control.name
	quad.mesh = QuadMesh.new()
	quad.material_override = mat
	quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(quad)
	var o := {"control": control, "viewport": vp, "quad": quad, "angles": angles, "anchor": anchor}
	overlays.append(o)
	control.resized.connect(_fit_overlay.bind(o))
	control.visibility_changed.connect(func(): quad.visible = control.visible)
	quad.visible = control.visible
	_fit_overlay(o)


func _fit_overlay(o: Dictionary) -> void:
	var control: Control = o.control
	var px := Vector2i(ceili(control.size.x), ceili(control.size.y))
	if px.x <= 0 or px.y <= 0:
		return
	control.position = Vector2.ZERO
	var vp: SubViewport = o.viewport
	var ss := mini(OVERLAY_SUPERSAMPLE, 16384 / maxi(px.x, px.y))
	vp.size = px * maxi(1, ss)
	vp.size_2d_override = px
	(o.quad.mesh as QuadMesh).size = Vector2(px) * OVERLAY_PIXEL


# Body-locked placement: overlays share one lazily-following yaw and ignore the menu, so they never jump.
func _place_overlays(delta: float, head_yaw: float, hp: Vector3) -> void:
	if overlays.is_empty():
		return
	if is_inf(_hud_yaw):
		_hud_yaw = head_yaw
	var diff := angle_difference(_hud_yaw, head_yaw)
	if absf(diff) > UI_FOLLOW_ANGLE:
		_hud_following = true
	if _hud_following:
		_hud_yaw += diff * minf(1.0, UI_FOLLOW_SPEED * delta)
		if absf(angle_difference(_hud_yaw, head_yaw)) < 0.02:
			_hud_following = false
	for o: Dictionary in overlays:
		var quad: MeshInstance3D = o.quad
		var a: Vector2 = o.angles
		# Faces the head: the quad's +Z points back along the view ray.
		var b := Basis(Vector3.UP, _hud_yaw + deg_to_rad(-a.x)) * Basis(Vector3.RIGHT, deg_to_rad(a.y))
		var anchor_pos := hp + b * Vector3(0, 0, -OVERLAY_DISTANCE)
		var half: Vector2 = (quad.mesh as QuadMesh).size * 0.5
		var anchor: Vector2 = o.anchor
		quad.global_basis = b
		quad.global_position = anchor_pos - b * Vector3(anchor.x * half.x, anchor.y * half.y, 0.0)


func _build_laser() -> void:
	var box := BoxMesh.new()
	box.size = Vector3(0.4, 0.4, 1.0)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.4, 0.8, 1.0)
	mat.no_depth_test = true
	mat.render_priority = 11
	laser = MeshInstance3D.new()
	laser.name = "PointerLaser"
	laser.mesh = box
	laser.material_override = mat
	laser.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	laser.visible = false
	right_aim.add_child(laser)

# ---------------------------------------------------------------- Weapon (fixed pose)

# Attaches the player's MD2 weapon to the right controller in a fixed pose. The MD2 is set to frame 0 once
# and never animated; all movement comes from the tracked controller.
func attach_weapon(mesh: MeshInstance3D, md2: MD2Model, def_name: String, def_scale: float) -> void:
	var fit := weapon_fit(md2, def_name, def_scale)
	mesh.transform = fit.transform
	md2.set_pose(mesh, [0], [1.0])
	weapon_anchor.add_child(mesh)
	weapon_tip_local = weapon_anchor.transform * fit.tip
	weapon_pommel_local = weapon_anchor.transform * fit.pommel
	_has_prev_tip = false
	swing_state = new_swing_state()


static func weapon_fit(md2: MD2Model, def_name: String, def_scale: float) -> Dictionary:
	var verts := PackedVector3Array()
	if md2.mesh != null and md2.mesh.get_surface_count() > 0:
		verts = md2.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var frac: float = WEAPON_GRIP_FRACTION_OVERRIDES.get(def_name.to_lower(), WEAPON_GRIP_FRACTION)
	return weapon_grip_transform(verts, frac, def_scale * WEAPON_SCALE)


# Measures a frame-0 weapon mesh and returns the model -> grip-space transform that puts the hand point at
# the origin and the blade along -Z. The tip is the end of the long axis furthest along +X+Y (MD2 weapons
# are modelled in the right hand of a standing character with the blade pointing out and up).
static func weapon_grip_transform(verts: PackedVector3Array, grip_fraction: float, scale: float) -> Dictionary:
	if verts.is_empty():
		return {"transform": Transform3D.IDENTITY.scaled(Vector3.ONE * scale), "tip": Vector3(0, 0, -scale), "pommel": Vector3.ZERO}
	var c := Vector3.ZERO
	for p in verts:
		c += p
	c /= verts.size()
	var end_a := c
	var best := -1.0
	for p in verts:
		var d := p.distance_squared_to(c)
		if d > best:
			best = d
			end_a = p
	var end_b := end_a
	best = -1.0
	for p in verts:
		var d := p.distance_squared_to(end_a)
		if d > best:
			best = d
			end_b = p
	var tip := end_a
	var pommel := end_b
	if end_b.x + end_b.y > end_a.x + end_a.y:
		tip = end_b
		pommel = end_a
	var axis := tip - pommel
	if axis.length_squared() < 1e-6:
		axis = Vector3(0, 0, -1)
	axis = axis.normalized()
	var side := Vector3(0, 0, 1) - axis * axis.z
	if side.length_squared() < 1e-4:
		side = Vector3(1, 0, 0) - axis * axis.x
	side = side.normalized()
	var z := -axis
	var y := z.cross(side).normalized()
	var rot := Basis(side, y, z).transposed() # model axis -> -Z, model side -> +X
	var b := rot.scaled(Vector3.ONE * scale)
	var grip := pommel.lerp(tip, grip_fraction)
	var xf := Transform3D(b, -(b * grip))
	return {"transform": xf, "tip": xf * tip, "pommel": xf * pommel}

# ---------------------------------------------------------------- Swing melee

static func new_swing_state() -> Dictionary:
	return {"active": false, "cooldown": 0.0}


# Advances the swing state machine for the current tip speed (units/s).
# Returns "start" when a swing begins, "end" when it finishes, or "" otherwise.
static func swing_step(state: Dictionary, tip_speed: float, delta: float) -> String:
	if state.active:
		if tip_speed < SWING_END_SPEED:
			state.active = false
			state.cooldown = SWING_COOLDOWN
			return "end"
		return ""
	state.cooldown = maxf(0.0, state.cooldown - delta)
	if state.cooldown <= 0.0 and tip_speed >= SWING_START_SPEED:
		state.active = true
		return "start"
	return ""


# True when the blade (pommel -> tip) or the tip's sweep since last frame touches the padded box.
static func blade_hits_box(box_min: Vector3, box_max: Vector3, pad: float, pommel: Vector3, tip: Vector3, prev_tip: Vector3) -> bool:
	if box_max.x < box_min.x or box_max.y < box_min.y or box_max.z < box_min.z:
		return false
	var box := AABB(box_min - Vector3.ONE * pad, box_max - box_min + Vector3.ONE * pad * 2.0)
	if box.has_point(tip) or box.has_point(pommel):
		return true
	return box.intersects_segment(pommel, tip) != null or box.intersects_segment(prev_tip, tip) != null


func _update_swing(delta: float, can_hit: bool) -> void:
	var inv := origin.global_transform.affine_inverse()
	var hand_xf: Transform3D = (weapon_anchor.get_parent() as Node3D).global_transform
	var tip_world: Vector3 = hand_xf * weapon_tip_local
	var pommel_world: Vector3 = hand_xf * weapon_pommel_local
	# Measured in origin space so locomotion and smooth turning don't count as swinging.
	var tip_o: Vector3 = inv * tip_world
	var pommel_o: Vector3 = inv * pommel_world
	if not _has_prev_tip or delta <= 0.0:
		_prev_tip_origin = tip_o
		_prev_pommel_origin = pommel_o
		_has_prev_tip = true
		return
	var speed: float = (tip_o - _prev_tip_origin).length() / delta
	var prev_tip_world: Vector3 = origin.global_transform * _prev_tip_origin
	var ev := swing_step(swing_state, speed if can_hit else 0.0, delta)
	if ev == "start":
		_hit_this_swing.clear()
		game.on_xr_swing_started()
	if swing_state.active and can_hit:
		var dir: Vector3 = tip_world - prev_tip_world
		dir = dir.normalized() if dir.length_squared() > 1e-6 else -head.global_basis.z
		for m in game.monsters:
			if m.dead or m.health <= 0.0 or m in _hit_this_swing:
				continue
			if blade_hits_box(m.bbox.min, m.bbox.max, HIT_PADDING, pommel_world, tip_world, prev_tip_world):
				_hit_this_swing.append(m)
				game.apply_melee_hit(m, dir)
				haptic(120, 0.9)
	_prev_tip_origin = tip_o
	_prev_pommel_origin = pommel_o

# ---------------------------------------------------------------- Input

func _just(c: XRController3D, button: String) -> bool:
	var key := "%s:%s" % [c.name, button]
	var down := c.is_button_pressed(button)
	var was: bool = _prev_buttons.get(key, false)
	_prev_buttons[key] = down
	return down and not was


static func _stick(v: Vector2) -> Vector2:
	var mag := v.length()
	if mag <= STICK_DEADZONE:
		return Vector2.ZERO
	return v * (minf(1.0, (mag - STICK_DEADZONE) / (1.0 - STICK_DEADZONE)) / mag)


# Reads the controllers into the same dictionary shape GamepadInput.poll returns. Also drives the UI pointer
# and the menu button, including while paused.
func poll(delta: float, paused: bool) -> Dictionary:
	var trigger_down := right_aim.get_float("trigger") > 0.6
	var trigger_just: bool = trigger_down and not _prev_buttons.get("trigger", false)
	_prev_buttons["trigger"] = trigger_down
	var menu := _just(left_hand, "menu_button")
	var a := _just(right_grip, "ax_button")
	var b := _just(right_grip, "by_button")
	var x := _just(left_hand, "ax_button")
	var y := _just(left_hand, "by_button")
	var l3 := _just(left_hand, "primary_click")
	var r3 := _just(right_grip, "primary_click")
	_update_pointer(trigger_down)

	if paused:
		if game.ui.is_menu_visible() and game.world_ready:
			if menu:
				game.ui.on_back_or_resume()
			elif b:
				game.ui.on_back_or_resume()
		return {}

	var move := _stick(left_hand.get_vector2("primary"))
	var look := _stick(right_grip.get_vector2("primary"))
	if l3:
		_sprint_toggle = not _sprint_toggle
	if _sprint_toggle and move.length() < 0.05:
		_sprint_toggle = false
	var fly: bool = game.fly_mode
	var cycle := 0
	if y or r3:
		cycle = 1
	elif x:
		cycle = -1
	return {
		"move_x": move.x, "move_y": -move.y, "turn": look.x,
		"sprint": _sprint_toggle, "jump": a and not fly,
		"fly_up": fly and (right_grip.is_button_pressed("ax_button") or look.y > 0.5),
		"fly_down": fly and look.y < -0.5,
		"attack": trigger_just, "interact": b, "cycle_weapon": cycle, "pause_toggle": menu,
	}


# Combines gamepad and XR input dictionaries (axes add, flags OR) so both can be used together.
static func merge_input(a: Dictionary, b: Dictionary) -> Dictionary:
	var out := a.duplicate()
	for k in b:
		var v = b[k]
		if not out.has(k):
			out[k] = v
		elif v is bool:
			out[k] = bool(out[k]) or v
		elif v is float or v is int:
			if k == "cycle_weapon":
				out[k] = out[k] if int(out[k]) != 0 else v
			else:
				out[k] = clampf(float(out[k]) + float(v), -1.0, 1.0)
	return out


func haptic(duration_ms: float, strength: float) -> void:
	if right_grip == null:
		return
	right_grip.trigger_haptic_pulse("haptic", 0.0, clampf(strength, 0.0, 1.0), clampf(duration_ms, 10.0, 2000.0) / 1000.0, 0.0)


# Spell origin/direction from the right controller's aim ray.
func aim_ray() -> Array:
	return [right_aim.global_position, -right_aim.global_basis.z.normalized()]

# ---------------------------------------------------------------- Body / head sync

static func _yaw_of(b: Basis) -> float:
	var f := -b.z
	return atan2(-f.x, -f.z)


func _rotate_origin_about_head(angle: float) -> void:
	if absf(angle) < 1e-6:
		return
	var pivot := head.global_position
	var t := origin.global_transform
	t.origin -= pivot
	t = t.rotated(Vector3.UP, angle)
	t.origin += pivot
	origin.global_transform = t


# The game sets camera yaw directly on level load, respawn and save restore; turn the play space to match.
func _apply_external_yaw() -> void:
	var cam: Camera3D = game.camera
	if is_inf(_written_yaw) or absf(angle_difference(cam.rotation.y, _written_yaw)) > 1e-3:
		_rotate_origin_about_head(angle_difference(_yaw_of(head.global_basis), cam.rotation.y))
		_written_yaw = cam.rotation.y


# Before movement: physical (room-scale) head motion and smooth turning move the player body.
func begin_frame(delta: float, input: Dictionary) -> void:
	_apply_external_yaw()
	var local_head := head.position
	if _has_last_head:
		var d := local_head - _last_local_head
		d.y = 0.0
		var world_d := origin.global_basis * d
		game.camera.position += Vector3(world_d.x, 0.0, world_d.z)
	_last_local_head = local_head
	_has_last_head = true
	var turn: float = input.get("turn", 0.0)
	if absf(turn) > 0.0:
		_rotate_origin_about_head(-turn * TURN_SPEED * delta)


# After movement: put the tracked head on the collision-resolved body and copy its orientation back.
func sync_body(delta: float, playing: bool) -> void:
	_apply_external_yaw()
	var cam: Camera3D = game.camera
	var head_offset := head.global_position - origin.global_position
	var o := origin.global_position
	o.x = cam.position.x - head_offset.x
	o.z = cam.position.z - head_offset.z
	o.y = cam.position.y - CollisionWorld.EYE_HEIGHT
	origin.global_position = o
	cam.basis = head.global_basis.orthonormalized()
	_written_yaw = cam.rotation.y
	_place_ui_panel(delta)
	if weapon_anchor.get_child_count() > 0:
		_update_swing(delta, playing and not game.player_dead and game.is_melee_weapon())
	else:
		_has_prev_tip = false

# ---------------------------------------------------------------- UI panel and pointer

func _place_ui_panel(delta: float) -> void:
	var menu: bool = game.ui.is_menu_visible()
	var head_yaw := _yaw_of(head.global_basis)
	if is_inf(_panel_yaw):
		_panel_yaw = head_yaw
	var diff := angle_difference(_panel_yaw, head_yaw)
	if absf(diff) > UI_FOLLOW_ANGLE or menu != _panel_was_menu:
		_panel_following = true
	_panel_was_menu = menu
	if _panel_following:
		_panel_yaw += diff * minf(1.0, UI_FOLLOW_SPEED * delta)
		if absf(angle_difference(_panel_yaw, head_yaw)) < 0.02:
			_panel_following = false
	var fwd := Vector3(-sin(_panel_yaw), 0.0, -cos(_panel_yaw))
	var hp := head.global_position
	ui_panel.global_position = hp + fwd * UI_DISTANCE
	ui_panel.global_basis = Basis(Vector3.UP, _panel_yaw)
	_place_overlays(delta, head_yaw, hp)


func _update_pointer(trigger_down: bool) -> void:
	var active: bool = game.ui.is_menu_visible()
	var hit = _pointer_hit() if active else null
	laser.visible = active
	if not active:
		_release_pointer()
		return
	var length := LASER_LENGTH
	if hit != null:
		length = hit[1]
		var pos: Vector2 = hit[0]
		var motion := InputEventMouseMotion.new()
		motion.position = pos
		motion.global_position = pos
		motion.button_mask = MOUSE_BUTTON_MASK_LEFT if _pointer_pressed else 0
		ui_viewport.push_input(motion)
		if trigger_down != _pointer_pressed:
			_pointer_pressed = trigger_down
			var btn := InputEventMouseButton.new()
			btn.button_index = MOUSE_BUTTON_LEFT
			btn.pressed = trigger_down
			btn.position = pos
			btn.global_position = pos
			btn.button_mask = MOUSE_BUTTON_MASK_LEFT if trigger_down else 0
			ui_viewport.push_input(btn)
	elif not trigger_down:
		_release_pointer()
	laser.scale = Vector3(1.0, 1.0, length)
	laser.position = Vector3(0, 0, -length * 0.5)


func _release_pointer() -> void:
	if not _pointer_pressed:
		return
	_pointer_pressed = false
	var btn := InputEventMouseButton.new()
	btn.button_index = MOUSE_BUTTON_LEFT
	btn.pressed = false
	ui_viewport.push_input(btn)


# Returns [pixel position in the UI viewport, ray distance] or null.
func _pointer_hit():
	var inv := ui_panel.global_transform.affine_inverse()
	var p0 := inv * right_aim.global_position
	var d := inv.basis * (-right_aim.global_basis.z)
	if absf(d.z) < 1e-6:
		return null
	var t := -p0.z / d.z
	if t <= 0.0:
		return null
	var local := p0 + d * t
	var size: Vector2 = (ui_panel.mesh as QuadMesh).size
	var uv := Vector2(local.x / size.x + 0.5, 0.5 - local.y / size.y)
	if uv.x < 0.0 or uv.x > 1.0 or uv.y < 0.0 or uv.y > 1.0:
		return null
	var world_dist := (ui_panel.global_transform * local).distance_to(right_aim.global_position)
	return [uv * Vector2(UI_SIZE), world_dist]
