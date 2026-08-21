class_name GunsmithHitboxModel
extends RefCounted

## Mutable hitbox authoring model. Gunsmith UI renders this state; the shared
## hurtbox profile remains the normalization and persistence authority.

const HurtboxProfile := preload("res://scripts/combat/socom_hurtbox_profile.gd")

var scales: Dictionary
var geometry: Dictionary
var custom_hitboxes: Array[Dictionary]


func configure(
	scale_data: Dictionary,
	geometry_data: Dictionary,
	custom_data: Array[Dictionary]
) -> void:
	scales = scale_data
	geometry = geometry_data
	custom_hitboxes = custom_data


func editable_ids() -> Array[StringName]:
	var result: Array[StringName] = HurtboxProfile.REGION_KEYS.duplicate()
	for entry: Dictionary in custom_hitboxes:
		result.append(StringName(entry.get("id", &"")))
	return result


func custom_index(editor_id: StringName) -> int:
	for index in custom_hitboxes.size():
		if StringName(custom_hitboxes[index].get("id", &"")) == editor_id:
			return index
	return -1


func source_region(editor_id: StringName) -> StringName:
	var index := custom_index(editor_id)
	return StringName(custom_hitboxes[index].get("source_region", &"torso")) if index >= 0 else editor_id


func damage_type(editor_id: StringName) -> StringName:
	var index := custom_index(editor_id)
	if index >= 0:
		return StringName(custom_hitboxes[index].get(
			"damage_region",
			HurtboxProfile.damage_type_for_source_region(source_region(editor_id))
		))
	return HurtboxProfile.damage_type_for_source_region(editor_id)


func display_name(editor_id: StringName) -> String:
	var index := custom_index(editor_id)
	if index >= 0:
		return String(custom_hitboxes[index].get(
			"display_name",
			"%s extra" % HurtboxProfile.region_label(source_region(editor_id))
		))
	return HurtboxProfile.region_label(editor_id)


func width(editor_id: StringName) -> float:
	var index := custom_index(editor_id)
	var value: Variant = (
		custom_hitboxes[index].get("width_scale", 1.0)
		if index >= 0
		else scales.get(editor_id, 1.0)
	)
	return clampf(float(value), HurtboxProfile.MIN_SCALE, HurtboxProfile.MAX_SCALE)


func set_width(editor_id: StringName, value: float) -> void:
	var bounded := clampf(value, HurtboxProfile.MIN_SCALE, HurtboxProfile.MAX_SCALE)
	var index := custom_index(editor_id)
	if index >= 0:
		custom_hitboxes[index]["width_scale"] = bounded
	else:
		scales[editor_id] = bounded


func geometry_for(editor_id: StringName) -> Dictionary:
	var index := custom_index(editor_id)
	var entry: Dictionary = (
		(custom_hitboxes[index].get("geometry", {}) as Dictionary).duplicate(true)
		if index >= 0
		else (geometry.get(editor_id, {}) as Dictionary).duplicate(true)
	)
	return {editor_id: entry}


func set_geometry(editor_id: StringName, entry: Dictionary) -> void:
	var index := custom_index(editor_id)
	if index >= 0:
		custom_hitboxes[index]["geometry"] = entry.duplicate(true)
	else:
		geometry[editor_id] = entry.duplicate(true)


func offset(editor_id: StringName) -> Vector3:
	return HurtboxProfile.geometry_offset(geometry_for(editor_id), editor_id)


func shape(editor_id: StringName) -> StringName:
	return HurtboxProfile.geometry_shape(geometry_for(editor_id), editor_id)


func length(editor_id: StringName) -> float:
	return HurtboxProfile.geometry_length_scale(geometry_for(editor_id), editor_id)


func set_offset(editor_id: StringName, value: Vector3) -> void:
	var geometry_document := geometry_for(editor_id)
	HurtboxProfile.set_geometry_offset(geometry_document, editor_id, value)
	set_geometry(editor_id, geometry_document[editor_id])


func duplicate_hitbox(editor_id: StringName) -> StringName:
	var region := source_region(editor_id)
	var new_id := _next_custom_id(region)
	var entry := (geometry_for(editor_id)[editor_id] as Dictionary).duplicate(true)
	var copied_offset := HurtboxProfile.geometry_offset({new_id: entry}, new_id)
	copied_offset.x += 0.025 if copied_offset.x <= HurtboxProfile.MAX_OFFSET_METERS - 0.025 else -0.025
	entry["offset"] = {"x": copied_offset.x, "y": copied_offset.y, "z": copied_offset.z}
	custom_hitboxes.append({
		"id": String(new_id),
		"source_region": String(region),
		"damage_region": String(damage_type(editor_id)),
		"display_name": "%s extra" % HurtboxProfile.region_label(region),
		"width_scale": width(editor_id),
		"geometry": entry,
	})
	custom_hitboxes = HurtboxProfile.normalize_custom_hitboxes(custom_hitboxes)
	return new_id


func delete_custom(editor_id: StringName) -> StringName:
	var index := custom_index(editor_id)
	if index < 0:
		return &""
	var region := StringName(custom_hitboxes[index].get("source_region", &"torso"))
	custom_hitboxes.remove_at(index)
	return region


func set_damage_type(editor_id: StringName, damage_region: StringName) -> bool:
	var index := custom_index(editor_id)
	if index < 0 or damage_region not in HurtboxProfile.DAMAGE_TYPE_KEYS:
		return false
	custom_hitboxes[index]["damage_region"] = String(damage_region)
	return true


func snap_to_rig(editor_id: StringName) -> void:
	var defaults := HurtboxProfile.default_geometry()
	var region := source_region(editor_id)
	var snapped := (defaults[region] as Dictionary).duplicate(true)
	snapped["shape"] = String(shape(editor_id))
	set_geometry(editor_id, snapped)


func align_builtins_to_rig() -> void:
	var aligned := HurtboxProfile.default_geometry()
	for region: StringName in HurtboxProfile.REGION_KEYS:
		(aligned[region] as Dictionary)["shape"] = String(
			HurtboxProfile.geometry_shape(geometry, region)
		)
	geometry = aligned


func _next_custom_id(source_region: StringName) -> StringName:
	var suffix := 1
	while true:
		var candidate := StringName("%s_extra_%d" % [String(source_region), suffix])
		if candidate not in editable_ids():
			return candidate
		suffix += 1
	return &"extra_hitbox"
