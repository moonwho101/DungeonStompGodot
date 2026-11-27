# HUD, screen overlays and the main/generator/options menus (port of index.html + the HUD code).
class_name GameUI
extends CanvasLayer

const AMBER := Color("#f59e0b")
const SHOW_DEBUG_PANEL := false # top-left info panel (mode, position, depth, objects); set false to hide it
const WEB_MENU_SCALE := 3.0 # web build only: the browser canvas is much smaller than the 4K layout, so enlarge the menu

const VIGNETTE_SHADER := """
shader_type canvas_item;
uniform vec4 edge_color : source_color = vec4(1.0, 0.0, 0.0, 0.8);
uniform float inner = 0.4;
uniform float opacity = 0.0;
uniform vec2 rect_size = vec2(1280.0, 720.0);
void fragment() {
	vec2 p = (UV - 0.5) * rect_size;
	float t = length(p) / length(rect_size * 0.5);
	float k = clamp((t - inner) / (1.0 - inner), 0.0, 1.0);
	COLOR = vec4(edge_color.rgb, edge_color.a * k * opacity);
}
"""

const BAR_SHADER := """
shader_type canvas_item;
uniform vec4 c0 : source_color;
uniform vec4 c1 : source_color;
uniform vec4 c2 : source_color;
uniform vec2 rect_size = vec2(180.0, 16.0);
uniform float radius = 6.0;
void fragment() {
	vec2 p = UV * rect_size;
	float r = min(radius, min(rect_size.x, rect_size.y) * 0.5);
	vec2 q = abs(p - rect_size * 0.5) - rect_size * 0.5 + r;
	float d = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
	vec4 col = UV.x < 0.5 ? mix(c0, c1, UV.x * 2.0) : mix(c1, c2, (UV.x - 0.5) * 2.0);
	COLOR = vec4(col.rgb, col.a * clamp(0.5 - d, 0.0, 1.0));
}
"""

var game # Game
var minimap: Minimap

var _font: SystemFont
var _font_bold: SystemFont
var _font_black: SystemFont
var _mono: SystemFont

var _flash: ColorRect
var _flash_mat: ShaderMaterial
var _flash_opacity := 0.0
var _flash_target := 0.0
var _flash_hold := 0.0
var _death: Control
var _info: RichTextLabel
var _info_values := {"mode": "FPS (WALK)", "mode_color": "#10b981", "pos": "0, 0, 0", "depth": "1", "obj": "0",
	"light": "0", "normalmap": true, "music": true, "gamepad": "None", "gamepad_on": false}
var _hp_fill: ColorRect
var _xp_fill: ColorRect
var _hp_target := 1.0
var _xp_target := 0.0
var _hp_cur := 1.0
var _xp_cur := 0.0
var _hp_text: Label
var _level_text: Label
var _kills_text: Label
var _gun_text: Label
var _loading: ColorRect
var _toast: PanelContainer
var _toast_label: Label
var _toast_timer := 0.0

# Menu
var _menu: PanelContainer
var _menu_dim: ColorRect
var _web_menu_font: FontFile
var _menu_original_fonts: Dictionary[Control, Font] = {}
var _scaled_fonts: Dictionary[Font, Font] = {}
var _font_title: FontVariation
var _font_heading: FontVariation
var _font_section: FontVariation
var _font_button: FontVariation
var _views: Dictionary = {}
var _current_view := "main"
var _prompt: Label
var _status: Label
var _btn_new: Button
var _btn_resume: Button
var _btn_generator: Button
var _btn_options: Button
var _btn_controls: Button
var _btn_webxr: Button # web build only: starts/ends a WebXR session
var _controls_flat: HBoxContainer
var _controls_vr: VBoxContainer
var _btn_generate: Button
var _btn_gen_back: Button
var _gen_size: HSlider
var _gen_size_val: Label
var _gen_seed: LineEdit
var _opt_normal: CheckButton
var _opt_music: CheckButton
var _opt_vibration: CheckButton
var _opt_invert: CheckButton
var _opt_hud: CheckButton
var _opt_god: CheckButton
var _opt_fly: CheckButton
var _opt_fullscreen: CheckButton
var _opt_tip: Label # keyboard shortcuts; hidden on the VR panel
var _opt_sens: HSlider
var _opt_sens_val: Label
var _btn_opt_back: Button
var _syncing := false


func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	_font = _sys_font(["Segoe UI", "Tahoma", "Geneva", "Verdana", "sans-serif"], 400)
	_font_bold = _sys_font(["Segoe UI", "Tahoma", "Geneva", "Verdana", "sans-serif"], 700)
	_font_black = _sys_font(["Segoe UI", "Tahoma", "Geneva", "Verdana", "sans-serif"], 800)
	_mono = _sys_font(["Consolas", "Courier New", "monospace"], 400)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_build_overlays(root)
	_build_minimap(root)
	_build_info(root)
	_build_hud(root)
	_build_loading(root)
	_build_menu(root)
	_collect_menu_fonts()
	if OS.has_feature("web"):
		_prepare_web_menu_font()
	_build_toast(root)
	get_viewport().size_changed.connect(_on_resize)
	_on_resize()


func _sys_font(names: Array, weight: int) -> SystemFont:
	var f := SystemFont.new()
	f.font_names = PackedStringArray(names)
	f.font_weight = weight
	var emoji := SystemFont.new()
	emoji.font_names = PackedStringArray(["Segoe UI Emoji", "Noto Color Emoji", "Apple Color Emoji"])
	f.fallbacks = [emoji]
	return f


