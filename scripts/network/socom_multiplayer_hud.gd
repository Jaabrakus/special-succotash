class_name SocomMultiplayerHUD
extends CanvasLayer

## Presentation-only multiplayer HUD. Network simulation and authority remain
## in SocomMultiplayerSlice; this node owns controls, labels, and formatting.

signal host_requested
signal join_requested(address: String)
signal leave_requested
signal team_requested(team: int)
signal ready_requested

const LobbyState := preload("res://scripts/network/socom_lobby_state.gd")

var menu_panel: PanelContainer
var address_edit: LineEdit
var status_label: Label
var score_label: Label
var reticle: Label
var player_state_label: Label
var match_clock_label: Label
var objective_status_label: Label
var lobby_panel: PanelContainer
var lobby_roster_label: RichTextLabel
var lobby_map_label: Label
var alpha_team_button: Button
var bravo_team_button: Button
var ready_button: Button
var lobby_status_label: Label


func _ready() -> void:
	_build_match_hud()
	_build_lobby()


func show_lobby(enabled: bool, session_active: bool) -> void:
	lobby_panel.visible = enabled
	reticle.visible = not enabled and session_active
	if enabled:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func set_status(message: String) -> void:
	status_label.text = "SOCOM-141 MULTIPLAYER SLICE  •  %s" % message


func refresh_scoreboard(mission_rules: Dictionary, round_wins: Dictionary, scores: Dictionary) -> void:
	if String(mission_rules.get("primary_mode", "demolition")) == "demolition":
		score_label.text = "ROUNDS  ALPHA %d  •  BRAVO %d" % [
			int(round_wins.get(0, 0)), int(round_wins.get(1, 0)),
		]
		return
	var entries: Array[String] = []
	var ids := scores.keys()
	ids.sort()
	for raw_id: Variant in ids:
		entries.append("P%s:%s" % [raw_id, scores[raw_id]])
	score_label.text = "SCORE  " + "  •  ".join(entries)


func refresh_match_clock(round_index: int, remaining: float, session_active: bool) -> void:
	var total_seconds := maxi(0, ceili(remaining))
	match_clock_label.text = "ROUND %d  •  %02d:%02d" % [
		maxi(round_index, 1), total_seconds / 60, total_seconds % 60,
	]
	match_clock_label.visible = session_active


func refresh_player_state(health: float, maximum: float, magazine: int, reserve: int) -> void:
	player_state_label.text = "HEALTH %d/%d  •  AMMO %d/%d" % [
		int(round(health)), int(round(maximum)), magazine, reserve,
	]


func refresh_objective_status(state: Dictionary) -> void:
	var session_active := bool(state.get("session_active", false))
	objective_status_label.visible = session_active
	if not session_active:
		return
	if bool(state.get("pickup_positions_empty", true)):
		objective_status_label.text = "DEMOLITION  •  ELIMINATION ONLY — MAP HAS NO BOMB PICKUP"
	elif bool(state.get("bomb_planted", false)):
		var defuse_seconds := maxf(float(state.get("defuse_time_seconds", 5.0)), 0.1)
		var defuse_percent := clampf(float(state.get("defuse_progress", 0.0)) / defuse_seconds, 0.0, 1.0) * 100.0
		var defusing_peer := int(state.get("defusing_peer_id", 0))
		if defusing_peer != 0:
			objective_status_label.text = "SEAL %d DEFUSING  •  %.0f%%  •  DETONATION IN %.1f" % [
				defusing_peer, defuse_percent, float(state.get("fuse_remaining", 0.0)),
			]
		else:
			objective_status_label.text = "BOMB PLANTED  •  HOLD F TO DEFUSE  •  DETONATION IN %.1f" % float(state.get("fuse_remaining", 0.0))
	elif int(state.get("carrier_peer_id", 0)) != 0:
		var plant_seconds := maxf(float(state.get("plant_time_seconds", 5.0)), 0.1)
		var progress := clampf(float(state.get("plant_progress", 0.0)) / plant_seconds, 0.0, 1.0)
		objective_status_label.text = "SEAL %d HAS BOMB  •  HOLD F AT ENEMY TARGET  •  PLANT %.0f%%" % [
			int(state.get("carrier_peer_id", 0)), progress * 100.0,
		]
	else:
		objective_status_label.text = "BOMB AVAILABLE  •  HOLD F TO PICK UP"


