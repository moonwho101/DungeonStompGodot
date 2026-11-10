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
	var chest := TDSModel.load_for_def(models.get_model_by_name("cdoorclosedchest"))
	check(chest != null and chest.has_geometry, "chest .3ds loads")

	var wav := AudioManager.load_wav(FileAccess.get_file_as_bytes(DataPaths.path("Sounds/swish8.wav")))
	check(wav != null and wav.data.size() > 0, "IMA-ADPCM wav decodes")

	_xr_tests(models)

	TDSModel.clear_cache()
	MD2Model.clear_cache()
	Materials.clear_caches()

	print("FAILED: %d" % _failures if _failures > 0 else "ALL TESTS PASSED")
	quit(1 if _failures > 0 else 0)


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
	mesh.set_instance_shader_parameter("frames", Vector4(7, 8, 0, 0))
	mesh.set_instance_shader_parameter("weights", Vector4(0.5, 0.5, 0, 0))
	rig.attach_weapon(mesh, axe, axe_def.name, axe_def.scale)
	check(mesh.get_instance_shader_parameter("frames") == Vector4.ZERO
		and mesh.get_instance_shader_parameter("weights") == Vector4(1, 0, 0, 0), "XR weapon is held in fixed frame-0 pose")
	check(mesh.get_parent() == rig.weapon_anchor, "XR weapon parented to the controller anchor")
	rig.weapon_anchor.free()
	rig.free()

	var s := XRRig.new_swing_state()
	check(XRRig.swing_step(s, XRRig.SWING_START_SPEED * 0.5, 0.016) == "", "slow motion is not a swing")
	check(XRRig.swing_step(s, XRRig.SWING_START_SPEED * 1.2, 0.016) == "start", "fast motion starts a swing")
	check(XRRig.swing_step(s, XRRig.SWING_START_SPEED * 1.2, 0.016) == "", "swing continues without restarting")
	check(XRRig.swing_step(s, XRRig.SWING_END_SPEED * 0.5, 0.016) == "end", "swing ends when the tip slows")
	check(XRRig.swing_step(s, XRRig.SWING_START_SPEED * 2.0, 0.016) == "", "cooldown blocks an immediate new swing")
	XRRig.swing_step(s, 0.0, XRRig.SWING_COOLDOWN)
	check(XRRig.swing_step(s, XRRig.SWING_START_SPEED * 2.0, 0.016) == "start", "new swing after cooldown")

	var bmin := Vector3(-20, 0, -20)
	var bmax := Vector3(20, 80, 20)
	check(XRRig.blade_hits_box(bmin, bmax, 0.0, Vector3(-60, 40, 0), Vector3(-10, 40, 0), Vector3(-10, 40, 0)), "blade inside monster box hits")
	check(XRRig.blade_hits_box(bmin, bmax, 0.0, Vector3(-60, 40, 0), Vector3(-10, 40, 40), Vector3(-10, 40, -40)), "tip sweep through box hits")
	check(not XRRig.blade_hits_box(bmin, bmax, 0.0, Vector3(-90, 40, 0), Vector3(-40, 40, 0), Vector3(-40, 50, 0)), "blade outside box misses")

	var merged := XRRig.merge_input({"move_x": 0.5, "jump": false}, {"move_x": 0.8, "jump": true, "turn": 0.3})
	check(is_equal_approx(merged.move_x, 1.0) and merged.jump and is_equal_approx(merged.turn, 0.3), "gamepad and XR input merge")
