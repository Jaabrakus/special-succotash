extends SceneTree

const MANIFEST_PATH := "res://config/agls_traversal_asset_manifest.json"

var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_expect(FileAccess.file_exists(MANIFEST_PATH), "AGLS traversal manifest exists")
	var file := FileAccess.open(MANIFEST_PATH, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(file.get_as_text()) if file != null else null
	_expect(parsed is Dictionary, "AGLS traversal manifest is valid JSON")
	if not parsed is Dictionary:
		_finish()
		return
	var manifest := parsed as Dictionary
	_expect(int(manifest.get("schema_version", 0)) == 1, "manifest schema is supported")
	_expect(String(manifest.get("source_mutation_policy", "")) == "read_only", "AGLS source is read-only")
	var authority: Dictionary = manifest.get("authority", {})
	_expect(String(authority.get("movement", "")) == "CharacterBody3D", "Godot body owns movement")
	_expect(String(authority.get("animation", "")) == "visual_only", "imported root motion is visual-only")

	var families: Dictionary = manifest.get("families", {})
	for family_name in [
		"swimming", "climbing", "ladder", "rope", "zipline",
		"mantle_vault", "narrow_ledge", "wheel_valve",
		"weapon_reload", "weapon_recoil", "weapon_equip", "weapon_pickup",
		"locomotion_idle", "locomotion_walk", "locomotion_run",
		"locomotion_turn", "locomotion_crouch", "locomotion_crawl",
		"locomotion_air", "locomotion_roll", "locomotion_additive", "grenade",
	]:
		_expect(families.has(family_name), "family is cataloged: %s" % family_name)
		var family: Dictionary = families.get(family_name, {})
		_expect(int(family.get("asset_count", 0)) > 0, "family has AGLS references: %s" % family_name)

	var swimming: Dictionary = families.get("swimming", {})
	_expect(int(swimming.get("exportable_count", 0)) >= 15, "swimming has a complete base clip set")
	var swimming_names: Dictionary = {}
	for raw_entry in swimming.get("assets", []):
		if raw_entry is Dictionary:
			swimming_names[String((raw_entry as Dictionary).get("name", ""))] = true
	for required_name in [
		"ALS_Swim_Idle_01",
		"ALS_Swim_Normal_F",
		"ALS_Swim_Freestyle_F",
		"ALS_Swim_Underwater_F",
		"ALS_Swim_Land_Into_Water_02",
	]:
		_expect(swimming_names.has(required_name), "swimming clip is cataloged: %s" % required_name)

	var reload_names := _family_names(families.get("weapon_reload", {}))
	_expect(reload_names.has("ALSP2_Reloading_Rifle_M4A4"), "rifle reload is cataloged")
	_expect(reload_names.has("ALSP2_Reload_Pistol"), "pistol reload is cataloged")
	var recoil_names := _family_names(families.get("weapon_recoil", {}))
	_expect(recoil_names.has("ALSv2_Rifle_Recoil_Offset_01"), "rifle recoil is cataloged")
	_expect(recoil_names.has("ALSv2_Pistol_2H_Recoil_Offset_01"), "pistol recoil is cataloged")
	_finish()


func _family_names(family: Dictionary) -> Dictionary:
	var names: Dictionary = {}
	for raw_entry in family.get("assets", []):
		if raw_entry is Dictionary:
			names[String((raw_entry as Dictionary).get("name", ""))] = true
	return names


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("AGLS_MANIFEST_CHECK PASS ", label)
	else:
		failures.append(label)
		push_error("AGLS_MANIFEST_CHECK FAIL %s" % label)


func _finish() -> void:
	if failures.is_empty():
		print("AGLS_ASSET_MANIFEST_REGRESSION PASS")
		quit(0)
	else:
		print("AGLS_ASSET_MANIFEST_REGRESSION FAIL ", failures)
		quit(1)
