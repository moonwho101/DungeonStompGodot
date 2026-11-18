# Headless test suite: godot --headless --path . -s res://tests/test_runner.gd
extends SceneTree

var _failures := 0


func check(cond: bool, msg: String) -> void:
	if cond:
		print("  ok   ", msg)
	else:
		_failures += 1
		printerr("  FAIL ", msg)


func _init() -> void:
	_run_tests.call_deferred()


func _run_tests() -> void:
	print("Dungeon Stomp Godot tests")

	var tm := Parsers.TextureManager.new()
	tm.load_textures_dat("bin/textures.dat")
	check(tm.aliases.size() > 100, "textures.dat aliases loaded (%d)" % tm.aliases.size())

	var objs := Parsers.ObjectsDatParser.new()
	objs.parse("bin/Objects.dat")
	check(objs.objects.size() > 100, "Objects.dat definitions parsed (%d)" % objs.objects.size())
	var corridor: Parsers.ObjectDef = null
	for id in objs.objects:
		if objs.objects[id].name.to_lower() == "corridor01":
			corridor = objs.objects[id]
			break
	var tri_count := 0
	if corridor != null:
		for p: Parsers.ObjectPoly in corridor.polys:
			tri_count += p.verts.size() / 15
	check(tri_count == 96, "CORRIDOR01 has 96 triangles (%d)" % tri_count)

	var models := Parsers.ModelListParser.new()
	models.parse("bin/modellist.dat")
	var goblin := models.get_model_by_name("GOBLIN")
	check(goblin != null and goblin.is_md2() and goblin.monster_weapon == "GOBLINAXE", "modellist GOBLIN entry")

	for m_name in ["FULIMO", "OKTA", "SORB"]:
		var cfg := Monster.get_config(m_name)
		check(cfg.canCastSpells == true and cfg.spells.size() > 0 and cfg.attackRange > 100.0 and cfg.stopDistance > 100.0 and cfg.spellCooldown > 0.0,
			"%s spellcaster config" % m_name)

	var level := Parsers.LevelMapParser.new()
	level.parse_file("bin/level1.map")
	check(level.instances.size() == 1991, "level1.map instances (%d)" % level.instances.size())
	check(level.start_pos == Vector3(5200, 128, 2600), "level1.map start position")

	var a := DungeonGenerator.generate({"numObjectsToPlace": 150, "seed": "test-seed"})
	var b := DungeonGenerator.generate({"numObjectsToPlace": 150, "seed": "test-seed"})
	check(a != "" and a == b, "seeded generator is deterministic")
	check(a.contains("spiral") and a.begins_with("OBJECT startpos"), "generated map has start and exit portal")
	check(DungeonGenerator.imul(0xFFFFFFFF, 5) == 0xFFFFFFFB, "imul matches Math.imul")

	var cw := CollisionWorld.new()
	cw.add_triangle(Vector3(0, 0, 0), Vector3(0, 0, 500), Vector3(500, 0, 500))
	cw.add_triangle(Vector3(0, 0, 0), Vector3(500, 0, 500), Vector3(500, 0, 0))
	cw.build_grid()
	var grounded := cw.resolve_capsule_world(Vector3(250, 80, 250), CollisionWorld.EYE_HEIGHT, CollisionWorld.CAPSULE_RADIUS,
		CollisionWorld.CAPSULE_HEIGHT, Vector3(0, -100, 0), true, null, [], false, Vector3.ZERO)
	check(grounded and absf(cw.out_pos.y - 100.0) < 1.0, "capsule lands on floor (y=%.2f)" % cw.out_pos.y)
	check(cw.out_vel.y >= 0.0, "downward velocity removed on landing")
	check(cw.has_line_of_sight(Vector3(100, 100, 100), Vector3(400, 100, 400)), "line of sight in open air")
	check(not cw.has_line_of_sight(Vector3(250, 50, 250), Vector3(250, -50, 250)), "floor blocks line of sight")

	var md2 := MD2Model.load_for_def(goblin)
	check(md2 != null and md2.frame_count >= 198, "goblin.md2 loads with all frames")
	_fall_and_attack_tests(md2)
	_monster_movement_tests(md2)
	var chest := TDSModel.load_for_def(models.get_model_by_name("cdoorclosedchest"))
	check(chest != null and chest.has_geometry, "chest .3ds loads")

	var wav := AudioManager.load_wav(FileAccess.get_file_as_bytes(DataPaths.path("Sounds/swish8.wav")))
	check(wav != null and wav.data.size() > 0, "IMA-ADPCM wav decodes")

	_xr_tests(models)
	_effect_pool_tests()

	TDSModel.clear_cache()
	MD2Model.clear_cache()
	Materials.clear_caches()

	print("FAILED: %d" % _failures if _failures > 0 else "ALL TESTS PASSED")
	quit(1 if _failures > 0 else 0)


