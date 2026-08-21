extends SceneTree

const MovementCommand := preload("res://scripts/network/socom_movement_command.gd")

var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var packed := load("res://main.tscn") as PackedScene
	_expect(packed != null, "main scene loads")
	if packed == null:
		_finish()
		return
	var scene := packed.instantiate()
	root.add_child(scene)
	await _steps(30)
	var player := scene.get_node_or_null("Player") as CharacterBody3D
	_expect(player != null, "authoritative player exists")
	if player == null:
		_finish()
		return
	player.set("move_speed", 6.0)
	player.set("strafe_speed", 4.5)
	_expect(
		is_equal_approx(float(player.call("_directional_movement_speed", Vector2.UP, 6.0)), 6.0),
		"forward velocity keeps the authoritative move speed"
	)
	_expect(
		is_equal_approx(float(player.call("_directional_movement_speed", Vector2.RIGHT, 6.0)), 4.5),
		"pure strafe velocity uses the independently tunable speed"
	)

	player.call("set_local_input_enabled", false)
	Input.action_press(&"move_right")
	await _steps(4)
	Input.action_release(&"move_right")
	_expect(
		Vector2(player.velocity.x, player.velocity.z).length() < 0.05,
		"remote player never samples local device input"
	)

	var command = MovementCommand.new()
	command.simulation_tick = 410
	command.aim_yaw = deg_to_rad(90.0)
	command.move_axis = Vector2(0.0, -1.0)
	player.call("queue_movement_command", command)
	await physics_frame
	var consumed = player.call("get_last_movement_command")
	_expect(consumed != null and consumed.simulation_tick == 410, "one queued command owns one simulation tick")
	var desired: Vector3 = player.call("get_desired_movement_direction")
	var expected := Basis(Vector3.UP, command.aim_yaw) * Vector3.FORWARD
	_expect(desired.dot(expected) > 0.99, "travel derives from command aim yaw, not rendered camera position")

	player.velocity = Vector3.ZERO
	player.call("set_local_input_enabled", true)
	await _steps(2)
	await _check_latest_lateral_input_wins(player)
	await _check_stance_clearance(scene, player)
	await _check_committed_action_collision(scene, player)
	scene.queue_free()
	_finish()


func _check_latest_lateral_input_wins(player: CharacterBody3D) -> void:
	Input.action_press(&"move_left")
	await physics_frame
	Input.action_press(&"move_right")
	await physics_frame
	var command = player.call("get_last_movement_command")
	_expect(
		command != null and command.move_axis.x > 0.99,
		"D overrides a held A as the newest lateral input"
	)
	Input.action_release(&"move_right")
	await physics_frame
	command = player.call("get_last_movement_command")
	_expect(
		command != null and command.move_axis.x < -0.99,
		"releasing D falls back to the A that remains held"
	)
	Input.action_release(&"move_left")
	await physics_frame

	Input.action_press(&"move_right")
	await physics_frame
	Input.action_press(&"move_left")
	await physics_frame
	command = player.call("get_last_movement_command")
	_expect(
		command != null and command.move_axis.x < -0.99,
		"A overrides a held D as the newest lateral input"
	)
	Input.action_release(&"move_left")
	await physics_frame
	command = player.call("get_last_movement_command")
	_expect(
		command != null and command.move_axis.x > 0.99,
		"releasing A falls back to the D that remains held"
	)
	Input.action_release(&"move_right")
	await physics_frame


func _check_stance_clearance(scene: Node, player: CharacterBody3D) -> void:
	var saved_position := player.global_position
	player.set_physics_process(false)
	player.global_position = Vector3(24.0, 8.0, 24.0)
	player.set("posture", 1)
	player.set("motion_state", 1)
	player.call("_apply_posture_collider")
	_expect(StringName(player.call("get_posture_name")) == &"CROUCHED", "test enters crouch")

	var ceiling := StaticBody3D.new()
	ceiling.name = "RegressionLowCeiling"
	var shape_node := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.0, 0.20, 2.0)
	shape_node.shape = box
	ceiling.add_child(shape_node)
	scene.add_child(ceiling)
	ceiling.global_position = player.global_position + Vector3.UP * 1.48
	await _steps(2)
	_expect(
		not bool(player.call("_has_posture_clearance", 0)),
		"standing capsule detects the low ceiling before expansion"
	)
	_expect(
		not bool(player.call("_try_set_posture", 0))
		and StringName(player.call("get_posture_name")) == &"CROUCHED",
		"low ceiling blocks unsafe stand expansion"
	)
	ceiling.queue_free()
	await _steps(2)
	_expect(
		bool(player.call("_try_set_posture", 0))
		and StringName(player.call("get_posture_name")) == &"STANDING",
		"standing succeeds after clearance returns"
	)
	player.global_position = saved_position
	player.velocity = Vector3.ZERO
	player.set_physics_process(true)
	await _steps(20)


func _check_committed_action_collision(scene: Node, player: CharacterBody3D) -> void:
	player.velocity = Vector3.ZERO
	var direction := -player.global_basis.z.normalized()
	var wall := StaticBody3D.new()
	wall.name = "RegressionActionWall"
	var shape_node := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.5, 2.5, 0.20)
	shape_node.shape = box
	wall.add_child(shape_node)
	scene.add_child(wall)
	wall.global_position = player.global_position + direction * 0.85 + Vector3.UP * 1.0
	wall.look_at(wall.global_position + direction, Vector3.UP)
	await physics_frame
	var start := player.global_position
	Input.action_press(&"move_forward")
	Input.action_press(&"dive")
	await physics_frame
	Input.action_release(&"dive")
	await _steps(20)
	Input.action_release(&"move_forward")
	var travel := (player.global_position - start).dot(direction)
	_expect(travel < 0.75, "dive cannot tunnel through a close wall")
	_expect(StringName(player.call("get_motion_state_name")) != &"DIVING", "wall impact ends the committed dive safely")
	wall.queue_free()


func _steps(count: int) -> void:
	for _index in range(count):
		await physics_frame


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("MOVEMENT_COMMAND_CHECK PASS ", label)
	else:
		failures.append(label)
		push_error("MOVEMENT_COMMAND_CHECK FAIL %s" % label)


func _finish() -> void:
	for action in [&"move_right", &"move_forward", &"crouch", &"dive"]:
		Input.action_release(action)
	if failures.is_empty():
		print("MOVEMENT_COMMAND_REGRESSION PASS")
		quit(0)
	else:
		print("MOVEMENT_COMMAND_REGRESSION FAIL ", failures)
		quit(1)
