class_name SocomRoundScoreStrip
extends Control

## Persistent top-center round/match state strip for round-based modes.
## Dumb view only: the host pushes state via update_round_score and this
## control draws. No input, no polling, no gameplay access — mirrors the
## loadout card's conventions and palette.

const COLOR_BG := Color(0.015, 0.022, 0.028, 0.85)
const COLOR_BORDER := Color("c8a66b", 0.45)
const COLOR_BORDER_MATCH_POINT := Color("f2cf6a", 0.95)
const COLOR_ALPHA := Color("6eb6ff")
const COLOR_BRAVO := Color("ff7d76")
const COLOR_TEXT := Color("aeb9c9")
const COLOR_DIM := Color("7f8b9c")
const COLOR_TIMER := Color("a9f4c0")
const COLOR_TIMER_LOW := Color("f2cf6a")
const COLOR_TIMER_CRITICAL := Color("ff6b6b")
const COLOR_PIP_OFF := Color(1.0, 1.0, 1.0, 0.14)
const COLOR_PHASE := Color("c8a66b")
const COLOR_PHASE_MATCH_POINT := Color("f2cf6a")
const COLOR_PHASE_OVERTIME := Color("ff6b6b")

const PANEL_WIDTH := 480.0
const PANEL_HEIGHT := 76.0

var alpha_wins: int = 0
var bravo_wins: int = 0
var alpha_label := "ALPHA"
var bravo_label := "BRAVO"
var maximum_rounds: int = 11
var rounds_to_win: int = 6
var round_index: int = 1
var seconds_remaining: float = 0.0
var phase_label: String = "LIVE"
var phase_kind: StringName = &"live"  # live|buy|round_end|match_point|overtime|match_end


func _ready() -> void:
	custom_minimum_size = Vector2(PANEL_WIDTH, PANEL_HEIGHT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	offset_left = -PANEL_WIDTH * 0.5
	offset_right = PANEL_WIDTH * 0.5
	offset_top = 14.0
	offset_bottom = 14.0 + PANEL_HEIGHT


## Pushed by the host whenever round state changes. Nothing here mutates
## gameplay; it exists to be rendered and regression-asserted.
func update_round_score(
	alpha: int,
	bravo: int,
	max_rounds: int,
	to_win: int,
	current_round: int,
	seconds: float,
	phase: String,
	kind: StringName = &"live"
) -> void:
	alpha_wins = maxi(0, alpha)
	bravo_wins = maxi(0, bravo)
	maximum_rounds = maxi(3, max_rounds)
	rounds_to_win = maxi(1, to_win)
	round_index = maxi(1, current_round)
	seconds_remaining = maxf(0.0, seconds)
	phase_label = phase
	phase_kind = kind
	queue_redraw()


## The Square's axis words for teams 0/1. Defaults keep the classic labels so
## the strip is presentable before a match applies its nomenclature.
func set_team_labels(word_0: String, word_1: String) -> void:
	alpha_label = word_0
	bravo_label = word_1
	queue_redraw()


func _draw() -> void:
	var panel := StyleBoxFlat.new()
	panel.bg_color = COLOR_BG
	panel.set_corner_radius_all(7)
	panel.set_border_width_all(1)
	panel.border_color = (
		COLOR_BORDER_MATCH_POINT
		if _is_match_point()
		else COLOR_BORDER
	)
	draw_style_box(panel, Rect2(Vector2.ZERO, size))

	var font := ThemeDB.fallback_font
	var center_x := size.x * 0.5

	_draw_team_block(font, alpha_label, alpha_wins, 26.0, COLOR_ALPHA, false)
	_draw_team_block(font, bravo_label, bravo_wins, size.x - 26.0, COLOR_BRAVO, true)
	_draw_timer(font, center_x)
	_draw_pips(center_x)
	_draw_phase_label(font, center_x)


func _draw_team_block(
	font: Font,
	team_name: String,
	wins: int,
	anchor_x: float,
	color: Color,
	right_aligned: bool
) -> void:
	# draw_string ignores alignment without a width box, so position both
	# strings manually: left-aligned grows right from the anchor, right-aligned
	# grows left.
	var name_width := font.get_string_size(team_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
	var name_x := anchor_x - name_width if right_aligned else anchor_x
	draw_string(font, Vector2(name_x, 26.0), team_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, color)
	var score_text := str(wins)
	var score_width := font.get_string_size(score_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 30).x
	var score_x := anchor_x - score_width if right_aligned else anchor_x
	var score_color := color if wins > 0 else COLOR_DIM
	draw_string(font, Vector2(score_x, 60.0), score_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 30, score_color)


func _draw_timer(font: Font, center_x: float) -> void:
	var seconds := ceili(seconds_remaining)
	var minutes := seconds / 60
	var remaining := seconds % 60
	var text := "%d:%02d" % [minutes, remaining]
	var color := COLOR_TIMER
	if seconds <= 5:
		color = COLOR_TIMER_CRITICAL
	elif seconds <= 10:
		color = COLOR_TIMER_LOW
	draw_string(
		font,
		Vector2(center_x, 34.0),
		text,
		HORIZONTAL_ALIGNMENT_CENTER,
		-1,
		24,
		color
	)


func _draw_pips(center_x: float) -> void:
	var total := mini(maximum_rounds, 15)
	var spacing := 13.0
	var half := float(total) * 0.5
	var row_y := 48.0
	var alpha_slots := int(ceil(float(total) * 0.5))
	for pip_index in total:
		var offset := float(pip_index) - half + 0.5
		var pip_x := center_x + offset * spacing
		var is_alpha_pip := pip_index < alpha_slots
		# Wins fill from the centre outward: alpha's innermost pip is the last
		# index on its side, bravo's innermost is its first.
		var filled_alpha := is_alpha_pip and (alpha_slots - 1 - pip_index) < alpha_wins
		var filled_bravo := (not is_alpha_pip) and (pip_index - alpha_slots) < bravo_wins
		var color := COLOR_PIP_OFF
		if filled_alpha:
			color = COLOR_ALPHA
		elif filled_bravo:
			color = COLOR_BRAVO
		draw_circle(Vector2(pip_x, row_y), 3.5, color)


func _draw_phase_label(font: Font, center_x: float) -> void:
	var color := COLOR_PHASE
	match phase_kind:
		&"match_point":
			color = COLOR_PHASE_MATCH_POINT
		&"overtime":
			color = COLOR_PHASE_OVERTIME
		&"buy":
			color = COLOR_TIMER
		_:
			color = COLOR_PHASE
	draw_string(
		font,
		Vector2(center_x, 68.0),
		phase_label.to_upper(),
		HORIZONTAL_ALIGNMENT_CENTER,
		-1,
		11,
		color
	)


func _is_match_point() -> bool:
	return (
		alpha_wins == rounds_to_win - 1
		or bravo_wins == rounds_to_win - 1
	)
