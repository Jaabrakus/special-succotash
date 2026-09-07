extends "res://scripts/network/socom_multiplayer_tournament_runtime.gd"

## Lobby lifecycle only. Existing operators, camera and server weapon still
## own movement, aim and damage. No practice result reaches round scoring.
const WarmupArmory := preload("res://scripts/ui/socom_buy_menu.gd")
const WARMUP_PATH := "res://config/network/lobby_warmup.json"
const ArmoryRules := preload("res://scripts/economy/socom_economy_rules.gd")
var warmup_loadouts: Dictionary = {}
var warmup_saved_ammo: Dictionary = {}
var warmup_profile: Dictionary = {}
var warmup_active := false
var warmup_generation := 0
var warmup_weapon_changed_at: Dictionary = {}
var warmup_playing_local := false
var warmup_armory: Control


func _ready() -> void:
	var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string(WARMUP_PATH))
	warmup_profile = saved if saved is Dictionary else {}
	warmup_profile["respawn_seconds"] = clampf(float(warmup_profile.get("respawn_seconds", 2.0)), 0.5, 10.0)
	warmup_profile["weapon_change_cooldown_seconds"] = clampf(float(warmup_profile.get("weapon_change_cooldown_seconds", 0.5)), 0.25, 5.0)
	super._ready()
	var layer := CanvasLayer.new()
	layer.name = "WarmupArmoryLayer"
	layer.layer = 150
	add_child(layer)
	warmup_armory = WarmupArmory.new()
	warmup_armory.name = "WarmupArmory"
	warmup_armory.economy_enabled = false
	layer.add_child(warmup_armory)
	warmup_armory.purchase_requested.connect(_choose_warmup_weapon)
	warmup_armory.close_requested.connect(_close_warmup_armory)
	multiplayer_hud.warmup_requested.connect(_enter_warmup)


func is_lobby_warmup_active() -> bool:
	return warmup_active and not session_active and lobby.phase != LobbyStateScript.PHASE_PLAYING


func _broadcast_lobby() -> void:
	if multiplayer.is_server() and not session_active and lobby.phase != LobbyStateScript.PHASE_PLAYING and bool(warmup_profile.get("enabled", false)):
		if not warmup_active:
			warmup_active = true
			warmup_generation += 1
		var index := 0
		for peer_id: int in _sorted_peer_ids(lobby.players.keys()):
			if not operators.has(peer_id):
				var spawn := _spawn_for_team(index % 2, index / 2)
				_server_spawn_operator(peer_id, index % 2, spawn)
				spawn_operator.rpc(peer_id, index % 2, spawn)
			index += 1
	super._broadcast_lobby()


func _admit_peer(peer_id: int) -> void:
	super._admit_peer(peer_id)
	if is_lobby_warmup_active() and lobby.players.has(peer_id):
		receive_warmup_loadout.rpc_id(peer_id, server_equipped_weapon_id, warmup_loadouts)


func receive_lobby_state(snapshot: Dictionary) -> void:
	super.receive_lobby_state(snapshot)
	warmup_active = bool(snapshot.get("warmup", false))
	if is_lobby_warmup_active() and local_operator != null:
		local_operator.set_local_input_enabled(warmup_playing_local and not (warmup_armory != null and warmup_armory.visible))
		# The camera captures on creation, which can happen before the first
		# lobby snapshot. Keep menu input usable until the player enters practice.
		if not warmup_playing_local:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	multiplayer_hud.warmup_button.visible = is_lobby_warmup_active()
	multiplayer_hud.warmup_button.disabled = not operators.has(multiplayer.get_unique_id())


func _spawn_operator_local(peer_id: int, team: int, spawn: Vector3) -> void:
	super._spawn_operator_local(peer_id, team, spawn)
	if peer_id == multiplayer.get_unique_id() and warmup_active:
		local_operator.set_local_input_enabled(false)
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _enter_warmup() -> void:
	if not is_lobby_warmup_active() or local_operator == null:
		return
	warmup_playing_local = true
	_show_lobby(false)
	local_operator.set_local_input_enabled(true)
	reticle.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_set_status("WARM-UP • B: WEAPONS • TAB: LOBBY / GREEN UP • practice kills do not count")


