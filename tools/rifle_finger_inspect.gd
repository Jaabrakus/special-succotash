extends "res://tools/seal_locomotion_visual_probe.gd"

func _sample(state: String) -> void:
	await super._sample(state)
	if not state.ends_with("_fire"):
		return
	var s: Skeleton3D = driver.skeleton
	var contact = preload("res://scripts/player/operator_weapon_contact_solver.gd")
	for side in ["Right", "Left"]:
		var hand := s.find_bone("mixamorig_" + side + "Hand")
		var hand_rest: Transform3D = contact.bone_global_rest(s, hand)
		for finger in ["Index", "Middle", "Thumb"]:
			for i in range(1, 4):
				var idx := s.find_bone("mixamorig_%sHand%s%d" % [side, finger, i])
				var rest: Transform3D = contact.bone_global_rest(s, idx)
				print("FINGER_REST ", side, finger, i, " handspace=", hand_rest.affine_inverse() * rest, " pose=", s.get_bone_pose_rotation(idx))
	print("FINGER_META ", driver.weapon_node.get_meta("support_hand_pose", {}))