static func _style(bg: Color, border: Color = Color(0, 0, 0, 0), border_w: int = 0, radius: int = 8,
		pad_h: float = 0.0, pad_v: float = 0.0, shadow: Color = Color(0, 0, 0, 0), shadow_size: int = 0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(border_w)
	s.set_corner_radius_all(radius)
	s.content_margin_left = pad_h
	s.content_margin_right = pad_h
	s.content_margin_top = pad_v
	s.content_margin_bottom = pad_v
	s.shadow_color = shadow
	s.shadow_size = shadow_size
	s.anti_aliasing = true
	return s


func _label(text: String, font: Font, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _on_resize() -> void:
	var vs := get_viewport().get_visible_rect().size
	_flash_mat.set_shader_parameter("rect_size", vs)
	_fit_hud()
	_fit_menu()


# ---------------------------------------------------------------- Overlays

func _vignette(root: Control, color: Color, inner: float) -> ShaderMaterial:
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = VIGNETTE_SHADER
	mat.shader = sh
	mat.set_shader_parameter("edge_color", color)
	mat.set_shader_parameter("inner", inner)
	rect.material = mat
	rect.visible = false # shown only while a flash is fading in/out
	root.add_child(rect)
	_flash = rect
	return mat


func _build_overlays(root: Control) -> void:
	_flash_mat = _vignette(root, Color(1, 0, 0, 0.8), 0.4)

	_death = ColorRect.new()
	(_death as ColorRect).color = Color(60 / 255.0, 0, 0, 0.7)
	_death.set_anchors_preset(Control.PRESET_FULL_RECT)
	_death.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_death.visible = false
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var big := _label("YOU DIED", _font_black, 56, Color("#fecaca"))
	big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var small := _label("Respawning at the dungeon entrance...", _font_bold, 16, Color("#fca5a5"))
	small.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(big)
	box.add_child(small)
	_death.add_child(box)
	box.anchor_left = 0.5
	box.anchor_right = 0.5
	box.anchor_top = 0.5
	box.anchor_bottom = 0.5
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	root.add_child(_death)

	# In VR aiming comes from the controllers, so a crosshair on the body-locked UI panel would be misleading.
	if game == null or game.xr_rig == null:
		var cross := Crosshair.new()
		cross.set_anchors_preset(Control.PRESET_CENTER)
		cross.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(cross)
		_hud_items.append(cross)


class Crosshair:
	extends Control

	func _draw() -> void:
		draw_circle(Vector2.ZERO, 5.0, Color(0, 0, 0, 0.5))
		draw_circle(Vector2.ZERO, 4.0, Color(1, 1, 1, 0.7))


func flash_screen(kind: String, opacity: float, hold_ms: float) -> void:
	# No damage flash; in VR every screen flash would show up as a tinted rectangle on the UI panel.
	if kind == "red" or game.xr_rig != null:
		return
	var color := Color(1, 0, 0, 0.8)
	var inner := 0.4
	match kind:
		"green":
			color = Color(34 / 255.0, 197 / 255.0, 94 / 255.0, 0.5)
			inner = 0.3
		"health":
			color = Color(34 / 255.0, 197 / 255.0, 94 / 255.0, 0.4)
		"xp":
			color = Color(234 / 255.0, 179 / 255.0, 8 / 255.0, 0.4)
	_flash_mat.set_shader_parameter("edge_color", color)
	_flash_mat.set_shader_parameter("inner", inner)
	_flash_target = opacity
	_flash_hold = hold_ms / 1000.0


func show_death_screen(show: bool) -> void:
	_death.visible = show


# ---------------------------------------------------------------- Minimap and info panel

func _build_minimap(root: Control) -> void:
	_minimap_box = Control.new()
	_minimap_box.name = "Minimap"
	_minimap_box.custom_minimum_size = Vector2(260, 260)
	_minimap_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_minimap_box.anchor_left = 1.0
	_minimap_box.anchor_right = 1.0
	_minimap_box.offset_left = -15 - 260
	_minimap_box.offset_right = -15
	_minimap_box.offset_top = 15
	_minimap_box.offset_bottom = 15 + 260
	root.add_child(_minimap_box)
	_hud_items.append(_minimap_box)
	var frame := Panel.new()
	frame.add_theme_stylebox_override("panel", _style(Color(10 / 255.0, 14 / 255.0, 23 / 255.0, 0.88), Color(0, 0, 0, 0), 0, 130,
		0, 0, Color(0, 0, 0, 0.8), 16))
	frame.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	_minimap_box.add_child(frame)
	minimap = Minimap.new()
	minimap.game = game
	minimap.set_anchors_preset(Control.PRESET_FULL_RECT)
	frame.add_child(minimap)
	var border := Panel.new()
	border.add_theme_stylebox_override("panel", _style(Color(0, 0, 0, 0), Color(245 / 255.0, 158 / 255.0, 11 / 255.0, 0.4), 2, 130))
	border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	border.set_anchors_preset(Control.PRESET_FULL_RECT)
	_minimap_box.add_child(border)


func update_minimap(pos: Vector3, camera: Camera3D) -> void:
	if not is_hud_visible():
		return
	minimap.update_minimap(pos, camera, get_process_delta_time())


func _build_info(root: Control) -> void:
	var panel := PanelContainer.new()
	panel.name = "DebugPanel"
	_info_panel = panel
	panel.add_theme_stylebox_override("panel", _style(Color(15 / 255.0, 23 / 255.0, 42 / 255.0, 0.85),
		Color(1, 1, 1, 0.1), 1, 8, 14, 10, Color(0, 0, 0, 0.5), 12))
	panel.position = Vector2(15, 15)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_info = RichTextLabel.new()
	_info.bbcode_enabled = true
	_info.fit_content = true
	_info.autowrap_mode = TextServer.AUTOWRAP_OFF
	_info.scroll_active = false
	_info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_info.add_theme_font_override("normal_font", _mono)
	_info.add_theme_font_override("bold_font", _sys_font(["Consolas", "Courier New", "monospace"], 700))
	_info.add_theme_font_size_override("normal_font_size", 13)
	_info.add_theme_font_size_override("bold_font_size", 13)
	_info.add_theme_color_override("default_color", Color("#d1d5db"))
	_info.add_theme_constant_override("line_separation", 4)
	panel.add_child(_info)
	root.add_child(panel)
	panel.visible = SHOW_DEBUG_PANEL
	if SHOW_DEBUG_PANEL:
		_hud_items.append(panel)
	_refresh_info()


func _refresh_info() -> void:
	if not SHOW_DEBUG_PANEL:
		return # the panel is never shown; skip rebuilding its BBCode (position updates 10x per second)
	var v := _info_values
	var nm_on: bool = v.normalmap
	var mu_on: bool = v.music
	var t := "[b][color=#f59e0b]Dungeon Stomp Godot - by Mark Longo Copyright 2001-%d[/color][/b]\n" % Time.get_date_dict_from_system().year
	t += "Mode: [color=%s]%s[/color]\n" % [v.mode_color, v.mode]
	t += "Position: %s\n" % v.pos
	t += "Depth: [color=#38bdf8]%s[/color] | Objects: %s | Lights: %s\n" % [v.depth, v.obj, v.light]
	t += "Normal Maps: [color=%s]%s[/color] (N) | Music: [color=%s]%s[/color] (P)\n" % [
		"#00ff88" if nm_on else "#ef4444", "ON" if nm_on else "OFF", "#00ff88" if mu_on else "#ef4444", "ON" if mu_on else "OFF"]
	t += "Gamepad: [color=%s]%s[/color]\n" % ["#00ff88" if v.gamepad_on else "#64748b", v.gamepad]
	t += "Controls: WASD / L-Stick (Move) | Space / A (Jump) | E / X (Open Door) | RT (Attack) | LB/RB (Weapon)"
	_info.text = t


func set_info(key: String, text: String) -> void:
	if _info_values.get(key) == text:
		return
	_info_values[key] = text
	if _info != null:
		_refresh_info()


func set_toggle_info(key: String, enabled: bool) -> void:
	_info_values[key] = enabled
	if _info != null:
		_refresh_info()


func set_mode_display(fly: bool) -> void:
	_info_values.mode = "FLY MODE" if fly else "FPS (WALK)"
	_info_values.mode_color = "#00ffff" if fly else "#00ff88"
	_refresh_info()


func set_gamepad_display(name: String, connected: bool) -> void:
	_info_values.gamepad = name
	_info_values.gamepad_on = connected
	_refresh_info()

# ---------------------------------------------------------------- Bottom HUD

const HUD_SCALE := 1.0 # size of the bottom HUD bar (1.0 = original size); raise it to make the HUD bigger

static func _hs(v: float) -> int:
	return roundi(v * HUD_SCALE)


func _badge(title: String, value: String, value_color: Color, value_size: int = 15, min_w: float = 60.0) -> Label:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _style(Color(30 / 255.0, 41 / 255.0, 59 / 255.0, 0.6), Color(1, 1, 1, 0.12),
		_hs(1), _hs(8), _hs(14), _hs(6)))
	panel.custom_minimum_size = Vector2(min_w * HUD_SCALE, 0)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 0)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var t := _label(title.to_upper(), _font_bold, _hs(10), Color("#64748b"))
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var v := _label(value, _font_black, _hs(value_size), value_color)
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(t)
	box.add_child(v)
	panel.add_child(box)
	_hud_row.add_child(panel)
	return v


