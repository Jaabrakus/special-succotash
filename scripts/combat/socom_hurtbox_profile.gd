class_name SocomHurtboxProfile
extends RefCounted

## Canonical anatomical tuning shared by the Composure Lab, the local target
## range, and future network player hurtbox components. Camera obstruction and
## CharacterBody movement collision intentionally do not use this profile.

const CONFIG_PATH := "res://config/combat/hurtbox_profile.json"
const CURRENT_SCHEMA_VERSION := 6
const PlaytestStateCollector := preload("res://scripts/runtime/playtest_state_collector.gd")
const MIN_SCALE := 0.45
const MAX_SCALE := 1.0
const MIN_LENGTH_SCALE := 0.35
const MAX_LENGTH_SCALE := 1.0
const MAX_OFFSET_METERS := 0.12
const SHAPE_KEYS: Array[StringName] = [&"capsule", &"sphere", &"box"]
const SHAPE_LABELS := {
	&"capsule": "Capsule",
	&"sphere": "Sphere",
	&"box": "Box",
}

# A duplicated shape keeps its bone anchor but can be painted with a gameplay
# damage identity. These broad identities are intentional: left/right placement
# belongs to the animated anchor, while damage rules only need anatomy class.
const DAMAGE_TYPE_KEYS: Array[StringName] = [
	&"HEAD", &"NECK", &"TORSO", &"PELVIS", &"ARM", &"LEG", &"FOOT",
]
const DAMAGE_TYPE_LABELS := {
	&"HEAD": "Head",
	&"NECK": "Neck",
	&"TORSO": "Torso",
	&"PELVIS": "Pelvis",
	&"ARM": "Arm",
	&"LEG": "Leg",
	&"FOOT": "Foot",
}

const REGION_KEYS: Array[StringName] = [
	&"head",
	&"neck",
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
	&"neck": "Neck",
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
	&"head": [&"head", &"neck"],
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
	var document := _load_profile_document()
	if document.is_empty():
		return result
	var source: Dictionary = document.get("radius_scales", {})
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
			"shape": String(default_shape_for_region(region_key)),
			"offset": {
				"x": default_offset.x,
				"y": default_offset.y,
				"z": default_offset.z,
			},
			"length_scale": 1.0,
		}
	return result


static func load_geometry() -> Dictionary:
	var document := _load_profile_document()
	if document.is_empty():
		return default_geometry()
	return normalize_geometry(document.get("geometry", {}))


static func load_custom_hitboxes() -> Array[Dictionary]:
	var document := _load_profile_document()
	if document.is_empty():
		return []
	return normalize_custom_hitboxes(document.get("custom_hitboxes", []))


