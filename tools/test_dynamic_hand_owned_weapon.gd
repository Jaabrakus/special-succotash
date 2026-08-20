extends SceneTree

var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var packed := load("res://main.tscn") as PackedScene
	_expect(packed != null, "playground loads")
	if packed == null:
		_finish()
		return
	var scene := packed.instantiate()
	root.add_child(scene)
	await _steps(50)
	var mannequin := scene.get_node_or_null("Player/Mannequin")
	var driver = mannequin.get("production_animation") if mannequin != null else null
	var solver = driver.get("weapon_pose_solver") if driver != null else null
	var weapon := driver.get("weapon_node") as Node3D if driver != null else null
	var skeleton := solver.get("skeleton") as Skeleton3D if solver != null else null
	_expect(driver != null and solver != null and weapon != null, "live weapon pose path is available")
	if driver == null or solver == null or weapon == null or skeleton == null:
		scene.queue_free()
		_finish()
		return
	var muzzle := weapon.find_child("Socket_Muzzle", true, false) as Marker3D
	var barrel_base := weapon.find_child("Socket_BarrelBase", true, false) as Marker3D
	var trigger_socket := weapon.find_child("Socket_RightHand", true, false) as Marker3D
	_expect(
		muzzle != null and barrel_base != null and trigger_socket != null,
		"weapon exposes its authored barrel and trigger grip"
	)
	# The mannequin normally copies the live camera rig into this driver every frame.
	# Pause only that bridge so this focused test can inject exact aim samples.
	mannequin.set_process(false)
	var initial_debug: Dictionary = solver.call("get_debug_state")
	_expect(
		bool(initial_debug.get("right_hand_owns_ready_weapon", false)),
		"equipped rifle enables right-hand visual ownership"
	)
	_set_aim(driver, 0.0, 0.0)
	await _steps(24)
	initial_debug = solver.call("get_debug_state")
	var initial_barrel := _barrel_direction(muzzle, barrel_base)
	var initial_hand_basis := _hand_world(skeleton).basis.orthonormalized()

	var requested_yaw := deg_to_rad(24.0)
	var requested_pitch := deg_to_rad(-14.0)
	_set_aim(driver, requested_yaw, requested_pitch)
	await _steps(30)
	var aimed_barrel := _barrel_direction(muzzle, barrel_base)
	var aimed_hand_basis := _hand_world(skeleton).basis.orthonormalized()
	var grip_orientation_error_deg := rad_to_deg(aimed_barrel.angle_to(-aimed_hand_basis.y))
	var barrel_rotation_deg := rad_to_deg(initial_barrel.angle_to(aimed_barrel))
	var hand_rotation_deg := rad_to_deg(
		initial_hand_basis.get_rotation_quaternion().angle_to(
			aimed_hand_basis.get_rotation_quaternion()
		)
	)
	var expected_mount_basis: Basis = (_hand_world(skeleton) * Transform3D(
		solver.get("weapon_hand_mount_transform")
	)).basis
	var grip_position_error := trigger_socket.global_position.distance_to(
		_hand_world(skeleton).origin
	)
	var mount_rotation_error_deg := rad_to_deg(
		weapon.global_basis.get_rotation_quaternion().angle_to(
			expected_mount_basis.get_rotation_quaternion()
		)
	)
	var aimed_debug: Dictionary = solver.call("get_debug_state")
	var aimed_direction: Vector3 = aimed_debug.get("aim_direction", Vector3.ZERO)
	var barrel_alignment_error_deg := rad_to_deg(aimed_barrel.angle_to(aimed_direction))
	print("DYNAMIC_HAND_OWNERSHIP_AIM initial=%s aimed=%s yaw=%.2f pitch=%.2f wrist=%.2f aim_error=%.2f weight=%.3f" % [
		str(initial_debug.get("aim_direction", Vector3.ZERO)),
		str(aimed_debug.get("aim_direction", Vector3.ZERO)),
		float(aimed_debug.get("aim_yaw_demand_deg", 0.0)),
		float(aimed_debug.get("aim_pitch_demand_deg", 0.0)),
		float(aimed_debug.get("wrist_correction_deg", 0.0)),
		float(aimed_debug.get("weapon_aim_error_deg", 0.0)),
		float(aimed_debug.get("weight", 0.0)),
	])
	print("DYNAMIC_HAND_OWNERSHIP_DIRECTIONS initial_barrel=%s aimed_barrel=%s target=%s alignment_error_deg=%.2f" % [
		str(initial_barrel),
		str(aimed_barrel),
		str(aimed_direction),
		barrel_alignment_error_deg,
	])
	print(
		"DYNAMIC_HAND_OWNERSHIP_METRIC barrel_rotation_deg=%.2f hand_rotation_deg=%.2f grip_position_error=%.5f grip_orientation_error_deg=%.2f mount_rotation_error_deg=%.3f trigger=%.5f support=%.5f" % [
			barrel_rotation_deg,
			hand_rotation_deg,
			grip_position_error,
			grip_orientation_error_deg,
			mount_rotation_error_deg,
			float(aimed_debug.get("trigger_hand_error_m", 1.0)),
			float(aimed_debug.get("support_hand_error_m", 1.0)),
		]
	)
	_expect(barrel_rotation_deg >= 12.0, "rifle barrel responds to yaw and pitch")
	_expect(barrel_alignment_error_deg <= 3.0, "rifle barrel finishes on the requested aim line")
	_expect(hand_rotation_deg >= 8.0, "right hand rotates dynamically with the rifle")
	_expect(grip_position_error <= 0.003, "rifle trigger grip remains position-attached to the right hand")
	_expect(grip_orientation_error_deg <= 12.0, "rifle points along the right-hand grip axis")
	_expect(mount_rotation_error_deg <= 0.5, "rifle remains rotation-attached to the right hand")
	_expect(
		float(aimed_debug.get("trigger_hand_error_m", 1.0)) <= 0.035,
		"trigger hand remains on its saved grip"
	)
	_expect(
		float(aimed_debug.get("support_hand_error_m", 1.0)) <= 0.055,
		"left hand follows the moving support grip"
	)
	scene.queue_free()
	_finish()


func _set_aim(driver: Node, yaw: float, pitch: float) -> void:
	driver.call(
		"set_visual_inputs",
		Vector2.ZERO,
		&"STANDING",
		yaw,
		pitch,
		1.0,
		false,
		0.0
	)


func _barrel_direction(muzzle: Marker3D, barrel_base: Marker3D) -> Vector3:
	return (muzzle.global_position - barrel_base.global_position).normalized()


func _hand_world(skeleton: Skeleton3D) -> Transform3D:
	var hand_index := skeleton.find_bone("mixamorig_RightHand")
	return skeleton.global_transform * skeleton.get_bone_global_pose(hand_index)


func _steps(count: int) -> void:
	for _index in count:
		await process_frame


func _expect(condition: bool, message: String) -> void:
	if condition:
		print("DYNAMIC_HAND_OWNERSHIP_CHECK PASS " + message)
	else:
		failures.append(message)
		push_error("DYNAMIC_HAND_OWNERSHIP_CHECK FAIL " + message)


func _finish() -> void:
	if failures.is_empty():
		print("DYNAMIC_HAND_OWNERSHIP_REGRESSION PASS")
		quit(0)
	else:
		quit(1)
