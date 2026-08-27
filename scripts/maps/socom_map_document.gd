class_name SocomMapDocument
extends RefCounted

const ACTIVE_MAP_PATH := "res://config/maps/current_map.json"
const USER_MAP_DIRECTORY := "user://maps"
const USER_MAP_INDEX_PATH := "user://maps/library.json"
const USER_ACTIVE_MAP_PATH := "user://maps/active_map.json"
const SCHEMA_VERSION := 1
static var library_directory_override := ""
const SUPPORTED_TYPES: Array[StringName] = [
	&"ground", &"wall", &"cover_low", &"cover_tall", &"platform", &"ramp", &"player_spawn",
	&"point_light", &"ambience_zone",
	&"fog_zone",
	&"doorway_wall", &"window_wall", &"stairs", &"roof", &"column",
	&"primitive_box", &"primitive_cylinder", &"primitive_sphere",
	&"curved_wall", &"jagged_wall", &"breached_wall",
	&"tree", &"pine_tree", &"bush", &"rocky_mountain", &"imported_asset",
	&"team_alpha_spawn", &"team_bravo_spawn", &"bomb_pickup", &"alpha_bomb_site", &"bravo_bomb_site",
	&"training_dummy", &"moving_training_dummy",
]

const SOCOM_OBJECTIVE_TYPES: Array[StringName] = [
	&"team_alpha_spawn", &"team_bravo_spawn", &"bomb_pickup", &"alpha_bomb_site", &"bravo_bomb_site",
]

const ENVIRONMENT_PRESETS := {
	"tactical_overcast": {
		"label": "Tactical Overcast", "sky_top": Color("263747"), "sky_horizon": Color("8795a0"),
		"ground_color": Color("273039"), "ambient_color": Color("b5c7d8"), "ambient_energy": 0.78,
		"sun_color": Color("dce8f2"), "sun_energy": 1.05, "sun_rotation": Vector3(-52.0, -32.0, 0.0),
		"fog_enabled": true, "fog_density": 0.006, "fog_color": Color("778590"), "exposure": 1.0,
	},
	"golden_hour": {
		"label": "Golden Hour", "sky_top": Color("304c72"), "sky_horizon": Color("e5a164"),
		"ground_color": Color("4b342b"), "ambient_color": Color("e0b58d"), "ambient_energy": 0.68,
		"sun_color": Color("ffd19a"), "sun_energy": 1.65, "sun_rotation": Vector3(-18.0, -48.0, 0.0),
		"fog_enabled": true, "fog_density": 0.004, "fog_color": Color("c78f6a"), "exposure": 1.08,
	},
	"moonlit_night": {
		"label": "Moonlit Night", "sky_top": Color("07101f"), "sky_horizon": Color("1b2940"),
		"ground_color": Color("090d15"), "ambient_color": Color("7897bd"), "ambient_energy": 0.34,
		"sun_color": Color("91b7e8"), "sun_energy": 0.62, "sun_rotation": Vector3(-38.0, 28.0, 0.0),
		"fog_enabled": true, "fog_density": 0.009, "fog_color": Color("19283a"), "exposure": 0.83,
	},
	"high_contrast_day": {
		"label": "High Contrast Day", "sky_top": Color("2872aa"), "sky_horizon": Color("b7d8e6"),
		"ground_color": Color("35433f"), "ambient_color": Color("c9dbdd"), "ambient_energy": 0.62,
		"sun_color": Color("fff2d0"), "sun_energy": 1.9, "sun_rotation": Vector3(-58.0, -24.0, 0.0),
		"fog_enabled": false, "fog_density": 0.002, "fog_color": Color("b5cbd4"), "exposure": 1.0,
	},
}

