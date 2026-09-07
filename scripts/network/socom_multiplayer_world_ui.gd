extends "res://scripts/network/socom_multiplayer_objectives.gd"


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"toggle_fire_mode") and not event.is_echo() \
			and local_operator != null and local_operator.local_input_enabled \
			and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		local_fire_policy.cycle_mode()
		_refresh_player_state()
		get_viewport().set_input_as_handled()
	if event.is_action_pressed("ui_cancel") and not dedicated_server_mode:
		exit_menu.toggle(session_active)
		get_viewport().set_input_as_handled()


func _disconnect_existing_peer() -> void:
	if webrtc_signaling_client != null and is_instance_valid(webrtc_signaling_client):
		webrtc_signaling_client.stop()
		webrtc_signaling_client.queue_free()
	webrtc_signaling_client = null
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	network_peer = multiplayer.multiplayer_peer
	active_network_transport = "offline"
	active_network_endpoint = ""
	_clear_operators()
	lobby.reset()
	session_active = false
	round_active = false
	round_resolution_pending = false
	lobby_countdown_remaining = 0.0
	_reset_demolition_objective()
	if multiplayer_hud != null: multiplayer_hud.clear_host_invite()


func _build_environment() -> void:
	active_map_document = MapDocument.load_active()
	var args := OS.get_cmdline_user_args()
	if args.has("--dedicated-server"):
		var deployment_map_path := String(multiplayer_deployment_profile.get(
			"server_map_document",
			""
		))
		for argument: String in args:
			if argument.begins_with("--mp-map="):
				deployment_map_path = argument.trim_prefix("--mp-map=").strip_edges()
		if (
			deployment_map_path.begins_with("res://config/maps/")
			and deployment_map_path.ends_with(".json")
		):
			var deployment_map := MapDocument.load_path(deployment_map_path)
			if not deployment_map.is_empty():
				active_map_document = deployment_map
			else:
				push_warning("Dedicated map could not be loaded: %s" % deployment_map_path)
		elif not deployment_map_path.is_empty():
			push_warning("Dedicated map path is outside res://config/maps: %s" % deployment_map_path)
	if not active_map_document.is_empty() and bool(active_map_document.get("enabled", true)):
		_apply_multiplayer_map(active_map_document)
		return
	_build_fallback_environment()


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
	_build_objective_beacons()
	_refresh_lobby_ui()


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
		_add_objective_beacon(root, Vector3(raw_position), Color("4fa3ff"), "ALPHA TARGET")
	for raw_position: Variant in bomb_site_positions.get(1, []):
		_add_objective_beacon(root, Vector3(raw_position), Color("ff655e"), "BRAVO TARGET")
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
		var operator: Variant = operators.get(raw_peer_id)
		if operator != null:
			operator.set_bomb_carrier(int(raw_peer_id) == bomb_carrier_peer_id)
	if bomb_visual == null or not is_instance_valid(bomb_visual):
		return
	if bomb_carrier_peer_id != 0:
		bomb_visual.visible = false
		var carrier: Variant = operators.get(bomb_carrier_peer_id)
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


func _build_fallback_environment() -> void:
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color(0.09, 0.11, 0.14)
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color(0.75, 0.78, 0.84)
	settings.ambient_light_energy = 0.82
	environment.environment = settings
	add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, -30.0, 0.0)
	sun.shadow_enabled = true
	add_child(sun)
	_add_box("ArenaFloor", Vector3(22.0, 0.25, 26.0), Vector3(0.0, -0.125, -2.0), Color(0.31, 0.34, 0.38))
	_add_box("CenterCover", Vector3(7.0, 1.15, 0.7), Vector3(0.0, 0.575, -2.0), Color(0.44, 0.40, 0.35))
	_add_box("LeftCover", Vector3(0.7, 2.4, 5.0), Vector3(-5.2, 1.2, -2.0), Color(0.32, 0.36, 0.42))
	_add_box("RightCover", Vector3(0.7, 2.4, 5.0), Vector3(5.2, 1.2, -2.0), Color(0.32, 0.36, 0.42))


func _add_box(node_name: String, size: Vector3, position: Vector3, color: Color) -> void:
	var body := StaticBody3D.new()
	body.name = node_name
	body.position = position
	var mesh := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = size
	mesh.mesh = box_mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	mesh.material_override = material
	body.add_child(mesh)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	add_child(body)


