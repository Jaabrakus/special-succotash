extends "res://scripts/network/socom_multiplayer_world_ui.gd"

## Tournament mode: the Square over the existing slice. The host owns a
## SocomTournamentModel; clients submit squad intents through RPCs and render
## pushed snapshots. Registration runs in the lobby; pods play as Gunfight
## matches (mode plumbing transmutes "tournament" into the gunfight ruleset)
## with only the pod's two squads spawned — everyone else watches the bracket.
##
## In the lore (docs/SQUARE_DESIGN_LANGUAGE.md) the final's winner occupies
## the center: the champion is the Tenet.

const TournamentModel := preload("res://scripts/tournament/socom_tournament_model.gd")
const TournamentPanelScript := preload("res://scripts/ui/socom_tournament_lobby_panel.gd")

var tournament_active: bool = false
var tournament = null
var local_tournament_snapshot: Dictionary = {}
var tournament_panel: SocomTournamentLobbyPanel
var _live_pod_number: int = 0


func _build_environment() -> void:
	# Transmute the launcher's tournament mode into the gunfight ruleset merge
	# the world layer already performs, and remember the tournament flag.
	if String(ProjectSettings.get_setting("socom/session/match_mode", "")) == "tournament":
		tournament_active = true
		ProjectSettings.set_setting("socom/session/match_mode", "gunfight")
		ProjectSettings.set_setting("socom/session/players_per_side", 16)
	super._build_environment()


func _build_ui() -> void:
	super._build_ui()
	if dedicated_server_mode:
		return
	tournament_panel = TournamentPanelScript.new()
	tournament_panel.name = "TournamentLobby"
	add_child(tournament_panel)
	tournament_panel.create_squad_requested.connect(_on_create_squad)
	tournament_panel.join_squad_requested.connect(_on_join_squad)
	tournament_panel.ready_toggled.connect(_on_squad_ready)
	tournament_panel.lock_bracket_requested.connect(_on_lock_bracket)


func _show_lobby(enabled: bool) -> void:
	if not tournament_active:
		super._show_lobby(enabled)
		return
	# Tournament mode replaces the two-faction lobby with the Square.
	if multiplayer_hud != null:
		multiplayer_hud.show_lobby(false, false)
	if tournament_panel != null:
		tournament_panel.show_panel(enabled)
	if not enabled:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _advance_lobby_countdown(delta: float) -> void:
	# Pods begin from the bracket, not from lobby readiness.
	if tournament_active:
		return
	super._advance_lobby_countdown(delta)


# --- Client intents (any_peer -> host) -------------------------------------


func _on_create_squad(squad_name: String, house: String) -> void:
	submit_squad_registration.rpc_id(1, squad_name, house)


func _on_join_squad(squad_id: String) -> void:
	submit_squad_join.rpc_id(1, squad_id)


func _on_squad_ready(ready: bool) -> void:
	submit_squad_ready.rpc_id(1, ready)


func _on_lock_bracket() -> void:
	submit_bracket_lock.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func submit_squad_registration(squad_name: String, house: String) -> void:
	if not multiplayer.is_server() or not tournament_active or tournament == null:
		return
	tournament.register_squad(squad_name, multiplayer.get_remote_sender_id(), house)
	_broadcast_tournament_state()


@rpc("any_peer", "call_remote", "reliable")
func submit_squad_join(squad_id: String) -> void:
	if not multiplayer.is_server() or not tournament_active or tournament == null:
		return
	tournament.join_squad(squad_id, multiplayer.get_remote_sender_id())
	_broadcast_tournament_state()


@rpc("any_peer", "call_remote", "reliable")
func submit_squad_ready(ready: bool) -> void:
	if not multiplayer.is_server() or not tournament_active or tournament == null:
		return
	var peer_id := multiplayer.get_remote_sender_id()
	for raw_squad: Variant in tournament.squads.values():
		var squad := raw_squad as Dictionary
		if (squad.get("members", []) as Array).has(peer_id):
			tournament.set_squad_ready(String(squad.get("id", "")), ready)
	_broadcast_tournament_state()


@rpc("any_peer", "call_remote", "reliable")
func submit_bracket_lock() -> void:
	if not multiplayer.is_server() or not tournament_active or tournament == null:
		return
	if tournament.state != TournamentModel.STATE_REGISTRATION:
		return
	var locked: Dictionary = tournament.lock_registration()
	if bool(locked.get("ok", false)):
		_broadcast_tournament_state()
		_open_next_tournament_pod()