func _effect_pool_tests() -> void:
	var fx := Effects.new()
	root.add_child(fx)
	for i in 2:
		var life := 0.01 if i == 0 else 1.0
		fx.emit_particle(i, 10, 0, 0, 0, 0, 0xff0000, 2, life)
		fx._emit_blood(i, 10, 0, 0, 0, 0, 1, 0, 0, 1, 2, life, 0, 0, 0, 1, 0, false)
	fx.update_pickup_effects(0.02)
	check(fx._p_mm.visible_instance_count == 1 and fx._p_buf[3] == 1.0,
		"only surviving spark is submitted, with its own transform")
	check(fx._b_mm.visible_instance_count == 1 and fx._b_buf[3] == 1.0 and fx._b_buf[16] == 1.0,
		"only surviving blood instance is submitted, with its own transform and softness")
	fx.add_explosion_flash(Vector3.ZERO, 0xffffff, 100)
	var flash: Effects.LightSlot = fx.explosion_flashes[0].slot
	fx.create_floating_text("pickup", Vector3.ZERO, "#ffffff")
	fx.clear_world_effects()
	fx.update_pickup_effects(0.01)
	check(not flash.busy and fx.floating_texts.is_empty() and fx.explosion_flashes.is_empty()
		and fx._p_mm.visible_instance_count == 0 and fx._b_mm.visible_instance_count == 0,
		"changing worlds releases transient effects immediately")
	fx.free()


class QuietAudio:
	extends RefCounted

	func play_sound(_file: String, _volume: float) -> void:
		pass


class QuietEffects:
	extends RefCounted

	func emit_particle(_x: float, _y: float, _z: float, _vx: float, _vy: float, _vz: float,
			_color: int, _size: float, _life: float) -> void:
		pass


class MonsterTestGame:
	extends RefCounted
	var dungeon_depth := 1
	var world_root := Node3D.new()
	var collision := CollisionWorld.new()
	var monsters: Array = []
	var fall_recovery_y := -1000.0
	var player_start_pos := Vector3(500, 128, 500)
	var target := Vector3(0, 100, 0)
	var audio := QuietAudio.new()
	var fx := QuietEffects.new()
	var damage := 0.0
	var shots := 0

	func player_position() -> Vector3:
		return target

	func damage_player(amount: float) -> void:
		damage += amount

	func launch_monster_projectile(_monster: Monster, _spell: String, _target: Vector3) -> void:
		shots += 1


func _test_monster(game: MonsterTestGame, model: MD2Model, family: String) -> Monster:
	var mesh := model.create_instance("")
	game.world_root.add_child(mesh)
	return Monster.new(game, model, mesh, null, null, Monster.get_config(family), Vector3(0, 50, 0), 0.0, 1.0)


