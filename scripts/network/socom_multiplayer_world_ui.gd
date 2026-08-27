extends "res://scripts/network/socom_multiplayer_objectives.gd"

const BuyMenuScript := preload("res://scripts/ui/socom_buy_menu.gd")
const TeamNomenclature := preload("res://scripts/network/socom_team_nomenclature.gd")
var buy_menu: SocomBuyMenu
var _buy_menu_layer: CanvasLayer
var _buy_menu_mouse_was_captured: bool = true
var _buy_menu_window_remaining: float = 0.0
var _buy_menu_dismissed_for_window: bool = false


func _disconnect_existing_peer() -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	_clear_operators()
	lobby.reset()
	session_active = false
	round_active = false
	round_resolution_pending = false
	buy_phase_active = false
	local_buy_phase_open = false
	_overtime_active = false
	_buy_menu_dismissed_for_window = false
	_close_buy_menu(false)
	multiplayer_hud.clear_round_strip()
	lobby_countdown_remaining = 0.0
	_reset_demolition_objective()
	if multiplayer_hud != null: multiplayer_hud.clear_host_invite()


func _build_environment() -> void:
	active_map_document = MapDocument.load_active()
	var launch_mode := String(ProjectSettings.get_setting("socom/session/match_mode", ""))
	if launch_mode == "gunfight":
		# The ruleset travels inside the map document so every admitted peer
		# receives the identical gameplay block through receive_server_map.
		var ruleset := load_ruleset_gameplay()
		if not ruleset.is_empty():
			if active_map_document.is_empty():
				active_map_document = {"map_id": "gunfight_ruleset", "objects": []}
			active_map_document["gameplay"] = ruleset
	ProjectSettings.set_setting("socom/session/match_mode", "")
	# Scale plumbing: the launcher's players-per-side becomes the admission
	# cap (both sides, host included). Tournament lobbies preset a wide side.
	var players_per_side := clampi(int(ProjectSettings.get_setting("socom/session/players_per_side", 8)), 1, 16)
	ProjectSettings.set_setting("socom/session/players_per_side", 8)
	ProjectSettings.set_setting("socom/session/max_match_players", clampi(players_per_side * 2, 2, MAX_PLAYERS))
	ProjectSettings.set_setting(
		"socom/session/room_title",
		"%dV%d %s ROOM" % [players_per_side, players_per_side, "GUNFIGHT" if launch_mode != "" else "DEMOLITION"]
	)
	if not active_map_document.is_empty() and bool(active_map_document.get("enabled", true)):
		_apply_multiplayer_map(active_map_document)
		return
	_apply_team_nomenclature()
	MapRuntime.build_fallback_environment(self)


func _apply_multiplayer_map(document: Dictionary) -> void:
	var normalized := MapDocument.normalize(document)
	if normalized.is_empty():
		return
	active_map_document = normalized
	if active_map_root != null and is_instance_valid(active_map_root):
		active_map_root.queue_free()
	active_map_root = Node3D.new()
	active_map_root.name = "ActiveMultiplayerMap"
	add_child(active_map_root)
	MapAmbience.build_into(active_map_root, active_map_document)
	MapRuntime.build_into(active_map_root, active_map_document)
	var acoustic: Node = get_node_or_null("/root/AcousticPropagation")
	if acoustic != null and acoustic.has_method("configure_map"):
		acoustic.call("configure_map", active_map_document, local_camera)
	var layout := MapGameplay.demolition_layout(active_map_document)
	team_spawn_points[0] = (layout.get("alpha_spawns", []) as Array).duplicate()
	team_spawn_points[1] = (layout.get("bravo_spawns", []) as Array).duplicate()
	bomb_pickup_positions.assign(layout.get("bomb_pickups", []))
	bomb_site_positions[0] = (layout.get("alpha_targets", []) as Array).duplicate()
	bomb_site_positions[1] = (layout.get("bravo_targets", []) as Array).duplicate()
	mission_rules = MapGameplay.mission_rules(active_map_document)
	round_rules = MapGameplay.round_rules(active_map_document)
	_apply_team_nomenclature()
	_build_objective_beacons()
	_refresh_lobby_ui()


