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
	
	# Open space in main training range
	player.global_position = Vector3(0.0, 0.05, 0.0)
	player.velocity = Vector3.ZERO
	
	var pitches := [0.0, -15.0, -30.0, -45.0, -55.0, -60.0, -65.0, -70.0, -75.0, -80.0, -85.0]
	
	for p in pitches:
		camera_rig.profile.pitch_min_deg = minf(camera_rig.profile.pitch_min_deg, p)
		camera_rig.set_aim_angles(0.0, deg_to_rad(p), true)
		player.global_position = Vector3(0.0, 0.05, 0.0)
		player.velocity = Vector3.ZERO
		for f in 15:
			await physics_frame
			
		player.request_jump()
		await physics_frame
		
		var max_bore := 0.0
		var max_trig := 0.0
		var max_supp := 0.0
		var min_target_dist := 999.0
		var air_frames := 0
		
		for f in 60:
			await physics_frame
			var movement := StringName(player.call("get_motion_state_name"))
			if movement == &"AIRBORNE":
				air_frames += 1
				# Continuous firing readiness throughout jump
				driver.notify_fired()
				var bore_err: float = float(solver.get("weapon_aim_error_deg"))
				var trig_err: float = float(solver.get("action_trigger_contact_error_m"))
				var supp_err: float = float(solver.get("support_hand_error_m"))
				var target: Vector3 = solver.get("last_target_point")
				var muzzle := solver.get("muzzle_socket") as Node3D
				var dist := muzzle.global_position.distance_to(target)
				
				# After first 3 frames of entry blend
				if air_frames >= 4:
					max_bore = maxf(max_bore, bore_err)
					max_trig = maxf(max_trig, trig_err)
					max_supp = maxf(max_supp, supp_err)
					min_target_dist = minf(min_target_dist, dist)
			elif air_frames > 5 and player.is_on_floor():
				break
				
		print("PITCH %5.1f: air=%2d | max_bore=%6.2f deg | trig=%.4fm | supp=%.4fm | min_target_dist=%.2fm" % [
			p, air_frames, max_bore, max_trig, max_supp, min_target_dist
		])
		
	quit(0)
