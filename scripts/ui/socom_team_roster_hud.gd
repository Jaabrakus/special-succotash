class_name SocomTeamRosterHUD
extends Control

## Authentic SOCOM 2 Tactical Match Scorecard & SITREP
## Ported from reCOM (data/s1/common/dialog/dlgMultiplayerRound.rdr, CTeamNames, CTeamMateNames)
## Toggled / held via Tab key (SELECT button on PS2).

const FACTION_DATA := {
	0: {"name": "TENET", "color": Color("6eb6ff"), "accent": Color("9df2cd")},
	1: {"name": "PHANTOM", "color": Color("ff7d76"), "accent": Color("f2cf6a")},
}

const SCORECARD_WIDTH := 680.0
const SCORECARD_HEIGHT := 340.0

var is_scorecard_open: bool = false

var team_alpha_score: int = 0
var team_bravo_score: int = 0
var round_timer_seconds: float = 180.0
var bomb_status_text: String = "SATCHEL BOMB AT SPAWN"
var is_bomb_armed: bool = false

var alpha_players: Array[Dictionary] = [
	{"name": "SPECTRE (YOU)", "alive": true, "kills": 3, "deaths": 0, "ping": 24},
	{"name": "JESTER", "alive": true, "kills": 1, "deaths": 1, "ping": 32},
	{"name": "WARDOG", "alive": true, "kills": 2, "deaths": 1, "ping": 45},
	{"name": "BOOMER", "alive": false, "kills": 0, "deaths": 1, "ping": 38},
]

var bravo_players: Array[Dictionary] = [
	{"name": "TANGO-1", "alive": true, "kills": 1, "deaths": 2, "ping": 50},
	{"name": "TANGO-2", "alive": true, "kills": 1, "deaths": 2, "ping": 42},
	{"name": "TANGO-3", "alive": false, "kills": 0, "deaths": 1, "ping": 64},
	{"name": "TANGO-4", "alive": false, "kills": 0, "deaths": 1, "ping": 58},
]


func _ready() -> void:
	custom_minimum_size = Vector2(SCORECARD_WIDTH, SCORECARD_HEIGHT)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_IGNORE
	visible = false


func show_scorecard(show: bool) -> void:
	is_scorecard_open = show
	visible = show
	if show:
		queue_redraw()


func set_roster_data(
	alpha: Array,
	bravo: Array,
	alpha_score: int = -1,
	bravo_score: int = -1,
	timer_sec: float = -1.0,
	bomb_msg: String = "",
	bomb_armed: bool = false
) -> void:
	alpha_players.clear()
	for p: Variant in alpha:
		if p is Dictionary:
			alpha_players.append((p as Dictionary).duplicate(true))
	bravo_players.clear()
	for p: Variant in bravo:
		if p is Dictionary:
			bravo_players.append((p as Dictionary).duplicate(true))
	if alpha_score >= 0:
		team_alpha_score = alpha_score
	if bravo_score >= 0:
		team_bravo_score = bravo_score
	if timer_sec >= 0.0:
		round_timer_seconds = timer_sec
	if not bomb_msg.is_empty():
		bomb_status_text = bomb_msg
	is_bomb_armed = bomb_armed
	if visible:
		queue_redraw()


func update_match_state(
	alpha_alive: int, alpha_total: int, alpha_score: int,
	bravo_alive: int, bravo_total: int, bravo_score: int,
	timer_sec: float, bomb_state_msg: String = "", bomb_armed: bool = false
) -> void:
	team_alpha_score = alpha_score
	team_bravo_score = bravo_score
	round_timer_seconds = timer_sec
	if not bomb_state_msg.is_empty():
		bomb_status_text = bomb_state_msg
	is_bomb_armed = bomb_armed
	if visible:
		queue_redraw()


