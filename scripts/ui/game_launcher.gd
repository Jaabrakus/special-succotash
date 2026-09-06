extends Control

const MULTIPLAYER_SCENE := "res://multiplayer_slice.tscn"
const MAP_EDITOR_SCENE := "res://map_creation_lab.tscn"
const TRAINING_RANGE_SCENE := "res://main.tscn"
const ANIMATION_STUDIO_SCENE := "res://animation_library_lab.tscn"

const MapDocument := preload("res://scripts/maps/socom_map_document.gd")
const KeyboardProfile := preload("res://scripts/input/socom_keyboard_mapping_profile.gd")
const ControlsGuideScript := preload("res://scripts/ui/socom_controls_guide.gd")
const PlayableResourceWarmup := preload("res://scripts/runtime/playable_resource_warmup.gd")
const EloRatingSystemScript := preload("res://scripts/network/socom_elo_rating_system.gd")
const MatchmakingDirectoryClient := preload(
	"res://scripts/network/socom_matchmaking_directory_client.gd"
)
const SessionCompatibility := preload(
	"res://scripts/network/socom_session_compatibility.gd"
)
const DeploymentProfile := preload(
	"res://scripts/network/socom_multiplayer_deployment_profile.gd"
)

var address_edit: LineEdit
var map_selector: OptionButton
var map_entries: Array[Dictionary] = []
var status_label: Label
var identity_label: Label
var controls_guide: SocomControlsGuide
var restricted_web_build := false
var play_open_in_progress := false

# Main views
var menu_column: VBoxContainer
var server_browser_panel: VBoxContainer
var leaderboard_panel: VBoxContainer

# Server directory UI elements
var server_list: ItemList
var server_browser_status_label: Label
var server_browser_join_button: Button
var server_browser_refresh_button: Button
var server_rows: Array[Dictionary] = []

# Leaderboard UI elements
var leaderboard_title_label: Label
var leaderboard_table_label: RichTextLabel
var your_rank_label: RichTextLabel
var leaderboard_refresh_btn: Button

var current_user_profile: Dictionary = {}
var multiplayer_deployment_profile: Dictionary = {}
var browser_server_url := ""
var webrtc_signaling_url := ""
var matchmaking_directory = null
var directory_request_in_progress := false


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	multiplayer_deployment_profile = DeploymentProfile.load_profile()
	restricted_web_build = (
		OS.has_feature("web")
		or OS.has_feature("restricted_web")
		or OS.get_cmdline_user_args().has("--restricted-web-preview")
	)
	browser_server_url = String(multiplayer_deployment_profile.get(
		"browser_server_url",
		""
	))
	var query_server_url := DeploymentProfile.browser_query_server_url()
	if not query_server_url.is_empty():
		browser_server_url = query_server_url
	webrtc_signaling_url = DeploymentProfile.webrtc_signaling_url(
		multiplayer_deployment_profile
	)
	KeyboardProfile.apply_project_mapping()
	MapDocument.ensure_active_map_in_library()
	_build_ui()
	_build_settings()
	_refresh_map_selector()
	if restricted_web_build:
		status_label.text = "Train solo, join the 32-player tournament, or view the global leaderboard."
	call_deferred("_initialize_guest_identity")


