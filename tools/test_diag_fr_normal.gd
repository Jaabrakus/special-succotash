extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var scene: Node3D = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	for f in 65:
		await physics_frame
		
	var player: CharacterBody3D = scene.get_node("Player")
	
	player.global_position = Vector3(0.0, 0.05, 0.5)
	player.velocity = Vector3.ZERO
	player.motion_state = player.MotionState.STANDING
	
	for f in 15:
		await physics_frame
		
	Input.action_press(&"move_forward")
	Input.action_press(&"move_right")
	
	for f in 25:
		await physics_frame
		
	player.request_jump()
	for f in 10:
		await physics_frame
		print("FRAME %d: motion=%s pos.y=%.3f vy=%.3f on_floor=%s" % [
			f, player.call("get_motion_state_name"), player.global_position.y, player.velocity.y, player.is_on_floor()
		])
		
	Input.action_release(&"move_forward")
	Input.action_release(&"move_right")
	quit(0)
