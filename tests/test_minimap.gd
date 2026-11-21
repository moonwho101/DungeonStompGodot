# Run with a GPU: godot --xr-mode off --path . -s res://tests/test_minimap.gd
extends SceneTree


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(160, 160)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var map := Minimap.new()
	map.size = Vector2(vp.size)
	var portal := {"position": Vector3.ZERO}
	map.game = {"collision": CollisionWorld.new(), "doors": [], "chests": [], "active_pickups": [],
		"monsters": [], "active_teleporters": [portal]}
	vp.add_child(map)
	# Check the actual composited pixels over the player and at the tip of three rim bearings.
	var failures := 0
	for pair: Array in [[Vector3.ZERO, Vector2i(80, 80)], [Vector3.FORWARD, Vector2i(80, 7)],
			[Vector3.RIGHT, Vector2i(152, 80)], [Vector3(-1, 0, 1), Vector2i(29, 131)]]:
		portal.position = pair[0] * 4000.0
		map.queue_redraw()
		await process_frame
		await RenderingServer.frame_post_draw
		var pixel := vp.get_texture().get_image().get_pixelv(pair[1])
		if not (pixel.b > 0.8 and pixel.g > 0.6 and pixel.r < 0.4):
			printerr("Exit marker missing at ", pair[1], ": ", pixel)
			failures += 1
	vp.free()
	if failures == 0:
		print("MINIMAP PORTAL TESTS PASSED")
	quit(1 if failures else 0)