var _hud_row: HBoxContainer
var _hud_panel: PanelContainer
var _minimap_box: Control
var _info_panel: PanelContainer
var _hud_items: Array[Control] = [] # everything the "Show Player HUD" option toggles
const BAR_W := 180.0 * HUD_SCALE
const BAR_H := 16.0 * HUD_SCALE

func _bar(title: String, right_text: String, right_color: Color, c0: Color, c1: Color, c2: Color) -> Array:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", _hs(4))
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := _label(title, _font_bold, _hs(11), Color("#94a3b8"))
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var r := _label(right_text, _font_bold, _hs(11), right_color)
	row.add_child(l)
	row.add_child(r)
	box.add_child(row)
	var track := Panel.new()
	track.custom_minimum_size = Vector2(BAR_W, BAR_H)
	track.add_theme_stylebox_override("panel", _style(Color(15 / 255.0, 23 / 255.0, 42 / 255.0, 0.8), Color(1, 1, 1, 0.15),
		_hs(1), _hs(8)))
	track.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fill := ColorRect.new()
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = BAR_SHADER
	mat.shader = sh
	mat.set_shader_parameter("c0", c0)
	mat.set_shader_parameter("c1", c1)
	mat.set_shader_parameter("c2", c2)
	fill.material = mat
	fill.position = Vector2(0, 0)
	fill.size = Vector2(BAR_W, BAR_H)
	track.add_child(fill)
	box.add_child(track)
	_hud_row.add_child(box)
	return [fill, r]


func _build_hud(root: Control) -> void:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _style(Color(15 / 255.0, 18 / 255.0, 26 / 255.0, 0.93),
		Color(1, 170 / 255.0, 0, 0.25), _hs(1), _hs(12), _hs(24), _hs(12), Color(0, 0, 0, 0.8), _hs(24)))
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 1.0
	panel.anchor_bottom = 1.0
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	panel.offset_bottom = -20
	panel.resized.connect(_fit_hud)
	_hud_panel = panel
	_hud_items.append(panel)
	_hud_row = HBoxContainer.new()
	_hud_row.add_theme_constant_override("separation", _hs(16))
	_hud_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_hud_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(_hud_row)
	root.add_child(panel)
	_level_text = _badge("Hero", "LVL 1", Color("#38bdf8"))
	var hp := _bar("HEALTH", "100 / 100", Color("#f87171"), Color("#dc2626"), Color("#ef4444"), Color("#f87171"))
	_hp_fill = hp[0]
	_hp_text = hp[1]
	var xp := _bar("EXP", "PROGRESS", Color("#94a3b8"), Color("#0284c7"), Color("#38bdf8"), Color("#7dd3fc"))
	_xp_fill = xp[0]
	_kills_text = _badge("KILLS", "0", Color("#f43f5e"))
	_gun_text = _badge("WEAPON", "AXE", AMBER, 13, 120)
	_set_fill(_hp_fill, _hp_cur)
	_set_fill(_xp_fill, _xp_cur)


# Keeps the HUD anchored bottom-centre and shrinks it if it would be wider than the screen. In VR the HUD has
# its own panel sized to fit it (see XRRig.attach_hud), so it is never shrunk there.
func _fit_hud() -> void:
	if _hud_panel == null:
		return
	if _hud_detached:
		_hud_panel.scale = Vector2.ONE
		return
	var vs := get_viewport().get_visible_rect().size
	var w := _hud_panel.size.x
	var s := minf(1.0, vs.x * 0.96 / w) if w > 0.0 else 1.0
	_hud_panel.pivot_offset = Vector2(w * 0.5, _hud_panel.size.y)
	_hud_panel.scale = Vector2(s, s)


var _hud_detached := false
var _detached_panels: Array[Dictionary] = [] # layout of each detached control, for restore_hud_panels

# The take_* functions move a HUD element out of the full-screen UI so VR can show it on its own panel.
func _detach(c: Control) -> Control:
	_detached_panels.append({
		"control": c, "parent": c.get_parent(), "index": c.get_index(),
		"anchors": [c.anchor_left, c.anchor_top, c.anchor_right, c.anchor_bottom],
		"offsets": [c.offset_left, c.offset_top, c.offset_right, c.offset_bottom],
		"scale": c.scale, "pivot": c.pivot_offset,
	})
	c.get_parent().remove_child(c)
	c.set_anchors_preset(Control.PRESET_TOP_LEFT)
	c.position = Vector2.ZERO
	c.scale = Vector2.ONE
	c.pivot_offset = Vector2.ZERO
	return c


func take_hud_panel() -> PanelContainer:
	_hud_detached = true
	return _detach(_hud_panel)


func take_minimap() -> Control:
	_detach(_minimap_box)
	_minimap_box.size = _minimap_box.custom_minimum_size
	return _minimap_box


func take_info_panel() -> PanelContainer:
	return _detach(_info_panel)


# Puts the detached HUD elements back into the full-screen UI (a WebXR session ended).
func restore_hud_panels() -> void:
	for panel in _detached_panels:
		var c: Control = panel.control
		c.get_parent().remove_child(c)
		var parent: Node = panel.parent
		parent.add_child(c)
		parent.move_child(c, mini(panel.index, parent.get_child_count() - 1))
		c.anchor_left = panel.anchors[0]
		c.anchor_top = panel.anchors[1]
		c.anchor_right = panel.anchors[2]
		c.anchor_bottom = panel.anchors[3]
		c.offset_right = panel.offsets[2]
		c.offset_bottom = panel.offsets[3]
		c.offset_left = panel.offsets[0]
		c.offset_top = panel.offsets[1]
		c.scale = panel.scale
		c.pivot_offset = panel.pivot
	_detached_panels.clear()
	_hud_detached = false
	_fit_hud()


# Reparents the UI between the desktop window and the XR rig's UI panel viewport.
func move_to_viewport(parent: Node) -> void:
	get_viewport().size_changed.disconnect(_on_resize)
	reparent(parent)
	get_viewport().size_changed.connect(_on_resize)
	_on_resize()


# Shows/hides every HUD element: bottom bar, minimap, info panel and crosshair.
func set_hud_visible(show: bool) -> void:
	for item: Control in _hud_items:
		item.visible = show


func is_hud_visible() -> bool:
	return _hud_panel.visible


func update_hud(stats: Dictionary, gun_text: String) -> void:
	var max_hp := maxf(1.0, float(stats.maxHealth))
	_hp_target = clampf(float(stats.health) / max_hp, 0.0, 1.0)
	_xp_target = clampf(float(stats.xp) / maxf(1.0, float(stats.nextXp)), 0.0, 1.0)
	_hp_text.text = "%d / %d" % [int(ceil(float(stats.health))), int(stats.maxHealth)]
	_level_text.text = "LVL %d" % int(stats.level)
	_kills_text.text = str(int(stats.kills))
	_gun_text.text = gun_text


