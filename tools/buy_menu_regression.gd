extends SceneTree

## Buy menu regression: economy rules, price-table coverage, purchase
## validation, profile availability, UI construction/signals, and the source
## contract that the menu never equips weapons directly.

const Economy := preload("res://scripts/economy/socom_economy_rules.gd")
const Validator := preload("res://scripts/economy/socom_purchase_validator.gd")
const BuyMenuScript := preload("res://scripts/ui/socom_buy_menu.gd")
const KeyboardMappingProfile := preload("res://scripts/input/socom_keyboard_mapping_profile.gd")

var failures := 0


func _expect(condition: bool, message: String) -> void:
	if condition:
		print("BUY_MENU_CHECK PASS ", message)
		return
	failures += 1
	push_error("BUY_MENU_CHECK FAIL " + message)


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_check_economy_rules()
	_check_price_table()
	_check_weapon_profiles()
	_check_validator()
	_check_input_profile()
	await _check_ui_construction()
	_check_source_contracts()
	_finish()


func _finish() -> void:
	if failures == 0:
		print("BUY_MENU_REGRESSION PASS")
		quit(0)
		return
	print("BUY_MENU_REGRESSION FAIL count=", failures)
	quit(1)


func _check_economy_rules() -> void:
	_expect(not Economy.get_config().is_empty(), "economy config loads")
	_expect(Economy.firearm_categories().size() == 6, "six firearm categories configured")
	_expect(Economy.starting_cash() > 0, "starting cash is positive")
	_expect(Economy.buy_window_seconds() >= 5.0, "buy window is at least five seconds")
	_expect(Economy.carry_weight_cap() >= 3, "carry weight cap is at least three")
	_expect(Economy.slot_for_category("Pistols") == "secondary", "pistols occupy the secondary slot")
	_expect(Economy.slot_for_category("Assault Rifles") == "primary", "rifles occupy the primary slot")


func _check_price_table() -> void:
	var priced := 0
	for category: Variant in Economy.firearm_categories():
		for raw_record: Variant in Economy.weapons_for_category(String(category)):
			var weapon_id := String((raw_record as Dictionary).get("weapon_id", ""))
			if Economy.price_for(weapon_id) <= 0:
				_expect(false, "weapon has a positive price: " + weapon_id)
				continue
			if Economy.carry_weight_for(weapon_id) <= 0:
				_expect(false, "weapon has a positive carry weight: " + weapon_id)
				continue
			priced += 1
	_expect(priced == 34, "all 34 catalog firearms are priced (got %d)" % priced)


func _check_weapon_profiles() -> void:
	var with_profiles := 0
	for category: Variant in Economy.firearm_categories():
		for raw_record: Variant in Economy.weapons_for_category(String(category)):
			var weapon_id := String((raw_record as Dictionary).get("weapon_id", ""))
			var path := "res://config/weapons/%s.json" % weapon_id
			if not FileAccess.file_exists(path):
				_expect(false, "firearm has an equip profile: " + weapon_id)
				continue
			var file := FileAccess.open(path, FileAccess.READ)
			var parsed: Variant = JSON.parse_string(file.get_as_text()) if file else null
			file.close()
			if not parsed is Dictionary:
				_expect(false, "firearm profile parses: " + weapon_id)
				continue
			var profile := parsed as Dictionary
			if String(profile.get("model_fbx", "")).is_empty():
				_expect(false, "firearm profile has a model: " + weapon_id)
				continue
			if not (profile.get("fire_modes", []) is Array) or (profile.get("fire_modes") as Array).is_empty():
				_expect(false, "firearm profile has fire modes: " + weapon_id)
				continue
			with_profiles += 1
	_expect(with_profiles == 34, "all 34 firearms are equippable (got %d)" % with_profiles)


func _validator_context(cash: int, loadout: Dictionary, phase_open: bool, economy: bool) -> Dictionary:
	return {"cash": cash, "loadout": loadout, "phase_open": phase_open, "economy_enabled": economy}