## The Square opens with the match: the map's declared axis becomes the team
## words everywhere in-match. The lobby keeps ALPHA/BRAVO — faces are revealed
## when play begins. Never changes team ids.
func _apply_team_nomenclature() -> void:
	var labels := TeamNomenclature.labels_for_document(active_map_document)
	team_labels = {0: labels[0], 1: labels[1]}
	if multiplayer_hud != null:
		multiplayer_hud.set_team_labels(labels[0], labels[1])


func _build_objective_beacons() -> void:
	if active_map_root == null:
		return
	bomb_visual = null
	var root := Node3D.new()
	root.name = "DemolitionObjectiveBeacons"
	active_map_root.add_child(root)
	for position: Vector3 in bomb_pickup_positions:
		_add_objective_beacon(root, position, Color("f4d34f"), "BOMB PICKUP")
	for raw_position: Variant in bomb_site_positions.get(0, []):
		_add_objective_beacon(root, Vector3(raw_position), Color("4fa3ff"), "%s TARGET" % team_labels[0])
	for raw_position: Variant in bomb_site_positions.get(1, []):
		_add_objective_beacon(root, Vector3(raw_position), Color("ff655e"), "%s TARGET" % team_labels[1])
	if not bomb_pickup_positions.is_empty():
		bomb_visual = DemolitionBombScene.instantiate() as Node3D
		bomb_visual.name = "DemolitionBombVisual"
		root.add_child(bomb_visual)
		bomb_world_position = bomb_pickup_positions[0]
		_update_bomb_visual()


func _add_objective_beacon(parent: Node3D, position: Vector3, color: Color, text: String) -> void:
	var marker := Node3D.new()
	marker.position = position
	parent.add_child(marker)
	var visual := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.65
	mesh.bottom_radius = 0.65
	mesh.height = 0.06
	visual.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(color, 0.70)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	visual.material_override = material
	marker.add_child(visual)
	var label := Label3D.new()
	label.text = text
	label.position.y = 0.8
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = color
	label.font_size = 24
	marker.add_child(label)


func _update_bomb_visual() -> void:
	for raw_peer_id: Variant in operators:
		var operator := operators.get(raw_peer_id) as SocomNetworkOperator
		if operator != null:
			operator.set_bomb_carrier(int(raw_peer_id) == bomb_carrier_peer_id)
	if bomb_visual == null or not is_instance_valid(bomb_visual):
		return
	if bomb_carrier_peer_id != 0:
		bomb_visual.visible = false
		var carrier := operators.get(bomb_carrier_peer_id) as SocomNetworkOperator
		if carrier != null:
			bomb_visual.call("set_bomb_state", &"CARRIED", 0.0)
			return
	bomb_visual.visible = true
	bomb_visual.global_position = bomb_world_position + Vector3(0.0, 0.02, 0.0)
	bomb_visual.global_rotation = Vector3.ZERO
	if bomb_planted and bomb_defusing_peer_id != 0:
		var defuse_seconds := maxf(float(mission_rules.get("defuse_time_seconds", 5.0)), 0.1)
		bomb_visual.call(
			"set_bomb_state",
			&"DEFUSING",
			clampf(bomb_defuse_progress / defuse_seconds, 0.0, 1.0)
		)
	elif bomb_planted:
		bomb_visual.call("set_bomb_state", &"PLANTED", 0.0)
	else:
		bomb_visual.call("set_bomb_state", &"AVAILABLE", 0.0)


