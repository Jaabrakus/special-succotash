extends SceneTree

## Empirical weapon-scale calibrator. Boots the real training range, equips
## every catalog firearm through the authorized pickup path, measures the
## equipped mesh's WORLD-space bounding box, and solves normalized_scale so
## the rendered weapon matches the category target length. Then re-equips and
## verifies. Re-run any time the attach chain or FBX imports change.
## Run headless:
##   godot --headless --path . --script res://tools/calibrate_equipped_weapon_scales.gd

const MAIN_SCENE := preload("res://main.tscn")
const CONFIG_DIRECTORY := "res://config/weapons/"

const TARGET_LENGTH_BY_CATEGORY := {
	"Pistols": 0.24,
	"Submachine Guns": 0.55,
	"Shotguns": 0.95,
	"Assault Rifles": 0.90,
	"Sniper Rifles": 1.05,
	"Machine Guns": 1.05,
}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var main := MAIN_SCENE.instantiate()
	root.add_child(main)
	for _frame in 15:
		await process_frame
	var weapon_controller: Node = main.get("weapon_controller") as Node
	var player: Node = main.get("player") as Node
	var mannequin: Node = player.get_node_or_null("Mannequin") as Node
	if weapon_controller == null or mannequin == null:
		push_error("EQUIP_CALIBRATION ERROR controller or mannequin missing")
		quit(1)
		return

	var catalog_file := FileAccess.open(CONFIG_DIRECTORY + "recom_weapons_catalog.json", FileAccess.READ)
	var catalog: Dictionary = (
		(JSON.parse_string(catalog_file.get_as_text()) as Dictionary) if catalog_file else {}
	)
	catalog_file.close()

	var failures := 0
	for raw_record: Variant in (catalog.get("weapons", []) as Array):
		var record := raw_record as Dictionary
		var category := String(record.get("category", ""))
		if not TARGET_LENGTH_BY_CATEGORY.has(category):
			continue
		var weapon_id := String(record.get("weapon_id", ""))
		var target := float(TARGET_LENGTH_BY_CATEGORY[category])

		var measured := await _measure(weapon_controller, mannequin, weapon_id)
		if measured <= 0.0:
			push_error("EQUIP_CALIBRATION ERROR could not measure %s" % weapon_id)
			failures += 1
			continue
		var profile := _read_profile(weapon_id)
		if profile.is_empty():
			push_error("EQUIP_CALIBRATION ERROR profile missing %s" % weapon_id)
			failures += 1
			continue
		var old_scale := float(profile.get("normalized_scale", 1.0))
		var new_scale := old_scale * (target / measured)
		profile["normalized_scale"] = new_scale
		if not _write_profile(weapon_id, profile):
			push_error("EQUIP_CALIBRATION ERROR profile not writable %s" % weapon_id)
			failures += 1
			continue

		var verified := await _measure(weapon_controller, mannequin, weapon_id)
		var ok := absf(verified - target) <= 0.25 * target
		print(
			"EQUIP_CALIBRATION %s %s scale %.6f -> %.6f world %.3fm -> %.3fm (target %.2fm)" % [
				"PASS" if ok else "FAIL",
				weapon_id,
				old_scale,
				new_scale,
				measured,
				verified,
				target,
			]
		)
		if not ok:
			failures += 1

	print("EQUIP_CALIBRATION SUMMARY failures=%d" % failures)
	if failures > 0:
		print("EQUIP_CALIBRATION FAIL")
		quit(1)
		return
	print("EQUIP_CALIBRATION PASS")
	quit(0)


func _measure(weapon_controller: Node, mannequin: Node, weapon_id: String) -> float:
	var ok := bool(weapon_controller.call(
		"apply_authorized_weapon_pickup",
		CONFIG_DIRECTORY + weapon_id + ".json"
	))
	for _frame in 6:
		await process_frame
	if not ok:
		return -1.0
	var candidates := mannequin.find_children("WeaponMesh", "Node3D", true, false)
	if candidates.is_empty():
		return -1.0
	var aabb := _world_aabb(candidates[candidates.size() - 1] as Node3D)
	if aabb.size == Vector3.ZERO:
		return -1.0
	return maxf(aabb.size.x, maxf(aabb.size.y, aabb.size.z))


func _read_profile(weapon_id: String) -> Dictionary:
	var file := FileAccess.open(CONFIG_DIRECTORY + weapon_id + ".json", FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	return (parsed as Dictionary).duplicate(true) if parsed is Dictionary else {}


func _write_profile(weapon_id: String, profile: Dictionary) -> bool:
	var file := FileAccess.open(CONFIG_DIRECTORY + weapon_id + ".json", FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(profile, "  "))
	file.close()
	return true


func _world_aabb(node: Node3D) -> AABB:
	var aabb := AABB()
	var first := true
	var stack: Array[Node] = [node]
	while not stack.is_empty():
		var current := stack.pop_back() as Node
		if current is MeshInstance3D:
			var mi := current as MeshInstance3D
			if mi.mesh != null:
				var box := mi.global_transform * mi.mesh.get_aabb()
				if first:
					aabb = box
					first = false
				else:
					aabb = aabb.merge(box)
		for child in current.get_children():
			stack.append(child)
	return aabb
