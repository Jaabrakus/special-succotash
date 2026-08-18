extends SceneTree

const ComposureScript := preload("res://scripts/weapons/operator_composure.gd")


func _init() -> void:
	var failures: Array[String] = []
	var stresses: Array[float] = []
	for fps in [30.0, 60.0, 120.0]:
		stresses.append(_simulate_burst(fps))
	if absf(stresses[0] - stresses[1]) > 0.025 or absf(stresses[1] - stresses[2]) > 0.025:
		failures.append("composure varies excessively across frame rates: %s" % [stresses])

	var model := ComposureScript.new()
	model.stress = 1.0
	var core_floor := model.get_precision_core_scale()
	if core_floor < 0.699 or core_floor > 0.701:
		failures.append("full-stress precision core escaped its 70%% floor")
	model.notify_shot()
	for frame in 12:
		model.advance(1.0 / 60.0, 0.0, 0.0)
	if model.get_shot_bounce() > 0.001:
		failures.append("shot bounce did not reset after its transient envelope")

	var opening := ComposureScript.new()
	if opening.get_shot_dispersion_multiplier(1, 0.0, 0.0) != 0.0:
		failures.append("settled first shot was not exact-center")
	if opening.get_shot_dispersion_multiplier(1, 0.30, 0.0) <= 0.0:
		failures.append("movement did not invalidate exact-center first shot")
	var second_multiplier := opening.get_shot_dispersion_multiplier(2, 0.0, 0.0)
	if second_multiplier <= 0.0 or second_multiplier >= 0.30:
		failures.append("second shot escaped the tight opening-pair range")
	if opening.get_shot_dispersion_multiplier(3, 0.0, 0.0) != 1.0:
		failures.append("third shot did not enter the normal dispersion model")

	if failures.is_empty():
		print("COMPOSURE_REGRESSION_PASS fps_stress=%s core_floor=%.3f" % [stresses, core_floor])
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)


func _simulate_burst(fps: float) -> float:
	var model := ComposureScript.new()
	var frame_delta := 1.0 / fps
	var shot_interval := 60.0 / 650.0
	var duration := 0.80
	var elapsed := 0.0
	var next_shot := 0.0
	while elapsed < duration:
		var frame_end := minf(elapsed + frame_delta, duration)
		var cursor := elapsed
		# Apply each shot at its exact timestamp, even when several events land
		# inside a slow render frame. This mirrors a fixed/server tick event queue.
		while next_shot <= frame_end:
			model.advance(next_shot - cursor, 0.45, 0.20)
			model.notify_shot()
			cursor = next_shot
			next_shot += shot_interval
		model.advance(frame_end - cursor, 0.45, 0.20)
		elapsed = frame_end
	return model.stress
