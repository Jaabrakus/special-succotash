extends "res://tools/server_reload_rpc_regression.gd"

var second_client

func _run() -> void:
	server = _make_peer("DedicatedReloadServer")
	client = _make_peer("DedicatedReloadClientA")
	second_client = _make_peer("DedicatedReloadClientB")
	_expect(server.host_dedicated_server(14285) == OK, "real dedicated host starts")
	# Isolate cloud registration only: no Supabase writes in this localhost proof.
	server.server_backend.queue_free()
	server.server_backend = null
	_expect(client.join_match("ws://127.0.0.1:14285", 14285) == OK, "remote A connects via WebSocket")
	_expect(second_client.join_match("ws://127.0.0.1:14285", 14285) == OK, "remote B connects via WebSocket")
	if not await _wait(func(): return server.operators.size() == 2 and client.operators.size() == 2 and second_client.operators.size() == 2, 15):
		_expect(false, "dedicated server admits two playable clients")
		_finish()
		return
	_expect(server.local_operator == null and not server.operators.has(1), "dedicated host has no player advantage")
	var id: int = client.multiplayer.get_unique_id()
	_expect(server._server_choose_warmup_weapon(id, "870"), "dedicated host selects per-peer weapon")
	await _wait(func(): return String(client.equipped_config.get("weapon_id", "")) == "870", 3)
	server.server_magazine_ammo[id] = 1
	server._send_ammo_state(id)
	await create_timer(0.2).timeout
	client._request_local_reload()
	_expect(await _wait(func(): return server.reload_authority.is_active(id), 2), "client input reaches dedicated reload owner")
	await create_timer(0.3).timeout
	_expect(server.server_magazine_ammo[id] == 1, "dedicated host denies early refill")
	_expect(await _wait(func(): return server.server_magazine_ammo[id] == 12 and client.local_magazine_ammo == 12, 5), "dedicated deadline grants and replicates ammo")
	print("DEDICATED_RELOAD_REGRESSION ", "PASS" if failures.is_empty() else "FAIL")
	_finish()

func _finish() -> void:
	if second_client != null:
		second_client._disconnect_existing_peer()
	super._finish()
