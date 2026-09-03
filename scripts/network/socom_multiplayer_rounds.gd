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
	if not session_active or not round_active or round_resolution_pending:
		return
	if bomb_planted:
		return
	round_time_remaining = maxf(0.0, round_time_remaining - delta)
	var shown_second := ceili(round_time_remaining)
	if shown_second != last_round_clock_second:
		last_round_clock_second = shown_second
		_broadcast_round_state()
	if round_time_remaining <= 0.0:
		var timeout_result := String(round_rules.get("timeout_result", "draw"))
		var winner_team := -1
		if timeout_result == "alpha":
			winner_team = 0
		elif timeout_result == "bravo":
			winner_team = 1
		_server_finish_round(winner_team, "TIME EXPIRED")


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
	var rounds_to_win := int(round_rules.get("rounds_to_win", 4))
	var maximum_rounds := int(round_rules.get("maximum_rounds", 7))
	var match_complete := (
		(winner_team in [0, 1] and int(team_round_wins.get(winner_team, 0)) >= rounds_to_win)
		or round_index >= maximum_rounds
	)
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


func _present_shot(
	shooter_peer_id: int,
	origin: Vector3,
	impact: Vector3,
	hit: bool,
	message: String
) -> void:
	var weapon_config := _weapon_config_for_peer(shooter_peer_id)
	TracerSystemScript.spawn_tracer(
		get_tree(),
		origin,
		impact,
		Color(1.0, 0.86, 0.30),
		float(weapon_config.get("ballistics", {}).get("muzzle_velocity_mps", 715.0))
	)
	if not dedicated_server_mode:
		AudioEngine.play_gunshot(
			get_tree(),
			bool(weapon_config.get("ballistics", {}).get("is_silenced", false)),
			origin,
			false,
			_acoustic_exclusions_for_shooter(shooter_peer_id)
		)
	if hit:
		if message != "MISS":
			TracerSystemScript.spawn_body_hit_effect(
				get_tree(), impact, Vector3.UP, message.begins_with("HEAD")
			)
			if not dedicated_server_mode:
				AudioEngine.play_body_impact(
					get_tree(), impact, message.begins_with("HEAD")
				)
		else:
			TracerSystemScript.spawn_impact_effect(get_tree(), impact, Vector3.UP)
	if shooter_peer_id == multiplayer.get_unique_id():
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
	ballistics.fire_interval = 60.0 / maxf(60.0, ballistics.fire_rate_rpm)


func _configured_fire_interval() -> float:
	var rpm := float(equipped_config.get("ballistics", {}).get("fire_rate_rpm", 600.0))
	return 60.0 / maxf(60.0, rpm)


func _request_local_reload() -> void:
	if (
		local_operator == null
		or local_operator.mannequin == null
		or local_reload_pending
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
	driver.action_completed.connect(_on_local_reload_animation_completed, CONNECT_ONE_SHOT)
	driver.action_cancelled.connect(_on_local_reload_animation_cancelled, CONNECT_ONE_SHOT)


func _on_local_reload_animation_completed(clip_name: StringName) -> void:
	if not local_reload_pending or "reload" not in String(clip_name).to_lower():
		return
	local_reload_pending = false
	var peer_id := multiplayer.get_unique_id()
	if multiplayer.is_server():
		_server_reload_weapon(peer_id)
	else:
		submit_reload.rpc_id(1)

func _on_local_reload_animation_cancelled(clip_name: StringName) -> void:
	if "reload" in String(clip_name).to_lower():
		local_reload_pending = false
