extends "res://tools/lobby_warmup_regression.gd"
## Two in-process SceneMultiplayer peers; actual request/authority/receive path.
const Catalog := preload("res://scripts/weapons/socom_weapon_catalog.gd")

func _run() -> void:
	server = _make_peer("SourceArsenalServer")
	client = _make_peer("SourceArsenalClient")
	var hosted: bool = server.host_match(14289) == OK
	_expect(hosted, "host transport starts")
	if not hosted:
		_finish()
		return
	var joined: bool = client.join_match("127.0.0.1", 14289) == OK
	_expect(joined, "client connects")
	if not joined:
		_finish()
		return
	if not await _wait(func(): return server.operators.size() == 2 and client.operators.size() == 2, 20.0):
		_expect(false, "both peers admit and spawn")
		_finish()
		return
	var client_id: int = client.multiplayer.get_unique_id()
	_expect(not server._server_choose_warmup_weapon(991, "s2_m4a1"), "unknown peer rejected")
	for forbidden in ["designator", "mgl", "../../project", "m3_12_gauge"]:
		_expect(not server._server_choose_warmup_weapon(client_id, forbidden), "hidden/unsupported ID rejected " + forbidden)
	var count := 0
	for id: String in Catalog.source_arsenal_ids():
		# Clear only test cooldown between cases; verify real throttling below.
		server.warmup_weapon_changed_at[client_id] = -100.0
		client.warmup_armory.purchase_requested.emit(id)
		_expect(await _wait(func(): return client.equipped_config.get("weapon_id", "") == id and server.server_equipped_weapon_id.get(client_id, "") == id, 5.0), "RPC equipment delivery " + id)
		for peer in [server, client]:
			var actor: Node = peer.operators[client_id]
			var driver: Node = actor.get_node("Mannequin/ProductionAnimation")
			_expect(driver.equipped_weapon_config.weapon_id == id, "network actor presentation " + id)
			var saved_pose: Dictionary = Catalog.get_weapon(id).support_hand_pose
			var actual_pose: Dictionary = driver.weapon_node.get_meta("support_hand_pose", {})
			for key in ["finger_basis", "source_support_contact", "support_regrip_seconds"]:
				_expect(actual_pose.get(key) == saved_pose.get(key), "network actor saved grip policy " + id + "/" + key)
			var mesh: Node = driver.weapon_node.find_child("WeaponMesh", true, false)
			_expect(mesh != null and mesh.get_meta("source_model", "") == Catalog.get_weapon(id).source_asset.model, "network actor source geometry " + id)
		var config: Dictionary = server._weapon_config_for_peer(client_id)
		_expect(server.server_magazine_ammo[client_id] == config.ballistics.magazine_capacity, "authoritative ammo profile " + id)
		_expect(is_equal_approx(server.server_ballistics[client_id].fire_interval, 60.0 / config.ballistics.fire_rate_rpm), "authoritative cadence " + id)
		count += 1
		print("SOURCE_ARSENAL_NETWORK_EQUIP ", id)
	server.warmup_weapon_changed_at[client_id] = Time.get_ticks_msec() / 1000.0
	_expect(not server._server_choose_warmup_weapon(client_id, "s2_m4a1"), "real cooldown still enforced")
	server.session_active = true
	_expect(not server._server_choose_warmup_weapon(client_id, "s2_m4a1"), "live match selection remains locked")
	print("SOURCE_WEAPON_ARSENAL_NETWORK ", "PASS" if failures.is_empty() else "FAIL", " weapons=", count, " ", failures)
	_finish()
