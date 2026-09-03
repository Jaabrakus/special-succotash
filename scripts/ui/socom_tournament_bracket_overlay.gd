class_name SocomTournamentBracketOverlay
extends CanvasLayer

## Live in-game tournament bracket overlay showing active pairings, round scores,
## eliminations, and synchronous 5-second intermission countdowns.

signal intermission_completed

var background: ColorRect
var container: PanelContainer
var title_label: Label
var stage_label: Label
var bracket_table: RichTextLabel
var countdown_label: Label
var close_button: Button

var is_intermission: bool = false
var countdown_remaining: float = 0.0


func _init() -> void:
	layer = 15


func _ready() -> void:
	_build_ui()
	visible = false


func _build_ui() -> void:
	background = ColorRect.new()
	background.color = Color(0.02, 0.04, 0.06, 0.85)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	container = PanelContainer.new()
	container.custom_minimum_size = Vector2(800.0, 520.0)
	center.add_child(container)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, 20)
	container.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	margin.add_child(vbox)

	title_label = Label.new()
	title_label.text = "★ 141 GUNFIGHT TOURNAMENT BRACKET ★"
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", 22)
	title_label.add_theme_color_override("font_color", Color("8bc5ae"))
	vbox.add_child(title_label)

	stage_label = Label.new()
	stage_label.text = "STAGE: ROUND OF 16"
	stage_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stage_label.add_theme_font_size_override("font_size", 16)
	stage_label.add_theme_color_override("font_color", Color("f2cf6a"))
	vbox.add_child(stage_label)

	bracket_table = RichTextLabel.new()
	bracket_table.bbcode_enabled = true
	bracket_table.custom_minimum_size.y = 280.0
	bracket_table.size_flags_vertical = Control.SIZE_EXPAND_FILL
	bracket_table.add_theme_font_size_override("normal_font_size", 14)
	vbox.add_child(bracket_table)

	countdown_label = Label.new()
	countdown_label.text = "NEXT MATCH COMMENCING IN: 5s"
	countdown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	countdown_label.add_theme_font_size_override("font_size", 18)
	countdown_label.add_theme_color_override("font_color", Color("70f59b"))
	vbox.add_child(countdown_label)

	close_button = Button.new()
	close_button.text = "DISMISS BRACKET [TAB]"
	close_button.custom_minimum_size.y = 36.0
	close_button.pressed.connect(func(): visible = false)
	vbox.add_child(close_button)


func render_bracket(bracket_data: Dictionary, current_pair_id: int = -1) -> void:
	var stage: String = String(bracket_data.get("current_stage", "TOURNAMENT"))
	stage_label.text = "STAGE: %s" % stage.to_upper()

	var matchups: Array = bracket_data.get("bracket", [])
	var rows: Array[String] = []
	rows.append("[cell][b]MATCH[/b][/cell][cell][b]PAIR ALPHA[/b][/cell][cell][b]SCORE[/b][/cell][cell][b]PAIR BRAVO[/b][/cell][cell][b]STATUS[/b][/cell]")

	var m_idx := 1
	for m_dict in matchups:
		var p_a: int = int(m_dict.get("pair_a", -1))
		var p_b: int = int(m_dict.get("pair_b", -1))
		var s_a: int = int(m_dict.get("score_a", 0))
		var s_b: int = int(m_dict.get("score_b", 0))
		var winner: int = int(m_dict.get("winner_pair", -1))
		var completed: bool = bool(m_dict.get("is_completed", false))

		var color_a := "#7df0ad" if p_a == current_pair_id else ("#70f59b" if winner == p_a else "#d8dde6")
		var color_b := "#7df0ad" if p_b == current_pair_id else ("#70f59b" if winner == p_b else "#d8dde6")
		var status_str := "[color=#70f59b]★ ADVANCED[/color]" if completed else "[color=#f2cf6a]● IN PROGRESS[/color]"

		rows.append("[cell]#%d[/cell]" % m_idx)
		rows.append("[cell][color=%s]PAIR %02d[/color][/cell]" % [color_a, p_a + 1])
		rows.append("[cell][b]%d  —  %d[/b][/cell]" % [s_a, s_b])
		rows.append("[cell][color=%s]PAIR %02d[/color][/cell]" % [color_b, p_b + 1 if p_b >= 0 else 0])
		rows.append("[cell]%s[/cell]" % status_str)
		m_idx += 1

	bracket_table.text = "[table=5]\n%s\n[/table]" % "\n".join(rows)


func start_intermission_countdown(seconds: float = 5.0) -> void:
	is_intermission = true
	countdown_remaining = seconds
	visible = true
	countdown_label.visible = true


func _process(delta: float) -> void:
	if not is_intermission:
		return

	countdown_remaining -= delta
	if countdown_remaining > 0.0:
		countdown_label.text = "NEXT MATCH COMMENCING IN: %ds" % int(ceil(countdown_remaining))
	else:
		is_intermission = false
		countdown_label.text = "MATCH LIVE"
		intermission_completed.emit()