func _fall_and_attack_tests(model: MD2Model) -> void:
	var player := Game.new()
	player.camera = Camera3D.new()
	root.add_child(player.camera)
	player.player_start_pos = Vector3(500, 128, 500)
	player.collision.add_triangle(Vector3(0, -2000, 0), Vector3(0, -2000, 100), Vector3(100, -2000, 0))
	player._update_fall_recovery_y()
	check(player.fall_recovery_y == -3000.0, "fall threshold follows lowest triangle, including negative-Y maps")
	var box := CollisionWorld.Box.new()
	box.expand(Vector3(0, -2500, 0))
	box.expand(Vector3(100, -2400, 100))
	player.collision.boxes.append(box)
	player._update_fall_recovery_y()
	check(player.fall_recovery_y == -3500.0, "fall threshold also includes model collision boxes")
	player.camera.position = Vector3(0, player.fall_recovery_y, 0)
	check(not player._recover_player_if_fallen(), "player at threshold is not teleported")
	player.camera.position.y -= 1.0
	player.velocity = Vector3(10, -2000, 20)
	player.is_grounded = true
	player.jump_requested = true
	player.player_stats.health = 37.0
	player._update_player_movement(0.1, {})
	check(player.camera.position == player.player_start_pos and player.velocity == Vector3.ZERO,
		"fallen player returns to map start with velocity cleared before movement")
	check(not player.is_grounded and not player.jump_requested and player.player_stats.health == 37.0,
		"player recovery clears movement state without healing")
	for flying in [false, true]:
		player.fly_mode = flying
		player.camera.position = Vector3(0, player.fall_recovery_y + 1.0, 0)
		player.velocity = Vector3(0, -500, 0)
		player._update_player_movement(0.1, {})
		check(player.camera.position == player.player_start_pos and player.velocity == Vector3.ZERO,
			"player crossing threshold recovers in the same update (fly mode %s)" % flying)
	player.collision.clear()
	player.player_start_pos = Vector3(0, 500, 0)
	player._update_fall_recovery_y()
	check(player.fall_recovery_y == -600.0, "empty collision world uses startpos feet for threshold")
	player.camera.free()
	player.free()

	var game := MonsterTestGame.new()
	var monster := _test_monster(game, model, "GOBLIN")
	monster.position.y = game.fall_recovery_y
	check(not monster._recover_if_fallen(), "monster at threshold is not teleported")
	monster.position.y -= 1.0
	monster.velocity = Vector3(10, -2000, 20)
	monster.is_grounded = true
	monster.health = 7.0
	monster.set_state(Monster.State.ATTACK)
	monster.pending_spell = "FIREBALL"
	monster.has_los = true
	monster.update(0.1, game.target)
	check(monster.position == game.player_start_pos and monster.velocity == Vector3.ZERO and not monster.is_grounded,
		"fallen monster recovers even if marked grounded")
	check(monster.health == 7.0 and monster.state == Monster.State.IDLE and monster.pending_spell == "" and not monster.has_los,
		"monster recovery preserves health and cancels stale combat state")
	check(monster.mesh.position == monster.position and monster.bbox.contains_point(monster.position)
		and monster.hp_bar.position == monster.position + Vector3(0, monster.health_bar_height, 0),
		"monster mesh, hitbox and health bar follow recovery")
	monster.position = Vector3(0, game.fall_recovery_y + 1.0, 0)
	monster.velocity.y = -500.0
	monster.update(0.1, game.target)
	check(monster.position == game.player_start_pos and monster.velocity == Vector3.ZERO,
		"monster crossing threshold during gravity recovers in the same update")
	monster.state = Monster.State.DEATH
	monster.dead = true
	monster.health = 0.0
	monster.position.y = game.fall_recovery_y - 1.0
	monster.update(0.1, game.target)
	check(monster.position == game.player_start_pos and monster.dead and monster.health == 0.0
		and monster.bbox.is_empty(), "fallen corpse is recovered without resurrection")

	var melee := _test_monster(game, model, "GOBLIN")
	for height in [300.0, -300.0, 70.0, 0.0]:
		game.target = Vector3(0 if height == 70.0 else 80, 100 + height, 0)
		melee.set_state(Monster.State.CHASE)
		melee.update(0.0, game.target)
		check((melee.state == Monster.State.ATTACK) == (height == 0.0),
			"melee attack entry respects vertical range (height %.0f)" % height)
	for height in [65.0, -65.0, 64.0, -64.0, 0.0]:
		game.target = Vector3(0, 100 + height, 0)
		melee.set_state(Monster.State.CHASE)
		melee.set_state(Monster.State.ATTACK)
		melee.set_animation(Monster.ANIMS.ATTACK, true)
		melee.anim_timer = 0.4
		game.damage = 0.0
		melee.update(0.0, game.target)
		check((game.damage > 0.0) == (absf(height) <= Monster.MELEE_VERTICAL_REACH),
			"melee impact rechecks height after windup (height %.0f)" % height)
	var walled := MonsterTestGame.new()
	walled.collision.add_triangle(Vector3(50, -200, -200), Vector3(50, 400, -200), Vector3(50, 400, 200))
	walled.collision.add_triangle(Vector3(50, -200, -200), Vector3(50, 400, 200), Vector3(50, -200, 200))
	walled.collision.build_grid()
	walled.target = Vector3(100, 100, 0)
	var blocked := _test_monster(walled, model, "GOBLIN")
	blocked.set_state(Monster.State.ATTACK)
	blocked.set_animation(Monster.ANIMS.ATTACK, true)
	blocked.anim_timer = 0.4
	blocked.update(0.0, walled.target)
	check(walled.damage == 0.0, "melee impact needs line of sight to the player")
	walled.world_root.free()

	var caster := _test_monster(game, model, "SORCERER")
	for height in [651.0, -651.0, 0.0]:
		game.target = Vector3(200, 100 + height, 0)
		caster.set_state(Monster.State.CHASE)
		caster.los_timer = 0.0
		caster.update(0.0, game.target)
		check((caster.state == Monster.State.ATTACK) == (height == 0.0),
			"spell attack entry respects 3D range (height %.0f)" % height)
		caster.set_state(Monster.State.CHASE)
		caster.set_state(Monster.State.ATTACK)
		caster.set_animation(Monster.ANIMS.ATTACK, true)
		caster.anim_timer = 0.4
		game.shots = 0
		caster.update(0.0, game.target)
		check((game.shots == 1) == (height == 0.0),
			"spell release rechecks height after windup (height %.0f)" % height)
	game.world_root.free()
	Monster.clear_shared()


