extends SceneTree

func _init():
	var main_scene = load("res://main.tscn").instantiate()
	root.add_child(main_scene)
	for f in 40:
		await physics_frame
	var player = main_scene.get_node("Player") as CharacterBody3D
	var driver = player.get_node("Mannequin/ProductionAnimation")
	var skel = driver.get("skeleton") as Skeleton3D
	var posture_layer = driver.get("posture_layer")
	var spine_idx = skel.find_bone("mixamorig_Spine")
	var spine2_idx = skel.find_bone("mixamorig_Spine2")
	var hips_idx = skel.find_bone("mixamorig_Hips")
	
	Input.action_press("move_forward")
	for f in 20:
		await physics_frame
	
	player.request_jump()
	await physics_frame
	
	for f in 25:
		await physics_frame
		var m_state = player.call("get_motion_state_name")
		var s_rot = skel.get_bone_pose_rotation(spine_idx)
		var s2_rot = skel.get_bone_pose_rotation(spine2_idx)
		var h_rot = skel.get_bone_pose_rotation(hips_idx)
		var e_s = s_rot.get_euler()
		var e_s2 = s2_rot.get_euler()
		print("f=%02d %s Spine pitch=%.1f yaw=%.1f Spine2 pitch=%.1f yaw=%.1f" % [
			f, m_state, rad_to_deg(e_s.x), rad_to_deg(e_s.y), rad_to_deg(e_s2.x), rad_to_deg(e_s2.y)
		])
	Input.action_release("move_forward")
	main_scene.queue_free()
	quit()
