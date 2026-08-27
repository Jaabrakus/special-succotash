extends "res://scripts/network/socom_multiplayer_buy_phase.gd"

## Gunfight ruleset: short elimination rounds, no mid-round respawn, rotating
## identical loadouts, and an overtime flag that resolves timeouts. Everything
## here is server-authoritative and keyed off the map document's gameplay
## block; demolition and team-deathmatch flows are untouched (every override
## falls through to super when the mode is not gunfight).

const LOADOUT_TABLE_PATH := "res://config/economy/gunfight_loadouts.json"
const RULESET_PATH := "res://config/maps/gunfight_rules.json"

var _overtime_active: bool = false
var _overtime_flag_position: Vector3 = Vector3.ZERO
var _overtime_holder_peer: int = 0
var _overtime_hold_progress: float = 0.0
var _rotation_pairs: Array = []
var _rotation_loaded: bool = false


func _gunfight_enabled() -> bool:
	return String(mission_rules.get("primary_mode", "demolition")) == "gunfight"


func _loadout_mode() -> String:
	return String(mission_rules.get("loadout_mode", "economy"))


func _server_begin_match() -> void:
	super._server_begin_match()
	if not multiplayer.is_server() or not _gunfight_enabled():
		return
	if _loadout_mode() == "rotation":
		_server_apply_round_loadouts()
		for raw_id: Variant in operators.keys():
			_reset_ammo_for_peer(int(raw_id))


func _server_start_next_round() -> void:
	# Loadouts must be assigned BEFORE super: the respawn path resets each
	# peer's ammunition from their assigned weapon's profile.
	if multiplayer.is_server() and _gunfight_enabled() and _loadout_mode() == "rotation":
		_server_apply_round_loadouts()
	super._server_start_next_round()


func _server_open_buy_phase() -> void:
	if _gunfight_enabled() and _loadout_mode() == "rotation":
		# Pure Gunfight has no economy: the menu stays closed and the client
		# strip shows the round countdown instead of a buy window.
		buy_phase_active = false
		buy_time_remaining = 0.0
		_broadcast_buy_phase()
		return
	super._server_open_buy_phase()


func _on_operator_eliminated(victim_peer_id: int, attacker_peer_id: int) -> void:
	if not _gunfight_enabled():
		super._on_operator_eliminated(victim_peer_id, attacker_peer_id)
		return
	if not multiplayer.is_server():
		return
	if attacker_peer_id != victim_peer_id and operators.has(attacker_peer_id):
		var award := Economy.round_award("elimination")
		peer_cash[attacker_peer_id] = mini(
			Economy.maximum_cash(),
			int(peer_cash.get(attacker_peer_id, 0)) + award
		)
		_send_cash_state(attacker_peer_id)
	var victim := operators.get(victim_peer_id) as SocomNetworkOperator
	if victim != null and _team_is_eliminated(victim.team_id):
		_server_finish_round(1 - victim.team_id, "TEAM ELIMINATED")


func _advance_round_clock(delta: float) -> void:
	if not _gunfight_enabled():
		super._advance_round_clock(delta)
		return
	if _overtime_active:
		_server_advance_overtime_flag(delta)
		return
	super._advance_round_clock(delta)


func _server_finish_round(winner_team: int, reason: String) -> void:
	if (
		_gunfight_enabled()
		and winner_team < 0
		and not _overtime_active
		and String(round_rules.get("timeout_result", "draw")) == "overtime_flag"
	):
		_server_start_overtime()
		return
	if _gunfight_enabled():
		_overtime_active = false
	super._server_finish_round(winner_team, reason)


# --- Overtime flag -------------------------------------------------------


func _server_start_overtime() -> void:
	_overtime_active = true
	_overtime_holder_peer = 0
	_overtime_hold_progress = 0.0
	_overtime_flag_position = _pick_overtime_flag_position()
	var message := "OVERTIME  •  CAPTURE THE FLAG"
	_set_status(message)
	receive_match_event(message)


