class_name SocomMapCommandService
extends RefCounted

## One command surface for both the visual Map Lab and automation/LLM tooling.
## Callers submit plain Dictionaries and receive a new normalized document.

const MapDocument := preload("res://scripts/maps/socom_map_document.gd")
const MapAssetLibrary := preload("res://scripts/maps/socom_map_asset_library.gd")

const COMMANDS := {
	"place_object": "Create an object using type, position, optional size, name, and id.",
	"place_on_object": "Create an object resting on the top surface of another object id.",
	"place_prefab": "Create a validated reusable group such as tactical_room, guard_tower, or checkpoint.",
	"transform_object": "Change position, rotation_degrees, and/or size for an object id.",
	"duplicate_object": "Copy an object id with an optional offset and new_id.",
	"duplicate_group": "Copy every object sharing a group_id while preserving relative placement.",
	"scale_group": "Uniformly scale every object and relative offset in a group around its center.",
	"assign_group": "Assign one object to a reusable group_id.",
	"attach_object": "Attach one object to another so parent movement and rotation carry the child.",
	"detach_object": "Detach an object while preserving its current map transform.",
	"delete_object": "Delete one object by id.",
	"rename_object": "Give one object a human-readable name.",
	"set_object_properties": "Safely merge type-specific properties such as light energy or ambience audio_stream.",
	"set_object_color": "Set an object's saved material or light color.",
	"set_map_name": "Change the map name.",
	"set_grid_size": "Change placement snapping from 0.125 to 4 meters.",
	"apply_environment_preset": "Apply a complete authored atmosphere preset by name.",
	"set_environment": "Change individual atmosphere fields such as sun_energy, fog_density, or exposure.",
	"set_gameplay": "Configure mode, round time, maximum rounds, rounds to win, win conditions, bomb timing, and respawns.",
}


static func describe_capabilities() -> Dictionary:
	return {
		"schema_version": MapDocument.SCHEMA_VERSION,
		"map_path": MapDocument.ACTIVE_MAP_PATH,
		"commands": COMMANDS.duplicate(true),
		"object_types": Array(MapDocument.SUPPORTED_TYPES),
		"prefabs": MapDocument.PREFAB_DEFINITIONS.keys(),
		"coordinates": "Godot meters: +X right, +Y up, -Z forward",
		"safety": "Commands are validated, return a new document, and never save implicitly.",
	}


static func apply(document: Dictionary, command: Dictionary) -> Dictionary:
	var working := MapDocument.normalize(document)
	if working.is_empty():
		working = MapDocument.new_document()
	var command_name := String(command.get("command", ""))
	var result := {
		"ok": false,
		"message": "Unknown map command: %s" % command_name,
		"affected_id": "",
		"document": working,
	}
	match command_name:
		"place_object":
			result = _place_object(working, command)
		"place_on_object":
			result = _place_on_object(working, command)
		"place_prefab":
			result = _place_prefab(working, command)
		"transform_object":
			result = _transform_object(working, command)
		"duplicate_object":
			result = _duplicate_object(working, command)
		"duplicate_group":
			result = _duplicate_group(working, command)
		"scale_group":
			result = _scale_group(working, command)
		"assign_group":
			result = _assign_group(working, command)
		"attach_object":
			result = _attach_object(working, command)
		"detach_object":
			result = _detach_object(working, command)
		"delete_object":
			result = _delete_object(working, command)
		"rename_object":
			result = _rename_object(working, command)
		"set_object_properties":
			result = _set_object_properties(working, command)
		"set_object_color":
			result = _set_object_color(working, command)
		"set_map_name":
			working["name"] = String(command.get("name", "Untitled Tactical Map")).strip_edges()
			if String(working["name"]).is_empty():
				working["name"] = "Untitled Tactical Map"
			result = _success(working, "", "Renamed map to %s" % working["name"])
		"set_grid_size":
			working["grid_size"] = clampf(float(command.get("grid_size", 0.5)), 0.125, 4.0)
			result = _success(working, "", "Grid snap is %.3f m" % working["grid_size"])
		"apply_environment_preset":
			var preset_name := String(command.get("preset", "tactical_overcast"))
			if not MapDocument.ENVIRONMENT_PRESETS.has(preset_name):
				result = _failure(working, "Unknown environment preset: %s" % preset_name)
			else:
				working["environment"] = MapDocument.environment_from_preset(preset_name)
				result = _success(working, "", "Applied %s atmosphere" % MapDocument.ENVIRONMENT_PRESETS[preset_name]["label"])
		"set_environment":
			result = _set_environment(working, command)
		"set_gameplay":
			result = _set_gameplay(working, command)
	return result


