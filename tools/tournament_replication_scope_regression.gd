extends SceneTree

const TournamentSession := preload("res://scripts/network/socom_tournament_session.gd")
const MultiplayerScene := preload("res://multiplayer_slice.tscn")
const ServerBackend := preload("res://scripts/server/socom_server_backend.gd")
const TOURNAMENT_SETTING := "socom/session/tournament_mode"


class OperatorStub extends RefCounted:
	var alive := true
	var global_position := Vector3.ZERO
	var rotation := Vector3.ZERO
	var velocity := Vector3.ZERO
	var posture := 0
	var current_health := 100.0
	var consumed_input_tick := -1
	var respawn_revision := 0
	var motion_state := 0
	var network_aim_angles := Vector2.ZERO
	var desired_movement_direction := Vector3.ZERO
	var movement_input_strength := 0.0
	var peek_amount := 0.0


func _initialize() -> void:
	var session = TournamentSession.new()
	var pairs: Array[int] = []
	var members := {}
	for pair_id in 16:
		pairs.append(pair_id)
		members[pair_id] = [
			{"peer_id": pair_id * 2 + 1},
			{"peer_id": pair_id * 2 + 2},
		]
	var started: Dictionary = session.start(pairs, members)
	assert(bool(started.get("active", false)), "Tournament roster needs sixteen valid duos")
	assert(session.arena_for_peer(1) == 0, "Opening peer belongs to arena zero")
	assert(session.arena_for_peer(4) == 0, "Opening opponent belongs to arena zero")
	assert(session.arena_for_peer(5) == 1, "Next matchup belongs to the next arena")
	assert(not session.can_damage_between(1, 5), "Cross-arena damage must be denied")
	assert(session.can_damage_between(1, 4), "Same-arena damage must remain allowed")

	var scoped_slice: Node = MultiplayerScene.instantiate()
	scoped_slice.tournament_mode_enabled = true
	scoped_slice.tournament_session = session
	for peer_id in 32:
		scoped_slice.operators[peer_id + 1] = OperatorStub.new()
	var arena_zero_snapshot: Dictionary = scoped_slice.call("_tournament_snapshot_for_arena", 0)
	assert(arena_zero_snapshot.size() == 4, "An arena snapshot must contain exactly its four players")
	assert(arena_zero_snapshot.has(1) and arena_zero_snapshot.has(4), "Arena snapshot must retain local teammates and opponents")
	assert(not arena_zero_snapshot.has(5), "Arena snapshot must not leak the next arena")
	assert(bool(scoped_slice.call("is_peer_gameplay_action_allowed", 1)), "Active arena player input must remain allowed")
	scoped_slice.operators[1].alive = false
	assert(not bool(scoped_slice.call("is_peer_gameplay_action_allowed", 1)), "Eliminated player input must be denied")
	scoped_slice.free()

	ProjectSettings.set_setting(TOURNAMENT_SETTING, true)
	var slice: Node = MultiplayerScene.instantiate()
	root.add_child(slice)
	await process_frame
	assert(
		slice.call("_dedicated_server_advertised_capacity") == 32,
		"Tournament dedicated listing must advertise thirty-two slots"
	)
	slice.queue_free()

	assert(
		ServerBackend.sanitize_advertised_capacity(32) == 32,
		"Dedicated registration must retain the tournament's thirty-two slots"
	)
	assert(
		ServerBackend.sanitize_advertised_capacity(99) == 32,
		"Dedicated registration must not exceed the transport's thirty-two-player limit"
	)
	ProjectSettings.set_setting(TOURNAMENT_SETTING, false)
	print("TOURNAMENT_REPLICATION_SCOPE_REGRESSION PASS")
	quit(0)