func _monster_movement_tests(model: MD2Model) -> void:
	var game := MonsterTestGame.new()
	game.collision.add_triangle(Vector3(-500, 0, -500), Vector3(-500, 0, 500), Vector3(0, 0, 500))
	game.collision.add_triangle(Vector3(-500, 0, -500), Vector3(0, 0, 500), Vector3(0, 0, -500))
	game.collision.add_triangle(Vector3(0, 0, -200), Vector3(0, 300, -200), Vector3(0, 300, 200))
	game.collision.add_triangle(Vector3(0, 0, -200), Vector3(0, 300, 200), Vector3(0, 0, 200))
	game.collision.build_grid()
	game.target = Vector3(500, 100, 0)
	game.fall_recovery_y = -100000.0
	var monster := _test_monster(game, model, "GOBLIN")
	for fps in [60, 30, 15, 10]:
		monster.position = Vector3(-24.01, 50.01, 0)
		monster.velocity = Vector3.ZERO
		monster.rotation_y = PI / 2.0
		monster.state = Monster.State.CHASE
		monster.is_grounded = true
		var max_x := monster.position.x
		var min_y := monster.position.y
		for frame in fps:
			monster.update(1.0 / fps, game.target)
			max_x = maxf(max_x, monster.position.x)
			min_y = minf(min_y, monster.position.y)
		check(max_x <= -24.0 and min_y >= 50.0,
			"monster stays behind thin wall and on floor at %d FPS (max x=%.2f, min y=%.2f)" % [fps, max_x, min_y])
		if fps == 60:
			monster.update(0.1, game.target)
			check(monster.position.x <= -24.0 and monster.position.y >= 50.0,
				"one 100 ms hitch during 60 FPS pursuit cannot cross a thin wall")

	game.collision.clear()
	game.target = Vector3(1000, 100, 0)
	for fps in [60, 10]:
		monster.position = Vector3(0, 50, 0)
		monster.rotation_y = PI / 2.0
		for frame in fps:
			monster._move_forward(1.0 / fps, game.target)
		check(absf(monster.position.x - monster.config.moveSpeed) < 0.01,
			"subdivided pursuit preserves movement speed at %d FPS" % fps)
		monster.position = Vector3(0, 50, 0)
		monster.strafe_dir = 1.0
		monster.strafe_timer = 2.0
		monster._tactical_movement(1.0 / fps, 1000.0, game.target)
		check(absf(monster.position.z - monster.config.moveSpeed * 0.65 / fps) < 0.01,
			"subdivided strafing preserves movement speed at %d FPS" % fps)
	game.world_root.free()
	Monster.clear_shared()


