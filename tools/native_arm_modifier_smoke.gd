extends SceneTree


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var scene := (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	for _frame in range(60):
		await physics_frame
	var player := scene.get_node("Player") as CharacterBody3D
	var mannequin := player.get_node("Mannequin")
	var driver := mannequin.get_node("ProductionAnimation")
	mannequin.set_process(false)
	driver.call(
		"set_visual_inputs", Vector2.ZERO, &"STANDING", 0.0, 0.0, 1.0,
		false, 0.0, 0.0, &"STANDING", 0.0, &"WALK", 0.0,
		player.global_position + Vector3(0.0, 1.35, -25.0),
		Vector2.ZERO, 0.0, &"IDLE", 0.0
	)
	for _frame in range(30):
		await physics_frame
	var skeleton := driver.get("skeleton") as Skeleton3D
	var pose: Dictionary = driver.call("get_animation_debug_state").get("weapon_pose", {})
	for side in ["Right", "Left"]:
		var shoulder_index := skeleton.find_bone("mixamorig_%sArm" % side)
		var elbow_index := skeleton.find_bone("mixamorig_%sForeArm" % side)
		var hand_index := skeleton.find_bone("mixamorig_%sHand" % side)
		print(
			"ARM_GEOMETRY ", side,
			" shoulder=", (skeleton.global_transform * skeleton.get_bone_global_pose(shoulder_index)).origin,
			" elbow=", (skeleton.global_transform * skeleton.get_bone_global_pose(elbow_index)).origin,
			" hand=", (skeleton.global_transform * skeleton.get_bone_global_pose(hand_index)).origin,
			" pole=", pose.get("%s_elbow_pole_position" % side.to_lower(), Vector3.INF)
		)
	print("NATIVE_ARM callback_mode=", skeleton.modifier_callback_mode_process)
	for node_name in ["RuntimeRightHandIK", "RuntimeLeftHandIK"]:
		var modifier := skeleton.get_node_or_null(node_name) as TwoBoneIK3D
		if modifier == null:
			print("NATIVE_ARM ", node_name, " MISSING")
			continue
		var target_path := modifier.get_target_node(0)
		var pole_path := modifier.get_pole_node(0)
		var target := modifier.get_node_or_null(target_path) as Node3D
		var pole := modifier.get_node_or_null(pole_path) as Node3D
		var hand_index := modifier.get_end_bone(0)
		var hand_world := (
			skeleton.global_transform * skeleton.get_bone_global_pose(hand_index)
		).origin
		print(
			"NATIVE_ARM ", node_name,
			" active=", modifier.active,
			" influence=", modifier.influence,
			" root=", modifier.get_root_bone(0),
			" mid=", modifier.get_middle_bone(0),
			" end=", hand_index,
			" target_path=", target_path,
			" target=", target.global_position if target != null else Vector3.INF,
			" pole=", pole.global_position if pole != null else Vector3.INF,
			" hand=", hand_world
		)
	quit()
