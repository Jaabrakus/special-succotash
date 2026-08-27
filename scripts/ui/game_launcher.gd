extends Control

const MULTIPLAYER_SCENE := "res://multiplayer_slice.tscn"
const MAP_EDITOR_SCENE := "res://map_creation_lab.tscn"
const TRAINING_RANGE_SCENE := "res://main.tscn"
const STUDIO_WORKBENCH_SCENE := "res://studio_workbench.tscn"
const MapDocument := preload("res://scripts/maps/socom_map_document.gd")
const KeyboardProfile := preload("res://scripts/input/socom_keyboard_mapping_profile.gd")
const ControlsGuideScript := preload("res://scripts/ui/socom_controls_guide.gd")
const PlayableResourceWarmup := preload("res://scripts/runtime/playable_resource_warmup.gd")

var address_edit: LineEdit
var map_selector: OptionButton
var mode_selector: OptionButton
var team_size_selector: OptionButton

const HOST_TEAM_SIZES: Array[int] = [2, 3, 4, 8]
var map_entries: Array[Dictionary] = []
var status_label: Label
var identity_label: Label
var server_directory_status: Label
var server_list: VBoxContainer
var available_servers: Array[Dictionary] = []
var controls_guide: SocomControlsGuide
var restricted_web_build := false
var play_open_in_progress := false


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	restricted_web_build = (
		OS.has_feature("web")
		or OS.has_feature("restricted_web")
		or OS.get_cmdline_user_args().has("--restricted-web-preview")
	)
	KeyboardProfile.apply_project_mapping()
	MapDocument.ensure_active_map_in_library()
	_build_ui()
	_build_settings()
	_refresh_map_selector()
	call_deferred("_initialize_guest_identity")