func _check_validator() -> void:
	var verdict := Validator.validate("ak-47", _validator_context(8000, {"primary": "", "secondary": ""}, true, true))
	_expect(bool(verdict.get("ok", false)), "affordable rifle purchase validates")
	_expect(String(verdict.get("slot", "")) == "primary", "rifle resolves to the primary slot")

	verdict = Validator.validate("m9", _validator_context(8000, {"primary": "ak-47", "secondary": ""}, true, true))
	_expect(bool(verdict.get("ok", false)), "sidearm purchase validates alongside a rifle")
	_expect(String(verdict.get("slot", "")) == "secondary", "pistol resolves to the secondary slot")

	verdict = Validator.validate("m82a1a", _validator_context(100, {"primary": "", "secondary": ""}, true, true))
	_expect(not bool(verdict.get("ok", false)), "insufficient funds is rejected")
	_expect(String(verdict.get("reason", "")) == "INSUFFICIENT FUNDS", "insufficient funds reason is exact")

	verdict = Validator.validate("ak-47", _validator_context(8000, {"primary": "", "secondary": ""}, false, true))
	_expect(not bool(verdict.get("ok", false)), "purchase outside the buy window is rejected")
	_expect(String(verdict.get("reason", "")) == "BUY WINDOW CLOSED", "closed window reason is exact")

	verdict = Validator.validate(
		"mark_46_mod_0",
		_validator_context(16000, {"primary": "m82a1a", "secondary": "m9"}, true, true)
	)
	_expect(not bool(verdict.get("ok", false)), "over-weight loadout is rejected")
	_expect(String(verdict.get("reason", "")) == "OVER CARRY WEIGHT", "carry weight reason is exact")

	verdict = Validator.validate("ak-47", _validator_context(8000, {"primary": "ak-47", "secondary": ""}, true, true))
	_expect(not bool(verdict.get("ok", false)), "rebuying the carried weapon is rejected")

	verdict = Validator.validate("m67", _validator_context(16000, {"primary": "", "secondary": ""}, true, true))
	_expect(not bool(verdict.get("ok", false)), "non-firearm catalog ids are rejected")

	verdict = Validator.validate("not_a_weapon", _validator_context(16000, {"primary": "", "secondary": ""}, true, true))
	_expect(not bool(verdict.get("ok", false)), "unknown weapon ids are rejected")

	verdict = Validator.validate("m60e3", _validator_context(0, {"primary": "m82a1a", "secondary": ""}, false, false))
	_expect(bool(verdict.get("ok", false)), "training sandbox issues any weapon without cash, window, or weight")

	var applied := Validator.apply_purchase(
		"ak-47", {"primary": "", "secondary": "m9"}, 3000, true
	)
	_expect(int(applied.get("cash", -1)) == 3000 - Economy.price_for("ak-47"), "purchase deducts the price")
	_expect(
		String((applied.get("loadout", {}) as Dictionary).get("primary", "")) == "ak-47",
		"purchase fills the primary slot"
	)
	_expect(
		String((applied.get("loadout", {}) as Dictionary).get("secondary", "")) == "m9",
		"purchase preserves the other slot"
	)


func _check_input_profile() -> void:
	_expect(&"open_buy_menu" in KeyboardMappingProfile.ACTION_ORDER, "buy action is remappable in the profile")
	_expect(
		KeyboardMappingProfile.DEFAULT_BINDINGS.has(&"open_buy_menu"),
		"buy action has a default binding"
	)
	var buy_bindings: Array = KeyboardMappingProfile.DEFAULT_BINDINGS[&"open_buy_menu"]
	_expect(
		buy_bindings.size() == 1
		and int((buy_bindings[0] as Dictionary).get("physical_keycode", 0)) == KEY_P,
		"buy action defaults to P"
	)
	var fire_mode_bindings: Array = KeyboardMappingProfile.DEFAULT_BINDINGS[&"toggle_fire_mode"]
	_expect(
		int((fire_mode_bindings[0] as Dictionary).get("physical_keycode", 0)) == KEY_B,
		"B remains dedicated to fire mode"
	)
	_expect(
		String(KeyboardMappingProfile.ACTION_LABELS.get(&"open_buy_menu", "")).length() > 4,
		"buy action has a player-facing label"
	)