@rpc("authority", "call_remote", "reliable")
func receive_tournament_state(snapshot: Dictionary) -> void:
	local_tournament_snapshot = snapshot
	if not tournament_active:
		# Joining clients learn the session is a Square from the first push.
		tournament_active = true
		if not session_active:
			_show_lobby(true)
	if tournament_panel != null:
		tournament_panel.update_state(snapshot, multiplayer.get_unique_id())


func _broadcast_tournament_state() -> void:
	if tournament == null:
		return
	var snapshot: Dictionary = tournament.snapshot()
	receive_tournament_state(snapshot)
	if multiplayer.multiplayer_peer != null and multiplayer.is_server():
		receive_tournament_state.rpc(snapshot)


# --- Pod lifecycle (host) ---------------------------------------------------


func _open_next_tournament_pod() -> void:
	if not multiplayer.is_server() or not tournament_active or tournament == null:
		return
	for raw_pod: Variant in tournament.pods:
		var pod := raw_pod as Dictionary
		if String(pod.get("state", "")) != "pending":
			continue
		if String(pod.get("squad_a", "")).is_empty() or String(pod.get("squad_b", "")).is_empty():
			continue
		_begin_tournament_pod(int(pod.get("number", 0)))
		return


func _begin_tournament_pod(pod_number: int) -> void:
	var opened: Dictionary = tournament.open_pod(pod_number)
	if not bool(opened.get("ok", false)):
		return
	_live_pod_number = pod_number
	# Previous pod's operators were despawned when it reported; spawn only
	# this pod's two squads.
	var member_index := {0: 0, 1: 0}
	for faction: int in [0, 1]:
		var squad_id := String(opened.get("faction_%d" % faction, ""))
		for raw_squad: Variant in tournament.squads.values():
			var squad := raw_squad as Dictionary
			if String(squad.get("id", "")) != squad_id:
				continue
			for raw_member: Variant in (squad.get("members", []) as Array):
				var peer_id := int(raw_member)
				if not lobby.players.has(peer_id):
					continue
				var spawn_position := _spawn_for_team(faction, int(member_index[faction]))
				member_index[faction] = int(member_index[faction]) + 1
				_server_spawn_operator(peer_id, faction, spawn_position)
				spawn_operator.rpc(peer_id, faction, spawn_position)
	round_index = 1
	round_time_remaining = float(round_rules.get("time_limit_seconds", 40))
	last_round_clock_second = -1
	round_resolution_pending = false
	session_active = true
	round_active = true
	_reset_demolition_objective()
	receive_match_started(round_index, round_time_remaining)
	receive_match_started.rpc(round_index, round_time_remaining)
	_broadcast_tournament_state()
	var message := "THE SQUARE  •  POD %d" % pod_number
	_set_status(message)
	receive_match_event.rpc(message)


func _server_return_to_lobby(last_winner_team: int) -> void:
	if not tournament_active or tournament == null or _live_pod_number == 0:
		super._server_return_to_lobby(last_winner_team)
		return
	# The finished pod reports into the bracket; the Square continues.
	var pod := _pod_by_number(_live_pod_number)
	var winner_squad := String((pod.get("factions", {}) as Dictionary).get(last_winner_team, "")) if last_winner_team in [0, 1] else ""
	var result: Dictionary = tournament.report_pod_result(_live_pod_number, winner_squad)
	_live_pod_number = 0
	_broadcast_tournament_state()
	super._server_return_to_lobby(last_winner_team)
	if bool(result.get("complete", false)):
		var champion := String(tournament.champion())
		var message := "TENET HELD BY %s" % champion
		_set_status(message)
		receive_match_event.rpc(message)
		_show_lobby(true)
		return
	await get_tree().create_timer(4.0).timeout
	if not multiplayer.is_server() or session_active:
		return
	_open_next_tournament_pod()


func _pod_by_number(number: int) -> Dictionary:
	if tournament == null:
		return {}
	for raw_pod: Variant in tournament.pods:
		var pod := raw_pod as Dictionary
		if int(pod.get("number", 0)) == number:
			return pod
	return {}


func host_match(port: int = DEFAULT_PORT) -> Error:
	var error: Error = super.host_match(port)
	if error == OK and multiplayer.is_server() and tournament_active:
		tournament = TournamentModel.new()
		_broadcast_tournament_state()
	return error