func _build_ui() -> void:
	var background := ColorRect.new()
	background.color = Color("0b1119")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, 28)
	add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 16)
	margin.add_child(column)

	var top_bar := HBoxContainer.new()
	top_bar.add_theme_constant_override("separation", 16)
	column.add_child(top_bar)
	var title := Label.new()
	title.text = "141"
	title.add_theme_font_size_override("font_size", 36)
	title.add_theme_color_override("font_color", Color("8bc5ae"))
	top_bar.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "GUNFIGHT OPERATIONS"
	subtitle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	subtitle.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	subtitle.add_theme_color_override("font_color", Color("aab4c4"))
	top_bar.add_child(subtitle)
	identity_label = Label.new()
	identity_label.name = "GuestPlayerIdentity"
	identity_label.text = "PLAYER: Connecting guest…"
	identity_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	identity_label.add_theme_color_override("font_color", Color("7df0ad"))
	top_bar.add_child(identity_label)
	var settings_button := Button.new()
	settings_button.name = "PlayerSettingsButton"
	settings_button.text = "SETTINGS"
	settings_button.pressed.connect(_open_settings)
	top_bar.add_child(settings_button)
	column.add_child(HSeparator.new())

	var main_row := HBoxContainer.new()
	main_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_row.add_theme_constant_override("separation", 16)
	column.add_child(main_row)

	var left_panel := _build_panel(Vector2(265.0, 0.0))
	main_row.add_child(left_panel)
	var left := _panel_column(left_panel)
	_add_panel_heading(left, "PLAY")
	var quick_nav := _add_primary_action(left, "QUICK MATCH 2V2", _quick_match_gunfight)
	quick_nav.call_deferred("grab_focus")
	var join_invite := _add_primary_action(left, "JOIN INVITE", _focus_join_invite)
	join_invite.name = "JoinGame"
	var private_room := _add_primary_action(left, "HOST TOURNAMENT", _host_tournament)
	private_room.name = "HostGame"
	_add_primary_action(left, "TRAINING RANGE", _open_training_range)
	left.add_child(HSeparator.new())
	_add_panel_heading(left, "CREATE")
	_add_primary_action(left, "MAP EDITOR", _open_map_editor)
	if OS.has_feature("editor"):
		_add_primary_action(left, "STUDIO WORKBENCH", _open_studio_workbench)
	var left_spacer := Control.new()
	left_spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(left_spacer)
	if not restricted_web_build:
		var quit_button := Button.new()
		quit_button.name = "Quit"
		quit_button.text = "QUIT"
		quit_button.pressed.connect(get_tree().quit)
		left.add_child(quit_button)

	var feature_panel := _build_panel(Vector2(0.0, 0.0))
	feature_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_row.add_child(feature_panel)
	var feature := _panel_column(feature_panel)
	var mode_tag := Label.new()
	mode_tag.text = "FEATURED MODE  •  PROTOTYPE QUEUE"
	mode_tag.add_theme_color_override("font_color", Color("f2cf6a"))
	feature.add_child(mode_tag)
	var mode_title := Label.new()
	mode_title.text = "GUNFIGHT 2V2"
	mode_title.add_theme_font_size_override("font_size", 42)
	mode_title.add_theme_color_override("font_color", Color("8bc5ae"))
	feature.add_child(mode_title)
	var mode_copy := Label.new()
	mode_copy.text = "FIRST TO 6  •  40 SECOND ROUNDS  •  ROTATING SHARED LOADOUTS  •  NO RESPAWNS"
	mode_copy.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mode_copy.add_theme_color_override("font_color", Color("aab4c4"))
	feature.add_child(mode_copy)
	var queue_copy := Label.new()
	queue_copy.text = "Quick Match opens the real team-and-ready waiting room. Tournament brackets become the next matchmaking layer after the four-player room is production-ready."
	queue_copy.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	queue_copy.size_flags_vertical = Control.SIZE_EXPAND_FILL
	queue_copy.add_theme_font_size_override("font_size", 18)
	feature.add_child(queue_copy)
	var featured_quick := Button.new()
	featured_quick.name = "FeaturedQuickMatch"
	featured_quick.text = "QUICK MATCH  •  ENTER 2V2 ROOM"
	featured_quick.custom_minimum_size.y = 72.0
	featured_quick.add_theme_font_size_override("font_size", 20)
	featured_quick.pressed.connect(_quick_match_gunfight)
	feature.add_child(featured_quick)
	feature.add_child(HSeparator.new())
	_add_panel_heading(feature, "PRIVATE ROOM / INVITE")
	address_edit = LineEdit.new()
	address_edit.name = "JoinGameAddress"
	address_edit.placeholder_text = "Invite code or server address"
	address_edit.text = "" if restricted_web_build else "127.0.0.1"
	address_edit.custom_minimum_size.y = 42.0
	feature.add_child(address_edit)
	var room_actions := HBoxContainer.new()
	room_actions.add_theme_constant_override("separation", 10)
	feature.add_child(room_actions)
	var connect_button := Button.new()
	connect_button.name = "ConnectToRoom"
	connect_button.text = "JOIN INVITE"
	connect_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	connect_button.pressed.connect(_join_match)
	room_actions.add_child(connect_button)
	var host_gunfight := Button.new()
	host_gunfight.name = "HostGunfight2v2"
	host_gunfight.text = "CREATE PRIVATE ROOM"
	host_gunfight.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	host_gunfight.pressed.connect(_host_private_room)
	room_actions.add_child(host_gunfight)
	var room_options := HBoxContainer.new()
	room_options.add_theme_constant_override("separation", 10)
	feature.add_child(room_options)
	mode_selector = OptionButton.new()
	mode_selector.name = "HostModeSelector"
	mode_selector.custom_minimum_size.y = 42.0
	mode_selector.tooltip_text = "Demolition plants the objective; Gunfight plays shared-loadout elimination rounds."
	for mode_label: String in ["DEMOLITION", "GUNFIGHT"]:
		mode_selector.add_item(mode_label)
	mode_selector.select(0)
	room_options.add_child(mode_selector)
	team_size_selector = OptionButton.new()
	team_size_selector.name = "HostTeamSizeSelector"
	team_size_selector.custom_minimum_size.y = 42.0
	team_size_selector.tooltip_text = "Players per side. The room admits twice this number, host included."
	for size_label: String in ["2V2", "3V3", "4V4", "8V8"]:
		team_size_selector.add_item(size_label)
	team_size_selector.select(3)
	room_options.add_child(team_size_selector)
	map_selector = OptionButton.new()
	map_selector.name = "HostMapSelector"
	map_selector.custom_minimum_size.y = 42.0
	map_selector.tooltip_text = "Choose the geometry used by hosted rooms and the Training Range."
	map_selector.item_selected.connect(_on_map_selected)
	feature.add_child(map_selector)

	var servers_panel := _build_panel(Vector2(360.0, 0.0))
	main_row.add_child(servers_panel)
	var servers := _panel_column(servers_panel)
	_add_panel_heading(servers, "LIVE SERVERS")
	server_directory_status = Label.new()
	server_directory_status.name = "ServerDirectoryStatus"
	server_directory_status.text = "CHECKING SERVICE…"
	server_directory_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	server_directory_status.add_theme_color_override("font_color", Color("aab4c4"))
	servers.add_child(server_directory_status)
	var server_scroll := ScrollContainer.new()
	server_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	server_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	servers.add_child(server_scroll)
	server_list = VBoxContainer.new()
	server_list.name = "LiveServerList"
	server_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	server_list.add_theme_constant_override("separation", 8)
	server_scroll.add_child(server_list)
	var refresh_servers := Button.new()
	refresh_servers.name = "RefreshServers"
	refresh_servers.text = "REFRESH SERVERS"
	refresh_servers.pressed.connect(_refresh_server_directory)
	servers.add_child(refresh_servers)

	status_label = Label.new()
	status_label.name = "LauncherStatus"
	status_label.text = (
		"Browser player build • matchmaking service required"
		if restricted_web_build
		else "Gunfight room flow ready • Direct IP UDP 14141"
	)
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.add_theme_color_override("font_color", Color("7f8b9c"))
	column.add_child(status_label)


