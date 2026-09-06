extends SceneTree

const Rules := preload("res://scripts/network/socom_round_weapon_rules.gd")
const WeaponCatalog := preload("res://scripts/weapons/socom_weapon_catalog.gd")
const KeyboardProfile := preload("res://scripts/input/socom_keyboard_mapping_profile.gd")
const PlayerProfile := preload("res://scripts/player/player_gameplay_profile.gd")

var failures := 0


func _expect(condition: bool, message: String) -> void:
	if condition:
		print("ROUND_WEAPON_CHECK PASS ", message)
		return
	failures += 1
	push_error("ROUND_WEAPON_CHECK FAIL " + message)


func _init() -> void:
	Rules.reset_cache()
	var profile := Rules.load_profile()
	var pool := Rules.firearm_pool()
	_expect(int(profile.get("schema_version", 0)) == 1, "saved rule schema is current")
	_expect(bool(profile.get("enabled", false)), "shared random round weapon is enabled")
	_expect(pool.size() >= 30, "complete handheld firearm pool is available")

	var categories: Array = profile.get("firearm_categories", [])
	var excluded: Array = profile.get("excluded_weapon_ids", [])
	for weapon_id: String in pool:
		var record := WeaponCatalog.get_weapon(weapon_id)
		_expect(not record.is_empty(), "catalog record exists for " + weapon_id)
		_expect(categories.has(String(record.get("category", ""))), "pool category is a firearm: " + weapon_id)
		_expect(not excluded.has(weapon_id), "pool excludes non-handheld record: " + weapon_id)
		_expect(
			FileAccess.file_exists("res://config/weapons/%s.json" % weapon_id),
			"runtime weapon config exists for " + weapon_id
		)

	var round_one := Rules.choose_shared_weapon(141, "match:round:1", "", pool)
	var replayed_choice := Rules.choose_shared_weapon(141, "match:round:1", "", pool)
	var round_two := Rules.choose_shared_weapon(141, "match:round:2", round_one, pool)
	_expect(not round_one.is_empty(), "host chooses a weapon")
	_expect(round_one == replayed_choice, "one round key resolves one deterministic host choice")
	_expect(round_two != round_one, "consecutive rounds avoid repeating the same weapon")

	var peers: Array[int] = [1, 2, 3, 4]
	var assignment := Rules.shared_assignment(peers, round_one)
	_expect(assignment.size() == peers.size(), "all four 2v2 players receive an assignment")
	for peer_id: int in peers:
		_expect(String(assignment.get(peer_id, "")) == round_one, "peer %d receives the shared weapon" % peer_id)

	var grenades_before: Dictionary = PlayerProfile.load_profile().get("grenade_limits", {}).duplicate(true)
	Rules.choose_shared_weapon(142, "throwable-preservation", round_two, pool)
	var grenades_after: Dictionary = PlayerProfile.load_profile().get("grenade_limits", {}).duplicate(true)
	_expect(grenades_after == grenades_before, "weapon selection leaves throwable limits unchanged")
	for weapon_id: String in pool:
		_expect(
			String(WeaponCatalog.get_weapon(weapon_id).get("category", "")) != "Grenades & Explosives",
			"throwables never enter the firearm pool"
		)

	_expect(&"open_buy_menu" not in KeyboardProfile.ACTION_ORDER, "B buy action is absent from player controls")
	_expect(not KeyboardProfile.DEFAULT_BINDINGS.has(&"open_buy_menu"), "B has no buy-menu binding")
	_expect(&"open_buy_menu" in KeyboardProfile.REMOVED_LEGACY_ACTIONS, "stale saved buy bindings are erased")
	var fire_mode_bindings: Array = KeyboardProfile.DEFAULT_BINDINGS.get(
		&"toggle_fire_mode", []
	)
	_expect(
		fire_mode_bindings.size() == 1
		and int((fire_mode_bindings[0] as Dictionary).get("physical_keycode", 0)) == KEY_B,
		"B remains assigned to fire-mode switching"
	)

	var loadout_source := FileAccess.get_file_as_string(
		"res://scripts/network/socom_multiplayer_round_loadout.gd"
	)
	_expect(loadout_source.contains("_server_prepare_shared_round_weapon"), "host owns round selection")
	_expect(loadout_source.contains("server_equipped_weapon_id.merge"), "one shared assignment feeds server weapons")
	_expect(not loadout_source.contains("submit_purchase"), "purchase RPC is removed")
	_expect(not loadout_source.contains("buy_phase"), "buy-phase state is removed")

	var scene := load("res://multiplayer_slice.tscn") as PackedScene
	var slice := scene.instantiate() if scene != null else null
	_expect(slice != null, "canonical multiplayer scene instantiates")
	if slice != null:
		var script := slice.get_script() as Script
		var rpc_config: Dictionary = script.call("get_rpc_config")
		_expect(rpc_config.has("receive_round_weapon"), "shared weapon uses a reliable authority RPC")
		_expect(not rpc_config.has("submit_purchase"), "canonical RPC surface has no purchase request")
		slice.free()

	if failures == 0:
		print("ROUND_RANDOM_WEAPON_REGRESSION PASS")
		quit(0)
		return
	print("ROUND_RANDOM_WEAPON_REGRESSION FAIL count=", failures)
	quit(1)
