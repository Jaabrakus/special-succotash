class_name SocomTournamentLobbyPanel
extends CanvasLayer

## Tournament lobby panel (docs/SQUARE_DESIGN_LANGUAGE.md). Dumb view: it
## renders a pushed tournament snapshot and emits intents. Squad mutations
## always travel to the host; this panel never touches the model.

signal create_squad_requested(squad_name: String, house: String)
signal join_squad_requested(squad_id: String)
signal ready_toggled(ready: bool)
signal lock_bracket_requested

const HOUSES: Array[String] = ["(NO HOUSE)", "SATOR", "AREPO", "TENET", "OPERA", "ROTAS"]

var panel: PanelContainer
var body: VBoxContainer
var squads_label: RichTextLabel
var bracket_label: RichTextLabel
var phase_label: Label
var name_edit: LineEdit
var house_selector: OptionButton
var create_button: Button
var join_button: Button
var ready_button: Button
var lock_button: Button
var _selected_squad_id := ""
var _local_ready := false


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_build_ui()


func show_panel(enabled: bool) -> void:
	visible = enabled
	if enabled:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


## snapshot is SocomTournamentModel.snapshot(); local_peer selects highlight
## and controls visibility.
func update_state(snapshot: Dictionary, local_peer: int) -> void:
	if panel == null:
		return
	var state := String(snapshot.get("state", "registration"))
	var squads: Dictionary = snapshot.get("squads", {}) as Dictionary
	var pods: Array = snapshot.get("pods", []) as Array

	phase_label.text = _phase_text(state, squads.size())
	_render_squads(squads, local_peer)
	bracket_label.text = _render_bracket(pods, snapshot.get("champion", ""))
	create_button.disabled = state != "registration" or squads.size() >= 16
	join_button.disabled = state != "registration" or _selected_squad_id.is_empty()
	lock_button.disabled = state != "registration" or not _all_squads_ready(squads)
	ready_button.text = "UNREADY" if _local_ready else "READY UP"


func _phase_text(state: String, squad_count: int) -> String:
	match state:
		"registration":
			return "REGISTRATION  •  %d / 16 SQUADS" % squad_count
		"running":
			return "THE SQUARE IS RUNNING"
		"complete":
			return "THE SQUARE IS COMPLETE"
	return state


func _render_squads(squads: Dictionary, local_peer: int) -> void:
	var lines: Array[String] = []
	var sorted_ids: Array = squads.keys()
	sorted_ids.sort()
	for raw_id: Variant in sorted_ids:
		var squad: Dictionary = squads[raw_id] as Dictionary
		var members: Array = squad.get("members", []) as Array
		var mine := members.has(local_peer)
		var house := String(squad.get("house", ""))
		var status := "READY" if bool(squad.get("ready", false)) else ("[%s]" % house if house != "" else "open")
		lines.append(
			"[url=%s]%s %s  %d/2  %s[/url]" % [
				String(squad.get("id", "")),
				"►" if mine else "•",
				String(squad.get("name", "")),
				members.size(),
				status,
			]
		)
	squads_label.clear()
	for line: String in lines:
		squads_label.append_text(line + "\n")


func _render_bracket(pods: Array, champion: String) -> String:
	if pods.is_empty():
		return "[i]The bracket appears when registration locks.[/i]"
	var lines: Array[String] = []
	var by_round := {}
	for raw_pod: Variant in pods:
		var pod := raw_pod as Dictionary
		var round_number := int(pod.get("round", 0))
		if not by_round.has(round_number):
			by_round[round_number] = []
		(by_round[round_number] as Array).append(pod)
	for round_number: int in [1, 2, 3, 4]:
		if not by_round.has(round_number):
			continue
		lines.append("[color=#c8a66b]%s[/color]" % _round_name(round_number))
		for raw_pod: Variant in (by_round[round_number] as Array):
			var pod := raw_pod as Dictionary
			lines.append("  " + _pod_line(pod))
	if champion != "":
		lines.append("")
		lines.append("[color=#f2cf6a]TENET  —  %s[/color]" % _squad_display(String(champion)))
	return "\n".join(lines)


