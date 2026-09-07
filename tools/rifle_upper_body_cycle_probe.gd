extends "res://tools/rifle_reference_visual_probe.gd"

## Read-only pose diagnostics; see AK_M4_UPPER_BODY_STABILITY_DIAGNOSIS.md.
## --weapon=ak-47|m4a1 --output-prefix=/private/tmp/rifle-body-cycle
const CYCLE_BONES := {
	"hips": &"mixamorig_Hips", "spine": &"mixamorig_Spine",
	"chest": &"mixamorig_Spine2", "head": &"mixamorig_Head",
	"left_shoulder": &"mixamorig_LeftArm", "right_shoulder": &"mixamorig_RightArm",
	"left_foot": &"mixamorig_LeftFoot", "right_foot": &"mixamorig_RightFoot",
	"left_toe": &"mixamorig_LeftToeBase", "right_toe": &"mixamorig_RightToeBase",
}


func _run() -> void:
	if "--automated-test" in OS.get_cmdline_user_args() or weapon_id not in ["ak-47", "m4a1"]:
		failures.append("Use canonical input without --automated-test and AK/M4 only")
		_finish()
		return
	DirAccess.make_dir_recursive_absolute(output_prefix.get_base_dir())
	scene = (load("res://main.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(scene)
	await _frames(45)
	player = scene.get_node("Player") as CharacterBody3D
	controller = scene.get_node("WeaponController")
	driver = player.get_node("Mannequin/ProductionAnimation")
	_install_fixture()
	if not bool(controller.call("apply_authorized_weapon_pickup", "res://config/weapons/%s.json" % weapon_id)):
		failures.append("Canonical equip failed")
		_finish()
		return
	await _frames(90)
	for stance in [0, 1]:
		for direction: StringName in [&"move_left", &"move_right"]:
			for firing: bool in [false, true]:
				var selected := ""
				for argument in OS.get_cmdline_user_args():
					if argument.begins_with("--state="):
						selected = argument.trim_prefix("--state=")
				var state := "%s_%s_%s" % ["standing" if stance == 0 else "crouched", direction, "fire" if firing else "carry"]
				if selected != "" and state != selected:
					continue
				Input.action_release(&"move_left")
				Input.action_release(&"move_right")
				player.global_position = Vector3(500, 0.02, 500)
				player.velocity = Vector3.ZERO
				if not bool(player.call("_try_set_posture", stance)):
					failures.append("Canonical posture refused")
				await _frames(100)
				Input.action_press(direction)
				await _frames(90)
				if firing:
					_request_shot()
					await _frames(30)
				await _record_cycle(stance, direction, firing)
	if samples.is_empty():
		failures.append("No requested cycle state matched")
	_finish()


func _record_cycle(stance: int, direction: StringName, firing: bool) -> void:
	var skeleton := driver.get("skeleton") as Skeleton3D
	var initial_angles: Dictionary = {}
	var ranges: Dictionary = {}
	var trace: Array[Dictionary] = []
	var rotation_refs: Dictionary = {}
	var label := "%s_%s_%s" % ["standing" if stance == 0 else "crouched", direction, "fire" if firing else "carry"]
	var camera_rig := get_first_node_in_group("socom_camera_rig")
	for frame in 240:
		if firing and frame % 48 == 40:
			_request_shot()
		await _frames(1)
		var values := _cycle_values(skeleton, rotation_refs)
		values["phase"] = float(driver.get("locomotion_graph").shared_phase)
		values["ready"] = float(driver.get("weapon_ready_weight"))
		values["carry_weight"] = float(driver.get("locomotion_graph").locomotion_carry_weight)
		values["speed_mps"] = Vector2(player.velocity.x, player.velocity.z).length()
		values["body_y"] = player.global_position.y
		values["body_yaw_deg"] = rad_to_deg(player.global_rotation.y)
		values["camera_aim_yaw_deg"] = rad_to_deg(float(camera_rig.get("aim_yaw")))
		values["camera_aim_pitch_deg"] = rad_to_deg(float(camera_rig.get("aim_pitch")))
		var pose: Node = driver.get("weapon_pose_solver")
		values["trigger_contact_m"] = float(pose.trigger_hand_error_m)
		values["support_contact_m"] = float(pose.support_hand_error_m)
		values["gait_roll_retention"] = float(driver.get("upper_body_gait_roll_retention"))
		values["separation"] = float(driver.call("_lower_body_separation_weight"))
		values["directional_error_deg"] = float(driver.get("posture_layer").last_directional_shoulder_error_deg)
		values["directional_target_deg"] = float(driver.get("posture_layer").last_directional_shoulder_target_deg)
		values["chest_correction_deg"] = float(driver.get("posture_layer").last_chest_square_correction_deg)
		for key: String in values:
			var value := float(values[key])
			if key.ends_with("_deg"):
				if not initial_angles.has(key):
					initial_angles[key] = value
				value = float(initial_angles[key]) + wrapf(value - float(initial_angles[key]), -180.0, 180.0)
			if not ranges.has(key):
				ranges[key] = {"min": value, "max": value, "range": 0.0}
			var interval: Dictionary = ranges[key]
			interval.min = minf(float(interval.min), value)
			interval.max = maxf(float(interval.max), value)
			interval.range = float(interval.max) - float(interval.min)
		trace.append(values)
	if float(ranges.speed_mps.min) < 0.5:
		failures.append(label + " did not actually move throughout the sample")
	if firing and float(ranges.ready.min) < 0.98:
		failures.append(label + " did not retain settled fire readiness")
	var row := {"state": label, "ranges": ranges, "frames": trace, "head_hips_y_correlation": _correlation(trace, "head_y", "hips_y")}
	samples.append(row)
	print("UPPER_BODY_CYCLE ", label, " ", JSON.stringify({"ranges": ranges, "head_hips_y_correlation": row.head_hips_y_correlation}))


func _cycle_values(skeleton: Skeleton3D, rotation_refs: Dictionary) -> Dictionary:
	var values: Dictionary = {}
	for label: String in CYCLE_BONES:
		var index := skeleton.find_bone(CYCLE_BONES[label])
		var world := skeleton.global_transform * skeleton.get_bone_global_pose(index)
		var position: Vector3 = player.global_basis.inverse() * (world.origin - player.global_position)
		values[label + "_x"] = position.x
		values[label + "_y"] = position.y
		values[label + "_z"] = position.z
		values[label + "_world_y"] = world.origin.y
		var rotation := world.basis.orthonormalized().get_rotation_quaternion().normalized()
		if not rotation_refs.has(label):
			rotation_refs[label] = rotation
		values[label + "_rotation_from_first_deg"] = rad_to_deg(rotation.angle_to(rotation_refs[label]))
		var angles := world.basis.orthonormalized().get_euler() * 180.0 / PI
		values[label + "_pitch_deg"] = angles.x
		values[label + "_yaw_deg"] = angles.y
		values[label + "_roll_deg"] = angles.z
	values["head_above_hips_y"] = float(values.head_y) - float(values.hips_y)
	values["chest_above_hips_y"] = float(values.chest_y) - float(values.hips_y)
	values["head_above_chest_y"] = float(values.head_y) - float(values.chest_y)
	var left := Vector3(values.left_shoulder_x, values.left_shoulder_y, values.left_shoulder_z)
	var right := Vector3(values.right_shoulder_x, values.right_shoulder_y, values.right_shoulder_z)
	var shoulder_bar := (right - left).normalized()
	values["shoulder_bar_roll_deg"] = rad_to_deg(asin(clampf(shoulder_bar.y, -1.0, 1.0)))
	values["shoulder_bar_yaw_deg"] = rad_to_deg(atan2(-shoulder_bar.z, shoulder_bar.x))
	values["shoulder_center_x"] = (left.x + right.x) * 0.5
	values["shoulder_center_y"] = (left.y + right.y) * 0.5
	var target: Vector3 = driver.get("visual_aim_target")
	var world_center: Vector3 = player.global_position + player.global_basis * ((left + right) * 0.5)
	var aim_forward := (target - world_center).normalized()
	var aim_right := aim_forward.cross(Vector3.UP).normalized()
	values["physical_shoulder_square_deg"] = rad_to_deg(acos(clampf(absf((player.global_basis * shoulder_bar).normalized().dot(aim_right)), 0.0, 1.0)))
	values["visual_aim_heading_deg"] = rad_to_deg(atan2(aim_forward.x, -aim_forward.z))
	for side: String in ["left", "right"]:
		var foot := Vector3(values[side + "_foot_x"], values[side + "_foot_y"], values[side + "_foot_z"])
		var toe := Vector3(values[side + "_toe_x"], values[side + "_toe_y"], values[side + "_toe_z"])
		var direction := toe - foot
		values[side + "_foot_to_toe_heading_deg"] = rad_to_deg(atan2(direction.x, -direction.z))
	return values


func _correlation(trace: Array[Dictionary], first: String, second: String) -> float:
	var a_sum := 0.0
	var b_sum := 0.0
	var aa_sum := 0.0
	var bb_sum := 0.0
	var ab_sum := 0.0
	for frame in trace:
		var a := float(frame[first])
		var b := float(frame[second])
		a_sum += a
		b_sum += b
		aa_sum += a * a
		bb_sum += b * b
		ab_sum += a * b
	var count := float(trace.size())
	var divisor := sqrt(maxf((count * aa_sum - a_sum * a_sum) * (count * bb_sum - b_sum * b_sum), 0.0))
	return (count * ab_sum - a_sum * b_sum) / divisor if divisor > 0.00000001 else 0.0