func _draw() -> void:
	if not visible:
		return

	var center := size * 0.5
	var card_rect := Rect2(center.x - SCORECARD_WIDTH * 0.5, center.y - SCORECARD_HEIGHT * 0.5, SCORECARD_WIDTH, SCORECARD_HEIGHT)
	var font := ThemeDB.fallback_font

	# Outer Tactical Background
	draw_rect(card_rect, Color(0.015, 0.022, 0.028, 0.94))
	draw_rect(card_rect, Color(0.25, 0.35, 0.38, 0.75), false, 2.0)

	# --- Header Bar ---
	var header_rect := Rect2(card_rect.position.x, card_rect.position.y, SCORECARD_WIDTH, 44.0)
	draw_rect(header_rect, Color(0.03, 0.05, 0.07, 0.98))
	draw_line(header_rect.position + Vector2(0.0, 44.0), header_rect.position + Vector2(SCORECARD_WIDTH, 44.0), Color("c8a66b"), 1.5)

	# Title & Clock
	draw_string(font, header_rect.position + Vector2(16.0, 28.0), "SITREP  •  DEMOLITION", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("e3d3b3"))

	var minutes := int(round_timer_seconds) / 60
	var seconds := int(round_timer_seconds) % 60
	var time_str := "%02d:%02d" % [minutes, seconds]
	if is_bomb_armed:
		time_str = "💣 " + time_str
	draw_string(font, header_rect.position + Vector2(SCORECARD_WIDTH - 120.0, 28.0), time_str, HORIZONTAL_ALIGNMENT_RIGHT, -1, 16, Color("ff4444") if is_bomb_armed else Color("ffffff"))

	# --- Score Summary Banner ---
	var banner_y := card_rect.position.y + 70.0
	var alpha_col: Color = FACTION_DATA[0]["color"]
	var bravo_col: Color = FACTION_DATA[1]["color"]

	var alpha_header := "%s  (ROUNDS: %d)" % [FACTION_DATA[0]["name"], team_alpha_score]
	draw_string(font, Vector2(card_rect.position.x + 24.0, banner_y), alpha_header, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, alpha_col)

	var bravo_header := "%s  (ROUNDS: %d)" % [FACTION_DATA[1]["name"], team_bravo_score]
	draw_string(font, Vector2(center.x + 24.0, banner_y), bravo_header, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, bravo_col)

	# Column headers
	var col_header_y := banner_y + 24.0
	draw_string(font, Vector2(card_rect.position.x + 40.0, col_header_y), "OPERATOR", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("8fa09b"))
	draw_string(font, Vector2(center.x - 110.0, col_header_y), "K / D", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("8fa09b"))
	draw_string(font, Vector2(center.x - 50.0, col_header_y), "PING", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("8fa09b"))

	draw_string(font, Vector2(center.x + 40.0, col_header_y), "OPERATOR", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("8fa09b"))
	draw_string(font, Vector2(card_rect.end.x - 110.0, col_header_y), "K / D", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("8fa09b"))
	draw_string(font, Vector2(card_rect.end.x - 50.0, col_header_y), "PING", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("8fa09b"))

	# Divider line between teams
	draw_line(Vector2(center.x, banner_y - 10.0), Vector2(center.x, card_rect.end.y - 40.0), Color(0.20, 0.28, 0.32, 0.60), 1.0)

	# --- Team 0 Rows ---
	var row_y := col_header_y + 24.0
	for p in alpha_players:
		var alive: bool = p.get("alive", true)
		var pip_col := alpha_col if alive else Color(0.5, 0.2, 0.2, 0.6)
		# Status pip
		draw_circle(Vector2(card_rect.position.x + 28.0, row_y - 4.0), 3.5, pip_col)
		var text_col := Color("ffffff") if alive else Color("7a8588")
		draw_string(font, Vector2(card_rect.position.x + 40.0, row_y), String(p.get("name", "")), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, text_col)
		draw_string(font, Vector2(center.x - 110.0, row_y), "%d / %d" % [int(p.get("kills", 0)), int(p.get("deaths", 0))], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, text_col)
		draw_string(font, Vector2(center.x - 50.0, row_y), "%dms" % int(p.get("ping", 30)), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, text_col)
		row_y += 24.0

	# --- Team 1 Rows ---
	row_y = col_header_y + 24.0
	for p in bravo_players:
		var alive: bool = p.get("alive", true)
		var pip_col := bravo_col if alive else Color(0.5, 0.2, 0.2, 0.6)
		draw_circle(Vector2(center.x + 28.0, row_y - 4.0), 3.5, pip_col)
		var text_col := Color("ffffff") if alive else Color("7a8588")
		draw_string(font, Vector2(center.x + 40.0, row_y), String(p.get("name", "")), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, text_col)
		draw_string(font, Vector2(card_rect.end.x - 110.0, row_y), "%d / %d" % [int(p.get("kills", 0)), int(p.get("deaths", 0))], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, text_col)
		draw_string(font, Vector2(card_rect.end.x - 50.0, row_y), "%dms" % int(p.get("ping", 30)), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, text_col)
		row_y += 24.0

	# --- Bottom Status Bar ---
	var footer_y := card_rect.end.y - 16.0
	var status_col := Color("ff5548") if is_bomb_armed else Color("9df2cd")
	draw_string(font, Vector2(card_rect.position.x + 20.0, footer_y), "OBJECTIVE: %s" % bomb_status_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, status_col)
	draw_string(font, Vector2(card_rect.end.x - 180.0, footer_y), "HOLD TAB • SITREP", HORIZONTAL_ALIGNMENT_RIGHT, -1, 11, Color("8fa09b"))
