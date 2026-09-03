extends SceneTree

## Read-only behavioral probe for the supplied Godot 4.6 NEW IK AIM project.
## Run with that project as --path so its Player scene and import cache are used.


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var packed := load("res://Node/Player.tscn") as PackedScene
	if packed == null:
		push_error("REFERENCE_NATIVE_IK_PROBE could not load Player.tscn")
		quit(1)
		return
	var player := packed.instantiate()
	root.add_child(player)
	for _frame in range(12):
		await process_frame
	var skeleton := player.get_node("Model/GeneralSkeleton") as Skeleton3D
	var modifier := skeleton.get_node("LHTwoBoneIK3D") as TwoBoneIK3D
	var palm_copy := skeleton.get_node("LHCopyTransformModifier3D2") as CopyTransformModifier3D
	var hand_index := modifier.get_end_bone(0)
	var target := modifier.get_node(modifier.get_target_node(0)) as Node3D
	var pole := modifier.get_node(modifier.get_pole_node(0)) as Node3D
	var hand_world := (
		skeleton.global_transform * skeleton.get_bone_global_pose(hand_index)
	).origin
	print(
		"REFERENCE_NATIVE_IK_PROBE active=", modifier.active,
		" callback=", skeleton.modifier_callback_mode_process,
		" hand=", hand_world,
		" target=", target.global_position,
		" error_m=", hand_world.distance_to(target.global_position)
	)
	modifier.active = false
	palm_copy.active = false
	for _frame in range(4):
		await process_frame
	var dynamic_target := Marker3D.new()
	dynamic_target.name = "DynamicReferenceTarget"
	skeleton.add_child(dynamic_target)
	dynamic_target.global_transform = target.global_transform
	var dynamic_pole := Marker3D.new()
	dynamic_pole.name = "DynamicReferencePole"
	skeleton.add_child(dynamic_pole)
	dynamic_pole.global_transform = pole.global_transform
	var dynamic_ik := TwoBoneIK3D.new()
	dynamic_ik.name = "DynamicReferenceIK"
	dynamic_ik.set_setting_count(1)
	dynamic_ik.set_target_node(0, NodePath("../DynamicReferenceTarget"))
	dynamic_ik.set_pole_node(0, NodePath("../DynamicReferencePole"))
	dynamic_ik.set_root_bone_name(0, "LeftUpperArm")
	dynamic_ik.set_root_bone(0, 6)
	dynamic_ik.set_middle_bone_name(0, "LeftLowerArm")
	dynamic_ik.set_middle_bone(0, 7)
	dynamic_ik.set_end_bone_name(0, "LeftHand")
	dynamic_ik.set_end_bone(0, 8)
	dynamic_ik.set_use_virtual_end(0, false)
	dynamic_ik.set_extend_end_bone(0, false)
	skeleton.add_child(dynamic_ik)
	for _frame in range(8):
		await process_frame
	var dynamic_hand_world := (
		skeleton.global_transform * skeleton.get_bone_global_pose(hand_index)
	).origin
	print(
		"REFERENCE_NATIVE_IK_DYNAMIC active=", dynamic_ik.active,
		" target_path=", dynamic_ik.get_target_node(0),
		" hand=", dynamic_hand_world,
		" target=", dynamic_target.global_position,
		" error_m=", dynamic_hand_world.distance_to(dynamic_target.global_position)
	)
	for bone_index in [6, 7, 8]:
		print(
			"REFERENCE_NATIVE_IK_CHAIN bone=", skeleton.get_bone_name(bone_index),
			" parent=", skeleton.get_bone_parent(bone_index),
			" rest=", skeleton.get_bone_rest(bone_index),
			" pose_scale=", skeleton.get_bone_pose_scale(bone_index)
		)
	quit()