func _build_loading(root: Control) -> void:
	_loading = ColorRect.new()
	_loading.color = Color(5 / 255.0, 7 / 255.0, 12 / 255.0, 0.92)
	_loading.set_anchors_preset(Control.PRESET_FULL_RECT)
	_loading.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_loading.visible = false
	var l := _label("LOADING DUNGEON...", _font_bold, 20, AMBER)
	l.set_anchors_preset(Control.PRESET_FULL_RECT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_loading.add_child(l)
	root.add_child(_loading)


func show_loading(show: bool) -> void:
	_loading.visible = show


func _build_toast(root: Control) -> void:
	_toast = PanelContainer.new()
	_toast.add_theme_stylebox_override("panel", _style(Color(15 / 255.0, 20 / 255.0, 30 / 255.0, 0.96),
		Color(245 / 255.0, 158 / 255.0, 11 / 255.0, 0.6), 1, 8, 20, 10, Color(0, 0, 0, 0.8), 24))
	_toast.anchor_left = 0.5
	_toast.anchor_right = 0.5
	_toast.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toast.offset_top = 24
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast.modulate.a = 0.0
	_toast.visible = false
	_toast_label = _label("", _font_bold, 14, AMBER)
	_toast.add_child(_toast_label)
	root.add_child(_toast)


func toast(message: String) -> void:
	_toast_label.text = message
	_toast_timer = 3.2


func _process(delta: float) -> void:
	# Each element is only touched while it is changing, so an idle HUD doesn't redraw every frame.
	# Damage / pickup flash (opacity transition 0.15 s ease-out)
	if _flash_hold > 0.0:
		_flash_hold -= delta
		if _flash_hold <= 0.0:
			_flash_target = 0.0
	if _flash_opacity != _flash_target:
		_flash_opacity = move_toward(_flash_opacity, _flash_target, delta / 0.15)
		_flash_mat.set_shader_parameter("opacity", _flash_opacity)
		_flash.visible = _flash_opacity > 0.0
	# Bars ease towards their targets (CSS width transition 0.2 s)
	_hp_cur = _ease_fill(_hp_fill, _hp_cur, _hp_target, delta)
	_xp_cur = _ease_fill(_xp_fill, _xp_cur, _xp_target, delta)
	# Toast slide in/out
	var a := _toast.modulate.a
	if _toast_timer > 0.0:
		_toast_timer -= delta
		a = move_toward(a, 1.0, delta / 0.3)
	else:
		a = move_toward(a, 0.0, delta / 0.3)
	if a != _toast.modulate.a:
		_toast.modulate.a = a
		_toast.offset_top = lerpf(-36.0, 24.0, a)
		_toast.visible = a > 0.0


func _ease_fill(fill: ColorRect, cur: float, target: float, delta: float) -> float:
	if cur == target:
		return cur
	cur = lerpf(cur, target, minf(1.0, delta * 12.0))
	if absf(cur - target) < 0.001:
		cur = target
	_set_fill(fill, cur)
	return cur


# True while the full-screen UI layer has something to draw (VR hides its world-space panel otherwise).
func has_screen_content() -> bool:
	return _menu.visible or _loading.visible or _death.visible or _toast.visible or _flash.visible


func _set_fill(fill: ColorRect, pct: float) -> void:
	var w := BAR_W * pct
	fill.size = Vector2(w, BAR_H)
	fill.visible = w > 0.5
	(fill.material as ShaderMaterial).set_shader_parameter("rect_size", Vector2(maxf(w, 1.0), BAR_H))


# ---------------------------------------------------------------- Menu

const GOLD := Color("#fbbf24")
const TEXT := Color("#e2e8f0")
const MUTED := Color("#94a3b8")
const DESKTOP_MENU_SCALE := 1.6 # desktop: the layout is authored for the 1280x720 VR canvas, so enlarge it on the 4K canvas
const SWITCH_SIZE := Vector2(46, 24)
const KNOB_SIZE := 18.0

const KEYBOARD_CONTROLS := [["WASD", "Move"], ["Mouse", "Look"], ["Left Click", "Attack / Cast"],
	["Shift", "Sprint"], ["Space", "Jump"], ["E", "Open Door / Chest"], ["Q / Z", "Switch Weapon"],
	["F", "Fly Mode"], ["G", "Regenerate Dungeon"], ["H", "Toggle HUD"], ["Esc", "Menu"]]
const GAMEPAD_CONTROLS := [["L-Stick", "Move (L3 Sprint)"], ["R-Stick", "Look (R3 Level)"], ["RT", "Attack / Cast"],
	["A", "Jump / Confirm"], ["X", "Open Door / Chest"], ["LB / RB", "Switch Weapon"], ["LT", "Sprint"],
	["Start", "Menu"]]
const VR_CONTROLS := [["L-Stick", "Move (click to Sprint)"], ["R-Stick", "Turn"], ["Swing", "Melee Attack"],
	["R-Trigger", "Cast Spell / Select"], ["A", "Jump"], ["B", "Open Door / Chest / Back"], ["X / Y", "Switch Weapon"],
	["L-Trigger / Menu", "Menu"]]


# Vector divider (line - diamond - line); drawn rather than typed so it renders identically on every platform.
class Ornament:
	extends Control
	var color := Color("#f59e0b")

	func _init(width: float = 300.0) -> void:
		custom_minimum_size = Vector2(width, 12)
		size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := size * 0.5
		var faded := Color(color, 0.0)
		var gap := 16.0
		for side in [-1.0, 1.0]:
			var a := Vector2(c.x + side * gap, c.y)
			var b := Vector2(c.x + side * c.x, c.y)
			draw_polygon(PackedVector2Array([a + Vector2(0, -0.75), b + Vector2(0, -0.75), b + Vector2(0, 0.75), a + Vector2(0, 0.75)]),
				PackedColorArray([color, faded, faded, color]))
			_diamond(Vector2(c.x + side * 10.0, c.y), 2.5, Color(color, 0.7))
		_diamond(c, 5.5, color)

	func _diamond(p: Vector2, r: float, col: Color) -> void:
		draw_colored_polygon(PackedVector2Array([p + Vector2(0, -r), p + Vector2(r, 0), p + Vector2(0, r), p + Vector2(-r, 0)]), col)


# Crossed swords drawn with primitives (replaces the emoji, which the web build's font can't render).
class SwordsEmblem:
	extends Control

	func _init() -> void:
		custom_minimum_size = Vector2(44, 44)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		for angle in [-PI / 4.0, PI / 4.0]:
			draw_set_transform(size * 0.5, angle, Vector2.ONE * size.y / 52.0)
			draw_colored_polygon(PackedVector2Array([Vector2(-2.6, 8), Vector2(-2.6, -18), Vector2(0, -25),
				Vector2(2.6, -18), Vector2(2.6, 8)]), Color("#e2e8f0"))
			draw_line(Vector2(0, 6), Vector2(0, -19), Color("#94a3b8"), 1.0)
			draw_rect(Rect2(-9, 8, 18, 3.5), Color("#f59e0b"))
			draw_rect(Rect2(-1.6, 11.5, 3.2, 8.5), Color("#92400e"))
			draw_circle(Vector2(0, 22), 2.8, Color("#fbbf24"))
		draw_set_transform_matrix(Transform2D.IDENTITY)


# Full-width option row with an animated on/off switch on the right.
class MenuToggle:
	extends CheckButton
	var _knob := 0.0

	func _init() -> void:
		var blank := ImageTexture.create_from_image(Image.create_empty(int(SWITCH_SIZE.x), int(SWITCH_SIZE.y), false,
			Image.FORMAT_RGBA8)) # transparent; reserves the switch area, the switch itself is drawn in _draw
		for k in ["checked", "unchecked", "checked_disabled", "unchecked_disabled", "checked_mirrored",
				"unchecked_mirrored", "checked_disabled_mirrored", "unchecked_disabled_mirrored"]:
			add_theme_icon_override(k, blank)

	func _process(delta: float) -> void:
		var target := 1.0 if button_pressed else 0.0
		if _knob != target:
			_knob = move_toward(_knob, target, delta * 8.0) if is_visible_in_tree() else target
			queue_redraw()

	func _draw() -> void:
		var sb := get_theme_stylebox("normal")
		var r := Rect2(Vector2(size.x - SWITCH_SIZE.x - sb.content_margin_right, (size.y - SWITCH_SIZE.y) * 0.5), SWITCH_SIZE)
		var track := StyleBoxFlat.new()
		track.set_corner_radius_all(int(SWITCH_SIZE.y * 0.5))
		track.anti_aliasing = true
		track.bg_color = Color(1, 1, 1, 0.14).lerp(Color("#f59e0b"), _knob)
		track.border_color = Color(1, 1, 1, 0.22).lerp(Color("#fbbf24"), _knob)
		track.set_border_width_all(1)
		draw_style_box(track, r)
		var pad := (SWITCH_SIZE.y - KNOB_SIZE) * 0.5
		var x := lerpf(r.position.x + pad + KNOB_SIZE * 0.5, r.end.x - pad - KNOB_SIZE * 0.5, _knob)
		var y := r.position.y + SWITCH_SIZE.y * 0.5
		draw_circle(Vector2(x, y + 1.0), KNOB_SIZE * 0.5, Color(0, 0, 0, 0.35))
		draw_circle(Vector2(x, y), KNOB_SIZE * 0.5, Color("#f8fafc") if _knob > 0.5 else Color("#cbd5e1"))


# Slider with a drawn knob (the default grabber icon is a small bitmap that blurs when the menu is enlarged).
class MenuSlider:
	extends HSlider

	func _init() -> void:
		var blank := ImageTexture.create_from_image(Image.create_empty(int(KNOB_SIZE), int(KNOB_SIZE), false, Image.FORMAT_RGBA8))
		for k in ["grabber", "grabber_highlight", "grabber_disabled"]:
			add_theme_icon_override(k, blank)
		value_changed.connect(func(_v: float): queue_redraw())
		focus_entered.connect(queue_redraw)
		focus_exited.connect(queue_redraw)

	func _draw() -> void:
		var ratio := 0.0 if max_value <= min_value else (value - min_value) / (max_value - min_value)
		var p := Vector2(KNOB_SIZE * 0.5 + ratio * (size.x - KNOB_SIZE), size.y * 0.5)
		if has_focus():
			draw_circle(p, KNOB_SIZE * 0.5 + 5.0, Color(245 / 255.0, 158 / 255.0, 11 / 255.0, 0.3))
		draw_circle(p + Vector2(0, 1), KNOB_SIZE * 0.5, Color(0, 0, 0, 0.35))
		draw_circle(p, KNOB_SIZE * 0.5, Color("#fbbf24"))
		draw_circle(p, KNOB_SIZE * 0.2, Color("#78350f"))


func _collect_menu_fonts() -> void:
	for control: Control in _menu.find_children("*", "Control", true, false):
		if control.has_theme_font_override("font"):
			_menu_original_fonts[control] = control.get_theme_font("font")


func _prepare_web_menu_font() -> void:
	# Web SystemFont uses the engine fallback; copy its vector data, not the shared VR font, and render it as
	# MSDF so the WEB_MENU_SCALE-enlarged menu stays sharp.
	_web_menu_font = ThemeDB.fallback_font.duplicate() as FontFile
	assert(_web_menu_font != null, "The engine fallback must be a vector FontFile")
	_web_menu_font.multichannel_signed_distance_field = true
	for control: Control in _menu_original_fonts: # release any previously applied scaled fonts first
		control.add_theme_font_override("font", _menu_original_fonts[control])
	_scaled_fonts.clear()
	_fit_menu()


# MSDF counterpart of a menu font, used while the menu is enlarged with Control.scale (which would blur bitmap glyphs).
# On the web every weight maps to the (semibold) engine fallback font; embolden would add artifacts to MSDF glyphs.
func _scaled_font(f: Font) -> Font:
	if _scaled_fonts.has(f):
		return _scaled_fonts[f]
	var out: Font
	if f is FontVariation:
		var v := (f as FontVariation).duplicate() as FontVariation
		v.base_font = _scaled_font(v.base_font)
		out = v
	elif _web_menu_font != null:
		out = _web_menu_font
	else:
		var d := f.duplicate() as Font
		d.set("multichannel_signed_distance_field", true)
		out = d
	_scaled_fonts[f] = out
	return out


# Enlarges the menu on a flat screen (clamped to fit, MSDF fonts) and keeps it 1:1 on the VR panel; also swaps
# the platform-specific parts of the menu when the UI moves between the screen and the VR panel.
func _fit_menu() -> void:
	if _menu == null:
		return
	var in_vr := get_viewport() is SubViewport
	if _controls_flat != null:
		_controls_flat.visible = not in_vr
		_controls_vr.visible = in_vr
		_opt_fullscreen.visible = not in_vr
		_opt_tip.visible = not in_vr
	if _menu_dim != null:
		_menu_dim.visible = _menu.visible and not in_vr
	var scaled := not in_vr and not _menu_original_fonts.is_empty()
	var s := 1.0
	if scaled:
		s = WEB_MENU_SCALE if _web_menu_font != null else DESKTOP_MENU_SCALE
		var vs := get_viewport().get_visible_rect().size
		if _menu.size.x > 0.0 and _menu.size.y > 0.0:
			s = minf(s, minf(vs.x * 0.95 / _menu.size.x, vs.y * 0.92 / _menu.size.y))
	_menu.pivot_offset = _menu.size * 0.5
	_menu.scale = Vector2.ONE * s
	for control: Control in _menu_original_fonts:
		var original: Font = _menu_original_fonts[control]
		var font: Font = _scaled_font(original) if scaled else original
		if control.get_theme_font("font") != font:
			control.add_theme_font_override("font", font)


# Re-centres the panel on its new minimum size after a view switch (a Control never shrinks on its own).
func _recenter_menu() -> void:
	_menu.offset_left = 0
	_menu.offset_right = 0
	_menu.offset_top = 0
	_menu.offset_bottom = 0


func _spaced_font(base: Font, spacing: int) -> FontVariation:
	var v := FontVariation.new()
	v.base_font = base
	v.spacing_glyph = spacing
	return v


func _menu_button(text: String, primary: bool = false) -> Button:
	var b := Button.new()
	b.text = text.to_upper()
	b.add_theme_font_override("font", _font_button)
	b.add_theme_font_size_override("font_size", 17)
	b.custom_minimum_size.y = 46
	b.focus_mode = Control.FOCUS_ALL
	var normal: StyleBoxFlat
	var hover: StyleBoxFlat
	var pressed: StyleBoxFlat
	if primary:
		normal = _style(Color("#e8920a"), GOLD, 1, 8, 18, 10, Color(245 / 255.0, 158 / 255.0, 11 / 255.0, 0.3), 10)
		hover = _style(Color("#f6a623"), Color("#fde68a"), 1, 8, 18, 10, Color(245 / 255.0, 158 / 255.0, 11 / 255.0, 0.55), 16)
		pressed = _style(Color("#c97a06"), GOLD, 1, 8, 18, 10)
		for k in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color",
				"font_disabled_color"]:
			b.add_theme_color_override(k, Color("#1c1208"))
	else:
		normal = _style(Color(1, 1, 1, 0.045), Color(1, 1, 1, 0.12), 1, 8, 18, 10)
		hover = _style(Color(245 / 255.0, 158 / 255.0, 11 / 255.0, 0.16), AMBER, 1, 8, 18, 10, Color(245 / 255.0, 158 / 255.0, 11 / 255.0, 0.22), 10)
		hover.border_width_left = 4
		pressed = _style(Color(245 / 255.0, 158 / 255.0, 11 / 255.0, 0.28), GOLD, 1, 8, 18, 10)
		pressed.border_width_left = 4
		b.add_theme_color_override("font_color", TEXT)
		b.add_theme_color_override("font_hover_color", Color.WHITE)
		b.add_theme_color_override("font_focus_color", GOLD)
		b.add_theme_color_override("font_pressed_color", Color.WHITE)
		b.add_theme_color_override("font_hover_pressed_color", Color.WHITE)
		b.add_theme_color_override("font_disabled_color", Color(226 / 255.0, 232 / 255.0, 240 / 255.0, 0.3))
	var disabled := normal.duplicate() as StyleBoxFlat
	disabled.bg_color.a *= 0.4
	disabled.border_color = Color(1, 1, 1, 0.06)
	disabled.shadow_size = 0
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("hover_pressed", pressed)
	b.add_theme_stylebox_override("disabled", disabled)
	b.add_theme_stylebox_override("focus", _focus_ring(8))
	return b


