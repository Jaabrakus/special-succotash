class_name SocomMapDocument
extends RefCounted

const ACTIVE_MAP_PATH := "res://config/maps/current_map.json"
const SCHEMA_VERSION := 1
const SUPPORTED_TYPES: Array[StringName] = [
	&"ground", &"wall", &"cover_low", &"cover_tall", &"platform", &"ramp", &"player_spawn",
	&"point_light", &"ambience_zone",
	&"curved_wall", &"jagged_wall",
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
	&"curved_wall": {"label": "Curved Wall", "size": Vector3(5.0, 3.0, 0.35), "color": Color("687078")},
	&"jagged_wall": {"label": "Broken Wall", "size": Vector3(5.0, 2.6, 0.45), "color": Color("5d6268")},
	&"team_alpha_spawn": {"label": "Alpha Team Spawn", "size": Vector3(1.0, 1.8, 1.0), "color": Color("4fa3ff")},
	&"team_bravo_spawn": {"label": "Bravo Team Spawn", "size": Vector3(1.0, 1.8, 1.0), "color": Color("ff655e")},
	&"bomb_pickup": {"label": "Neutral Bomb Pickup", "size": Vector3(0.8, 0.8, 0.8), "color": Color("f4d34f")},
	&"alpha_bomb_site": {"label": "Alpha Base Target", "size": Vector3(3.0, 0.25, 3.0), "color": Color("4fa3ff")},
	&"bravo_bomb_site": {"label": "Bravo Base Target", "size": Vector3(3.0, 0.25, 3.0), "color": Color("ff655e")},
	&"training_dummy": {"label": "Training Dummy", "size": Vector3(0.8, 1.8, 0.8), "color": Color("f39a55")},
	&"moving_training_dummy": {"label": "Moving Dummy", "size": Vector3(0.8, 1.8, 0.8), "color": Color("50d8df")},
}


static func new_document(map_name: String = "Untitled Tactical Map") -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
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


static func load_active() -> Dictionary:
	var bundled := SocomPlaytestStateCollector.bundled_state("map")
	if not bundled.is_empty():
		return normalize(bundled)
	return load_path(ACTIVE_MAP_PATH)


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
		"enabled": bool(document.get("enabled", true)),
		"name": String(document.get("name", "Untitled Tactical Map")),
		"grid_size": clampf(float(document.get("grid_size", 0.5)), 0.125, 4.0),
		"environment": normalize_environment(document.get("environment", {})),
		"gameplay": normalize_gameplay(document.get("gameplay", {})),
		"objects": [],
	}
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
		"bomb_fuse_seconds": 35,
		"plant_time_seconds": 5.0,
		"respawns_enabled": false,
	}


static func normalize_gameplay(value: Variant) -> Dictionary:
	var source := value as Dictionary if value is Dictionary else {}
	var primary_mode := String(source.get("primary_mode", "demolition"))
	if primary_mode not in ["demolition", "team_deathmatch"]:
		primary_mode = "demolition"
	var supported: Array = source.get("supported_modes", [primary_mode])
	var clean_supported: Array[String] = []
	for mode: Variant in supported:
		var mode_name := String(mode)
		if mode_name in ["demolition", "team_deathmatch"] and mode_name not in clean_supported:
			clean_supported.append(mode_name)
	if primary_mode not in clean_supported:
		clean_supported.push_front(primary_mode)
	return {
		"primary_mode": primary_mode,
		"supported_modes": clean_supported,
		"round_time_seconds": clampi(int(source.get("round_time_seconds", 300)), 60, 1800),
		"bomb_fuse_seconds": clampi(int(source.get("bomb_fuse_seconds", 35)), 10, 120),
		"plant_time_seconds": clampf(float(source.get("plant_time_seconds", 5.0)), 1.0, 20.0),
		"respawns_enabled": bool(source.get("respawns_enabled", primary_mode == "team_deathmatch")),
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
	if type_name == &"training_dummy":
		return {"health": 100.0}
	if type_name == &"moving_training_dummy":
		return {"health": 100.0, "patrol_distance": 6.0, "patrol_speed": 1.5, "turn_pause": 0.35}
	var material := {"texture_path": "", "roughness": 0.9, "metallic": 0.0, "uv_scale": 1.0}
	if type_name == &"curved_wall":
		material.merge({"radius": 4.0, "arc_degrees": 90.0, "segments": 8}, true)
	elif type_name == &"jagged_wall":
		material.merge({"pieces": 6, "height_variance": 0.8, "edge_rotation": 5.0}, true)
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
