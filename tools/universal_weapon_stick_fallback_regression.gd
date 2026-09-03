extends SceneTree

const RESOLVER := preload(
	"res://scripts/labs/gunsmith2/weapon_visual_rig_resolver.gd"
)
const CONTRACT := preload(
	"res://scripts/labs/gunsmith2/weapon_visual_rig_contract.gd"
)
const WEAPON_DIRECTORY := "res://config/weapons"
const FALLBACK_ID := "universal_starter_stick_v1"
const STICK_SCENE := "res://assets/weapons/placeholders/universal_weapon_stick.tscn"


func _init() -> void:
	RESOLVER.clear_cache()
	var fallback := RESOLVER.load_published(FALLBACK_ID)
	_assert(not fallback.is_empty(), "published fallback loads")
	var fallback_visual: Dictionary = fallback.get("visual", {})
	_assert(String(fallback_visual.get("model_fbx", "")) == STICK_SCENE, "stick scene is published")
	_assert(load(STICK_SCENE) is PackedScene, "stick scene is loadable")
	_assert(
		is_equal_approx(float(fallback_visual.get("normalized_scale", 0.0)), 1.0),
		"stick scene keeps its meter-authored scale"
	)
	var checked := 0
	var fallback_count := 0
	var explicit_count := 0
	var directory := DirAccess.open(WEAPON_DIRECTORY)
	_assert(directory != null, "weapon directory opens")
	if directory == null:
		quit(1)
		return
	for file_name in directory.get_files():
		if file_name.get_extension().to_lower() != "json":
			continue
		var profile := _read_json("%s/%s" % [WEAPON_DIRECTORY, file_name])
		if profile.is_empty() or not profile.has("weapon_id"):
			continue
		checked += 1
		var resolved := RESOLVER.resolve_for_presentation(profile)
		var explicit_id := String(profile.get("visual_rig_id", ""))
		_assert(String(resolved.get("_visual_rig_id", "")) == FALLBACK_ID, "%s uses universal stick" % file_name)
		_assert(String(resolved.get("model_fbx", "")) == STICK_SCENE, "%s uses stick mesh" % file_name)
		_assert_preserved(profile, resolved, file_name)
		if explicit_id.is_empty():
			fallback_count += 1
		else:
			explicit_count += 1
	var authority_probe := {
		"weapon_id": "authority_probe",
		"catalog_id": "catalog_probe",
		"ammo": 17,
		"magazine_capacity": 30,
		"reserve_ammo": 90,
		"damage": 41.0,
		"fire_modes": ["SEMI", "BURST"],
		"default_fire_mode": "BURST",
		"ballistics": {"muzzle_velocity_mps": 915.0, "penetration": 0.42},
		"inventory_state": {"slot": 2, "equipped": true, "rounds": 17},
		"muzzle_metadata": {"authority": "server", "revision": 7},
		"weapon_sockets": {"muzzle_socket": {"x": 9.0, "y": 8.0, "z": 7.0}},
	}
	var authority_resolved := RESOLVER.resolve_for_presentation(authority_probe)
	_assert_preserved(authority_probe, authority_resolved, "authority_probe")
	_assert(checked >= 40, "all catalog weapon profiles checked")
	_assert(fallback_count > 0, "fallback path covered")
	_assert(explicit_count > 0, "explicit-rig replacement path covered")
	print(
		"UNIVERSAL_WEAPON_STICK_ALL_PROFILES_PASS profiles=%d default=%d replaced_explicit=%d" % [
			checked,
			fallback_count,
			explicit_count,
		]
	)
	quit(0)


func _assert_preserved(original: Dictionary, resolved: Dictionary, label: String) -> void:
	var presentation_changes := CONTRACT.VISUAL_FIELDS.duplicate()
	presentation_changes.erase("weapon_sockets")
	for key: Variant in original:
		if String(key) in presentation_changes:
			continue
		_assert(
			resolved.get(key) == original[key],
			"%s preserves %s" % [label, String(key)]
		)


func _read_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed as Dictionary if parsed is Dictionary else {}


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error("UNIVERSAL_WEAPON_STICK_FALLBACK_FAIL %s" % message)
	quit(1)
