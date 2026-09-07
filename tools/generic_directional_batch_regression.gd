extends "res://tools/firearm_family_transition_regression.gd"

## Candidate proof only. Never writes a runtime profile or publishes a rig.
## Uses real canonical input/equip through the inherited family fixture.
## --weapons=870,hk5sd,m82a1a [--list-only] [--capture] --output-prefix=...
const BATCH_PATH := "res://config/weapon_directional_batch_candidates.json"
const RigContract := preload("res://scripts/labs/gunsmith2/weapon_visual_rig_contract.gd")
const EXPECTED_BATCH_IDS := [
	"12_gauge_pump", "552", "870", "9mm_sub", "aks-74", "f90", "hk5", "hk5sd",
	"m14", "m16a2-m203", "m3_12_gauge", "m4a1-m203", "m4a1_sd", "m60e3",
	"m63a", "m82a1a", "m87elr", "mark_46_mod_0", "sr-25", "sr-25_sd", "ta_12_gauge",
]

var batch_rows: Array[Dictionary] = []
const ContactGeometry := preload("res://scripts/player/operator_weapon_contact_solver.gd")
var use_candidate := false
var all_firearms := false
var geometry_holds: Array[String] = []


func _initialize() -> void:
	use_candidate = "--use-candidate" in OS.get_cmdline_user_args()
	all_firearms = "--all-firearms" in OS.get_cmdline_user_args()
	selected_ids.assign(["870", "hk5sd", "m82a1a"])
	if all_firearms:
		selected_ids.clear()
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--weapons="):
			selected_ids.clear()
			break
	super._initialize()


func _collect_inventory() -> void:
	super._collect_inventory()
	var document := _read_dictionary(BATCH_PATH)
	var entries: Dictionary = document.get("weapons", {})
	var ids: Array = entries.keys()
	ids.sort()
	var expected: Array = EXPECTED_BATCH_IDS.duplicate()
	expected.sort()
	if ids != expected:
		_fail_once("Generic candidate batch differs from its explicit21-ID scope")
	var checked_rigs: Dictionary = {}
	for id: String in ids:
		var entry: Dictionary = entries[id]
		var candidate_id := String(entry.get("candidate_rig", ""))
		if not checked_rigs.has(candidate_id):
			_validate_candidate(entry)
			checked_rigs[candidate_id] = true
	for id in selected_ids:
		if not entries.has(id):
			if all_firearms:
				continue # Existing AK/M4/M16/M40 and separate pistol negative controls.
			_fail_once(id + " is outside the generic candidate ownership scope")
			continue
		var entry: Dictionary = entries[id]
		var raw_path := "res://config/weapons/%s.json" % id
		var raw_text := FileAccess.get_file_as_string(raw_path)
		var raw := _read_dictionary(raw_path)
		var unchanged_lines := PackedStringArray()
		for line in raw_text.split("\n"):
			if line.begins_with('  "visual_rig_schema_version":'):
				continue
			if line.begins_with('  "visual_rig_id":'):
				if entry.has("source_visual_rig_id"):
					unchanged_lines.append('  "visual_rig_id": "%s",' % entry.source_visual_rig_id)
				continue
			unchanged_lines.append(line)
		var raw_unchanged := "\n".join(unchanged_lines).sha256_text() == String(entry.get("source_raw_sha256", ""))
		if not raw_unchanged:
			_fail_once(id + " raw model/gameplay data changed outside its visual-rig pointer")
		if not use_candidate and String(raw.get("visual_rig_id", "")) != String(entry.candidate_rig):
			_fail_once(id + " candidate is not assigned in the canonical raw profile")
		var resolved := Contract.load_config(raw_path)
		var handling: Dictionary = resolved.get("handling_profile", {})
		var resolved_family := String(handling.get("family", ""))
		if resolved_family != String(entry.family) or resolved_family not in ["LONG_GUN", "TWO_HAND_RIFLE"]:
			_fail_once(id + " candidate changed the original long-gun family")
		var dynamic: Dictionary = handling.get("dynamic_hold", {})
		if bool(dynamic.get("buttstock_constraint", {}).get("enabled", true)):
			_fail_once(id + " candidate enabled legacy stock behavior outside authored ready")
		for row in inventory:
			if row.id != id:
				continue
			if row.gameplay_contract_sha256 != String(entry.gameplay_sha256):
				_fail_once(id + " canonical mechanics signature changed")
		batch_rows.append({"weapon":id, "candidate":entry.candidate_rig, "raw_unchanged_except_pointer":raw_unchanged,
			"family":resolved_family, "legacy_stock_enabled":dynamic.get("buttstock_constraint", {}).get("enabled", true)})
	print("GENERIC_DIRECTIONAL_CONTRACT rigs=", checked_rigs.size(), " selected=", selected_ids, " failures=", failures)


