extends "res://tools/main_pistol_source_attachment_regression.gd"

## Translation card: diagnose the existing mount roll relative to the current
## skinned palm. Same main/weapon owner; no saved edits, no arm or gameplay writes.
## Focused proof: measured local bore/up and independently captured roll candidates.
func _sample(state: String) -> void:
	if not state.ends_with("standing_idle"): return
	var pose: Node3D = driver.weapon_pose_solver
	var palm: Transform3D = pose._right_hand_grip_world_transform()
	var bore: Vector3 = pose.barrel_base_socket.global_position.direction_to(pose.muzzle_socket.global_position)
	var up: Vector3 = (pose.barrel_base_socket.global_position - pose.trigger_socket.global_position).slide(bore).normalized()
	print("PISTOL_MOUNT_FRAME ", JSON.stringify({"bore_in_palm": str(palm.basis.inverse() * bore), "up_in_palm": str(palm.basis.inverse() * up), "palm_anchor": str(pose.right_palm_anchor_local)}))
	var source_mount: Transform3D = pose.weapon_hand_mount_transform
	var local_bore := palm.basis.inverse() * bore
	var finger_points := {}
	for finger in ["Index", "Middle", "Ring", "Pinky", "Thumb"]:
		for segment in range(1, 4):
			var name := "mixamorig_RightHand%s%d" % [finger, segment]
			var bone: int = pose.skeleton.find_bone(name)
			finger_points[name] = str(palm.affine_inverse() * (pose.skeleton.global_transform * pose.skeleton.get_bone_global_pose(bone)).origin)
	print("PISTOL_FINGER_POINTS_M ", JSON.stringify(finger_points))
	if "--palm-offsets" in OS.get_cmdline_user_args():
		var source_offset: Vector3 = pose.source_pistol_palm_offset_m
		for offset in [Vector3.ZERO, Vector3(0,0,.02), Vector3(0,0,.035), Vector3(0,.015,.035), Vector3(0,.025,.045)]:
			pose.source_pistol_palm_offset_m = offset
			pose._weapon_transform_on_trigger_hand(pose._right_hand_grip_world_transform(), true)
			_force_descendants(pose.weapon_node)
			await super._sample("palm_offset_%d_%d_%d_mm" % [roundi(offset.x*1000), roundi(offset.y*1000), roundi(offset.z*1000)])
		pose.source_pistol_palm_offset_m = source_offset
		print("PISTOL_MOUNT_PROBE ", JSON.stringify({"result":"PASS" if failures.is_empty() else "FAIL", "samples":samples.size(), "failures":failures}))
		quit(0 if failures.is_empty() else 1)
		return
	for roll in [0.0, 90.0, -90.0, 180.0]:
		pose.weapon_hand_mount_transform.basis = Basis(local_bore, deg_to_rad(roll)) * source_mount.basis
		pose._weapon_transform_on_trigger_hand(palm, true)
		_force_descendants(pose.weapon_node)
		print("PISTOL_ACTUAL_ROLL ", roll, " up_in_palm=", palm.basis.inverse() * (pose.barrel_base_socket.global_position - pose.trigger_socket.global_position).slide(bore).normalized())
		await super._sample("mount_roll_" + str(int(roll)))
	pose.weapon_hand_mount_transform = source_mount
	print("PISTOL_MOUNT_PROBE ", JSON.stringify({"result":"PASS" if failures.is_empty() else "FAIL", "samples":samples.size(), "failures":failures}))
	quit(0 if failures.is_empty() else 1)

func _force_descendants(node: Node) -> void:
	if node is Node3D:
		(node as Node3D).force_update_transform()
	for child in node.get_children():
		_force_descendants(child)
