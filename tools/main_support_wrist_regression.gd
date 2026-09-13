extends "res://tools/ledge_climb_regression.gd"

const Weapons = preload("res://scripts/weapons/weapon_rig_contract.gd")

func _run() -> void:
	ProjectSettings.set_setting("socom/playtest/use_active_bundle", false)
	root.size = Vector2i(1280, 800)
	var main := load("res://main.tscn").instantiate() as Node3D
	main.get_node("IndependentCameraRig").capture_mouse_on_ready = false
	root.add_child(main)
	for frame in 90:
		await physics_frame
		await process_frame
	player = main.get_node("Player")
	player.set_local_input_enabled(false)
	main.get_node("WeaponController").set_input_enabled(false)
	world = Node3D.new()
	root.add_child(world)
	world.position = Vector3(500,0,500)
	_box("Floor", Vector3(20,0.2,20), Vector3(0,-0.1,0))
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-40,-30,0)
	world.add_child(light)
	camera = Camera3D.new()
	camera.fov = 45.0
	world.add_child(camera)
	await _reset(Vector3(500,0.03,500))
	player.get_node("Mannequin").set_process(false)
	var driver = player.get_node("Mannequin/ProductionAnimation")
	for gun in ["m4a1", "ak-47"]:
		_expect(driver.notify_weapon_equipped(Weapons.load_config("res://config/weapons/"+gun+".json")), "equipped " + gun)
		for stance in [&"STANDING", &"CROUCHED", &"PRONE"]:
			for ready in [0.0, 1.0]:
				driver.set_visual_inputs(Vector2.ZERO, stance, 0.0, 0.0, ready, false, 0.0, 0.0, &"LOCOMOTION", 0.0, &"WALK", 0.0, player.global_position + Vector3(0,1.5,-20))
				for frame in 65:
					await physics_frame
					await process_frame
				await create_timer(0.0).timeout
				var pose = driver.weapon_pose_solver
				print("SUPPORT_GRIP family=", driver.equipped_weapon_family, " owner=", pose.weapon_owner, " mode=", pose.support_hand_mode, " fingers=", driver.weapon_grip_contact.snapshot())
				var sk: Skeleton3D = driver.skeleton
				var hand: int = sk.find_bone("mixamorig_LeftHand")
				var forearm: int = sk.find_bone("mixamorig_LeftForeArm")
				var finger: int = sk.find_bone("mixamorig_LeftHandMiddle1")
				var wrist: Vector3 = sk.get_bone_global_pose(hand).origin
				var arm_axis: Vector3 = wrist - sk.get_bone_global_pose(forearm).origin
				var palm_axis: Vector3 = sk.get_bone_global_pose(finger).origin - wrist
				var long_local := sk.get_bone_rest(finger).origin.normalized()
				var across := sk.get_bone_rest(sk.find_bone("mixamorig_LeftHandIndex1")).origin - sk.get_bone_rest(sk.find_bone("mixamorig_LeftHandPinky1")).origin
				var palm_normal: Vector3 = (sk.global_basis * sk.get_bone_global_pose(hand).basis * long_local.cross(across).normalized()).normalized()
				var up_dot: float = palm_normal.dot(pose.weapon_node.global_basis.y.normalized())
				var bend: float = rad_to_deg(arm_axis.angle_to(palm_axis))
				print("SUPPORT_WRIST ", gun, " ", stance, " ready=", ready, " bend=", bend, " contact=", pose.support_hand_error_m, " aim=", pose.weapon_aim_error_deg, " palm_up=", up_dot)
				_expect(pose.support_hand_error_m < 0.02, "left palm contact " + gun + str(stance))
				_expect(bend <= 57.0, "bounded wrist " + gun + str(stance))
				_expect(up_dot > 0.0, "support palm faces weapon up")
				if ready > 0.99: _expect(pose.weapon_aim_error_deg < 0.1, "ready bore remains aligned")
				if "--capture" in OS.get_cmdline_user_args() and stance != &"PRONE":
					_capture_wrist(sk.global_transform * wrist, gun+"-"+str(stance)+"-"+str(int(ready)))
	main.queue_free()
	world.queue_free()
	await process_frame
	print("MAIN_SUPPORT_WRIST ", "PASS" if failures.is_empty() else "FAIL", failures)
	quit(0 if failures.is_empty() else 1)

func _capture_wrist(target: Vector3, label: String) -> void:
	var was_paused := paused
	paused = true
	var output := "res://art_source/traversal_runtime_proof"
	DirAccess.make_dir_recursive_absolute(output)
	for side in [-1, 1]:
		camera.global_position = target + Vector3(0.8 * side, 0.25, -0.7)
		camera.look_at(target)
		camera.make_current()
		camera.force_update_transform()
		RenderingServer.force_draw(false)
		root.get_texture().get_image().save_png(output+"/wrist-"+label+"-side"+str(side)+".png")
	paused = was_paused