func _input(event: InputEvent) -> void:
	if not is_lobby_warmup_active() or not warmup_playing_local:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if not warmup_armory.visible and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			if event.is_action_pressed("equip_primary") or event.is_action_pressed("equip_secondary"):
				var slot := "secondary" if event.is_action_pressed("equip_secondary") else "primary"
				if multiplayer.is_server():
					_server_switch_warmup_slot(multiplayer.get_unique_id(), slot)
				else:
					request_warmup_slot.rpc_id(1, slot)
				get_viewport().set_input_as_handled()
				return
		if event.physical_keycode == KEY_TAB:
			_close_warmup_armory()
			warmup_playing_local = false
			local_operator.set_local_input_enabled(false)
			_show_lobby(true)
			get_viewport().set_input_as_handled()
		elif event.physical_keycode == KEY_B:
			if warmup_armory.visible:
				_close_warmup_armory()
			else:
				warmup_armory.update_state(0, warmup_loadouts.get(multiplayer.get_unique_id(), {}), 0.0, true)
				warmup_armory.open_menu()
				local_operator.set_local_input_enabled(false)
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if warmup_armory != null and warmup_armory.handle_unhandled_input(event):
		get_viewport().set_input_as_handled()
		return
	super._unhandled_input(event)


func _close_warmup_armory() -> void:
	if warmup_armory != null:
		warmup_armory.close_menu()
	if local_operator != null:
		local_operator.set_local_input_enabled(warmup_playing_local or session_active)
	if warmup_playing_local:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _choose_warmup_weapon(weapon_id: String) -> void:
	if multiplayer.is_server():
		_server_choose_warmup_weapon(multiplayer.get_unique_id(), weapon_id)
	else:
		request_warmup_weapon.rpc_id(1, weapon_id)


@rpc("any_peer", "call_remote", "reliable")
func request_warmup_weapon(weapon_id: String) -> void:
	if multiplayer.is_server():
		_server_choose_warmup_weapon(multiplayer.get_remote_sender_id(), weapon_id)


func _server_choose_warmup_weapon(peer_id: int, weapon_id: String) -> bool:
	if not multiplayer.is_server() or not is_lobby_warmup_active() or not lobby.players.has(peer_id) or not operators.has(peer_id):
		return false
	if not operators[peer_id].alive or not RoundWeaponRules.firearm_pool().has(weapon_id):
		return false
	var now := Time.get_ticks_msec() / 1000.0
	if now - float(warmup_weapon_changed_at.get(peer_id, -100.0)) < float(warmup_profile.get("weapon_change_cooldown_seconds", 0.5)):
		return false
	warmup_weapon_changed_at[peer_id] = now
	var old_id := String(_weapon_config_for_peer(peer_id).get("weapon_id", ""))
	var saved_ammo: Dictionary = warmup_saved_ammo.get(peer_id, {})
	saved_ammo[old_id] = {"magazine": int(server_magazine_ammo.get(peer_id, 0)), "reserve": int(server_reserve_ammo.get(peer_id, 0))}
	warmup_saved_ammo[peer_id] = saved_ammo
	var slots: Dictionary = warmup_loadouts.get(peer_id, {"primary": "", "secondary": ""})
	var old_slot := ArmoryRules.slot_for_category(String(_weapon_config_for_peer(peer_id).get("category", "")))
	if String(slots.get(old_slot, "")).is_empty():
		slots[old_slot] = old_id
	var slot := ArmoryRules.slot_for_category(String(ArmoryRules.weapon_record(weapon_id).get("category", "")))
	slots[slot] = weapon_id
	warmup_loadouts[peer_id] = slots
	server_equipped_weapon_id[peer_id] = weapon_id
	_server_apply_round_weapon_runtime([peer_id])
	if saved_ammo.has(weapon_id):
		server_magazine_ammo[peer_id] = int(saved_ammo[weapon_id].magazine)
		server_reserve_ammo[peer_id] = int(saved_ammo[weapon_id].reserve)
		_send_ammo_state(peer_id)
	combat_commands.reset_peer(peer_id, true)
	server_ballistics[peer_id].fire_cooldown = server_ballistics[peer_id].fire_interval
	receive_warmup_loadout({peer_id: weapon_id}, {peer_id: slots})
	receive_warmup_loadout.rpc({peer_id: weapon_id}, {peer_id: slots})
	return true


