extends SceneTree

## Read-only audit: for every catalog firearm profile, measures the raw FBX
## AABB and compares the profile's effective weapon length
## (long_axis * normalized_scale) against the category target. Reports each
## weapon as OK or MISMATCH so scale regressions are impossible to miss.
## Run headless:
##   godot --headless --path . --script res://tools/verify_weapon_profile_scales.gd

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
	var catalog_file := FileAccess.open(CONFIG_DIRECTORY + "recom_weapons_catalog.json", FileAccess.READ)
	var catalog: Dictionary = (
		(JSON.parse_string(catalog_file.get_as_text()) as Dictionary) if catalog_file else {}
	)
	catalog_file.close()

	var mismatches := 0
	for raw_record: Variant in (catalog.get("weapons", []) as Array):
		var record := raw_record as Dictionary
		var category := String(record.get("category", ""))
		if not TARGET_LENGTH_BY_CATEGORY.has(category):
			continue
		var weapon_id := String(record.get("weapon_id", ""))
		var path := CONFIG_DIRECTORY + weapon_id + ".json"
		if not FileAccess.file_exists(path):
			print("SCALE_AUDIT MISMATCH %s no-profile" % weapon_id)
			mismatches += 1
			continue
		var file := FileAccess.open(path, FileAccess.READ)
		var profile: Dictionary = (JSON.parse_string(file.get_as_text()) as Dictionary) if file else {}
		file.close()
		var fbx := String(profile.get("model_fbx", ""))
		var scene := load(fbx) as PackedScene
		if scene == null:
			print("SCALE_AUDIT MISMATCH %s model-unloadable (%s)" % [weapon_id, fbx])
			mismatches += 1
			continue
		var node := scene.instantiate() as Node3D
		root.add_child(node)
		var aabb := _combined_aabb(node)
		node.queue_free()
		var long_axis := 0
		if aabb.size.y > aabb.size[long_axis]:
			long_axis = 1
		if aabb.size.z > aabb.size[long_axis]:
			long_axis = 2
		var raw_length := aabb.size[long_axis]
		var scale := float(profile.get("normalized_scale", 1.0))
		var effective := raw_length * scale
		var target := float(TARGET_LENGTH_BY_CATEGORY[category])
		var ratio := effective / target if target > 0.0 else 0.0
		if ratio > 1.6 or ratio < 0.625:
			print(
				"SCALE_AUDIT MISMATCH %s (%s) raw=%.3fm scale=%.4f effective=%.3fm target=%.2fm ratio=%.2f" % [
					weapon_id, fbx.get_file(), raw_length, scale, effective, target, ratio,
				]
			)
			mismatches += 1
		else:
			print(
				"SCALE_AUDIT OK %s (%s) effective=%.3fm target=%.2fm" % [
					weapon_id, fbx.get_file(), effective, target,
				]
			)

	print("SCALE_AUDIT SUMMARY total-firearms-with-mismatches=%d" % mismatches)
	if mismatches > 0:
		print("SCALE_AUDIT FAIL")
		quit(1)
		return
	print("SCALE_AUDIT PASS")
	quit(0)


func _combined_aabb(node: Node3D) -> AABB:
	var aabb := AABB()
	var first := true
	for child in node.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := child as MeshInstance3D
		if mesh_instance.mesh == null:
			continue
		var mesh_aabb := mesh_instance.global_transform * mesh_instance.mesh.get_aabb()
		if first:
			aabb = mesh_aabb
			first = false
		else:
			aabb = aabb.merge(mesh_aabb)
	return aabb