func _focus_ring(radius: int) -> StyleBoxFlat:
	var focus := _style(Color(0, 0, 0, 0), GOLD, 2, radius)
	focus.set_expand_margin_all(3)
	focus.shadow_color = Color(245 / 255.0, 158 / 255.0, 11 / 255.0, 0.6)
	focus.shadow_size = 8
	return focus


func _tip(text: String) -> Label:
	var l := _label(text, _font, 14, MUTED)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func _field_label(text: String, value: String) -> Array:
	var row := HBoxContainer.new()
	var l := _label(text, _font, 17, TEXT)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := _label(value, _font_bold, 17, GOLD)
	row.add_child(l)
	row.add_child(v)
	return [row, v]


func _toggle(text: String) -> CheckButton:
	var c := MenuToggle.new()
	c.text = text
	c.add_theme_font_override("font", _font)
	c.add_theme_font_size_override("font_size", 17)
	c.custom_minimum_size = Vector2(300, 44)
	c.focus_mode = Control.FOCUS_ALL
	c.add_theme_color_override("font_color", TEXT)
	c.add_theme_color_override("font_hover_color", Color.WHITE)
	c.add_theme_color_override("font_focus_color", GOLD)
	c.add_theme_color_override("font_pressed_color", TEXT)
	c.add_theme_color_override("font_hover_pressed_color", Color.WHITE)
	var normal := _style(Color(1, 1, 1, 0.035), Color(1, 1, 1, 0.07), 1, 8, 14, 6)
	var hover := _style(Color(245 / 255.0, 158 / 255.0, 11 / 255.0, 0.12), Color(245 / 255.0, 158 / 255.0, 11 / 255.0, 0.55), 1, 8, 14, 6)
	c.add_theme_stylebox_override("normal", normal)
	c.add_theme_stylebox_override("pressed", normal)
	c.add_theme_stylebox_override("hover", hover)
	c.add_theme_stylebox_override("hover_pressed", hover)
	c.add_theme_stylebox_override("focus", _focus_ring(8))
	return c


