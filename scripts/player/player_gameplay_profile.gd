class_name PlayerGameplayProfile
extends RefCounted

## Shared player durability settings. Weapon profiles must never own these values.

const CONFIG_PATH := "res://config/player_gameplay_profile.json"
const DEFAULT_MAX_HEALTH := 100.0
const MAX_GRENADES_PER_TYPE := 3
const DEFAULT_GRENADE_LIMITS := {
	"frag": 3,
	"flash": 3,
	"smoke": 3,
}


static func load_profile() -> Dictionary:
	var bundled := SocomPlaytestStateCollector.bundled_state("player_gameplay")
	if not bundled.is_empty():
		return normalize(bundled)
	if not FileAccess.file_exists(CONFIG_PATH):
		return normalize({})
	var file := FileAccess.open(CONFIG_PATH, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(file.get_as_text()) if file else null
	return normalize(parsed as Dictionary if parsed is Dictionary else {})


static func save_max_health(value: float) -> bool:
	var profile := load_profile()
	profile["max_health"] = clampf(value, 1.0, 1000.0)
	return _write_profile(profile)


static func save_grenade_limits(values: Dictionary) -> bool:
	var profile := load_profile()
	var limits: Dictionary = profile.get("grenade_limits", {}).duplicate(true)
	for type_name in DEFAULT_GRENADE_LIMITS:
		limits[type_name] = clampi(
			int(values.get(type_name, limits.get(type_name, 3))),
			0,
			MAX_GRENADES_PER_TYPE
		)
	profile["grenade_limits"] = limits
	return _write_profile(profile)


static func _write_profile(profile: Dictionary) -> bool:
	var file := FileAccess.open(CONFIG_PATH, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(profile, "  ") + "\n")
	file.close()
	return true


static func normalize(raw: Dictionary) -> Dictionary:
	var raw_limits: Dictionary = (
		raw.get("grenade_limits", {}) as Dictionary
		if raw.get("grenade_limits", {}) is Dictionary
		else {}
	)
	var grenade_limits: Dictionary = {}
	for type_name in DEFAULT_GRENADE_LIMITS:
		grenade_limits[type_name] = clampi(
			int(raw_limits.get(type_name, DEFAULT_GRENADE_LIMITS[type_name])),
			0,
			MAX_GRENADES_PER_TYPE
		)
	return {
		"schema_version": maxi(1, int(raw.get("schema_version", 1))),
		"max_health": clampf(float(raw.get("max_health", DEFAULT_MAX_HEALTH)), 1.0, 1000.0),
		"grenade_limits": grenade_limits,
	}