func _build_ui() -> void:
	var background := ColorRect.new()
	background.color = Color("10151d")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(760.0, 740.0)
	center.add_child(panel)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, 24)
	panel.add_child(margin)

	var root_column := VBoxContainer.new()
	root_column.add_theme_constant_override("separation", 8)
	margin.add_child(root_column)

	var title := Label.new()
	title.text = "141"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 36)
	title.add_theme_color_override("font_color", Color("8bc5ae"))
	root_column.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "GUNFIGHT OPERATIONS"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_color_override("font_color", Color("aab4c4"))
	root_column.add_child(subtitle)

	identity_label = Label.new()
	identity_label.name = "GuestPlayerIdentity"
	identity_label.text = "PLAYER: Connecting guest…"
	identity_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	identity_label.add_theme_color_override("font_color", Color("7df0ad"))
	root_column.add_child(identity_label)
	root_column.add_child(HSeparator.new())

	# =========================================================================
	# 1. MAIN MENU COLUMN
	# =========================================================================
	menu_column = VBoxContainer.new()
	menu_column.add_theme_constant_override("separation", 8)
	root_column.add_child(menu_column)

	var quick_match_button := _add_primary_action(
		menu_column,
		"JOIN 32-PLAYER TOURNAMENT" if restricted_web_build else "QUICK MATCH",
		_quick_match
	)
	quick_match_button.name = "QuickMatch"
	if not restricted_web_build:
		var browse_servers_button := _add_primary_action(
			menu_column,
			"BROWSE SERVERS",
			_open_server_browser
		)
		browse_servers_button.name = "BrowseServers"
		var host_game_button := _add_primary_action(
			menu_column,
			"HOST PRIVATE MATCH",
			_host_private_match
		)
		host_game_button.name = "HostGame"
		var create_room_button := _add_primary_action(
			menu_column,
			"CREATE 32P TOURNAMENT ROOM",
			_open_tournament_room
		)
		create_room_button.name = "CreateTournamentRoom"
	var leaderboard_button := _add_primary_action(
		menu_column,
		"GLOBAL LEADERBOARD",
		_open_leaderboard
	)
	leaderboard_button.name = "GlobalLeaderboard"
	var training_button := _add_primary_action(
		menu_column,
		"TRAINING GROUNDS" if restricted_web_build else "TRAINING RANGE",
		_open_training_range
	)
	training_button.name = "TrainingRange"
	training_button.tooltip_text = "Practice solo. Press B near spawn to choose a weapon. No server required."

	if not restricted_web_build:
		var join_row := HBoxContainer.new()
		join_row.add_theme_constant_override("separation", 8)
		menu_column.add_child(join_row)
		address_edit = LineEdit.new()
		address_edit.name = "JoinGameAddress"
		address_edit.placeholder_text = "Invite code or server address"
		address_edit.text = "127.0.0.1"
		address_edit.custom_minimum_size.y = 42.0
		address_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		join_row.add_child(address_edit)
		var join_button := Button.new()
		join_button.name = "JoinGame"
		join_button.text = "JOIN ROOM"
		join_button.custom_minimum_size = Vector2(130.0, 42.0)
		join_button.pressed.connect(_join_match)
		join_row.add_child(join_button)

		map_selector = OptionButton.new()
		map_selector.name = "HostMapSelector"
		map_selector.custom_minimum_size.y = 40.0
		map_selector.tooltip_text = "Choose which saved map this match will use."
		map_selector.item_selected.connect(_on_map_selected)
		menu_column.add_child(map_selector)
		_add_primary_action(menu_column, "MAP EDITOR", _open_map_editor)
		var studio_button := _add_primary_action(
			menu_column,
			"STUDIO LABS",
			_open_animation_studio
		)
		studio_button.name = "AnimationStudio"

	menu_column.add_child(HSeparator.new())
	var utility_row := HBoxContainer.new()
	utility_row.alignment = BoxContainer.ALIGNMENT_CENTER
	utility_row.add_theme_constant_override("separation", 10)
	menu_column.add_child(utility_row)

	var settings_button := Button.new()
	settings_button.name = "PlayerSettingsButton"
	settings_button.text = "SETTINGS / KEY BINDS"
	settings_button.pressed.connect(_open_settings)
	utility_row.add_child(settings_button)
	if not restricted_web_build:
		var quit_button := Button.new()
		quit_button.text = "QUIT"
		quit_button.pressed.connect(get_tree().quit)
		utility_row.add_child(quit_button)

	# =========================================================================
	# 2. LIVE SERVER DIRECTORY
	# =========================================================================
	server_browser_panel = VBoxContainer.new()
	server_browser_panel.name = "ServerBrowserPanel"
	server_browser_panel.add_theme_constant_override("separation", 8)
	server_browser_panel.visible = false
	root_column.add_child(server_browser_panel)

	var browser_title := Label.new()
	browser_title.text = "ACTIVE MATCH SERVERS"
	browser_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	browser_title.add_theme_font_size_override("font_size", 20)
	browser_title.add_theme_color_override("font_color", Color("8bc5ae"))
	server_browser_panel.add_child(browser_title)

	var browser_columns := Label.new()
	browser_columns.text = "SERVER  •  MODE / MAP  •  REGION  •  PLAYERS"
	browser_columns.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	browser_columns.add_theme_color_override("font_color", Color("aeb9c9"))
	server_browser_panel.add_child(browser_columns)

	server_list = ItemList.new()
	server_list.name = "ServerList"
	server_list.custom_minimum_size.y = 360.0
	server_list.select_mode = ItemList.SELECT_SINGLE
	server_list.item_selected.connect(_on_server_selected)
	server_browser_panel.add_child(server_list)

	server_browser_status_label = Label.new()
	server_browser_status_label.name = "ServerBrowserStatus"
	server_browser_status_label.text = "Refresh to query the authoritative service directory."
	server_browser_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	server_browser_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	server_browser_status_label.add_theme_color_override("font_color", Color("aeb9c9"))
	server_browser_panel.add_child(server_browser_status_label)

	var server_actions := HBoxContainer.new()
	server_actions.add_theme_constant_override("separation", 8)
	server_browser_panel.add_child(server_actions)
	server_browser_refresh_button = Button.new()
	server_browser_refresh_button.name = "RefreshServers"
	server_browser_refresh_button.text = "REFRESH"
	server_browser_refresh_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	server_browser_refresh_button.pressed.connect(_refresh_server_browser)
	server_actions.add_child(server_browser_refresh_button)
	server_browser_join_button = Button.new()
	server_browser_join_button.name = "JoinSelectedServer"
	server_browser_join_button.text = "JOIN SELECTED"
	server_browser_join_button.disabled = true
	server_browser_join_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	server_browser_join_button.pressed.connect(_join_selected_server)
	server_actions.add_child(server_browser_join_button)
	var leave_browser_button := Button.new()
	leave_browser_button.text = "← BACK"
	leave_browser_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	leave_browser_button.pressed.connect(_close_server_browser)
	server_actions.add_child(leave_browser_button)

	# =========================================================================
	# 3. GLOBAL PRAETORIAN LEADERBOARD PANEL (WITH STICKY YOUR RANK CARD)
	# =========================================================================
	leaderboard_panel = VBoxContainer.new()
	leaderboard_panel.add_theme_constant_override("separation", 8)
	leaderboard_panel.visible = false
	root_column.add_child(leaderboard_panel)

	leaderboard_title_label = Label.new()
	leaderboard_title_label.text = "★ GLOBAL PRAETORIAN LEADERBOARD ★"
	leaderboard_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	leaderboard_title_label.add_theme_font_size_override("font_size", 20)
	leaderboard_title_label.add_theme_color_override("font_color", Color("f2cf6a"))
	leaderboard_panel.add_child(leaderboard_title_label)

	leaderboard_table_label = RichTextLabel.new()
	leaderboard_table_label.bbcode_enabled = true
	leaderboard_table_label.custom_minimum_size.y = 300.0
	leaderboard_table_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	leaderboard_table_label.add_theme_font_size_override("normal_font_size", 14)
	leaderboard_panel.add_child(leaderboard_table_label)

	var your_rank_card := PanelContainer.new()
	your_rank_card.custom_minimum_size.y = 52.0
	leaderboard_panel.add_child(your_rank_card)
	var rank_margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		rank_margin.add_theme_constant_override("margin_%s" % side, 8)
	your_rank_card.add_child(rank_margin)
	your_rank_label = RichTextLabel.new()
	your_rank_label.bbcode_enabled = true
	your_rank_label.add_theme_font_size_override("normal_font_size", 14)
	rank_margin.add_child(your_rank_label)

	var lb_actions_row := HBoxContainer.new()
	lb_actions_row.add_theme_constant_override("separation", 8)
	leaderboard_panel.add_child(lb_actions_row)

	leaderboard_refresh_btn = Button.new()
	leaderboard_refresh_btn.name = "RefreshLeaderboard"
	leaderboard_refresh_btn.text = "🔄 REFRESH LEADERBOARD"
	leaderboard_refresh_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	leaderboard_refresh_btn.pressed.connect(_fetch_and_render_leaderboard)
	lb_actions_row.add_child(leaderboard_refresh_btn)

	var leave_lb_btn := Button.new()
	leave_lb_btn.text = "← BACK TO MAIN MENU"
	leave_lb_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	leave_lb_btn.pressed.connect(_on_leave_leaderboard)
	lb_actions_row.add_child(leave_lb_btn)

	status_label = Label.new()
	status_label.text = (
		"32 PLAYERS  •  16 DUOS  •  8 SIMULTANEOUS 2v2 ARENAS"
		if restricted_web_build
		else "Direct-IP 32-Player Room • Praetorian Ladder • UDP 14141"
	)
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.add_theme_color_override("font_color", Color("7f8b9c"))
	root_column.add_child(status_label)


