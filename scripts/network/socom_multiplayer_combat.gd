extends "res://scripts/network/socom_multiplayer_replication.gd"

func _try_submit_local_shot() -> void:
	if (
		local_camera == null
		or local_operator == null
		or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED
		or not Input.is_action_pressed("fire")
		or local_fire_cooldown > 0.0
		or local_reload_pending
	):
		return
	local_fire_cooldown = _configured_fire_interval()
	var packet := local_camera.build_local_aim_intent()
	if packet.is_empty():
		return
	if multiplayer.is_server():
		_server_process_shot(multiplayer.get_unique_id(), packet)
	else:
		submit_shot.rpc_id(1, packet)


func _queue_server_shot(peer_id: int, packet: Dictionary) -> bool:
	if not multiplayer.is_server() or not operators.has(peer_id):
		return false
	if typeof(packet.get("sequence")) != TYPE_INT:
		return false
	var sequence := int(packet.sequence)
	if sequence <= int(last_enqueued_shot_sequence.get(peer_id, -1)):
		return false
	var queue: Array = pending_shot_packets.get(peer_id, [])
	if queue.size() >= MAX_QUEUED_SHOTS_PER_PEER:
		return false
	queue.append(packet.duplicate(true))
	pending_shot_packets[peer_id] = queue
	last_enqueued_shot_sequence[peer_id] = sequence
	return true


func _advance_pending_server_shots() -> void:
	for raw_id in pending_shot_packets:
		var peer_id := int(raw_id)
		var queue: Array = pending_shot_packets[raw_id]
		if queue.is_empty():
			if bool(pending_reload_requests.get(peer_id, false)):
				pending_reload_requests[peer_id] = false
				_server_reload_weapon(peer_id)
			continue
		var ballistics = server_ballistics.get(peer_id)
		if ballistics == null or float(ballistics.fire_cooldown) > 0.0:
			continue
		var packet: Dictionary = queue.pop_front()
		pending_shot_packets[raw_id] = queue
		_server_process_shot(peer_id, packet)


func _server_process_shot(peer_id: int, packet: Dictionary) -> void:
	var shooter := operators.get(peer_id) as SocomNetworkOperator
	var ballistics = server_ballistics.get(peer_id)
	if shooter == null or ballistics == null or not shooter.alive or not round_active:
		return
	if int(server_magazine_ammo.get(peer_id, 0)) <= 0:
		_send_ammo_state(peer_id)
		return
	var muzzle_marker := shooter.mannequin.get_active_muzzle_marker()
	if muzzle_marker == null:
		return
	var muzzle := muzzle_marker.global_position
	var authoritative_report_anchor := _authoritative_shot_report_anchor(shooter)
	var validation := ShotAuthority.validate_intent(
		packet,
		authoritative_report_anchor,
		int(last_accepted_shot_sequence.get(peer_id, -1)),
		-1
	)
	if not bool(validation.get("accepted", false)):
		last_rejected_shot_reason[peer_id] = String(
			validation.get("reason", "INVALID_AIM_INTENT")
		)
		return
	last_accepted_shot_sequence[peer_id] = int(packet.get("sequence", 0))
	var authoritative_shot_direction := ShotAuthority.resolve_trace_direction(
		validation,
		authoritative_report_anchor,
		muzzle
	)
	var exclude: Array[RID] = [shooter.get_rid()]
	if shooter.hurtbox_rig:
		exclude.append_array(shooter.hurtbox_rig.get_hurtbox_rids())
	var movement_ratio := clampf(
		Vector2(shooter.velocity.x, shooter.velocity.z).length()
		/ maxf(shooter.move_speed, 0.001),
		0.0,
		1.0
	)
	var composure = server_composure.get(peer_id)
	var retained_instability: float = float(composure.get_shot_instability(
		movement_ratio,
		0.0
	))
	var dispersion_multiplier: float = float(composure.get_shot_dispersion_multiplier(
		int(ballistics.continuous_shot_count) + 1,
		movement_ratio,
		0.0
	))
	var core_scale: float = float(composure.get_precision_core_scale())
	var seed := int(packet.get("sequence", 0)) * 73856093 ^ peer_id * 19349663
	# Rewind only the measured packet transit. The fixed 130 ms remote render
	# buffer is intentionally not rewound, so every player keeps the authored
	# lead requirement while ordinary connection differences are reduced.
	var rewind_restore := _begin_transport_rewind(peer_id)
	var result: Dictionary = ballistics.try_fire_direction(
		muzzle,
		authoritative_shot_direction,
		get_world_3d().direct_space_state,
		exclude,
		seed,
		shooter.get_posture_name(),
		retained_instability,
		not shooter.is_on_floor(),
		dispersion_multiplier
	)
	if not bool(result.get("fired", false)):
		last_rejected_shot_reason[peer_id] = String(result.get("reason", "CADENCE"))
		_restore_transport_rewind(rewind_restore)
		return
	last_rejected_shot_reason[peer_id] = ""
	server_magazine_ammo[peer_id] = maxi(
		0,
		int(server_magazine_ammo.get(peer_id, 0)) - 1
	)
	_send_ammo_state(peer_id)
	composure.notify_shot()
	var damage_message := "MISS"
	var collider: Object = result.get("hit_collider")
	var receiver: SocomNetworkOperator = null
	var damage_scale := 1.0
	var hit_region := &""
	if collider != null and collider.has_method("get_damage_receiver"):
		receiver = collider.call("get_damage_receiver") as SocomNetworkOperator
		if receiver != null and receiver.team_id != shooter.team_id:
			var classification: Dictionary = collider.call(
				"classify_shot_path",
				muzzle,
				Vector3(result.direction),
				core_scale
			)
			damage_scale = (
				1.0
				if bool(classification.get("precision", true))
				else clampf(
					float(equipped_config.get("composure", {}).get("graze_damage_scale", 0.38)),
					0.0,
					1.0
				)
			)
			hit_region = StringName(collider.call("get_hit_region"))
	_restore_transport_rewind(rewind_restore)
	if receiver != null and receiver.team_id != shooter.team_id:
			var damage_result := receiver.take_bullet_damage_region(
				float(ballistics.damage_per_shot) * damage_scale,
				hit_region,
				Vector3(result.hit_pos),
				Vector3(result.get("normal", Vector3.UP)),
				muzzle,
				peer_id,
				float(ballistics.headshot_multiplier)
			)
			if bool(damage_result.get("accepted", false)):
				damage_message = "%s  %.0f DMG" % [
					String(damage_result.get("hit_region", &"HIT")),
					float(damage_result.get("damage", 0.0)),
				]
				if bool(damage_result.get("headshot", false)):
					_send_head_impact_feedback(
						int(damage_result.get("victim_peer_id", 0)),
						float(damage_result.get("damage", 0.0)),
						bool(damage_result.get("eliminated", false))
					)
	var hit := collider != null
	_present_shot(peer_id, muzzle, Vector3(result.hit_pos), hit, damage_message)
	receive_shot_effect.rpc(peer_id, muzzle, Vector3(result.hit_pos), hit, damage_message)


