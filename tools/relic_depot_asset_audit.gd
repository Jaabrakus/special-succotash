extends SceneTree
const BASE := "res://art_source/sketchfab_intake_20260906/prepared/"
func _initialize() -> void:
	call_deferred("_run")
func _run() -> void:
	for path: String in ["res://assets/characters/ps1_gas_mask_soldier/trooper_rigged.fbx", BASE + "ps1low_poly_night_vision_special_forces_soldier/imported.scn"]:
		var scene := (load(path) as PackedScene).instantiate()
		root.add_child(scene)
		print("ASSET ", path)
		for sk: Skeleton3D in scene.find_children("*", "Skeleton3D", true, false):
			print("SKELETON ", sk.global_transform)
			for i in sk.get_bone_count():
				print(i, " ", sk.get_bone_name(i), " ", sk.global_transform * sk.get_bone_global_rest(i).origin)
		for mesh: MeshInstance3D in scene.find_children("*", "MeshInstance3D", true, false):
			print("MESH ", mesh.name, " ", mesh.transform, " skin=", mesh.skin)
		scene.free()
	for pack: String in ["psx_industrial_pack", "psx_tropical_pack_v1", "rocks_-_psx_low_poly", "psx_shipping_containers_2", "psx_old_warehouse"]:
		var scene := (load(BASE + pack + "/imported.scn") as PackedScene).instantiate()
		print("PACK ", pack)
		scene.print_tree_pretty()
		scene.free()
	quit()