func _add_primary_action(parent: VBoxContainer, label_text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.name = label_text.to_snake_case().to_pascal_case()
	button.text = label_text
	button.custom_minimum_size.y = 48.0
	button.add_theme_font_size_override("font_size", 17)
	button.pressed.connect(callback)
	parent.add_child(button)
	return button


func _build_settings() -> void:
	controls_guide = ControlsGuideScript.new() as SocomControlsGuide
	controls_guide.name = "PublicPlayerSettings"
	controls_guide.show_hint_button = false
	controls_guide.public_player_copy = true
	add_child(controls_guide)


func _open_settings() -> void:
	controls_guide.set_guide_visible(true)


func _initialize_guest_identity() -> void:
	var service := get_node_or_null("/root/SupabaseClient")
	if service == null or not bool(service.call("is_configured")):
		current_user_profile = {"display_name": "Local Guest", "elo_rating": 0, "rank_tier": "TIRO III", "tier_kills": 0, "tier_deaths": 0}
		identity_label.text = "PLAYER: Local Guest  •  TIRO III [0 ELO]"
		return
	var result: Dictionary = await service.call("ensure_guest_session")
	if not bool(result.get("ok", false)):
		identity_label.text = "PLAYER: Local Guest  •  cloud offline"
		return
	var name_str := String(result.get("display_name", "Guest"))
	var prof_res: Dictionary = await service.call("get_player_profile")
	if bool(prof_res.get("ok", false)):
		current_user_profile = prof_res.get("profile", {})
		var elo := int(current_user_profile.get("elo_rating", 0))
		var rank := String(current_user_profile.get("rank_tier", "TIRO III"))
		identity_label.text = "PLAYER: %s  •  %s [%d ELO]" % [name_str, rank, elo]
	else:
		current_user_profile = {"display_name": name_str, "elo_rating": 0, "rank_tier": "TIRO III", "tier_kills": 0, "tier_deaths": 0}
		identity_label.text = "PLAYER: %s  •  TIRO III [0 ELO]" % name_str


func _open_tournament_room() -> void:
	if not _select_host_map():
		return
	ProjectSettings.set_setting("socom/session/tournament_mode", true)
	ProjectSettings.set_setting("socom/session/launch_mode", "host")
	ProjectSettings.set_setting("socom/session/join_address", "")
	_collect_and_open(MULTIPLAYER_SCENE)


func _host_private_match() -> void:
	if restricted_web_build:
		return
	if not _select_host_map():
		return
	_configure_private_host_session()
	_collect_and_open(MULTIPLAYER_SCENE)


func _configure_private_host_session() -> void:
	# The launcher selects the established native listen-server path. The
	# canonical multiplayer session still owns the peer, lobby, shots, damage,
	# and disconnect lifecycle.
	ProjectSettings.set_setting("socom/session/tournament_mode", false)
	ProjectSettings.set_setting("socom/session/launch_mode", "host")
	ProjectSettings.set_setting("socom/session/join_address", "")


func _ensure_matchmaking_directory():
	if matchmaking_directory == null:
		matchmaking_directory = MatchmakingDirectoryClient.new(
			get_node_or_null("/root/SupabaseClient")
		)
	return matchmaking_directory


func _quick_match() -> void:
	if restricted_web_build:
		if not _configure_browser_tournament_session():
			return
		_collect_and_open(MULTIPLAYER_SCENE)
		return
	if directory_request_in_progress:
		return
	directory_request_in_progress = true
	status_label.text = "Finding an official 32-player tournament with room…"
	var directory = _ensure_matchmaking_directory()
	var result: Dictionary = await directory.find_quick_match(
		"auto",
		{},
		-1.0,
		restricted_web_build,
		"gunfight_2v2",
		32
	)
	directory_request_in_progress = false
	if not bool(result.get("ok", false)):
		status_label.text = "Quick Match unavailable: %s" % String(
			result.get("message", "No compatible server is online.")
		)
		return
	var server: Dictionary = result.get("server", {})
	status_label.text = "Joining %s…" % String(server.get("name", "match server"))
	_join_directory_endpoint(result.get("endpoint", {}))


func _configure_browser_tournament_session() -> bool:
	if not browser_server_url.begins_with("wss://"):
		status_label.text = "Tournament unavailable: secure dedicated server is not configured."
		return false
	ProjectSettings.set_setting("socom/session/tournament_mode", true)
	ProjectSettings.set_setting("socom/session/launch_mode", "join")
	ProjectSettings.set_setting("socom/session/join_address", browser_server_url)
	ProjectSettings.set_setting("socom/session/webrtc_room_code", "")
	ProjectSettings.set_setting("socom/session/webrtc_signaling_url", "")
	return true


func _open_server_browser() -> void:
	menu_column.visible = false
	leaderboard_panel.visible = false
	server_browser_panel.visible = true
	_refresh_server_browser()


func _close_server_browser() -> void:
	server_browser_panel.visible = false
	menu_column.visible = true


func _refresh_server_browser() -> void:
	if directory_request_in_progress:
		return
	directory_request_in_progress = true
	server_rows.clear()
	server_list.clear()
	server_browser_join_button.disabled = true
	server_browser_refresh_button.disabled = true
	server_browser_status_label.text = "Querying live regions and server heartbeats…"
	var directory = _ensure_matchmaking_directory()
	var region_result: Dictionary = await directory.list_healthy_regions()
	if not bool(region_result.get("ok", false)):
		_finish_server_refresh(String(region_result.get("message", "Service directory unavailable.")))
		return
	for raw_region: Variant in region_result.get("regions", []):
		if raw_region is not Dictionary:
			continue
		var region := raw_region as Dictionary
		var region_key := String(region.get("region_key", ""))
		var server_result: Dictionary = await directory.list_healthy_servers(region_key)
		if not bool(server_result.get("ok", false)):
			continue
		for raw_server: Variant in server_result.get("servers", []):
			if raw_server is not Dictionary:
				continue
			var server := raw_server as Dictionary
			if (
				String(server.get("game_build", "")) != SessionCompatibility.local_build()
				or int(server.get("protocol_version", 0)) != SessionCompatibility.PROTOCOL_VERSION
			):
				continue
			var endpoint: Dictionary = MatchmakingDirectoryClient.join_endpoint(
				server,
				restricted_web_build
			)
			if not bool(endpoint.get("ok", false)):
				continue
			server["_join_endpoint"] = endpoint
			server_rows.append(server)
	server_rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_region := String(a.get("region", ""))
		var b_region := String(b.get("region", ""))
		if a_region != b_region:
			return a_region < b_region
		return int(a.get("current_players", 0)) > int(b.get("current_players", 0))
	)
	for server: Dictionary in server_rows:
		server_list.add_item(_format_server_row(server))
	_finish_server_refresh(
		"%d compatible live server%s." % [
			server_rows.size(),
			"" if server_rows.size() == 1 else "s",
		]
		if not server_rows.is_empty()
		else "No fresh compatible server currently has capacity."
	)