static func validate_document(document: Dictionary) -> Dictionary:
	var errors: Array[String] = []
	var warnings: Array[String] = []
	var normalized := MapDocument.normalize(document)
	if normalized.is_empty():
		errors.append("Map document is empty or invalid.")
		return {"ok": false, "errors": errors, "warnings": warnings}
	var ids: Dictionary = {}
	var spawn_count := 0
	var type_counts: Dictionary = {}
	for object: Dictionary in normalized.get("objects", []):
		var object_id := String(object.get("id", ""))
		if ids.has(object_id):
			errors.append("Duplicate object id: %s" % object_id)
		ids[object_id] = true
		if String(object.get("type", "")) == "player_spawn":
			spawn_count += 1
		var type_name := String(object.get("type", ""))
		type_counts[type_name] = int(type_counts.get(type_name, 0)) + 1
		if type_name == "imported_asset":
			var properties: Dictionary = object.get("properties", {})
			var asset_path := String(properties.get("asset_path", ""))
			if not MapAssetLibrary.asset_exists(asset_path):
				errors.append("Imported asset is missing or unsafe: %s" % asset_path)
			if String(properties.get("collision_mode", "box")) not in ["none", "box", "detailed_mesh"]:
				errors.append("Imported asset has an invalid collision mode: %s" % object_id)
	if spawn_count == 0:
		errors.append("Map needs one Player Spawn.")
	elif spawn_count > 1:
		warnings.append("Map has %d Player Spawns; gameplay uses the first one." % spawn_count)
	if normalized.get("objects", []).size() > 500:
		warnings.append("Map has more than 500 objects; combine large blockout surfaces when possible.")
	var gameplay: Dictionary = normalized.get("gameplay", {})
	var supported_modes: Array = gameplay.get("supported_modes", [])
	if "team_deathmatch" in supported_modes or "demolition" in supported_modes:
		for required_spawn in ["team_alpha_spawn", "team_bravo_spawn"]:
			if int(type_counts.get(required_spawn, 0)) == 0:
				errors.append("SOCOM team map needs %s." % required_spawn)
	if "demolition" in supported_modes:
		for required_objective in ["bomb_pickup", "alpha_bomb_site", "bravo_bomb_site"]:
			if int(type_counts.get(required_objective, 0)) == 0:
				errors.append("Demolition map needs %s." % required_objective)
	return {"ok": errors.is_empty(), "errors": errors, "warnings": warnings}


static func _place_object(document: Dictionary, command: Dictionary) -> Dictionary:
	var type_name := StringName(command.get("type", "wall"))
	if type_name not in MapDocument.SUPPORTED_TYPES:
		return _failure(document, "Unsupported object type: %s" % type_name)
	var position := _command_vector(command.get("position", {}), Vector3.ZERO)
	var size := _command_vector(command.get("size", {}), Vector3.ZERO)
	var object := MapDocument.make_object(type_name, position, size)
	var requested_id := String(command.get("id", "")).strip_edges()
	if not requested_id.is_empty():
		if _find_object_index(document, requested_id) >= 0:
			return _failure(document, "Object id already exists: %s" % requested_id)
		object["id"] = requested_id
	var requested_name := String(command.get("name", "")).strip_edges()
	if not requested_name.is_empty():
		object["name"] = requested_name
	if command.get("properties", {}) is Dictionary:
		var merged_properties: Dictionary = object.get("properties", {}).duplicate(true)
		merged_properties.merge(command.get("properties", {}), true)
		object["properties"] = merged_properties
	if command.has("color"):
		object["color"] = MapDocument.color_to_data(MapDocument.data_to_color(command.get("color", {}), MapDocument.data_to_color(object.get("color", {}))))
	(document["objects"] as Array).append(object)
	return _success(document, String(object["id"]), "Placed %s" % object["name"])