const SURFACE_PRESETS := {
	"default": {"label": "Default", "roughness": 0.9, "metallic": 0.0},
	"concrete": {
		"label": "Dark Weathered Concrete",
		"roughness": 0.94,
		"metallic": 0.0,
		"texture_path": "res://assets/textures/environment/original_materials/dark_concrete_albedo_v1.png",
	},
	"stucco": {
		"label": "Warm Weathered Masonry",
		"roughness": 0.94,
		"metallic": 0.0,
		"texture_path": "res://assets/textures/environment/original_materials/warm_masonry_albedo_v1.png",
	},
	"muddy_limestone": {
		"label": "Packed Earth / Gravel",
		"roughness": 0.97,
		"metallic": 0.0,
		"texture_path": "res://assets/textures/environment/original_materials/packed_earth_albedo_v1.png",
	},
	"grass": {
		"label": "Dry Tactical Grass",
		"roughness": 1.0,
		"metallic": 0.0,
		"texture_path": "res://assets/textures/environment/original_materials/dry_grass_albedo_v1.png",
	},
	"dirt": {
		"label": "Packed Earth / Gravel",
		"roughness": 1.0,
		"metallic": 0.0,
		"texture_path": "res://assets/textures/environment/original_materials/packed_earth_albedo_v1.png",
	},
	"rock": {
		"label": "Rough Mountain Rock",
		"roughness": 0.98,
		"metallic": 0.0,
		"texture_path": "res://assets/textures/environment/original_materials/rough_rock_albedo_v1.png",
	},
}

const LIGHT_PRESETS := {
	"warm_lamp": {"label": "Warm Lamp", "color": Color("ffd09a"), "energy": 3.2, "range": 10.0, "shadow_enabled": true},
	"cool_flood": {"label": "Cool Flood", "color": Color("9fd8ff"), "energy": 4.2, "range": 14.0, "shadow_enabled": true},
	"red_alert": {"label": "Red Alert", "color": Color("ff5b4f"), "energy": 2.8, "range": 8.0, "shadow_enabled": true},
	"moon_fill": {"label": "Moon Fill", "color": Color("8daeff"), "energy": 1.8, "range": 18.0, "shadow_enabled": false},
}

const TYPE_DEFAULTS := {
	&"ground": {"label": "Ground Tile", "size": Vector3(8.0, 0.25, 8.0), "color": Color("59616b")},
	&"wall": {"label": "Wall", "size": Vector3(4.0, 3.0, 0.3), "color": Color("6b7078")},
	&"cover_low": {"label": "Low Cover", "size": Vector3(3.0, 1.1, 0.6), "color": Color("655e55")},
	&"cover_tall": {"label": "Tall Cover", "size": Vector3(1.3, 2.2, 1.3), "color": Color("555d68")},
	&"platform": {"label": "Platform", "size": Vector3(4.0, 0.4, 4.0), "color": Color("5e685b")},
	&"ramp": {"label": "Ramp", "size": Vector3(3.0, 0.35, 5.0), "color": Color("756950")},
	&"player_spawn": {"label": "Player Spawn", "size": Vector3(0.8, 1.8, 0.8), "color": Color("55dca0")},
	&"point_light": {"label": "Practical Light", "size": Vector3(0.35, 0.35, 0.35), "color": Color("ffd59b")},
	&"ambience_zone": {"label": "Ambience Zone", "size": Vector3(6.0, 3.0, 6.0), "color": Color("8b6be8")},
	&"fog_zone": {"label": "Tactical Fog Zone", "size": Vector3(10.0, 3.0, 10.0), "color": Color("7d99a8")},
	&"doorway_wall": {"label": "Doorway Wall", "size": Vector3(4.0, 3.0, 0.3), "color": Color("716d67")},
	&"window_wall": {"label": "Window Wall", "size": Vector3(4.0, 3.0, 0.3), "color": Color("6d716f")},
	&"stairs": {"label": "Stairs", "size": Vector3(3.0, 2.5, 5.0), "color": Color("71695e")},
	&"roof": {"label": "Roof / Floor Slab", "size": Vector3(6.0, 0.35, 6.0), "color": Color("625f5a")},
	&"column": {"label": "Structural Column", "size": Vector3(0.6, 3.0, 0.6), "color": Color("68645e")},
	&"primitive_box": {"label": "Freeform Box", "size": Vector3(2.0, 2.0, 2.0), "color": Color("747b82")},
	&"primitive_cylinder": {"label": "Freeform Cylinder", "size": Vector3(2.0, 2.0, 2.0), "color": Color("707980")},
	&"primitive_sphere": {"label": "Freeform Sphere", "size": Vector3(2.0, 2.0, 2.0), "color": Color("737b80")},
	&"curved_wall": {"label": "Curved Wall", "size": Vector3(5.0, 3.0, 0.35), "color": Color("687078")},
	&"jagged_wall": {"label": "Broken Wall", "size": Vector3(5.0, 2.6, 0.45), "color": Color("5d6268")},
	&"breached_wall": {"label": "Breached Wall + Hole", "size": Vector3(6.0, 3.0, 0.45), "color": Color("5f5d59")},
	&"tree": {"label": "Broadleaf Tree", "size": Vector3(3.5, 7.0, 3.5), "color": Color("47774b")},
	&"pine_tree": {"label": "Pine Tree", "size": Vector3(3.8, 8.5, 3.8), "color": Color("315f46")},
	&"bush": {"label": "Concealment Bush", "size": Vector3(3.4, 2.1, 2.8), "color": Color("354b2b")},
	&"rocky_mountain": {"label": "Rocky Mountain", "size": Vector3(18.0, 12.0, 18.0), "color": Color("67655f")},
	&"imported_asset": {"label": "Imported Community Asset", "size": Vector3(1.0, 1.0, 1.0), "color": Color("ffffff")},
	&"team_alpha_spawn": {"label": "Alpha Team Spawn", "size": Vector3(1.0, 1.8, 1.0), "color": Color("4fa3ff")},
	&"team_bravo_spawn": {"label": "Bravo Team Spawn", "size": Vector3(1.0, 1.8, 1.0), "color": Color("ff655e")},
	&"bomb_pickup": {"label": "Neutral Bomb Pickup", "size": Vector3(0.8, 0.8, 0.8), "color": Color("f4d34f")},
	&"alpha_bomb_site": {"label": "Alpha Base Target", "size": Vector3(3.0, 0.25, 3.0), "color": Color("4fa3ff")},
	&"bravo_bomb_site": {"label": "Bravo Base Target", "size": Vector3(3.0, 0.25, 3.0), "color": Color("ff655e")},
	&"training_dummy": {"label": "Training Dummy", "size": Vector3(0.8, 1.8, 0.8), "color": Color("f39a55")},
	&"moving_training_dummy": {"label": "Moving Dummy", "size": Vector3(0.8, 1.8, 0.8), "color": Color("50d8df")},
}

