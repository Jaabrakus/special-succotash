class_name SocomMultiplayerHUD
extends CanvasLayer

## Presentation-only multiplayer HUD. Network simulation and authority remain
## in SocomMultiplayerSlice; this node owns controls, labels, and formatting.

signal warmup_requested
signal host_requested
signal join_requested(address: String)
signal leave_requested
signal team_requested(team: int)
signal pair_requested(pair_id: int)
signal ready_requested
signal sudden_death_vote_requested(candidate_peer_id: int)

const LobbyState := preload("res://scripts/network/socom_lobby_state.gd")
const MatchInvite := preload("res://scripts/network/socom_match_invite.gd")
const TeamRosterHUD := preload("res://scripts/ui/socom_team_roster_hud.gd")
const LoadoutCardHUD := preload("res://scripts/ui/socom_loadout_card_hud.gd")

var menu_panel: PanelContainer
var address_edit: LineEdit
var status_label: Label
var score_label: Label
var reticle: SocomDynamicReticle
var player_state_label: Label
var match_clock_label: Label
var objective_status_label: Label
var lobby_panel: PanelContainer
var lobby_roster_label: RichTextLabel
var lobby_map_label: Label
var alpha_team_button: Button
var bravo_team_button: Button
var team_selector_row: HBoxContainer
var pair_selector_row: HBoxContainer
var pair_selector: OptionButton
var warmup_button: Button
var ready_button: Button
var lobby_status_label: Label
var invite_panel: PanelContainer
var invite_code_edit: LineEdit
var invite_copy_button: Button
var invite_help_label: Label
var team_roster_hud = null
var loadout_card_hud = null
var connection_title: Label
var connection_explanation: Label
var host_button: Button
var join_button: Button
var sudden_death_vote_panel: PanelContainer
var sudden_death_vote_title: Label
var sudden_death_vote_status: Label
var sudden_death_vote_buttons: Array[Button] = []


func _ready() -> void:
	_build_match_hud()
	_build_lobby()


func show_lobby(enabled: bool, session_active: bool) -> void:
	lobby_panel.visible = enabled
	reticle.visible = not enabled and session_active
	if enabled:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func set_status(message: String) -> void:
	status_label.text = "DELTA COM MULTIPLAYER SLICE  •  %s" % message


func show_host_invite(port: int) -> void:
	var invite: Dictionary = MatchInvite.create_for_host(port)
	invite_panel.visible = true
	invite_code_edit.text = String(invite.get("code", "INVITE UNAVAILABLE"))
	invite_copy_button.disabled = not bool(invite.get("ok", false))
	invite_copy_button.text = "COPY CODE"
	invite_help_label.text = (
		"Share this code. Players paste it into JOIN GAME. Internet play still needs UDP %d reachable on the host."
		% port
		if bool(invite.get("ok", false))
		else String(invite.get("message", "Could not create an invite code."))
	)


func show_webrtc_room(room_code: String) -> void:
	invite_panel.visible = true
	invite_code_edit.text = room_code
	invite_copy_button.disabled = room_code.is_empty()
	invite_copy_button.text = "COPY ROOM CODE"
	invite_help_label.text = (
		"Share this room code. Browser players paste it into JOIN ROOM. "
		+ "Gameplay connects peer-to-peer after signaling."
	)


func clear_host_invite() -> void:
	if invite_panel != null:
		invite_panel.visible = false


