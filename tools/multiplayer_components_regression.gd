extends SceneTree

const Queue := preload("res://scripts/network/socom_combat_command_queue.gd")
const Policy := preload("res://scripts/network/socom_round_policy.gd")
const Factory := preload("res://scripts/network/socom_transport_factory.gd")
var failed := false

func _initialize() -> void:
	var queue := Queue.new()
	queue.reset_peer(7)
	var packet := {"sequence": 1, "payload": {"value": 2}}
	check(queue.enqueue(7, packet, 1), "accept initial shot")
	packet.payload.value = 9
	var snapshot := queue.snapshot(7)
	check(snapshot[0].payload.value == 2, "input copied")
	snapshot[0].payload.value = 8
	check(queue.snapshot(7)[0].payload.value == 2, "diagnostic snapshot isolated")
	check(not queue.enqueue(7, {"sequence": 1}, 1), "reject replay")
	check(not queue.enqueue(7, {"sequence": 2}, 1), "bounded queue")
	check(not queue.enqueue(7, {"sequence": "3"}, 1), "reject malformed sequence")
	queue.defer_reload(7)
	check(not queue.consume_reload(7), "reload waits for shots")
	check(queue.pop_ready(7, false).is_empty(), "cooldown preserves queue")
	check(queue.pop_ready(7, true).sequence == 1, "ready consumes once")
	check(queue.consume_reload(7) and not queue.consume_reload(7), "reload consumed once")
	queue.defer_reload(7)
	check(queue.enqueue(7, {"sequence": 2}, 1) and not queue.reload_pending(7), "fresh fire cancels deferred reload")
	queue.reset_peer(7, true)
	check(not queue.has_shots(7) and queue.last_sequence(7) == 2, "weapon swap preserves replay protection")
	queue.reset_peer(7)
	check(queue.last_sequence(7) == -1, "new peer resets sequence")
	queue.remove_peer(7)
	check(queue.peer_ids().is_empty(), "disconnect clears peer")
	var paused := Policy.advance_clock(10.0, 10, 2.0, false, "alpha")
	check(paused.remaining == 10.0 and not paused.broadcast and not paused.expired, "inactive or planted-bomb clock paused")
	var tick := Policy.advance_clock(10.0, 10, 1.0, true, "draw")
	check(tick.remaining == 9.0 and tick.broadcast and not tick.expired, "clock second broadcast")
	for result in ["alpha", "bravo", "draw"]:
		var end := Policy.advance_clock(0.1, 1, 0.2, true, result)
		check(end.expired and end.remaining == 0.0 and end.winner == ["draw", "alpha", "bravo"].find(result) - 1, "timeout " + result)
	check(Policy.match_complete(0, {0: 4}, 4, {}), "win threshold")
	check(Policy.match_complete(-1, {}, 7, {}), "round limit")
	check(not Policy.match_complete(0, {0: 2}, 3, {}), "unfinished match")
	check(int(Factory.connect_websocket("ws://example.com", 1234, true).error) != OK, "secure browser rejects insecure endpoint")
	for file in ["socom_transport_factory", "socom_round_policy", "socom_combat_command_queue", "socom_shot_presentation"]:
		var source := FileAccess.get_file_as_string("res://scripts/network/" + file + ".gd")
		check(not "socom_multiplayer_state.gd" in source and not "get_parent(" in source and not "@rpc" in source, "independent boundary " + file)
	print("MULTIPLAYER_COMPONENTS_REGRESSION " + ("FAIL" if failed else "PASS"))
	quit(1 if failed else 0)

func check(ok: bool, label: String) -> void:
	if not ok:
		failed = true
		push_error(label)