# VR logic that doesn't need a headset: fixed weapon pose, grip fit, swing detection and blade hits.
func _xr_tests(models: Parsers.ModelListParser) -> void:
	var axe_def := models.get_model_by_name("AXE")
	var axe := MD2Model.load_for_def(axe_def)
	var fit := XRRig.weapon_fit(axe, axe_def.name, axe_def.scale)
	var tip: Vector3 = fit.tip
	var pommel: Vector3 = fit.pommel
	check(tip.z < -20.0 and Vector2(tip.x, tip.y).length() < 0.5, "XR weapon tip points along grip -Z (%s)" % tip)
	check(pommel.z > 0.0 and Vector2(pommel.x, pommel.y).length() < 0.5, "XR weapon pommel sits behind the hand (%s)" % pommel)

	var rig := XRRig.new()
	rig.weapon_anchor = Node3D.new()
	var mesh := axe.create_instance(axe_def.texture_alias)
	Materials.set_instance_parameter(mesh, "frames", Vector4(7, 8, 0, 0))
	Materials.set_instance_parameter(mesh, "weights", Vector4(0.5, 0.5, 0, 0))
	rig.attach_weapon(mesh, axe, axe_def.name, axe_def.scale)
	check(_instance_parameter(mesh, "frames") == Vector4.ZERO
		and _instance_parameter(mesh, "weights") == Vector4(1, 0, 0, 0), "XR weapon is held in fixed frame-0 pose")
	var other := axe.create_instance(axe_def.texture_alias)
	axe.set_pose(other, [7], [1.0])
	check(_instance_parameter(other, "frames") == Vector4(7, 0, 0, 0)
		and _instance_parameter(mesh, "frames") == Vector4.ZERO, "MD2 instances keep independent poses")
	other.free()
	check(mesh.get_parent() == rig.weapon_anchor, "XR weapon parented to the controller anchor")
	rig.weapon_anchor.free()
	rig.free()

	var dt := 1.0 / 90.0
	var m := XRRig.UNITS_PER_METER
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234
	var jitter := PackedVector3Array()
	for i in 270:
		jitter.append(Vector3(rng.randf_range(-0.002, 0.002), rng.randf_range(-0.002, 0.002), rng.randf_range(-0.002, 0.002)) * m)
	check(_count_swings(jitter, dt) == 0, "tracking jitter at rest makes no swing sound")
	var twitch := PackedVector3Array()
	for i in 90:
		var off := 0.04 if i % 30 in [10, 11] else 0.0 # 4 cm jerk for two frames, a few times
		twitch.append(Vector3(off, 0, 0) * m)
	check(_count_swings(twitch, dt) == 0, "small quick twitches make no swing sound")
	check(_count_swings(_swing_path(0.5, 1.0, dt), dt) == 0, "slowly repositioning the weapon makes no swing sound")
	check(_count_swings(_swing_path(0.15, 0.12, dt), dt) == 0, "short flick (15 cm) makes no swing sound")
	check(_count_swings(_swing_path(0.6, 0.22, dt), dt) == 1, "a real swing (60 cm in 0.22 s) plays exactly one swing")
	var two := _swing_path(0.6, 0.22, dt)
	for i in 45:
		two.append(two[two.size() - 1])
	for p in _swing_path(0.6, 0.22, dt):
		two.append(Vector3(0.6 * m, 0, 0) - p) # swing back the other way
	check(_count_swings(two, dt) == 2, "two real swings half a second apart play two swings")

	var bmin := Vector3(-20, 0, -20)
	var bmax := Vector3(20, 80, 20)
	check(XRRig.blade_hits_box(bmin, bmax, 0.0, Vector3(-60, 40, 0), Vector3(-10, 40, 0), Vector3(-10, 40, 0)), "blade inside monster box hits")
	check(XRRig.blade_hits_box(bmin, bmax, 0.0, Vector3(-60, 40, 0), Vector3(-10, 40, 40), Vector3(-10, 40, -40)), "tip sweep through box hits")
	check(not XRRig.blade_hits_box(bmin, bmax, 0.0, Vector3(-90, 40, 0), Vector3(-40, 40, 0), Vector3(-40, 50, 0)), "blade outside box misses")

	var merged := XRRig.merge_input({"move_x": 0.5, "jump": false}, {"move_x": 0.8, "jump": true, "turn": 0.3})
	check(is_equal_approx(merged.move_x, 1.0) and merged.jump and is_equal_approx(merged.turn, 0.3), "gamepad and XR input merge")


func _instance_parameter(instance: GeometryInstance3D, parameter: StringName) -> Variant:
	if Materials.uses_material_uniforms():
		return (instance.material_override as ShaderMaterial).get_shader_parameter(parameter)
	return instance.get_instance_shader_parameter(parameter)


# Hand path (relative to the head) moving `meters` along X over `seconds` with an eased (sine) speed profile,
# padded with a short rest before and after.
func _swing_path(meters: float, seconds: float, dt: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	for i in 10:
		out.append(Vector3.ZERO)
	var n := maxi(1, roundi(seconds / dt))
	for i in n + 1:
		var k := 0.5 - 0.5 * cos(PI * float(i) / n)
		out.append(Vector3(meters * k * XRRig.UNITS_PER_METER, 0, 0))
	for i in 20:
		out.append(out[out.size() - 1])
	return out


# Runs a hand path through the same smoothing + state machine XRRig uses and counts swing sounds.
func _count_swings(path: PackedVector3Array, dt: float) -> int:
	var state := XRRig.new_swing_state()
	var speed := 0.0
	var starts := 0
	for i in range(1, path.size()):
		speed = XRRig.smooth_speed(speed, (path[i] - path[i - 1]).length() / dt, dt)
		if XRRig.swing_step(state, speed, dt) == "start":
			starts += 1
	return starts
