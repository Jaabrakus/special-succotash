extends SceneTree

const KeyboardProfile := preload("res://scripts/input/socom_keyboard_mapping_profile.gd")
const EquipmentWheel := preload("res://scripts/ui/socom_equipment_wheel.gd")
const RadioCommandWheel := preload("res://scripts/ui/socom_radio_command_wheel.gd")
const LoadoutCardHUD := preload("res://scripts/ui/socom_loadout_card_hud.gd")
const TeamRosterHUD := preload("res://scripts/ui/socom_team_roster_hud.gd")
const MultiplayerHUD := preload("res://scripts/network/socom_multiplayer_hud.gd")
const WeaponController := preload("res://scripts/weapons/socom_weapon_controller.gd")
const FireModePolicy := preload("res://scripts/weapons/weapon_fire_mode_policy.gd")
const WeaponContract := preload("res://scripts/weapons/weapon_rig_contract.gd")


func _initialize() -> void:
	print("--- Running Loadout HUD & Scorecard Regression ---")

	_test_input_mapping()
	_test_equipment_wheel_directional_selection()
	_test_radio_wheel_directional_selection()
	_test_weapon_controller_fire_modes()
	_test_fire_mode_trigger_gate()
	_test_imported_fire_mode_contracts()
	_test_loadout_card_hud()
	_test_team_roster_dynamic_data()
	_test_multiplayer_roster_forwarding()

	print("LOADOUT_HUD_SCORECARD_REGRESSION PASS")
	quit(0)


func _test_input_mapping() -> void:
	print("Checking input profile registration...")
	assert(KeyboardProfile.ACTION_ORDER.has(&"toggle_fire_mode"), "toggle_fire_mode missing from ACTION_ORDER")
	assert(KeyboardProfile.DEFAULT_BINDINGS.has(&"toggle_fire_mode"), "toggle_fire_mode missing default binding")
	var bindings: Array = KeyboardProfile.DEFAULT_BINDINGS[&"toggle_fire_mode"]
	assert(bindings.size() > 0 and int(bindings[0].get("physical_keycode", 0)) == KEY_B, "toggle_fire_mode not bound to KEY_B")
	print("✓ Input mapping verified")


func _test_equipment_wheel_directional_selection() -> void:
	print("Checking equipment wheel directional mouse motion...")
	var wheel = EquipmentWheel.new()
	var entries: Array[Dictionary] = [
		{"id": &"primary", "label": "M16A2", "enabled": true},
		{"id": &"secondary", "label": "M9", "enabled": true},
		{"id": &"frag", "label": "FRAG x2", "enabled": true},
		{"id": &"flash", "label": "FLASH x1", "enabled": true},
		{"id": &"smoke", "label": "SMOKE x1", "enabled": true},
		{"id": &"mission", "label": "AUTO", "enabled": false},
	]
	wheel.show_wheel(entries, 0)
	assert(wheel.visible, "Wheel should be visible after show_wheel")
	assert(wheel.selected_index == 0, "Initial selected_index should be 0")

	# Move mouse downward-right (towards bottom entries)
	wheel.apply_mouse_motion(Vector2(100.0, 100.0))
	assert(wheel.selected_index != 0, "Directional mouse motion must leave the initial equipment segment")
	assert(wheel.selected_index >= 0 and wheel.selected_index < entries.size(), "Selected index should be within bounds")

	wheel.hide_wheel()
	assert(not wheel.visible, "Wheel should be hidden after hide_wheel")
	wheel.free()
	print("✓ Equipment wheel directional selection verified")


func _test_radio_wheel_directional_selection() -> void:
	print("Checking radio wheel directional mouse motion...")
	var wheel = RadioCommandWheel.new()
	wheel.open_wheel()
	assert(wheel.selected_index == 0, "Radio wheel should start on its first sector")
	wheel.apply_mouse_motion(Vector2(100.0, 100.0))
	assert(wheel.selected_index != 0, "Directional mouse motion must leave the initial radio sector")
	wheel.free()
	print("✓ Radio wheel directional selection verified")


func _test_weapon_controller_fire_modes() -> void:
	print("Checking weapon controller fire mode cycling...")
	var controller = WeaponController.new()
	controller.set_fire_modes(["auto", "burst", "semi"])
	controller.current_fire_mode = "auto"

	var emitted_mode := [""]
	controller.fire_mode_changed.connect(func(m): emitted_mode[0] = m)

	var next_mode: String = controller.cycle_fire_mode()
	assert(next_mode == "burst", "Expected burst fire mode after cycling auto")
	assert(controller.get_fire_mode() == "burst", "get_fire_mode should return burst")
	assert(emitted_mode[0] == "burst", "Signal fire_mode_changed not emitted with burst")

	next_mode = controller.cycle_fire_mode()
	assert(next_mode == "semi", "Expected semi fire mode after cycling burst")

	next_mode = controller.cycle_fire_mode()
	assert(next_mode == "auto", "Expected auto fire mode after cycling semi")

	var snapshot: Dictionary = controller.get_ammo_snapshot()
	assert(snapshot.get("fire_mode") == "auto", "Ammo snapshot missing fire_mode")
	assert(snapshot.get("available_fire_modes") is Array, "Ammo snapshot missing available_fire_modes")

	controller.free()
	print("✓ Weapon controller fire mode cycling verified")