func _build_ui() -> void:
	multiplayer_hud = MultiplayerHUDScript.new()
	multiplayer_hud.name = "MultiplayerHUD"
	add_child(multiplayer_hud)
	multiplayer_hud.host_requested.connect(func(): host_match(DEFAULT_PORT))
	multiplayer_hud.join_requested.connect(func(address: String): join_match(address, DEFAULT_PORT))
	multiplayer_hud.leave_requested.connect(_leave_to_main_menu)
	multiplayer_hud.team_requested.connect(_choose_lobby_team)
	multiplayer_hud.ready_requested.connect(_toggle_lobby_ready)
	menu_panel = multiplayer_hud.menu_panel
	address_edit = multiplayer_hud.address_edit
	status_label = multiplayer_hud.status_label
	score_label = multiplayer_hud.score_label
	reticle = multiplayer_hud.reticle
	player_state_label = multiplayer_hud.player_state_label
	match_clock_label = multiplayer_hud.match_clock_label
	objective_status_label = multiplayer_hud.objective_status_label
	lobby_panel = multiplayer_hud.lobby_panel
	lobby_roster_label = multiplayer_hud.lobby_roster_label
	lobby_map_label = multiplayer_hud.lobby_map_label
	alpha_team_button = multiplayer_hud.alpha_team_button
	bravo_team_button = multiplayer_hud.bravo_team_button
	ready_button = multiplayer_hud.ready_button
	lobby_status_label = multiplayer_hud.lobby_status_label
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	exit_menu = ExitMenuScript.new() as SocomExitMenu
	exit_menu.name = "InGameExitMenu"
	exit_menu.return_to_launcher_requested.connect(_leave_to_main_menu)
	exit_menu.launch_studio_requested.connect(_leave_to_studio)
	add_child(exit_menu)
	_build_buy_menu()
	multiplayer_hud.build_round_strip()
	# Environment (and its axis) is applied before the UI exists; re-apply the
	# resolved team words so the HUD and strip never show a stale default.
	multiplayer_hud.set_team_labels(team_labels[0], team_labels[1])
	_refresh_scoreboard()
	_refresh_player_state()
	_refresh_match_clock()
	_refresh_objective_status()


func receive_round_state(
	time_remaining: float,
	alpha_rounds: int,
	bravo_rounds: int,
	current_round: int,
	active: bool
) -> void:
	super.receive_round_state(time_remaining, alpha_rounds, bravo_rounds, current_round, active)
	multiplayer_hud.update_round_strip(
		time_remaining,
		alpha_rounds,
		bravo_rounds,
		current_round,
		active,
		int(round_rules.get("rounds_to_win", 6)),
		int(round_rules.get("maximum_rounds", 11)),
		_overtime_active,
		buy_phase_active and local_buy_phase_open,
		local_buy_window_remaining
	)


func _build_buy_menu() -> void:
	if dedicated_server_mode:
		return
	_buy_menu_layer = CanvasLayer.new()
	_buy_menu_layer.layer = 150
	_buy_menu_layer.name = "BuyMenuLayer"
	add_child(_buy_menu_layer)
	buy_menu = BuyMenuScript.new()
	buy_menu.name = "BuyMenu"
	buy_menu.economy_enabled = true
	_buy_menu_layer.add_child(buy_menu)
	buy_menu.purchase_requested.connect(_on_buy_menu_purchase_requested)
	buy_menu.close_requested.connect(_on_buy_menu_close_requested)
	buy_menu_driver = self


func on_buy_phase(open: bool, seconds_remaining: float) -> void:
	_buy_menu_window_remaining = seconds_remaining
	if buy_menu == null:
		return
	if not open:
		_buy_menu_dismissed_for_window = false
		_close_buy_menu(false)
	elif (
		session_active
		and local_operator != null
		and not _buy_menu_dismissed_for_window
		and (exit_menu == null or not exit_menu.is_open())
	):
		_open_buy_menu()


func on_purchase_result(_ok: bool, _reason: String) -> void:
	_refresh_buy_menu_state()


