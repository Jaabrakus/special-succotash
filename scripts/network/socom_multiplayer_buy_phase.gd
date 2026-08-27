extends "res://scripts/network/socom_multiplayer_rounds.gd"

## Pre-round buy window and the server-authoritative weapon economy. The
## window opens while the round is live (Counter-Strike-style buy time): the
## server owns cash, loadouts, and purchase validation; the client menu is a
## prediction view only. Kisak-Strike was used as an architectural reference
## for the buy-period/purchase-validation split; no third-party code runs here.

const Economy := preload("res://scripts/economy/socom_economy_rules.gd")
const Validator := preload("res://scripts/economy/socom_purchase_validator.gd")

const WEAPON_CONFIG_DIRECTORY := "res://config/weapons/"

var peer_cash: Dictionary = {}
var peer_loadout: Dictionary = {}
var server_equipped_weapon_id: Dictionary = {}
var buy_phase_active: bool = false
var buy_time_remaining: float = 0.0
var buy_phase_broadcast_second: int = -1
var local_cash: int = 0
var local_loadout: Dictionary = {"primary": "", "secondary": ""}
var local_buy_window_remaining: float = 0.0
var local_buy_phase_open: bool = false
# Assigned by the world_ui layer; receives phase/cash pushes for the menu.
var buy_menu_driver


func _server_begin_match() -> void:
	super._server_begin_match()
	if not multiplayer.is_server():
		return
	_server_initialize_peer_economy()
	_server_open_buy_phase()


func _server_start_next_round() -> void:
	super._server_start_next_round()
	if not multiplayer.is_server():
		return
	_server_open_buy_phase()


func _server_initialize_peer_economy() -> void:
	for raw_id: Variant in operators.keys():
		var peer_id := int(raw_id)
		peer_cash[peer_id] = Economy.starting_cash()
		peer_loadout[peer_id] = {"primary": "", "secondary": ""}
		server_equipped_weapon_id[peer_id] = _default_weapon_id()
		_send_cash_state(peer_id)


func _default_weapon_id() -> String:
	return String(WeaponContract.load_equipped_config().get("weapon_id", "ak-47"))


func _server_open_buy_phase() -> void:
	if not multiplayer.is_server() or not session_active:
		return
	buy_phase_active = true
	buy_time_remaining = Economy.buy_window_seconds()
	buy_phase_broadcast_second = -1
	_broadcast_buy_phase()
	for raw_id: Variant in operators.keys():
		_send_cash_state(int(raw_id))


func _advance_round_clock(delta: float) -> void:
	if multiplayer.is_server() and buy_phase_active:
		buy_time_remaining = maxf(0.0, buy_time_remaining - delta)
		if buy_time_remaining <= 0.0:
			buy_phase_active = false
			_broadcast_buy_phase()
		else:
			var shown_second := ceili(buy_time_remaining)
			if shown_second != buy_phase_broadcast_second:
				buy_phase_broadcast_second = shown_second
				_broadcast_buy_phase()
	super._advance_round_clock(delta)


func _server_finish_round(winner_team: int, reason: String) -> void:
	if multiplayer.is_server() and winner_team in [0, 1]:
		for raw_id: Variant in operators.keys():
			var peer_id := int(raw_id)
			var operator := operators[raw_id] as SocomNetworkOperator
			if operator == null:
				continue
			var award := (
				Economy.round_award("round_win")
				if operator.team_id == winner_team
				else Economy.round_award("round_loss")
			)
			peer_cash[peer_id] = mini(
				Economy.maximum_cash(),
				int(peer_cash.get(peer_id, 0)) + award
			)
			_send_cash_state(peer_id)
	super._server_finish_round(winner_team, reason)


func _on_operator_eliminated(victim_peer_id: int, attacker_peer_id: int) -> void:
	if (
		multiplayer.is_server()
		and attacker_peer_id != victim_peer_id
		and operators.has(attacker_peer_id)
	):
		var award := Economy.round_award("elimination")
		peer_cash[attacker_peer_id] = mini(
			Economy.maximum_cash(),
			int(peer_cash.get(attacker_peer_id, 0)) + award
		)
		_send_cash_state(attacker_peer_id)
	super._on_operator_eliminated(victim_peer_id, attacker_peer_id)


func _broadcast_buy_phase() -> void:
	receive_buy_phase(buy_phase_active, buy_time_remaining)
	if multiplayer.multiplayer_peer != null and multiplayer.is_server():
		receive_buy_phase.rpc(buy_phase_active, buy_time_remaining)


func _send_cash_state(peer_id: int) -> void:
	var cash := int(peer_cash.get(peer_id, 0))
	if peer_id == multiplayer.get_unique_id():
		receive_cash_state(cash)
	else:
		receive_cash_state.rpc_id(peer_id, cash)


## Server-side per-peer weapon config. Peers without a purchase keep the
## shared equipped profile so existing behaviour is unchanged.
func _weapon_config_for_peer(peer_id: int) -> Dictionary:
	var weapon_id := String(server_equipped_weapon_id.get(peer_id, ""))
	if weapon_id.is_empty():
		return super._weapon_config_for_peer(peer_id)
	var config := WeaponContract.load_config(WEAPON_CONFIG_DIRECTORY + weapon_id + ".json")
	return config if not config.is_empty() else super._weapon_config_for_peer(peer_id)


