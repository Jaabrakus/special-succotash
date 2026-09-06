extends SceneTree

const Countdown := preload("res://scripts/network/socom_lobby_countdown_policy.gd")
const Encoder := preload("res://scripts/network/socom_snapshot_encoder.gd")
const Plan := preload("res://scripts/network/socom_arena_runtime_plan.gd")
const Session := preload("res://scripts/network/socom_tournament_session.gd")
var failed := false

func _initialize() -> void:
	var idle := Countdown.advance(false, true, 3.0, -1, 1.0)
	check(not idle.start and not idle.broadcast and idle.remaining == 3.0, "inactive countdown")
	var cancel := Countdown.advance(true, false, 0.1, 1, 1.0)
	check(cancel.cancel and cancel.broadcast and not cancel.start, "unready cancels before expiry")
	var tick := Countdown.advance(true, true, 3.0, -1, 0.1)
	check(tick.shown == 3 and tick.broadcast and not tick.start, "countdown broadcast")
	check(not Countdown.advance(true, true, 2.9, 3, 0.1).broadcast, "no duplicate second broadcast")
	check(Countdown.advance(true, true, 0.1, 1, 0.2).start, "ready countdown expires")
	var session := Session.new()
	var pairs: Array[int] = []
	var members := {}
	for pair in 16:
		pairs.append(pair)
		members[pair] = [{"peer_id": pair * 2 + 1}, {"peer_id": pair * 2 + 2}]
	check(bool(session.start(pairs, members).get("active", false)), "32-player domain session starts")
	var all_peers := {}
	for arena in 8:
		var roster := Plan.roster(session, arena)
		var deployment := Plan.deployment(session, arena)
		check(roster.size() == 4 and deployment.size() == 4, "four players per arena")
		var snapshot := {}
		for entry: Dictionary in roster:
			check(not all_peers.has(entry.peer_id), "no cross-arena duplicate")
			all_peers[entry.peer_id] = true
			snapshot[entry.peer_id] = {"health": 100}
		for entry: Dictionary in deployment:
			check(entry.combat_eligible and entry.spawn == session.spawn_for_peer(entry.peer_id), "deployment preserves eligibility and spawn")
		var packets := Encoder.packets(snapshot, 123, 77, 2)
		check(packets.size() == 2, "bounded packet chunks")
		for index in packets.size():
			var packet: Dictionary = packets[index]
			check(packet.timestamp_ms == 123 and packet.tick == 77 and packet.chunk_count == 2 and packet.chunk_index == index, "wire metadata preserved")
			for peer in packet.entities:
				check(session.arena_for_peer(peer) == arena, "packet arena isolation")
	check(all_peers.size() == 32, "all 32 represented once")
	var arena_match = session.coordinator.arena_sub_matches[0]
	arena_match.phase = arena_match.PHASE_SUDDEN_DEATH
	arena_match.sudden_death_peer_a = 1
	arena_match.sudden_death_peer_b = 3
	for entry: Dictionary in Plan.deployment(session, 0):
		check(entry.combat_eligible == (entry.peer_id in [1, 3]), "only selected representatives deploy alive")
	arena_match.is_round_active = false
	for entry: Dictionary in Plan.deployment(session, 0):
		check(not entry.combat_eligible, "intermission deactivates all combatants")
	check(Plan.roster(session, -1).is_empty() and Plan.roster(session, 99).is_empty(), "invalid arena rejected")
	print("LOBBY_REPLICATION_ARENA_REGRESSION ", "FAIL" if failed else "PASS")
	quit(1 if failed else 0)

func check(ok: bool, label: String) -> void:
	if not ok:
		failed = true
		push_error(label)
