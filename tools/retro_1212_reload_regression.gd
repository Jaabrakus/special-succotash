extends "res://tools/reload_trigger_attachment_regression.gd"

## Unassigned geometry candidate uses the existing equipment presentation API.
const VisualContract := preload("res://scripts/labs/gunsmith2/weapon_visual_rig_contract.gd")

func _check_stance(stance: int) -> void:
	if weapon_id not in ["9mm_sub", "870"]:
		_fail_once("1212 reload proof only covers the two prepared model candidates")
		return
	if stance == 0:
		var candidate: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://art_source/retro1212_calibration/%s.runtime_candidate.json" % weapon_id))
		candidate.status = "published"
		var raw := Contract.load_config("res://config/weapons/%s.json" % weapon_id)
		var merged := VisualContract.merge_for_presentation(raw, candidate)
		merged.erase("visual_rig_id")
		if not player.get_node("Mannequin").call("notify_operator_weapon_equipped",Contract.normalize_config(merged)):
			_fail_once("1212 canonical presentation handoff refused")
		await _frames(90)
	await super._check_stance(stance)