func _authoritative_shot_report_anchor(shooter: SocomNetworkOperator) -> Vector3:
	var report_height := 1.35
	var posture_name := shooter.get_posture_name()
	if posture_name == &"CROUCHED":
		report_height = 0.95
	elif posture_name == &"PRONE":
		report_height = 0.45
	return shooter.global_position + Vector3.UP * report_height


func _send_head_impact_feedback(
	victim_peer_id: int,
	damage: float,
	eliminated: bool
) -> void:
	if victim_peer_id <= 0:
		return
	if victim_peer_id == multiplayer.get_unique_id():
		receive_damage_feedback("HEAD", damage, eliminated)
	else:
		receive_damage_feedback.rpc_id(victim_peer_id, "HEAD", damage, eliminated)


func _advance_server_composure(delta: float) -> void:
	for raw_id in server_composure:
		var peer_id := int(raw_id)
		var operator := operators.get(peer_id) as SocomNetworkOperator
		if operator == null:
			continue
		var ratio := clampf(
			Vector2(operator.velocity.x, operator.velocity.z).length()
			/ maxf(operator.move_speed, 0.001),
			0.0,
			1.0
		)
		var stance := ComposureScript.Stance.STANDING
		if operator.posture == PlayerScript.MotionState.CROUCHED:
			stance = ComposureScript.Stance.CROUCHED
		elif operator.posture == PlayerScript.MotionState.PRONE:
			stance = ComposureScript.Stance.PRONE
		server_composure[raw_id].advance(delta, ratio, 0.0, stance)


func _broadcast_authoritative_state() -> void:
	var timestamp_ms := Time.get_ticks_msec()
	var tick := Engine.get_physics_frames()
	var snapshot: Dictionary = {}
	var peer_ids: Array = operators.keys()
	peer_ids.sort()
	for raw_id in peer_ids:
		var operator := operators[raw_id] as SocomNetworkOperator
		snapshot[raw_id] = {
			"position": operator.global_position,
			"yaw": operator.rotation.y,
			"velocity": operator.velocity,
			"posture": operator.posture,
			"health": operator.current_health,
			"alive": operator.alive,
		}
	var chunks := NetworkProtocol.chunk_snapshot_entities(
		snapshot,
		SNAPSHOT_ENTITIES_PER_PACKET
	)
	var chunk_count := chunks.size()
	for chunk_index in chunk_count:
		var packet := {
			"timestamp_ms": timestamp_ms,
			"tick": tick,
			"chunk_index": chunk_index,
			"chunk_count": chunk_count,
			"entities": chunks[chunk_index],
		}
		receive_world_state.rpc(packet, scores if chunk_index == 0 else {})
