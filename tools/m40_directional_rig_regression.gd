extends "res://tools/firearm_family_transition_regression.gd"

## Visual-only M40 revision; source weapon values remain byte-identical.
const RAW := "res://config/weapons/m40a1.json"
const CANDIDATE := "res://config/weapon_visual_rigs/m40a1_directional_v3.json"
const RAW_SHA256 := "d5e325b738b6d788b0af7f7530c455de24a00dd0774f98641916eef17c101f74"
const VisualContract := preload("res://scripts/labs/gunsmith2/weapon_visual_rig_contract.gd")


func _initialize() -> void:
	super._initialize()
	selected_ids.assign(["m40a1"])


func _collect_inventory() -> void:
	super._collect_inventory()
	var source := FileAccess.get_file_as_string(RAW)
	var original_source := source.replace('  "visual_rig_id": "m40a1_directional_v3",\n', "")
	if original_source.sha256_text() != RAW_SHA256:
		_fail_once("M40 raw data changed outside its explicit visual pointer")
	var original: Dictionary = JSON.parse_string(original_source)
	var expected: Dictionary = VisualContract.extract(original, "m40a1_directional_v1", 1, "published").visual
	var hold: Dictionary = expected.handling_profile.dynamic_hold
	hold.authored_shoulder_stock_enabled = true
	hold.locomotion_ready_carry_weight = 1.0
	hold.standing_idle_square_pelvis = true
	hold.fire_saved_joint_rotations_enabled = false
	hold.fire_spine_ccdik_enabled = false
	hold.ready_shoulder_pocket = {"downward_m":0.055, "right_wrist_roll_degrees":-15.0}
	hold.strafe_carry = {"right_hip_follow_weight":1.0, "left_elbow_flare_degrees":12.0,
		"right_stock_release_m":0.33, "right_stock_release_frame":"chest_forward"}
	var slots: Dictionary = expected.handling_profile.locomotion_slots
	slots.run_left = "run_lateral_left"
	slots.run_right = "run_lateral_right"
	slots.crouch_left = "crouch_lateral_left"
	slots.crouch_right = "crouch_lateral_right"
	var support := {"x":-0.00334209203720093, "y":0.0764622688293457, "z":0.26}
	expected.weapon_sockets.left_hand_ik_target = support.duplicate()
	for clip: String in ["aim_idle", "combat_fire"]:
		for frame: Dictionary in expected.animation_frame_pose_keys[clip].values():
			frame.left_hand_target = support.duplicate()
	for key: String in ["aim_idle", "combat_fire", "idle_crouch", "gunsmith_catalog_4031626968"]:
		expected.animation_hand_maps[key].left_grip = support.duplicate()
	for stance: String in ["STANDING", "CROUCHED"]:
		expected.stances[stance].left_grip = support.duplicate()
	var candidate: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CANDIDATE))
	if not _same_data(expected, candidate.get("visual", {})):
		_fail_once("M40 candidate changed an undeclared model/contact/action field")
	var validation := VisualContract.validate(candidate, true, "m40a1_directional_v3")
	if not validation.ok:
		_fail_once("M40 candidate contract rejected: " + str(validation.errors))
	if Contract.load_config(RAW).get("_visual_rig_id", "") != "m40a1_directional_v3":
		_fail_once("M40 canonical consumer did not resolve the candidate")
	print("M40_DIRECTIONAL_CONTRACT ", "PASS" if failures.is_empty() else "FAIL")


func _same_data(left: Variant, right: Variant) -> bool:
	if left is Dictionary and right is Dictionary:
		if left.size() != right.size():
			return false
		for key: Variant in left:
			if not right.has(key) or not _same_data(left[key], right[key]):
				return false
		return true
	if left is Array and right is Array:
		if left.size() != right.size():
			return false
		for index in left.size():
			if not _same_data(left[index], right[index]):
				return false
		return true
	if typeof(left) in [TYPE_INT, TYPE_FLOAT] and typeof(right) in [TYPE_INT, TYPE_FLOAT]:
		return float(left) == float(right)
	return left == right
