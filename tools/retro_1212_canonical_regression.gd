extends "res://tools/firearm_family_transition_regression.gd"
## Actual-input canonical proof for only the two confirmed 1212 models.
## Default checks saved runtime assignments. --use-candidate loads the saved
## unassigned calibration through the normal Equipment presentation handoff.
const VisualContract := preload("res://scripts/labs/gunsmith2/weapon_visual_rig_contract.gd")
const MODEL_BY_ID := {
	"9mm_sub":"res://assets/weapons/retro_1212/uzi_candidate.scn",
	"870":"res://assets/weapons/retro_1212/pump_candidate.scn",
}

func _initialize() -> void:
	super._initialize()
	if selected_ids.is_empty():
		selected_ids.assign(["9mm_sub","870"])
	if output_prefix == "/private/tmp/firearm-family-transitions":
		output_prefix = "/private/tmp/retro1212-canonical"

func _check_stance(stance: int) -> void:
	if weapon_id not in MODEL_BY_ID:
		_fail_once("No confirmed 1212 model for " + weapon_id)
		return
	if stance == 0 and "--use-candidate" in OS.get_cmdline_user_args():
		var path := "res://art_source/retro1212_calibration/"+weapon_id+".runtime_candidate.json"
		var candidate: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
		candidate.status = "published" # In-memory fixture only; never writes a published document.
		var raw := Contract.load_config("res://config/weapons/"+weapon_id+".json")
		var merged := VisualContract.merge_for_presentation(raw,candidate)
		merged.erase("visual_rig_id")
		var config := Contract.normalize_config(merged,"res://config/weapons/"+weapon_id+".json")
		for key in ["ballistics","fire_modes","default_fire_mode","burst_size","weapon_id"]:
			if JSON.stringify(raw.get(key),"",true) != JSON.stringify(config.get(key),"",true):
				_fail_once(weapon_id+" candidate changed protected gameplay field "+key)
		if not player.get_node("Mannequin").call("notify_operator_weapon_equipped",config):
			_fail_once(weapon_id+" candidate canonical presentation handoff refused")
		await _frames(90)
		print("RETRO1212_IN_MEMORY_CANDIDATE ",weapon_id," hash=",FileAccess.get_sha256(path))
	var resolved: Dictionary = driver.get("equipped_weapon_config")
	if String(resolved.get("model_fbx","")) != MODEL_BY_ID[weapon_id]:
		_fail_once(weapon_id+" canonical model is not the verified 1212 artifact")
	await super._check_stance(stance)