func refresh_lobby(
	lobby,
	local_peer_id: int,
	map_document: Dictionary,
	round_rules: Dictionary,
	countdown_remaining: float
) -> void:
	var alpha_lines: Array[String] = []
	var bravo_lines: Array[String] = []
	var ids: Array = lobby.players.keys()
	ids.sort()
	for raw_id: Variant in ids:
		var entry: Dictionary = lobby.players[raw_id]
		var ready_mark := "[color=#70f59b]● READY[/color]" if bool(entry.get("ready", false)) else "[color=#7f8b9c]○ WAITING[/color]"
		var local_mark := "  [color=#f2cf6a](YOU)[/color]" if int(raw_id) == local_peer_id else ""
		var line := "%s  %s%s" % [ready_mark, String(entry.get("display_name", "PLAYER")), local_mark]
		(alpha_lines if int(entry.get("team", 0)) == 0 else bravo_lines).append(line)
	lobby_roster_label.text = (
		"[table=2]"
		+ "[cell][font_size=20][color=#6eb6ff]ALPHA[/color][/font_size]\n%s[/cell]" % ("\n".join(alpha_lines) if not alpha_lines.is_empty() else "—")
		+ "[cell][font_size=20][color=#ff7d76]BRAVO[/color][/font_size]\n%s[/cell]" % ("\n".join(bravo_lines) if not bravo_lines.is_empty() else "—")
		+ "[/table]"
	)
	var local_entry: Dictionary = lobby.players.get(local_peer_id, {})
	var local_ready := bool(local_entry.get("ready", false))
	ready_button.disabled = local_entry.is_empty() or lobby.phase == LobbyState.PHASE_PLAYING
	ready_button.text = "● GREEN — READY" if local_ready else "○ NOT READY — GREEN UP"
	ready_button.add_theme_color_override("font_color", Color("70f59b") if local_ready else Color("d8dde6"))
	alpha_team_button.disabled = local_entry.is_empty() or lobby.phase != LobbyState.PHASE_WAITING
	bravo_team_button.disabled = alpha_team_button.disabled
	var map_name := String(map_document.get("name", "Fallback Arena"))
	var minutes := float(round_rules.get("time_limit_seconds", 300)) / 60.0
	lobby_map_label.text = "%s  •  DEMOLITION  •  %.1f MIN  •  FIRST TO %d" % [
		map_name, minutes, int(round_rules.get("rounds_to_win", 4)),
	]
	if lobby.phase == LobbyState.PHASE_PLAYING:
		_set_lobby_message("Match in progress. You will enter when everyone returns to the lobby.", Color("f2cf6a"))
	elif lobby.phase == LobbyState.PHASE_COUNTDOWN:
		_set_lobby_message("ALL PLAYERS READY  •  MATCH STARTS IN %d" % ceili(countdown_remaining), Color("70f59b"))
	elif lobby.players.size() < LobbyState.MINIMUM_PLAYERS:
		_set_lobby_message("Waiting for at least two players.", Color("aeb9c9"))
	elif lobby.team_count(0) == 0 or lobby.team_count(1) == 0:
		_set_lobby_message("Both Alpha and Bravo need at least one player.", Color("f2cf6a"))
	else:
		_set_lobby_message("Choose a side, then green up. The match starts when everyone is ready.", Color("aeb9c9"))


