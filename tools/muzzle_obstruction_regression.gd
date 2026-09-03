extends SceneTree

const MultiplayerScene := preload("res://multiplayer_slice.tscn")
const NetworkOperator := preload("res://scripts/network/socom_network_operator.gd")

var failures: Array[String] = []
var shot_signal_count := 0
var last_shot_origin := Vector3.ZERO


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var slice = MultiplayerScene.instantiate()
	root.add_child(slice)
	await process_frame

	var peer_id := 1
	slice.call("_server_spawn_operator", peer_id, 0, Vector3.ZERO)
	var target_peer_id := 2
	var target := NetworkOperator.new() as SocomNetworkOperator
	target.name = "MuzzleObstructionTarget"
	target.position = Vector3(0.0, 0.0, -8.0)
	slice.add_child(target)
	target.configure_identity(target_peer_id, 1)
	slice.operators[target_peer_id] = target
	await process_frame
	await process_frame
	await physics_frame
	var shooter := slice.operators.get(peer_id) as SocomNetworkOperator
	var ballistics = slice.server_ballistics.get(peer_id)
	_expect(
		shooter != null and target != null and ballistics != null,
		"server combat fixture is ready"
	)
	if shooter == null or target == null or ballistics == null:
		_finish(slice)
		return

	slice.round_active = true
	ballistics.shot_fired.connect(_on_server_shot_fired)
	var muzzle_marker := shooter.mannequin.get_active_muzzle_marker() as Node3D
	_expect(muzzle_marker != null, "server operator exposes its authoritative muzzle")
	if muzzle_marker == null:
		_finish(slice)
		return
	var server_muzzle := muzzle_marker.global_position
	var server_anchor: Vector3 = slice.call("_authoritative_shot_report_anchor", shooter)
	var server_direction: Vector3 = shooter.mannequin.get_active_barrel_direction()
	if server_direction.length_squared() < 0.99:
		server_direction = -shooter.global_basis.z
	ballistics.base_spread_deg = 0.0
	ballistics.moving_spread_deg = 0.0
	ballistics.full_gait_spread_deg = 0.0
	ballistics.airborne_spread_deg = 0.0
	_align_target_torso(target, server_muzzle + server_direction * 8.0)
	await physics_frame
	var target_health_before := target.current_health

	var wall := _make_wall_between(server_anchor, server_muzzle)
	slice.add_child(wall)
	await physics_frame
	await physics_frame

	var starting_ammo := int(slice.server_magazine_ammo.get(peer_id, -1))
	var packet := _aim_packet(
		1,
		server_anchor + server_direction * 1.0,
		server_direction
	)
	# These hostile client claims are deliberately ignored by authority.
	packet["reported_muzzle_origin_override"] = server_muzzle + server_direction * 4.0
	packet["client_muzzle_obstructed"] = false
	packet["client_obstruction_clear"] = true
	slice.call("_server_process_shot", peer_id, packet)

	_expect(
		String(slice.last_rejected_shot_reason.get(peer_id, "")) == "MUZZLE_OBSTRUCTED",
		"nearby server-world geometry rejects the shot"
	)
	_expect(
		int(slice.server_magazine_ammo.get(peer_id, -1)) == starting_ammo,
		"blocked shot consumes no authoritative ammunition"
	)
	_expect(shot_signal_count == 0, "blocked shot never enters ballistics or damage resolution")
	_expect(
		is_equal_approx(target.current_health, target_health_before),
		"blocked shot applies no damage to the server target behind cover"
	)
	_expect(
		int(slice.last_accepted_shot_sequence.get(peer_id, -1)) == 1,
		"blocked but valid intent consumes its sequence against replay"
	)

	wall.queue_free()
	await physics_frame
	await physics_frame
	slice.call("_server_process_shot", peer_id, packet)
	_expect(
		String(slice.last_rejected_shot_reason.get(peer_id, "")) == "STALE_SEQUENCE",
		"replayed sequence remains rejected after obstruction clears"
	)
	_expect(
		int(slice.server_magazine_ammo.get(peer_id, -1)) == starting_ammo
		and shot_signal_count == 0,
		"replayed packet has no ammo or firing side effects"
	)

	var clear_server_muzzle := (
		shooter.mannequin.get_active_muzzle_marker() as Node3D
	).global_position
	_align_target_torso(target, clear_server_muzzle + server_direction * 8.0)
	await physics_frame
	clear_server_muzzle = (
		shooter.mannequin.get_active_muzzle_marker() as Node3D
	).global_position
	_align_target_torso(target, clear_server_muzzle + server_direction * 8.0)
	if slice.get("operator_state_history") != null:
		slice.operator_state_history.clear()
	var clear_packet := _aim_packet(2, server_anchor, server_direction)
	slice.call("_server_process_shot", peer_id, clear_packet)
	_expect(
		String(slice.last_rejected_shot_reason.get(peer_id, "blocked")) == "",
		"clear authoritative muzzle accepts the next valid sequence"
	)
	_expect(
		int(slice.server_magazine_ammo.get(peer_id, -1)) == starting_ammo - 1,
		"clear server shot consumes exactly one round"
	)
	_expect(shot_signal_count == 1, "clear server shot enters ballistics exactly once")
	_expect(
		target.current_health < target_health_before,
		"clear server shot reaches authoritative damage resolution"
	)
	_expect(
		last_shot_origin.distance_to(clear_server_muzzle) < 0.001,
		"server ballistics trace starts at the authoritative muzzle"
	)

	_finish(slice)


