extends SceneTree

const SUIT := preload(
	"res://assets/characters/military_tactical_suit/military_tactical_suit_production.glb"
)


func _initialize() -> void:
	var root_node := SUIT.instantiate() as Node3D
	root.add_child(root_node)
	var skeleton := _find_skeleton(root_node)
	assert(skeleton != null)
	for chain in [
		["mixamorig_LeftArm_033", "mixamorig_LeftForeArm_034", Vector3.RIGHT],
		["mixamorig_LeftForeArm_034", "mixamorig_LeftHand_035", Vector3.RIGHT],
		["mixamorig_RightArm_09", "mixamorig_RightForeArm_010", Vector3.LEFT],
		["mixamorig_RightForeArm_010", "mixamorig_RightHand_011", Vector3.LEFT],
	]:
		var bone_index := skeleton.find_bone(String(chain[0]))
		var child_index := skeleton.find_bone(String(chain[1]))
		var direction := (
			skeleton.get_bone_global_rest(child_index).origin
			- skeleton.get_bone_global_rest(bone_index).origin
		).normalized()
		print("SUIT_BIND_AUDIT_CHAIN bone=%s direction=%s error_degrees=%.6f" % [
			chain[0],
			str(direction),
			rad_to_deg(direction.angle_to(chain[2] as Vector3)),
		])
	var head := skeleton.get_bone_global_rest(
		skeleton.find_bone("mixamorig_Head_06")
	).origin
	var feet := (
		skeleton.get_bone_global_rest(skeleton.find_bone("mixamorig_LeftFoot_065")).origin
		+ skeleton.get_bone_global_rest(skeleton.find_bone("mixamorig_RightFoot_059")).origin
	) * 0.5
	print("SUIT_BIND_AUDIT_REFERENCE height=%.9f head=%s feet=%s" % [
		head.distance_to(feet), str(head), str(feet)
	])
	var mesh_count := 0
	var bind_counts: Array[int] = []
	for mesh in _collect_meshes(root_node):
		mesh_count += 1
		if mesh.skin != null:
			bind_counts.append(mesh.skin.get_bind_count())
	print("SUIT_BIND_AUDIT_SKINS meshes=%d bind_counts=%s" % [mesh_count, str(bind_counts)])
	quit(0)


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for child in node.get_children():
		var found := _find_skeleton(child)
		if found != null:
			return found
	return null


func _collect_meshes(node: Node) -> Array[MeshInstance3D]:
	var meshes: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		meshes.append(node as MeshInstance3D)
	for child in node.get_children():
		meshes.append_array(_collect_meshes(child))
	return meshes
