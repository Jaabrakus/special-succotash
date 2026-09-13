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
	
	player.global_position = Vector3(300.0, 0.05, 300.0)
	player.velocity = Vector3.ZERO
	camera_rig.profile.pitch_min_deg = -85.0
	camera_rig.profile.pitch_max_deg = 85.0
	camera_rig.set_aim_angles(0.0, deg_to_rad(-85.0), true)
	
	for f in 15:
		await physics_frame
		
	print("DEBUG P-85 GROUNDED:")
	driver.notify_fired()
	await physics_frame
	_print_aim_state(solver, camera_rig)
	
	player.request_jump()
	for f in 40:
		await physics_frame
		var movement := StringName(player.call("get_motion_state_name"))
		if movement == &"AIRBORNE":
			driver.notify_fired()
			print("DEBUG P-85 AIR frame %d:" % f)
			_print_aim_state(solver, camera_rig)
			break
			
	quit(0)

func _print_aim_state(solver: Node, camera_rig: Node3D) -> void:
	var muzzle := solver.get("muzzle_socket") as Node3D
	var barrel := solver.get("barrel_base_socket") as Node3D
	var target: Vector3 = solver.get("last_target_point")
	var bore := (muzzle.global_position - barrel.global_position).normalized()
	var forward := (target - muzzle.global_position).normalized()
	var bore_deg := rad_to_deg(bore.angle_to(forward))
	var aim_err: float = float(solver.get("weapon_aim_error_deg"))
	var trig_err: float = float(solver.get("action_trigger_contact_error_m"))
	var supp_err: float = float(solver.get("support_hand_error_m"))
	print("  target=%s muzzle=%s" % [str(target), str(muzzle.global_position)])
	print("  bore=%s forward=%s" % [str(bore), str(forward)])
	print("  bore_deg=%.2f solver_aim_err=%.2f trig_err=%.4f supp_err=%.4f" % [
		bore_deg, aim_err, trig_err, supp_err
	])
	print("  rig_weapon_aim_point=%s rig_aim_point=%s rig_pitch_deg=%.1f" % [
		str(camera_rig.get("weapon_aim_point")),
		str(camera_rig.get("aim_point")),
		rad_to_deg(float(camera_rig.get("aim_pitch")))
	])
