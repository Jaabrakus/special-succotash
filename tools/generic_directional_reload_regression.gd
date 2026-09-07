extends "res://tools/reload_trigger_attachment_regression.gd"

## Reuses canonical three-posture reload/regrip and gameplay accounting.
## --weapons=f90 [--use-candidate] [--capture] --output-prefix=...
const CandidateContract := preload("res://scripts/labs/gunsmith2/weapon_visual_rig_contract.gd")
const CANDIDATE_REGISTRY := "res://config/weapon_directional_batch_candidates.json"


func _check_stance(stance: int) -> void:
	if stance == 0 and "--use-candidate" in OS.get_cmdline_user_args():
		var registry: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CANDIDATE_REGISTRY))
		if not registry.weapons.has(weapon_id):
			_fail_once(weapon_id + " is outside the declared generic batch")
			return
		var entry: Dictionary = registry.weapons[weapon_id]
		var path := "res://config/weapons/%s.json" % weapon_id
		var raw := Contract.load_config(path)
		var candidate: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://config/weapon_visual_rigs/%s.json" % entry.candidate_rig))
		var merged := CandidateContract.merge_for_presentation(raw, candidate)
		merged.erase("visual_rig_id")
		var config := Contract.normalize_config(merged, path)
		for key in ["weapon_id", "ballistics", "fire_modes", "default_fire_mode", "burst_size", "model_fbx"]:
			if JSON.stringify(raw.get(key), "", true) != JSON.stringify(config.get(key), "", true):
				_fail_once(weapon_id + " reload preview changed gameplay/model field " + key)
		if not player.get_node("Mannequin").call("notify_operator_weapon_equipped", config):
			_fail_once(weapon_id + " candidate presentation handoff refused")
			return
		await _frames(90)
		print("GENERIC_RELOAD_IN_MEMORY_CANDIDATE ", weapon_id, " ", entry.candidate_rig)
	await super._check_stance(stance)


func _measure_reload(label: String, frame: int) -> void:
	super._measure_reload(label, frame)
	var pose: Node3D = driver.get("weapon_pose_solver")
	var stock_active := bool(pose.get("authored_shoulder_stock_active"))
	var action: StringName = driver.get("requested_action")
	var posture: StringName = driver.get("posture")
	if stock_active and (posture == &"PRONE" or action != &""):
		_fail_once(label + " authored shoulder stock leaked into prone/reload ownership")
	var row: Dictionary = reload_rows[-1]
	row["authored_stock_active"] = stock_active
	row["posture"] = String(posture)
	if label.ends_with("_complete") and frame >= 20 and float(row.physical_support_error_m) > 0.01:
		_fail_once(label + " completed support regrip exceeds10 mm")
