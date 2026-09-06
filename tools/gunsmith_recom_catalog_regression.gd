extends SceneTree

const WeaponCatalog := preload("res://scripts/weapons/socom_weapon_catalog.gd")
const Adapter := preload(
	"res://scripts/labs/gunsmith/gunsmith_recom_catalog_adapter.gd"
)
const Persistence := preload(
	"res://scripts/labs/gunsmith/gunsmith_persistence_controller.gd"
)
const Repository := preload(
	"res://scripts/labs/gunsmith/gunsmith_weapon_profile_repository.gd"
)


func _initialize() -> void:
	var all_items := WeaponCatalog.get_all_weapons()
	var baseline: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(WeaponCatalog.CATALOG_PATH))
	var registry: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(WeaponCatalog.EXTENSIONS_PATH))
	assert(baseline.weapons.size() == 60, "Original reCOM catalog must retain all 60 items")
	for original: Dictionary in baseline.weapons:
		var expected := original.duplicate(true)
		expected.merge(registry.get("metadata_overrides", {}).get(String(original.weapon_id), {}), true)
		assert(WeaponCatalog.get_weapon(String(original.weapon_id)) == expected, "Only explicit metadata may differ from archived reCOM record")
	assert(all_items.size() == 63, "Expected preserved catalog plus three prototype shotguns")
	var categories := Adapter.gunsmith_categories()
	var firearm_count := 0
	for category: String in categories:
		firearm_count += (categories[category] as Array).size()
		for weapon_id: String in categories[category]:
			var resolved := Adapter.resolve(weapon_id)
			assert(not resolved.is_empty(), "Gunsmith record did not resolve: %s" % weapon_id)
			assert(
				FileAccess.file_exists(String(resolved.model_fbx)),
				"Gunsmith fallback mesh is missing: %s" % resolved.model_fbx
			)
	assert(firearm_count == 37, "Expected 37 firearm records, got %d" % firearm_count)
	assert(not WeaponCatalog.get_weapon("m67").is_empty(), "Equipment catalog lost M67")
	assert(Adapter.resolve("m67").is_empty(), "Grenades must not enter the firearm rig editor")

	var m16 := Adapter.load_editable_profile("m16a2")
	assert(String(m16.get("weapon_id")) == "m16a2", "M16A2 identity was not applied")
	assert(String(m16.get("display_name")) == "M16A2", "M16A2 display name mismatch")
	assert(float(m16.get("ballistics", {}).get("fire_rate_rpm", 0.0)) == 600.0, "M16A2 RPM mismatch")
	assert(m16.get("fire_modes") == ["semi", "burst"], "M16A2 fire modes mismatch")
	assert(int(m16.get("burst_size", 0)) == 3, "M16A2 burst size mismatch")
	assert(
		Adapter._has_complete_visual_calibration(m16),
		"M16A2 must carry a complete, per-model visual calibration"
	)
	assert(
		not Adapter._has_complete_visual_calibration({
			"weapon_id": "raw_catalog_entry",
			"normalized_scale": 1.0,
		}),
		"A raw JSON catalog entry must never masquerade as an approved weapon rig"
	)
	var loadout := Repository.build_operator_loadout("m16a2")
	assert(
		String(loadout.get("primary_weapon_id", "")) == "m16a2"
			and String(loadout.get("rig_config", "")).ends_with("m16a2.json"),
		"Only the explicit equip action builds the canonical gameplay loadout"
	)

	var saved := Adapter.decorate_saved_profile({
		"ballistics": {"damage": 99.0},
		"weapon_sockets": {"muzzle_socket": {"x": 1.0}},
	}, "m16a2")
	assert(float(saved.ballistics.damage) == 99.0, "Editable tuning was overwritten")
	assert(float(saved.weapon_sockets.muzzle_socket.x) == 1.0, "Authored sockets were overwritten")
	assert(String(saved.model_fbx).ends_with("AssaultRifle_1.fbx"), "M16A2 visual mapping mismatch")

	var contact := Vector3(0.25, 0.05, -0.10)
	var stances := {"STANDING": {"left_grip": {}}}
	var hands := {"aim_idle": {"left_grip": {}}}
	var frames := {"aim_idle": {"0": {"left_hand_target": {}}}}
	Persistence.synchronize_ready_contact(stances, hands, frames, contact)
	assert(_vector(stances.STANDING.left_grip).is_equal_approx(contact), "Standing contact did not follow the physical socket")
	assert(_vector(hands.aim_idle.left_grip).is_equal_approx(contact), "Aim Idle contact did not follow the physical socket")
	assert(_vector(frames.aim_idle["0"].left_hand_target).is_equal_approx(contact), "Aim Idle frame zero did not follow the physical socket")

	print("GUNSMITH_RECOM_CATALOG_REGRESSION PASS firearms=%d catalog=%d" % [
		firearm_count,
		all_items.size(),
	])
	quit(0)


func _vector(data: Dictionary) -> Vector3:
	return Vector3(float(data.get("x", 0.0)), float(data.get("y", 0.0)), float(data.get("z", 0.0)))