func _open_buy_menu() -> void:
	if buy_menu == null or buy_menu.is_open():
		return
	_buy_menu_mouse_was_captured = Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	_refresh_buy_menu_state()
	buy_menu.open_menu()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _on_buy_menu_close_requested() -> void:
	_close_buy_menu(true)


func _close_buy_menu(dismiss_for_window: bool = false) -> void:
	if dismiss_for_window and local_buy_phase_open:
		_buy_menu_dismissed_for_window = true
	if buy_menu == null or not buy_menu.is_open():
		return
	buy_menu.close_menu()
	Input.mouse_mode = (
		Input.MOUSE_MODE_CAPTURED
		if _buy_menu_mouse_was_captured
		else Input.MOUSE_MODE_VISIBLE
	)


func _refresh_buy_menu_state() -> void:
	if buy_menu == null:
		return
	buy_menu.update_state(
		local_cash,
		local_loadout,
		_buy_menu_window_remaining,
		local_buy_phase_open
	)


func _on_buy_menu_purchase_requested(weapon_id: String) -> void:
	client_request_purchase(weapon_id)
	_refresh_buy_menu_state()


func _unhandled_input(event: InputEvent) -> void:
	# Session owns the escape/exit-menu branch; only swallow events the buy
	# menu actually consumes so that contract stays intact.
	if buy_menu != null and session_active:
		if buy_menu.is_open():
			if event.is_action_pressed(&"open_buy_menu"):
				_close_buy_menu(true)
				get_viewport().set_input_as_handled()
				return
			if buy_menu.handle_unhandled_input(event):
				get_viewport().set_input_as_handled()
				return
		elif (
			event.is_action_pressed(&"open_buy_menu")
			and local_buy_phase_open
			and local_operator != null
			and (exit_menu == null or not exit_menu.is_open())
		):
			_open_buy_menu()
			get_viewport().set_input_as_handled()
			return
	super._unhandled_input(event)


func _leave_to_main_menu() -> void:
	_disconnect_existing_peer()
	get_tree().change_scene_to_file("res://game_launcher.tscn")


func _leave_to_studio() -> void:
	_disconnect_existing_peer()
	var navigation := get_node_or_null("/root/StudioNavigation")
	if navigation != null:
		navigation.call("activate")
		navigation.call("open_home")
	else:
		get_tree().change_scene_to_file("res://game_launcher.tscn")
func _show_lobby(enabled: bool) -> void:
	if enabled:
		_buy_menu_dismissed_for_window = false
		_close_buy_menu(false)
	if multiplayer_hud == null:
		return
	multiplayer_hud.show_lobby(enabled, session_active)
	_refresh_lobby_ui()
func _refresh_lobby_ui() -> void:
	if multiplayer_hud == null:
		return
	multiplayer_hud.refresh_lobby(
		lobby,
		multiplayer.get_unique_id(),
		active_map_document,
		round_rules,
		lobby_countdown_remaining
	)
func _set_status(message: String) -> void:
	if multiplayer_hud != null:
		multiplayer_hud.set_status(message)
func _refresh_scoreboard() -> void:
	if multiplayer_hud == null:
		return
	multiplayer_hud.refresh_scoreboard(mission_rules, team_round_wins, scores)
	var alpha_list: Array[Dictionary] = []
	var bravo_list: Array[Dictionary] = []
	var local_id := multiplayer.get_unique_id()
	for raw_id: Variant in lobby.players.keys():
		var peer_id := int(raw_id)
		var p_entry: Dictionary = lobby.players[raw_id]
		var team: int = int(p_entry.get("team", 0))
		var p_name: String = String(p_entry.get("display_name", "SEAL %d" % peer_id))
		if peer_id == local_id:
			p_name += " (YOU)"
		var is_alive := true
		if operators.has(peer_id):
			var op = operators[peer_id]
			if op != null:
				is_alive = bool(op.alive)
		var p_kills: int = int(scores.get(peer_id, 0))
		var item := {
			"name": p_name,
			"alive": is_alive,
			"kills": p_kills,
			"deaths": 0,
			"ping": 20,
		}
		(alpha_list if team == 0 else bravo_list).append(item)
	var bomb_msg := "SATCHEL BOMB AT SPAWN"
	if bomb_planted:
		bomb_msg = "BOMB ARMED  •  DEFUSE IN PROGRESS"
	elif bomb_carrier_peer_id != 0:
		bomb_msg = "SEAL %d HAS BOMB" % bomb_carrier_peer_id
	multiplayer_hud.update_roster_data(
		alpha_list,
		bravo_list,
		int(team_round_wins.get(0, 0)),
		int(team_round_wins.get(1, 0)),
		round_time_remaining,
		bomb_msg,
		bomb_planted
	)
	_refresh_player_state()
