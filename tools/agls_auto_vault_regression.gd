extends SceneTree

const PlayerScene := preload("res://scenes/player/operator_player.tscn")
const MovementCommand := preload("res://scripts/network/socom_movement_command.gd")

var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var world := Node3D.new()
	world.name = "AutomaticVaultRegressionWorld"
	root.add_child(world)
	_add_box(world, "Floor", Vector3(12.0, 0.20, 12.0), Vector3(0.0, -0.10, 0.0))
	_add_box(world, "LowVault", Vector3(2.2, 1.0, 0.65), Vector3(0.0, 0.50, 0.0))
	_add_box(world, "TallWall", Vector3(2.2, 2.0, 0.65), Vector3(3.2, 1.0, 0.0))

	var player := PlayerScene.instantiate() as CharacterBody3D
	player.name = "LowVaultPlayer"
	player.position = Vector3(0.0, 0.05, 2.0)
	player.set_local_input_enabled(false)
	world.add_child(player)
	await _step_physics(8)
	_expect(player.is_on_floor(), "low-vault fixture starts grounded")

	player.velocity = Vector3.FORWARD * 3.0
	var entered_vault := false
	var maximum_height := player.global_position.y
	for _frame in range(150):
		_queue_forward(player)
		await physics_frame
		entered_vault = entered_vault or player.get_motion_state_name() == &"VAULTING"
		maximum_height = maxf(maximum_height, player.global_position.y)
		if entered_vault and player.get_traversal_mode_name() == &"grounded" and player.global_position.z < -0.65:
			break
	if not entered_vault:
		var collider := player.get_node("CollisionShape3D") as CollisionShape3D
		var capsule := collider.shape as CapsuleShape3D
		var runtime = player.get("traversal")
		print("AUTO_VAULT_METRIC blocked_position=%s probe=%s" % [
			player.global_position,
			runtime.mantle_motor.probe(
				player,
				Vector3.FORWARD,
				capsule.height,
				capsule.radius
			),
		])
	_expect(entered_vault, "forward movement automatically starts one vault")
	_expect(maximum_height > 0.78, "authoritative collision body clears the low obstacle")
	_expect(player.global_position.z < -0.65, "automatic vault lands beyond the obstacle")
	_expect(player.get_traversal_mode_name() == &"grounded", "vault returns to grounded")

	var tall_player := PlayerScene.instantiate() as CharacterBody3D
	tall_player.name = "TallWallPlayer"
	tall_player.position = Vector3(3.2, 0.05, 2.0)
	tall_player.set_local_input_enabled(false)
	world.add_child(tall_player)
	await _step_physics(8)
	tall_player.velocity = Vector3.FORWARD * 3.0
	var tall_wall_vaulted := false
	for _frame in range(80):
		_queue_forward(tall_player)
		await physics_frame
		tall_wall_vaulted = tall_wall_vaulted or tall_player.get_motion_state_name() == &"VAULTING"
	_expect(not tall_wall_vaulted, "automatic vault rejects a wall above its height range")
	_expect(tall_player.global_position.z > 0.15, "rejected wall remains collision blocking")
	_finish()


func _queue_forward(player: CharacterBody3D) -> void:
	var command := MovementCommand.new()
	command.simulation_tick = Engine.get_physics_frames()
	command.aim_yaw = 0.0
	command.world_move_override = Vector3.FORWARD
	player.queue_movement_command(command)


func _add_box(parent: Node3D, box_name: String, size: Vector3, position: Vector3) -> void:
	var body := StaticBody3D.new()
	body.name = box_name
	body.position = position
	parent.add_child(body)
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collider.shape = shape
	body.add_child(collider)


func _step_physics(count: int) -> void:
	for _index in range(count):
		await physics_frame


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("AUTO_VAULT_CHECK PASS ", label)
		return
	failures.append(label)
	push_error("AUTO_VAULT_CHECK FAIL %s" % label)


func _finish() -> void:
	if failures.is_empty():
		print("AGLS_AUTO_VAULT_REGRESSION PASS")
		quit(0)
		return
	print("AGLS_AUTO_VAULT_REGRESSION FAIL ", failures)
	quit(1)