const PREFAB_DEFINITIONS := {
	"tactical_room": {
		"label": "Tactical Room",
		"objects": [
			{"type": "roof", "name": "Room Floor", "offset": Vector3(0.0, 0.175, 0.0), "size": Vector3(8.0, 0.35, 8.0)},
			{"type": "doorway_wall", "name": "Room Doorway", "offset": Vector3(0.0, 1.5, 4.0), "size": Vector3(8.0, 3.0, 0.3)},
			{"type": "window_wall", "name": "Room Window", "offset": Vector3(0.0, 1.5, -4.0), "size": Vector3(8.0, 3.0, 0.3)},
			{"type": "wall", "name": "Room Left Wall", "offset": Vector3(-4.0, 1.5, 0.0), "size": Vector3(8.0, 3.0, 0.3), "yaw": 90.0},
			{"type": "wall", "name": "Room Right Wall", "offset": Vector3(4.0, 1.5, 0.0), "size": Vector3(8.0, 3.0, 0.3), "yaw": 90.0},
			{"type": "roof", "name": "Room Roof", "offset": Vector3(0.0, 3.175, 0.0), "size": Vector3(8.0, 0.35, 8.0)},
		],
	},
	"guard_tower": {
		"label": "Guard Tower",
		"objects": [
			{"type": "platform", "name": "Tower Deck", "offset": Vector3(0.0, 3.0, 0.0), "size": Vector3(5.0, 0.4, 5.0)},
			{"type": "column", "name": "Tower Post NW", "offset": Vector3(-2.1, 1.5, -2.1)},
			{"type": "column", "name": "Tower Post NE", "offset": Vector3(2.1, 1.5, -2.1)},
			{"type": "column", "name": "Tower Post SW", "offset": Vector3(-2.1, 1.5, 2.1)},
			{"type": "column", "name": "Tower Post SE", "offset": Vector3(2.1, 1.5, 2.1)},
			{"type": "stairs", "name": "Tower Stairs", "offset": Vector3(0.0, 1.5, 5.0), "size": Vector3(3.0, 3.0, 6.0)},
			{"type": "cover_low", "name": "Tower Parapet", "offset": Vector3(0.0, 3.65, -2.3), "size": Vector3(5.0, 0.9, 0.35)},
		],
	},
	"checkpoint": {
		"label": "Road Checkpoint",
		"objects": [
			{"type": "cover_low", "name": "Checkpoint Left", "offset": Vector3(-3.0, 0.55, 0.0), "size": Vector3(4.0, 1.1, 0.8)},
			{"type": "cover_low", "name": "Checkpoint Right", "offset": Vector3(3.0, 0.55, 0.0), "size": Vector3(4.0, 1.1, 0.8)},
			{"type": "cover_tall", "name": "Checkpoint Booth", "offset": Vector3(0.0, 1.1, -2.0), "size": Vector3(2.2, 2.2, 2.2)},
		],
	},
}


