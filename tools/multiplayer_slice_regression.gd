extends SceneTree

const Protocol := preload("res://scripts/network/socom_network_protocol.gd")
const MovementCommand := preload("res://scripts/network/socom_movement_command.gd")
const MultiplayerScene := preload("res://multiplayer_slice.tscn")
const NetworkOperator := preload("res://scripts/network/socom_network_operator.gd")
const LobbyState := preload("res://scripts/network/socom_lobby_state.gd")
const MapDocument := preload("res://scripts/maps/socom_map_document.gd")
const MatchInvite := preload("res://scripts/network/socom_match_invite.gd")
const ShotAuthority := preload("res://scripts/network/socom_shot_authority.gd")

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var lobby := LobbyState.new()
	var host_entry := lobby.add_player(1, "HOST")
	var guest_entry := lobby.add_player(2, "GUEST")
	_assert(int(host_entry.get("team", -1)) == 0, "host is assigned to Alpha by default")
	_assert(int(guest_entry.get("team", -1)) == 1, "second player is assigned to Bravo by default")
	_assert(not lobby.all_players_ready(), "lobby waits until every connected player greens up")
	_assert(lobby.set_ready(1, true) and lobby.set_ready(2, true), "both players can green up")
	_assert(lobby.all_players_ready(), "all-ready gate opens only with both teams represented")
	lobby.clear_ready_states()
	_assert(not lobby.all_players_ready(), "new matches clear every ready state")

	var command = MovementCommand.new()
	command.simulation_tick = 42
	command.move_axis = Vector2(2.0, -2.0)
	command.aim_yaw = 9.0
	command.jump_pressed = true
	command.peek_axis = 3.0
	var packet := Protocol.movement_to_packet(command)
	var restored = Protocol.packet_to_movement(packet)
	_assert(restored.simulation_tick == 42, "movement tick did not survive serialization")
	_assert(restored.move_axis.length() <= 1.001, "movement packet was not bounded")
	_assert(restored.aim_yaw >= -PI and restored.aim_yaw <= PI, "aim yaw was not wrapped")
	_assert(restored.jump_pressed, "one-shot movement input was lost")
	_assert(absf(restored.peek_axis) <= 1.0, "peek input was not bounded")
	_assert(Protocol.movement_packet_is_sane(packet), "valid movement packet was rejected")
	_assert(
		not Protocol.movement_packet_is_sane({"tick": 1, "move": Vector2(99.0, 0.0), "aim_yaw": 0.0}),
		"unbounded movement packet was accepted"
	)

	var sanitized := Protocol.sanitize_aim_packet({
		"sequence": 7,
		"simulation_tick": 18,
		"yaw": 0.2,
		"pitch": 0.1,
		"reported_muzzle_origin": Vector3(1.0, 2.0, 3.0),
		"direction": Vector3(0.0, 0.0, -7.0),
		"convergence_distance": 12.0,
	})
	_assert(is_equal_approx(Vector3(sanitized.direction).length(), 1.0), "aim direction was not normalized")
	_assert(
		is_equal_approx(float(sanitized.convergence_distance), 12.0),
		"aim convergence distance survives packet sanitization"
	)
	var report_anchor := Vector3(0.0, 1.35, 0.0)
	var convergence_target := Vector3(0.0, 1.48, -12.0)
	var convergence_direction := report_anchor.direction_to(convergence_target)
	var convergence_packet := {
		"sequence": 1,
		"simulation_tick": 10,
		"yaw": wrapf(atan2(-convergence_direction.x, -convergence_direction.z), -PI, PI),
		"pitch": asin(convergence_direction.y),
		"reported_muzzle_origin": report_anchor,
		"direction": convergence_direction,
		"convergence_distance": report_anchor.distance_to(convergence_target),
	}
	var convergence_validation := ShotAuthority.validate_intent(
		convergence_packet,
		report_anchor,
		-1,
		10
	)
	_assert(
		bool(convergence_validation.get("accepted", false)),
		"bounded reticle convergence intent is accepted"
	)
	var shifted_server_muzzle := Vector3(0.32, 1.62, 0.15)
	var resolved_direction := ShotAuthority.resolve_trace_direction(
		convergence_validation,
		report_anchor,
		shifted_server_muzzle
	)
	_assert(
		rad_to_deg(resolved_direction.angle_to(
			shifted_server_muzzle.direction_to(convergence_target)
		)) < 0.01,
		"server muzzle converges on the reticle target despite presentation offset"
	)
	var invalid_convergence := convergence_packet.duplicate(true)
	invalid_convergence["convergence_distance"] = 999.0
	_assert(
		not bool(ShotAuthority.validate_intent(
			invalid_convergence,
			report_anchor,
			-1,
			10
		).get("accepted", false)),
		"unbounded client convergence is rejected"
	)
	var displaced_anchor := convergence_packet.duplicate(true)
	displaced_anchor["reported_muzzle_origin"] = report_anchor + Vector3(5.0, 0.0, 0.0)
	_assert(
		not bool(ShotAuthority.validate_intent(
			displaced_anchor,
			report_anchor,
			-1,
			10
		).get("accepted", false)),
		"client cannot displace its reported body anchor away from server authority"
	)
	var representative_entities: Dictionary = {}
	var representative_scores: Dictionary = {}
	for peer_id in range(1, 17):
		representative_entities[peer_id] = {
			"position": Vector3(float(peer_id), 0.05, -13.0),
			"yaw": 0.0,
			"velocity": Vector3.ZERO,
			"posture": 0,
			"health": 100.0,
			"alive": true,
		}
		representative_scores[peer_id] = 0
	var snapshot_chunks := Protocol.chunk_snapshot_entities(representative_entities, 4)
	_assert(snapshot_chunks.size() == 4, "16-player state is split into four MTU-safe chunks")
	var chunked_entity_count := 0
	for chunk_index in snapshot_chunks.size():
		var chunk: Dictionary = snapshot_chunks[chunk_index]
		chunked_entity_count += chunk.size()
		_assert(chunk.size() <= 4, "snapshot chunks never exceed the entity packet limit")
		var representative_packet := {
			"timestamp_ms": 1000,
			"tick": 60,
			"chunk_index": chunk_index,
			"chunk_count": snapshot_chunks.size(),
			"entities": chunk,
		}
		var encoded_payload := var_to_bytes([
			representative_packet,
			representative_scores if chunk_index == 0 else {},
		])
		_assert(encoded_payload.size() < 1200, "snapshot chunk keeps payload headroom below ENet MTU")
	_assert(chunked_entity_count == 16, "snapshot chunking preserves every operator")

	var slice := MultiplayerScene.instantiate()
	root.add_child(slice)
	await process_frame
	_assert(slice != null, "multiplayer scene did not instantiate")
	_assert(slice.has_method("host_match"), "host entry point missing")
	_assert(slice.has_method("join_match"), "join entry point missing")
	var queued_operator = NetworkOperator.new()
	queued_operator.visual_runtime_enabled = false
	slice.add_child(queued_operator)
	slice.operators[501] = queued_operator
	slice.last_enqueued_shot_sequence[501] = -1
	slice.pending_shot_packets[501] = []
	_assert(
		bool(slice.call("_queue_server_shot", 501, {"sequence": 1})),
		"server accepts the first sequenced client shot into its cadence queue"
	)
	_assert(
		not bool(slice.call("_queue_server_shot", 501, {"sequence": 1})),
		"server shot queue rejects replayed sequences before simulation"
	)
	for sequence in range(2, 9):
		slice.call("_queue_server_shot", 501, {"sequence": sequence})
	_assert(
		not bool(slice.call("_queue_server_shot", 501, {"sequence": 9})),
		"server shot queue is bounded against packet floods"
	)
	slice.operators.erase(501)
	slice.pending_shot_packets.erase(501)
	slice.last_enqueued_shot_sequence.erase(501)
	queued_operator.queue_free()
	_assert(slice.spawn_points.size() == 16, "8v8 spawn contract missing")
	_assert(slice.call("_spawn_for_team", 0, 0).z > 0.0, "team 0 spawn side is invalid")
	_assert(slice.call("_spawn_for_team", 1, 0).z < 0.0, "team 1 spawn side is invalid")
	_assert(slice.menu_panel != null, "host/join test UI missing")
	_assert(not slice.equipped_config.is_empty(), "multiplayer did not load the equipped Gunsmith profile")
	_assert(
		is_equal_approx(float(slice.remote_interpolation_delay_seconds), 0.130),
		"competitive rules preserve the shared 130 ms remote render window"
	)
	slice.peer_transport_one_way_ms[77] = 120.0
	_assert(
		is_equal_approx(float(slice.call("_transport_compensation_seconds", 77)), 0.080),
		"real transport compensation is capped without removing the shared lead window"
	)
	_assert(slice.find_child("MultiplayerLobbyPanel", true, false) != null, "multiplayer exposes a lobby roster")
	_assert(slice.find_child("ChooseAlphaTeamButton", true, false) != null, "players can choose Alpha")
	_assert(slice.find_child("ChooseBravoTeamButton", true, false) != null, "players can choose Bravo")
	_assert(slice.find_child("GreenUpReadyButton", true, false) != null, "players have a green-ready button")
	_assert(slice.find_child("HostInviteCodePanel", true, false) != null, "host lobby exposes a squad invite code")
	_assert(slice.find_child("CopyHostInviteCode", true, false) is Button, "host can copy the invite code")
	slice.multiplayer_hud.show_host_invite(14141)
	var invite_edit := slice.find_child("HostInviteCode", true, false) as LineEdit
	var decoded_invite: Dictionary = MatchInvite.decode(invite_edit.text if invite_edit != null else "")
	_assert(bool(decoded_invite.get("ok", false)) and int(decoded_invite.get("port", 0)) == 14141, "visible host code resolves to the hosted UDP port")
	_assert(slice.find_child("MultiplayerRoundClock", true, false) != null, "match HUD exposes the authored round timer")
	_assert(slice.find_child("DemolitionObjectiveStatus", true, false) != null, "match HUD exposes the bomb objective")
	var authored_map := MapDocument.new_document("Multiplayer Regression Map")
	slice.call("_apply_multiplayer_map", authored_map)
	_assert(String(slice.active_map_document.get("name", "")) == "Multiplayer Regression Map", "multiplayer consumes the host's saved map document")
	_assert(slice.call("_spawn_for_team", 0, 0).is_equal_approx(Vector3(-7.0, 0.05, 7.0)), "Alpha uses the authored map spawn")
	_assert(slice.call("_spawn_for_team", 1, 0).is_equal_approx(Vector3(7.0, 0.05, -7.0)), "Bravo uses the authored map spawn")
	_assert(int(slice.round_rules.get("time_limit_seconds", 0)) == 300, "multiplayer consumes the authored round time")
	_assert(not slice.bomb_pickup_positions.is_empty(), "multiplayer consumes the authored bomb pickup")
	_assert(not (slice.bomb_site_positions.get(0, []) as Array).is_empty(), "multiplayer consumes the Alpha bomb target")
	_assert(not (slice.bomb_site_positions.get(1, []) as Array).is_empty(), "multiplayer consumes the Bravo bomb target")
	_assert(slice.bomb_visual != null, "multiplayer builds the visible demolition bomb asset")
	var alpha_objective_operator := NetworkOperator.new()
	alpha_objective_operator.name = "AlphaObjectiveOperator"
	slice.add_child(alpha_objective_operator)
	alpha_objective_operator.configure_identity(101, 0)
	var bravo_objective_operator := NetworkOperator.new()
	bravo_objective_operator.name = "BravoObjectiveOperator"
	slice.add_child(bravo_objective_operator)
	bravo_objective_operator.configure_identity(102, 1)
	_assert(
		alpha_objective_operator.team_visual_color != bravo_objective_operator.team_visual_color,
		"Alpha and Bravo operators use distinct character colors"
	)
	slice.operators[101] = alpha_objective_operator
	slice.operators[102] = bravo_objective_operator
	var rewind_now_ms := float(Time.get_ticks_msec())
	bravo_objective_operator.global_position = Vector3(10.0, 0.0, 0.0)
	slice.operator_state_history[102] = [
		{"time_ms": rewind_now_ms - 80.0, "position": Vector3(2.0, 0.0, 0.0), "yaw": 0.0},
		{"time_ms": rewind_now_ms, "position": Vector3(10.0, 0.0, 0.0), "yaw": 0.0},
	]
	slice.peer_transport_one_way_ms[101] = 40.0
	var rewind_restore: Array[Dictionary] = slice.call("_begin_transport_rewind", 101)
	_assert(
		bravo_objective_operator.global_position.x > 4.0
		and bravo_objective_operator.global_position.x < 8.0,
		"server rewinds enemies only by measured packet transit"
	)
	slice.call("_restore_transport_rewind", rewind_restore)
	_assert(
		bravo_objective_operator.global_position.is_equal_approx(Vector3(10.0, 0.0, 0.0)),
		"transport compensation restores the current authoritative position after validation"
	)
	slice.session_active = true
	slice.round_active = true
	slice.call("_reset_demolition_objective")
	alpha_objective_operator.global_position = slice.bomb_world_position
	slice.objective_interact_held[101] = true
	slice.call("_advance_demolition_objective", 0.1)
	_assert(slice.bomb_carrier_peer_id == 101, "server validates bomb pickup from operator position")
	_assert(
		slice.status_label != null
			and "BOMB ACQUIRED" in slice.status_label.text
			and "ALPHA" not in slice.status_label.text
			and "SEAL" not in slice.status_label.text,
		"bomb pickup toast confirms the state without revealing the carrier or team"
	)
	var alpha_bomb_pack := alpha_objective_operator.find_child("WearableBackpack", true, false) as Node3D
	var bravo_bomb_pack := bravo_objective_operator.find_child("WearableBackpack", true, false) as Node3D
	_assert(
		alpha_bomb_pack != null and alpha_bomb_pack.visible
			and bravo_bomb_pack != null and not bravo_bomb_pack.visible,
		"replicated bomb ownership shows the backpack only on the current carrier"
	)
	alpha_objective_operator.global_position = Vector3((slice.bomb_site_positions.get(1, []) as Array)[0])
	slice.call("_advance_demolition_objective", float(slice.mission_rules.get("plant_time_seconds", 5.0)) * 0.5)
	_assert(slice.bomb_plant_progress > 0.0 and not slice.bomb_planted, "planting advances only while the carrier holds interact at the enemy target")
	slice.objective_interact_held[101] = false
	slice.call("_advance_demolition_objective", 0.1)
	_assert(is_zero_approx(slice.bomb_plant_progress), "releasing interact cancels an incomplete plant")
	slice.objective_interact_held[101] = true
	slice.call("_drop_bomb_from_peer", 101)
	_assert(
		slice.bomb_carrier_peer_id == 0
		and slice.bomb_world_position.is_equal_approx(alpha_objective_operator.global_position),
		"carrier loss drops the bomb at the last authoritative operator position"
	)
	slice.call("_advance_demolition_objective", 0.1)
	_assert(slice.bomb_carrier_peer_id == 101, "a dropped bomb can be recovered through the same validated pickup rule")
	alpha_objective_operator.global_position = Vector3((slice.bomb_site_positions.get(1, []) as Array)[0])
	slice.call("_advance_demolition_objective", float(slice.mission_rules.get("plant_time_seconds", 5.0)) + 0.01)
	_assert(slice.bomb_planted and slice.bomb_planting_team == 0, "Alpha can plant at Bravo's authored target")
	_assert(alpha_bomb_pack != null and not alpha_bomb_pack.visible, "planting removes the bomb backpack from the carrier")
	_assert(
		slice.bomb_visual != null and StringName(slice.bomb_visual.get("bomb_state")) == &"PLANTED",
		"replicated planted state reaches the visible bomb asset"
	)
	alpha_objective_operator.global_position = slice.bomb_world_position
	slice.objective_interact_held[101] = true
	slice.call("_advance_demolition_objective", 0.5)
	_assert(
		slice.bomb_defusing_peer_id == 0 and is_zero_approx(slice.bomb_defuse_progress),
		"the planting team cannot defuse its own bomb"
	)
	alpha_objective_operator.alive = false
	slice.call("_on_operator_eliminated", 101, 102)
	_assert(
		slice.round_active and slice.bomb_planted,
		"eliminating the attackers after plant leaves the live bomb for defenders to defuse"
	)
	alpha_objective_operator.alive = true
	slice.objective_interact_held[101] = false
	bravo_objective_operator.global_position = slice.bomb_world_position
	slice.objective_interact_held[102] = true
	slice.call("_advance_demolition_objective", float(slice.mission_rules.get("defuse_time_seconds", 5.0)) * 0.5)
	_assert(slice.bomb_defusing_peer_id == 102 and slice.bomb_defuse_progress > 0.0, "a living defender can begin a server-owned defuse")
	slice.objective_interact_held[102] = false
	slice.call("_advance_demolition_objective", 0.1)
	_assert(slice.bomb_defusing_peer_id == 0 and is_zero_approx(slice.bomb_defuse_progress), "moving away or releasing interact cancels an incomplete defuse")
	slice.objective_interact_held[102] = true
	slice.call("_advance_demolition_objective", float(slice.mission_rules.get("defuse_time_seconds", 5.0)) + 0.01)
	_assert(
		not slice.round_active
		and not slice.bomb_planted
		and int(slice.team_round_wins.get(1, 0)) == 1,
		"a living defender holding F at the planted bomb completes a server-owned defuse"
	)
	var completed_objective_snapshot: Dictionary = slice.call("_objective_state_snapshot")
	_assert(
		int(completed_objective_snapshot.get("carrier_peer_id", -1)) == 0
		and not bool(completed_objective_snapshot.get("planted", true)),
		"late-join objective snapshots expose the same completed authoritative state"
	)

	# Start a clean objective state to retain the detonation win regression.
	slice.session_active = true
	slice.round_resolution_pending = false
	slice.round_active = true
	slice.team_round_wins = {0: 0, 1: 0}
	slice.call("_reset_demolition_objective")
	alpha_objective_operator.global_position = slice.bomb_world_position
	slice.objective_interact_held[101] = true
	slice.objective_interact_held[102] = false
	slice.call("_advance_demolition_objective", 0.1)
	_assert(slice.bomb_carrier_peer_id == 101, "a new round resets the bomb for another validated pickup")
	alpha_objective_operator.global_position = Vector3((slice.bomb_site_positions.get(1, []) as Array)[0])
	slice.call("_advance_demolition_objective", float(slice.mission_rules.get("plant_time_seconds", 5.0)) + 0.01)
	_assert(slice.bomb_planted and slice.bomb_planting_team == 0, "a new round permits another validated plant")
	slice.bomb_fuse_remaining = 0.01
	slice.call("_advance_demolition_objective", 0.02)
	_assert(not slice.round_active and int(slice.team_round_wins.get(0, 0)) == 1, "bomb detonation awards the planting team one round")
	slice.operators.erase(101)
	slice.operators.erase(102)
	alpha_objective_operator.queue_free()
	bravo_objective_operator.queue_free()

	var operator = NetworkOperator.new()
	operator.name = "RegressionNetworkOperator"
	root.add_child(operator)
	operator.configure_identity(9, 1)
	await process_frame
	await process_frame
	await physics_frame
	_assert(operator.mannequin != null, "network operator did not build canonical mannequin")
	_assert(operator.hurtbox_rig != null, "network operator did not bind animated hurtboxes")
	if operator.hurtbox_rig != null:
		_assert(
			operator.hurtbox_rig.get_region_area(&"RIGHT_UPPER_ARM") != null,
			"network operator is missing an anatomical upper-arm region"
		)
	operator.configure_network_presentation(false, false)
	_assert(
		not operator.mannequin.legacy_procedural_updates_enabled,
		"remote operators disable the hidden legacy mannequin solver"
	)
	_assert(
		operator.hurtbox_rig != null and not operator.hurtbox_rig.is_physics_processing(),
		"client replicas disable unused hurtbox physics"
	)
	operator.configure_network_presentation(true, true)
	_assert(
		operator.mannequin.legacy_procedural_updates_enabled,
		"the local visual owner keeps camera-marker mannequin updates"
	)
	_assert(
		operator.hurtbox_rig != null and operator.hurtbox_rig.is_physics_processing(),
		"the server keeps authoritative animated hurtboxes active"
	)
	var lightweight_operator = NetworkOperator.new()
	lightweight_operator.name = "RegressionLightweightNetworkOperator"
	lightweight_operator.visual_runtime_enabled = false
	root.add_child(lightweight_operator)
	await process_frame
	_assert(
		lightweight_operator.mannequin == null
		and lightweight_operator.hurtbox_rig == null,
		"network soak bots can skip client-only presentation without creating rigs"
	)
	_assert(
		lightweight_operator.get_node_or_null("CollisionShape3D") != null,
		"network soak bots retain movement and lifecycle collision"
	)
	lightweight_operator.queue_free()
	var health_before: float = operator.current_health
	var damage := operator.take_bullet_damage_region(
		10.0,
		&"TORSO",
		operator.global_position + Vector3.UP,
		Vector3.BACK,
		Vector3(0.0, 1.0, 4.0),
		2
	)
	_assert(bool(damage.get("accepted", false)), "server-side network damage was rejected")
	_assert(operator.current_health < health_before, "server-side damage did not reduce health")
	var health_before_head: float = float(operator.current_health)
	var custom_headshot := operator.take_bullet_damage_region(
		10.0,
		&"HEAD",
		operator.global_position + Vector3.UP,
		Vector3.BACK,
		Vector3(0.0, 1.0, 4.0),
		2,
		2.25
	)
	_assert(
		is_equal_approx(float(custom_headshot.get("damage", 0.0)), 22.5)
		and is_equal_approx(operator.current_health, health_before_head - 22.5),
		"server damage uses the firing gun's authored headshot multiplier"
	)
	slice.call("_attach_local_camera", operator)
	var feedback_camera = slice.local_camera
	var aim_before := Vector2(feedback_camera.aim_yaw, feedback_camera.aim_pitch)
	slice.receive_damage_feedback("TORSO", 10.0, false)
	_assert(
		int(feedback_camera.get_head_impact_debug_state().get("count", -1)) == 0,
		"non-head damage does not trigger the violent head-impact jolt"
	)
	slice.receive_damage_feedback("HEAD", 22.5, false)
	feedback_camera.call("_begin_camera_presentation_frame")
	feedback_camera.call("_apply_head_impact_presentation", 1.0 / 60.0)
	var feedback_state: Dictionary = feedback_camera.get_head_impact_debug_state()
	_assert(
		int(feedback_state.get("count", 0)) == 1
		and bool(feedback_state.get("active", false))
		and Vector3(feedback_state.get("camera_rotation", Vector3.ZERO)).length() > 0.001,
		"server-confirmed head damage triggers one visible victim-camera jolt"
	)
	_assert(
		Vector2(feedback_camera.aim_yaw, feedback_camera.aim_pitch).is_equal_approx(aim_before),
		"head-impact presentation never redirects authoritative aim"
	)

	if failures.is_empty():
		print("MULTIPLAYER_SLICE_REGRESSION PASS")
	else:
		for failure in failures:
			push_error("MULTIPLAYER_SLICE_REGRESSION " + failure)
		print("MULTIPLAYER_SLICE_REGRESSION FAIL count=%d" % failures.size())
	quit(0 if failures.is_empty() else 1)


func _assert(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
