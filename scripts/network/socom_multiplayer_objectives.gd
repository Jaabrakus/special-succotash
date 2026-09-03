extends "res://scripts/network/socom_multiplayer_buy_phase.gd"

func _set_local_objective_interaction(held: bool) -> void:
	var peer_id := multiplayer.get_unique_id()
	if multiplayer.is_server():
		objective_interact_held[peer_id] = held
	else:
		submit_objective_interaction.rpc_id(1, held)


func _advance_demolition_objective(delta: float) -> void:
	if (
		not session_active
		or not round_active
		or String(mission_rules.get("primary_mode", "demolition")) != "demolition"
		or bomb_pickup_positions.is_empty()
	):
		return
	objective_broadcast_accumulator += delta
	if bomb_planted:
		bomb_fuse_remaining = maxf(0.0, bomb_fuse_remaining - delta)
		if bomb_fuse_remaining <= 0.0:
			bomb_defusing_peer_id = 0
			bomb_defuse_progress = 0.0
			_broadcast_objective_state()
			_server_finish_round(bomb_planting_team, "BOMB DETONATED")
			return
		_advance_bomb_defuse(delta)
		if not bomb_planted or not round_active:
			return
		if objective_broadcast_accumulator >= 0.25:
			objective_broadcast_accumulator = 0.0
			_broadcast_objective_state()
		return
	if bomb_carrier_peer_id == 0:
		for raw_id: Variant in objective_interact_held.keys():
			if not bool(objective_interact_held.get(raw_id, false)):
				continue
			var candidate: Variant = operators.get(int(raw_id))
			if candidate == null or not candidate.alive:
				continue
			if candidate.global_position.distance_to(bomb_world_position) <= 1.6:
				bomb_carrier_peer_id = int(raw_id)
				bomb_planting_team = candidate.team_id
				bomb_plant_progress = 0.0
				_broadcast_objective_toast("BOMB ACQUIRED")
				_broadcast_objective_state()
				break
		return
	var carrier: Variant = operators.get(bomb_carrier_peer_id)
	if carrier == null or not carrier.alive:
		_drop_bomb_from_peer(bomb_carrier_peer_id)
		return
	bomb_world_position = carrier.global_position
	var target_team: int = 1 - int(carrier.team_id)
	var near_target := false
	for raw_target: Variant in bomb_site_positions.get(target_team, []):
		if carrier.global_position.distance_to(Vector3(raw_target)) <= 1.8:
			near_target = true
			break
	if near_target and bool(objective_interact_held.get(bomb_carrier_peer_id, false)):
		bomb_plant_progress += delta
		var plant_seconds := float(mission_rules.get("plant_time_seconds", 5.0))
		if bomb_plant_progress >= plant_seconds:
			bomb_planted = true
			bomb_planting_team = carrier.team_id
			bomb_carrier_peer_id = 0
			bomb_plant_progress = plant_seconds
			bomb_fuse_remaining = float(mission_rules.get("bomb_fuse_seconds", 35))
			bomb_defusing_peer_id = 0
			bomb_defuse_progress = 0.0
			_broadcast_objective_toast("BOMB PLANTED")
			_broadcast_objective_state()
			return
	else:
		bomb_plant_progress = 0.0
	if objective_broadcast_accumulator >= 0.25:
		objective_broadcast_accumulator = 0.0
		_broadcast_objective_state()


func _advance_bomb_defuse(delta: float) -> void:
	if not bomb_planted or bomb_planting_team not in [0, 1]:
		bomb_defusing_peer_id = 0
		bomb_defuse_progress = 0.0
		return
	var defending_team := 1 - bomb_planting_team
	var eligible_ids: Array[int] = []
	for raw_id: Variant in objective_interact_held.keys():
		var peer_id := int(raw_id)
		if not bool(objective_interact_held.get(raw_id, false)):
			continue
		var candidate: Variant = operators.get(peer_id)
		if (
			candidate != null
			and candidate.alive
			and candidate.team_id == defending_team
			and candidate.global_position.distance_to(bomb_world_position) <= 1.8
		):
			eligible_ids.append(peer_id)
	eligible_ids.sort()
	if eligible_ids.is_empty():
		bomb_defusing_peer_id = 0
		bomb_defuse_progress = 0.0
		return
	var active_defuser := eligible_ids[0]
	if bomb_defusing_peer_id != active_defuser:
		bomb_defusing_peer_id = active_defuser
		bomb_defuse_progress = 0.0
	bomb_defuse_progress += delta
	var defuse_seconds := maxf(float(mission_rules.get("defuse_time_seconds", 5.0)), 0.1)
	if bomb_defuse_progress < defuse_seconds:
		return
	bomb_planted = false
	bomb_fuse_remaining = 0.0
	bomb_defuse_progress = defuse_seconds
	_broadcast_objective_state()
	_server_finish_round(defending_team, "BOMB DEFUSED")


