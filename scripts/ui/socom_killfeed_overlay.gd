class_name SocomKillfeedOverlay
extends Control

## Authentic SOCOM 2 Multiplayer Killfeed & Score Popup System
## Ported from reCOM (Apps/FTS/hud/hud_scorepopup.cpp)

const MAX_KILL_ROWS := 5
const ROW_LIFETIME := 5.0

const FACTION_COLORS := {
	0: Color("6eb6ff"), # TENET
	1: Color("ff7d76"), # PHANTOM
}

var kill_entries: Array[Dictionary] = []
var score_popups: Array[Dictionary] = []


func _ready() -> void:
	custom_minimum_size = Vector2(400, 240)
	set_anchors_preset(Control.PRESET_TOP_RIGHT)
	offset_left = -420.0
	offset_top = 58.0
	offset_right = -20.0
	offset_bottom = 300.0
	mouse_filter = MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	var needs_redraw := false

	# Age kill feed entries
	for i in range(kill_entries.size() - 1, -1, -1):
		kill_entries[i]["time"] -= delta
		if kill_entries[i]["time"] <= 0.0:
			kill_entries.remove_at(i)
		needs_redraw = true

	# Age score popups
	for i in range(score_popups.size() - 1, -1, -1):
		score_popups[i]["time"] -= delta
		score_popups[i]["offset_y"] -= delta * 18.0
		if score_popups[i]["time"] <= 0.0:
			score_popups.remove_at(i)
		needs_redraw = true

	if needs_redraw:
		queue_redraw()


func add_kill(
	killer: String, killer_team: int,
	victim: String, victim_team: int,
	weapon: String = "M4A1", headshot: bool = false
) -> void:
	if kill_entries.size() >= MAX_KILL_ROWS:
		kill_entries.pop_front()
	kill_entries.append({
		"killer": killer,
		"killer_team": killer_team,
		"victim": victim,
		"victim_team": victim_team,
		"weapon": weapon,
		"headshot": headshot,
		"time": ROW_LIFETIME,
	})
	queue_redraw()


func add_score_toast(title: String, points: int) -> void:
	score_popups.append({
		"title": title,
		"points": points,
		"time": 2.2,
		"offset_y": 0.0,
	})
	queue_redraw()


func _draw() -> void:
	var font := ThemeDB.fallback_font
	var y_offset := 0.0

	# 1. Render Killfeed Rows
	for entry in kill_entries:
		var alpha: float = clampf(float(entry.get("time", 1.0)) / 0.8, 0.0, 1.0)
		var k_col: Color = FACTION_COLORS.get(int(entry.get("killer_team", 0)), Color("6eb6ff"))
		k_col.a = alpha
		var v_col: Color = FACTION_COLORS.get(int(entry.get("victim_team", 1)), Color("ff7d76"))
		v_col.a = alpha
		var weapon_str: String = " 🔫 %s " % entry.get("weapon", "RIFLE")
		if bool(entry.get("headshot", false)):
			weapon_str += "💀 "

		var killer_str: String = entry.get("killer", "SPECTRE")
		var victim_str: String = entry.get("victim", "TARGET")

		var row_text := "%s%s%s" % [killer_str, weapon_str, victim_str]
		var text_sz := font.get_string_size(row_text, HORIZONTAL_ALIGNMENT_RIGHT, -1, 13)
		var start_x := size.x - text_sz.x - 10.0

		# Background plate
		draw_rect(Rect2(start_x - 6.0, y_offset, text_sz.x + 12.0, 22.0), Color(0.015, 0.022, 0.028, 0.70 * alpha))

		# Draw killer name
		draw_string(font, Vector2(start_x, y_offset + 16.0), killer_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, k_col)
		var k_width := font.get_string_size(killer_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x

		# Draw weapon icon
		draw_string(font, Vector2(start_x + k_width, y_offset + 16.0), weapon_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.85, 0.88, 0.90, alpha))
		var w_width := font.get_string_size(weapon_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x

		# Draw victim name
		draw_string(font, Vector2(start_x + k_width + w_width, y_offset + 16.0), victim_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, v_col)

		y_offset += 26.0

	# 2. Render Score Toasts
	var toast_y := 160.0
	for popup in score_popups:
		var p_alpha: float = clampf(float(popup.get("time", 1.0)) / 0.6, 0.0, 1.0)
		var str_val := "+%d %s" % [int(popup.get("points", 100)), String(popup.get("title", "SCORE"))]
		var col := Color("f2cf6a")
		col.a = p_alpha
		var cur_y := toast_y + float(popup.get("offset_y", 0.0))
		draw_string(font, Vector2(size.x - 220.0, cur_y), str_val, HORIZONTAL_ALIGNMENT_RIGHT, -1, 15, col)
		toast_y += 24.0