static func new_document(map_name: String = "Untitled Tactical Map") -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"map_id": _new_map_id(),
		"enabled": true,
		"name": map_name,
		"grid_size": 0.5,
		"environment": environment_from_preset("tactical_overcast"),
		"gameplay": default_gameplay(),
		"objects": [
			make_object(&"ground", Vector3(0.0, -0.125, 0.0), Vector3(24.0, 0.25, 24.0)),
			make_object(&"player_spawn", Vector3(0.0, 0.05, 3.0)),
			make_object(&"team_alpha_spawn", Vector3(-7.0, 0.05, 7.0)),
			make_object(&"team_bravo_spawn", Vector3(7.0, 0.05, -7.0)),
			make_object(&"bomb_pickup", Vector3(0.0, 0.4, 0.0)),
			make_object(&"alpha_bomb_site", Vector3(-7.0, 0.125, 8.5)),
			make_object(&"bravo_bomb_site", Vector3(7.0, 0.125, -8.5)),
		],
	}


static func make_object(
	type_name: StringName,
	position: Vector3,
	size_override: Vector3 = Vector3.ZERO
) -> Dictionary:
	var safe_type := type_name if type_name in SUPPORTED_TYPES else &"wall"
	var defaults: Dictionary = TYPE_DEFAULTS[safe_type]
	var size: Vector3 = size_override if not size_override.is_zero_approx() else defaults["size"]
	return {
		"id": "map_%s_%s" % [String(safe_type), str(Time.get_ticks_usec())],
		"type": String(safe_type),
		"name": String(defaults["label"]),
		"position": vector_to_data(position),
		"rotation_degrees": vector_to_data(Vector3.ZERO),
		"size": vector_to_data(size),
		"color": color_to_data(defaults["color"]),
		"properties": _default_properties(safe_type),
	}


static func make_prefab_objects(prefab_name: String, origin: Vector3, group_id: String = "") -> Array[Dictionary]:
	var objects: Array[Dictionary] = []
	if not PREFAB_DEFINITIONS.has(prefab_name):
		return objects
	var safe_group := group_id.strip_edges()
	if safe_group.is_empty():
		safe_group = "%s_%s" % [prefab_name, str(Time.get_ticks_usec())]
	var definitions: Array = PREFAB_DEFINITIONS[prefab_name].get("objects", [])
	for index in definitions.size():
		var definition := definitions[index] as Dictionary
		var type_name := StringName(definition.get("type", "wall"))
		var offset: Vector3 = definition.get("offset", Vector3.ZERO)
		var size: Vector3 = definition.get("size", Vector3.ZERO)
		var object := make_object(type_name, origin + offset, size)
		object["id"] = "%s_%02d_%s" % [safe_group, index, String(type_name)]
		object["name"] = String(definition.get("name", object.get("name", "Object")))
		object["rotation_degrees"] = vector_to_data(Vector3(0.0, float(definition.get("yaw", 0.0)), 0.0))
		var properties: Dictionary = object.get("properties", {})
		properties["group_id"] = safe_group
		properties["prefab_name"] = prefab_name
		object["properties"] = properties
		objects.append(object)
	return objects


static func load_active() -> Dictionary:
	var session_selected: Variant = ProjectSettings.get_setting("socom/session/selected_map_document", {})
	if session_selected is Dictionary and not (session_selected as Dictionary).is_empty():
		return normalize(session_selected as Dictionary)
	var bundled := SocomPlaytestStateCollector.bundled_state("map")
	if not bundled.is_empty():
		return normalize(bundled)
	var user_selected := load_path(_library_active_path())
	if not user_selected.is_empty():
		return user_selected
	return load_path(ACTIVE_MAP_PATH)


