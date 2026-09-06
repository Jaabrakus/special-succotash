extends "res://scripts/network/socom_multiplayer_combat.gd"

func _on_operator_eliminated(victim_peer_id: int, attacker_peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	var victim: Variant = operators.get(victim_peer_id)
	if String(mission_rules.get("primary_mode", "demolition")) == "demolition":
		_drop_bomb_from_peer(victim_peer_id)
		if (
			victim != null
			and bool(round_rules.get("win_by_elimination", true))
			and _team_is_eliminated(victim.team_id)
		):
			if bomb_planted and victim.team_id == bomb_planting_team:
				# A live planted bomb is still a win condition. Eliminating the
				# attackers does not replace the defender's required defuse.
				_set_status("ATTACKERS ELIMINATED  •  DEFUSE THE BOMB")
				receive_match_event.rpc("ATTACKERS ELIMINATED  •  DEFUSE THE BOMB")
			else:
				_server_finish_round(1 - victim.team_id, "TEAM ELIMINATION")
		return
	if attacker_peer_id != victim_peer_id and scores.has(attacker_peer_id):
		scores[attacker_peer_id] = int(scores[attacker_peer_id]) + 1
	_refresh_scoreboard()
	if int(scores.get(attacker_peer_id, 0)) >= SCORE_LIMIT:
		_end_round(attacker_peer_id)
	else:
		_respawn_after_delay(victim_peer_id)


func _end_round(winner_peer_id: int) -> void:
	if not round_active:
		return
	round_active = false
	var message := "ROUND WON BY SEAL %d  •  resetting in 4 seconds" % winner_peer_id
	_set_status(message)
	receive_match_event.rpc(message)
	await get_tree().create_timer(4.0).timeout
	if not multiplayer.is_server():
		return
	for raw_id in scores:
		scores[raw_id] = 0
	for raw_id in operators:
		var peer_id: int = int(raw_id)
		var operator: Variant = operators[raw_id]
		operator.respawn_at(Vector3(assigned_spawns.get(peer_id, _spawn_for_peer(peer_id))))
		_reset_ammo_for_peer(peer_id)
	round_active = true
	_set_status("NEW ROUND  •  first to %d" % SCORE_LIMIT)
	receive_match_event.rpc("NEW ROUND  •  first to %d" % SCORE_LIMIT)
	_refresh_scoreboard()


func _team_is_eliminated(team: int) -> bool:
	var found_member := false
	for raw_id: Variant in operators.keys():
		var operator: Variant = operators[raw_id]
		if operator == null or operator.team_id != team:
			continue
		found_member = true
		if operator.alive:
			return false
	return found_member


func _advance_round_clock(delta: float) -> void:
	var decision := RoundPolicy.advance_clock(round_time_remaining, last_round_clock_second, delta,
		session_active and round_active and not round_resolution_pending and not bomb_planted,
		String(round_rules.get("timeout_result", "draw")))
	round_time_remaining = decision.remaining
	last_round_clock_second = decision.shown
	if decision.broadcast:
		_broadcast_round_state()
	if decision.expired:
		_server_finish_round(int(decision.winner), "TIME EXPIRED")


func _server_finish_round(winner_team: int, reason: String) -> void:
	if not multiplayer.is_server() or not round_active or round_resolution_pending:
		return
	round_resolution_pending = true
	round_active = false
	if winner_team in [0, 1]:
		team_round_wins[winner_team] = int(team_round_wins.get(winner_team, 0)) + 1
	var winner_text := "DRAW" if winner_team < 0 else ("ALPHA" if winner_team == 0 else "BRAVO")
	var message := "%s ROUND  •  %s  •  resetting in 4 seconds" % [winner_text, reason]
	_set_status(message)
	receive_match_event.rpc(message)
	_broadcast_round_state()
	await get_tree().create_timer(4.0).timeout
	if not multiplayer.is_server():
		return
	var match_complete := RoundPolicy.match_complete(winner_team, team_round_wins, round_index, round_rules)
	if match_complete:
		_server_return_to_lobby(winner_team)
	else:
		_server_start_next_round()


func _server_start_next_round() -> void:
	round_index += 1
	var team_members := {0: 0, 1: 0}
	for raw_id: Variant in operators.keys():
		var peer_id := int(raw_id)
		var operator: Variant = operators[raw_id]
		var team: int = int(operator.team_id)
		var member_index := int(team_members.get(team, 0))
		var spawn_position := _spawn_for_team(team, member_index)
		team_members[team] = member_index + 1
		assigned_spawns[peer_id] = spawn_position
		operator.respawn_at(spawn_position)
		_reset_ammo_for_peer(peer_id)
	round_time_remaining = float(round_rules.get("time_limit_seconds", 300))
	last_round_clock_second = -1
	round_resolution_pending = false
	round_active = true
	_reset_demolition_objective()
	receive_match_started(round_index, round_time_remaining)
	receive_match_started.rpc(round_index, round_time_remaining)
	_broadcast_round_state()
	var message := "ROUND %d STARTED" % round_index
	_set_status(message)
	receive_match_event.rpc(message)


func _server_return_to_lobby(last_winner_team: int) -> void:
	var alpha_rounds := int(team_round_wins.get(0, 0))
	var bravo_rounds := int(team_round_wins.get(1, 0))
	var winner_team := last_winner_team
	if alpha_rounds != bravo_rounds:
		winner_team = 0 if alpha_rounds > bravo_rounds else 1
	var winner_text := "MATCH DRAW" if alpha_rounds == bravo_rounds else "%s WINS MATCH" % ("ALPHA" if winner_team == 0 else "BRAVO")
	var message := "%s  •  %d-%d" % [winner_text, alpha_rounds, bravo_rounds]
	session_active = false
	round_active = false
	round_resolution_pending = false
	_reset_demolition_objective()
	for raw_id: Variant in operators.keys():
		despawn_operator.rpc(int(raw_id))
	_clear_operators()
	lobby.phase = LobbyStateScript.PHASE_WAITING
	lobby.clear_ready_states()
	_show_lobby(true)
	receive_return_to_lobby.rpc(message)
	_broadcast_lobby()
	_set_status(message)


func _broadcast_round_state() -> void:
	receive_round_state(
		round_time_remaining,
		int(team_round_wins.get(0, 0)),
		int(team_round_wins.get(1, 0)),
		round_index,
		round_active
	)
	if multiplayer.multiplayer_peer != null and multiplayer.is_server():
		receive_round_state.rpc(
			round_time_remaining,
			int(team_round_wins.get(0, 0)),
			int(team_round_wins.get(1, 0)),
			round_index,
			round_active
		)


func _respawn_after_delay(peer_id: int) -> void:
	await get_tree().create_timer(RESPAWN_SECONDS).timeout
	if not multiplayer.is_server():
		return
	var operator: Variant = operators.get(peer_id)
	if operator:
		operator.respawn_at(Vector3(assigned_spawns.get(peer_id, _spawn_for_peer(peer_id))))
		_reset_ammo_for_peer(peer_id)


func _present_shot(shooter_peer_id: int, origin: Vector3, impact: Vector3, hit: bool, message: String) -> void:
	if not dedicated_server_mode and shot_presentation != null:
		shot_presentation.present_shot(origin, impact, hit, message,
			_weapon_config_for_peer(shooter_peer_id), _acoustic_exclusions_for_shooter(shooter_peer_id))
	if shooter_peer_id == multiplayer.get_unique_id():
		if local_camera != null and not dedicated_server_mode:
			local_camera.notify_functional_aim_climb()
		if reticle != null and not dedicated_server_mode:
			reticle.notify_shot()
		_set_status("SHOT  •  %s" % message)


func _acoustic_exclusions_for_shooter(shooter_peer_id: int) -> Array:
	var exclusions: Array = []
	var shooter := operators.get(shooter_peer_id) as Node
	if shooter == null:
		return exclusions
	if shooter is CollisionObject3D:
		exclusions.append((shooter as CollisionObject3D).get_rid())
	for child in shooter.find_children("*", "CollisionObject3D", true, false):
		if child is CollisionObject3D:
			exclusions.append((child as CollisionObject3D).get_rid())
	return exclusions


func _apply_ballistics_profile(ballistics, weapon_config: Dictionary = {}) -> void:
	var resolved_config := weapon_config if not weapon_config.is_empty() else equipped_config
	var values: Dictionary = resolved_config.get("ballistics", {})
	ballistics.fire_rate_rpm = float(values.get("fire_rate_rpm", 600.0))
	ballistics.damage_per_shot = float(values.get("damage", 34.0))
	ballistics.headshot_multiplier = clampf(
		float(values.get("headshot_multiplier", 3.5)), 1.0, 10.0
	)
	ballistics.muzzle_velocity_mps = float(values.get("muzzle_velocity_mps", 715.0))
	ballistics.base_spread_deg = float(values.get("base_spread_deg", 0.28))
	ballistics.moving_spread_deg = float(values.get("moving_spread_deg", 0.95))
	ballistics.full_gait_spread_deg = float(values.get("full_gait_spread_deg", 1.55))
	ballistics.opening_burst_motion_multiplier = float(
		values.get("opening_burst_motion_multiplier", 0.35)
	)
	ballistics.bloom_per_shot_deg = float(values.get("bloom_per_shot_deg", 0.32))
	ballistics.max_recoil_bloom_deg = float(values.get("max_recoil_bloom_deg", 2.4))
	ballistics.bloom_recovery_speed = float(values.get("bloom_recovery_speed", 10.0))
	ballistics.crouch_spread_multiplier = float(values.get("crouch_spread_multiplier", 0.72))
	ballistics.crouch_bloom_per_shot_deg = float(values.get("crouch_bloom_per_shot_deg", 1.35))
	ballistics.crouch_max_recoil_bloom_deg = float(values.get("crouch_max_recoil_bloom_deg", 1.70))
	ballistics.crouch_bloom_recovery_speed = float(values.get("crouch_bloom_recovery_speed", 18.0))
	ballistics.configure_projectiles(values)
	ballistics.fire_interval = 60.0 / maxf(1.0, ballistics.fire_rate_rpm)


func _configured_fire_interval() -> float:
	var rpm := float(equipped_config.get("ballistics", {}).get("fire_rate_rpm", 600.0))
	return 60.0 / maxf(1.0, rpm)


func _request_local_reload() -> void:
	if (
		local_operator == null
		or local_operator.mannequin == null
		or local_reload_pending
		or not local_operator.alive
		or local_reserve_ammo <= 0
		or local_magazine_ammo >= int(equipped_config.get("ballistics", {}).get("magazine_capacity", 30))
	):
		return
	var driver: Node = local_operator.mannequin.get("production_animation") as Node
	if driver == null:
		return
	if not local_operator.mannequin.play_operator_semantic_action_timed(
		&"reload",
		float(driver.call("weapon_reload_duration_seconds")),
		0.12
	):
		return
	local_reload_pending = true
	# Clear the counterpart's previous one-shot subscription before replay.
	if driver.action_completed.is_connected(_on_local_reload_animation_completed):
		driver.action_completed.disconnect(_on_local_reload_animation_completed)
	if driver.action_cancelled.is_connected(_on_local_reload_animation_cancelled):
		driver.action_cancelled.disconnect(_on_local_reload_animation_cancelled)
	driver.action_completed.connect(_on_local_reload_animation_completed, CONNECT_ONE_SHOT)
	driver.action_cancelled.connect(_on_local_reload_animation_cancelled, CONNECT_ONE_SHOT)
	if multiplayer.is_server():
		_server_reload_weapon(multiplayer.get_unique_id())
	else:
		submit_reload.rpc_id(1, true)


func _on_local_reload_animation_completed(clip_name: StringName) -> void:
	if not local_reload_pending or "reload" not in String(clip_name).to_lower():
		return
	local_reload_pending = false
	# Presentation finishing is not an ammunition grant. The server clock owns it.

func _on_local_reload_animation_cancelled(clip_name: StringName) -> void:
	if "reload" in String(clip_name).to_lower():
		local_reload_pending = false
		if multiplayer.is_server():
			var peer_id := multiplayer.get_unique_id()
			combat_commands.cancel_reload(peer_id)
			reload_authority.cancel(peer_id)
		else:
			submit_reload.rpc_id(1, false)