func _finish_server_refresh(message: String) -> void:
	directory_request_in_progress = false
	server_browser_refresh_button.disabled = false
	server_browser_status_label.text = message


func _format_server_row(server: Dictionary) -> String:
	var ruleset: Dictionary = server.get("ruleset", {})
	var mode := String(server.get(
		"mode_key",
		ruleset.get("mode", ruleset.get("primary_mode", "gunfight"))
	))
	var map_name := String(server.get(
		"map_key",
		ruleset.get("map_name", server.get("map_name", "rotation"))
	))
	return "%s  •  %s / %s  •  %s  •  %d/%d" % [
		String(server.get("name", "SOCOM SERVER")),
		mode.replace("_", " ").to_upper(),
		map_name,
		String(server.get("region", "unknown")).to_upper(),
		int(server.get("current_players", 0)),
		int(server.get("capacity", 0)),
	]


func _on_server_selected(index: int) -> void:
	server_browser_join_button.disabled = index < 0 or index >= server_rows.size()


func _join_selected_server() -> void:
	var selected := server_list.get_selected_items()
	if selected.is_empty():
		server_browser_status_label.text = "Select a server first."
		return
	var index := int(selected[0])
	if index < 0 or index >= server_rows.size():
		server_browser_status_label.text = "That server is no longer available. Refresh the list."
		return
	_join_directory_endpoint(server_rows[index].get("_join_endpoint", {}))


