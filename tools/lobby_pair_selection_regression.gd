extends SceneTree

const LobbyState := preload("res://scripts/network/socom_lobby_state.gd")
const MultiplayerHUD := preload("res://scripts/network/socom_multiplayer_hud.gd")


class PairingSessionHarness:
	extends "res://scripts/network/socom_multiplayer_lobby_pairing.gd"

	var lobby_broadcast_count := 0

	func _broadcast_lobby() -> void:
		lobby_broadcast_count += 1


var failures: Array[String] = []
var requested_pair_id := -1


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_team_mode_and_ready_invariants()
	_test_server_owned_pair_validation()
	_test_authoritative_snapshot_round_trip()
	await _test_lobby_selector_presentation()
	_test_canonical_rpc_and_signal_chain()
	if failures.is_empty():
		print("LOBBY_PAIR_SELECTION_REGRESSION PASS")
		quit(0)
		return
	push_error("LOBBY_PAIR_SELECTION_REGRESSION FAIL %s" % str(failures))
	quit(1)


func _test_team_mode_and_ready_invariants() -> void:
	var team_lobby := LobbyState.new()
	_expect(
		team_lobby.lobby_mode == LobbyState.LOBBY_MODE_TEAMS,
		"ordinary lobbies default to team mode"
	)
	team_lobby.set_lobby_mode(LobbyState.LOBBY_MODE_GUNFIGHT_2V2)
	team_lobby.reset()
	_expect(
		team_lobby.lobby_mode == LobbyState.LOBBY_MODE_TEAMS,
		"reset restores ordinary team mode instead of leaking tournament mode"
	)
	team_lobby.add_player(1, "ALPHA")
	team_lobby.add_player(2, "BRAVO")
	team_lobby.set_ready(1, true)
	team_lobby.set_ready(2, true)
	_expect(
		team_lobby.set_team(1, LobbyState.TEAM_BRAVO),
		"server accepts an ordinary waiting-player team move"
	)
	_expect(
		not bool((team_lobby.players[1] as Dictionary).get("ready", true))
		and bool((team_lobby.players[2] as Dictionary).get("ready", false)),
		"accepted team move clears only the moving player's ready flag"
	)
	team_lobby.set_ready(1, true)
	_expect(
		not team_lobby.all_players_ready(),
		"ordinary all-ready remains false when Alpha or Bravo has no player"
	)

	var pair_lobby := LobbyState.new()
	pair_lobby.set_lobby_mode(LobbyState.LOBBY_MODE_GUNFIGHT_2V2)
	for peer_id in range(1, 5):
		pair_lobby.add_player(peer_id, "PAIR %d" % peer_id)
	pair_lobby.set_pair(4, 2)
	for peer_id in range(1, 5):
		pair_lobby.set_ready(peer_id, true)
	_expect(
		pair_lobby.get_combat_ready_pairs().size() == 1,
		"separated ready players do not form a combat-ready duo"
	)
	_expect(
		pair_lobby.set_pair(4, 1),
		"server accepts a ready player moving back into an open duo"
	)
	_expect(
		not bool((pair_lobby.players[4] as Dictionary).get("ready", true)),
		"accepted pair move clears the moving player's ready flag"
	)
	_expect(
		pair_lobby.get_combat_ready_pairs().size() == 1
		and not pair_lobby.can_host_master_start(),
		"tournament pair flow cannot start from readiness carried across a pair move"
	)


func _test_server_owned_pair_validation() -> void:
	var session := PairingSessionHarness.new()
	session.lobby.set_lobby_mode(LobbyState.LOBBY_MODE_GUNFIGHT_2V2)
	for peer_id in range(1, 5):
		session.lobby.add_player(peer_id, "SEAL %d" % peer_id)
	_expect(session.lobby.get_pair_members(0).size() == 2, "automatic admission fills pair zero to capacity")
	_expect(session.lobby.get_pair_members(1).size() == 2, "automatic admission continues into pair one")

	session._server_set_lobby_pair(1, 2)
	_expect(_pair_for(session.lobby, 1) == 2, "server accepts an admitted peer into an open pair")
	_expect(session.lobby_broadcast_count == 1, "accepted pair change broadcasts one authoritative snapshot")
	session._server_set_lobby_pair(3, 2)
	_expect(session.lobby.get_pair_members(2).size() == LobbyState.PAIR_CAPACITY, "server fills a pair to exactly two players")
	_expect(session.lobby_broadcast_count == 2, "second accepted pair change broadcasts once")

	session._server_set_lobby_pair(2, 2)
	_expect(_pair_for(session.lobby, 2) == 0, "server rejects a third player from a full pair")
	_expect(session.lobby_broadcast_count == 2, "rejected full-pair request does not broadcast")
	session._server_set_lobby_pair(2, -1)
	session._server_set_lobby_pair(2, LobbyState.MAX_PAIRS)
	_expect(_pair_for(session.lobby, 2) == 0, "server rejects pair ids outside the authoritative range")
	_expect(session.lobby_broadcast_count == 2, "invalid pair ids do not broadcast")

	session.lobby.phase = LobbyState.PHASE_COUNTDOWN
	session._server_set_lobby_pair(2, 3)
	_expect(_pair_for(session.lobby, 2) == 0, "server rejects pair changes outside the waiting phase")
	_expect(session.lobby_broadcast_count == 2, "phase-rejected pair request does not broadcast")
	session.free()