static func save_to_library(document: Dictionary) -> Dictionary:
	var normalized := normalize(document)
	if normalized.is_empty():
		return {"ok": false, "error": "Map document is empty."}
	var map_id := _safe_map_id(String(normalized.get("map_id", "")))
	if map_id.is_empty():
		map_id = _new_map_id()
		normalized["map_id"] = map_id
	var path := _library_directory().path_join("%s.json" % map_id)
	if not save_path(normalized, path):
		return {"ok": false, "error": "Could not save the map library file."}
	if not save_path(normalized, _library_active_path()):
		return {"ok": false, "error": "Could not select the saved map."}
	ProjectSettings.set_setting("socom/session/selected_map_document", normalized.duplicate(true))
	return {"ok": true, "map_id": map_id, "path": path, "document": normalized}


static func select_library_map(map_id: String) -> Dictionary:
	var safe_id := _safe_map_id(map_id)
	if safe_id.is_empty():
		return {}
	var document := load_path(_library_directory().path_join("%s.json" % safe_id))
	if document.is_empty() or not save_path(document, _library_active_path()):
		return {}
	ProjectSettings.set_setting("socom/session/selected_map_document", document.duplicate(true))
	return document


static func list_library_maps() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	var directory := DirAccess.open(_library_directory())
	if directory == null:
		return entries
	directory.list_dir_begin()
	var file_name := directory.get_next()
	while not file_name.is_empty():
		if (
			not directory.current_is_dir()
			and file_name.ends_with(".json")
			and file_name != _library_active_path().get_file()
		):
			var path := _library_directory().path_join(file_name)
			var document := load_path(path)
			if not document.is_empty():
				entries.append({
					"map_id": String(document.get("map_id", file_name.get_basename())),
					"name": String(document.get("name", "Untitled Tactical Map")),
					"path": path,
					"modified_unix": FileAccess.get_modified_time(path),
					"document": document,
				})
		file_name = directory.get_next()
	directory.list_dir_end()
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("modified_unix", 0)) > int(b.get("modified_unix", 0))
	)
	return entries


static func ensure_active_map_in_library() -> Dictionary:
	var active := load_active()
	if active.is_empty():
		active = new_document()
	var map_id := String(active.get("map_id", ""))
	if not map_id.is_empty() and FileAccess.file_exists(_library_directory().path_join("%s.json" % _safe_map_id(map_id))):
		save_path(active, _library_active_path())
		return active
	var result := save_to_library(active)
	return result.get("document", {}) as Dictionary if bool(result.get("ok", false)) else active


static func load_path(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(file.get_as_text()) if file else null
	return normalize(parsed as Dictionary) if parsed is Dictionary else {}


static func save_path(document: Dictionary, path: String = ACTIVE_MAP_PATH) -> bool:
	var normalized := normalize(document)
	if normalized.is_empty():
		return false
	var error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	if error != OK and error != ERR_ALREADY_EXISTS:
		return false
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(normalized, "  "))
	file.close()
	return true


static func normalize(document: Dictionary) -> Dictionary:
	if document.is_empty():
		return {}
	var result := {
		"schema_version": SCHEMA_VERSION,
		"map_id": _safe_map_id(String(document.get("map_id", ""))),
		"enabled": bool(document.get("enabled", true)),
		"name": String(document.get("name", "Untitled Tactical Map")),
		"grid_size": clampf(float(document.get("grid_size", 0.5)), 0.125, 4.0),
		"environment": normalize_environment(document.get("environment", {})),
		"gameplay": normalize_gameplay(document.get("gameplay", {})),
		"lore": normalize_lore(document.get("lore", {})),
		"objects": [],
	}
	if String(result["map_id"]).is_empty():
		result["map_id"] = _new_map_id()
	var seen: Dictionary = {}
	for raw_object: Variant in document.get("objects", []):
		if not raw_object is Dictionary:
			continue
		var object := raw_object as Dictionary
		var type_name := StringName(object.get("type", ""))
		if type_name not in SUPPORTED_TYPES:
			continue
		var object_id := String(object.get("id", ""))
		if object_id.is_empty() or seen.has(object_id):
			object_id = "map_%s_%s_%d" % [String(type_name), str(Time.get_ticks_usec()), seen.size()]
		seen[object_id] = true
		var defaults: Dictionary = TYPE_DEFAULTS[type_name]
		var size := data_to_vector(object.get("size", {}), defaults["size"])
		size = Vector3(maxf(absf(size.x), 0.1), maxf(absf(size.y), 0.1), maxf(absf(size.z), 0.1))
		(result["objects"] as Array).append({
			"id": object_id,
			"type": String(type_name),
			"name": String(object.get("name", defaults["label"])),
			"position": vector_to_data(data_to_vector(object.get("position", {}))),
			"rotation_degrees": vector_to_data(data_to_vector(object.get("rotation_degrees", {}))),
			"size": vector_to_data(size),
			"color": color_to_data(data_to_color(object.get("color", {}), defaults["color"])),
			"properties": (object.get("properties", {}) as Dictionary).duplicate(true) if object.get("properties", {}) is Dictionary else {},
		})
	return result