func _join_directory_endpoint(endpoint: Dictionary) -> void:
	if not bool(endpoint.get("ok", true)):
		status_label.text = String(endpoint.get("message", "That server cannot be joined."))
		return
	var join_address := String(endpoint.get("url", "")).strip_edges()
	if join_address.is_empty():
		join_address = String(endpoint.get("address", "")).strip_edges()
		var port := int(endpoint.get("port", 0))
		if port > 0 and join_address.find(":") < 0:
			join_address = "%s:%d" % [join_address, port]
	if join_address.is_empty():
		status_label.text = "The selected server did not publish a usable endpoint."
		return
	ProjectSettings.set_setting(
		"socom/session/tournament_mode",
		String(endpoint.get("mode_key", "demolition")) == "gunfight_2v2"
	)
	ProjectSettings.set_setting("socom/session/launch_mode", "join")
	ProjectSettings.set_setting("socom/session/join_address", join_address)
	_collect_and_open(MULTIPLAYER_SCENE)


func _open_leaderboard() -> void:
	menu_column.visible = false
	server_browser_panel.visible = false
	leaderboard_panel.visible = true
	_fetch_and_render_leaderboard()


func _on_leave_leaderboard() -> void:
	leaderboard_panel.visible = false
	menu_column.visible = true


func _fetch_and_render_leaderboard() -> void:
	leaderboard_table_label.text = "[center][color=#aeb9c9]Fetching Global Praetorian Leaderboard...[/color][/center]"

	var my_name := String(current_user_profile.get("display_name", "You"))
	var my_elo := int(current_user_profile.get("elo_rating", 0))
	var my_rank := String(current_user_profile.get("rank_tier", "TIRO III"))
	var my_tk := int(current_user_profile.get("tier_kills", 0))
	var my_td := int(current_user_profile.get("tier_deaths", 0))
	var my_kd_str := "%.2f" % (float(my_tk) / float(maxi(1, my_td))) if my_td > 0 else "%d.00" % my_tk
	var my_tourneys := int(current_user_profile.get("tournaments_won", 0))

	your_rank_label.text = "[center][b][color=#f2cf6a]YOUR STANDING:[/color]  [color=#7df0ad]%s[/color]  •  [color=#6eb6ff]%s[/color]  •  [color=#70f59b]%d ELO[/color]  •  TIER K/D: [color=#ffffff]%s[/color]  •  TOURNEYS WON: [color=#f2cf6a]%d[/color][/b][/center]" % [
		my_name, my_rank, my_elo, my_kd_str, my_tourneys
	]

	var service := get_node_or_null("/root/SupabaseClient")
	var rows: Array = []
	if service == null or not bool(service.call("is_configured")):
		leaderboard_table_label.text = "[center][color=#ffad73]Global leaderboard unavailable: cloud service is not configured.[/color][/center]"
		return
	var lb_res: Dictionary = await service.call("get_gunfight_leaderboard", 50)
	if not bool(lb_res.get("ok", false)):
		leaderboard_table_label.text = "[center][color=#ffad73]Global leaderboard unavailable: %s[/color][/center]" % String(
			lb_res.get("message", "the service did not return standings.")
		)
		return
	rows = lb_res.get("leaderboard", [])
	if rows.is_empty():
		leaderboard_table_label.text = "[center][color=#aeb9c9]No ranked tournament results yet.[/color][/center]"
		return

	var header := "[cell][b]# [/b][/cell][cell][b]OPERATOR[/b][/cell][cell][b]PRAETORIAN RANK[/b][/cell][cell][b]ELO[/b][/cell][cell][b]TIER K/D[/b][/cell][cell][b]WIN %[/b][/cell][cell][b]TOURNEYS[/b][/cell]"
	var cells: Array[String] = [header]
	var rank_idx := 1
	for entry in rows:
		var h_name: String = String(entry.get("display_name", entry.get("handle", "Operator")))
		var r_tier: String = String(entry.get("rank_tier", "TIRO III"))
		var r_elo: int = int(entry.get("elo_rating", 0))
		var r_kd: float = float(entry.get("current_tier_kd", 0.0))
		var r_win: float = float(entry.get("win_rate_percentage", 0.0))
		var r_tour: int = int(entry.get("tournaments_won", 0))

		var is_me := (h_name == my_name)
		var color_tag := "#7df0ad" if is_me else ("#f2cf6a" if rank_idx == 1 else "#d8dde6")

		cells.append("[cell][color=%s]#%02d[/color][/cell]" % [color_tag, rank_idx])
		cells.append("[cell][color=%s]%s[/color][/cell]" % [color_tag, h_name + (" (YOU)" if is_me else "")])
		cells.append("[cell][color=%s]%s[/color][/cell]" % [color_tag, r_tier])
		cells.append("[cell][color=%s]%d[/color][/cell]" % [color_tag, r_elo])
		cells.append("[cell][color=%s]%.2f[/color][/cell]" % [color_tag, r_kd])
		cells.append("[cell][color=%s]%.1f%%[/color][/cell]" % [color_tag, r_win])
		cells.append("[cell][color=%s]%d[/color][/cell]" % [color_tag, r_tour])
		rank_idx += 1

	leaderboard_table_label.text = "[table=7]\n%s\n[/table]" % "\n".join(cells)


