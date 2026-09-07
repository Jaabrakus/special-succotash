class_name MultiplayerControlledDamageProbe
extends RefCounted

## Focused full-lobby damage phase used by the multiplayer lifecycle probe.
## Keeps lane setup, client convergence shots, and health invariants out of the
## lifecycle/orchestration script so either test can evolve independently.

const SHOTS_PER_TARGET := 12 # Bounded attempts: round-selected guns do not all kill in three hits.
const HEIGHT := 30.0
const LANE_SPACING := 3.0
const SHOOTER_Z := 1.75
const TARGET_Z := -1.75
# Canonical standing torso center measured from the server's animated rig.
const TARGET_HEIGHT := 1.48

var tree: SceneTree
var slice: Node
var client_index := 0


func configure(scene_tree: SceneTree, multiplayer_slice: Node, probe_client_index: int) -> void:
	tree = scene_tree
	slice = multiplayer_slice
	client_index = probe_client_index


func prepare_host() -> void:
	var pair_count := mini(_team_peer_ids(0).size(), _team_peer_ids(1).size())
	for team in [0, 1]:
		var peer_ids := _team_peer_ids(team)
		for index in peer_ids.size():
			var operator = slice.operators.get(peer_ids[index])
			if operator == null:
				continue
			operator.global_position = _lane_position(index, pair_count, team)
			operator.rotation.y = 0.0
			operator.velocity = Vector3.ZERO
			operator.set_physics_process(false)
			if operator.hurtbox_rig != null:
				operator.hurtbox_rig.force_pose_update()
	print("MULTIPLAYER_LIFECYCLE HOST_CONTROLLED_HITS_READY pairs=%d" % pair_count)


func run_client(cycle: int, peer_id: int) -> Dictionary:
	if not await _wait_until(
		func() -> bool:
			var operator = slice.operators.get(peer_id)
			if operator == null or operator.global_position.distance_to(
				_expected_position(peer_id)
			) > 0.15:
				return false
			if operator.team_id != 0:
				return true
			var target = _paired_enemy(peer_id)
			return (
				target != null
				and target.global_position.distance_to(
					_expected_position(int(target.network_peer_id))
				) <= 0.15
			),
		5.0
	):
		return {"ok": false, "reason": "client %d never received the controlled-hit lane" % client_index}
	var shooter = slice.operators.get(peer_id)
	if shooter == null or shooter.team_id != 0:
		return {"ok": true}
	var target = _paired_enemy(peer_id)
	if target == null or shooter.mannequin == null:
		return {"ok": false, "reason": "client %d lacks its controlled-hit presentation path" % client_index}
	# Leave more than the bounded rewind window after the teleport so history
	# and all client snapshots agree on the controlled lane.
	await tree.create_timer(0.35).timeout
	for shot_index in SHOTS_PER_TARGET:
		if not target.alive: break
		var report_anchor := _expected_position(peer_id) + Vector3.UP * 1.35
		var target_point := (
			_expected_position(int(target.network_peer_id)) + Vector3.UP * TARGET_HEIGHT
		)
		slice.rpc_id(
			1,
			"submit_shot",
			_directed_packet(
				cycle * 1000 + 100 + shot_index,
				report_anchor,
				target_point
			)
		)
		await tree.create_timer(0.50).timeout
	print(
		"MULTIPLAYER_LIFECYCLE CLIENT_CONTROLLED_HITS_SENT index=%d cycle=%d target=%d"
		% [client_index, cycle, int(target.network_peer_id)]
	)
	return {"ok": true}


