extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	for frame in 24:
		await process_frame
	var weapon = game.get("weapon_controller")
	var player = game.get("player")
	for magazine in [0, 5]:
		weapon.rounds_in_magazine = magazine
		weapon.reserve_rounds = 0
		assert(not weapon.can_reload())
		assert(not weapon.request_reload(), "No false-success reload preview")
		assert(not game.call("_request_weapon_reload"), "No reload animation without reserves")
		assert(not weapon.reload_locked and not player.get_meta("reload_action_pending", false))
		assert(weapon.rounds_in_magazine == magazine)
	weapon.rounds_in_magazine = weapon.magazine_capacity
	weapon.reserve_rounds = 20
	assert(not game.call("_request_weapon_reload"), "Full magazine cannot reload")
	weapon.rounds_in_magazine = 0
	assert(weapon.can_reload())
	assert(game.call("_request_weapon_reload"), "Empty magazine with reserves can reload")
	assert(weapon.reload_locked and weapon.rounds_in_magazine == 0, "Ammo still waits for commit cue")
	print("EMPTY_AMMO_RELOAD_PASS: rejected before animation, full-mag rejection, valid empty-mag reload")
	game.queue_free()
	await process_frame
	quit()