func _round_name(round_number: int) -> String:
	match round_number:
		1:
			return "OPENING PODS"
		2:
			return "QUARTERFINALS"
		3:
			return "SEMIFINALS"
		4:
			return "FINAL  •  THE CENTER"
	return "ROUND %d" % round_number


func _pod_line(pod: Dictionary) -> String:
	var squad_a := String(pod.get("squad_a", ""))
	var squad_b := String(pod.get("squad_b", ""))
	var winner := String(pod.get("winner", ""))
	var state := String(pod.get("state", "pending"))
	var text := "%s vs %s" % [_squad_display(squad_a), _squad_display(squad_b)]
	if winner != "":
		text += "  →  [color=#70f59b]%s[/color]" % _squad_display(winner)
	elif state == "live":
		text += "  [LIVE]"
	return text


func _squad_display(squad_id: String) -> String:
	return squad_id if squad_id != "" else "—"


func _all_squads_ready(squads: Dictionary) -> bool:
	if squads.size() != 16:
		return false
	for raw_squad: Variant in squads.values():
		var squad := raw_squad as Dictionary
		if (squad.get("members", []) as Array).size() != 2 or not bool(squad.get("ready", false)):
			return false
	return true


func _build_ui() -> void:
	panel = PanelContainer.new()
	panel.name = "TournamentLobbyPanel"
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(760.0, 640.0)
	add_child(panel)
	var margin := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, 24)
	panel.add_child(margin)
	body = VBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	margin.add_child(body)

	var title := Label.new()
	title.text = "THE SQUARE"
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color("8bc5ae"))
	body.add_child(title)

	phase_label = Label.new()
	phase_label.add_theme_font_size_override("font_size", 14)
	phase_label.add_theme_color_override("font_color", Color("f2cf6a"))
	body.add_child(phase_label)

	squads_label = RichTextLabel.new()
	squads_label.bbcode_enabled = true
	squads_label.fit_content = false
	squads_label.custom_minimum_size = Vector2(0.0, 150.0)
	squads_label.meta_clicked.connect(_on_squad_clicked)
	body.add_child(squads_label)

	var entry_row := HBoxContainer.new()
	entry_row.add_theme_constant_override("separation", 8)
	body.add_child(entry_row)
	name_edit = LineEdit.new()
	name_edit.placeholder_text = "Squad name"
	name_edit.custom_minimum_size = Vector2(220.0, 40.0)
	entry_row.add_child(name_edit)
	house_selector = OptionButton.new()
	house_selector.custom_minimum_size = Vector2(140.0, 40.0)
	for house: String in HOUSES:
		house_selector.add_item(house)
	entry_row.add_child(house_selector)
	create_button = _button("CREATE SQUAD", _on_create_pressed)
	entry_row.add_child(create_button)

	var action_row := HBoxContainer.new()
	action_row.add_theme_constant_override("separation", 8)
	body.add_child(action_row)
	join_button = _button("JOIN SELECTED", _on_join_pressed)
	action_row.add_child(join_button)
	ready_button = _button("READY UP", _on_ready_pressed)
	action_row.add_child(ready_button)
	lock_button = _button("LOCK THE SQUARE", _on_lock_pressed)
	action_row.add_child(lock_button)

	bracket_label = RichTextLabel.new()
	bracket_label.bbcode_enabled = true
	bracket_label.fit_content = false
	bracket_label.custom_minimum_size = Vector2(0.0, 240.0)
	body.add_child(bracket_label)


func _button(label_text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = label_text
	button.custom_minimum_size.y = 40.0
	button.add_theme_font_size_override("font_size", 14)
	button.pressed.connect(callback)
	return button


func _on_create_pressed() -> void:
	var house_index := house_selector.selected
	var house := "" if house_index <= 0 else HOUSES[house_index]
	create_squad_requested.emit(name_edit.text.strip_edges(), house)


func _on_join_pressed() -> void:
	if not _selected_squad_id.is_empty():
		join_squad_requested.emit(_selected_squad_id)


func _on_ready_pressed() -> void:
	_local_ready = not _local_ready
	ready_toggled.emit(_local_ready)


func _on_lock_pressed() -> void:
	lock_bracket_requested.emit()


func _on_squad_clicked(meta: Variant) -> void:
	_selected_squad_id = String(meta)
	join_button.disabled = _selected_squad_id.is_empty()