func show_sudden_death_vote_state(state: Dictionary) -> void:
	if sudden_death_vote_panel == null:
		return
	var phase := String(state.get("phase", ""))
	if phase == "SUDDEN_DEATH_VOTE":
		sudden_death_vote_panel.visible = true
		reticle.visible = false
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		var seconds := maxi(0, ceili(float(state.get("remaining", 0.0))))
		var local_vote_peer_id := int(state.get("local_vote_peer_id", -1))
		sudden_death_vote_title.text = "SUDDEN DEATH — CHOOSE YOUR 1V1 FIGHTER"
		sudden_death_vote_status.text = (
			"Vote locked in • %d seconds remaining" % seconds
			if local_vote_peer_id > 0
			else "Your duo has %d seconds to vote" % seconds
		)
		var candidates: Array = state.get("candidates", [])
		for index in sudden_death_vote_buttons.size():
			var button := sudden_death_vote_buttons[index]
			button.visible = index < candidates.size()
			if index >= candidates.size():
				continue
			var candidate: Dictionary = candidates[index]
			var candidate_peer_id := int(candidate.get("peer_id", -1))
			button.set_meta("candidate_peer_id", candidate_peer_id)
			button.text = "%s  •  %d VOTE%s%s" % [
				String(candidate.get("display_name", "SEAL %d" % candidate_peer_id)),
				int(candidate.get("votes", 0)),
				"S" if int(candidate.get("votes", 0)) != 1 else "",
				"  ✓ YOUR PICK" if candidate_peer_id == local_vote_peer_id else "",
			]
		return
	sudden_death_vote_panel.visible = false
	if phase == "SUDDEN_DEATH":
		var representative_a := String(state.get("representative_a_name", "ALPHA"))
		var representative_b := String(state.get("representative_b_name", "BRAVO"))
		status_label.text = "SUDDEN DEATH  •  %s VS %s" % [representative_a, representative_b]
		reticle.visible = bool(state.get("local_selected", false))
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif phase == "REGULATION":
		reticle.visible = true
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func configure_connection_mode(browser_client: bool, default_server_url: String = "") -> void:
	if address_edit == null:
		return
	if browser_client:
		connection_title.text = "32-PLAYER TOURNAMENT"
		connection_explanation.text = (
			"The official tournament connection ended. Return to the main menu "
			+ "to rejoin through Quick Match."
		)
		address_edit.text = default_server_url
		address_edit.visible = false
		host_button.visible = false
		join_button.visible = false
	else:
		connection_title.text = "MULTIPLAYER MATCH"
		connection_explanation.text = (
			"Host one native window or join ENet / ws://.\n"
			+ "WASD move • Mouse aim • Left click fire • Esc releases mouse"
		)
		host_button.visible = true
		join_button.visible = true


func _copy_host_invite() -> void:
	if invite_code_edit.text.is_empty() or invite_copy_button.disabled:
		return
	DisplayServer.clipboard_set(invite_code_edit.text)
	invite_copy_button.text = "COPIED"


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


func refresh_player_state(health: float, maximum: float, magazine: int, reserve: int,
		weapon_name: String = "NO WEAPON", slot: String = "primary",
		fire_mode: String = "auto", modes: Array[String] = [], burst_size: int = 3) -> void:
	player_state_label.text = "HEALTH %d/%d  •  AMMO %d/%d" % [
		int(round(health)), int(round(maximum)), magazine, reserve,
	]
	if loadout_card_hud != null:
		loadout_card_hud.update_weapon_state(
			weapon_name,
			slot,
			magazine,
			reserve,
			fire_mode,
			modes,
			burst_size
		)
		loadout_card_hud.update_health(health, maximum)


