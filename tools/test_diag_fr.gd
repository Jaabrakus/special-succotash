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
	
	# Add open test floor
	var test_floor := StaticBody3D.new()
	test_floor.position = Vector3(400.0, 0.0, 400.0)
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(300.0, 1.0, 300.0)
	col.shape = box
	col.position = Vector3(0.0, -0.5, 0.0)
	test_floor.add_child(col)
	scene.add_child(test_floor)
	
	player.global_position = Vector3(400.0, 0.05, 400.0)
	player.velocity = Vector3.ZERO
	player.motion_state = player.MotionState.STANDING
	player.posture = player.MotionState.STANDING
	
	for f in 15:
		await physics_frame
		
	Input.action_press(&"move_forward")
	Input.action_press(&"move_right")
	
	for f in 25:
		await physics_frame
		
	print("Pre-jump: pos=%s vel=%s on_floor=%s motion=%s" % [
		str(player.global_position), str(player.velocity), player.is_on_floor(), player.call("get_motion_state_name")
	])
	
	player.request_jump()
	await physics_frame
	
	print("Post-jump frame 0: pos=%s vel=%s on_floor=%s motion=%s" % [
		str(player.global_position), str(player.velocity), player.is_on_floor(), player.call("get_motion_state_name")
	])
	
	for f in 40:
		await physics_frame
		print("Post-jump frame %d: pos.y=%.3f vy=%.3f on_floor=%s motion=%s" % [
			f + 1, player.global_position.y, player.velocity.y, player.is_on_floor(), player.call("get_motion_state_name")
		])
		if f > 5 and player.call("get_motion_state_name") != "AIRBORNE" and player.is_on_floor():
			break
			
	Input.action_release(&"move_forward")
	Input.action_release(&"move_right")
	quit(0)