func _test_authoritative_snapshot_round_trip() -> void:
	var server_lobby := LobbyState.new()
	server_lobby.set_lobby_mode(LobbyState.LOBBY_MODE_GUNFIGHT_2V2)
	server_lobby.add_player(1, "HOST")
	server_lobby.add_player(2, "PARTNER")
	server_lobby.set_pair(1, 4)
	server_lobby.set_pair(2, 4)
	var snapshot: Dictionary = server_lobby.snapshot(2.5)
	var client_lobby := LobbyState.new()
	client_lobby.apply_snapshot(snapshot)
	_expect(_pair_for(client_lobby, 1) == 4 and _pair_for(client_lobby, 2) == 4, "authoritative snapshot preserves duo assignment")
	_expect(is_equal_approx(float(snapshot.get("countdown_seconds", 0.0)), 2.5), "pair snapshot keeps the established lobby countdown contract")


func _test_lobby_selector_presentation() -> void:
	var hud := MultiplayerHUD.new()
	root.add_child(hud)
	await process_frame
	_expect(hud.pair_selector != null, "HUD builds one named duo selector")
	_expect(hud.pair_selector.item_count == LobbyState.MAX_PAIRS, "HUD exposes all authoritative pair ids")

	var lobby := LobbyState.new()
	lobby.set_lobby_mode(LobbyState.LOBBY_MODE_GUNFIGHT_2V2)
	lobby.add_player(1, "ONE")
	lobby.add_player(2, "TWO")
	lobby.add_player(3, "THREE")
	hud.refresh_lobby(lobby, 3, {}, {}, 0.0)
	_expect(
		hud.pair_selector_row.visible and not hud.team_selector_row.visible,
		"tournament lobby exposes duo selection and hides irrelevant team controls"
	)
	_expect(
		hud.lobby_roster_label.text.contains("TOURNAMENT DUOS"),
		"tournament roster groups players under the duo contract"
	)
	var full_pair_index := hud.pair_selector.get_item_index(0)
	var local_pair_index := hud.pair_selector.get_item_index(1)
	_expect(hud.pair_selector.is_item_disabled(full_pair_index), "HUD marks another full duo unavailable")
	_expect(not hud.pair_selector.is_item_disabled(local_pair_index), "HUD keeps the local player's current duo selectable")
	_expect(hud.pair_selector.selected == local_pair_index, "authoritative snapshot selects the local player's duo")
	_expect(hud.lobby_roster_label.text.contains("PAIR 01"), "roster visibly labels each player's duo")

	requested_pair_id = -1
	hud.pair_requested.connect(_capture_pair_request)
	var open_pair_index := hud.pair_selector.get_item_index(2)
	hud.pair_selector.item_selected.emit(open_pair_index)
	_expect(requested_pair_id == 2, "HUD emits pair intent without mutating lobby state")
	_expect(_pair_for(lobby, 3) == 1, "HUD does not own the pair assignment")
	lobby.phase = LobbyState.PHASE_COUNTDOWN
	hud.refresh_lobby(lobby, 3, {}, {}, 1.0)
	_expect(hud.pair_selector.disabled, "HUD disables pair selection outside the waiting phase")
	var team_lobby := LobbyState.new()
	team_lobby.add_player(1, "ALPHA")
	team_lobby.add_player(2, "BRAVO")
	hud.refresh_lobby(team_lobby, 1, {}, {}, 0.0)
	_expect(
		not hud.pair_selector_row.visible and hud.team_selector_row.visible,
		"ordinary lobby exposes team selection and hides tournament duo controls"
	)
	hud.queue_free()
	await process_frame


func _test_canonical_rpc_and_signal_chain() -> void:
	var world_ui_source := FileAccess.get_file_as_string("res://scripts/network/socom_multiplayer_world_ui.gd")
	_expect(world_ui_source.contains("pair_requested.connect(_choose_lobby_pair)"), "canonical HUD signal enters the multiplayer session")
	var pair_layer_source := FileAccess.get_file_as_string("res://scripts/network/socom_multiplayer_lobby_pairing.gd")
	_expect(pair_layer_source.contains("request_lobby_pair.rpc_id(1, pair_id)"), "remote client sends pair intent only to server peer one")
	_expect(pair_layer_source.contains("_server_set_lobby_pair(multiplayer.get_remote_sender_id(), pair_id)"), "server derives pair owner from the RPC sender")

	var scene := load("res://multiplayer_slice.tscn") as PackedScene
	var slice := scene.instantiate() if scene != null else null
	_expect(slice != null, "canonical multiplayer scene instantiates")
	if slice != null:
		var script := slice.get_script() as Script
		var rpc_config: Dictionary = script.call("get_rpc_config") if script != null else {}
		_expect(rpc_config.has("request_lobby_pair"), "canonical runtime registers the reliable pair-selection RPC")
		slice.free()


func _capture_pair_request(pair_id: int) -> void:
	requested_pair_id = pair_id


func _pair_for(lobby, peer_id: int) -> int:
	var entry: Dictionary = lobby.players.get(peer_id, {})
	return int(entry.get("pair_id", -1))


func _expect(condition: bool, message: String) -> void:
	if condition:
		print("LOBBY_PAIR_CHECK PASS ", message)
		return
	failures.append(message)
	push_error("LOBBY_PAIR_CHECK FAIL " + message)
