extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var scene: Node3D = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	for f in 65:
		await physics_frame
		
	var player: CharacterBody3D = scene.get_node("Player")
	var camera_rig: Node3D = scene.get_node("IndependentCameraRig")
	var driver: Node = player.get_node("Mannequin/ProductionAnimation")
	var solver: Node = driver.get("weapon_pose_solver")
	
	# Open floor
	var test_floor := StaticBody3D.new()
	test_floor.position = Vector3(300.0, 0.0, 300.0)
	var col := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = Vector3(200.0, 1.0, 200.0)
	col.shape = box_shape
	col.position = Vector3(0.0, -0.5, 0.0)
	test_floor.add_child(col)
	scene.add_child(test_floor)
	
	player.global_position = Vector3(300.0, 0.05, 300.0)
	player.velocity = Vector3.ZERO
	camera_rig.profile.pitch_min_deg = -85.0
	camera_rig.profile.pitch_max_deg = 85.0
	camera_rig.set_aim_angles(deg_to_rad(180.0), deg_to_rad(-85.0), true)
	
	Input.action_press(&"move_forward")
	for f in 25:
		await physics_frame
		
	player.request_jump()
	await physics_frame
	
	var air_count := 0
	for f in 50:
		await physics_frame
		var movement := StringName(player.call("get_motion_state_name"))
		if movement == &"AIRBORNE":
			air_count += 1
			if air_count == 1:
				driver.notify_fired()
			var bore_err: float = float(solver.get("weapon_aim_error_deg"))
			var trig_err: float = float(solver.get("action_trigger_contact_error_m"))
			var supp_err: float = float(solver.get("support_hand_error_m"))
			var ready_wt: float = float(driver.get("weapon_ready_weight"))
			var target: Vector3 = solver.get("last_target_point")
			var muzzle := solver.get("muzzle_socket") as Node3D
			print("AIR frame %2d: bore=%.2f deg | trig=%.4fm | supp=%.4fm | ready=%.2f | target_dist=%.2fm" % [
				air_count, bore_err, trig_err, supp_err, ready_wt, muzzle.global_position.distance_to(target)
			])
		elif air_count > 0 and player.is_on_floor():
			break
			
	Input.action_release(&"move_forward")
	quit(0)
