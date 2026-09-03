extends SceneTree

const REFERENCES := {
	"character": "res://ik-demo-4.6-main/assets/models/IK_character.glb",
	"animated_character": "res://ik-demo-4.6-main/assets/models/IK_character_animation.glb",
}

const REQUIRED_ARM_BONES := [
	&"mixamorig_RightArm",
	&"mixamorig_RightForeArm",
	&"mixamorig_RightHand",
	&"mixamorig_LeftArm",
	&"mixamorig_LeftForeArm",
	&"mixamorig_LeftHand",
]


func _init() -> void:
	var failed := false
	for label: String in REFERENCES:
		var scene_path: String = REFERENCES[label]
		var packed := load(scene_path) as PackedScene
		if packed == null:
			push_error("IK intake could not load %s" % scene_path)
			failed = true
			continue
		var instance := packed.instantiate()
		root.add_child(instance)
		var skeleton := _find_skeleton(instance)
		var animation_player := _find_animation_player(instance)
		if skeleton == null:
			push_error("IK intake found no Skeleton3D in %s" % scene_path)
			failed = true
			instance.queue_free()
			continue
		var missing: Array[StringName] = []
		for bone_name: StringName in REQUIRED_ARM_BONES:
			if skeleton.find_bone(bone_name) < 0:
				missing.append(bone_name)
		var animations: Array[StringName] = []
		if animation_player != null:
			animations = animation_player.get_animation_list()
		print(
			"IK_REFERENCE ", label,
			" bones=", skeleton.get_bone_count(),
			" required_arm_chain=", "PASS" if missing.is_empty() else "FAIL",
			" animations=", animations
		)
		if not missing.is_empty():
			push_error("IK intake missing arm bones: %s" % [missing])
			failed = true
		instance.queue_free()
	print(
		"IK_REFERENCE native_two_bone=",
		"PASS" if ClassDB.class_exists("TwoBoneIK3D") else "FAIL"
	)
	if not ClassDB.class_exists("TwoBoneIK3D"):
		failed = true
	quit(1 if failed else 0)


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for child: Node in node.get_children():
		var found := _find_skeleton(child)
		if found != null:
			return found
	return null


func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child: Node in node.get_children():
		var found := _find_animation_player(child)
		if found != null:
			return found
	return null
