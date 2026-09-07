extends "res://tools/rifle_full_right_reach_probe.gd"

## Saved D-only release, actual canonical input and physical endpoints.
## A measurement harness succeeds only if these additional assertions pass.
const PoseAPI := preload("res://scripts/player/operator_weapon_pose_solver.gd")
var phase_offset_frames := 0


func _run() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--phase-offset="):
			phase_offset_frames = clampi(int(argument.trim_prefix("--phase-offset=")), 0, 60)
	_check_equipment_defaults()
	await super._run()


func _check_equipment_defaults() -> void:
	var pose := PoseAPI.new()
	for id: String in ["ak-47", "m16a2", "m4a1", "mark_23"]:
		var document: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://config/weapons/%s.json" % id))
		var dynamic: Dictionary = document.get("handling_profile", {}).get("dynamic_hold", {})
		pose.configure_dynamic_hold(dynamic)
		var expected := 0.33 if id in ["ak-47", "m4a1"] else 0.0
		if not is_equal_approx(pose.strafe_right_stock_release_m, expected):
			failures.append(id + " equip-time release value leaks or differs from saved contract")
		var expected_frame: StringName = &"chest_forward" if id in ["ak-47", "m4a1"] else &"aim_forward"
		if pose.strafe_right_stock_release_frame != expected_frame:
			failures.append(id + " equip-time release frame leaks or differs from saved contract")
		var expected_pocket := 0.065 if id in ["ak-47", "m4a1"] else 0.0
		var expected_roll := -15.0 if id in ["ak-47", "m4a1"] else 0.0
		if not is_equal_approx(pose.ready_shoulder_pocket_downward_m, expected_pocket) or not is_equal_approx(pose.ready_shoulder_pocket_right_wrist_roll_degrees, expected_roll):
			failures.append(id + " equip-time pocket calibration leaks or differs from saved contract")
		if not is_zero_approx(pose.authored_stock_release_applied_m):
			failures.append(id + " equip must clear applied release")
		# Give the next equip a non-zero prior value to verify a real reset.
		pose.authored_stock_release_applied_m = 0.17
	var old: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://config/weapon_visual_rigs/m4a1_agls_v7.json"))
	var current: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://config/weapon_visual_rigs/m4a1_agls_v8.json"))
	var dynamic: Dictionary = current.visual.handling_profile.dynamic_hold
	if not is_equal_approx(float(dynamic.strafe_carry.right_stock_release_m), 0.33):
		failures.append("Published M4 v8 must include the real release opt-in")
	if String(dynamic.strafe_carry.get("right_stock_release_frame", "")) != "chest_forward":
		failures.append("Published M4 v8 must use the turned chest carry frame")
	var comparable := current.duplicate(true)
	comparable.visual.handling_profile.dynamic_hold.strafe_carry.erase("right_stock_release_frame")
	comparable.visual.handling_profile.dynamic_hold.strafe_carry.right_stock_release_m = old.visual.handling_profile.dynamic_hold.strafe_carry.right_stock_release_m
	comparable.revision = old.revision
	comparable.visual_rig_id = old.visual_rig_id
	if comparable != old:
		failures.append("Immutable M4 v8 changed more than the authorized carry frame and measured scalar")
	var v9: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://config/weapon_visual_rigs/m4a1_agls_v9.json"))
	var pocket: Dictionary = v9.visual.handling_profile.dynamic_hold.get("ready_shoulder_pocket", {})
	if not is_equal_approx(float(pocket.get("downward_m", 0.0)), 0.065) or not is_equal_approx(float(pocket.get("right_wrist_roll_degrees", 0.0)), -15.0):
		failures.append("Published M4 v9 must retain the measured non-right pocket calibration")
	var previous_comparable := v9.duplicate(true)
	previous_comparable.visual.handling_profile.dynamic_hold.erase("ready_shoulder_pocket")
	previous_comparable.revision = current.revision
	previous_comparable.visual_rig_id = current.visual_rig_id
	if previous_comparable != current:
		failures.append("Immutable M4 v9 changed more than its authorized ready shoulder pocket")
	pose.configure_dynamic_hold({"ready_shoulder_pocket": {"downward_m": INF, "right_wrist_roll_degrees": NAN}})
	if not is_zero_approx(pose.ready_shoulder_pocket_downward_m) or not is_zero_approx(pose.ready_shoulder_pocket_right_wrist_roll_degrees):
		failures.append("Non-finite pocket calibration must fail safely to zero")
	pose.configure_dynamic_hold({"ready_shoulder_pocket": {"downward_m": 10.0, "right_wrist_roll_degrees": -100.0}})
	if not is_equal_approx(pose.ready_shoulder_pocket_downward_m, 0.07) or not is_equal_approx(pose.ready_shoulder_pocket_right_wrist_roll_degrees, -20.0):
		failures.append("Pocket calibration must preserve its 7cm and 20-degree authoring bounds")
	pose.free()


