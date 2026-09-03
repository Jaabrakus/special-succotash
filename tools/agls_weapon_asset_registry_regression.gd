extends SceneTree

const Registry := preload("res://scripts/weapons/agls_weapon_asset_registry.gd")
const MANIFEST_PATH := "res://config/agls_weapon_assets.json"

var failures: Array[String] = []


func _initialize() -> void:
	var file := FileAccess.open(MANIFEST_PATH, FileAccess.READ)
	var manifest: Variant = JSON.parse_string(file.get_as_text()) if file != null else null
	_expect(manifest is Dictionary, "AGLS weapon manifest is valid JSON")
	if not manifest is Dictionary:
		_finish()
		return
	var weapons: Dictionary = (manifest as Dictionary).get("weapons", {})
	_expect(weapons.size() == 12, "all twelve AGLS weapon assets are cataloged")
	for required_id in ["m4a1", "ak47", "m9", "desert_eagle"]:
		_expect(weapons.has(required_id), "%s AGLS asset is cataloged" % required_id)

	for profile_path in [
		"res://config/weapons/m4a1.json",
		"res://config/weapons/ak-47.json",
		"res://config/weapons/m9.json",
		"res://config/weapons/de__50.json",
	]:
		var profile_file := FileAccess.open(profile_path, FileAccess.READ)
		var profile: Variant = (
			JSON.parse_string(profile_file.get_as_text())
			if profile_file != null
			else null
		)
		_expect(profile is Dictionary, "%s profile loads" % profile_path.get_file())
		if not profile is Dictionary:
			continue
		var fallback := String((profile as Dictionary).get("model_fbx", ""))
		var resolved := Registry.preferred_model_path(profile as Dictionary)
		_expect(
			resolved == fallback or resolved.contains("/agls_intake/imported/weapons/"),
			"%s resolves to an AGLS mesh or its safe fallback" % profile_path.get_file()
		)
		_expect(ResourceLoader.exists(resolved), "%s resolved mesh is loadable" % profile_path.get_file())
	_finish()


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("AGLS_WEAPON_ASSET_CHECK PASS %s" % label)
		return
	failures.append(label)
	push_error("AGLS_WEAPON_ASSET_CHECK FAIL %s" % label)


func _finish() -> void:
	if failures.is_empty():
		print("AGLS_WEAPON_ASSET_REGRESSION PASS")
		quit(0)
		return
	print("AGLS_WEAPON_ASSET_REGRESSION FAIL %s" % [failures])
	quit(1)
