extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var scene: Node3D = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	for f in 65:
		await physics_frame
		
	var player: CharacterBody3D = scene.get_node("Player")
	
	# Open test floor
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
	
	for f in 15:
		await physics_frame
		
	Input.action_press(&"move_forward")
	Input.action_press(&"move_right")
	
	for f in 25:
		await physics_frame
		
	player.request_jump()
	for f in 5:
		await physics_frame
		print("FRAME %d:" % f)
		print("  motion_state=%s" % player.call("get_motion_state_name"))
		print("  vel=%s pos=%s" % [str(player.velocity), str(player.global_position)])
		print("  is_on_floor=%s is_on_ceiling=%s is_on_wall=%s" % [player.is_on_floor(), player.is_on_ceiling(), player.is_on_wall()])
		print("  collisions=%d" % player.get_slide_collision_count())
		for c in range(player.get_slide_collision_count()):
			var sc := player.get_slide_collision(c)
			print("    col %d: obj=%s normal=%s pos=%s" % [c, sc.get_collider().name, sc.get_normal(), sc.get_position()])
			
	quit(0)
