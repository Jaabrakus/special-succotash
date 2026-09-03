extends SceneTree

## Proves the AGLS sweep is sampled by camera pitch while SOCOM retains aim
## authority and both hands remain animation-owned.

var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var packed := load("res://main.tscn") as PackedScene
	_expect(packed != null, "main scene loads")
	if packed == null:
		_finish()
		return
	var scene := packed.instantiate()
	root.add_child(scene)
	for _frame in range(45):
		await process_frame
	var player := scene.get_node("Player") as CharacterBody3D
	var mannequin := player.get_node("Mannequin")
	var driver = mannequin.get_node_or_null("ProductionAnimation")
	_expect(driver != null, "production animation driver exists")
	if driver == null:
		_finish()
		return
	# This focused presentation test supplies its own immutable visual snapshot.
	# Pause the normal mannequin bridge so it cannot replace that snapshot from
	# the live camera on the next frame.
	mannequin.set_process(false)
	var measured_pitch: Dictionary = {}
	var sample_times: Dictionary = {}
	for pitch_degrees in [-20.0, 0.0, 20.0]:
		var pitch := deg_to_rad(pitch_degrees)
		var direction := Vector3(0.0, sin(pitch), -cos(pitch)).normalized()
		var target := player.global_position + Vector3.UP * 1.7 + direction * 20.0
		driver.set_visual_inputs(
			Vector2.ZERO,
			&"STANDING",
			0.0,
			pitch,
			1.0,
			false,
			0.0,
			0.0,
			&"LOCOMOTION",
			0.0,
			&"WALK",
			0.0,
			target
		)
		for _settle in range(8):
			await process_frame
		var barrel: Vector3 = mannequin.call("get_active_barrel_direction")
		var debug: Dictionary = driver.call("get_animation_debug_state")
		var sweep: Dictionary = debug.get("authored_rifle_aim_sweep", {})
		measured_pitch[pitch_degrees] = rad_to_deg(asin(clampf(barrel.y, -1.0, 1.0)))
		sample_times[pitch_degrees] = float(sweep.get("sample_time", -1.0))
		print("AGLS_AUTHORED_AIM_SWEEP pitch_input_deg=%.2f barrel_pitch_deg=%.4f sample_time=%.6f weight=%.4f bones=%d clip=%s" % [
			pitch_degrees,
			float(measured_pitch[pitch_degrees]),
			float(sample_times[pitch_degrees]),
			float(sweep.get("weight", 0.0)),
			int(sweep.get("bone_count", 0)),
			String(sweep.get("clip", "")),
		])
		_expect(bool(sweep.get("hands_are_animation_owned", false)), "hands stay animation-owned")
		_expect(int(sweep.get("bone_count", 0)) >= 10, "authored upper-body channels are applied")
	_expect(
		float(sample_times[-20.0]) > float(sample_times[0.0])
		and float(sample_times[0.0]) > float(sample_times[20.0]),
		"camera pitch selects ordered AGLS sweep samples"
	)
	_expect(
		float(measured_pitch[20.0]) > float(measured_pitch[0.0])
		and float(measured_pitch[0.0]) > float(measured_pitch[-20.0]),
		"rendered rifle follows camera pitch direction"
	)
	var measured_yaw: Dictionary = {}
	for yaw_degrees in [-20.0, 0.0, 20.0]:
		var yaw := deg_to_rad(yaw_degrees)
		var direction := Vector3(-sin(yaw), 0.0, -cos(yaw)).normalized()
		var target := player.global_position + Vector3.UP * 1.7 + direction * 20.0
		driver.set_visual_inputs(
			Vector2.ZERO, &"STANDING", yaw, 0.0, 1.0, false, 0.0,
			0.0, &"LOCOMOTION", 0.0, &"WALK", 0.0, target
		)
		for _settle in range(8):
			await process_frame
		var barrel: Vector3 = mannequin.call("get_active_barrel_direction")
		measured_yaw[yaw_degrees] = rad_to_deg(atan2(-barrel.x, -barrel.z))
		print("AGLS_AUTHORED_AIM_SWEEP yaw_input_deg=%.2f barrel_yaw_deg=%.4f" % [
			yaw_degrees,
			float(measured_yaw[yaw_degrees]),
		])
	_expect(
		float(measured_yaw[20.0]) > float(measured_yaw[0.0])
		and float(measured_yaw[0.0]) > float(measured_yaw[-20.0]),
		"rendered rifle follows camera yaw direction"
	)
	_finish()


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("AGLS_AUTHORED_AIM_SWEEP_CHECK PASS %s" % label)
		return
	failures.append(label)
	push_error("AGLS_AUTHORED_AIM_SWEEP_CHECK FAIL %s" % label)


func _finish() -> void:
	if failures.is_empty():
		print("AGLS_AUTHORED_AIM_SWEEP_LIVE_REGRESSION PASS")
		quit(0)
	else:
		print("AGLS_AUTHORED_AIM_SWEEP_LIVE_REGRESSION FAIL %s" % [failures])
		quit(1)