static func _new_map_id() -> String:
	return "map_%s" % str(Time.get_ticks_usec())


static func _safe_map_id(value: String) -> String:
	var result := ""
	for character in value.to_lower():
		if character in "abcdefghijklmnopqrstuvwxyz0123456789_-":
			result += character
	return result.left(64)


static func _library_directory() -> String:
	return library_directory_override if not library_directory_override.is_empty() else USER_MAP_DIRECTORY


static func _library_active_path() -> String:
	return _library_directory().path_join(USER_ACTIVE_MAP_PATH.get_file())


static func environment_from_preset(preset_name: String) -> Dictionary:
	var safe_name := preset_name if ENVIRONMENT_PRESETS.has(preset_name) else "tactical_overcast"
	var preset: Dictionary = ENVIRONMENT_PRESETS[safe_name]
	return {
		"preset": safe_name,
		"sky_top": color_to_data(preset["sky_top"]),
		"sky_horizon": color_to_data(preset["sky_horizon"]),
		"ground_color": color_to_data(preset["ground_color"]),
		"ambient_color": color_to_data(preset["ambient_color"]),
		"ambient_energy": preset["ambient_energy"],
		"sun_color": color_to_data(preset["sun_color"]),
		"sun_energy": preset["sun_energy"],
		"sun_rotation": vector_to_data(preset["sun_rotation"]),
		"fog_enabled": preset["fog_enabled"],
		"fog_density": preset["fog_density"],
		"fog_color": color_to_data(preset["fog_color"]),
		"exposure": preset["exposure"],
		"soundscape": "outdoor_tactical",
	}


static func default_gameplay() -> Dictionary:
	return {
		"primary_mode": "demolition",
		"supported_modes": ["demolition", "team_deathmatch"],
		"round_time_seconds": 300,
		"maximum_rounds": 7,
		"rounds_to_win": 4,
		"elimination_wins_round": true,
		"bomb_detonation_wins_round": true,
		"round_timeout_result": "draw",
		"bomb_fuse_seconds": 35,
		"plant_time_seconds": 5.0,
		"defuse_time_seconds": 5.0,
		"respawns_enabled": false,
	}


const SUPPORTED_PRIMARY_MODES: Array[String] = [
	"demolition", "team_deathmatch", "gunfight",
]
const SUPPORTED_TIMEOUT_RESULTS: Array[String] = [
	"draw", "alpha", "bravo", "overtime_flag",
]
const SUPPORTED_LOADOUT_MODES: Array[String] = [
	"economy", "rotation", "fixed_allowance",
]