func _accept_sample(row: Dictionary) -> void:
	var physical: Dictionary = row.physical
	var solver: Node = driver.get("weapon_pose_solver")
	var prefix := "%s posture=%s sample=%s " % [weapon_id, row.posture, row.sample_index]
	if not is_equal_approx(float(solver.get("strafe_right_stock_release_m")), 0.33):
		failures.append(prefix + "actual resolved runtime opt-in missing")
	if not is_equal_approx(float(solver.get("ready_shoulder_pocket_downward_m")), 0.065) or not is_equal_approx(float(solver.get("ready_shoulder_pocket_right_wrist_roll_degrees")), -15.0):
		failures.append(prefix + "actual resolved runtime pocket calibration missing")
	if float(row.stock_release_m) < 0.32 or float(row.stock_release_m) > 0.33001:
		failures.append(prefix + "full D must apply the bounded readiness-scaled release")
	if float(row.torso_target_deg) < 89.0 or absf(float(row.torso_target_error_deg)) > 0.1:
		failures.append(prefix + "probe did not attain the full right torso target")
	if String(row.stock_release_frame) != "chest_forward":
		failures.append(prefix + "actual runtime carry frame differs from saved chest-forward contract")
	if absf(float(row.stock_offset_aim_forward_m)) > 0.005 or absf(float(row.stock_offset_up_m)) > 0.005 or absf(float(row.stock_offset_aim_right_m) - float(row.stock_release_m)) > 0.005:
		failures.append(prefix + "full-right stock must sit in front of the turned chest, not along the barrel")
	if float(row.chest_forward_heading_error_deg) > 1.0:
		failures.append(prefix + "physical chest plane does not face the intended rightward heading")
	var mesh_clearance := float(row.chest_plane_mesh_clearance_m)
	if not is_finite(mesh_clearance) or mesh_clearance < 0.08:
		failures.append(prefix + "visible rigid weapon bounds do not clear the front of the physical chest plane")
	for key: String in ["stock", "trigger", "support", "muzzle"]:
		if float(row.chest_plane_contact_clearance_m[key]) < 0.10:
			failures.append(prefix + key + " must remain in front of the actual torso plane")
	if maxf(float(physical.trigger_contact_m), float(physical.support_contact_m)) > 0.005:
		failures.append(prefix + "physical palms exceed 5 mm")
	if float(physical.bore_to_reticle_degrees) > 0.5:
		failures.append(prefix + "physical barrel misses the reticle")
	for side: String in ["Left", "Right"]:
		var angle := float(row[side].current_elbow_deg)
		if angle < float(solver.get("minimum_elbow_angle_deg")) or angle > float(solver.get("maximum_elbow_angle_deg")):
			failures.append(prefix + side + " elbow outside existing human bounds: " + str(angle))


func _after_measurements() -> void:
	await _frames(phase_offset_frames)
	for stance in [0, 1]:
		player.call("_try_set_posture", stance)
		player.global_position = Vector3(500.0, 0.02, 500.0)
		player.velocity = Vector3.ZERO
		await _frames(100)
		var solver: Node = driver.get("weapon_pose_solver")
		if not is_zero_approx(float(solver.get("authored_stock_release_applied_m"))):
			failures.append("Idle leaked right-stock release")
		if _request_shot():
			await _record_transition(stance, "idle_shot_entry", 32)
		await _frames(110)
		Input.action_press(&"move_left")
		await _frames(45)
		if _request_shot():
			await _record_transition(stance, "A_shot_entry", 32)
		Input.action_release(&"move_left")
		await _record_transition(stance, "A_stop_recovery", 100)
		await _frames(20)
		Input.action_press(&"move_right")
		await _frames(45)
		if _request_shot():
			await _record_transition(stance, "shot_entry", 24)
		Input.action_release(&"move_right")
		Input.action_press(&"move_left")
		await _record_transition(stance, "D_to_A", 24)
		if _request_shot():
			await _record_transition(stance, "A_fire", 12)
		Input.action_release(&"move_left")
		Input.action_press(&"move_right")
		await _record_transition(stance, "A_to_D", 30)
		Input.action_release(&"move_right")
		await _record_transition(stance, "D_stop_recovery", 100)
		if float(driver.get("weapon_ready_weight")) > 0.001 or not is_zero_approx(float(solver.get("authored_stock_release_applied_m"))):
			failures.append("Recovery must return to zero ready and zero stock release")


func _record_transition(stance: int, state: String, frames: int) -> void:
	for frame in frames:
		await _frames(1)
		var row := _reach()
		row["posture"] = stance
		row["state"] = state
		row["frame"] = frame
		transition_samples.append(row)
		var solver: Node = driver.get("weapon_pose_solver")
		var prefix := "%s %s %s " % [weapon_id, stance, state]
		if float(row.right_stock_turn_weight) < 0.0:
			_fail_once(prefix + "canonical driver omitted shared right-turn binding")
		if is_zero_approx(float(row.right_stock_turn_weight)) and not is_zero_approx(float(row.stock_release_m)):
			_fail_once(prefix + "zero right-turn presentation leaked release")
		if bool(solver.get("authored_shoulder_stock_active")) and not is_equal_approx(float(row.stock_release_m), 0.33 * float(row.right_stock_turn_weight)):
			_fail_once(prefix + "stock release does not consume actual turn progress")
		if not bool(solver.get("authored_shoulder_stock_active")):
			continue
		if maxf(float(row.physical.trigger_contact_m), float(row.physical.support_contact_m)) > 0.005:
			_fail_once(prefix + "transition palms exceed 5 mm")
		if not state.ends_with("stop_recovery") and float(row.physical.bore_to_reticle_degrees) > 0.5:
			_fail_once(prefix + "accepted-fire physical bore exceeds 0.5 degrees")
		if float(row.ready) > 0.98:
			for side: String in ["Left", "Right"]:
				var angle := float(row[side].current_elbow_deg)
				if angle < float(solver.get("minimum_elbow_angle_deg")) or angle > float(solver.get("maximum_elbow_angle_deg")):
					_fail_once(prefix + side + " elbow violates existing human bounds")


func _fail_once(message: String) -> void:
	if not failures.has(message):
		failures.append(message)
