class_name SocomCharacterAppearanceProfile
extends RefCounted

const DEFAULT_PATH := "res://config/character_appearance.json"
const SAVE_PATH := "user://character_appearance.json"
const COLORS := {"source": Color.WHITE, "black": Color(.24,.26,.29), "green": Color(.40,.56,.36), "blue": Color(.40,.61,.95), "white": Color(1,1,1)}
const GEAR := {"cap": ["Cap", "SKM_Patch_Flag_Cap"], "vest": ["Bulletproof", "SKM_Patch_Back"], "pouches": ["Drops_1"], "holster": ["Holster_Hard", "Pistol_Leg"], "patches": ["SKM_Patch_Back", "SKM_Patch_Flag_Cap"]}

static func defaults() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(DEFAULT_PATH)) as Dictionary

static func sanitize(raw: Dictionary) -> Dictionary:
	var data := defaults()
	for key in ["shirt", "pants"]:
		if COLORS.has(String(raw.get(key, ""))):
			data[key] = String(raw[key])
	for key in GEAR:
		if raw.get(key) is bool:
			data[key] = raw[key]
	return data

static func load_profile(path: String = SAVE_PATH) -> Dictionary:
	if not FileAccess.file_exists(path):
		return defaults()
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return sanitize(data) if data is Dictionary else defaults()

static func save_profile(data: Dictionary, path: String = SAVE_PATH) -> Error:
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(sanitize(data), "\t"))
	file.close()
	return DirAccess.rename_absolute(path + ".tmp", path)

static func visible_mesh(name: String, data: Dictionary) -> bool:
	for key in GEAR:
		if name in GEAR[key] and not bool(data.get(key, true)):
			return false
	return true

static func tint(name: String, data: Dictionary) -> Color:
	var key := "shirt" if name == "Shirt_RolledUp" else "pants" if name == "Jeans_Tactic" else ""
	return COLORS.get(String(data.get(key, "source")), Color.WHITE)