func _check_stance(stance: int) -> void:
	if use_candidate and stance == 0:
		var document := _read_dictionary(BATCH_PATH)
		if not document.weapons.has(weapon_id):
			await super._check_stance(stance)
			return
		var entry: Dictionary = document.weapons[weapon_id]
		var candidate := _read_dictionary("res://config/weapon_visual_rigs/%s.json" % entry.candidate_rig)
		var raw_path := "res://config/weapons/%s.json" % weapon_id
		var raw := Contract.load_config(raw_path)
		# This pass copies handling only. Retain every current visual geometry
		# field even where an earlier, separate fit experiment moved a contact.
		if all_firearms:
			var current_visual := RigContract.extract(raw, String(candidate.visual_rig_id), 1, "published")
			var candidate_input := RigContract.merge_for_presentation(raw, candidate)
			candidate_input.erase("visual_rig_id")
			var normalized_candidate := Contract.normalize_config(candidate_input, raw_path)
			for field: String in RigContract.VISUAL_FIELDS:
				if field != "handling_profile" and candidate.visual.has(field) and not _same_value(current_visual.visual.get(field), normalized_candidate.get(field)):
					if not geometry_holds.has(weapon_id):
						geometry_holds.append(weapon_id)
					if current_visual.visual.has(field):
						candidate.visual[field] = current_visual.visual[field].duplicate(true) if current_visual.visual[field] is Dictionary or current_visual.visual[field] is Array else current_visual.visual[field]
					else:
						candidate.visual.erase(field)
		var merged: Dictionary = RigContract.merge_for_presentation(raw, candidate)
		merged.erase("visual_rig_id")
		var config := Contract.normalize_config(merged, raw_path)
		for key in ["ballistics", "fire_modes", "default_fire_mode", "burst_size", "weapon_id", "model_fbx"]:
			if not _same_value(raw.get(key), config.get(key)):
				_fail_once(weapon_id + " preview changed protected data " + key)
		if not player.get_node("Mannequin").call("notify_operator_weapon_equipped", config):
			_fail_once(weapon_id + " saved candidate presentation handoff refused")
			return
		await _frames(90)
		_assert_weapon_visible(weapon_id + " saved candidate preview")
		print("GENERIC_IN_MEMORY_CANDIDATE ", weapon_id, " rig=", entry.candidate_rig)
	await super._check_stance(stance)


func _validate_candidate(entry: Dictionary) -> void:
	var base := _read_dictionary("res://config/weapon_visual_rigs/%s.json" % entry.base_rig)
	var candidate := _read_dictionary("res://config/weapon_visual_rigs/%s.json" % entry.candidate_rig)
	var validation: Dictionary = RigContract.validate(candidate, true, String(entry.candidate_rig))
	if not bool(validation.get("ok", false)):
		_fail_once(String(entry.candidate_rig) + " immutable contract validation failed")
		return
	var expected_visual: Dictionary = base.get("visual", {}).duplicate(true)
	var handling: Dictionary = expected_visual.handling_profile
	var dynamic: Dictionary = handling.dynamic_hold
	var calibration: Dictionary = entry.get("calibration", {})
	var support_contact: Dictionary = calibration.get("support_contact", {})
	for key: String in support_contact:
		if key not in ["y", "z"] or not entry.has("surface_witness"):
			_fail_once(String(entry.candidate_rig) + " support contact lacks the declared triangle witness")
		else:
			expected_visual.weapon_sockets.left_hand_ik_target[key] = float(support_contact[key])
	dynamic.authored_shoulder_stock_enabled = true
	dynamic.locomotion_ready_carry_weight = 1.0
	dynamic.standing_idle_square_pelvis = true
	dynamic.ready_shoulder_pocket = {"downward_m":float(calibration.get("ready_pocket_downward_m", 0.03)), "right_wrist_roll_degrees":-15.0}
	var base_pocket: Dictionary = calibration.get("base_pocket", {})
	for key: String in base_pocket:
		if key not in ["inward_offset_m", "downward_offset_m", "forward_offset_m"]:
			_fail_once(String(entry.candidate_rig) + " unknown base-pocket calibration key")
		else:
			dynamic.buttstock_constraint[key] = float(base_pocket[key])
	dynamic.strafe_carry = {"right_hip_follow_weight":1.0, "left_elbow_flare_degrees":12.0,
		"right_stock_release_m":float(calibration.get("right_stock_release_m", 0.33)), "right_stock_release_frame":"chest_forward"}
	handling.locomotion_slots = {"run_left":"run_lateral_left", "run_right":"run_lateral_right",
		"crouch_left":"crouch_lateral_left", "crouch_right":"crouch_lateral_right"}
	if not _same_value(expected_visual, candidate.get("visual", {})):
		_fail_once(String(entry.candidate_rig) + " changes an unapproved visual/model/contact/action field")
	if candidate.get("family", "") != base.get("family", ""):
		_fail_once(String(entry.candidate_rig) + " changed its rig family")


