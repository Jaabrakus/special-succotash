extends SceneTree

const SOURCE_SCENE := "res://assets/characters/ps1_gas_mask_soldier/trooper_rigged.fbx"
const SKELETON_CONTRACT := preload("res://scripts/player/operator_skeleton_contract.gd")


func _init() -> void:
	var packed := load(SOURCE_SCENE) as PackedScene
	if packed == null:
		push_error("INDEX_PROBE source scene failed to load: %s" % SOURCE_SCENE)
		quit(1)
		return
	var root := packed.instantiate()
	var skeleton := _find_skeleton(root)
	if skeleton == null:
		push_error("INDEX_PROBE source scene has no Skeleton3D")
		root.free()
		quit(1)
		return
	print("INDEX_PROBE root=", root.name, " skeleton=", root.get_path_to(skeleton), " count=", skeleton.get_bone_count())
	for bone_index in range(skeleton.get_bone_count()):
		print("INDEX_PROBE_ALL index=", bone_index, " bone=", skeleton.get_bone_name(bone_index))
	for bone_name in [
		"mixamorig_Spine",
		"mixamorig_Spine1",
		"mixamorig_Spine2",
		"mixamorig_Neck",
		"mixamorig_Head",
		"mixamorig_RightShoulder",
		"mixamorig_RightArm",
		"mixamorig_RightForeArm",
		"mixamorig_RightHand",
		"mixamorig_LeftShoulder",
		"mixamorig_LeftArm",
		"mixamorig_LeftForeArm",
		"mixamorig_LeftHand",
	]:
		print("INDEX_PROBE bone=", bone_name, " index=", skeleton.find_bone(bone_name))
	SKELETON_CONTRACT.ensure_65_bones(skeleton)
	for bone_index in range(41, skeleton.get_bone_count()):
		print("AUTHORED_BONE bones/", bone_index, "/name = &\"", skeleton.get_bone_name(bone_index), "\"")
		print("AUTHORED_BONE bones/", bone_index, "/parent = ", skeleton.get_bone_parent(bone_index))
		print("AUTHORED_BONE bones/", bone_index, "/rest = ", skeleton.get_bone_rest(bone_index))
		print("AUTHORED_BONE bones/", bone_index, "/enabled = true")
	root.free()
	quit()


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for child in node.get_children():
		var found := _find_skeleton(child)
		if found != null:
			return found
	return null