func _open_map_editor() -> void:
	get_tree().change_scene_to_file(MAP_EDITOR_SCENE)


func _open_animation_studio() -> void:
	var navigation := get_node_or_null("/root/StudioNavigation")
	if navigation != null:
		if not bool(navigation.get("active")):
			navigation.call("activate")
		navigation.call("open_scene", ANIMATION_STUDIO_SCENE)
	else:
		get_tree().change_scene_to_file(ANIMATION_STUDIO_SCENE)


func _open_training_range() -> void:
	if not restricted_web_build and not _select_host_map():
		return
	if restricted_web_build:
		ProjectSettings.set_setting("socom/session/selected_map_document", MapDocument.load_path(
			String(multiplayer_deployment_profile.get("server_map_document", MapDocument.ACTIVE_MAP_PATH))
		))
	# Training must not inherit a previous tournament/join intent. Its canonical
	# runtime consumes the bundled map and weapon profiles without cloud access.
	ProjectSettings.set_setting("socom/session/tournament_mode", false)
	ProjectSettings.set_setting("socom/session/launch_mode", "")
	ProjectSettings.set_setting("socom/session/join_address", "")
	ProjectSettings.set_setting("socom/session/webrtc_room_code", "")
	ProjectSettings.set_setting("socom/session/public_training", true)
	_collect_and_open(TRAINING_RANGE_SCENE)


