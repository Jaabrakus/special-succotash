extends SceneTree

const Catalog := preload("res://scripts/weapons/socom_weapon_catalog.gd")
const Economy := preload("res://scripts/economy/socom_economy_rules.gd")
const Validator := preload("res://scripts/economy/socom_purchase_validator.gd")
const RoundRules := preload("res://scripts/network/socom_round_weapon_rules.gd")
const EXCLUDED := ["designator", "mk_3-a2", "air_to_ground_missile", "exploding_fuel"]
const ARCHIVE_SHA256 := "a867d849e3e1a3c1e056537395d9832e13958a31bf3dca688e8711d9a9325d79"
var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_expect(FileAccess.get_sha256(Catalog.CATALOG_PATH) == ARCHIVE_SHA256, "all archived source data remains byte-identical")
	_expect(Catalog.get_all_weapons().size() == 63 + Catalog.source_arsenal_ids().size(), "archive/prototypes retained alongside source arsenal")
	_expect(Catalog.get_weapon("m40a1").category == "Sniper Rifles", "M40A1 runtime category")
	var saved_m40: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://config/weapons/m40a1.json"))
	_expect(saved_m40.category == "Sniper Rifles", "M40A1 canonical profile category")
	var pool := RoundRules.firearm_pool()
	_expect(pool.size() == 12, "12 core competitive firearms; no hidden selections")
	var context := {"cash": 0, "loadout": {"primary": "m4a1", "secondary": "mark_23"}, "phase_open": true, "economy_enabled": true}
	for id: String in EXCLUDED:
		_expect(not Catalog.get_weapon(id).is_empty(), id + " remains archived")
		_expect(not pool.has(id), id + " absent from server firearm pool")
		for economy_enabled in [false, true]:
			var denied := context.duplicate(true)
			denied["economy_enabled"] = economy_enabled
			denied["allow_training_prototypes"] = true
			_expect(not bool(Validator.validate(id, denied).ok), id + " rejected by shared selection validation")
	var eligible_ids: Array[String] = []
	for category: String in Economy.firearm_categories():
		for record: Dictionary in Economy.weapons_for_category(category):
			var id := String(record.weapon_id)
			eligible_ids.append(id)
			_expect(not EXCLUDED.has(id), id + " is a handheld selection")
	_expect(eligible_ids.size() == 12 + Catalog.source_arsenal_ids().size(), "core weapons plus explicit source arsenal visible")
	var verdict := Validator.validate("m40a1", context)
	_expect(bool(verdict.ok) and int(verdict.cost) == 0 and verdict.slot == "primary", "M40A1 equips with zero cash")
	context["cash"] = -100
	_expect(bool(Validator.validate("m40a1", context).ok), "even negative legacy cash cannot block equipment selection")
	var applied := Validator.apply_purchase("m40a1", context.loadout, 0, true)
	_expect(applied.loadout == {"primary": "m40a1", "secondary": "mark_23"} and int(applied.cash) == 0, "primary replaced without cash or extra slots")
	context["phase_open"] = false
	_expect(not bool(Validator.validate("m40a1", context).ok), "locked phase cannot be bypassed by free selection")
	ProjectSettings.set_setting("socom/session/public_training", true)
	var game := (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(game)
	current_scene = game
	for frame in 35:
		await process_frame
	var runtime = game.buy_menu_runtime
	var menu = runtime.buy_menu
	var grenades_before: Dictionary = game.grenade_inventory.duplicate(true)
	runtime.open_menu()
	var row_ids: Array[String] = []
	for category: String in Economy.firearm_categories():
		menu._select_category(category)
		await process_frame
		for row: Node in menu._row_container.get_children():
			var id := String(row.get_meta("weapon_id", ""))
			row_ids.append(id)
			_expect(not id.is_empty() and not EXCLUDED.has(id), "actual menu row eligible: " + id)
			_expect(not String(row.text).contains("$"), "actual row has no price: " + id)
			if id == "m40a1":
				_expect(category == "Sniper Rifles", "actual M40A1 row under sniper category only")
	_expect(row_ids.size() == 12 + Catalog.source_arsenal_ids().size() and row_ids.count("m40a1") == 1 and row_ids.count("de__50") == 1, "actual menu has core and source firearms exactly once")
	var all_text := _visible_text(menu)
	_expect(all_text.contains("EQUIP WEAPON") and not all_text.contains("PURCHASE") and not all_text.contains("CASH") and not all_text.contains("$"), "actual menu is equipment picker, not store")
	for id in ["m4a1", "mark_23", "m40a1", "m9"]:
		menu.purchase_requested.emit(id)
	_expect(game.weapon_controller.carried_loadout == {"primary": "m40a1", "secondary": "m9"}, "canonical selection replaces one primary and one pistol")
	_expect(menu._slots_label.text.contains("Watchman") and menu._slots_label.text.contains("Sentry 9"), "loadout header uses codenames rather than internal IDs")
	menu.purchase_requested.emit("de__50")
	_expect(game.weapon_controller.carried_loadout == {"primary": "m40a1", "secondary": "de__50"}, "restored Desert Eagle equips in the canonical pistol slot")
	_expect(game.weapon_controller.equipped_weapon_display_name == "Sentinel .50", "equipped Desert Eagle uses its codename")
	_expect(game.grenade_inventory == grenades_before, "canonical equipment selection leaves throwables unchanged")
	var before_invalid: Dictionary = game.weapon_controller.carried_loadout.duplicate(true)
	for id: String in EXCLUDED:
		menu.purchase_requested.emit(id)
	_expect(game.weapon_controller.carried_loadout == before_invalid, "invalid menu submissions cannot alter canonical equipment")
	if "--render" in OS.get_cmdline_user_args():
		runtime.open_menu()
		var show_eagle := "--deagle" in OS.get_cmdline_user_args()
		menu._select_category("Pistols" if show_eagle else "Sniper Rifles")
		menu._selected_weapon_id = "de__50" if show_eagle else "m40a1"
		menu._refresh_detail()
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/private/tmp/armory-loadout-selection-deagle.png" if show_eagle else "/private/tmp/armory-loadout-selection-snipers.png")
	game.queue_free()
	await process_frame
	for failure in failures:
		push_error(failure)
	print("ARMORY_LOADOUT_SELECTION_REGRESSION ", "PASS" if failures.is_empty() else "FAIL", " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)


func _visible_text(node: Node) -> String:
	var result := ""
	if node is Label or node is Button:
		result += String(node.text) + "\n"
	for child: Node in node.get_children():
		result += _visible_text(child)
	return result


func _expect(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
