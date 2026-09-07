extends SceneTree

const Controller := preload("res://scripts/weapons/socom_weapon_controller.gd")
const Ballistics := preload("res://scripts/weapons/weapon_ballistics.gd")
const Contract := preload("res://scripts/weapons/weapon_rig_contract.gd")
const Rules := preload("res://scripts/network/socom_round_weapon_rules.gd")
const Slots := preload("res://scripts/economy/socom_economy_rules.gd")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var game = load("res://multiplayer_slice.tscn").instantiate()
	root.add_child(game)
	var canonical := Controller.new()
	canonical.ballistics = Ballistics.new()
	canonical.add_child(canonical.ballistics)
	var checked := 0
	for id: String in Rules.firearm_pool():
		var config := Contract.load_config("res://config/weapons/%s.json" % id)
		assert(canonical._apply_weapon_config(config), id)
		game.equipped_config = config
		game._configure_local_fire_mode()
		assert(game.local_fire_policy.current_mode == canonical.current_fire_mode, id)
		assert(game.local_fire_policy.available_modes == canonical.available_fire_modes, id)
		for mode: String in canonical.available_fire_modes:
			canonical.fire_mode_policy.select_mode(mode)
			game.local_fire_policy.select_mode(mode)
			game.local_magazine_ammo = 100
			game.local_fire_cooldown = 0.0
			var reference_cooldown := 0.0
			var shots := 0
			for frame in 600:
				var held := frame < 60 or frame >= 300
				var pressed := frame == 0 or frame == 300
				var expected := canonical.fire_mode_policy.should_attempt_shot(pressed, held, 100 - shots)
				expected = expected and reference_cooldown <= 0.0
				var actual: bool = game._local_trigger_wants_shot(pressed, held, true)
				assert(actual == expected, "%s %s frame %d" % [id, mode, frame])
				if actual:
					shots += 1
					canonical.fire_mode_policy.notify_shot_result({"fired": true})
					game.local_fire_policy.notify_shot_result({"fired": true})
					game.local_magazine_ammo -= 1
					reference_cooldown = canonical.ballistics.fire_interval
					game.local_fire_cooldown = game._configured_fire_interval()
				reference_cooldown = maxf(0.0, reference_cooldown - 1.0 / 60.0)
				game.local_fire_cooldown = maxf(0.0, game.local_fire_cooldown - 1.0 / 60.0)
			if mode == "semi": assert(shots == 2, "%s must shoot once per pull" % id)
			if mode == "burst": assert(shots == 2 * canonical.burst_size, id)
			assert(not game._local_trigger_wants_shot(true, true, false), "Menu/death cannot fire")
			assert(not game.local_fire_policy.has_pending_burst(), "Disabled input cancels burst")
			game._refresh_player_state()
			var card = game.multiplayer_hud.loadout_card_hud
			assert(card.current_fire_mode == mode, id)
			assert(card.available_fire_modes == canonical.available_fire_modes, id)
			assert(card.active_slot_label == Slots.slot_for_category(String(config.category)).to_upper(), id)
			assert(card.weapon_display_name == String(config.display_name).to_upper(), id)
		checked += 1
	canonical.free()
	game.free()
	print("NETWORK_FIRE_MODE_PARITY PASS weapons=%d semi/burst/auto cadence, slot and HUD" % checked)
	quit()
