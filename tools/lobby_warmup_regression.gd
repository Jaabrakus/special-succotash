extends SceneTree

const Slice := preload("res://multiplayer_slice.tscn")
const DamageProbe := preload("res://tools/multiplayer_controlled_damage_probe.gd")
var failures: Array[String] = []
var server
var client

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	server = _make_peer("WarmupServer")
	client = _make_peer("WarmupClient")
	_expect(server.host_match(14279) == OK, "host transport starts")
	_expect(client.join_match("127.0.0.1", 14279) == OK, "client connects")
	if not await _wait(func(): return server.operators.size() == 2 and client.operators.size() == 2, 15.0):
		_expect(false, "two admitted players spawn in shared waiting room")
		_finish()
		return
	var client_id: int = client.multiplayer.get_unique_id()
	_expect(server.is_lobby_warmup_active() and client.is_lobby_warmup_active(), "warm-up reaches both peers")
	_expect(not server.session_active and not server.round_active, "practice does not start a round")
	for non_firearm in ["designator", "mk_3-a2", "air_to_ground_missile", "exploding_fuel"]:
		_expect(not server._server_choose_warmup_weapon(client_id, non_firearm), "server rejects non-firearm selection: " + non_firearm)
	client.multiplayer_hud.warmup_button.pressed.emit()
	_expect(client.warmup_playing_local and not client.lobby_panel.visible, "lobby button enters playable practice")
	var key := InputEventKey.new()
	key.physical_keycode = KEY_B
	key.pressed = true
	client._input(key)
	_expect(client.warmup_armory.visible, "B opens free armory")
	client.warmup_armory.purchase_requested.emit("870")
	_expect(await _wait(func(): return String(server.server_equipped_weapon_id.get(client_id, "")) == "870" and String(client.equipped_config.get("weapon_id", "")) == "870", 5.0), "client selection is host approved and replicated")
	_expect(not server._server_choose_warmup_weapon(991, "870"), "unknown peer cannot equip")
	_expect(not server._server_choose_warmup_weapon(1, "../../project"), "unknown weapon/path is rejected")
	server.server_magazine_ammo[client_id] = 3
	await create_timer(0.55).timeout
	client._choose_warmup_weapon("mark_23")
	_expect(await _wait(func(): return String(client.equipped_config.get("weapon_id", "")) == "mark_23", 5.0), "remote pistol selection")
	_expect(client.warmup_loadouts.get(client_id, {}) == {"primary": "870", "secondary": "mark_23"}, "two slots replicated to client")
	await create_timer(0.55).timeout
	client.rpc_id(1, "request_warmup_slot", "primary")
	_expect(await _wait(func(): return String(client.equipped_config.get("weapon_id", "")) == "870", 5.0), "remote switch to retained primary")
	_expect(int(server.server_magazine_ammo[client_id]) == 3, "remote switch does not refill primary")
	await create_timer(0.55).timeout
	client._choose_warmup_weapon("m40a1")
	_expect(await _wait(func(): return String(client.equipped_config.get("weapon_id", "")) == "m40a1", 5.0), "remote M40A1 selection is replicated")
	_expect(client.warmup_loadouts.get(client_id, {}) == {"primary": "m40a1", "secondary": "mark_23"}, "remote sniper replaces primary and preserves pistol")
	_expect(String(client.equipped_config.get("category", "")) == "Sniper Rifles", "remote sniper category uses corrected canonical profile")
	await create_timer(0.55).timeout
	client._choose_warmup_weapon("870")
	_expect(await _wait(func(): return String(client.equipped_config.get("weapon_id", "")) == "870", 5.0), "remote replacement returns to retained shotgun")
	client._refresh_player_state()
	client._present_shot(client_id, Vector3.ZERO, Vector3.FORWARD, false, "MISS")
	_expect(client.local_camera.vrc_height_px > 0.0 and client.reticle.functional_aim_climb_enabled, "remote accepted shot drives camera-owned reticle climb")
	client.local_camera._advance_functional_aim_climb(5.0)
	_expect(server._server_choose_warmup_weapon(1, "870"), "host can choose shotgun")
	# Exercise canonical server shot and real anatomical damage in a clear lane.
	var shooter = server.operators[1]
	var target = server.operators[client_id]
	for operator in [shooter, target]:
		operator.set_physics_process(false)
		operator.velocity = Vector3.ZERO
		operator.rotation.y = 0.0
	shooter.global_position = Vector3(0, 30, 1.75)
	target.global_position = Vector3(0, 30, -1.75)
	# Same-team fire is enabled only in practice.
	target.team_id = shooter.team_id
	await create_timer(0.6).timeout
	shooter.hurtbox_rig.force_pose_update()
	target.hurtbox_rig.force_pose_update()
	await physics_frame
	var torso: Area3D = target.hurtbox_rig.get_region_area(&"TORSO")
	var anchor: Vector3 = server._authoritative_shot_report_anchor(shooter)
	var probe := DamageProbe.new()
	var packet := probe._directed_packet(101, anchor, torso.global_position)
	var before_ammo: int = server.server_magazine_ammo[1]
	server.server_ballistics[1].fire_cooldown = 0.0
	server._server_process_shot(1, packet)
	_expect(int(server.server_magazine_ammo[1]) == before_ammo - 1, "eight pellets consume one shell")
	_expect(target.current_health < target.max_health - 12.0, "multiple pellets damage actual other player")
	var before_scores: Dictionary = server.scores.duplicate(true)
	if target.alive:
		target.take_bullet_damage_region(1000.0, &"TORSO", torso.global_position, Vector3.UP, anchor, 1, 1.0)
	_expect(not target.alive, "practice damage can eliminate")
	_expect(await _wait(func(): return target.alive, 4.0), "practice victim automatically respawns")
	_expect(server.scores == before_scores and server.team_round_wins == {0: 0, 1: 0}, "practice kill leaves scores untouched")
	# Remote client fires through the real RPC, never a local health mutation.
	target.global_position = Vector3(0, 30, -1.75)
	shooter.global_position = Vector3(0, 30, 1.75)
	target.rotation.y = PI
	await create_timer(0.4).timeout
	target.hurtbox_rig.force_pose_update()
	shooter.hurtbox_rig.force_pose_update()
	await physics_frame
	var remote_anchor: Vector3 = server._authoritative_shot_report_anchor(target)
	var host_torso: Area3D = shooter.hurtbox_rig.get_region_area(&"TORSO")
	client.rpc_id(1, "submit_shot", probe._directed_packet(102, remote_anchor, host_torso.global_position))
	_expect(await _wait(func(): return shooter.current_health < shooter.max_health, 3.0),
		"remote client shot damages host through authoritative RPC")
	# A queued warm-up respawn must never heal/replace live operators.
	target.take_bullet_damage_region(1000.0, &"TORSO", torso.global_position, Vector3.UP, anchor, 1, 1.0)
	server.lobby.set_team(1, 0)
	server.lobby.set_team(client_id, 1)
	server.lobby.phase = server.LobbyStateScript.PHASE_COUNTDOWN
	server._server_begin_match()
	_expect(await _wait(func(): return client.session_active, 5.0), "both peers transition into the actual match")
	_expect(not server.is_lobby_warmup_active() and not client.is_lobby_warmup_active(), "warm-up closes on live start")
	_expect(server.local_operator.local_input_enabled and client.local_operator.local_input_enabled,
		"live start restores host and client movement input")
	_expect(not server._server_choose_warmup_weapon(1, "870"), "live round rejects free selection")
	_expect(server.server_equipped_weapon_id[1] == server.server_equipped_weapon_id[client_id], "live players get same random round weapon")
	_expect(server.operators[client_id].current_health == server.operators[client_id].max_health, "live start restores full health")
	var live_target = server.operators[client_id]
	live_target.set_physics_process(false)
	live_target.current_health = 73.0
	await create_timer(2.3).timeout
	_expect(live_target.current_health == 73.0, "old practice respawn cannot heal live player")
	_expect(not server._shot_can_damage_peer(1, 1), "live friendly/self damage remains blocked")
	_finish()

func _make_peer(label: String):
	var viewport := SubViewport.new()
	viewport.name = label
	viewport.own_world_3d = true
	viewport.size = Vector2i(960, 640)
	root.add_child(viewport)
	var api := SceneMultiplayer.new()
	set_multiplayer(api, viewport.get_path())
	var scene := Slice.instantiate()
	scene.name = "Session"
	viewport.add_child(scene)
	return scene

func _wait(predicate: Callable, seconds: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if predicate.call(): return true
		await create_timer(0.05).timeout
	return bool(predicate.call())

func _expect(ok: bool, label: String) -> void:
	print("LOBBY_WARMUP_CHECK ", "PASS " if ok else "FAIL ", label)
	if not ok: failures.append(label)

func _finish() -> void:
	server._disconnect_existing_peer()
	client._disconnect_existing_peer()
	server.get_parent().queue_free()
	client.get_parent().queue_free()
	await process_frame
	print("LOBBY_WARMUP_REGRESSION ", "PASS" if failures.is_empty() else "FAIL ", failures)
	quit(0 if failures.is_empty() else 1)