func _pick_overtime_flag_position() -> Vector3:
	if not bomb_pickup_positions.is_empty():
		return bomb_pickup_positions[0]
	var sum := Vector3.ZERO
	var count := 0
	for raw_position: Variant in team_spawn_points.get(0, []):
		sum += Vector3(raw_position)
		count += 1
	for raw_position: Variant in team_spawn_points.get(1, []):
		sum += Vector3(raw_position)
		count += 1
	return sum / maxf(float(count), 1.0) if count > 0 else Vector3(0.0, 0.05, 0.0)


func _server_advance_overtime_flag(delta: float) -> void:
	var radius := float(mission_rules.get("overtime_flag_radius_m", 2.5))
	var hold_target := float(mission_rules.get("overtime_hold_seconds", 3.0))
	var holder := 0
	var best_distance := radius
	for raw_id: Variant in operators.keys():
		var peer_id := int(raw_id)
		var operator := operators[raw_id] as SocomNetworkOperator
		if operator == null or not operator.alive:
			continue
		var distance := operator.global_position.distance_to(_overtime_flag_position)
		if distance <= best_distance:
			best_distance = distance
			holder = peer_id
	if holder != _overtime_holder_peer:
		_overtime_holder_peer = holder
		_overtime_hold_progress = 0.0
		if holder != 0:
			_set_status("OVERTIME  •  SEAL %d IS ON THE FLAG" % holder)
		return
	if holder == 0:
		return
	_overtime_hold_progress += delta
	if _overtime_hold_progress >= hold_target:
		var operator := operators.get(holder) as SocomNetworkOperator
		if operator != null:
			var winning_team := operator.team_id
			_overtime_active = false
			_server_finish_round(winning_team, "FLAG CAPTURED")


# --- Loadout rotation ----------------------------------------------------


func _server_apply_round_loadouts() -> void:
	var pair := _rotation_pair(round_index)
	if pair.is_empty():
		return
	for raw_id: Variant in operators.keys():
		var peer_id := int(raw_id)
		peer_loadout[peer_id] = {
			"primary": String(pair[0]),
			"secondary": String(pair[1]),
		}
		server_equipped_weapon_id[peer_id] = String(pair[0])
	receive_round_loadout(String(pair[0]), String(pair[1]))
	if multiplayer.multiplayer_peer != null and multiplayer.is_server():
		receive_round_loadout.rpc(String(pair[0]), String(pair[1]))


func _rotation_pair(current_round: int) -> Array:
	if not _rotation_loaded:
		_rotation_loaded = true
		_rotation_pairs = _read_rotation_pairs()
	if _rotation_pairs.is_empty():
		return []
	return _rotation_pairs[posmod(current_round - 1, _rotation_pairs.size())]


func _read_rotation_pairs() -> Array:
	if not FileAccess.file_exists(LOADOUT_TABLE_PATH):
		push_warning("Gunfight rotation table missing: %s" % LOADOUT_TABLE_PATH)
		return []
	var file := FileAccess.open(LOADOUT_TABLE_PATH, FileAccess.READ)
	if file == null:
		return []
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary:
		return []
	return (parsed as Dictionary).get("pairs", []) as Array


@rpc("authority", "call_remote", "reliable")
func receive_round_loadout(primary_id: String, secondary_id: String) -> void:
	local_loadout = {"primary": primary_id, "secondary": secondary_id}
	if not primary_id.is_empty():
		_client_equip_weapon(primary_id)


## The Gunfight gameplay block travels inside the map document so every
## admitted peer receives the identical ruleset through receive_server_map.
static func load_ruleset_gameplay() -> Dictionary:
	if not FileAccess.file_exists(RULESET_PATH):
		push_warning("Gunfight ruleset missing: %s" % RULESET_PATH)
		return {}
	var file := FileAccess.open(RULESET_PATH, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary:
		return {}
	return (parsed as Dictionary).get("gameplay", {}) as Dictionary