func _reset_ammo_for_peer(peer_id: int) -> void:
	var values: Dictionary = _weapon_config_for_peer(peer_id).get("ballistics", {})
	server_magazine_ammo[peer_id] = int(values.get("magazine_capacity", 30))
	server_reserve_ammo[peer_id] = int(values.get("reserve_ammo", 90))
	_send_ammo_state(peer_id)


func _server_reload_weapon(peer_id: int) -> void:
	if not multiplayer.is_server() or not operators.has(peer_id):
		return
	var capacity := int(_weapon_config_for_peer(peer_id).get("ballistics", {}).get("magazine_capacity", 30))
	var magazine := int(server_magazine_ammo.get(peer_id, capacity))
	var reserve := int(server_reserve_ammo.get(peer_id, 0))
	var transferred := mini(maxi(0, capacity - magazine), reserve)
	server_magazine_ammo[peer_id] = magazine + transferred
	server_reserve_ammo[peer_id] = reserve - transferred
	_send_ammo_state(peer_id)


func client_request_purchase(weapon_id: String) -> void:
	if multiplayer.is_server():
		_server_handle_purchase(multiplayer.get_unique_id(), weapon_id)
	else:
		submit_purchase.rpc_id(1, weapon_id)


@rpc("any_peer", "call_remote", "reliable")
func submit_purchase(weapon_id: String) -> void:
	if not multiplayer.is_server():
		return
	_server_handle_purchase(multiplayer.get_remote_sender_id(), weapon_id)


func _server_handle_purchase(peer_id: int, weapon_id: String) -> void:
	if not multiplayer.is_server() or not operators.has(peer_id):
		return
	var context := {
		"cash": int(peer_cash.get(peer_id, 0)),
		"loadout": peer_loadout.get(peer_id, {}),
		"phase_open": buy_phase_active,
		"economy_enabled": true,
	}
	var verdict: Dictionary = Validator.validate(weapon_id, context)
	if not bool(verdict.get("ok", false)):
		_send_purchase_result(
			peer_id, false, String(verdict.get("reason", "DENIED")), "", {}
		)
		return
	var clean_id := weapon_id.to_lower().strip_edges()
	var applied: Dictionary = Validator.apply_purchase(
		clean_id, context.get("loadout", {}), int(context.get("cash", 0)), true
	)
	peer_cash[peer_id] = int(applied.get("cash", 0))
	peer_loadout[peer_id] = applied.get("loadout", {})
	server_equipped_weapon_id[peer_id] = clean_id
	var weapon_config := _weapon_config_for_peer(peer_id)
	var ballistics = server_ballistics.get(peer_id)
	if ballistics != null:
		_apply_ballistics_profile(ballistics, weapon_config)
	var composure = server_composure.get(peer_id)
	if composure != null:
		composure.configure_weapon(weapon_config.get("composure", {}))
	_reset_ammo_for_peer(peer_id)
	_send_cash_state(peer_id)
	_send_purchase_result(
		peer_id, true, "", clean_id, peer_loadout[peer_id]
	)


func _send_purchase_result(
	peer_id: int,
	ok: bool,
	reason: String,
	weapon_id: String,
	loadout: Dictionary
) -> void:
	var cash := int(peer_cash.get(peer_id, 0))
	if peer_id == multiplayer.get_unique_id():
		receive_purchase_result(ok, reason, cash, weapon_id, loadout)
	else:
		receive_purchase_result.rpc_id(peer_id, ok, reason, cash, weapon_id, loadout)


@rpc("authority", "call_remote", "reliable")
func receive_purchase_result(
	ok: bool,
	reason: String,
	cash: int,
	weapon_id: String,
	loadout: Dictionary
) -> void:
	local_cash = cash
	if not loadout.is_empty():
		local_loadout = loadout
	if ok and not weapon_id.is_empty():
		_client_equip_weapon(weapon_id)
	if buy_menu_driver != null and buy_menu_driver.has_method("on_purchase_result"):
		buy_menu_driver.on_purchase_result(ok, reason)


@rpc("authority", "call_remote", "reliable")
func receive_buy_phase(open: bool, seconds_remaining: float) -> void:
	local_buy_phase_open = open
	local_buy_window_remaining = maxf(0.0, seconds_remaining)
	if buy_menu_driver != null and buy_menu_driver.has_method("on_buy_phase"):
		buy_menu_driver.on_buy_phase(open, local_buy_window_remaining)


@rpc("authority", "call_remote", "reliable")
func receive_cash_state(cash: int) -> void:
	local_cash = cash


func _client_equip_weapon(weapon_id: String) -> void:
	var config := WeaponContract.load_config(WEAPON_CONFIG_DIRECTORY + weapon_id + ".json")
	if config.is_empty():
		push_warning("Buy menu received unknown weapon config for %s" % weapon_id)
		return
	equipped_config = config
	if (
		local_operator != null
		and local_operator.mannequin != null
		and local_operator.mannequin.has_method("notify_operator_weapon_equipped")
	):
		local_operator.mannequin.call("notify_operator_weapon_equipped", config)
