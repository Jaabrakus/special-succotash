extends "res://scripts/network/socom_multiplayer_lobby_pairing.gd"

@rpc("any_peer", "call_remote", "unreliable_ordered")
func submit_movement(packet: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if not is_peer_gameplay_action_allowed(sender):
		return
	if not NetworkProtocol.movement_packet_is_sane(packet):
		return
	var command_tick := int(packet.get("tick", -1))
	if command_tick <= int(last_command_tick.get(sender, -1)):
		return
	last_command_tick[sender] = command_tick
	latest_commands[sender] = packet
	var operator: Variant = operators[sender]
	operator.queue_movement_command(NetworkProtocol.packet_to_movement(packet))
	if not logged_command_peers.has(sender):
		logged_command_peers[sender] = true
		print("MP_SLICE COMMAND_ACCEPTED peer=%d" % sender)


@rpc("authority", "call_remote", "unreliable")
func receive_time_sync_probe(nonce: int, server_send_ms: float) -> void:
	# Echo an opaque server probe immediately. The server measures the complete
	# round trip and never trusts a client-reported ping value.
	if multiplayer.is_server():
		return
	submit_time_sync_echo.rpc_id(1, nonce, server_send_ms)


@rpc("any_peer", "call_remote", "unreliable")
func submit_time_sync_echo(nonce: int, server_send_ms: float) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	var pending: Dictionary = pending_time_sync.get(sender, {})
	if int(pending.get("nonce", -1)) != nonce:
		return
	var authoritative_send_ms := float(pending.get("server_send_ms", -1.0))
	if authoritative_send_ms < 0.0 or absf(authoritative_send_ms - server_send_ms) > 0.5:
		return
	var server_now_ms := float(Time.get_ticks_msec())
	var measured_rtt_ms := clampf(server_now_ms - authoritative_send_ms, 0.0, 1000.0)
	var measured_one_way_ms := minf(
		measured_rtt_ms * 0.5,
		MAX_TRANSPORT_COMPENSATION_MS
	)
	var previous := float(peer_transport_one_way_ms.get(sender, measured_one_way_ms))
	peer_transport_one_way_ms[sender] = lerpf(previous, measured_one_way_ms, 0.20)
	pending_time_sync.erase(sender)
	receive_time_sync_result.rpc_id(
		sender,
		server_now_ms,
		measured_rtt_ms
	)


@rpc("authority", "call_remote", "unreliable")
func receive_time_sync_result(server_send_ms: float, measured_rtt_ms: float) -> void:
	if multiplayer.is_server():
		return
	var local_receive_ms := float(Time.get_ticks_msec())
	var offset_sample := (
		server_send_ms + clampf(measured_rtt_ms, 0.0, 1000.0) * 0.5
		- local_receive_ms
	)
	if server_clock_synchronized:
		server_clock_offset_ms = lerpf(server_clock_offset_ms, offset_sample, 0.20)
	else:
		server_clock_offset_ms = offset_sample
		server_clock_synchronized = true


@rpc("any_peer", "call_remote", "reliable")
func submit_shot(packet: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if is_peer_gameplay_action_allowed(sender):
		_queue_server_shot(sender, packet)


@rpc("any_peer", "call_remote", "reliable")
func submit_reload() -> void:
	if multiplayer.is_server():
		var peer_id := multiplayer.get_remote_sender_id()
		if is_peer_gameplay_action_allowed(peer_id):
			pending_reload_requests[peer_id] = true


@rpc("any_peer", "call_remote", "reliable")
func submit_objective_interaction(held: bool) -> void:
	if multiplayer.is_server():
		var peer_id := multiplayer.get_remote_sender_id()
		if is_peer_gameplay_action_allowed(peer_id):
			objective_interact_held[peer_id] = held


func is_peer_gameplay_action_allowed(peer_id: int) -> bool:
	return operators.has(peer_id)


@rpc("authority", "call_remote", "unreliable_ordered")
func receive_world_state(snapshot_packet: Dictionary, score_snapshot: Dictionary) -> void:
	if not score_snapshot.is_empty():
		scores = score_snapshot
	var entities: Dictionary = snapshot_packet.get("entities", snapshot_packet)
	var timestamp_seconds := _server_timestamp_to_local_seconds(
		float(snapshot_packet.get("timestamp_ms", Time.get_ticks_msec()))
	)
	var local_id := multiplayer.get_unique_id()

	for raw_id in entities:
		var peer_id: int = int(raw_id)
		var operator: Variant = operators.get(peer_id)
		if operator == null:
			continue
		var state: Dictionary = entities[raw_id]
		if peer_id == local_id:
			pending_snapshots[raw_id] = state
		else:
			operator.push_network_snapshot(
				Vector3(state.get("position", operator.global_position)),
				float(state.get("yaw", operator.rotation.y)),
				Vector3(state.get("velocity", Vector3.ZERO)),
				int(state.get("posture", 0)),
				float(state.get("health", operator.current_health)),
				bool(state.get("alive", true)),
				timestamp_seconds
			)

	if not logged_first_snapshot:
		logged_first_snapshot = true
		print("MP_SLICE SNAPSHOT_RECEIVED operators=%d" % entities.size())
	_refresh_scoreboard()


@rpc("authority", "call_remote", "reliable")
func receive_shot_effect(
	shooter_peer_id: int,
	origin: Vector3,
	impact: Vector3,
	hit: bool,
	message: String
) -> void:
	_present_shot(shooter_peer_id, origin, impact, hit, message)


@rpc("authority", "call_remote", "reliable")
func receive_damage_feedback(
	hit_region: String,
	damage: float,
	eliminated: bool
) -> void:
	if hit_region != "HEAD" or local_camera == null:
		return
	var intensity := clampf(damage / 100.0, 0.85, 1.20)
	local_camera.notify_head_impact(intensity)
	_set_status("HEAD IMPACT%s" % ("  •  ELIMINATED" if eliminated else ""))


@rpc("authority", "call_remote", "reliable")
func receive_match_event(message: String) -> void:
	_set_status(message)


@rpc("authority", "call_remote", "reliable")
func receive_ammo_state(magazine_rounds: int, reserve_rounds: int) -> void:
	local_magazine_ammo = maxi(0, magazine_rounds)
	local_reserve_ammo = maxi(0, reserve_rounds)
	_refresh_player_state()
	if AutoReloadPolicy.should_start(local_magazine_ammo, local_reserve_ammo, local_reload_pending): call_deferred("_request_local_reload")

@rpc("authority", "call_remote", "reliable")
func receive_objective_state(state: Dictionary) -> void:
	bomb_carrier_peer_id = int(state.get("carrier_peer_id", 0))
	bomb_world_position = Vector3(state.get("world_position", Vector3.ZERO))
	bomb_planted = bool(state.get("planted", false))
	bomb_planting_team = int(state.get("planting_team", -1))
	bomb_plant_progress = float(state.get("plant_progress", 0.0))
	bomb_fuse_remaining = float(state.get("fuse_remaining", 0.0))
	bomb_defusing_peer_id = int(state.get("defusing_peer_id", 0))
	bomb_defuse_progress = float(state.get("defuse_progress", 0.0))
	_update_bomb_visual()
	_refresh_objective_status()


func _server_spawn_operator(
	peer_id: int,
	assigned_team: int,
	assigned_spawn: Vector3
) -> void:
	assigned_spawns[peer_id] = assigned_spawn
	_spawn_operator_local(peer_id, assigned_team, assigned_spawn)
	var ballistics = BallisticsScript.new()
	ballistics.name = "ServerBallistics_%d" % peer_id
	add_child(ballistics)
	var weapon_config: Dictionary = _weapon_config_for_peer(peer_id)
	_apply_ballistics_profile(ballistics, weapon_config)
	server_ballistics[peer_id] = ballistics
	var composure = ComposureScript.new()
	composure.configure_weapon(weapon_config.get("composure", {}))
	server_composure[peer_id] = composure
	_reset_ammo_for_peer(peer_id)
	last_accepted_shot_sequence[peer_id] = -1
	last_enqueued_shot_sequence[peer_id] = -1
	pending_shot_packets[peer_id] = []
	pending_reload_requests[peer_id] = false
	last_rejected_shot_reason[peer_id] = ""
	scores[peer_id] = 0


func _spawn_operator_local(peer_id: int, team: int, spawn_position: Vector3) -> void:
	if operators.has(peer_id):
		return
	var operator := NetworkOperatorScript.new()
	var local_id := multiplayer.get_unique_id()
	var is_local_owner := peer_id == local_id
	var lightweight_probe_client := (
		not multiplayer.is_server()
		and OS.get_cmdline_user_args().has("--network-probe-lite-client")
	)
	# A lightweight probe client keeps only its locally owned presentation rig.
	# That still exercises the real client muzzle/weapon path without multiplying
	# every remote operator's heavy animation stack across all probe processes.
	operator.visual_runtime_enabled = not lightweight_probe_client or is_local_owner
	operator.name = "NetworkOperator_%d" % peer_id
	operator.position = spawn_position
	operator.rotation.y = PI if team == 0 else 0.0
	operator.interpolation_delay_seconds = remote_interpolation_delay_seconds
	_apply_competitive_movement_profile(operator)
	operator.configure_max_health(
		float(PlayerGameplayProfile.load_profile().get("max_health", 100.0)),
		true
	)
	add_child(operator)
	operator.configure_identity(peer_id, team)
	operators[peer_id] = operator
	operator_state_history[peer_id] = []
	peer_transport_one_way_ms[peer_id] = 0.0
	operator.set_replica_mode(not is_local_owner and not multiplayer.is_server())
	operator.set_local_input_enabled(is_local_owner)
	operator.configure_network_presentation(is_local_owner, multiplayer.is_server())
	if multiplayer.is_server():
		operator.eliminated.connect(_on_operator_eliminated)
	if is_local_owner:
		local_operator = operator
		if operator.mannequin != null:
			_attach_local_camera(operator)
	_update_bomb_visual()
	print("MP_SLICE OPERATOR_SPAWN peer=%d team=%d local=%s" % [peer_id, team, is_local_owner])
	_refresh_scoreboard()


func _apply_competitive_movement_profile(operator) -> void:
	if operator == null:
		return
	var document := PlaytestStateCollector.bundled_state("movement")
	var movement: Dictionary = document.get("movement", {})
	operator.move_speed = float(movement.get("move_speed", operator.move_speed))
	operator.strafe_speed = float(movement.get("strafe_speed", operator.strafe_speed))
	operator.instant_strafe_response = bool(
		movement.get("instant_strafe_response", operator.instant_strafe_response)
	)
	operator.strafe_burst_frames = clampi(
		int(movement.get("strafe_burst_frames", operator.strafe_burst_frames)),
		1,
		4
	)
	operator.strafe_burst_multiplier = clampf(
		float(movement.get("strafe_burst_multiplier", operator.strafe_burst_multiplier)),
		1.0,
		1.5
	)
	operator.strafe_burst_decay_seconds = clampf(
		float(movement.get(
			"strafe_burst_decay_seconds",
			operator.strafe_burst_decay_seconds
		)),
		0.0,
		0.40
	)
	operator.strafe_chain_window_seconds = clampf(
		float(movement.get(
			"strafe_chain_window_seconds",
			operator.strafe_chain_window_seconds
		)),
		0.20,
		1.50
	)


func _remove_operator(peer_id: int) -> void:
	var operator: Variant = operators.get(peer_id)
	if operator != null:
		operator.queue_free()
	operators.erase(peer_id)
	latest_commands.erase(peer_id)
	last_accepted_shot_sequence.erase(peer_id)
	last_enqueued_shot_sequence.erase(peer_id)
	pending_shot_packets.erase(peer_id)
	pending_reload_requests.erase(peer_id)
	last_rejected_shot_reason.erase(peer_id)
	last_command_tick.erase(peer_id)
	operator_state_history.erase(peer_id)
	peer_transport_one_way_ms.erase(peer_id)
	pending_time_sync.erase(peer_id)
	scores.erase(peer_id)
	assigned_spawns.erase(peer_id)
	var ballistics := server_ballistics.get(peer_id) as Node
	if ballistics != null:
		ballistics.queue_free()
	server_ballistics.erase(peer_id)
	server_composure.erase(peer_id)
	server_magazine_ammo.erase(peer_id)
	server_reserve_ammo.erase(peer_id)
	_refresh_scoreboard()


func _clear_operators() -> void:
	for peer_id in operators.keys():
		_remove_operator(int(peer_id))
	operators.clear()
	local_operator = null
	if local_camera:
		local_camera.queue_free()
		local_camera = null


func _attach_local_camera(operator) -> void:
	if local_camera != null:
		local_camera.queue_free()
	local_camera = CameraRigScript.new() as SocomCameraRig
	local_camera.name = "LocalSOCOMCamera"
	local_camera.target = operator
	local_camera.head_marker = operator.mannequin.head_marker
	local_camera.torso_marker = operator.mannequin.torso_marker
	local_camera.pelvis_marker = operator.mannequin.pelvis_marker
	local_camera.feet_marker = operator.mannequin.feet_marker
	local_camera.yaw = operator.global_rotation.y
	add_child(local_camera)
	var acoustic: Node = get_node_or_null("/root/AcousticPropagation")
	if acoustic != null and acoustic.has_method("set_listener"):
		acoustic.call("set_listener", local_camera)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _advance_time_sync(delta: float) -> void:
	if not multiplayer.is_server():
		return
	time_sync_accumulator += maxf(delta, 0.0)
	if time_sync_accumulator < TIME_SYNC_INTERVAL_SECONDS:
		return
	time_sync_accumulator = fmod(time_sync_accumulator, TIME_SYNC_INTERVAL_SECONDS)
	for raw_peer_id in multiplayer.get_peers():
		var peer_id := int(raw_peer_id)
		time_sync_nonce += 1
		var server_send_ms := float(Time.get_ticks_msec())
		pending_time_sync[peer_id] = {
			"nonce": time_sync_nonce,
			"server_send_ms": server_send_ms,
		}
		receive_time_sync_probe.rpc_id(peer_id, time_sync_nonce, server_send_ms)


func _server_timestamp_to_local_seconds(server_timestamp_ms: float) -> float:
	if multiplayer.is_server():
		return server_timestamp_ms / 1000.0
	if not server_clock_synchronized:
		# Until the first probe completes, receive time is a safe local timeline.
		return float(Time.get_ticks_msec()) / 1000.0
	return (server_timestamp_ms - server_clock_offset_ms) / 1000.0


func _record_server_operator_history() -> void:
	if not multiplayer.is_server():
		return
	var now_ms := float(Time.get_ticks_msec())
	var cutoff_ms := now_ms - OPERATOR_HISTORY_SECONDS * 1000.0
	for raw_id in operators:
		var peer_id: int = int(raw_id)
		var operator: Variant = operators[raw_id]
		if operator == null:
			continue
		var history: Array = operator_state_history.get(peer_id, [])
		history.append({
			"time_ms": now_ms,
			"position": operator.global_position,
			"yaw": operator.global_rotation.y,
			"posture": operator.get_posture_name(),
		})
		while history.size() > 2 and float(history[0].get("time_ms", 0.0)) < cutoff_ms:
			history.pop_front()
		operator_state_history[peer_id] = history


func _sample_operator_history(history: Array, target_time_ms: float) -> Dictionary:
	if history.is_empty():
		return {}
	var first: Dictionary = history.front()
	var last: Dictionary = history.back()
	if target_time_ms <= float(first.get("time_ms", target_time_ms)):
		return first.duplicate(true)
	if target_time_ms >= float(last.get("time_ms", target_time_ms)):
		return last.duplicate(true)
	for index in range(history.size() - 1):
		var older: Dictionary = history[index]
		var newer: Dictionary = history[index + 1]
		var older_ms := float(older.get("time_ms", 0.0))
		var newer_ms := float(newer.get("time_ms", older_ms))
		if target_time_ms < older_ms or target_time_ms > newer_ms:
			continue
		var weight := clampf(
			(target_time_ms - older_ms) / maxf(newer_ms - older_ms, 0.001),
			0.0,
			1.0
		)
		return {
			"time_ms": target_time_ms,
			"position": Vector3(older.get("position", Vector3.ZERO)).lerp(
				Vector3(newer.get("position", Vector3.ZERO)),
				weight
			),
			"yaw": lerp_angle(
				float(older.get("yaw", 0.0)),
				float(newer.get("yaw", 0.0)),
				weight
			),
		}
	return last.duplicate(true)


func _transport_compensation_seconds(peer_id: int) -> float:
	return clampf(
		float(peer_transport_one_way_ms.get(peer_id, 0.0)),
		0.0,
		MAX_TRANSPORT_COMPENSATION_MS
	) / 1000.0


func _begin_transport_rewind(shooter_peer_id: int) -> Array[Dictionary]:
	var compensation_seconds := _transport_compensation_seconds(shooter_peer_id)
	if compensation_seconds <= 0.0001:
		return []
	var target_time_ms := float(Time.get_ticks_msec()) - compensation_seconds * 1000.0
	var restore: Array[Dictionary] = []
	for raw_id in operators:
		var peer_id: int = int(raw_id)
		if peer_id == shooter_peer_id:
			continue
		var operator: Variant = operators[raw_id]
		if operator == null or not operator.alive:
			continue
		var sampled: Dictionary = _sample_operator_history(
			operator_state_history.get(peer_id, []),
			target_time_ms
		)
		if sampled.is_empty():
			continue
		restore.append({
			"operator": operator,
			"transform": operator.global_transform,
		})
		operator.global_position = Vector3(sampled.get("position", operator.global_position))
		operator.global_rotation.y = float(sampled.get("yaw", operator.global_rotation.y))
		operator.force_update_transform()
		if operator.hurtbox_rig != null:
			operator.hurtbox_rig.force_pose_update()
	return restore


func _restore_transport_rewind(restore: Array[Dictionary]) -> void:
	for entry in restore:
		var operator: Variant = entry.get("operator")
		if operator == null or not is_instance_valid(operator):
			continue
		operator.global_transform = Transform3D(entry.get("transform", operator.global_transform))
		operator.force_update_transform()
		if operator.hurtbox_rig != null:
			operator.hurtbox_rig.force_pose_update()
