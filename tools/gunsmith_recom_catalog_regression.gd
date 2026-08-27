extends SceneTree

const WeaponCatalog := preload("res://scripts/weapons/socom_weapon_catalog.gd")
const Adapter := preload(
	"res://scripts/labs/gunsmith/gunsmith_recom_catalog_adapter.gd"
)
const Persistence := preload(
	"res://scripts/labs/gunsmith/gunsmith_persistence_controller.gd"
)


func _initialize() -> void:
	var all_items := WeaponCatalog.get_all_weapons()
	assert(all_items.size() == 60, "Complete reCOM catalog must retain all 60 items")
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
	assert(firearm_count == 34, "Expected 34 firearm records, got %d" % firearm_count)
	assert(not WeaponCatalog.get_weapon("m67").is_empty(), "Equipment catalog lost M67")
	assert(Adapter.resolve("m67").is_empty(), "Grenades must not enter the firearm rig editor")

	var m16 := Adapter.load_editable_profile("m16a2")
	assert(String(m16.get("weapon_id")) == "m16a2", "M16A2 identity was not applied")
	assert(String(m16.get("display_name")) == "M16A2", "M16A2 display name mismatch")
	assert(float(m16.get("ballistics", {}).get("fire_rate_rpm", 0.0)) == 600.0, "M16A2 RPM mismatch")
	assert(m16.get("fire_modes") == ["semi", "burst"], "M16A2 fire modes mismatch")
	assert(int(m16.get("burst_size", 0)) == 3, "M16A2 burst size mismatch")

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