func _reset_demolition_objective() -> void:
	bomb_carrier_peer_id = 0
	bomb_planted = false
	bomb_planting_team = -1
	bomb_plant_progress = 0.0
	bomb_fuse_remaining = 0.0
	bomb_defusing_peer_id = 0
	bomb_defuse_progress = 0.0
	bomb_world_position = bomb_pickup_positions[0] if not bomb_pickup_positions.is_empty() else Vector3.ZERO
	objective_interact_held.clear()
	objective_broadcast_accumulator = 0.0
	_broadcast_objective_state()


func _drop_bomb_from_peer(peer_id: int) -> void:
	if bomb_carrier_peer_id != peer_id:
		return
	var carrier: Variant = operators.get(peer_id)
	if carrier != null:
		bomb_world_position = carrier.global_position
	bomb_carrier_peer_id = 0
	bomb_plant_progress = 0.0
	bomb_defusing_peer_id = 0
	bomb_defuse_progress = 0.0
	_broadcast_objective_toast("BOMB DROPPED")
	_broadcast_objective_state()


func _broadcast_objective_toast(message: String) -> void:
	_set_status(message)
	if multiplayer.is_server() and multiplayer.multiplayer_peer != null:
		receive_match_event.rpc(message)


func _broadcast_objective_state() -> void:
	var state := _objective_state_snapshot()
	receive_objective_state(state)
	if multiplayer.multiplayer_peer != null and multiplayer.is_server():
		receive_objective_state.rpc(state)


func _objective_state_snapshot() -> Dictionary:
	return {
		"carrier_peer_id": bomb_carrier_peer_id,
		"world_position": bomb_world_position,
		"planted": bomb_planted,
		"planting_team": bomb_planting_team,
		"plant_progress": bomb_plant_progress,
		"fuse_remaining": bomb_fuse_remaining,
		"defusing_peer_id": bomb_defusing_peer_id,
		"defuse_progress": bomb_defuse_progress,
	}


func _server_reload_weapon(peer_id: int) -> void:
	if not multiplayer.is_server() or not operators.has(peer_id):
		return
	var capacity := int(equipped_config.get("ballistics", {}).get("magazine_capacity", 30))
	var magazine := int(server_magazine_ammo.get(peer_id, capacity))
	var reserve := int(server_reserve_ammo.get(peer_id, 0))
	var transferred := mini(maxi(0, capacity - magazine), reserve)
	server_magazine_ammo[peer_id] = magazine + transferred
	server_reserve_ammo[peer_id] = reserve - transferred
	_send_ammo_state(peer_id)


func _reset_ammo_for_peer(peer_id: int) -> void:
	var values: Dictionary = equipped_config.get("ballistics", {})
	server_magazine_ammo[peer_id] = int(values.get("magazine_capacity", 30))
	server_reserve_ammo[peer_id] = int(values.get("reserve_ammo", 90))
	_send_ammo_state(peer_id)


func _send_ammo_state(peer_id: int) -> void:
	var magazine := int(server_magazine_ammo.get(peer_id, 0))
	var reserve := int(server_reserve_ammo.get(peer_id, 0))
	if peer_id == multiplayer.get_unique_id():
		receive_ammo_state(magazine, reserve)
	else:
		receive_ammo_state.rpc_id(peer_id, magazine, reserve)


func _spawn_for_peer(peer_id: int) -> Vector3:
	return spawn_points[(peer_id - 1) % spawn_points.size()]


func _spawn_for_team(team: int, member_index: int) -> Vector3:
	var authored: Array = team_spawn_points.get(team, [])
	if not authored.is_empty():
		var base := Vector3(authored[member_index % authored.size()])
		var duplicate_row := floori(float(member_index) / float(authored.size()))
		if duplicate_row > 0:
			var side := -1.0 if duplicate_row % 2 == 0 else 1.0
			var distance := float((duplicate_row + 1) / 2) * 1.25
			base += Vector3(side * distance, 0.0, 0.0)
		return base
	var team_offset := 0 if team == 0 else 8
	return spawn_points[team_offset + (member_index % 8)]


func _team_member_count(team: int) -> int:
	var count := 0
	for raw_id in operators:
		var operator: Variant = operators[raw_id]
		if operator != null and operator.team_id == team:
			count += 1
	return count
