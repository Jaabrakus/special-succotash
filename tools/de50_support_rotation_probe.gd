extends "res://tools/firearm_family_transition_regression.gd"

## Bounded authoring preview for DE50_PALM_ROTATION_TRANSLATION.md.
## No runtime/profile writes. Optional --pitch= --yaw= --roll= changes only the
## live preview metadata consumed by the existing saved support-palm path.
## A passing preview is NOT an assigned/published rig; verify that separately.
var preview_angles := Vector3.ZERO
var reach_rows: Array[Dictionary] = []


func _initialize() -> void:
	selected_ids = ["de__50"]
	output_prefix = "/private/tmp/de50-support-rotation"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output-prefix="):
			output_prefix = argument.trim_prefix("--output-prefix=")
		elif argument.begins_with("--pitch="):
			preview_angles.x = float(argument.trim_prefix("--pitch="))
		elif argument.begins_with("--yaw="):
			preview_angles.y = float(argument.trim_prefix("--yaw="))
		elif argument.begins_with("--roll="):
			preview_angles.z = float(argument.trim_prefix("--roll="))
		elif argument == "--capture":
			capture = true
	_run.call_deferred()


func _run() -> void:
	root.set_disable_input(true)
	for action: StringName in InputMap.get_actions():
		InputMap.action_erase_events(action)
	_validate_saved_revision()
	await super._run()


func _validate_saved_revision() -> void:
	var before: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://config/weapon_visual_rigs/family_pistol_4_v3.json"))
	var after: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://config/weapon_visual_rigs/family_pistol_4_v5.json"))
	var contract := load("res://scripts/labs/gunsmith2/weapon_visual_rig_contract.gd")
	var validation: Dictionary = contract.validate(after, true, "family_pistol_4_v5")
	if not bool(validation.get("ok", false)):
		_fail_once("DE .50 immutable visual-rig contract invalid")
	var expected_visual: Dictionary = before.visual.duplicate(true)
	expected_visual.support_hand_pose.palm_pitch_deg = 3.0
	var same_visual := _same_value(expected_visual, after.visual)
	if not same_visual:
		_fail_once("DE .50 revision changes more than the approved support wrist pitch")
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://config/weapons/de__50.json"))
	if raw.get("visual_rig_id", "") != "family_pistol_4_v5":
		_fail_once("DE .50 canonical saved assignment missing")
	print("DE50_SAVED_REVISION ", validation.get("ok", false), " only_support_pitch_changed=", same_visual)


func _same_value(left: Variant, right: Variant, value_path: String = "visual") -> bool:
	# JSON 0 and 0.0 are the same data. Compare nested numeric values exactly,
	# without an approximate tolerance or relying on container identity.
	if typeof(left) in [TYPE_INT, TYPE_FLOAT] and typeof(right) in [TYPE_INT, TYPE_FLOAT]:
		if float(left) != float(right):
			print("DE50_DATA_DIFFERENCE ", value_path, " before=%.20f after=%.20f" % [float(left), float(right)])
		return float(left) == float(right)
	if left is Dictionary and right is Dictionary:
		if left.size() != right.size():
			return false
		for key: Variant in left:
			if not right.has(key) or not _same_value(left[key], right[key], value_path + "." + str(key)):
				return false
		return true
	if left is Array and right is Array:
		if left.size() != right.size():
			return false
		for index in left.size():
			if not _same_value(left[index], right[index], value_path + "." + str(index)):
				return false
		return true
	return left == right


func _check_stance(stance: int) -> void:
	var solver: Node = driver.get("weapon_pose_solver")
	if not preview_angles.is_zero_approx():
		var weapon: Node = solver.get("weapon_node")
		var palm: Dictionary = weapon.get_meta("support_hand_pose", {}).duplicate(true)
		palm.palm_pitch_deg = preview_angles.x
		palm.palm_yaw_deg = preview_angles.y
		palm.palm_roll_deg = preview_angles.z
		weapon.set_meta("support_hand_pose", palm)
		# Hand-map entry restores metadata from this already-loaded saved contract.
		# Preview the same source field, not a transient metadata value that the
		# canonical loader correctly overwrites on the next animation transition.
		var asset: RefCounted = driver.get("asset_runtime")
		var config: Dictionary = asset.get("equipped_weapon_config").duplicate(true)
		config["support_hand_pose"] = palm
		asset.set("equipped_weapon_config", config)
	await super._check_stance(stance)


func _record_transition(label: String, count: int, check_bore: bool) -> void:
	for frame in count:
		await super._record_transition(label, 1, check_bore)
		if not transition_rows.is_empty():
			transition_rows[-1].frame = frame
		if label.contains("standing_D_fire") and frame in [10, 13, 16, 20]:
			_record_reach(label, frame)
		if capture and label.contains("D_fire") and frame == 13:
			await _capture_state(label + "_frame13")


func _record_reach(label: String, frame: int) -> void:
	var solver: Node = driver.get("weapon_pose_solver")
	var shoulder: Vector3 = solver.call("_bone_world_position", &"mixamorig_LeftArm")
	var elbow: Vector3 = solver.call("_bone_world_position", &"mixamorig_LeftForeArm")
	var wrist: Vector3 = solver.call("_bone_world_position", &"mixamorig_LeftHand")
	var palm: Transform3D = solver.call("_left_hand_grip_world_transform")
	var socket: Node3D = solver.get("support_socket")
	var a := shoulder.distance_to(elbow)
	var b := elbow.distance_to(wrist)
	var offset := palm.origin - wrist
	var base_basis := socket.global_basis.orthonormalized()
	var hand_pose: Dictionary = solver.get("weapon_node").get_meta("support_hand_pose", {})
	var current_angles := Vector3(float(hand_pose.get("palm_pitch_deg", 0.0)), float(hand_pose.get("palm_yaw_deg", 0.0)), float(hand_pose.get("palm_roll_deg", 0.0)))
	var current_basis := base_basis * Basis.from_euler(current_angles * (PI / 180.0), EULER_ORDER_YXZ)
	var candidates: Array[Dictionary] = []
	for axis in 3:
		for angle in [-5.0, -2.0, 0.0, 2.0, 5.0]:
			var angles := current_angles
			angles[axis] += angle
			var next_basis := base_basis * Basis.from_euler(angles * (PI / 180.0), EULER_ORDER_YXZ)
			var next_wrist := socket.global_position - next_basis * current_basis.inverse() * offset
			var distance := shoulder.distance_to(next_wrist)
			var predicted := rad_to_deg(acos(clampf((a * a + b * b - distance * distance) / (2.0 * a * b), -1.0, 1.0)))
			candidates.append({"axis": ["pitch", "yaw", "roll"][axis], "delta_deg": angle, "predicted_elbow_deg": predicted, "desired_wrist_span_m": distance})
	var row := {"state": label, "frame": frame, "current_angle": _physical_elbow_angle(&"Left"), "upper_m": a, "lower_m": b, "palm_error_m": palm.origin.distance_to(socket.global_position), "candidates": candidates}
	reach_rows.append(row)
	print("DE50_REACH ", JSON.stringify(row))


func _finish() -> void:
	var output := FileAccess.open(output_prefix + "-reach.json", FileAccess.WRITE)
	if output:
		output.store_string(JSON.stringify({"preview_only": not preview_angles.is_zero_approx(), "preview_support_rotation_degrees": str(preview_angles), "reach": reach_rows}, "\t"))
		output.close()
	super._finish()