static func normalize_gameplay(value: Variant) -> Dictionary:
	var source := value as Dictionary if value is Dictionary else {}
	var primary_mode := String(source.get("primary_mode", "demolition"))
	if primary_mode not in SUPPORTED_PRIMARY_MODES:
		primary_mode = "demolition"
	var supported: Array = source.get("supported_modes", [primary_mode])
	var clean_supported: Array[String] = []
	for mode: Variant in supported:
		var mode_name := String(mode)
		if mode_name in SUPPORTED_PRIMARY_MODES and mode_name not in clean_supported:
			clean_supported.append(mode_name)
	if primary_mode not in clean_supported:
		clean_supported.push_front(primary_mode)
	var maximum_rounds := clampi(int(source.get("maximum_rounds", 7)), 1, 25)
	var timeout_result := String(source.get("round_timeout_result", "draw"))
	if timeout_result not in SUPPORTED_TIMEOUT_RESULTS:
		timeout_result = "draw"
	var loadout_mode := String(source.get("loadout_mode", "economy"))
	if loadout_mode not in SUPPORTED_LOADOUT_MODES:
		loadout_mode = "economy"
	return {
		"primary_mode": primary_mode,
		"supported_modes": clean_supported,
		"round_time_seconds": clampi(int(source.get("round_time_seconds", 300)), 30, 1800),
		"maximum_rounds": maximum_rounds,
		"rounds_to_win": clampi(int(source.get("rounds_to_win", 4)), 1, maximum_rounds),
		"elimination_wins_round": bool(source.get("elimination_wins_round", true)),
		"bomb_detonation_wins_round": bool(source.get("bomb_detonation_wins_round", true)),
		"round_timeout_result": timeout_result,
		"bomb_fuse_seconds": clampi(int(source.get("bomb_fuse_seconds", 35)), 10, 120),
		"plant_time_seconds": clampf(float(source.get("plant_time_seconds", 5.0)), 1.0, 20.0),
		"defuse_time_seconds": clampf(float(source.get("defuse_time_seconds", 5.0)), 1.0, 20.0),
		"respawns_enabled": bool(source.get("respawns_enabled", primary_mode == "team_deathmatch")),
		"loadout_mode": loadout_mode,
		"fixed_allowance_amount": clampi(int(source.get("fixed_allowance_amount", 2500)), 0, 16000),
		"overtime_flag_radius_m": clampf(float(source.get("overtime_flag_radius_m", 2.5)), 1.0, 8.0),
		"overtime_hold_seconds": clampf(float(source.get("overtime_hold_seconds", 3.0)), 1.0, 10.0),
	}


static func normalize_lore(value: Variant) -> Dictionary:
	# The five words of the Square (docs/SQUARE_DESIGN_LANGUAGE.md). This is a
	# schema whitelist like SUPPORTED_TYPES; SocomTeamNomenclature holds the
	# runtime copy and square_regression.gd pins the two together.
	var valid_houses: Array[String] = ["SATOR", "AREPO", "TENET", "OPERA", "ROTAS"]
	var source := value as Dictionary if value is Dictionary else {}
	var axis := String(source.get("axis", "default"))
	if axis not in ["default", "alternate", "classic"]:
		axis = "default"
	var house := String(source.get("house", "")).to_upper()
	if house not in valid_houses:
		house = ""
	var brief := String(source.get("brief", "")).strip_edges().substr(0, 160)
	return {
		"axis": axis,
		"house": house,
		"brief": brief,
	}


static func normalize_environment(value: Variant) -> Dictionary:
	var source := value as Dictionary if value is Dictionary else {}
	var fallback := environment_from_preset(String(source.get("preset", "tactical_overcast")))
	return {
		"preset": String(source.get("preset", fallback["preset"])),
		"sky_top": color_to_data(data_to_color(source.get("sky_top", {}), data_to_color(fallback["sky_top"]))),
		"sky_horizon": color_to_data(data_to_color(source.get("sky_horizon", {}), data_to_color(fallback["sky_horizon"]))),
		"ground_color": color_to_data(data_to_color(source.get("ground_color", {}), data_to_color(fallback["ground_color"]))),
		"ambient_color": color_to_data(data_to_color(source.get("ambient_color", {}), data_to_color(fallback["ambient_color"]))),
		"ambient_energy": clampf(float(source.get("ambient_energy", fallback["ambient_energy"])), 0.0, 4.0),
		"sun_color": color_to_data(data_to_color(source.get("sun_color", {}), data_to_color(fallback["sun_color"]))),
		"sun_energy": clampf(float(source.get("sun_energy", fallback["sun_energy"])), 0.0, 8.0),
		"sun_rotation": vector_to_data(data_to_vector(source.get("sun_rotation", {}), data_to_vector(fallback["sun_rotation"]))),
		"fog_enabled": bool(source.get("fog_enabled", fallback["fog_enabled"])),
		"fog_density": clampf(float(source.get("fog_density", fallback["fog_density"])), 0.0, 0.1),
		"fog_color": color_to_data(data_to_color(source.get("fog_color", {}), data_to_color(fallback["fog_color"]))),
		"exposure": clampf(float(source.get("exposure", fallback["exposure"])), 0.25, 3.0),
		"soundscape": String(source.get("soundscape", fallback["soundscape"])),
	}


