class_name SocomTournamentBracketOverlay
extends Control

## Displays full tournament tree progression, stage transitions, advancing pairs,
## and authoritative countdown timers between tournament stages.

var background: ColorRect
var center_panel: PanelContainer
var title_label: Label
var stage_label: Label
var countdown_label: Label
var bracket_tree_label: RichTextLabel

var is_showing: bool = false
var countdown_seconds: float = 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_IGNORE
	visible = false
	_build_ui()


func _build_ui() -> void:
	background = ColorRect.new()
	background.color = Color(0.06, 0.08, 0.11, 0.88)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	center_panel = PanelContainer.new()
	center_panel.custom_minimum_size = Vector2(860.0, 560.0)
	center.add_child(center_panel)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, 24)
	center_panel.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)

	title_label = Label.new()
	title_label.text = "★ SOCOM-141 GUNFIGHT TOURNAMENT BRACKET ★"
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", 22)
	title_label.add_theme_color_override("font_color", Color("8bc5ae"))
	column.add_child(title_label)

	stage_label = Label.new()
	stage_label.text = "STAGE TRANSITION"
	stage_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stage_label.add_theme_font_size_override("font_size", 16)
	stage_label.add_theme_color_override("font_color", Color("f2cf6a"))
	column.add_child(stage_label)

	countdown_label = Label.new()
	countdown_label.text = "NEXT STAGE STARTING IN 5"
	countdown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	countdown_label.add_theme_font_size_override("font_size", 26)
	countdown_label.add_theme_color_override("font_color", Color("70f59b"))
	column.add_child(countdown_label)

	column.add_child(HSeparator.new())

	bracket_tree_label = RichTextLabel.new()
	bracket_tree_label.bbcode_enabled = true
	bracket_tree_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	bracket_tree_label.add_theme_font_size_override("normal_font_size", 15)
	column.add_child(bracket_tree_label)


func show_stage_transition(stage_name: String, countdown: float, bracket_data: Dictionary) -> void:
	is_showing = true
	countdown_seconds = countdown
	visible = true
	stage_label.text = "%s COMPLETE • UPDATING BRACKET" % stage_name.to_upper()
	_update_countdown_display()
	_render_bracket(bracket_data)


func hide_overlay() -> void:
	is_showing = false
	visible = false


func update_countdown(remaining: float) -> void:
	countdown_seconds = remaining
	_update_countdown_display()


func _update_countdown_display() -> void:
	var sec := ceili(countdown_seconds)
	if sec <= 0:
		countdown_label.text = "LAUNCHING NEXT MATCHES..."
		countdown_label.add_theme_color_override("font_color", Color("70f59b"))
	else:
		countdown_label.text = "NEXT STAGE STARTS IN %d" % sec
		countdown_label.add_theme_color_override("font_color", Color("70f59b") if sec <= 3 else Color("f2cf6a"))


func _render_bracket(bracket_data: Dictionary) -> void:
	var matchups: Array = bracket_data.get("bracket", [])
	if matchups.is_empty():
		bracket_tree_label.text = "[center][color=#aeb9c9]Generating next stage matchups...[/color][/center]"
		return

	var lines: Array[String] = []
	for m in matchups:
		var match_dict := m as Dictionary
		var pair_a := int(match_dict.get("pair_a", -1)) + 1
		var pair_b := int(match_dict.get("pair_b", -1)) + 1
		var score_a := int(match_dict.get("score_a", 0))
		var score_b := int(match_dict.get("score_b", 0))
		var winner := int(match_dict.get("winner_pair", -1))
		var is_done := bool(match_dict.get("is_completed", false))
		var stage := String(match_dict.get("stage", "MATCH"))

		var tag_a := ""
		var tag_b := ""
		if is_done:
			if winner == pair_a - 1:
				tag_a = " [color=#70f59b]★ ADVANCED[/color]"
				tag_b = " [color=#ff7d76]✕ ELIMINATED[/color]"
			else:
				tag_a = " [color=#ff7d76]✕ ELIMINATED[/color]"
				tag_b = " [color=#70f59b]★ ADVANCED[/color]"

		var match_line := "[cell][color=#f2cf6a]%s[/color]\n[color=#6eb6ff]PAIR %02d[/color] [%d]%s\n[color=#ff7d76]PAIR %02d[/color] [%d]%s[/cell]" % [
			stage, pair_a, score_a, tag_a, pair_b, score_b, tag_b
		]
		lines.append(match_line)

	bracket_tree_label.text = "[table=4]\n%s\n[/table]" % "\n".join(lines)