func fire_host(cycle: int) -> void:
	await tree.create_timer(0.35).timeout
	var shooter = slice.operators.get(1)
	var target = _paired_enemy(1)
	if shooter == null or target == null or shooter.mannequin == null:
		return
	for shot_index in SHOTS_PER_TARGET:
		if not target.alive: break
		var muzzle: Vector3 = shooter.mannequin.get_active_muzzle_position()
		var target_point: Vector3 = target.global_position + Vector3.UP * TARGET_HEIGHT
		var torso_area: Area3D = (
			target.hurtbox_rig.get_region_area(&"TORSO")
			if target.hurtbox_rig != null
			else null
		)
		if torso_area != null:
			target_point = torso_area.global_position
		var report_anchor: Vector3 = shooter.global_position + Vector3.UP * 1.35
		print(
			"MULTIPLAYER_LIFECYCLE HOST_CONTROLLED_SHOT index=%d muzzle=%s target=%s"
			% [shot_index, muzzle, target_point]
		)
		slice.call(
			"_server_process_shot",
			1,
			_directed_packet(
				cycle * 1000 + 100 + shot_index,
				report_anchor,
				target_point
			)
		)
		print(
			"MULTIPLAYER_LIFECYCLE HOST_CONTROLLED_RESULT index=%d hp=%.1f reject=%s"
			% [
				shot_index,
				target.current_health,
				String(slice.last_rejected_shot_reason.get(1, "")),
			]
		)
		await tree.create_timer(0.50).timeout


func targets_eliminated() -> bool:
	var targets := _team_peer_ids(1)
	if targets.is_empty():
		return false
	for peer_id in targets:
		var target = slice.operators.get(peer_id)
		if target == null or target.alive or target.current_health > 0.0:
			return false
	return true


func shooters_survived() -> bool:
	for peer_id in _team_peer_ids(0):
		var shooter = slice.operators.get(peer_id)
		if shooter == null or not shooter.alive or shooter.current_health < shooter.max_health:
			return false
	return true


func target_count() -> int:
	return _team_peer_ids(1).size()


func diagnostic() -> String:
	var entries: Array[String] = []
	for peer_id in _team_peer_ids(1):
		var target = slice.operators.get(peer_id)
		entries.append(
			"%d:hp=%.1f alive=%s" % [peer_id, target.current_health, target.alive]
			if target != null
			else "%d:missing" % peer_id
		)
	return ", ".join(entries)


func _directed_packet(sequence: int, report_anchor: Vector3, target_point: Vector3) -> Dictionary:
	var direction := report_anchor.direction_to(target_point)
	return {
		"sequence": sequence,
		"simulation_tick": Engine.get_physics_frames(),
		"yaw": wrapf(atan2(-direction.x, -direction.z), -PI, PI),
		"pitch": asin(clampf(direction.y, -1.0, 1.0)),
		"reported_muzzle_origin": report_anchor,
		"direction": direction,
		"convergence_distance": report_anchor.distance_to(target_point),
	}


func _team_peer_ids(team: int) -> Array[int]:
	var result: Array[int] = []
	for raw_id in slice.operators:
		var operator = slice.operators[raw_id]
		if operator != null and int(operator.team_id) == team:
			result.append(int(raw_id))
	result.sort()
	return result


func _paired_enemy(shooter_peer_id: int):
	var shooters := _team_peer_ids(0)
	var targets := _team_peer_ids(1)
	var pair_index := shooters.find(shooter_peer_id)
	if pair_index < 0 or pair_index >= targets.size():
		return null
	return slice.operators.get(targets[pair_index])


func _expected_position(peer_id: int) -> Vector3:
	var operator = slice.operators.get(peer_id)
	if operator == null:
		return Vector3.INF
	var team := int(operator.team_id)
	var team_ids := _team_peer_ids(team)
	var pair_count := mini(_team_peer_ids(0).size(), _team_peer_ids(1).size())
	var index := team_ids.find(peer_id)
	return _lane_position(index, pair_count, team) if index >= 0 else Vector3.INF


func _lane_position(index: int, pair_count: int, team: int) -> Vector3:
	var centered_index := float(index) - float(maxi(0, pair_count - 1)) * 0.5
	return Vector3(
		centered_index * LANE_SPACING,
		HEIGHT,
		SHOOTER_Z if team == 0 else TARGET_Z
	)


func _wait_until(predicate: Callable, timeout_seconds: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout_seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if bool(predicate.call()):
			return true
		await tree.create_timer(0.05).timeout
	return bool(predicate.call())
