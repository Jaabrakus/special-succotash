extends "res://scripts/network/socom_multiplayer_replication.gd"

func _server_reload_weapon(peer_id: int) -> void:
	if not multiplayer.is_server() or not is_peer_gameplay_action_allowed(peer_id) or reload_authority.is_active(peer_id):
		return
	var operator: Variant = operators.get(peer_id)
	if operator == null or not operator.alive or (not round_active and not is_lobby_warmup_active()):
		return
	var config: Dictionary = _weapon_config_for_peer(peer_id)
	var capacity := int(config.get("ballistics", {}).get("magazine_capacity", 30))
	if int(server_magazine_ammo.get(peer_id, 0)) >= capacity or int(server_reserve_ammo.get(peer_id, 0)) <= 0:
		return
	# Earlier accepted fire requests retain order; start the clock after they drain.
	if combat_commands.has_shots(peer_id):
		combat_commands.defer_reload(peer_id)
		return
	var context := "%s:%d" % [String(config.get("weapon_id", "")), operator.get_instance_id()]
	reload_authority.begin(peer_id, context, reload_authority.duration_seconds(config), Time.get_ticks_msec())


func _advance_server_reloads() -> void:
	if not multiplayer.is_server():
		return
	for raw_id in reload_authority.peer_ids():
		var peer_id := int(raw_id)
		var operator: Variant = operators.get(peer_id)
		if not is_peer_gameplay_action_allowed(peer_id) or operator == null or not operator.alive or (not round_active and not is_lobby_warmup_active()):
			reload_authority.cancel(peer_id)
			continue
		# Cheap clock check first: do not parse/normalize a weapon profile each tick.
		if not reload_authority.is_due(peer_id, Time.get_ticks_msec()):
			continue
		var config: Dictionary = _weapon_config_for_peer(peer_id)
		var context := "%s:%d" % [String(config.get("weapon_id", "")), operator.get_instance_id()]
		if not reload_authority.consume_ready(peer_id, context, Time.get_ticks_msec()):
			continue
		var capacity := int(config.get("ballistics", {}).get("magazine_capacity", 30))
		var magazine := int(server_magazine_ammo.get(peer_id, 0))
		var reserve := int(server_reserve_ammo.get(peer_id, 0))
		var transferred := mini(maxi(0, capacity - magazine), reserve)
		server_magazine_ammo[peer_id] = magazine + transferred
		server_reserve_ammo[peer_id] = reserve - transferred
		_send_ammo_state(peer_id)


func _try_submit_local_shot() -> void:
	if local_reload_pending and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and Input.is_action_just_pressed("fire"):
		if local_operator != null and local_operator.mannequin != null:
			var driver: Node = local_operator.mannequin.get("production_animation")
			if driver != null:
				driver.call("cancel_reload_action")
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
		reload_authority.cancel(multiplayer.get_unique_id())
		combat_commands.cancel_reload(multiplayer.get_unique_id())
		_server_process_shot(multiplayer.get_unique_id(), packet)
	else:
		submit_shot.rpc_id(1, packet)


func _queue_server_shot(peer_id: int, packet: Dictionary) -> bool:
	if not multiplayer.is_server() or not operators.has(peer_id):
		return false
	if not combat_commands.enqueue(peer_id, packet, MAX_QUEUED_SHOTS_PER_PEER):
		return false
	reload_authority.cancel(peer_id)
	return true


func _advance_pending_server_shots() -> void:
	_advance_server_reloads()
	for raw_id in combat_commands.peer_ids():
		var peer_id := int(raw_id)
		if not combat_commands.has_shots(peer_id):
			if combat_commands.consume_reload(peer_id):
				_server_reload_weapon(peer_id)
			continue
		var ballistics: Variant = server_ballistics.get(peer_id)
		var ready: bool = ballistics != null and float(ballistics.fire_cooldown) <= 0.0
		var packet: Dictionary = combat_commands.pop_ready(peer_id, ready)
		if not packet.is_empty():
			_server_process_shot(peer_id, packet)


