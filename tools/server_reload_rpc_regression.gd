extends SceneTree
const Slice := preload("res://multiplayer_slice.tscn")
var failures: Array[String] = []
var server
var client

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	server = _make_peer("ReloadServer")
	client = _make_peer("ReloadClient")
	_expect(server.host_match(14283) == OK, "host starts")
	_expect(client.join_match("127.0.0.1", 14283) == OK, "client connects")
	if not await _wait(func(): return server.operators.size() == 2 and client.operators.size() == 2, 15):
		_expect(false, "two admitted peers")
		_finish()
		return
	var peer_id: int = client.multiplayer.get_unique_id()
	client.multiplayer_hud.warmup_button.pressed.emit()
	_expect(server._server_choose_warmup_weapon(1, "m60e3"), "host heavy weapon")
	_expect(server._server_choose_warmup_weapon(peer_id, "870"), "client shotgun")
	await _wait(func(): return String(client.equipped_config.get("weapon_id", "")) == "870", 3)
	server.server_magazine_ammo[1] = 1
	server.server_magazine_ammo[peer_id] = 1
	server._send_ammo_state(1)
	server._send_ammo_state(peer_id)
	await create_timer(0.2).timeout
	client._request_local_reload()
	server._request_local_reload()
	_expect(await _wait(func(): return server.reload_authority.is_active(peer_id) and server.reload_authority.is_active(1), 2), "input starts both server clocks")
	var started := Time.get_ticks_msec()
	# Falsified local completion is cosmetic, and repeated RPCs do not shorten time.
	client._on_local_reload_animation_completed(&"reload")
	for index in 5: client.rpc_id(1, "submit_reload", true)
	await create_timer(0.3).timeout
	_expect(server.server_magazine_ammo[peer_id] == 1 and server.server_magazine_ammo[1] == 1, "forged finish and repeated starts grant no ammo")
	_expect(server.latest_commands.has(peer_id), "movement commands continue while reloading")
	_expect(await _wait(func(): return not server.reload_authority.is_active(peer_id), 5), "shotgun reload completes")
	var elapsed := float(Time.get_ticks_msec() - started) / 1000.0
	_expect(elapsed >= 4.2 and elapsed < 5.2, "shotgun uses server 4.5-second clock")
	_expect(server.server_magazine_ammo[peer_id] == 12, "per-peer shotgun capacity, not host machine-gun capacity")
	_expect(server.server_magazine_ammo[1] == 1, "machine gun still reloading after shotgun")
	_expect(await _wait(func(): return not server.reload_authority.is_active(1), 3), "machine gun completes independently")
	_expect(server.server_magazine_ammo[1] > 1, "server grants heavy-weapon ammo")
	# Fire intent interrupts a fresh reload, even when not a valid damage packet.
	server.server_magazine_ammo[peer_id] = 1
	client.rpc_id(1, "submit_reload", true)
	_expect(await _wait(func(): return server.reload_authority.is_active(peer_id), 2), "second reload starts")
	client.rpc_id(1, "submit_shot", {"sequence": 999})
	_expect(await _wait(func(): return not server.reload_authority.is_active(peer_id), 2), "fresh fire intent cancels reload")
	_expect(server.server_magazine_ammo[peer_id] == 1, "cancel grants no ammunition")
	client.rpc_id(1, "submit_reload", true)
	_expect(await _wait(func(): return server.reload_authority.is_active(peer_id), 2), "reload can restart after cancel")
	client.rpc_id(1, "submit_reload", false)
	_expect(await _wait(func(): return not server.reload_authority.is_active(peer_id), 2), "explicit cancellation RPC")
	server._server_reload_weapon(peer_id)
	server.operators[peer_id].alive = false
	server._advance_server_reloads()
	_expect(not server.reload_authority.is_active(peer_id), "death discards deadline")
	server.operators[peer_id].alive = true
	server._server_reload_weapon(peer_id)
	server._reset_ammo_for_peer(peer_id)
	_expect(not server.reload_authority.is_active(peer_id), "round/weapon reset discards deadline")
	# Preserve preceding fire requests; the reload starts after they drain.
	server.server_magazine_ammo[peer_id] = 1
	server.set_physics_process(false)
	server.combat_commands.enqueue(peer_id, {"sequence": 1000}, 8)
	server.server_ballistics[peer_id].fire_cooldown = 0.0
	server._server_reload_weapon(peer_id)
	_expect(not server.reload_authority.is_active(peer_id) and server.combat_commands.reload_pending(peer_id), "reload waits behind earlier shot")
	server._advance_pending_server_shots()
	server._advance_pending_server_shots()
	_expect(server.reload_authority.is_active(peer_id), "earlier shot does not cancel later reload request")
	server.reload_authority.cancel(peer_id)
	server.set_physics_process(true)
	server.server_magazine_ammo[peer_id] = 1
	server._server_reload_weapon(peer_id)
	client._disconnect_existing_peer()
	_expect(await _wait(func(): return not server.operators.has(peer_id), 3), "disconnect removes peer")
	_expect(not server.reload_authority.is_active(peer_id), "disconnect clears deadline")
	_finish()

func _make_peer(label: String):
	var viewport := SubViewport.new()
	viewport.name = label
	viewport.own_world_3d = true
	viewport.size = Vector2i(640, 400)
	root.add_child(viewport)
	set_multiplayer(SceneMultiplayer.new(), viewport.get_path())
	var scene := Slice.instantiate()
	scene.name = "Session"
	viewport.add_child(scene)
	return scene

func _wait(predicate: Callable, seconds: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000)
	while Time.get_ticks_msec() < deadline:
		if predicate.call(): return true
		await create_timer(0.025).timeout
	return bool(predicate.call())

func _expect(ok: bool, label: String) -> void:
	print("SERVER_RELOAD_CHECK ", "PASS " if ok else "FAIL ", label)
	if not ok: failures.append(label)

func _finish() -> void:
	server._disconnect_existing_peer()
	client._disconnect_existing_peer()
	for failure in failures: push_error(failure)
	print("SERVER_RELOAD_RPC_REGRESSION ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