static func _place_on_object(document: Dictionary, command: Dictionary) -> Dictionary:
	var target_id := String(command.get("target_id", ""))
	var target_index := _find_object_index(document, target_id)
	if target_index < 0:
		return _failure(document, "Surface object not found: %s" % target_id)
	var target := (document["objects"] as Array)[target_index] as Dictionary
	var target_position := MapDocument.data_to_vector(target.get("position", {}))
	var target_size := MapDocument.data_to_vector(target.get("size", {}), Vector3.ONE)
	var type_name := StringName(command.get("type", "wall"))
	if type_name not in MapDocument.SUPPORTED_TYPES:
		return _failure(document, "Unsupported object type: %s" % type_name)
	var requested_size := _command_vector(command.get("size", {}), Vector3.ZERO)
	var placed_size: Vector3 = requested_size if not requested_size.is_zero_approx() else MapDocument.TYPE_DEFAULTS[type_name]["size"]
	var horizontal := _command_vector(command.get("offset", {}), Vector3.ZERO)
	var placement := target_position + horizontal
	placement.y = target_position.y + target_size.y * 0.5 + placed_size.y * 0.5
	var place_command := command.duplicate(true)
	place_command["command"] = "place_object"
	place_command["position"] = MapDocument.vector_to_data(placement)
	place_command.erase("target_id")
	place_command.erase("offset")
	return _place_object(document, place_command)


static func _place_prefab(document: Dictionary, command: Dictionary) -> Dictionary:
	var prefab_name := String(command.get("prefab", ""))
	if not MapDocument.PREFAB_DEFINITIONS.has(prefab_name):
		return _failure(document, "Unknown prefab: %s" % prefab_name)
	var origin := _command_vector(command.get("position", {}), Vector3.ZERO)
	var group_id := String(command.get("group_id", "")).strip_edges()
	var objects := MapDocument.make_prefab_objects(prefab_name, origin, group_id)
	if objects.is_empty():
		return _failure(document, "Prefab has no objects: %s" % prefab_name)
	for object: Dictionary in objects:
		var base_id := String(object.get("id", "object"))
		var unique_id := base_id
		var suffix := 1
		while _find_object_index(document, unique_id) >= 0:
			unique_id = "%s_%d" % [base_id, suffix]
			suffix += 1
		object["id"] = unique_id
		(document["objects"] as Array).append(object)
	var affected_id := String(objects[0].get("id", ""))
	return _success(document, affected_id, "Placed %s prefab (%d pieces)" % [MapDocument.PREFAB_DEFINITIONS[prefab_name]["label"], objects.size()])


static func _transform_object(document: Dictionary, command: Dictionary) -> Dictionary:
	var object_id := String(command.get("id", ""))
	var index := _find_object_index(document, object_id)
	if index < 0:
		return _failure(document, "Object not found: %s" % object_id)
	var object := (document["objects"] as Array)[index] as Dictionary
	var old_position := MapDocument.data_to_vector(object["position"])
	var old_rotation := MapDocument.data_to_vector(object["rotation_degrees"])
	if command.has("position"):
		object["position"] = MapDocument.vector_to_data(_command_vector(command["position"], MapDocument.data_to_vector(object["position"])))
	if command.has("rotation_degrees"):
		object["rotation_degrees"] = MapDocument.vector_to_data(_command_vector(command["rotation_degrees"], MapDocument.data_to_vector(object["rotation_degrees"])))
	if command.has("size"):
		var size := _command_vector(command["size"], MapDocument.data_to_vector(object["size"])).abs()
		object["size"] = MapDocument.vector_to_data(Vector3(maxf(size.x, 0.1), maxf(size.y, 0.1), maxf(size.z, 0.1)))
	(document["objects"] as Array)[index] = object
	_transform_attached_children(
		document,
		object_id,
		old_position,
		MapDocument.data_to_vector(object["position"]),
		old_rotation,
		MapDocument.data_to_vector(object["rotation_degrees"])
	)
	return _success(document, object_id, "Transformed %s" % object["name"])


static func _transform_attached_children(
	document: Dictionary,
	parent_id: String,
	old_parent_position: Vector3,
	new_parent_position: Vector3,
	old_parent_rotation: Vector3,
	new_parent_rotation: Vector3
) -> void:
	var rotation_delta := new_parent_rotation - old_parent_rotation
	var delta_basis := Basis.from_euler(Vector3(
		deg_to_rad(rotation_delta.x),
		deg_to_rad(rotation_delta.y),
		deg_to_rad(rotation_delta.z)
	))
	for child_index in (document["objects"] as Array).size():
		var child := (document["objects"] as Array)[child_index] as Dictionary
		var properties: Dictionary = child.get("properties", {})
		if String(properties.get("attached_to", "")) != parent_id:
			continue
		var child_id := String(child.get("id", ""))
		var old_child_position := MapDocument.data_to_vector(child.get("position", {}))
		var old_child_rotation := MapDocument.data_to_vector(child.get("rotation_degrees", {}))
		var relative_position := old_child_position - old_parent_position
		var new_child_position := new_parent_position + delta_basis * relative_position
		var new_child_rotation := old_child_rotation + rotation_delta
		child["position"] = MapDocument.vector_to_data(new_child_position)
		child["rotation_degrees"] = MapDocument.vector_to_data(new_child_rotation)
		(document["objects"] as Array)[child_index] = child
		_transform_attached_children(
			document,
			child_id,
			old_child_position,
			new_child_position,
			old_child_rotation,
			new_child_rotation
		)