func _check_ui_construction() -> void:
	var menu := BuyMenuScript.new()
	root.add_child(menu)
	await process_frame

	menu.economy_enabled = true
	menu.update_state(8000, {"primary": "ak-47", "secondary": "m9"}, 12.0, true)
	menu.open_menu()
	await process_frame
	_expect(menu.is_open(), "menu opens")
	_expect(menu.visible, "menu is visible while open")
	var category_buttons := 0
	for category: Variant in Economy.firearm_categories():
		if menu._category_buttons.has(String(category)):
			category_buttons += 1
	_expect(category_buttons == 6, "all six categories are selectable (got %d)" % category_buttons)
	_expect(not menu._selected_category.is_empty(), "a category is selected on open")
	_expect(not menu._selected_weapon_id.is_empty(), "a weapon is selected on open")

	var requested: Array[String] = []
	menu.purchase_requested.connect(func(weapon_id: String): requested.append(weapon_id))
	menu._submit("ak-47")
	await process_frame
	_expect(requested.size() == 1 and requested[0] == "ak-47", "purchase request signal carries the weapon id")

	var close_events: Array[bool] = []
	menu.close_requested.connect(func(): close_events.append(true))
	var cancel_event := InputEventAction.new()
	cancel_event.action = "ui_cancel"
	cancel_event.pressed = true
	_expect(menu.handle_unhandled_input(cancel_event), "escape is consumed while open")
	_expect(close_events.size() == 1, "escape requests close")

	menu.close_menu()
	_expect(not menu.is_open(), "menu closes")

	menu.economy_enabled = false
	menu.update_state(0, {"primary": "", "secondary": ""}, 0.0, true)
	menu.open_menu()
	await process_frame
	_expect(menu._row_label(
		Economy.weapon_record("ak-47"),
		Validator.validate("ak-47", _validator_context(0, {"primary": "", "secondary": ""}, false, false))
	).contains("$") == false, "training sandbox hides prices")
	menu.free()


func _check_source_contracts() -> void:
	var menu_source := FileAccess.get_file_as_string("res://scripts/ui/socom_buy_menu.gd")
	_expect(
		not menu_source.contains("apply_authorized_weapon_pickup"),
		"buy menu never equips weapons directly"
	)
	_expect(
		not menu_source.contains("load_config"),
		"buy menu never loads weapon configs"
	)
	var buy_phase_source := FileAccess.get_file_as_string("res://scripts/network/socom_multiplayer_buy_phase.gd")
	_expect(
		buy_phase_source.contains("Validator.validate"),
		"server purchase path validates through the shared validator"
	)
	_expect(
		buy_phase_source.contains("@rpc(\"any_peer\", \"call_remote\", \"reliable\")"),
		"purchase submission is a client-to-server RPC"
	)
	_expect(
		buy_phase_source.contains("_apply_ballistics_profile(ballistics, weapon_config)"),
		"accepted purchases reconfigure authoritative per-peer ballistics"
	)
	_expect(
		buy_phase_source.contains("func _on_round_resolution_started"),
		"round cash is awarded only after the parent resolution guard"
	)
	_expect(
		buy_phase_source.contains("_apply_replicated_weapon_presentation"),
		"world snapshots apply purchased presentation to every operator view"
	)
	_expect(
		buy_phase_source.contains("peer_id == multiplayer.get_unique_id()"),
		"host purchases receive their result without a self RPC"
	)
	var range_runtime_source := FileAccess.get_file_as_string(
		"res://scripts/runtime/main_buy_menu_runtime.gd"
	)
	_expect(
		not range_runtime_source.contains("buy_menu.close_menu()\n\t\tclose_menu()"),
		"training purchase restores input through one runtime close path"
	)
	_expect(
		not range_runtime_source.contains("_player_in_zone"),
		"training range opens the buy menu without a hidden spawn-radius gate"
	)
	var gunfight_source := FileAccess.get_file_as_string("res://scripts/network/socom_multiplayer_gunfight.gd")
	_expect(
		gunfight_source.begins_with("extends \"res://scripts/network/socom_multiplayer_buy_phase.gd\""),
		"gunfight layer sits above the buy phase layer"
	)
	var objectives_source := FileAccess.get_file_as_string("res://scripts/network/socom_multiplayer_objectives.gd")
	_expect(
		objectives_source.begins_with("extends \"res://scripts/network/socom_multiplayer_gunfight.gd\""),
		"objectives layer sits above the gunfight layer"
	)
	_expect(
		objectives_source.count("_award_objective_cash(") == 2,
		"plant and defuse both grant the configured objective award"
	)
	var world_ui_source := FileAccess.get_file_as_string(
		"res://scripts/network/socom_multiplayer_world_ui.gd"
	)
	_expect(
		world_ui_source.contains("_buy_menu_dismissed_for_window"),
		"multiplayer remembers a player-dismissed menu for the current window"
	)
	_expect(
		world_ui_source.contains("not exit_menu.is_open()"),
		"buy menu cannot open underneath the exit menu"
	)