func update_roster_data(
	alpha: Array,
	bravo: Array,
	alpha_score: int = -1,
	bravo_score: int = -1,
	timer_sec: float = -1.0,
	bomb_msg: String = "",
	bomb_armed: bool = false
) -> void:
	if team_roster_hud != null:
		team_roster_hud.set_roster_data(
			alpha,
			bravo,
			alpha_score,
			bravo_score,
			timer_sec,
			bomb_msg,
			bomb_armed
		)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"toggle_scoreboard"):
		if team_roster_hud != null:
			team_roster_hud.show_scorecard(true)
	elif event.is_action_released(&"toggle_scoreboard"):
		if team_roster_hud != null:
			team_roster_hud.show_scorecard(false)


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
	var pair_mode: bool = lobby.lobby_mode == LobbyState.LOBBY_MODE_GUNFIGHT_2V2
	var alpha_lines: Array[String] = []
	var bravo_lines: Array[String] = []
	var pair_lines: Array[String] = []
	var ids: Array = lobby.players.keys()
	ids.sort()
	for raw_id: Variant in ids:
		var entry: Dictionary = lobby.players[raw_id]
		var ready_mark := "[color=#70f59b]● READY[/color]" if bool(entry.get("ready", false)) else "[color=#7f8b9c]○ WAITING[/color]"
		var local_mark := "  [color=#f2cf6a](YOU)[/color]" if int(raw_id) == local_peer_id else ""
		var pair_number := int(entry.get("pair_id", -1)) + 1
		var pair_mark := "[color=#f2cf6a]PAIR %02d[/color]" % pair_number
		var line := "%s  %s  %s%s" % [
			pair_mark,
			ready_mark,
			String(entry.get("display_name", "PLAYER")),
			local_mark,
		]
		if pair_mode:
			pair_lines.append(line)
		else:
			(alpha_lines if int(entry.get("team", 0)) == 0 else bravo_lines).append(line)
	if pair_mode:
		lobby_roster_label.text = (
			"[font_size=20][color=#f2cf6a]TOURNAMENT DUOS[/color][/font_size]\n%s"
			% ("\n".join(pair_lines) if not pair_lines.is_empty() else "—")
		)
	else:
		lobby_roster_label.text = (
			"[table=2]"
			+ "[cell][font_size=20][color=#6eb6ff]ALPHA[/color][/font_size]\n%s[/cell]" % ("\n".join(alpha_lines) if not alpha_lines.is_empty() else "—")
			+ "[cell][font_size=20][color=#ff7d76]BRAVO[/color][/font_size]\n%s[/cell]" % ("\n".join(bravo_lines) if not bravo_lines.is_empty() else "—")
			+ "[/table]"
		)
	var local_entry: Dictionary = lobby.players.get(local_peer_id, {})
	var local_ready := bool(local_entry.get("ready", false))
	pair_selector_row.visible = pair_mode
	team_selector_row.visible = not pair_mode
	if pair_mode:
		var local_pair_id := int(local_entry.get("pair_id", -1))
		for index in pair_selector.item_count:
			var pair_id := pair_selector.get_item_id(index)
			var occupancy: int = lobby.get_pair_members(pair_id).size()
			pair_selector.set_item_text(index, "PAIR %02d  •  %d/%d" % [
				pair_id + 1,
				occupancy,
				LobbyState.PAIR_CAPACITY,
			])
			pair_selector.set_item_disabled(
				index,
				occupancy >= LobbyState.PAIR_CAPACITY and pair_id != local_pair_id
			)
		var selected_index := pair_selector.get_item_index(local_pair_id)
		if selected_index >= 0:
			pair_selector.select(selected_index)
		pair_selector.disabled = local_entry.is_empty() or lobby.phase != LobbyState.PHASE_WAITING
	ready_button.disabled = local_entry.is_empty() or lobby.phase == LobbyState.PHASE_PLAYING
	ready_button.text = "● GREEN — READY" if local_ready else "○ NOT READY — GREEN UP"
	ready_button.add_theme_color_override("font_color", Color("70f59b") if local_ready else Color("d8dde6"))
	alpha_team_button.disabled = pair_mode or local_entry.is_empty() or lobby.phase != LobbyState.PHASE_WAITING
	bravo_team_button.disabled = alpha_team_button.disabled
	var map_name := String(map_document.get("name", "Fallback Arena"))
	var minutes := float(round_rules.get("time_limit_seconds", 300)) / 60.0
	lobby_map_label.text = (
		"%s  •  GUNFIGHT 2V2  •  16-DUO BRACKET" % map_name
		if pair_mode
		else "%s  •  DEMOLITION  •  %.1f MIN  •  FIRST TO %d" % [
			map_name, minutes, int(round_rules.get("rounds_to_win", 4)),
		]
	)
	if lobby.phase == LobbyState.PHASE_PLAYING:
		_set_lobby_message("Match in progress. You will enter when everyone returns to the lobby.", Color("f2cf6a"))
	elif lobby.phase == LobbyState.PHASE_COUNTDOWN:
		_set_lobby_message("ALL PLAYERS READY  •  MATCH STARTS IN %d" % ceili(countdown_remaining), Color("70f59b"))
	elif lobby.players.size() < LobbyState.MINIMUM_PLAYERS:
		_set_lobby_message("Waiting for at least two players.", Color("aeb9c9"))
	elif pair_mode:
		_set_lobby_message(
			"Choose your duo, then Green Up. All 16 complete duos are required.",
			Color("aeb9c9")
		)
	elif lobby.team_count(0) == 0 or lobby.team_count(1) == 0:
		_set_lobby_message("Both Alpha and Bravo need at least one player.", Color("f2cf6a"))
	else:
		_set_lobby_message("Choose a side, then green up. The match starts when everyone is ready.", Color("aeb9c9"))


