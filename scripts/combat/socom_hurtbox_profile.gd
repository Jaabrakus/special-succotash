class_name SocomHurtboxProfile
extends RefCounted

## Canonical anatomical tuning shared by the Composure Lab, the local target
## range, and future network player hurtbox components. Camera obstruction and
## CharacterBody movement collision intentionally do not use this profile.

const CONFIG_PATH := "res://config/combat/hurtbox_profile.json"
const MIN_SCALE := 0.45
const MAX_SCALE := 1.25
const MIN_LENGTH_SCALE := 0.35
const MAX_LENGTH_SCALE := 1.65
const MAX_OFFSET_METERS := 0.35

const REGION_KEYS: Array[StringName] = [
	&"head",
	&"torso",
	&"pelvis",
	&"left_upper_arm",
	&"right_upper_arm",
	&"left_forearm",
	&"right_forearm",
	&"left_thigh",
	&"right_thigh",
	&"left_calf",
	&"right_calf",
	&"left_foot",
	&"right_foot",
]

const REGION_LABELS := {
	&"head": "Head",
	&"torso": "Torso",
	&"pelvis": "Pelvis",
	&"left_upper_arm": "Left upper arm",
	&"right_upper_arm": "Right upper arm",
	&"left_forearm": "Left forearm",
	&"right_forearm": "Right forearm",
	&"left_thigh": "Left thigh",
	&"right_thigh": "Right thigh",
	&"left_calf": "Left calf",
	&"right_calf": "Right calf",
	&"left_foot": "Left foot",
	&"right_foot": "Right foot",
}

const LEGACY_GROUP_REGIONS := {
	&"head": [&"head"],
	&"torso": [&"torso", &"pelvis"],
	&"arms": [
		&"left_upper_arm", &"right_upper_arm",
		&"left_forearm", &"right_forearm",
	],
	&"legs": [
		&"left_thigh", &"right_thigh",
		&"left_calf", &"right_calf",
		&"left_foot", &"right_foot",
	],
}


static func default_scales() -> Dictionary:
	var result := {
		"global": 0.88,
		"head": 1.0,
		"torso": 1.0,
		"arms": 1.0,
		"legs": 1.0,
	}
	for key in REGION_KEYS:
		result[key] = 1.0
	return result


static func load_scales() -> Dictionary:
	var result := default_scales()
	if not FileAccess.file_exists(CONFIG_PATH):
		return result
	var file := FileAccess.open(CONFIG_PATH, FileAccess.READ)
	if file == null:
		return result
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		return result
	var source: Dictionary = parsed.get("radius_scales", {})
	return normalize_scales(source)


static func default_geometry() -> Dictionary:
	var result: Dictionary = {}
	for region_key in REGION_KEYS:
		var default_offset := Vector3.ZERO
		if region_key == &"torso":
			# The torso capsule is wider than the short Spine-to-Neck bone span.
			# Lower its center so its rounded top meets, but does not cover, the head.
			default_offset.y = -0.08
		result[region_key] = {
			"offset": {
				"x": default_offset.x,
				"y": default_offset.y,
				"z": default_offset.z,
			},
			"length_scale": 1.0,
		}
	return result


static func load_geometry() -> Dictionary:
	if not FileAccess.file_exists(CONFIG_PATH):
		return default_geometry()
	var file := FileAccess.open(CONFIG_PATH, FileAccess.READ)
	if file == null:
		return default_geometry()
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		return default_geometry()
	return normalize_geometry((parsed as Dictionary).get("geometry", {}))


static func normalize_scales(scales: Dictionary) -> Dictionary:
	var normalized := default_scales()
	for key in [&"global", &"head", &"torso", &"arms", &"legs"]:
		if _has_key(scales, key):
			normalized[key] = _scale_value(scales, key, float(normalized[key]))

	# Profiles written before per-region editing inherit their family value.
	# Once an exact region exists it wins, so the new UI can tune one body part
	# without silently resizing its mirrored limb or its entire family.
	for region_key in REGION_KEYS:
		var fallback_group := group_for_region(region_key)
		var fallback := float(normalized.get(fallback_group, 1.0))
		normalized[region_key] = _scale_value(scales, region_key, fallback)
	return normalized