func _refresh_match_clock() -> void:
	if multiplayer_hud != null:
		multiplayer_hud.refresh_match_clock(round_index, round_time_remaining, session_active)
func _refresh_objective_status() -> void:
	if multiplayer_hud == null:
		return
	multiplayer_hud.refresh_objective_status({
		"session_active": session_active,
		"pickup_positions_empty": bomb_pickup_positions.is_empty(),
		"bomb_planted": bomb_planted,
		"defuse_time_seconds": mission_rules.get("defuse_time_seconds", 5.0),
		"defuse_progress": bomb_defuse_progress,
		"defusing_peer_id": bomb_defusing_peer_id,
		"fuse_remaining": bomb_fuse_remaining,
		"carrier_peer_id": bomb_carrier_peer_id,
		"plant_time_seconds": mission_rules.get("plant_time_seconds", 5.0),
		"plant_progress": bomb_plant_progress,
	})
func _refresh_player_state() -> void:
	if multiplayer_hud == null:
		return
	var current_health := float(local_operator.current_health) if local_operator != null else 0.0
	var maximum_health := float(local_operator.max_health) if local_operator != null else float(
		PlayerGameplayProfile.load_profile().get("max_health", 100.0)
	)
	multiplayer_hud.refresh_player_state(
		current_health,
		maximum_health,
		local_magazine_ammo,
		local_reserve_ammo
	)
func _ensure_input_map() -> void:
	KeyboardMappingProfile.apply_project_mapping()


func _ensure_action(action: StringName) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, 0.25)


func _remove_key_binding(action: StringName, keycode: Key) -> void:
	if not InputMap.has_action(action):
		return
	for existing_event in InputMap.action_get_events(action):
		if existing_event is InputEventKey and existing_event.physical_keycode == keycode:
			InputMap.action_erase_event(action, existing_event)


func _add_key_action(action: StringName, keycode: Key) -> void:
	_ensure_action(action)
	for event in InputMap.action_get_events(action):
		if event is InputEventKey and event.physical_keycode == keycode:
			return
	var key := InputEventKey.new()
	key.physical_keycode = keycode
	InputMap.action_add_event(action, key)


func _apply_command_line_mode() -> void:
	var args := OS.get_cmdline_user_args()
	var port := DEFAULT_PORT
	var join_address := ""
	for argument in args:
		if argument.begins_with("--mp-port="):
			port = int(argument.trim_prefix("--mp-port="))
		elif argument.begins_with("--mp-join="):
			join_address = argument.trim_prefix("--mp-join=")
	if args.has("--mp-host"):
		host_match(port)
	elif not join_address.is_empty():
		join_match(join_address, port)
	else:
		var launch_mode := String(ProjectSettings.get_setting("socom/session/launch_mode", ""))
		var launcher_address := String(ProjectSettings.get_setting("socom/session/join_address", ""))
		ProjectSettings.set_setting("socom/session/launch_mode", "")
		ProjectSettings.set_setting("socom/session/join_address", "")
		if launch_mode == "host":
			host_match(port)
		elif launch_mode == "join":
			join_match(launcher_address, port)
		elif launch_mode == "dedicated":
			host_dedicated_server(port)