func _build_match_hud() -> void:
	status_label = _add_label(Vector2(20.0, 16.0), 17, Color.WHITE, "DELTA COM MULTIPLAYER SLICE")
	score_label = _add_label(Vector2(20.0, 42.0), 16)
	player_state_label = _add_label(Vector2(20.0, 66.0), 15, Color("a9f4c0"))
	match_clock_label = _add_label(Vector2(20.0, 90.0), 18, Color("f2cf6a"))
	match_clock_label.name = "MultiplayerRoundClock"
	objective_status_label = _add_label(Vector2(20.0, 116.0), 16, Color("f4d34f"))
	objective_status_label.name = "DemolitionObjectiveStatus"
	team_roster_hud = TeamRosterHUD.new()
	team_roster_hud.name = "SocomTeamRosterHUD"
	add_child(team_roster_hud)
	loadout_card_hud = LoadoutCardHUD.new()
	loadout_card_hud.name = "SocomLoadoutCardHUD"
	add_child(loadout_card_hud)
	reticle = preload("res://scripts/ui/socom_dynamic_reticle.gd").new()
	reticle.name = "SharedWeaponReticle"
	reticle.visible = false
	add_child(reticle)
	menu_panel = PanelContainer.new()
	menu_panel.position = Vector2(20.0, 146.0)
	menu_panel.custom_minimum_size = Vector2(360.0, 0.0)
	add_child(menu_panel)
	var column := VBoxContainer.new()
	menu_panel.add_child(column)
	connection_title = Label.new()
	connection_title.text = "MULTIPLAYER MATCH"
	connection_title.add_theme_font_size_override("font_size", 20)
	column.add_child(connection_title)
	connection_explanation = Label.new()
	connection_explanation.text = "Host one native window or join ENet / ws://.\nWASD move • Mouse aim • Left click fire • Esc releases mouse"
	connection_explanation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(connection_explanation)
	address_edit = LineEdit.new()
	address_edit.placeholder_text = "Invite code or server address"
	address_edit.text = "127.0.0.1"
	column.add_child(address_edit)
	var row := HBoxContainer.new()
	column.add_child(row)
	host_button = Button.new()
	host_button.name = "HostGame"
	host_button.text = "HOST MATCH"
	host_button.pressed.connect(func(): host_requested.emit())
	row.add_child(host_button)
	join_button = Button.new()
	join_button.name = "JoinGame"
	join_button.text = "JOIN MATCH"
	join_button.pressed.connect(func(): join_requested.emit(address_edit.text))
	row.add_child(join_button)
	var leave_button := Button.new()
	leave_button.text = "MAIN MENU"
	leave_button.pressed.connect(func(): leave_requested.emit())
	column.add_child(leave_button)
	_build_sudden_death_vote_panel()


func _build_sudden_death_vote_panel() -> void:
	sudden_death_vote_panel = PanelContainer.new()
	sudden_death_vote_panel.name = "SuddenDeathVotePanel"
	sudden_death_vote_panel.set_anchors_preset(Control.PRESET_CENTER)
	sudden_death_vote_panel.position = Vector2(-240.0, -125.0)
	sudden_death_vote_panel.custom_minimum_size = Vector2(480.0, 250.0)
	sudden_death_vote_panel.visible = false
	add_child(sudden_death_vote_panel)
	var margin := MarginContainer.new()
	for side: StringName in [&"margin_left", &"margin_right", &"margin_top", &"margin_bottom"]:
		margin.add_theme_constant_override(side, 24)
	sudden_death_vote_panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	margin.add_child(column)
	sudden_death_vote_title = Label.new()
	sudden_death_vote_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sudden_death_vote_title.add_theme_font_size_override("font_size", 22)
	sudden_death_vote_title.add_theme_color_override("font_color", Color("f2cf6a"))
	column.add_child(sudden_death_vote_title)
	sudden_death_vote_status = Label.new()
	sudden_death_vote_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sudden_death_vote_status.add_theme_color_override("font_color", Color("d8dde6"))
	column.add_child(sudden_death_vote_status)
	for index in 2:
		var button := Button.new()
		button.name = "SuddenDeathCandidate%d" % (index + 1)
		button.custom_minimum_size.y = 58.0
		button.pressed.connect(_on_sudden_death_candidate_pressed.bind(button))
		column.add_child(button)
		sudden_death_vote_buttons.append(button)