func _test_fire_mode_trigger_gate() -> void:
	print("Checking enforced semi, burst, and auto trigger behavior...")
	var policy = FireModePolicy.new()

	policy.configure(["semi"], "semi", 3)
	assert(policy.should_attempt_shot(true, true, 30), "Semi must fire on press")
	assert(not policy.should_attempt_shot(false, true, 29), "Semi must not repeat while held")
	assert(policy.should_attempt_shot(true, true, 29), "Semi must fire after a new press")

	policy.configure(["burst"], "burst", 3)
	for shot_index in 3:
		assert(
			policy.should_attempt_shot(shot_index == 0, true, 30 - shot_index),
			"Three-round burst stopped before shot %d" % (shot_index + 1)
		)
		policy.notify_shot_result({"fired": true})
	assert(not policy.should_attempt_shot(false, true, 27), "Burst repeated without release")

	policy.configure(["burst"], "burst", 2)
	assert(policy.should_attempt_shot(true, true, 30), "Two-round burst missed first shot")
	policy.notify_shot_result({"fired": true})
	assert(policy.should_attempt_shot(false, true, 29), "Two-round burst missed second shot")
	policy.notify_shot_result({"fired": true})
	assert(not policy.should_attempt_shot(false, true, 28), "Two-round burst fired a third shot")

	policy.configure(["auto"], "auto", 3)
	assert(policy.should_attempt_shot(true, true, 30), "Auto missed initial shot")
	assert(policy.should_attempt_shot(false, true, 29), "Auto must continue while held")
	assert(not policy.should_attempt_shot(false, false, 28), "Auto must stop on release")
	print("✓ Fire mode trigger limits verified")


func _test_imported_fire_mode_contracts() -> void:
	print("Checking imported reCOM fire mode contracts...")
	var m16 := WeaponContract.load_config("res://config/weapons/assaultrifle_1.json")
	assert(m16.get("fire_modes") == ["semi", "burst"], "M16A2 modes mismatch")
	assert(int(m16.get("burst_size", 0)) == 3, "M16A2 must use a three-round burst")
	var ak47 := WeaponContract.load_config("res://config/weapons/ak-47.json")
	assert(ak47.get("fire_modes") == ["semi", "auto"], "AK-47 modes mismatch")
	var sniper := WeaponContract.load_config("res://config/weapons/sniperrifle_1.json")
	assert(sniper.get("fire_modes") == ["semi"], "M82A1A must remain semi-auto")
	print("✓ Imported fire mode contracts verified")


func _test_loadout_card_hud() -> void:
	print("Checking SocomLoadoutCardHUD updates...")
	var hud = LoadoutCardHUD.new()
	hud.update_weapon_state("AK-47", "PRIMARY", 30, 90, "burst", ["auto", "burst", "semi"], 3)
	assert(hud.weapon_display_name == "AK-47", "Weapon name mismatch")
	assert(hud.rounds_in_magazine == 30, "Magazine mismatch")
	assert(hud.current_fire_mode == "burst", "Fire mode mismatch")
	assert(hud.burst_size == 3, "Burst count mismatch")

	hud.update_grenade_state({"frag": 3, "flash": 2, "smoke": 0}, "FRAG", true)
	assert(hud.is_grenade_active == true, "Grenade should be active")
	assert(hud.active_slot_label == "GRENADE", "Slot label should be GRENADE")

	hud.update_health(75.0, 100.0)
	assert(hud.health_current == 75.0, "Health current mismatch")

	hud.free()
	print("✓ SocomLoadoutCardHUD verified")


func _test_team_roster_dynamic_data() -> void:
	print("Checking SocomTeamRosterHUD dynamic data binding...")
	var roster_hud = TeamRosterHUD.new()
	var alpha := [
		{"name": "ALPHA 1 (YOU)", "alive": true, "kills": 5, "deaths": 1, "ping": 18},
		{"name": "ALPHA 2", "alive": false, "kills": 2, "deaths": 3, "ping": 25},
	]
	var bravo := [
		{"name": "BRAVO 1", "alive": true, "kills": 3, "deaths": 2, "ping": 40},
		{"name": "BRAVO 2", "alive": false, "kills": 1, "deaths": 4, "ping": 55},
	]
	roster_hud.set_roster_data(alpha, bravo, 2, 1, 142.5, "BOMB ARMED", true)

	assert(roster_hud.alpha_players.size() == 2, "Alpha players count mismatch")
	assert(roster_hud.bravo_players.size() == 2, "Bravo players count mismatch")
	assert(roster_hud.team_alpha_score == 2, "Alpha score mismatch")
	assert(roster_hud.team_bravo_score == 1, "Bravo score mismatch")
	assert(roster_hud.is_bomb_armed == true, "Bomb armed state mismatch")
	assert(roster_hud.bomb_status_text == "BOMB ARMED", "Bomb status text mismatch")

	roster_hud.show_scorecard(true)
	assert(roster_hud.visible, "Scorecard should be visible")
	roster_hud.show_scorecard(false)
	assert(not roster_hud.visible, "Scorecard should be hidden")

	roster_hud.free()
	print("✓ SocomTeamRosterHUD dynamic binding verified")


func _test_multiplayer_roster_forwarding() -> void:
	print("Checking multiplayer roster forwarding...")
	var multiplayer_hud = MultiplayerHUD.new()
	var roster_hud = TeamRosterHUD.new()
	multiplayer_hud.team_roster_hud = roster_hud
	multiplayer_hud.update_roster_data(
		[{"name": "ALPHA", "alive": true}],
		[{"name": "BRAVO", "alive": true}],
		3,
		2,
		41.0,
		"BOMB ARMED",
		true
	)
	assert(roster_hud.team_alpha_score == 3, "Multiplayer Alpha score was not forwarded")
	assert(roster_hud.team_bravo_score == 2, "Multiplayer Bravo score was not forwarded")
	assert(roster_hud.is_bomb_armed, "Multiplayer bomb state was not forwarded")
	multiplayer_hud.free()
	roster_hud.free()
	print("✓ Multiplayer roster forwarding verified")