func _server_process_shot(peer_id: int, packet: Dictionary) -> void:
	var shooter: Variant = operators.get(peer_id)
	var ballistics: Variant = server_ballistics.get(peer_id)
	if (
		not is_peer_gameplay_action_allowed(peer_id)
		or shooter == null
		or ballistics == null
		or not shooter.alive
		or (not round_active and not is_lobby_warmup_active())
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
	# Classify every pellet against the same rewound pose, then restore once.
	var impacts: Array[Dictionary] = []
	for projectile: Dictionary in result.get("projectiles", [result]):
		var collider: Object = projectile.get("hit_collider")
		var receiver: Variant = null
		if collider != null:
			if collider.has_method("get_damage_receiver"):
				receiver = collider.call("get_damage_receiver")
			elif collider.has_method("take_bullet_damage_region"):
				receiver = collider
		var scale := 1.0
		var region: StringName = &"TORSO"
		if receiver != null and _shot_can_damage_peer(peer_id, int(receiver.network_peer_id)):
			if collider.has_method("classify_shot_path"):
				var classification: Dictionary = collider.call(
					"classify_shot_path", muzzle, Vector3(projectile.direction), core_scale)
				if not bool(classification.get("precision", true)):
					scale = clampf(float(_weapon_config_for_peer(peer_id).get(
						"composure", {}).get("graze_damage_scale", 0.38)), 0.0, 1.0)
			if collider.has_method("get_hit_region"):
				region = StringName(collider.call("get_hit_region"))
		else:
			receiver = null
		impacts.append({"projectile": projectile, "receiver": receiver,
			"scale": scale, "region": region})
	_restore_transport_rewind(rewind_restore)
	var visual_impacts: Array[Dictionary] = []
	for impact: Dictionary in impacts:
		var projectile: Dictionary = impact.projectile
		var receiver: Variant = impact.receiver
		var message := "MISS"
		if is_instance_valid(receiver):
			var damage_result: Dictionary = receiver.take_bullet_damage_region(
				float(projectile.get("damage", ballistics.damage_per_shot)) * float(impact.scale),
				StringName(impact.region), Vector3(projectile.hit_pos),
				Vector3(projectile.get("normal", Vector3.UP)), muzzle, peer_id,
				float(ballistics.headshot_multiplier))
			if bool(damage_result.get("accepted", false)):
				message = "%s  %.0f DMG" % [String(damage_result.get("hit_region", &"HIT")),
					float(damage_result.get("damage", 0.0))]
				if bool(damage_result.get("headshot", false)):
					_send_head_impact_feedback(int(damage_result.get("victim_peer_id", 0)),
						float(damage_result.get("damage", 0.0)), bool(damage_result.get("eliminated", false)))
		visual_impacts.append({"position": projectile.hit_pos,
			"hit": projectile.get("hit_collider") != null, "message": message})
	var first: Dictionary = visual_impacts.pop_front()
	_present_shot(peer_id, muzzle, Vector3(first.position), bool(first.hit), String(first.message))
	_broadcast_shot_effect(peer_id, muzzle, Vector3(first.position), bool(first.hit), String(first.message))
	if not visual_impacts.is_empty():
		_present_pellet_impacts(peer_id, muzzle, visual_impacts)
		_broadcast_pellet_impacts(peer_id, muzzle, visual_impacts)


func _shot_can_damage_peer(attacker: int, victim: int) -> bool:
	return operators.has(attacker) and operators.has(victim) and (
		operators[attacker].team_id != operators[victim].team_id
		and is_damage_allowed_between(attacker, victim))


func _broadcast_pellet_impacts(shooter: int, origin: Vector3, impacts: Array[Dictionary]) -> void:
	receive_pellet_impacts.rpc(shooter, origin, impacts)


@rpc("authority", "call_remote", "reliable")
func receive_pellet_impacts(shooter: int, origin: Vector3, impacts: Array[Dictionary]) -> void:
	_present_pellet_impacts(shooter, origin, impacts)


func _present_pellet_impacts(shooter: int, origin: Vector3, impacts: Array[Dictionary]) -> void:
	if not dedicated_server_mode and shot_presentation != null:
		shot_presentation.present_pellets(origin, impacts, _weapon_config_for_peer(shooter))



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
	var peer_ids: Array = operators.keys()
	peer_ids.sort()
	var snapshot := SnapshotEncoder.capture(operators, peer_ids)
	for packet in SnapshotEncoder.packets(snapshot, Time.get_ticks_msec(), Engine.get_physics_frames(), SNAPSHOT_ENTITIES_PER_PACKET):
		receive_world_state.rpc(packet, scores if int(packet.chunk_index) == 0 else {})