func _record_transition(label: String, count: int, check_bore: bool) -> void:
	for frame in count:
		await super._record_transition(label, 1, check_bore)
		if transition_rows.is_empty():
			continue
		transition_rows[-1].frame = frame
		var solver: Node3D = driver.get("weapon_pose_solver")
		var reach: Dictionary = {}
		for side: String in ["Right", "Left"]:
			var hand_target: Node3D = solver.get("trigger_hand_target" if side == "Right" else "support_hand_target")
			var palm_anchor: Vector3 = solver.get("right_palm_anchor_local" if side == "Right" else "left_palm_anchor_local")
			var wrist: Transform3D = ContactGeometry.wrist_target_for_contact(solver.skeleton, hand_target.global_transform, palm_anchor)
			var shoulder: Vector3 = solver.call("_bone_world_position", StringName("mixamorig_" + side + "Arm"))
			var elbow: Vector3 = solver.call("_bone_world_position", StringName("mixamorig_" + side + "ForeArm"))
			var actual_wrist: Vector3 = solver.call("_bone_world_position", StringName("mixamorig_" + side + "Hand"))
			var upper := shoulder.distance_to(elbow)
			var lower := elbow.distance_to(actual_wrist)
			var distance := shoulder.distance_to(wrist.origin)
			var minimum := float(solver.get("minimum_elbow_angle_deg"))
			var maximum := float(solver.get("maximum_elbow_angle_deg"))
			var minimum_reach := sqrt(maxf(0.0, upper * upper + lower * lower - 2.0 * upper * lower * cos(deg_to_rad(minimum))))
			var maximum_reach := sqrt(maxf(0.0, upper * upper + lower * lower - 2.0 * upper * lower * cos(deg_to_rad(maximum))))
			reach[side.to_lower()] = {"requested_wrist_distance_m":distance, "minimum_reach_m":minimum_reach,
				"maximum_reach_m":maximum_reach, "upper_length_m":upper, "lower_length_m":lower,
				"wrist_position_error_m":actual_wrist.distance_to(wrist.origin),
				"shoulder_world":str(shoulder), "requested_wrist_world":str(wrist.origin)}
		transition_rows[-1].requested_reach = reach
		# Each inherited one-frame observation sees frame zero. Preserve the
		# parent's intermediate-stop captures using this enclosing frame index.
		if capture and label.ends_with("_D_stop_recovery") and frame in [5, 6, 7, 9, 12, 15, 17, 95, 97, 98, 99]:
			await _capture_state(label + "_frame_%02d" % frame)


func _same_value(left: Variant, right: Variant) -> bool:
	if typeof(left) in [TYPE_INT, TYPE_FLOAT] and typeof(right) in [TYPE_INT, TYPE_FLOAT]:
		return float(left) == float(right)
	if left is Dictionary and right is Dictionary:
		if left.size() != right.size():
			return false
		for key: Variant in left:
			if not right.has(key) or not _same_value(left[key], right[key]):
				return false
		return true
	if left is Array and right is Array:
		if left.size() != right.size():
			return false
		for index in left.size():
			if not _same_value(left[index], right[index]):
				return false
		return true
	return left == right


func _read_dictionary(path: String) -> Dictionary:
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return value if value is Dictionary else {}


func _finish() -> void:
	var file := FileAccess.open(output_prefix + "-candidate-contract.json", FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify({"candidate_only":true, "in_memory_preview":use_candidate,
			"all_firearms":all_firearms, "geometry_holds":geometry_holds,
			"selected":batch_rows, "failures":failures}, "\t"))
		file.close()
	super._finish()