static func normalize_geometry(geometry: Dictionary) -> Dictionary:
	var normalized := default_geometry()
	for region_key in REGION_KEYS:
		var source: Variant = geometry.get(region_key, geometry.get(String(region_key), {}))
		if not source is Dictionary:
			continue
		var source_entry := source as Dictionary
		var source_offset: Variant = source_entry.get("offset", {})
		if source_offset is Dictionary:
			var offset_data := source_offset as Dictionary
			(normalized[region_key] as Dictionary)["offset"] = {
				"x": clampf(float(offset_data.get("x", geometry_offset(normalized, region_key).x)), -MAX_OFFSET_METERS, MAX_OFFSET_METERS),
				"y": clampf(float(offset_data.get("y", geometry_offset(normalized, region_key).y)), -MAX_OFFSET_METERS, MAX_OFFSET_METERS),
				"z": clampf(float(offset_data.get("z", geometry_offset(normalized, region_key).z)), -MAX_OFFSET_METERS, MAX_OFFSET_METERS),
			}
		(normalized[region_key] as Dictionary)["length_scale"] = clampf(
			float(source_entry.get("length_scale", 1.0)),
			MIN_LENGTH_SCALE,
			MAX_LENGTH_SCALE
		)
	return normalized


static func geometry_offset(geometry: Dictionary, region_key: StringName) -> Vector3:
	var entry: Dictionary = geometry.get(region_key, geometry.get(String(region_key), {}))
	var offset: Dictionary = entry.get("offset", {})
	return Vector3(
		float(offset.get("x", 0.0)),
		float(offset.get("y", 0.0)),
		float(offset.get("z", 0.0))
	).clamp(
		Vector3.ONE * -MAX_OFFSET_METERS,
		Vector3.ONE * MAX_OFFSET_METERS
	)


static func set_geometry_offset(
	geometry: Dictionary,
	region_key: StringName,
	offset: Vector3
) -> void:
	var entry: Dictionary = geometry.get(region_key, {
		"offset": {},
		"length_scale": 1.0,
	})
	var bounded := offset.clamp(
		Vector3.ONE * -MAX_OFFSET_METERS,
		Vector3.ONE * MAX_OFFSET_METERS
	)
	entry["offset"] = {"x": bounded.x, "y": bounded.y, "z": bounded.z}
	geometry[region_key] = entry


static func geometry_length_scale(geometry: Dictionary, region_key: StringName) -> float:
	var entry: Dictionary = geometry.get(region_key, geometry.get(String(region_key), {}))
	return clampf(
		float(entry.get("length_scale", 1.0)),
		MIN_LENGTH_SCALE,
		MAX_LENGTH_SCALE
	)


static func set_geometry_length_scale(
	geometry: Dictionary,
	region_key: StringName,
	value: float
) -> void:
	var entry: Dictionary = geometry.get(region_key, {
		"offset": {"x": 0.0, "y": 0.0, "z": 0.0},
		"length_scale": 1.0,
	})
	entry["length_scale"] = clampf(value, MIN_LENGTH_SCALE, MAX_LENGTH_SCALE)
	geometry[region_key] = entry


static func group_for_region(region_key: StringName) -> StringName:
	for group_key: StringName in LEGACY_GROUP_REGIONS:
		if region_key in LEGACY_GROUP_REGIONS[group_key]:
			return group_key
	return &"legs"


static func set_group_scale(scales: Dictionary, group_key: StringName, value: float) -> void:
	var normalized_value := clampf(value, MIN_SCALE, MAX_SCALE)
	scales[group_key] = normalized_value
	for region_key: StringName in LEGACY_GROUP_REGIONS.get(group_key, []):
		scales[region_key] = normalized_value


static func region_scale_key(region: StringName) -> StringName:
	return StringName(String(region).to_lower())


static func region_label(region_key: StringName) -> String:
	return String(REGION_LABELS.get(region_key, String(region_key).capitalize()))


static func save_scales(scales: Dictionary) -> bool:
	return save_profile(scales, load_geometry())


static func save_geometry(geometry: Dictionary) -> bool:
	return save_profile(load_scales(), geometry)


static func save_profile(scales: Dictionary, geometry: Dictionary) -> bool:
	var normalized_scales := normalize_scales(scales)
	var normalized_geometry := normalize_geometry(geometry)
	var directory_error := DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(CONFIG_PATH.get_base_dir())
	)
	if directory_error != OK and directory_error != ERR_ALREADY_EXISTS:
		return false
	var file := FileAccess.open(CONFIG_PATH, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify({
		"schema_version": 3,
		"purpose": "Authored by the Composure Lab and loaded by all anatomical damage rigs; not camera or movement collision",
		"radius_scales": normalized_scales,
		"geometry": normalized_geometry,
	}, "  "))
	file.close()
	return true


static func _has_key(scales: Dictionary, key: StringName) -> bool:
	return scales.has(key) or scales.has(String(key))


static func _scale_value(scales: Dictionary, key: StringName, fallback: float) -> float:
	return clampf(
		float(scales.get(key, scales.get(String(key), fallback))),
		MIN_SCALE,
		MAX_SCALE
	)
