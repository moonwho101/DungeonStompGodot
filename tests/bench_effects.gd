# Headless CPU benchmark: simulate a full burst followed by 32 longer-lived sparks.
extends SceneTree


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var fx := Effects.new()
	root.add_child(fx)
	for i in Effects.MAX_PARTICLES:
		fx.emit_particle(i, 0, 0, 1, 1, 1, 0xffffff, 1, 60.0 if i >= Effects.MAX_PARTICLES - 32 else 0.01)
	fx._update_particles(0.02)
	var samples := PackedInt64Array()
	for batch in 7:
		var start := Time.get_ticks_usec()
		for frame in 120:
			fx._update_particles(1.0 / 90.0)
		samples.append(Time.get_ticks_usec() - start)
	samples.sort()
	print("32 live sparks: %d submitted; median %.1f us/update (7 x 120 updates)" %
		[fx._p_mm.visible_instance_count, samples[3] / 120.0])
	fx.free()
	quit()
