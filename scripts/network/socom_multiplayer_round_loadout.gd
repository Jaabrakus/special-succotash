extends "res://scripts/network/socom_multiplayer_rounds.gd"

## Host-owned firearm loadout for each round. One selection is shared by every
## player in an ordinary match, or by all four players in one tournament arena.
## Throwable inventory is deliberately outside this owner and is never reset.

const RoundWeaponRules := preload("res://scripts/network/socom_round_weapon_rules.gd")
const WEAPON_CONFIG_DIRECTORY := "res://config/weapons/"

var server_equipped_weapon_id: Dictionary = {}
var shared_round_weapon_by_key: Dictionary = {}
var previous_round_weapon_by_scope: Dictionary = {}
var round_weapon_match_seed: int = 0
var local_round_weapon_id := ""
var local_round_weapon_number := 0


func _server_begin_match() -> void:
	var should_prepare: bool = (
		multiplayer.is_server()
		and lobby.phase == LobbyStateScript.PHASE_COUNTDOWN
		and RoundWeaponRules.is_enabled()
	)
	var peer_ids: Array[int] = []
	if should_prepare:
		_server_begin_round_weapon_session()
		peer_ids = _sorted_peer_ids(lobby.players.keys())
		_server_prepare_shared_round_weapon("standard", "standard:1", peer_ids)
		_server_publish_round_weapon(peer_ids, 1)
	super._server_begin_match()
	if should_prepare and session_active:
		_server_apply_round_weapon_runtime(peer_ids)


func _server_start_next_round() -> void:
	var peer_ids := _sorted_peer_ids(operators.keys())
	var next_round := round_index + 1
	if multiplayer.is_server() and RoundWeaponRules.is_enabled():
		_server_prepare_shared_round_weapon(
			"standard",
			"standard:%d" % next_round,
			peer_ids
		)
		_server_apply_round_weapon_runtime(peer_ids)
		_server_publish_round_weapon(peer_ids, next_round)
	super._server_start_next_round()


func _server_begin_round_weapon_session() -> void:
	server_equipped_weapon_id.clear()
	shared_round_weapon_by_key.clear()
	previous_round_weapon_by_scope.clear()
	var seed_source := RandomNumberGenerator.new()
	seed_source.randomize()
	round_weapon_match_seed = int(seed_source.randi())


func _server_prepare_shared_round_weapon(
	scope_key: String,
	round_key: String,
	peer_ids: Array[int]
) -> String:
	if not multiplayer.is_server() or not RoundWeaponRules.is_enabled():
		return ""
	var weapon_id := String(shared_round_weapon_by_key.get(round_key, ""))
	if weapon_id.is_empty():
		weapon_id = RoundWeaponRules.choose_shared_weapon(
			round_weapon_match_seed,
			round_key,
			String(previous_round_weapon_by_scope.get(scope_key, ""))
		)
		if weapon_id.is_empty():
			weapon_id = _default_weapon_id()
		shared_round_weapon_by_key[round_key] = weapon_id
		previous_round_weapon_by_scope[scope_key] = weapon_id
	server_equipped_weapon_id.merge(
		RoundWeaponRules.shared_assignment(peer_ids, weapon_id),
		true
	)
	return weapon_id


func _default_weapon_id() -> String:
	return String(WeaponContract.load_equipped_config().get("weapon_id", "ak-47"))


func _weapon_config_for_peer(peer_id: int) -> Dictionary:
	var weapon_id := String(server_equipped_weapon_id.get(peer_id, ""))
	if weapon_id.is_empty():
		return super._weapon_config_for_peer(peer_id)
	var config := WeaponContract.load_config(WEAPON_CONFIG_DIRECTORY + weapon_id + ".json")
	return config if not config.is_empty() else super._weapon_config_for_peer(peer_id)


func _reset_ammo_for_peer(peer_id: int) -> void:
	reload_authority.cancel(peer_id)
	combat_commands.cancel_reload(peer_id)
	var values: Dictionary = _weapon_config_for_peer(peer_id).get("ballistics", {})
	server_magazine_ammo[peer_id] = int(values.get("magazine_capacity", 30))
	server_reserve_ammo[peer_id] = int(values.get("reserve_ammo", 90))
	_send_ammo_state(peer_id)




func _server_apply_round_weapon_runtime(peer_ids: Array[int]) -> void:
	for peer_id: int in peer_ids:
		var weapon_config := _weapon_config_for_peer(peer_id)
		var ballistics = server_ballistics.get(peer_id)
		if ballistics != null:
			_apply_ballistics_profile(ballistics, weapon_config)
		var composure = server_composure.get(peer_id)
		if composure != null:
			composure.configure_weapon(weapon_config.get("composure", {}))
		_reset_ammo_for_peer(peer_id)
		_apply_weapon_visual_to_peer(peer_id, weapon_config)


func _server_publish_round_weapon(peer_ids: Array[int], round_number: int) -> void:
	if not multiplayer.is_server() or peer_ids.is_empty():
		return
	var weapon_id := String(server_equipped_weapon_id.get(peer_ids[0], ""))
	if weapon_id.is_empty():
		return
	for recipient_peer_id: int in peer_ids:
		if recipient_peer_id == multiplayer.get_unique_id():
			receive_round_weapon(weapon_id, round_number, peer_ids)
		else:
			receive_round_weapon.rpc_id(
				recipient_peer_id, weapon_id, round_number, peer_ids
			)


@rpc("authority", "call_remote", "reliable")
func receive_round_weapon(
	weapon_id: String,
	round_number: int,
	affected_peer_ids: Array
) -> void:
	var config := WeaponContract.load_config(WEAPON_CONFIG_DIRECTORY + weapon_id + ".json")
	if config.is_empty():
		push_warning("Round loadout received unknown weapon config for %s" % weapon_id)
		return
	local_round_weapon_id = weapon_id
	local_round_weapon_number = round_number
	for raw_peer_id: Variant in affected_peer_ids:
		server_equipped_weapon_id[int(raw_peer_id)] = weapon_id
	if affected_peer_ids.has(multiplayer.get_unique_id()):
		equipped_config = config
		local_reload_pending = false
	for raw_peer_id: Variant in affected_peer_ids:
		_apply_weapon_visual_to_peer(int(raw_peer_id), config)
	_set_status(
		"ROUND %d LOADOUT  •  %s" % [
			round_number,
			RoundWeaponRules.display_name(weapon_id),
		]
	)


func _spawn_operator_local(peer_id: int, team: int, spawn_position: Vector3) -> void:
	super._spawn_operator_local(peer_id, team, spawn_position)
	_apply_weapon_visual_to_peer(peer_id, _weapon_config_for_peer(peer_id))


func _apply_weapon_visual_to_peer(peer_id: int, config: Dictionary) -> void:
	var operator = operators.get(peer_id)
	if (
		operator == null
		or operator.mannequin == null
		or not operator.mannequin.has_method("notify_operator_weapon_equipped")
	):
		return
	operator.mannequin.call("notify_operator_weapon_equipped", config)


func _sorted_peer_ids(values: Array) -> Array[int]:
	var result: Array[int] = []
	for value: Variant in values:
		result.append(int(value))
	result.sort()
	return result
