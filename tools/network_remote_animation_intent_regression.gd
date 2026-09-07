extends SceneTree

const Scene := preload("res://scenes/player/network_operator.tscn")
const Encoder := preload("res://scripts/network/socom_snapshot_encoder.gd")
const Protocol := preload("res://scripts/network/socom_network_protocol.gd")
const Command := preload("res://scripts/network/socom_movement_command.gd")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var server := Scene.instantiate() as SocomNetworkOperator
	server.network_command_driven = true
	root.add_child(server)
	server.set_physics_process(false)
	server.set_local_input_enabled(false)
	server.network_aim_angles = Vector2(0.4, 0.3)
	server.velocity = Vector3(2, 0, -3)
	server.desired_movement_direction = Vector3(1, 0, -1).normalized()
	server.movement_input_strength = 1.0
	server.motion_state = server.MotionState.DIVING
	server.peek_amount = 0.25
	await process_frame
	await process_frame
	assert(get_first_node_in_group("socom_camera_rig") == null, "Headless authority has no player camera")
	var driver = server.mannequin.production_animation
	server.mannequin._sync_production_animation(server)
	assert(is_equal_approx(driver.aim_pitch_rad, 0.3), "Headless mannequin consumes remote aim pitch")
	var proxy := Scene.instantiate() as SocomNetworkOperator
	root.add_child(proxy)
	proxy.set_replica_mode(true)
	proxy.set_physics_process(false)
	assert(server.get_node("CollisionShape3D").shape != proxy.get_node("CollisionShape3D").shape,
		"Inherited player instances must own separate mutable stance colliders")
	var state: Dictionary = Encoder.capture({2: server}, [2])[2]
	proxy.push_network_snapshot(state.position, state.yaw, state.velocity, state.posture,
		state.health, state.alive, 1.0, state.presentation)
	proxy.update_proxy_interpolation(1.13)
	proxy.mannequin._sync_production_animation(proxy)
	assert(proxy.motion_state == server.MotionState.DIVING, "Dive is not collapsed to idle posture")
	assert(proxy.network_aim_angles.is_equal_approx(server.network_aim_angles), "Actor-specific aim survives snapshot")
	assert(proxy.desired_movement_direction.is_equal_approx(server.desired_movement_direction))
	assert(is_equal_approx(proxy.mannequin.production_animation.aim_pitch_rad, 0.3))
	var command := Command.new()
	command.aim_pitch = 0.3
	assert(is_equal_approx(Protocol.packet_to_movement(Protocol.movement_to_packet(command)).aim_pitch, 0.3))
	var invalid := Protocol.movement_to_packet(command)
	invalid.aim_pitch = NAN
	assert(not Protocol.movement_packet_is_sane(invalid), "Reject non-finite client aim")
	server.free()
	proxy.free()
	print("NETWORK_REMOTE_ANIMATION_INTENT PASS no-camera authority, aim pitch, dive, locomotion intent")
	quit()