func _refresh_map_selector() -> void:
	if map_selector == null:
		return
	map_entries = MapDocument.list_library_maps()
	map_selector.clear()
	var active_map_id := String(MapDocument.load_active().get("map_id", ""))
	var active_index := -1
	for entry: Dictionary in map_entries:
		map_selector.add_item(String(entry.get("name", "Untitled Tactical Map")))
		if String(entry.get("map_id", "")) == active_map_id:
			active_index = map_selector.item_count - 1
	map_selector.disabled = map_entries.is_empty()
	if map_entries.is_empty():
		map_selector.add_item("Create a map in Map Editor first")
	elif active_index >= 0:
		map_selector.select(active_index)


func _on_map_selected(index: int) -> void:
	if index < 0 or index >= map_entries.size():
		return
	var entry: Dictionary = map_entries[index]
	var selected := MapDocument.select_library_map(String(entry.get("map_id", "")))
	if selected.is_empty():
		status_label.text = "That map could not be selected. Return to Map Editor and save it again."
		return
	status_label.text = "%s selected for Room and Training Range." % String(
		selected.get("name", "Saved map")
	)


func _select_host_map() -> bool:
	if map_entries.is_empty() or map_selector.selected < 0 or map_selector.selected >= map_entries.size():
		status_label.text = "Create and save a map before hosting."
		return false
	var entry: Dictionary = map_entries[map_selector.selected]
	var selected := MapDocument.select_library_map(String(entry.get("map_id", "")))
	if selected.is_empty():
		status_label.text = "That map could not be opened. Return to Map Editor and save it again."
		return false
	return true