static func _duplicate_object(document: Dictionary, command: Dictionary) -> Dictionary:
	var source_id := String(command.get("id", ""))
	var index := _find_object_index(document, source_id)
	if index < 0:
		return _failure(document, "Object not found: %s" % source_id)
	var source := ((document["objects"] as Array)[index] as Dictionary).duplicate(true)
	var new_id := String(command.get("new_id", "")).strip_edges()
	if new_id.is_empty():
		new_id = "%s_copy_%s" % [source_id, str(Time.get_ticks_usec())]
	if _find_object_index(document, new_id) >= 0:
		return _failure(document, "Object id already exists: %s" % new_id)
	source["id"] = new_id
	source["name"] = "%s Copy" % String(source.get("name", "Object"))
	var grid_size := float(document.get("grid_size", 0.5))
	var offset := _command_vector(command.get("offset", {}), Vector3(grid_size, 0.0, grid_size))
	source["position"] = MapDocument.vector_to_data(MapDocument.data_to_vector(source["position"]) + offset)
	(document["objects"] as Array).append(source)
	return _success(document, new_id, "Duplicated %s" % source["name"])


static func _assign_group(document: Dictionary, command: Dictionary) -> Dictionary:
	var object_id := String(command.get("id", ""))
	var index := _find_object_index(document, object_id)
	if index < 0:
		return _failure(document, "Object not found: %s" % object_id)
	var group_id := String(command.get("group_id", "")).strip_edges()
	var object := (document["objects"] as Array)[index] as Dictionary
	var properties: Dictionary = object.get("properties", {}).duplicate(true)
	if group_id.is_empty():
		properties.erase("group_id")
	else:
		properties["group_id"] = group_id
	object["properties"] = properties
	(document["objects"] as Array)[index] = object
	return _success(document, object_id, "Updated %s group" % object.get("name", "Object"))


static func _attach_object(document: Dictionary, command: Dictionary) -> Dictionary:
	var child_id := String(command.get("id", ""))
	var parent_id := String(command.get("parent_id", ""))
	var child_index := _find_object_index(document, child_id)
	var parent_index := _find_object_index(document, parent_id)
	if child_index < 0 or parent_index < 0:
		return _failure(document, "Attachment needs an existing child and parent.")
	if child_id == parent_id:
		return _failure(document, "An object cannot attach to itself.")
	var ancestor_id := parent_id
	while not ancestor_id.is_empty():
		if ancestor_id == child_id:
			return _failure(document, "Attachment would create a cycle.")
		var ancestor_index := _find_object_index(document, ancestor_id)
		if ancestor_index < 0:
			break
		var ancestor_properties: Dictionary = ((document["objects"] as Array)[ancestor_index] as Dictionary).get("properties", {})
		ancestor_id = String(ancestor_properties.get("attached_to", ""))
	var child := (document["objects"] as Array)[child_index] as Dictionary
	var properties: Dictionary = child.get("properties", {}).duplicate(true)
	properties["attached_to"] = parent_id
	child["properties"] = properties
	(document["objects"] as Array)[child_index] = child
	return _success(document, child_id, "Attached %s to %s" % [child.get("name", "Object"), ((document["objects"] as Array)[parent_index] as Dictionary).get("name", "Object")])


static func _detach_object(document: Dictionary, command: Dictionary) -> Dictionary:
	var object_id := String(command.get("id", ""))
	var index := _find_object_index(document, object_id)
	if index < 0:
		return _failure(document, "Object not found: %s" % object_id)
	var object := (document["objects"] as Array)[index] as Dictionary
	var properties: Dictionary = object.get("properties", {}).duplicate(true)
	properties.erase("attached_to")
	object["properties"] = properties
	(document["objects"] as Array)[index] = object
	return _success(document, object_id, "Detached %s" % object.get("name", "Object"))


