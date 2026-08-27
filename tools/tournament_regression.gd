extends SceneTree

## Tournament model regression: registration, locking, seeded bracket shape,
## pod faction assignment with side alternation, advancement, and champion
## resolution. Run headless:
##   godot --headless --path . --script res://tools/tournament_regression.gd

const Tournament := preload("res://scripts/tournament/socom_tournament_model.gd")

var failures: int = 0


func _expect(condition: bool, message: String) -> void:
	if condition:
		print("TOURNAMENT_CHECK PASS ", message)
		return
	failures += 1
	push_error("TOURNAMENT_CHECK FAIL " + message)


func _initialize() -> void:
	_check_registration()
	_check_lock_and_seeding()
	var model := _check_full_tournament()
	_check_snapshots(model)
	_finish()


func _finish() -> void:
	if failures == 0:
		print("TOURNAMENT_REGRESSION PASS")
		quit(0)
		return
	print("TOURNAMENT_REGRESSION FAIL count=", failures)
	quit(1)


func _fill(model, count: int = 16) -> void:
	for index: int in count:
		var result: Dictionary = model.register_squad("Squad %02d" % (index + 1), 100 + index)
		_expect(bool(result.get("ok", false)), "squad %d registers" % (index + 1))
		var join: Dictionary = model.join_squad(String(result.get("squad_id", "")), 200 + index)
		_expect(bool(join.get("ok", false)), "squad %d fills its second seat" % (index + 1))
		model.set_squad_ready(String(result.get("squad_id", "")), true)


func _check_registration() -> void:
	var model := Tournament.new()
	_expect(model.state == Tournament.STATE_REGISTRATION, "model starts in registration")
	var duplicate := model.register_squad("First", 1)
	model.register_squad("Second", 2)
	var again := model.register_squad("Third", 1)
	_expect(not bool(again.get("ok", true)), "a captain cannot found two squads")
	var house := model.register_squad("Housed", 3, "arepo")
	_expect(
		String((model.squads[String(house.get("squad_id", ""))] as Dictionary).get("house", "")) == "AREPO",
		"house affiliation uppercases and validates"
	)
	var bad_house := model.register_squad("Unhoused", 4, "PROTAGONIST")
	_expect(
		String((model.squads[String(bad_house.get("squad_id", ""))] as Dictionary).get("house", "kept")) == "",
		"unknown houses are dropped, not rejected"
	)
	var join_result: Dictionary = model.join_squad(String(duplicate.get("squad_id", "")), 9)
	_expect(bool(join_result.get("ok", false)), "a second player joins a squad")
	var full: Dictionary = model.join_squad(String(duplicate.get("squad_id", "")), 10)
	_expect(not bool(full.get("ok", true)), "a third player cannot join a 2v2 squad")
	var elsewhere: Dictionary = model.join_squad(String(house.get("squad_id", "")), 9)
	_expect(not bool(elsewhere.get("ok", true)), "a player cannot join two squads")
	_expect(not model.registration_ready_to_lock(), "not lockable while squads are unready or unfilled")


func _check_lock_and_seeding() -> void:
	var model := Tournament.new()
	_fill(model)
	var locked: Dictionary = model.lock_registration()
	_expect(bool(locked.get("ok", false)), "sixteen full ready squads lock the bracket")
	_expect(int(locked.get("pods", 0)) == 15, "a 16-squad bracket has exactly 15 matches")
	var round_one: Array[Dictionary] = model._pods_in_round(1)
	_expect(round_one.size() == 8, "eight opening pods")
	var left := 0
	var right := 0
	for match: Dictionary in round_one:
		if int(match["display_side"]) == 0:
			left += 1
		else:
			right += 1
	_expect(left == 4 and right == 4, "opening pods split four left, four right")
	_expect(
		int(round_one[0]["seed_a"]) == 1 and int(round_one[0]["seed_b"]) == 16,
		"seed one meets seed sixteen first"
	)
	_expect(
		int(round_one[7]["seed_a"]) == 2 and int(round_one[7]["seed_b"]) == 15,
		"seed two anchors the right half"
	)
	_expect(model._pods_in_round(2).size() == 4, "four quarterfinals")
	_expect(model._pods_in_round(3).size() == 2, "two semifinals")
	_expect(model._pods_in_round(4).size() == 1, "one final")
	var reopen: Dictionary = model.register_squad("Late", 999)
	_expect(not bool(reopen.get("ok", true)), "registration closes after lock")


func _check_full_tournament() -> RefCounted:
	var model := Tournament.new()
	_fill(model)
	model.lock_registration()
	# Run the entire bracket: higher seed wins every pod except the final,
	# where seed 2 takes the Tenet.
	var match_number := 1
	for round_number: int in 4:
		var live: Array[Dictionary] = model._pods_in_round(round_number + 1)
		for match: Dictionary in live:
			var pod: Dictionary = model.open_pod(match_number)
			_expect(bool(pod.get("ok", false)), "match %d opens a pod" % match_number)
			# The better (lower) seed wins every pod except the scripted final
			# upset, where seed two takes the Tenet.
			var winner_seed: int = (
				2
				if round_number == 3
				else mini(int(match["seed_a"]), int(match["seed_b"]))
			)
			var winner_id := model._squad_for_seed(winner_seed)
			var report: Dictionary = model.report_pod_result(match_number, winner_id)
			_expect(bool(report.get("ok", false)), "match %d reports and advances (%s)" % [match_number, report.get("reason", "ok")])
			match_number += 1
	_expect(model.state == Tournament.STATE_COMPLETE, "the bracket completes")
	_expect(model.champion() == model._squad_for_seed(2), "seed two holds the Tenet")
	var final: Array[Dictionary] = model._pods_in_round(4)
	_expect(String(final[0]["state"]) == "reported", "the final records its result")
	return model


func _check_snapshots(model: RefCounted) -> void:
	var snap: Dictionary = model.snapshot()
	_expect(snap.get("state", "") == Tournament.STATE_COMPLETE, "snapshot exposes tournament state")
	_expect((snap.get("pods", []) as Array).size() == 15, "snapshot carries the full bracket")
	_expect(String(snap.get("champion", "")) != "", "snapshot names the champion")
