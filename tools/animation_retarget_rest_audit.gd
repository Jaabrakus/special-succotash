extends SceneTree

const TARGET := "res://assets/characters/ps1_gas_mask_soldier/trooper_rigged.fbx"
const SOURCE := "res://assets/animations/mixamo/Lite Rifle Pack/idle.fbx"


func _initialize() -> void:
	var target_root := (load(TARGET) as PackedScene).instantiate()
	var source_root := (load(SOURCE) as PackedScene).instantiate()
	root.add_child(target_root)
	root.add_child(source_root)
	var target_skeleton := _find_skeleton(target_root)
	var source_skeleton := _find_skeleton(source_root)
	var source_player := _find_animation_player(source_root)
	print("RETARGET_REST target_bones=%d source_bones=%d" % [
		target_skeleton.get_bone_count(), source_skeleton.get_bone_count(),
	])
	var animation_name := source_player.get_animation_list()[0]
	var animation := source_player.get_animation(animation_name)
	for bone_name in [
		"mixamorig_RightShoulder", "mixamorig_RightArm",
		"mixamorig_RightForeArm", "mixamorig_RightHand",
		"mixamorig_LeftShoulder", "mixamorig_LeftArm",
		"mixamorig_LeftForeArm", "mixamorig_LeftHand",
	]:
		var target_index := target_skeleton.find_bone(bone_name)
		var source_index := source_skeleton.find_bone(bone_name)
		print("RETARGET_REST bone=%s target=%s source=%s" % [
			bone_name,
			target_skeleton.get_bone_rest(target_index) if target_index >= 0 else "missing",
			source_skeleton.get_bone_rest(source_index) if source_index >= 0 else "missing",
		])
		for track_index in animation.get_track_count():
			if not String(animation.track_get_path(track_index)).ends_with(":" + bone_name):
				continue
			print("RETARGET_REST track=%s type=%d value=%s" % [
				animation.track_get_path(track_index),
				animation.track_get_type(track_index),
				animation.track_get_key_value(track_index, 0),
			])
	quit(0)


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for child in node.get_children():
		var found := _find_skeleton(child)
		if found != null:
			return found
	return null


func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var found := _find_animation_player(child)
		if found != null:
			return found
	return null