static func _duplicate_group(document: Dictionary, command: Dictionary) -> Dictionary:
	var source_group := String(command.get("group_id", "")).strip_edges()
	if source_group.is_empty():
		var source_index := _find_object_index(document, String(command.get("id", "")))
		if source_index >= 0:
			var source_properties: Dictionary = ((document["objects"] as Array)[source_index] as Dictionary).get("properties", {})
			source_group = String(source_properties.get("group_id", ""))
	if source_group.is_empty():
		return _failure(document, "Select an object that belongs to a group, or provide group_id.")
	var new_group := String(command.get("new_group_id", "")).strip_edges()
	if new_group.is_empty():
		new_group = "%s_copy_%s" % [source_group, str(Time.get_ticks_usec())]
	var grid_size := float(document.get("grid_size", 0.5))
	var offset := _command_vector(command.get("offset", {}), Vector3(grid_size * 2.0, 0.0, grid_size * 2.0))
	var copies: Array[Dictionary] = []
	for raw_object: Dictionary in (document.get("objects", []) as Array):
		var properties: Dictionary = raw_object.get("properties", {})
		if String(properties.get("group_id", "")) != source_group:
			continue
		var copy := raw_object.duplicate(true)
		copy["id"] = "%s_%02d_%s" % [new_group, copies.size(), String(copy.get("type", "object"))]
		copy["name"] = "%s Copy" % String(copy.get("name", "Object"))
		copy["position"] = MapDocument.vector_to_data(MapDocument.data_to_vector(copy.get("position", {})) + offset)
		var copy_properties: Dictionary = copy.get("properties", {})
		copy_properties["group_id"] = new_group
		copy["properties"] = copy_properties
		copies.append(copy)
	if copies.is_empty():
		return _failure(document, "No objects belong to group: %s" % source_group)
	for copy: Dictionary in copies:
		(document["objects"] as Array).append(copy)
	return _success(document, String(copies[0].get("id", "")), "Duplicated group %s (%d pieces)" % [source_group, copies.size()])


static func _scale_group(document: Dictionary, command: Dictionary) -> Dictionary:
	var selected_id := String(command.get("id", ""))
	var selected_index := _find_object_index(document, selected_id)
	if selected_index < 0:
		return _failure(document, "Object not found: %s" % selected_id)
	var selected := (document["objects"] as Array)[selected_index] as Dictionary
	var selected_properties: Dictionary = selected.get("properties", {})
	var group_id := String(command.get("group_id", selected_properties.get("group_id", ""))).strip_edges()
	if group_id.is_empty():
		return _failure(document, "Selected object does not belong to a group.")
	var factor := clampf(float(command.get("factor", 1.0)), 0.1, 10.0)
	var grouped_indices: Array[int] = []
	var center := Vector3.ZERO
	for index in (document.get("objects", []) as Array).size():
		var object := (document["objects"] as Array)[index] as Dictionary
		var properties: Dictionary = object.get("properties", {})
		if String(properties.get("group_id", "")) != group_id:
			continue
		grouped_indices.append(index)
		center += MapDocument.data_to_vector(object.get("position", {}))
	if grouped_indices.is_empty():
		return _failure(document, "No objects belong to group: %s" % group_id)
	center /= float(grouped_indices.size())
	for index in grouped_indices:
		var object := (document["objects"] as Array)[index] as Dictionary
		var position := MapDocument.data_to_vector(object.get("position", {}))
		var size := MapDocument.data_to_vector(object.get("size", {}), Vector3.ONE)
		object["position"] = MapDocument.vector_to_data(center + (position - center) * factor)
		object["size"] = MapDocument.vector_to_data(Vector3(maxf(size.x * factor, 0.1), maxf(size.y * factor, 0.1), maxf(size.z * factor, 0.1)))
		(document["objects"] as Array)[index] = object
	return _success(document, selected_id, "Scaled group %s by %.2f×" % [group_id, factor])


static func _delete_object(document: Dictionary, command: Dictionary) -> Dictionary:
	var object_id := String(command.get("id", ""))
	var index := _find_object_index(document, object_id)
	if index < 0:
		return _failure(document, "Object not found: %s" % object_id)
	var object := (document["objects"] as Array)[index] as Dictionary
	(document["objects"] as Array).remove_at(index)
	for child_index in (document["objects"] as Array).size():
		var child := (document["objects"] as Array)[child_index] as Dictionary
		var properties: Dictionary = child.get("properties", {}).duplicate(true)
		if String(properties.get("attached_to", "")) == object_id:
			properties.erase("attached_to")
			child["properties"] = properties
			(document["objects"] as Array)[child_index] = child
	return _success(document, object_id, "Deleted %s" % object["name"])