func _slider(min_v: float, max_v: float, step: float) -> HSlider:
	var s := MenuSlider.new()
	s.min_value = min_v
	s.max_value = max_v
	s.step = step
	s.custom_minimum_size = Vector2(0, 26)
	s.focus_mode = Control.FOCUS_ALL
	s.add_theme_stylebox_override("grabber_area", _style(AMBER, Color(0, 0, 0, 0), 0, 3, 0, 3))
	s.add_theme_stylebox_override("grabber_area_highlight", _style(GOLD, Color(0, 0, 0, 0), 0, 3, 0, 3))
	s.add_theme_stylebox_override("slider", _style(Color(1, 1, 1, 0.14), Color(0, 0, 0, 0), 0, 3, 0, 3))
	s.add_theme_stylebox_override("focus", StyleBoxEmpty.new()) # MenuSlider draws a halo around the knob instead
	return s


# Card holding one group of settings; a slider block is laid out like a toggle row.
func _section(title: String) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	var l := _label(title.to_upper(), _font_section, 13, AMBER)
	head.add_child(l)
	var line := ColorRect.new()
	line.color = Color(245 / 255.0, 158 / 255.0, 11 / 255.0, 0.25)
	line.custom_minimum_size = Vector2(0, 1)
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(line)
	box.add_child(head)
	return box


func _slider_block(field: Array, slider: HSlider) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _style(Color(1, 1, 1, 0.035), Color(1, 1, 1, 0.07), 1, 8, 14, 8))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	box.add_child(field[0])
	box.add_child(slider)
	panel.add_child(box)
	return panel


func _view_header(text: String) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	var l := _label(text.to_upper(), _font_heading, 22, GOLD)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(l)
	box.add_child(Ornament.new(220.0))
	return box


func _key_chip(key: String) -> PanelContainer:
	var chip := PanelContainer.new()
	var sb := _style(Color(1, 1, 1, 0.08), Color(1, 1, 1, 0.22), 1, 5, 8, 2)
	sb.border_width_bottom = 3
	chip.add_theme_stylebox_override("panel", sb)
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := _label(key, _font_bold, 13, Color.WHITE)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	chip.add_child(l)
	return chip


func _controls_list(title: String, rows: Array, key_width: float) -> VBoxContainer:
	var section := _section(title)
	for entry: Array in rows:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var key_box := HBoxContainer.new()
		key_box.custom_minimum_size.x = key_width
		key_box.alignment = BoxContainer.ALIGNMENT_END
		key_box.add_child(_key_chip(entry[0]))
		row.add_child(key_box)
		var action := _label(entry[1], _font, 15, TEXT)
		action.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(action)
		section.add_child(row)
	return section