func _join_match() -> void:
	if restricted_web_build or address_edit == null:
		return
	var address := address_edit.text.strip_edges()
	if address.is_empty():
		status_label.text = "Enter an invite code or server address."
		return
	# Direct addresses do not carry directory metadata. The authoritative server
	# enables tournament presentation when it sends an arena layout.
	ProjectSettings.set_setting("socom/session/tournament_mode", false)
	ProjectSettings.set_setting("socom/session/launch_mode", "join")
	ProjectSettings.set_setting("socom/session/join_address", address)
	_collect_and_open(MULTIPLAYER_SCENE)


func _collect_and_open(scene_path: String) -> void:
	if play_open_in_progress:
		return
	if restricted_web_build and scene_path in [MULTIPLAYER_SCENE, TRAINING_RANGE_SCENE]:
		play_open_in_progress = true
		get_tree().change_scene_to_file(scene_path)
		return
	var collector := get_node_or_null("/root/PlaytestStateCollector")
	if collector == null:
		status_label.text = "Play blocked: saved-state collector is unavailable."
		return
	status_label.text = "Preparing selected map and player settings…"
	var result: Dictionary = collector.call("collect_saved_state")
	if not bool(result.get("ok", false)):
		status_label.text = "Play blocked: %s" % " | ".join(result.get("errors", []))
		return
	play_open_in_progress = true
	await PlayableResourceWarmup.warm_for_play(
		get_tree(),
		scene_path,
		MapDocument.load_active(),
		_update_playable_warmup_progress
	)
	if not is_inside_tree():
		return
	get_tree().change_scene_to_file(scene_path)


func _update_playable_warmup_progress(progress: float) -> void:
	if status_label != null:
		status_label.text = "Preparing playable build… %d%%" % int(round(progress * 100.0))
