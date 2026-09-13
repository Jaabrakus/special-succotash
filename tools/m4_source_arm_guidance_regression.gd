extends "res://tools/rifle_reference_visual_probe.gd"

const SourcePose := preload("res://scripts/player/operator_seal_weapon_pose.gd")
var baseline := false
var checked_frames := 0
var maximum_contact_m := 0.0
var maximum_firing_bore_degrees := 0.0
var maximum_elbow_step_m := 0.0
var previous_elbows: Dictionary = {}
var previous_physics_frame := -1
var skipped_step_intervals := 0


func _run() -> void:
	baseline = "--baseline" in OS.get_cmdline_user_args()
	weapon_id = "m4a1"
	_check_transport_math()
	if capture and DisplayServer.get_name() == "headless":
		failures.append("Capture needs a native display")
		_finish()
		return
	scene = (load("res://main.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(scene)
	await _frames(60)
	player = scene.get_node("Player") as CharacterBody3D
	driver = player.get_node("Mannequin/ProductionAnimation")
	controller = scene.get_node("WeaponController")
	_install_fixture()
	_check(bool(controller.call("apply_authorized_weapon_pickup", "res://config/weapons/m4a1.json")), "M4 canonical equip")
	if baseline:
		driver.animation_profile.locomotion.m4_source_elbow_transport_max_degrees = 0.0
	await _frames(90)
	var solver: Node3D = driver.weapon_pose_solver
	_check(is_equal_approx(solver.source_elbow_transport_max_degrees, 0.0 if baseline else 35.0), "Saved profile reaches runtime solver")
	for stance in [0, 1]:
		player.global_position = Vector3(500, 0.02, 500)
		player.velocity = Vector3.ZERO
		_check(bool(player.call("_try_set_posture", stance)), "Canonical stance accepted")
		await _frames(100)
		previous_elbows.clear()
		previous_physics_frame = -1
		var prefix := "standing" if stance == 0 else "crouched"
		Input.action_press(&"move_left")
		await _observe(24, prefix + "_left_entry")
		if _request_shot():
			await _observe(6, prefix + "_left_fire_entry")
			await _sample(prefix + "_left_fire_entry")
			await _observe(18, prefix + "_left_fire_settled")
			await _sample(prefix + "_left_fire_settled")
		Input.action_release(&"move_left")
		Input.action_press(&"move_right")
		await _observe(6, prefix + "_reverse_entry")
		await _sample(prefix + "_reverse_entry")
		await _observe(18, prefix + "_reverse_settled")
		if _request_shot():
			await _observe(6, prefix + "_right_fire_entry")
			await _sample(prefix + "_right_fire_entry")
			await _observe(18, prefix + "_right_fire_settled")
			await _sample(prefix + "_right_fire_settled")
		Input.action_release(&"move_right")
		await _observe(100, prefix + "_stop_recovery")
		await _sample(prefix + "_returned_idle")
		_check(SourcePose.elbow_transport_limit(solver, 0.0) == 0.0, "Idle returns to authored guide")
	# Protected states and equip reset must not inherit the M4 adjustment.
	for movement: StringName in [&"AIRBORNE", &"LANDING", &"DIVING", &"ROLLING", &"VAULTING"]:
		solver.last_movement_state = movement
		_check(SourcePose.elbow_transport_limit(solver, 1.0) == 0.0, "Protected " + String(movement))
	solver.last_movement_state = &"LOCOMOTION"
	solver.last_posture = &"PRONE"
	_check(SourcePose.elbow_transport_limit(solver, 1.0) == 0.0, "Prone unchanged")
	solver.last_posture = &"STANDING"
	solver.last_requested_action = &"reload"
	_check(SourcePose.elbow_transport_limit(solver, 1.0) == 0.0, "Reload unchanged")
	for gun in ["mark_23", "ak-47", "m4a1"]:
		_check(bool(controller.call("apply_authorized_weapon_pickup", "res://config/weapons/%s.json" % gun)), "Equip " + gun)
		await _frames(2)
		_check(is_equal_approx(solver.source_elbow_transport_max_degrees, 35.0 if gun == "m4a1" and not baseline else 0.0), "No cross-weapon guidance leakage " + gun)
	samples.append({"summary": true, "baseline": baseline, "checked_frames": checked_frames,
		"maximum_contact_m": maximum_contact_m, "maximum_firing_bore_degrees": maximum_firing_bore_degrees,
		"maximum_elbow_step_m": maximum_elbow_step_m, "skipped_step_intervals": skipped_step_intervals})
	# Let queued scene/equipment cleanup complete before terminating the tree.
	scene.queue_free()
	await process_frame
	await process_frame
	scene = null
	_finish()


func _observe(count: int, state: String) -> void:
	for frame in count:
		await _frames(1)
		checked_frames += 1
		var measured := _measure_physical_pose()
		_check(not measured.is_empty(), "Physical measurements present")
		if measured.is_empty():
			continue
		var contact := maxf(float(measured.trigger_contact_m), float(measured.support_contact_m))
		maximum_contact_m = maxf(maximum_contact_m, contact)
		_check(contact < 0.01, state + " grips remain within 1cm")
		if bool(driver.get("_presentation_fire_selected")):
			var bore := float(measured.bore_to_reticle_degrees)
			maximum_firing_bore_degrees = maxf(maximum_firing_bore_degrees, bore)
			_check(bore < 0.5, state + " accepted fire bore within 0.5 degrees")
		var solver: Node3D = driver.weapon_pose_solver
		var tick := Engine.get_physics_frames()
		# Rendering/capture can skip physics ticks under load. Do not misreport
		# their accumulated motion as a single-frame animation discontinuity.
		var adjacent := previous_physics_frame >= 0 and tick == previous_physics_frame + 1
		if previous_physics_frame >= 0 and not adjacent:
			skipped_step_intervals += 1
		for side in ["Left", "Right"]:
			var elbow: Vector3 = solver._bone_world_position(StringName("mixamorig_" + side + "ForeArm")) - solver._bone_world_position(StringName("mixamorig_" + side + "Arm"))
			if previous_elbows.has(side) and adjacent:
				var step := elbow.distance_to(previous_elbows[side])
				maximum_elbow_step_m = maxf(maximum_elbow_step_m, step)
				_check(step < 0.10, state + " elbow step below 10cm on adjacent ticks")
			previous_elbows[side] = elbow
		previous_physics_frame = tick


func _check_transport_math() -> void:
	var shoulder := Vector3(2, 3, 4)
	var wrist := shoulder + Vector3.FORWARD * 0.6
	var elbow := shoulder + Vector3(0.2, -0.15, -0.3)
	var turn := Basis(Vector3.UP, deg_to_rad(25.0))
	var target := shoulder + turn * (wrist - shoulder)
	var result := SourcePose.transport_elbow(shoulder, wrist, elbow, target, 35.0)
	_check(result.distance_to(shoulder + turn * (elbow - shoulder)) < 0.00001, "Guide follows source-to-target reach rotation")
	_check(is_equal_approx(result.distance_to(shoulder), elbow.distance_to(shoulder)), "Transport preserves shoulder-guide radius")
	_check(SourcePose.transport_elbow(shoulder, wrist, elbow, target, 0.0) == elbow, "Zero preserves authored guide")
	_check(SourcePose.transport_elbow(shoulder, shoulder, elbow, target, 35.0) == elbow, "Zero reach safe")
	_check(SourcePose.transport_elbow(shoulder, wrist, elbow, shoulder - (wrist - shoulder), 35.0) == elbow, "Opposite reach safe")
	_check(SourcePose.transport_elbow(shoulder, wrist, elbow, target, NAN) == elbow, "Nonfinite limit safe")
	var capped := SourcePose.transport_elbow(shoulder, wrist, elbow, target, 10.0)
	_check(rad_to_deg((capped - shoulder).angle_to(elbow - shoulder)) <= 10.001, "Transport respects angular cap")


func _check(ok: bool, message: String) -> void:
	if not ok and not failures.has(message):
		failures.append(message)