func _build_menu(root: Control) -> void:
	_font_title = _spaced_font(_font_black, 4)
	_font_heading = _spaced_font(_font_black, 3)
	_font_section = _spaced_font(_font_black, 2)
	_font_button = _spaced_font(_font_bold, 1)

	_menu_dim = ColorRect.new()
	_menu_dim.color = Color(2 / 255.0, 3 / 255.0, 8 / 255.0, 0.55)
	_menu_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_menu_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_menu_dim)

	_menu = PanelContainer.new()
	var panel_style := _style(Color(9 / 255.0, 11 / 255.0, 18 / 255.0, 0.96), Color(245 / 255.0, 158 / 255.0, 11 / 255.0, 0.35),
		1, 14, 36, 26, Color(0, 0, 0, 0.85), 48)
	panel_style.border_width_top = 3
	panel_style.border_color = Color(245 / 255.0, 158 / 255.0, 11 / 255.0, 0.45)
	_menu.add_theme_stylebox_override("panel", panel_style)
	_menu.custom_minimum_size = Vector2(520, 0)
	_menu.anchor_left = 0.5
	_menu.anchor_right = 0.5
	_menu.anchor_top = 0.5
	_menu.anchor_bottom = 0.5
	_menu.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_menu.grow_vertical = Control.GROW_DIRECTION_BOTH
	_menu.mouse_filter = Control.MOUSE_FILTER_STOP
	_menu.gui_input.connect(_on_menu_gui_input)
	_menu.resized.connect(_fit_menu)
	root.add_child(_menu)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 14)
	_menu.add_child(outer)

	var brand := VBoxContainer.new()
	brand.add_theme_constant_override("separation", 4)
	var title_row := HBoxContainer.new()
	title_row.alignment = BoxContainer.ALIGNMENT_CENTER
	title_row.add_theme_constant_override("separation", 14)
	var title := _label("DUNGEON STOMP", _font_title, 38, AMBER)
	title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	title.add_theme_constant_override("shadow_offset_y", 3)
	title_row.add_child(SwordsEmblem.new())
	title_row.add_child(title)
	title_row.add_child(SwordsEmblem.new())
	brand.add_child(title_row)
	brand.add_child(Ornament.new(340.0))
	var credit := _label("Created by Mark Longo  ·  © 2001-%d" % Time.get_date_dict_from_system().year, _font, 13, MUTED)
	credit.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	brand.add_child(credit)
	outer.add_child(brand)

	# Main view
	var main := VBoxContainer.new()
	main.add_theme_constant_override("separation", 9)
	_prompt = _label("Loading dungeon...", _font, 16, Color("#cbd5e1"))
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	main.add_child(_prompt)
	_btn_new = _menu_button("New Game", true)
	_btn_resume = _menu_button("Resume")
	_btn_resume.disabled = true
	_btn_generator = _menu_button("Dungeon Generator")
	_btn_options = _menu_button("Options")
	_btn_controls = _menu_button("Controls")
	for b in [_btn_new, _btn_resume, _btn_generator, _btn_options, _btn_controls]:
		main.add_child(b)
	if OS.has_feature("web"):
		# Enters a WebXR session, and becomes "Exit VR" while one is running (a browser tab can't be quit).
		_btn_webxr = _menu_button("Checking VR support...")
		_btn_webxr.disabled = true
		_btn_webxr.pressed.connect(func(): game.toggle_webxr())
		main.add_child(_btn_webxr)
	var exit_button := _menu_button("Exit Game")
	exit_button.pressed.connect(func(): game.quit_game())
	exit_button.visible = not OS.has_feature("web")
	main.add_child(exit_button)
	_status = _label("", _font, 16, Color("#38bdf8"))
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	main.add_child(_status)
	main.add_child(_tip("Find the glowing exit portal to descend. Every level is tougher."))
	outer.add_child(main)
	_views["main"] = main

	# Generator view
	var gen := VBoxContainer.new()
	gen.add_theme_constant_override("separation", 12)
	gen.add_child(_view_header("Dungeon Generator"))
	var layout := _section("Layout")
	var size_row := _field_label("Rooms / Objects", "225")
	_gen_size_val = size_row[1]
	_gen_size = _slider(150, 600, 25)
	_gen_size.value = 225
	_gen_size.value_changed.connect(func(v: float): _gen_size_val.text = str(int(v)))
	layout.add_child(_slider_block(size_row, _gen_size))
	var seed_box := VBoxContainer.new()
	seed_box.add_theme_constant_override("separation", 6)
	var seed_row := _field_label("Seed", "optional")
	(seed_row[1] as Label).add_theme_color_override("font_color", MUTED)
	seed_box.add_child(seed_row[0])
	_gen_seed = LineEdit.new()
	_gen_seed.placeholder_text = "Leave empty for random"
	_gen_seed.max_length = 32
	_gen_seed.add_theme_font_override("font", _font)
	_gen_seed.add_theme_font_size_override("font_size", 17)
	_gen_seed.add_theme_color_override("font_color", TEXT)
	_gen_seed.add_theme_color_override("font_placeholder_color", Color(148 / 255.0, 163 / 255.0, 184 / 255.0, 0.6))
	_gen_seed.add_theme_color_override("caret_color", GOLD)
	_gen_seed.add_theme_stylebox_override("normal", _style(Color(0, 0, 0, 0.35), Color(1, 1, 1, 0.15), 1, 6, 12, 9))
	_gen_seed.add_theme_stylebox_override("focus", _focus_ring(6))
	seed_box.add_child(_gen_seed)
	var seed_panel := PanelContainer.new()
	seed_panel.add_theme_stylebox_override("panel", _style(Color(1, 1, 1, 0.035), Color(1, 1, 1, 0.07), 1, 8, 14, 10))
	seed_panel.add_child(seed_box)
	layout.add_child(seed_panel)
	gen.add_child(layout)
	var gen_buttons := HBoxContainer.new()
	gen_buttons.add_theme_constant_override("separation", 10)
	_btn_gen_back = _menu_button("Back")
	_btn_generate = _menu_button("Generate Dungeon", true)
	_btn_gen_back.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_btn_generate.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_btn_generate.size_flags_stretch_ratio = 1.6
	gen_buttons.add_child(_btn_gen_back)
	gen_buttons.add_child(_btn_generate)
	gen.add_child(gen_buttons)
	outer.add_child(gen)
	_views["generator"] = gen

	# Options view: two columns of grouped settings
	var opts := VBoxContainer.new()
	opts.add_theme_constant_override("separation", 14)
	opts.add_child(_view_header("Options"))
	_opt_normal = _toggle("Normal Maps")
	_opt_hud = _toggle("Player HUD")
	_opt_fullscreen = _toggle("Fullscreen")
	_opt_music = _toggle("Music")
	_opt_vibration = _toggle("Controller Vibration")
	_opt_invert = _toggle("Invert Look Y")
	_opt_god = _toggle("God Mode")
	_opt_fly = _toggle("Fly Mode")
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 22)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 14)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var right := left.duplicate() as VBoxContainer
	var video := _section("Video")
	for c in [_opt_normal, _opt_hud, _opt_fullscreen]:
		video.add_child(c)
	var sound := _section("Audio")
	sound.add_child(_opt_music)
	left.add_child(video)
	left.add_child(sound)
	var input := _section("Controller")
	input.add_child(_opt_vibration)
	input.add_child(_opt_invert)
	var sens_row := _field_label("Look Sensitivity", "2.8")
	_opt_sens_val = sens_row[1]
	_opt_sens = _slider(1.0, 5.0, 0.2)
	_opt_sens.value = 2.8
	input.add_child(_slider_block(sens_row, _opt_sens))
	var cheats := _section("Cheats")
	cheats.add_child(_opt_god)
	cheats.add_child(_opt_fly)
	right.add_child(input)
	right.add_child(cheats)
	columns.add_child(left)
	columns.add_child(right)
	opts.add_child(columns)
	_opt_tip = _tip("Shortcuts: N normal maps  ·  P / M music  ·  H HUD  ·  F fly")
	opts.add_child(_opt_tip)
	_btn_opt_back = _menu_button("Back")
	opts.add_child(_btn_opt_back)
	outer.add_child(opts)
	_views["options"] = opts

	# Controls view: keyboard + gamepad on a flat screen, controller bindings on the VR panel (see _fit_menu)
	var ctrl := VBoxContainer.new()
	ctrl.add_theme_constant_override("separation", 14)
	ctrl.add_child(_view_header("Controls"))
	_controls_flat = HBoxContainer.new()
	_controls_flat.add_theme_constant_override("separation", 28)
	_controls_flat.add_child(_controls_list("Keyboard & Mouse", KEYBOARD_CONTROLS, 92))
	_controls_flat.add_child(_controls_list("Gamepad", GAMEPAD_CONTROLS, 82))
	ctrl.add_child(_controls_flat)
	_controls_vr = _controls_list("VR Controllers", VR_CONTROLS, 120)
	_controls_vr.visible = false
	ctrl.add_child(_controls_vr)
	var ctrl_back := _menu_button("Back")
	ctrl_back.pressed.connect(_on_back)
	ctrl.add_child(ctrl_back)
	outer.add_child(ctrl)
	_views["controls"] = ctrl

	_btn_new.pressed.connect(_on_new_game)
	_btn_resume.pressed.connect(click_resume)
	_btn_generator.pressed.connect(_on_open_generator)
	_btn_options.pressed.connect(_on_open_options)
	_btn_controls.pressed.connect(func():
		_click_sound()
		show_menu_view("controls"))
	_btn_generate.pressed.connect(_on_generate)
	_btn_gen_back.pressed.connect(_on_back)
	_btn_opt_back.pressed.connect(_on_back)
	_opt_fullscreen.toggled.connect(_on_fullscreen)
	_opt_god.toggled.connect(func(on: bool):
		if on != game.is_invincible:
			game.toggle_god_mode())
	_opt_fly.toggled.connect(func(on: bool): game.toggle_fly_mode(on))
	_opt_normal.toggled.connect(func(on: bool):
		if not _syncing:
			game.set_normal_maps_enabled(on)
			game.save_game_options())
	_opt_music.toggled.connect(func(on: bool):
		if _syncing or on == game.audio.is_music_on():
			return
		var enabled: bool = game.audio.toggle_music()
		set_toggle_info("music", enabled)
		if enabled:
			game.audio.start_next_music_track()
		game.save_game_options())
	_opt_vibration.toggled.connect(func(on: bool):
		if not _syncing:
			game.gamepad.vibration_enabled = on
			game.save_game_options())
	_opt_invert.toggled.connect(func(on: bool):
		if not _syncing:
			game.gamepad.invert_y = on
			game.save_game_options())
	_opt_hud.toggled.connect(func(on: bool):
		if not _syncing:
			set_hud_visible(on)
			game.save_game_options())
	_opt_sens.value_changed.connect(func(v: float):
		_opt_sens_val.text = "%.1f" % v
		if not _syncing:
			game.gamepad.set_sensitivity(v)
			game.save_game_options())
	show_menu_view("main")