func _aim_packet(sequence: int, reported_anchor: Vector3, direction: Vector3) -> Dictionary:
	var normalized := direction.normalized()
	return {
		"sequence": sequence,
		"simulation_tick": Engine.get_physics_frames(),
		"yaw": wrapf(atan2(-normalized.x, -normalized.z), -PI, PI),
		"pitch": asin(clampf(normalized.y, -1.0, 1.0)),
		"reported_muzzle_origin": reported_anchor,
		"direction": normalized,
	}


func _align_target_torso(target: SocomNetworkOperator, target_point: Vector3) -> void:
	if target.hurtbox_rig == null:
		return
	target.hurtbox_rig.force_pose_update()
	var torso := target.hurtbox_rig.get_region_area(&"TORSO") as Area3D
	if torso == null:
		return
	var offset := target.global_position - torso.global_position
	target.global_position = target_point + offset
	target.force_update_transform()
	target.hurtbox_rig.force_pose_update()


func _make_wall_between(anchor: Vector3, muzzle: Vector3) -> StaticBody3D:
	var wall := StaticBody3D.new()
	wall.name = "AuthoritativeMuzzleObstruction"
	var shape_node := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.5, 1.5, 0.08)
	shape_node.shape = shape
	wall.add_child(shape_node)
	var segment := muzzle - anchor
	var direction := segment.normalized() if segment.length_squared() > 0.0001 else Vector3.FORWARD
	wall.global_transform = Transform3D(
		Basis.looking_at(direction, Vector3.UP),
		anchor.lerp(muzzle, 0.5)
	)
	return wall


func _on_server_shot_fired(origin: Vector3, _impact: Vector3, _hit: bool) -> void:
	shot_signal_count += 1
	last_shot_origin = origin


func _expect(condition: bool, message: String) -> void:
	if condition:
		print("MUZZLE_OBSTRUCTION_CHECK PASS: %s" % message)
	else:
		failures.append(message)
		push_error("MUZZLE_OBSTRUCTION_CHECK FAIL: %s" % message)


func _finish(slice: Node) -> void:
	if slice != null:
		slice.queue_free()
	if failures.is_empty():
		print("MUZZLE_OBSTRUCTION_REGRESSION PASS")
		quit(0)
	else:
		print("MUZZLE_OBSTRUCTION_REGRESSION FAIL: %d issue(s)" % failures.size())
		quit(1)