static func _rename_object(document: Dictionary, command: Dictionary) -> Dictionary:
	var object_id := String(command.get("id", ""))
	var index := _find_object_index(document, object_id)
	if index < 0:
		return _failure(document, "Object not found: %s" % object_id)
	var name := String(command.get("name", "Object")).strip_edges()
	if name.is_empty():
		return _failure(document, "Object name cannot be empty.")
	var object := (document["objects"] as Array)[index] as Dictionary
	object["name"] = name
	(document["objects"] as Array)[index] = object
	return _success(document, object_id, "Renamed object to %s" % name)


static func _set_environment(document: Dictionary, command: Dictionary) -> Dictionary:
	var environment := MapDocument.normalize_environment(document.get("environment", {}))
	var changes: Variant = command.get("changes", {})
	if not changes is Dictionary:
		return _failure(document, "set_environment requires a changes dictionary.")
	var allowed := [
		"sky_top", "sky_horizon", "ground_color", "ambient_color", "ambient_energy",
		"sun_color", "sun_energy", "sun_rotation", "fog_enabled", "fog_density",
		"fog_color", "exposure", "soundscape", "film_grain_strength",
	]
	for key: Variant in (changes as Dictionary):
		if String(key) in allowed:
			environment[String(key)] = (changes as Dictionary)[key]
	document["environment"] = MapDocument.normalize_environment(environment)
	return _success(document, "", "Updated map atmosphere")


static func _set_object_properties(document: Dictionary, command: Dictionary) -> Dictionary:
	var object_id := String(command.get("id", ""))
	var index := _find_object_index(document, object_id)
	if index < 0:
		return _failure(document, "Object not found: %s" % object_id)
	var changes: Variant = command.get("changes", {})
	if not changes is Dictionary:
		return _failure(document, "set_object_properties requires a changes dictionary.")
	var object := (document["objects"] as Array)[index] as Dictionary
	var properties: Dictionary = object.get("properties", {}).duplicate(true)
	properties.merge(changes as Dictionary, true)
	object["properties"] = properties
	(document["objects"] as Array)[index] = object
	return _success(document, object_id, "Updated %s properties" % object["name"])


static func _set_object_color(document: Dictionary, command: Dictionary) -> Dictionary:
	var object_id := String(command.get("id", ""))
	var index := _find_object_index(document, object_id)
	if index < 0:
		return _failure(document, "Object not found: %s" % object_id)
	var object := (document["objects"] as Array)[index] as Dictionary
	object["color"] = MapDocument.color_to_data(MapDocument.data_to_color(command.get("color", {}), MapDocument.data_to_color(object.get("color", {}))))
	(document["objects"] as Array)[index] = object
	return _success(document, object_id, "Updated %s color" % object["name"])


static func _set_gameplay(document: Dictionary, command: Dictionary) -> Dictionary:
	var gameplay := MapDocument.normalize_gameplay(document.get("gameplay", {}))
	var changes: Variant = command.get("changes", {})
	if not changes is Dictionary:
		return _failure(document, "set_gameplay requires a changes dictionary.")
	for key in [
		"primary_mode", "supported_modes", "round_time_seconds", "maximum_rounds", "rounds_to_win",
		"elimination_wins_round", "bomb_detonation_wins_round", "round_timeout_result",
		"bomb_fuse_seconds", "plant_time_seconds", "defuse_time_seconds", "respawns_enabled",
	]:
		if (changes as Dictionary).has(key):
			gameplay[key] = (changes as Dictionary)[key]
	document["gameplay"] = MapDocument.normalize_gameplay(gameplay)
	return _success(document, "", "Updated SOCOM mission rules")


static func _find_object_index(document: Dictionary, object_id: String) -> int:
	var objects: Array = document.get("objects", [])
	for index in objects.size():
		var object: Variant = objects[index]
		if object is Dictionary and String((object as Dictionary).get("id", "")) == object_id:
			return index
	return -1


static func _command_vector(value: Variant, fallback: Vector3) -> Vector3:
	if value is Vector3:
		return value
	return MapDocument.data_to_vector(value, fallback)


static func _success(document: Dictionary, object_id: String, message: String) -> Dictionary:
	return {"ok": true, "message": message, "affected_id": object_id, "document": MapDocument.normalize(document)}


static func _failure(document: Dictionary, message: String) -> Dictionary:
	return {"ok": false, "message": message, "affected_id": "", "document": document}