static func _load_profile_document() -> Dictionary:
	var bundled := PlaytestStateCollector.bundled_state("hurtboxes")
	if not bundled.is_empty():
		return bundled
	if not FileAccess.file_exists(CONFIG_PATH):
		return {}
	var file := FileAccess.open(CONFIG_PATH, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	return (parsed as Dictionary) if parsed is Dictionary else {}


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
		var shape_kind := StringName(source_entry.get(
			"shape",
			default_shape_for_region(region_key)
		))
		if shape_kind not in SHAPE_KEYS:
			shape_kind = default_shape_for_region(region_key)
		(normalized[region_key] as Dictionary)["shape"] = String(shape_kind)
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


static func normalize_custom_hitboxes(raw_hitboxes: Variant) -> Array[Dictionary]:
	var normalized: Array[Dictionary] = []
	if not raw_hitboxes is Array:
		return normalized
	var used_ids: Dictionary = {}
	for raw_entry: Variant in raw_hitboxes:
		if not raw_entry is Dictionary:
			continue
		var source_entry := raw_entry as Dictionary
		var source_region := StringName(source_entry.get("source_region", &""))
		if source_region not in REGION_KEYS:
			continue
		var damage_region := StringName(source_entry.get(
			"damage_region",
			damage_type_for_source_region(source_region)
		))
		if damage_region not in DAMAGE_TYPE_KEYS:
			damage_region = damage_type_for_source_region(source_region)
		var editor_id := StringName(source_entry.get("id", &""))
		if editor_id == &"" or editor_id in REGION_KEYS or used_ids.has(editor_id):
			continue
		used_ids[editor_id] = true
		var raw_geometry: Variant = source_entry.get("geometry", {})
		var geometry_map := {source_region: raw_geometry if raw_geometry is Dictionary else {}}
		var normalized_geometry := normalize_geometry(geometry_map)
		normalized.append({
			"id": String(editor_id),
			"source_region": String(source_region),
			"damage_region": String(damage_region),
			"display_name": String(source_entry.get(
				"display_name",
				"%s extra" % region_label(source_region)
			)),
			"width_scale": clampf(
				float(source_entry.get("width_scale", 1.0)),
				MIN_SCALE,
				MAX_SCALE
			),
			"geometry": (normalized_geometry[source_region] as Dictionary).duplicate(true),
		})
	return normalized


static func damage_type_label(damage_type: StringName) -> String:
	return String(DAMAGE_TYPE_LABELS.get(damage_type, String(damage_type).capitalize()))


static func shape_label(shape_kind: StringName) -> String:
	return String(SHAPE_LABELS.get(shape_kind, String(shape_kind).capitalize()))


static func default_shape_for_region(region_key: StringName) -> StringName:
	return (
		&"sphere"
		if region_key in [&"head", &"left_foot", &"right_foot"]
		else &"capsule"
	)


static func damage_type_for_source_region(source_region: StringName) -> StringName:
	var text := String(source_region)
	if text == "head":
		return &"HEAD"
	if text == "neck":
		return &"NECK"
	if text == "torso":
		return &"TORSO"
	if text == "pelvis":
		return &"PELVIS"
	if "arm" in text or "forearm" in text:
		return &"ARM"
	if "foot" in text:
		return &"FOOT"
	return &"LEG"


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


static func geometry_shape(geometry: Dictionary, region_key: StringName) -> StringName:
	var entry: Dictionary = geometry.get(region_key, geometry.get(String(region_key), {}))
	var shape_kind := StringName(entry.get("shape", default_shape_for_region(region_key)))
	return shape_kind if shape_kind in SHAPE_KEYS else default_shape_for_region(region_key)


static func set_geometry_shape(
	geometry: Dictionary,
	region_key: StringName,
	shape_kind: StringName
) -> void:
	if shape_kind not in SHAPE_KEYS:
		return
	var entry: Dictionary = geometry.get(region_key, {
		"offset": {"x": 0.0, "y": 0.0, "z": 0.0},
		"length_scale": 1.0,
	})
	entry["shape"] = String(shape_kind)
	geometry[region_key] = entry


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
	return save_profile(scales, load_geometry(), load_custom_hitboxes())


static func save_geometry(geometry: Dictionary) -> bool:
	return save_profile(load_scales(), geometry, load_custom_hitboxes())


static func save_profile(
	scales: Dictionary,
	geometry: Dictionary,
	custom_hitboxes: Variant = null
) -> bool:
	var normalized_scales := normalize_scales(scales)
	var normalized_geometry := normalize_geometry(geometry)
	var normalized_custom := normalize_custom_hitboxes(
		load_custom_hitboxes() if custom_hitboxes == null else custom_hitboxes
	)
	var directory_error := DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(CONFIG_PATH.get_base_dir())
	)
	if directory_error != OK and directory_error != ERR_ALREADY_EXISTS:
		return false
	var file := FileAccess.open(CONFIG_PATH, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify({
		"schema_version": CURRENT_SCHEMA_VERSION,
		"purpose": "Authored by the Composure Lab and loaded by all anatomical damage rigs; not camera or movement collision",
		"radius_scales": normalized_scales,
		"geometry": normalized_geometry,
		"custom_hitboxes": normalized_custom,
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