func _build_ui() -> void:
	multiplayer_hud = MultiplayerHUDScript.new()
	multiplayer_hud.name = "MultiplayerHUD"
	add_child(multiplayer_hud)
	multiplayer_hud.host_requested.connect(_request_host_from_hud)
	multiplayer_hud.join_requested.connect(_request_join_from_hud)
	multiplayer_hud.leave_requested.connect(_leave_to_main_menu)
	multiplayer_hud.team_requested.connect(_choose_lobby_team)
	multiplayer_hud.pair_requested.connect(_choose_lobby_pair)
	multiplayer_hud.ready_requested.connect(_toggle_lobby_ready)
	multiplayer_hud.sudden_death_vote_requested.connect(_submit_sudden_death_vote_selection)
	var browser_server_url := String(multiplayer_deployment_profile.get(
		"browser_server_url",
		""
	))
	var query_server_url := DeploymentProfile.browser_query_server_url()
	if not query_server_url.is_empty():
		browser_server_url = query_server_url
	multiplayer_hud.configure_connection_mode(
		OS.has_feature("web"),
		browser_server_url
	)
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
	_refresh_scoreboard()


func _request_host_from_hud() -> void:
	if OS.has_feature("web"):
		host_webrtc_match(DeploymentProfile.webrtc_signaling_url(
			multiplayer_deployment_profile
		))
	else:
		host_match(DEFAULT_PORT)


func _request_join_from_hud(address: String) -> void:
	if DeploymentProfile.is_webrtc_room_code(address):
		join_webrtc_match(
			address,
			DeploymentProfile.webrtc_signaling_url(multiplayer_deployment_profile)
		)
	else:
		join_match(address, DEFAULT_PORT)
	_refresh_player_state()
	_refresh_match_clock()
	_refresh_objective_status()


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
	if reticle != null:
		var profile: Dictionary = equipped_config.get("reticle", {}).duplicate(true)
		profile["fire_interval_seconds"] = _configured_fire_interval()
		if local_camera != null:
			profile["camera_owned_aim"] = true
			local_camera.configure_reticle_climb(profile, String(equipped_config.get("weapon_id", "")))
			profile["functional_aim_climb_enabled"] = local_camera.reticle_climb_enabled()
			reticle.screen_center_override = local_camera.reticle_screen_normalized * get_viewport().get_visible_rect().size
		reticle.apply_profile(profile)
	var current_health := float(local_operator.current_health) if local_operator != null else 0.0
	var maximum_health := float(local_operator.max_health) if local_operator != null else float(
		PlayerGameplayProfile.load_profile().get("max_health", 100.0)
	)
	multiplayer_hud.refresh_player_state(
		current_health,
		maximum_health,
		local_magazine_ammo,
		local_reserve_ammo,
		String(equipped_config.get("display_name", "NO WEAPON")),
		WeaponSlotRules.slot_for_category(String(equipped_config.get("category", ""))),
		local_fire_policy.current_mode,
		local_fire_policy.available_modes,
		local_fire_policy.burst_size
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
	if args.has("--dedicated-server"):
		host_dedicated_server(port)
	elif args.has("--mp-host"):
		host_match(port)
	elif not join_address.is_empty():
		join_match(join_address, port)
	else:
		var launch_mode := String(ProjectSettings.get_setting("socom/session/launch_mode", ""))
		var launcher_address := String(ProjectSettings.get_setting("socom/session/join_address", ""))
		var webrtc_room_code := String(ProjectSettings.get_setting(
			"socom/session/webrtc_room_code",
			""
		))
		var webrtc_signaling_url := String(ProjectSettings.get_setting(
			"socom/session/webrtc_signaling_url",
			DeploymentProfile.webrtc_signaling_url(multiplayer_deployment_profile)
		))
		ProjectSettings.set_setting("socom/session/launch_mode", "")
		ProjectSettings.set_setting("socom/session/join_address", "")
		ProjectSettings.set_setting("socom/session/webrtc_room_code", "")
		ProjectSettings.set_setting("socom/session/webrtc_signaling_url", "")
		if launch_mode == "host":
			host_match(port)
		elif launch_mode == "join":
			join_match(launcher_address, port)
		elif launch_mode == "webrtc_host":
			host_webrtc_match(webrtc_signaling_url)
		elif launch_mode == "webrtc_join":
			join_webrtc_match(webrtc_room_code, webrtc_signaling_url)
		elif launch_mode == "webrtc_tournament":
			join_webrtc_tournament(webrtc_signaling_url)
		elif launch_mode == "dedicated":
			host_dedicated_server(port)
