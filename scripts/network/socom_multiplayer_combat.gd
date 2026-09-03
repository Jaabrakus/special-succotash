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
	var packet: Dictionary = local_camera.build_local_aim_intent()
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
		var peer_id: int = int(raw_id)
		var queue: Array = pending_shot_packets[raw_id]
		if queue.is_empty():
			if bool(pending_reload_requests.get(peer_id, false)):
				pending_reload_requests[peer_id] = false
				_server_reload_weapon(peer_id)
			continue
		var ballistics: Variant = server_ballistics.get(peer_id)
		if ballistics == null or float(ballistics.fire_cooldown) > 0.0:
			continue
		var packet: Dictionary = queue.pop_front()
		pending_shot_packets[raw_id] = queue
		_server_process_shot(peer_id, packet)


func _server_process_shot(peer_id: int, packet: Dictionary) -> void:
	var shooter: Variant = operators.get(peer_id)
	var ballistics: Variant = server_ballistics.get(peer_id)
	if (
		not is_peer_gameplay_action_allowed(peer_id)
		or shooter == null
		or ballistics == null
		or not shooter.alive
		or not round_active
	):
		return
	if int(server_magazine_ammo.get(peer_id, 0)) <= 0:
		_send_ammo_state(peer_id)
		return
	var muzzle_marker: Variant = shooter.mannequin.get_active_muzzle_marker()
	if muzzle_marker == null:
		return
	var muzzle: Vector3 = Vector3(muzzle_marker.global_position)
	var authoritative_report_anchor := _authoritative_shot_report_anchor(shooter)
	var validation_report_anchor := _closest_recent_shot_report_anchor(
		peer_id,
		shooter,
		packet
	)
	var validation := ShotAuthority.validate_intent(
		packet,
		validation_report_anchor,
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
	var muzzle_clearance := ShotAuthority.validate_muzzle_clearance(
		get_world_3d().direct_space_state,
		authoritative_report_anchor,
		muzzle,
		authoritative_shot_direction,
		exclude
	)
	if not bool(muzzle_clearance.get("accepted", false)):
		last_rejected_shot_reason[peer_id] = String(
			muzzle_clearance.get("reason", "MUZZLE_OBSTRUCTED")
		)
		return
	var movement_ratio := clampf(
		Vector2(shooter.velocity.x, shooter.velocity.z).length()
		/ maxf(shooter.move_speed, 0.001),
		0.0,
		1.0
	)
	var composure: Variant = server_composure.get(peer_id)
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
	var seed: int = int(packet.get("sequence", 0)) * 73856093 ^ peer_id * 19349663
	# Rewind only the measured packet transit. The fixed 130 ms remote render
	# buffer is intentionally not rewound, so every player keeps the authored
	# lead requirement while ordinary connection differences are reduced.
	var rewind_restore: Array[Dictionary] = _begin_transport_rewind(peer_id)
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
	var receiver: Variant = null
	var damage_scale: float = 1.0
	var hit_region: StringName = &""
	if collider != null:
		if collider.has_method("get_damage_receiver"):
			receiver = collider.call("get_damage_receiver")
		elif collider.has_method("take_bullet_damage_region"):
			receiver = collider
		if (
			receiver != null
			and receiver.team_id != shooter.team_id
			and is_damage_allowed_between(peer_id, int(receiver.network_peer_id))
		):
			if collider.has_method("classify_shot_path"):
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
						float(_weapon_config_for_peer(peer_id).get("composure", {}).get("graze_damage_scale", 0.38)),
						0.0,
						1.0
					)
				)
			if collider.has_method("get_hit_region"):
				hit_region = StringName(collider.call("get_hit_region"))
			else:
				hit_region = &"TORSO"
	_restore_transport_rewind(rewind_restore)
	if (
		receiver != null
		and receiver.team_id != shooter.team_id
		and is_damage_allowed_between(peer_id, int(receiver.network_peer_id))
	):
			var damage_result: Dictionary = receiver.take_bullet_damage_region(
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
	_broadcast_shot_effect(peer_id, muzzle, Vector3(result.hit_pos), hit, damage_message)


func _broadcast_shot_effect(
	shooter_peer_id: int,
	origin: Vector3,
	impact: Vector3,
	hit: bool,
	message: String
) -> void:
	receive_shot_effect.rpc(shooter_peer_id, origin, impact, hit, message)


func _authoritative_shot_report_anchor(shooter) -> Vector3:
	if shooter == null:
		return Vector3.ZERO
	var posture_name: StringName = StringName(shooter.get_posture_name())
	return shooter.global_position + Vector3.UP * _shot_report_height(posture_name)


func _closest_recent_shot_report_anchor(
	peer_id: int,
	shooter,
	packet: Dictionary
) -> Vector3:
	# The reported point is never a trace origin. It is only checked against
	# recent server-owned body anchors so a fast legitimate movement step does
	# not fail solely because the reliable shot arrived between simulations.
	var current_anchor := _authoritative_shot_report_anchor(shooter)
	if typeof(packet.get("reported_muzzle_origin")) != TYPE_VECTOR3:
		return current_anchor
	var reported_anchor: Vector3 = packet.get("reported_muzzle_origin")
	if not reported_anchor.is_finite():
		return current_anchor
	var closest_anchor := current_anchor
	var closest_distance := reported_anchor.distance_squared_to(current_anchor)
	var cutoff_ms := (
		float(Time.get_ticks_msec()) - OPERATOR_HISTORY_SECONDS * 1000.0
	)
	var history: Array = operator_state_history.get(peer_id, [])
	for entry_value in history:
		if not (entry_value is Dictionary):
			continue
		var entry := entry_value as Dictionary
		if float(entry.get("time_ms", 0.0)) < cutoff_ms:
			continue
		if typeof(entry.get("position")) != TYPE_VECTOR3:
			continue
		var position_value: Vector3 = entry.get("position")
		if not position_value.is_finite():
			continue
		var posture_name := StringName(
			entry.get("posture", shooter.get_posture_name())
		)
		var candidate_anchor := (
			position_value + Vector3.UP * _shot_report_height(posture_name)
		)
		var candidate_distance := reported_anchor.distance_squared_to(
			candidate_anchor
		)
		if candidate_distance < closest_distance:
			closest_anchor = candidate_anchor
			closest_distance = candidate_distance
	return closest_anchor


func _shot_report_height(posture_name: StringName) -> float:
	var report_height := 1.35
	if posture_name == &"CROUCHED":
		report_height = 0.95
	elif posture_name == &"PRONE":
		report_height = 0.45
	return report_height


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
		var peer_id: int = int(raw_id)
		var operator: Variant = operators.get(peer_id)
		if operator == null:
			continue
		var ratio: float = clampf(
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
		var operator: Variant = operators[raw_id]
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
