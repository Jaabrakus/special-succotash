class_name SocomMapCommandService
extends RefCounted

## One command surface for both the visual Map Lab and automation/LLM tooling.
## Callers submit plain Dictionaries and receive a new normalized document.

const MapDocument := preload("res://scripts/maps/socom_map_document.gd")

const COMMANDS := {
	"place_object": "Create an object using type, position, optional size, name, and id.",
	"transform_object": "Change position, rotation_degrees, and/or size for an object id.",
	"duplicate_object": "Copy an object id with an optional offset and new_id.",
	"delete_object": "Delete one object by id.",
	"rename_object": "Give one object a human-readable name.",
	"set_object_properties": "Safely merge type-specific properties such as light energy or ambience audio_stream.",
	"set_map_name": "Change the map name.",
	"set_grid_size": "Change placement snapping from 0.125 to 4 meters.",
	"apply_environment_preset": "Apply a complete authored atmosphere preset by name.",
	"set_environment": "Change individual atmosphere fields such as sun_energy, fog_density, or exposure.",
	"set_gameplay": "Configure SOCOM demolition/TDM mode, round time, bomb fuse, planting, and respawns.",
}


static func describe_capabilities() -> Dictionary:
	return {
		"schema_version": MapDocument.SCHEMA_VERSION,
		"map_path": MapDocument.ACTIVE_MAP_PATH,
		"commands": COMMANDS.duplicate(true),
		"object_types": Array(MapDocument.SUPPORTED_TYPES),
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
		"transform_object":
			result = _transform_object(working, command)
		"duplicate_object":
			result = _duplicate_object(working, command)
		"delete_object":
			result = _delete_object(working, command)
		"rename_object":
			result = _rename_object(working, command)
		"set_object_properties":
			result = _set_object_properties(working, command)
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
	(document["objects"] as Array).append(object)
	return _success(document, String(object["id"]), "Placed %s" % object["name"])


static func _transform_object(document: Dictionary, command: Dictionary) -> Dictionary:
	var object_id := String(command.get("id", ""))
	var index := _find_object_index(document, object_id)
	if index < 0:
		return _failure(document, "Object not found: %s" % object_id)
	var object := (document["objects"] as Array)[index] as Dictionary
	if command.has("position"):
		object["position"] = MapDocument.vector_to_data(_command_vector(command["position"], MapDocument.data_to_vector(object["position"])))
	if command.has("rotation_degrees"):
		object["rotation_degrees"] = MapDocument.vector_to_data(_command_vector(command["rotation_degrees"], MapDocument.data_to_vector(object["rotation_degrees"])))
	if command.has("size"):
		var size := _command_vector(command["size"], MapDocument.data_to_vector(object["size"])).abs()
		object["size"] = MapDocument.vector_to_data(Vector3(maxf(size.x, 0.1), maxf(size.y, 0.1), maxf(size.z, 0.1)))
	(document["objects"] as Array)[index] = object
	return _success(document, object_id, "Transformed %s" % object["name"])


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


static func _delete_object(document: Dictionary, command: Dictionary) -> Dictionary:
	var object_id := String(command.get("id", ""))
	var index := _find_object_index(document, object_id)
	if index < 0:
		return _failure(document, "Object not found: %s" % object_id)
	var object := (document["objects"] as Array)[index] as Dictionary
	(document["objects"] as Array).remove_at(index)
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
		"fog_color", "exposure", "soundscape",
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


static func _set_gameplay(document: Dictionary, command: Dictionary) -> Dictionary:
	var gameplay := MapDocument.normalize_gameplay(document.get("gameplay", {}))
	var changes: Variant = command.get("changes", {})
	if not changes is Dictionary:
		return _failure(document, "set_gameplay requires a changes dictionary.")
	for key in ["primary_mode", "supported_modes", "round_time_seconds", "bomb_fuse_seconds", "plant_time_seconds", "respawns_enabled"]:
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