func _on_sudden_death_candidate_pressed(button: Button) -> void:
	var candidate_peer_id := int(button.get_meta("candidate_peer_id", -1))
	if candidate_peer_id > 0:
		sudden_death_vote_requested.emit(candidate_peer_id)


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
	title.text = "DELTA COM MATCH LOBBY"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color("8bc5ae"))
	column.add_child(title)
	lobby_map_label = Label.new()
	lobby_map_label.name = "LobbySelectedMap"
	lobby_map_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lobby_map_label.add_theme_color_override("font_color", Color("f2cf6a"))
	column.add_child(lobby_map_label)
	invite_panel = PanelContainer.new()
	invite_panel.name = "HostInviteCodePanel"
	invite_panel.visible = false
	column.add_child(invite_panel)
	var invite_column := VBoxContainer.new()
	invite_column.add_theme_constant_override("separation", 4)
	invite_panel.add_child(invite_column)
	var invite_title := Label.new()
	invite_title.text = "INVITE YOUR SQUAD"
	invite_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	invite_title.add_theme_color_override("font_color", Color("8bc5ae"))
	invite_column.add_child(invite_title)
	var invite_row := HBoxContainer.new()
	invite_column.add_child(invite_row)
	invite_code_edit = LineEdit.new()
	invite_code_edit.name = "HostInviteCode"
	invite_code_edit.editable = false
	invite_code_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	invite_code_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	invite_row.add_child(invite_code_edit)
	invite_copy_button = Button.new()
	invite_copy_button.name = "CopyHostInviteCode"
	invite_copy_button.text = "COPY CODE"
	invite_copy_button.pressed.connect(_copy_host_invite)
	invite_row.add_child(invite_copy_button)
	invite_help_label = Label.new()
	invite_help_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	invite_help_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	invite_help_label.add_theme_font_size_override("font_size", 12)
	invite_help_label.add_theme_color_override("font_color", Color("aeb9c9"))
	invite_column.add_child(invite_help_label)
	column.add_child(HSeparator.new())
	lobby_roster_label = RichTextLabel.new()
	lobby_roster_label.name = "LobbyPlayerRoster"
	lobby_roster_label.bbcode_enabled = true
	lobby_roster_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	lobby_roster_label.add_theme_font_size_override("normal_font_size", 16)
	column.add_child(lobby_roster_label)
	pair_selector_row = HBoxContainer.new()
	pair_selector_row.name = "LobbyPairSelectorRow"
	pair_selector_row.add_theme_constant_override("separation", 10)
	column.add_child(pair_selector_row)
	var pair_label := Label.new()
	pair_label.text = "YOUR DUO"
	pair_label.add_theme_color_override("font_color", Color("f2cf6a"))
	pair_selector_row.add_child(pair_label)
	pair_selector = OptionButton.new()
	pair_selector.name = "LobbyPairSelector"
	pair_selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for pair_id in LobbyState.MAX_PAIRS:
		pair_selector.add_item("PAIR %02d" % (pair_id + 1), pair_id)
	pair_selector.item_selected.connect(_on_pair_selected)
	pair_selector_row.add_child(pair_selector)
	team_selector_row = HBoxContainer.new()
	team_selector_row.name = "LobbyTeamSelectorRow"
	team_selector_row.add_theme_constant_override("separation", 10)
	column.add_child(team_selector_row)
	alpha_team_button = _team_button("ChooseAlphaTeamButton", "JOIN ALPHA", Color("6eb6ff"), 0)
	bravo_team_button = _team_button("ChooseBravoTeamButton", "JOIN BRAVO", Color("ff7d76"), 1)
	team_selector_row.add_child(alpha_team_button)
	team_selector_row.add_child(bravo_team_button)
	ready_button = Button.new()
	ready_button.name = "GreenUpReadyButton"
	ready_button.text = "○ NOT READY — GREEN UP"
	ready_button.custom_minimum_size.y = 54
	ready_button.pressed.connect(func(): ready_requested.emit())
	column.add_child(ready_button)
	warmup_button = Button.new()
	warmup_button.name = "EnterWarmupButton"
	warmup_button.text = "TRAINING GROUNDS • TRY WEAPONS TOGETHER"
	warmup_button.visible = false
	warmup_button.custom_minimum_size.y = 44
	warmup_button.pressed.connect(func(): warmup_requested.emit())
	column.add_child(warmup_button)
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


func _on_pair_selected(index: int) -> void:
	if index < 0 or index >= pair_selector.item_count:
		return
	pair_requested.emit(pair_selector.get_item_id(index))


func _set_lobby_message(message: String, color: Color) -> void:
	lobby_status_label.text = message
	lobby_status_label.add_theme_color_override("font_color", color)
