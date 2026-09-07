extends "res://tools/firearm_family_transition_regression.gd"

## Exact saved-rig scope plus canonical physical transitions. Never edits data.
## --list-only for saved-contract proof; --phase-offset=13 for another gait phase.
const ORIGINAL := "res://config/weapon_visual_rigs/assaultrifle_1_v3.json"
const CANDIDATE := "res://config/weapon_visual_rigs/m16a2_directional_v1.json"
const ORIGINAL_SHA256 := "41577a81f208026fa19cabadb078ba6e1388dbf2ec3d7545b3c8c6a8646c2435"
const SUPPORT_POINT := Vector3(-0.0152557790279388, 0.0739297866821289, 0.24)
const SUPPORT_DATA := {"x":-0.0152557790279388,"y":0.0739297866821289,"z":0.24}
var phase_offset_frames := 0


func _initialize() -> void:
	super._initialize()
	for id in selected_ids:
		if id != "m16a2":
			_fail_once("This saved-rig proof is limited to M16A2")
	selected_ids.assign(["m16a2"])
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--phase-offset="):
			phase_offset_frames = clampi(int(argument.trim_prefix("--phase-offset=")), 0, 60)


func _collect_inventory() -> void:
	super._collect_inventory()
	if FileAccess.get_sha256(ORIGINAL) != ORIGINAL_SHA256:
		_fail_once("Original published M16 rig must remain immutable")
	var original: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ORIGINAL))
	var candidate: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CANDIDATE))
	var expected: Dictionary = original.visual.duplicate(true)
	var hold: Dictionary = expected.handling_profile.dynamic_hold
	hold.authored_shoulder_stock_enabled = true
	hold.ready_shoulder_pocket = {"downward_m":0.065,"right_wrist_roll_degrees":-15.0}
	hold.locomotion_ready_carry_weight = 1.0
	hold.standing_idle_square_pelvis = true
	hold.strafe_carry = {"right_hip_follow_weight":1.0,"left_elbow_flare_degrees":12.0,
		"right_stock_release_m":0.33,"right_stock_release_frame":"chest_forward"}
	hold.fire_saved_joint_rotations_enabled = false
	hold.fire_spine_ccdik_enabled = false
	var slots: Dictionary = expected.handling_profile.locomotion_slots
	slots.run_left = "run_lateral_left"
	slots.run_right = "run_lateral_right"
	slots.crouch_left = "crouch_lateral_left"
	slots.crouch_right = "crouch_lateral_right"
	expected.weapon_sockets.left_hand_ik_target = SUPPORT_DATA.duplicate()
	for clip: String in ["aim_idle", "combat_fire"]:
		for frame: Dictionary in expected.animation_frame_pose_keys[clip].values():
			frame.left_hand_target = SUPPORT_DATA.duplicate()
	for key: String in expected.animation_hand_maps:
		if not key.contains("Climbing"):
			expected.animation_hand_maps[key].left_grip = SUPPORT_DATA.duplicate()
	for stance: Dictionary in expected.stances.values():
		stance.left_grip = SUPPORT_DATA.duplicate()
	if not _same_data(candidate.visual, expected):
		_fail_once("M16 candidate changed a protected visual field beyond carry and normalized support contact")
	for key: String in ["schema_version", "family", "source_model_fbx", "status"]:
		if candidate.get(key) != original.get(key):
			_fail_once("M16 candidate changed protected metadata: " + key)
	var resolved := Contract.load_config("res://config/weapons/m16a2.json")
	if String(resolved.get("_visual_rig_id", "")) != "m16a2_directional_v1":
		_fail_once("Canonical M16 does not resolve the reviewed candidate")
	# Shared normalization round-trips JSON doubles through float32 Vector3.
	# The raw immutable visual diff above is exact; runtime space uses 1 µm.
	var resolved_support: Vector3 = Contract.vector3_from_map(resolved.get("weapon_sockets", {}).get("left_hand_ik_target", {}), Vector3.INF)
	if resolved_support.distance_to(SUPPORT_POINT) > 0.000001:
		_fail_once("Canonical M16 support contact differs from published candidate")
	print("M16_DIRECTIONAL_CONTRACT ", "PASS" if failures.is_empty() else "FAIL", " phase_offset=", phase_offset_frames)


func _check_stance(stance: int) -> void:
	await _frames(phase_offset_frames)
	await super._check_stance(stance)


func _measure_physical_pose() -> Dictionary:
	var result := super._measure_physical_pose()
	var solver: Node = driver.get("weapon_pose_solver")
	var support := solver.get("support_socket") as Node3D
	if support == null or support.position.distance_to(SUPPORT_POINT) > 0.000001:
		_fail_once("M16 ordinary stance/action switched away from its one saved support contact")
	return result


func _same_data(first: Variant, second: Variant) -> bool:
	if first is Dictionary and second is Dictionary:
		if first.size() != second.size():
			return false
		for key: Variant in first:
			if not second.has(key) or not _same_data(first[key], second[key]):
				return false
		return true
	if first is Array and second is Array:
		if first.size() != second.size():
			return false
		for index in first.size():
			if not _same_data(first[index], second[index]):
				return false
		return true
	if (first is int or first is float) and (second is int or second is float):
		return absf(float(first) - float(second)) < 0.000000000001
	return first == second