static func _default_properties(type_name: StringName) -> Dictionary:
	if type_name == &"point_light":
		return {"energy": 4.0, "range": 8.0, "shadow_enabled": true}
	if type_name == &"ambience_zone":
		return {"soundscape": "outdoor_tactical", "audio_stream": "", "volume_db": -8.0, "blend_distance": 2.0}
	if type_name == &"fog_zone":
		return {
			"density": 0.035,
			"blend_distance": 2.5,
			"priority": 0,
			"height_falloff": 0.0,
			"occlusion_strength": 0.35,
			"layer_count": 6,
		}
	if type_name in [&"doorway_wall", &"window_wall"]:
		return {"texture_path": "", "surface_kind": "stucco", "roughness": 0.94, "metallic": 0.0, "uv_scale": 1.0, "opening_width": 1.25, "opening_height": 2.2}
	if type_name == &"stairs":
		return {"texture_path": "", "surface_kind": "concrete", "roughness": 0.95, "metallic": 0.0, "uv_scale": 1.0, "steps": 10}
	if type_name == &"training_dummy":
		return {"health": 100.0}
	if type_name == &"moving_training_dummy":
		return {"health": 100.0, "patrol_distance": 6.0, "patrol_speed": 1.5, "turn_pause": 0.35}
	if type_name in [&"tree", &"pine_tree"]:
		return {"canopy_layers": 3, "trunk_ratio": 0.42, "variation_seed": 0}
	if type_name == &"bush":
		return {"cluster_count": 7, "variation_seed": 0, "concealment": true, "blocks_movement": false, "collision_enabled": false}
	if type_name == &"imported_asset":
		return {"asset_path": "", "collision_mode": "box", "collision_enabled": true}
	var surface_kind := "default"
	if type_name == &"ground":
		surface_kind = "muddy_limestone"
	elif type_name in [&"wall", &"curved_wall", &"jagged_wall", &"breached_wall", &"column"]:
		surface_kind = "stucco"
	elif type_name in [&"cover_low", &"cover_tall", &"platform", &"ramp", &"roof"]:
		surface_kind = "concrete"
	elif type_name == &"rocky_mountain":
		surface_kind = "rock"
	var preset: Dictionary = SURFACE_PRESETS.get(surface_kind, SURFACE_PRESETS["default"])
	var material := {
		"texture_path": "",
		"surface_kind": surface_kind,
		"roughness": float(preset.get("roughness", 0.9)),
		"metallic": float(preset.get("metallic", 0.0)),
		"uv_scale": 1.0,
	}
	if type_name == &"curved_wall":
		material.merge({"radius": 4.0, "arc_degrees": 90.0, "segments": 8}, true)
	elif type_name == &"jagged_wall":
		material.merge({"pieces": 6, "height_variance": 0.8, "edge_rotation": 5.0}, true)
	elif type_name == &"breached_wall":
		material.merge({"hole_width": 1.8, "hole_height": 1.55, "hole_bottom": 0.55, "hole_offset_x": 0.0}, true)
	elif type_name == &"rocky_mountain":
		material.merge({"ridge_segments": 12, "roughness_amount": 0.22, "peak_offset_x": 0.0, "peak_offset_z": 0.0, "variation_seed": 0}, true)
	return material


static func player_spawn(document: Dictionary, fallback: Vector3 = Vector3(0.0, 0.05, 0.5)) -> Vector3:
	for object: Dictionary in document.get("objects", []):
		if StringName(object.get("type", "")) == &"player_spawn":
			return data_to_vector(object.get("position", {}), fallback)
	return fallback


static func vector_to_data(value: Vector3) -> Dictionary:
	return {"x": value.x, "y": value.y, "z": value.z}


static func data_to_vector(value: Variant, fallback: Vector3 = Vector3.ZERO) -> Vector3:
	if not value is Dictionary:
		return fallback
	var data := value as Dictionary
	return Vector3(float(data.get("x", fallback.x)), float(data.get("y", fallback.y)), float(data.get("z", fallback.z)))


static func color_to_data(value: Color) -> Dictionary:
	return {"r": value.r, "g": value.g, "b": value.b, "a": value.a}


static func data_to_color(value: Variant, fallback: Color = Color.WHITE) -> Color:
	if not value is Dictionary:
		return fallback
	var data := value as Dictionary
	return Color(float(data.get("r", fallback.r)), float(data.get("g", fallback.g)), float(data.get("b", fallback.b)), float(data.get("a", fallback.a)))
