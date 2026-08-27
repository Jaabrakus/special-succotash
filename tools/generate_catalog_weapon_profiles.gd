extends SceneTree

## Generates an authored weapon profile (config/weapons/<id>.json) for every
## reCOM catalog firearm that does not have one yet, using the Gunsmith
## adapter's catalog-baseline merge. Existing authored profiles are never
## overwritten. Run headless:
##   godot --headless --path . --script res://tools/generate_catalog_weapon_profiles.gd

const RecomAdapter := preload("res://scripts/labs/gunsmith/gunsmith_recom_catalog_adapter.gd")
const Repository := preload("res://scripts/labs/gunsmith/gunsmith_weapon_profile_repository.gd")
const CONFIG_DIRECTORY := "res://config/weapons/"


func _initialize() -> void:
	var created: Array[String] = []
	var kept: Array[String] = []
	var failed: Array[String] = []

	var categories: Dictionary = RecomAdapter.gunsmith_categories()
	for raw_category: Variant in categories.keys():
		for raw_id: Variant in categories[raw_category]:
			var weapon_id := String(raw_id).to_lower()
			var path := CONFIG_DIRECTORY + weapon_id + ".json"
			if FileAccess.file_exists(path):
				kept.append(weapon_id)
				continue
			var profile: Dictionary = RecomAdapter.load_editable_profile(weapon_id)
			if profile.is_empty():
				failed.append(weapon_id)
				continue
			var file := FileAccess.open(path, FileAccess.WRITE)
			if file == null:
				failed.append(weapon_id)
				continue
			file.store_string(JSON.stringify(profile, "  "))
			file.close()
			created.append(weapon_id)

	print(
		"CATALOG_PROFILE_GENERATION created=%d kept=%d failed=%d" % [
			created.size(),
			kept.size(),
			failed.size(),
		]
	)
	if not failed.is_empty():
		push_error("CATALOG_PROFILE_GENERATION failed ids: %s" % ", ".join(failed))
		quit(1)
		return
	print("CATALOG_PROFILE_GENERATION PASS")
	quit(0)
