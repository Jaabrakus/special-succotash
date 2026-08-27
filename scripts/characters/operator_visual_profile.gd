class_name SocomOperatorVisualProfile
extends RefCounted

## Versioned character-art contract. This profile does not own gameplay,
## collision, hurtboxes, animation state, or weapon authority.

const Normalizer := preload("res://scripts/characters/operator_model_normalizer.gd")
const SCHEMA_VERSION := 2
const SKELETON_CONTRACT := "SOCOM_OPERATOR_CORE_V1"
const PROFILE_DIRECTORY := "res://config/operators"


static func from_validation(model_path: String, report: Dictionary) -> Dictionary:
	var profile_id := _slug(model_path.get_file().get_basename())
	var normalization := Normalizer.profile_data(report.get("normalization", {}) as Dictionary)
	var rotation: Dictionary = normalization.get(
		"rotation_degrees",
		{"x": 0.0, "y": 0.0, "z": 0.0}
	)
	var position: Dictionary = normalization.get(
		"position",
		{"x": 0.0, "y": 0.0, "z": 0.0}
	)
	return {
		"schema_version": SCHEMA_VERSION,
		"profile_id": profile_id,
		"display_name": model_path.get_file().get_basename().replace("_", " "),
		"model_path": model_path,
		"status": "APPROVED_FOR_CONVERSION",
		"skeleton_contract": SKELETON_CONTRACT,
		"source_skeleton": String(report.get("skeleton_name", "")),
		"source_bone_count": int(report.get("bone_count", 0)),
		"bone_map": (report.get("bone_map", {}) as Dictionary).duplicate(true),
		"requires_canonical_conversion": bool(report.get("requires_canonical_conversion", true)),
		"transform": {
			"scale": float(normalization.get("scale", 1.0)),
			"rotation_degrees": rotation.duplicate(true),
			"position": position.duplicate(true),
		},
		"normalization": normalization,
		"material_slots": (report.get("material_slots", []) as Array).duplicate(true),
		"validation": {
			"compatible": bool(report.get("compatible", false)),
			"warnings": (report.get("warnings", []) as Array).duplicate(),
		},
		"updated_at": Time.get_datetime_string_from_system(false, true),
	}


static func save(profile: Dictionary) -> Dictionary:
	if profile.is_empty() or not bool((profile.get("validation", {}) as Dictionary).get("compatible", false)):
		return {"ok": false, "error": "The model has not passed validation."}
	var profile_id := _slug(String(profile.get("profile_id", "operator")))
	var directory_path := ProjectSettings.globalize_path(PROFILE_DIRECTORY)
	var directory_error := DirAccess.make_dir_recursive_absolute(directory_path)
	if directory_error != OK:
		return {"ok": false, "error": error_string(directory_error)}
	var path := "%s/%s.json" % [PROFILE_DIRECTORY, profile_id]
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "error": "Could not open the profile path for writing."}
	file.store_string(JSON.stringify(profile, "  "))
	return {"ok": true, "path": path}


static func _slug(value: String) -> String:
	var result := ""
	for character in value.to_lower():
		result += character if character.is_valid_identifier() or character.is_valid_int() else "_"
	while "__" in result:
		result = result.replace("__", "_")
	result = result.trim_prefix("_").trim_suffix("_")
	return result if not result.is_empty() else "operator"