func _click_sound() -> void:
	game.audio.play_sound("buttonselect111.wav", 0.5)


func _on_menu_gui_input(event: InputEvent) -> void:
	# Clicking the menu panel (not a button) enters the dungeon, like the browser version.
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if _current_view == "main" and (game.world_ready or resume_enabled()):
			game.start_game_session()


func _on_new_game() -> void:
	_click_sound()
	if not game.world_ready:
		return
	_btn_new.disabled = true
	await game.new_game()
	_btn_new.disabled = false


func click_resume() -> void:
	if _btn_resume.disabled or not game.world_ready:
		return
	game.start_game_session()
	_click_sound()


func _on_open_generator() -> void:
	_click_sound()
	show_menu_view("generator")
	_gen_size.value = int(game.gen_options.get("numObjectsToPlace", 225))
	var s = game.gen_options.get("seed")
	_gen_seed.text = "" if s == null else str(s)


func _on_open_options() -> void:
	_click_sound()
	show_menu_view("options")
	sync_options()


func _on_generate() -> void:
	_click_sound()
	if not game.world_ready:
		return
	_btn_generate.disabled = true
	await game.generate_from_menu(int(_gen_size.value), _gen_seed.text.strip_edges())
	_btn_generate.disabled = false


func _on_back() -> void:
	_click_sound()
	show_menu_view("main")


func _on_fullscreen(on: bool) -> void:
	if _syncing:
		return
	_click_sound()
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if on else DisplayServer.WINDOW_MODE_WINDOWED)


func _sync_fullscreen_toggle() -> void:
	var was_syncing := _syncing
	_syncing = true
	_opt_fullscreen.button_pressed = DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	_syncing = was_syncing


func sync_options() -> void:
	_syncing = true
	_opt_god.set_pressed_no_signal(game.is_invincible)
	_opt_fly.set_pressed_no_signal(game.fly_mode)
	_opt_normal.button_pressed = game.normal_maps_enabled
	_opt_music.button_pressed = game.audio.is_music_on()
	_opt_vibration.button_pressed = game.gamepad.vibration_enabled
	_opt_invert.button_pressed = game.gamepad.invert_y
	_opt_hud.button_pressed = is_hud_visible()
	_opt_sens.value = game.gamepad.sensitivity
	_opt_sens_val.text = "%.1f" % game.gamepad.sensitivity
	_syncing = false
	set_toggle_info("music", game.audio.is_music_on())
	set_toggle_info("normalmap", game.normal_maps_enabled)
	_sync_fullscreen_toggle()


func show_menu_view(view: String) -> void:
	if not _views.has(view):
		return
	_current_view = view
	for k in _views:
		(_views[k] as Control).visible = k == view
	if _status != null:
		set_status("")
	if view == "options":
		_sync_fullscreen_toggle()
	_recenter_menu.call_deferred()


func show_menu(show: bool) -> void:
	_menu.visible = show
	_menu_dim.visible = show and not get_viewport() is SubViewport
	if not show:
		var f := get_viewport().gui_get_focus_owner()
		if f != null:
			f.release_focus()


func is_menu_visible() -> bool:
	return _menu != null and _menu.visible


func set_prompt(text: String) -> void:
	_prompt.text = text


# Web build only: updates the main menu's VR button (no-op elsewhere, where the button doesn't exist).
func set_webxr_state(text: String, enabled: bool, show: bool = true) -> void:
	if _btn_webxr != null:
		_btn_webxr.text = text.to_upper()
		_btn_webxr.disabled = not enabled
		_btn_webxr.visible = show


func set_status(text: String) -> void:
	_status.text = text
	_status.visible = text != ""
	_recenter_menu.call_deferred()


func set_resume_enabled(enabled: bool) -> void:
	_btn_resume.disabled = not enabled


func resume_enabled() -> bool:
	return not _btn_resume.disabled


# Escape / gamepad B: go back from a sub-menu, or resume from the main menu.
func on_back_or_resume() -> void:
	if _current_view != "main":
		_on_back()
	elif resume_enabled():
		click_resume()


func _focusables() -> Array:
	var out: Array = []
	_collect_focusables(_views[_current_view], out)
	return out


# Depth-first, so the options view's columns are walked top to bottom one after the other.
func _collect_focusables(n: Node, out: Array) -> void:
	for c in n.get_children():
		if not (c is Control and (c as Control).visible):
			continue
		if c is BaseButton or c is Slider or c is LineEdit:
			if not (c is BaseButton and (c as BaseButton).disabled):
				out.append(c)
		elif c is Container:
			_collect_focusables(c, out)


func _is_toggle(c: Control) -> bool:
	return c is Button and (c as Button).toggle_mode


func gamepad_move_focus(dir: int) -> void:
	var items := _focusables()
	if items.is_empty():
		return
	var cur := get_viewport().gui_get_focus_owner()
	var idx := items.find(cur)
	idx = 0 if idx == -1 else posmod(idx + dir, items.size())
	(items[idx] as Control).grab_focus()
	game.audio.play_sound("buttonselect111.wav", 0.25)


func gamepad_adjust(dir: int) -> void:
	var cur := get_viewport().gui_get_focus_owner()
	if cur is Slider:
		var s := cur as Slider
		s.value = clampf(s.value + dir * s.step, s.min_value, s.max_value)
		game.audio.play_sound("buttonselect111.wav", 0.25)
	elif cur != null and _is_toggle(cur):
		(cur as Button).button_pressed = not (cur as Button).button_pressed
		game.audio.play_sound("buttonselect111.wav", 0.35)


func gamepad_accept() -> void:
	var cur := get_viewport().gui_get_focus_owner()
	if cur == null:
		gamepad_move_focus(0)
		return
	if _is_toggle(cur):
		(cur as Button).button_pressed = not (cur as Button).button_pressed
		game.audio.play_sound("buttonselect111.wav", 0.4)
	elif cur is BaseButton:
		(cur as BaseButton).pressed.emit()