func _build_panel(minimum_size: Vector2) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = minimum_size
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return panel


func _panel_column(panel: PanelContainer) -> VBoxContainer:
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, 20)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 11)
	margin.add_child(column)
	return column


func _add_panel_heading(parent: VBoxContainer, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", Color("8bc5ae"))
	parent.add_child(label)


func _add_primary_action(parent: VBoxContainer, label_text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.name = label_text.to_snake_case().to_pascal_case()
	button.text = label_text
	button.custom_minimum_size.y = 50.0
	button.add_theme_font_size_override("font_size", 16)
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
		identity_label.text = "PLAYER: Local Guest"
		_show_server_directory_message("DIRECTORY OFFLINE\nDirect-IP rooms remain available.")
		return
	var result: Dictionary = await service.call("ensure_guest_session")
	identity_label.text = (
		"PLAYER: %s  •  GUEST" % String(result.get("display_name", "Guest"))
		if bool(result.get("ok", false))
		else "PLAYER: Local Guest  •  cloud offline"
	)
	await _refresh_server_directory()


func _quick_match_gunfight() -> void:
	status_label.text = "Opening a 2v2 Gunfight waiting room…"
	_host_gunfight()


func _host_tournament() -> void:
	# The Square: 16 two-player squads register in the tournament lobby, the
	# server seeds the bracket, and pods play as Gunfight matches. Ordinary
	# private-room hosting is unchanged.
	if not _select_host_map():
		return
	if restricted_web_build:
		status_label.text = "Browser match service is not connected yet."
		return
	ProjectSettings.set_setting("socom/session/match_mode", "tournament")
	ProjectSettings.set_setting("socom/session/launch_mode", "host")
	ProjectSettings.set_setting("socom/session/join_address", "")
	_collect_and_open(MULTIPLAYER_SCENE)


func _focus_join_invite() -> void:
	if address_edit == null:
		return
	address_edit.grab_focus()
	address_edit.select_all()
	status_label.text = "Enter an invite code or server address, then choose Join Invite."


func _refresh_server_directory() -> void:
	var service := get_node_or_null("/root/SupabaseClient")
	if service == null or not bool(service.call("is_configured")) or not service.has_method("list_match_servers"):
		_show_server_directory_message("DIRECTORY OFFLINE\nDirect-IP rooms remain available.")
		return
	server_directory_status.text = "REFRESHING COMPATIBLE SERVERS…"
	var result: Dictionary = await service.call("list_match_servers")
	if not bool(result.get("ok", false)):
		_show_server_directory_message("SERVICE UNAVAILABLE\n%s" % String(result.get("message", "Try again later.")))
		return
	available_servers.clear()
	for raw_server: Variant in result.get("servers", []):
		if raw_server is Dictionary:
			available_servers.append(raw_server as Dictionary)
	_rebuild_server_rows()


func _show_server_directory_message(message: String) -> void:
	available_servers.clear()
	server_directory_status.text = message
	server_directory_status.add_theme_color_override("font_color", Color("f2cf6a"))
	if server_list == null:
		return
	for child in server_list.get_children():
		child.queue_free()


func _rebuild_server_rows() -> void:
	for child in server_list.get_children():
		child.queue_free()
	server_directory_status.text = "%d COMPATIBLE SERVERS ONLINE" % available_servers.size()
	server_directory_status.add_theme_color_override("font_color", Color("7df0ad"))
	if available_servers.is_empty():
		var empty := Label.new()
		empty.text = "No compatible rooms are advertising capacity.\nHost a room or use an invite code."
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty.add_theme_color_override("font_color", Color("aab4c4"))
		server_list.add_child(empty)
		return
	for server: Dictionary in available_servers:
		var row := Button.new()
		row.text = "%s\n%s  •  %d/%d" % [
			String(server.get("name", "SERVER")),
			String(server.get("region", "unknown")).to_upper(),
			int(server.get("current_players", 0)),
			int(server.get("capacity", 0)),
		]
		row.custom_minimum_size.y = 62.0
		row.pressed.connect(_join_discovered_server.bind(server))
		server_list.add_child(row)


func _join_discovered_server(server: Dictionary) -> void:
	var address := String(server.get("public_address", ""))
	var port := int(server.get("public_port", 14141))
	if address.is_empty():
		status_label.text = "That server did not publish a valid address."
		return
	address_edit.text = "%s:%d" % [address, port]
	_join_match()


func _open_map_editor() -> void:
	get_tree().change_scene_to_file(MAP_EDITOR_SCENE)


func _open_studio_workbench() -> void:
	var navigation := get_node_or_null("/root/StudioNavigation")
	if navigation != null and bool(navigation.get("active")):
		navigation.call("open_scene", STUDIO_WORKBENCH_SCENE)
	else:
		get_tree().change_scene_to_file(STUDIO_WORKBENCH_SCENE)


func _open_training_range() -> void:
	if not _select_host_map():
		return
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
	status_label.text = "%s selected for Training Range and private 2v2 rooms." % String(
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


func _host_private_room() -> void:
	# One hosting flow, two dials: the mode picks the ruleset, the team size
	# picks the scale. Quick Match and Tournament preset both and reuse this.
	var gunfight_mode := mode_selector.selected == 1
	var side := HOST_TEAM_SIZES[team_size_selector.selected] if team_size_selector.selected >= 0 else 8
	if not _select_host_map():
		return
	if restricted_web_build:
		status_label.text = "Browser match service is not connected yet. Your selected map is ready for deployment."
		return
	ProjectSettings.set_setting("socom/session/match_mode", "gunfight" if gunfight_mode else "")
	ProjectSettings.set_setting("socom/session/players_per_side", side)
	ProjectSettings.set_setting("socom/session/launch_mode", "host")
	ProjectSettings.set_setting("socom/session/join_address", "")
	_collect_and_open(MULTIPLAYER_SCENE)


func _host_match() -> void:
	ProjectSettings.set_setting("socom/session/players_per_side", 8)
	mode_selector.select(0)
	_host_private_room()


func _host_gunfight(tournament_host: bool = false) -> void:
	if not _select_host_map():
		return
	if restricted_web_build:
		status_label.text = "Browser match service is not connected yet. Your selected map is ready for deployment."
		return
	ProjectSettings.set_setting("socom/session/match_mode", "gunfight")
	ProjectSettings.set_setting("socom/session/players_per_side", 2)
	ProjectSettings.set_setting("socom/session/tournament_host", tournament_host)
	ProjectSettings.set_setting("socom/session/launch_mode", "host")
	ProjectSettings.set_setting("socom/session/join_address", "")
	_collect_and_open(MULTIPLAYER_SCENE)


func _join_match() -> void:
	var address := address_edit.text.strip_edges()
	if address.is_empty():
		status_label.text = "Enter an invite code or server address."
		return
	if restricted_web_build:
		status_label.text = "Browser match service is not connected yet."
		return
	ProjectSettings.set_setting("socom/session/launch_mode", "join")
	ProjectSettings.set_setting("socom/session/join_address", address)
	_collect_and_open(MULTIPLAYER_SCENE)


func _collect_and_open(scene_path: String) -> void:
	if play_open_in_progress:
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