@rpc("any_peer", "call_remote", "reliable")
func request_warmup_slot(slot: String) -> void:
	if multiplayer.is_server():
		_server_switch_warmup_slot(multiplayer.get_remote_sender_id(), slot)


func _server_switch_warmup_slot(peer_id: int, slot: String) -> bool:
	if slot not in ["primary", "secondary"]:
		return false
	var id := String(warmup_loadouts.get(peer_id, {}).get(slot, ""))
	return not id.is_empty() and _server_choose_warmup_weapon(peer_id, id)


@rpc("authority", "call_remote", "reliable")
func receive_warmup_loadout(assignments: Dictionary, loadouts: Dictionary = {}) -> void:
	if session_active:
		return
	warmup_loadouts.merge(loadouts, true)
	for raw_id: Variant in assignments:
		var peer_id := int(raw_id)
		var weapon_id := String(assignments[raw_id])
		if not RoundWeaponRules.firearm_pool().has(weapon_id):
			continue
		server_equipped_weapon_id[peer_id] = weapon_id
		var config := _weapon_config_for_peer(peer_id)
		_apply_weapon_visual_to_peer(peer_id, config)
		if peer_id == multiplayer.get_unique_id():
			equipped_config = config
			_configure_local_fire_mode()
			local_reload_pending = false
			local_fire_cooldown = _configured_fire_interval()
			_refresh_player_state()
			_close_warmup_armory()


func _shot_can_damage_peer(attacker: int, victim: int) -> bool:
	if is_lobby_warmup_active():
		return attacker != victim and operators.has(attacker) and operators.has(victim)
	return super._shot_can_damage_peer(attacker, victim)


func _on_operator_eliminated(victim: int, attacker: int) -> void:
	if is_lobby_warmup_active():
		if multiplayer.is_server():
			_respawn_warmup(victim, warmup_generation, operators.get(victim))
		return
	super._on_operator_eliminated(victim, attacker)


func _respawn_warmup(peer_id: int, generation: int, victim: Node) -> void:
	await get_tree().create_timer(float(warmup_profile.get("respawn_seconds", 2.0))).timeout
	if not multiplayer.is_server() or not is_lobby_warmup_active() or generation != warmup_generation or not is_instance_valid(victim) or operators.get(peer_id) != victim:
		return
	victim.respawn_at(Vector3(assigned_spawns[peer_id]))
	warmup_saved_ammo.erase(peer_id)
	_reset_ammo_for_peer(peer_id)


func _server_begin_match() -> void:
	if multiplayer.is_server() and lobby.phase == LobbyStateScript.PHASE_COUNTDOWN:
		receive_warmup_end.rpc()
		receive_warmup_end()
	super._server_begin_match()


@rpc("authority", "call_remote", "reliable")
func receive_warmup_end() -> void:
	warmup_loadouts.clear()
	warmup_saved_ammo.clear()
	warmup_active = false
	warmup_generation += 1
	warmup_playing_local = false
	warmup_weapon_changed_at.clear()
	_close_warmup_armory()
	_clear_operators()
	server_equipped_weapon_id.clear()
	pending_snapshots.clear()
	scores.clear()
	local_reload_pending = false
	local_fire_cooldown = 0.0


func _disconnect_existing_peer() -> void:
	warmup_loadouts.clear()
	warmup_saved_ammo.clear()
	warmup_active = false
	warmup_generation += 1
	warmup_playing_local = false
	warmup_weapon_changed_at.clear()
	server_equipped_weapon_id.clear()
	_close_warmup_armory()
	super._disconnect_existing_peer()
