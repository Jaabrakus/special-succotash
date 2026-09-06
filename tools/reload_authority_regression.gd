extends SceneTree
const Authority := preload("res://scripts/network/socom_reload_authority.gd")
var failures: Array[String] = []

func _initialize() -> void:
	var ledger := Authority.new()
	_expect(ledger.begin(2, "m60:actor1", 6.0, 1000), "start accepted")
	_expect(not ledger.begin(2, "m60:actor1", 0.25, 1100), "repeat cannot shorten or restart")
	_expect(not ledger.is_due(2, 6999) and ledger.is_due(2, 7000), "cheap deadline gate avoids per-frame profile reads")
	_expect(not ledger.consume_ready(2, "m60:actor1", 6999), "early completion rejected")
	_expect(ledger.consume_ready(2, "m60:actor1", 7000), "deadline completes")
	_expect(not ledger.consume_ready(2, "m60:actor1", 8000), "completion consumed once")
	ledger.begin(2, "m60:actor1", 6, 0)
	_expect(not ledger.consume_ready(2, "870:actor1", 7000), "weapon change discards deadline")
	_expect(not ledger.is_active(2), "stale weapon context removed")
	ledger.begin(2, "m60:actor1", 6, 0)
	_expect(not ledger.consume_ready(2, "m60:actor2", 7000), "respawn context rejects stale completion")
	ledger.begin(2, "m60:actor2", 6, 0)
	ledger.cancel(2)
	_expect(not ledger.consume_ready(2, "m60:actor2", 7000), "cancel prevents refill")
	for peer in range(1, 33):
		_expect(ledger.begin(peer, "scope:" + str(peer), 3, 100), "concurrent start")
	for peer in range(1, 33):
		_expect(not ledger.consume_ready(peer, "scope:" + str(peer), 3099), "concurrent no early refill")
		_expect(ledger.consume_ready(peer, "scope:" + str(peer), 3100), "concurrent independent completion")
	_expect(ledger.peer_ids().is_empty(), "completed ledger has no retained peers")
	ledger.begin(1, "old", 1, 0)
	ledger.clear()
	_expect(not ledger.consume_ready(1, "old", 9999), "session clear prevents stale completion")
	for failure in failures: push_error(failure)
	print("RELOAD_AUTHORITY_REGRESSION ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)

func _expect(ok: bool, label: String) -> void:
	if not ok: failures.append(label)