func _build_match_hud() -> void:
	status_label = _add_label(Vector2(20.0, 16.0), 17, Color.WHITE, "SOCOM-141 MULTIPLAYER SLICE")
	score_label = _add_label(Vector2(20.0, 42.0), 16)
	player_state_label = _add_label(Vector2(20.0, 66.0), 15, Color("a9f4c0"))
	match_clock_label = _add_label(Vector2(20.0, 90.0), 18, Color("f2cf6a"))
	match_clock_label.name = "MultiplayerRoundClock"
	objective_status_label = _add_label(Vector2(20.0, 116.0), 16, Color("f4d34f"))
	objective_status_label.name = "DemolitionObjectiveStatus"
	reticle = Label.new()
	reticle.text = "+"
	reticle.add_theme_font_size_override("font_size", 28)
	reticle.set_anchors_preset(Control.PRESET_CENTER)
	reticle.position = Vector2(-8.0, -18.0)
	reticle.modulate = Color(1.0, 0.92, 0.20)
	reticle.visible = false
	add_child(reticle)
	menu_panel = PanelContainer.new()
	menu_panel.position = Vector2(20.0, 146.0)
	menu_panel.custom_minimum_size = Vector2(360.0, 0.0)
	add_child(menu_panel)
	var column := VBoxContainer.new()
	menu_panel.add_child(column)
	var title := Label.new()
	title.text = "8v8 DIRECT-IP MATCH"
	title.add_theme_font_size_override("font_size", 20)
	column.add_child(title)
	var explanation := Label.new()
	explanation.text = "Host one window. Join it from a second window.\nWASD move • Mouse aim • Left click fire • Esc releases mouse"
	column.add_child(explanation)
	address_edit = LineEdit.new()
	address_edit.placeholder_text = "Server address"
	address_edit.text = "127.0.0.1"
	column.add_child(address_edit)
	var row := HBoxContainer.new()
	column.add_child(row)
	var host_button := Button.new()
	host_button.text = "HOST MATCH"
	host_button.pressed.connect(func(): host_requested.emit())
	row.add_child(host_button)
	var join_button := Button.new()
	join_button.text = "JOIN MATCH"
	join_button.pressed.connect(func(): join_requested.emit(address_edit.text))
	row.add_child(join_button)
	var leave_button := Button.new()
	leave_button.text = "MAIN MENU"
	leave_button.pressed.connect(func(): leave_requested.emit())
	column.add_child(leave_button)


func _build_lobby() -> void:
	lobby_panel = PanelContainer.new()
	lobby_panel.name = "MultiplayerLobbyPanel"
	lobby_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lobby_panel.anchor_left = 0.18
	lobby_panel.anchor_top = 0.10
	lobby_panel.anchor_right = 0.82
	lobby_panel.anchor_bottom = 0.90
	lobby_panel.visible = false
	add_child(lobby_panel)
	var margin := MarginContainer.new()
	for side: StringName in [&"margin_left", &"margin_right", &"margin_top", &"margin_bottom"]:
		margin.add_theme_constant_override(side, 24 if side in [&"margin_left", &"margin_right"] else 20)
	lobby_panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)
	var title := Label.new()
	title.text = "SOCOM-141 MATCH LOBBY"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color("8bc5ae"))
	column.add_child(title)
	lobby_map_label = Label.new()
	lobby_map_label.name = "LobbySelectedMap"
	lobby_map_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lobby_map_label.add_theme_color_override("font_color", Color("f2cf6a"))
	column.add_child(lobby_map_label)
	column.add_child(HSeparator.new())
	lobby_roster_label = RichTextLabel.new()
	lobby_roster_label.name = "LobbyPlayerRoster"
	lobby_roster_label.bbcode_enabled = true
	lobby_roster_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	lobby_roster_label.add_theme_font_size_override("normal_font_size", 16)
	column.add_child(lobby_roster_label)
	var side_row := HBoxContainer.new()
	side_row.add_theme_constant_override("separation", 10)
	column.add_child(side_row)
	alpha_team_button = _team_button("ChooseAlphaTeamButton", "JOIN ALPHA", Color("6eb6ff"), 0)
	bravo_team_button = _team_button("ChooseBravoTeamButton", "JOIN BRAVO", Color("ff7d76"), 1)
	side_row.add_child(alpha_team_button)
	side_row.add_child(bravo_team_button)
	ready_button = Button.new()
	ready_button.name = "GreenUpReadyButton"
	ready_button.text = "○ NOT READY — GREEN UP"
	ready_button.custom_minimum_size.y = 54
	ready_button.pressed.connect(func(): ready_requested.emit())
	column.add_child(ready_button)
	lobby_status_label = Label.new()
	lobby_status_label.name = "LobbyReadyStatus"
	lobby_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lobby_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(lobby_status_label)
	var leave_button := Button.new()
	leave_button.text = "LEAVE LOBBY"
	leave_button.pressed.connect(func(): leave_requested.emit())
	column.add_child(leave_button)


func _add_label(
	position_value: Vector2,
	font_size: int,
	color: Color = Color.WHITE,
	text_value: String = ""
) -> Label:
	var label := Label.new()
	label.position = position_value
	label.text = text_value
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	add_child(label)
	return label


func _team_button(node_name: String, text_value: String, color: Color, team: int) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = text_value
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.add_theme_color_override("font_color", color)
	button.pressed.connect(func(): team_requested.emit(team))
	return button


func _set_lobby_message(message: String, color: Color) -> void:
	lobby_status_label.text = message
	lobby_status_label.add_theme_color_override("font_color", color)
