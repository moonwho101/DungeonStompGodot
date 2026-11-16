# Run with a real renderer, not --headless:
# godot --xr-mode off --path . --rendering-method mobile -s res://tests/test_lighting.gd
extends SceneTree

var _failures := 0


func _init() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if condition:
		print("  ok   ", message)
	else:
		_failures += 1
		printerr("  FAIL ", message)


func _run() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(64, 64)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var camera := Camera3D.new()
	camera.position = Vector3(5200, 128, 2600)
	camera.near = 1.0
	camera.far = 2000.0
	viewport.add_child(camera)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color.BLACK
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_DISABLED
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	camera.environment = environment
	var light := OmniLight3D.new()
	light.omni_range = Effects.LIGHT_RANGE
	light.omni_attenuation = Effects.LIGHT_DECAY
	light.light_energy = Effects.POINT_LIGHT_INTENSITY / PI
	light.light_specular = 0.0
	light.position = camera.position
	viewport.add_child(light)
	var surface := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(2000, 2000)
	surface.mesh = quad
	viewport.add_child(surface)
	for kind in ["world", "phong"]:
		var material := ShaderMaterial.new()
		material.shader = Materials.get_shader(kind)
		material.set_shader_parameter("specular_color", Color.BLACK)
		surface.material_override = material
		for distance in [200.0, 400.0, 600.0, 800.0, 1050.0]:
			surface.position = camera.position + Vector3(0, 0, -distance)
			await process_frame
			await RenderingServer.frame_post_draw
			var image := viewport.get_texture().get_image()
			var measured := image.get_pixel(32, 32).srgb_to_linear().r
			var cutoff := pow(maxf(1.0 - pow(distance / Effects.LIGHT_RANGE, 4.0), 0.0), 2.0)
			var expected := Effects.POINT_LIGHT_INTENSITY / PI * cutoff * pow(distance, -Effects.LIGHT_DECAY)
			_check(absf(measured - expected) < maxf(0.008, expected * 0.06),
				"%s falloff at %.0f units: measured %.4f, expected %.4f" % [kind, distance, measured, expected])
	viewport.free()
	Materials.clear_caches()
	print("LIGHTING TESTS PASSED" if _failures == 0 else "LIGHTING FAILURES: %d" % _failures)
	quit(0 if _failures == 0 else 1)
