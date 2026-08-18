extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var scene := (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	await _steps(45)
	var player = scene.get_node("Player")
	var rig = scene.get_node("IndependentCameraRig")
	var driver = player.get_node("Mannequin/ProductionAnimation")
	await process_frame
	_report("standing", driver)
	rig.call("set_aim_angles", deg_to_rad(28.0), deg_to_rad(-12.0), true)
	await _steps(30)
	await process_frame
	_report("standing_aim", driver)
	Input.action_press(&"crouch")
	await physics_frame
	Input.action_release(&"crouch")
	await _steps(30)
	await process_frame
	_report("crouched", driver)
	Input.action_press(&"prone")
	await physics_frame
	Input.action_release(&"prone")
	await _steps(45)
	await process_frame
	_report("prone", driver)
	_test_manual_forearm(driver)
	quit()

func _test_manual_forearm(driver: Node) -> void:
	driver.set_process(false)
	var skeleton: Skeleton3D = driver.get("skeleton")
	skeleton.clear_bones_global_pose_override()
	skeleton.force_update_all_bone_transforms()
	var middle := skeleton.find_bone("mixamorig_LeftForeArm")
	var hand := skeleton.find_bone("mixamorig_LeftHand")
	var before: Vector3 = skeleton.global_transform * skeleton.get_bone_global_pose(hand).origin
	var pose := skeleton.get_bone_global_pose(middle)
	pose.basis = Basis(Vector3.UP, PI * 0.5) * pose.basis
	skeleton.set_bone_global_pose_override(middle, pose, 1.0, true)
	skeleton.force_update_all_bone_transforms()
	var after: Vector3 = skeleton.global_transform * skeleton.get_bone_global_pose(hand).origin
	print("MANUAL_FOREARM before=", before, " after=", after, " shift=", before.distance_to(after), " override=", skeleton.get_bone_global_pose_override(middle))

func _report(label: String, driver: Node) -> void:
	var debug: Dictionary = driver.call("get_animation_debug_state")
	var solver = driver.get("weapon_pose_solver")
	var skeleton: Skeleton3D = driver.get("skeleton")
	var trigger_index := skeleton.find_bone("mixamorig_RightHand")
	var support_index := skeleton.find_bone("mixamorig_LeftHand")
	var trigger_world: Vector3 = skeleton.global_transform * skeleton.get_bone_global_pose(trigger_index).origin
	var support_world: Vector3 = skeleton.global_transform * skeleton.get_bone_global_pose(support_index).origin
	var measured := {
		"trigger": trigger_world.distance_to(solver.trigger_hand_target.global_position),
		"support": support_world.distance_to(solver.support_hand_target.global_position),
	}
	print("WEAPON_POSE_PROBE ", label, " ", JSON.stringify(debug.get("weapon_pose", {})), " measured=", JSON.stringify(measured))
	var weapon: Node3D = driver.get("weapon_node")
	if weapon != null:
		var aim: Vector3 = solver.last_aim_direction
		print("  weapon_axes dots aim x=", weapon.global_basis.x.normalized().dot(aim), " y=", weapon.global_basis.y.normalized().dot(aim), " z=", weapon.global_basis.z.normalized().dot(aim), " pos=", weapon.global_position)
	for side in [&"right", &"left"]:
		var names: Array = solver.ARM_BONES[side]
		var positions: Array[Vector3] = []
		for bone_name in names:
			var index := skeleton.find_bone(StringName(bone_name))
			positions.append(skeleton.global_transform * skeleton.get_bone_global_pose(index).origin)
		var target: Vector3 = (
			solver.trigger_hand_target.global_position
			if side == &"right"
			else solver.support_hand_target.global_position
		)
		print("  ", side, " shoulder=", positions[0], " elbow=", positions[1], " hand=", positions[2], " target=", target, " segments=", positions[0].distance_to(positions[1]), ",", positions[1].distance_to(positions[2]), " reach_distance=", positions[0].distance_to(target))

func _steps(count: int) -> void:
	for _index in range(count):
		await physics_frame
