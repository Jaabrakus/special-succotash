extends VBoxContainer

signal sequence_changed(patch: Dictionary)
signal preview_requested
signal verify_requested

const FULL_BODY := "FULL_BODY"
const UPPER_BODY := "UPPER_BODY"
const CURRENT_BASE := "CURRENT_BASE"
const INTERRUPT_POLICIES := ["RESTART", "REPLACE", "IGNORE_WHILE_ACTIVE"]

var _syncing := false
var _stage_labels: Array[Label] = []
var _layer: OptionButton
var _blend_in: SpinBox
var _blend_out: SpinBox
var _interrupt: OptionButton
var _priority: SpinBox
var _return: OptionButton
var _effects: LineEdit
var _cues: LineEdit
var _validation: Label


func _ready() -> void:
	name = "VisualSequenceEditor"
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_build_ui()


func set_sequence(
	event_name: String,
	posture: String,
	family: String,
	state_name: String,
	clip_path: String,
	route: Dictionary,
	rule: Dictionary,
	valid_state_names: Array[String]
) -> void:
	_syncing = true
	var effects: Array = route.get("effects", [])
	var cue_names: Array[String] = []
	for raw_cue in route.get("timed_cues", []):
		if raw_cue is Dictionary:
			var cue := raw_cue as Dictionary
			cue_names.append("%.2f:%s" % [float(cue.get("time", 0.0)), String(cue.get("name", ""))])
	_stage_labels[0].text = _stage("1  TRIGGER", event_name.replace("_", " ").capitalize())
	_stage_labels[1].text = _stage("2  CONDITIONS", "%s\n%s" % [posture.capitalize(), family.replace("_", " ").capitalize()])
	_stage_labels[2].text = _stage("3  ANIMATION", "%s\n%s" % [state_name, clip_path.get_file() if not clip_path.is_empty() else "MISSING CLIP"])
	_stage_labels[3].text = _stage("4  BODY + BLEND", "%s\n%.2fs in / %.2fs out" % [String(rule.get("layer", FULL_BODY)).replace("_", " ").capitalize(), float(rule.get("blend_in_seconds", 0.12)), float(rule.get("blend_out_seconds", 0.14))])
	_stage_labels[4].text = _stage("5  CUES", ", ".join(effects) if not effects.is_empty() else "No presentation effect")
	_stage_labels[5].text = _stage("6  RECOVERY", "%s\n%s" % [String(route.get("interrupt_policy", "RESTART")).capitalize(), String(rule.get("return_state", CURRENT_BASE)).replace("_", " ").capitalize()])
	_select_metadata(_layer, String(rule.get("layer", FULL_BODY)))
	_blend_in.value = float(rule.get("blend_in_seconds", 0.12))
	_blend_out.value = float(rule.get("blend_out_seconds", 0.14))
	_select_metadata(_interrupt, String(route.get("interrupt_policy", "RESTART")))
	_priority.value = int(route.get("priority", 50))
	_return.clear()
	_return.add_item("Current movement / stance")
	_return.set_item_metadata(0, CURRENT_BASE)
	for state in valid_state_names:
		_return.add_item(state)
		_return.set_item_metadata(_return.item_count - 1, state)
	_select_metadata(_return, String(rule.get("return_state", CURRENT_BASE)))
	_effects.text = ", ".join(effects)
	_cues.text = ", ".join(cue_names)
	_validation.text = _validate(state_name, clip_path, route, rule)
	_validation.add_theme_color_override(
		"font_color",
		Color(0.35, 1.0, 0.62) if _validation.text.begins_with("READY") else Color(1.0, 0.45, 0.35)
	)
	_syncing = false


func _build_ui() -> void:
	var title := Label.new()
	title.text = "VISUAL ACTION SEQUENCE — ONE ROUTE, START TO FINISH"
	title.add_theme_color_override("font_color", Color(0.35, 1.0, 0.62))
	add_child(title)
	var hint := Label.new()
	hint.text = "Gameplay sends the trigger. This sequence controls only how the operator looks and returns."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_color_override("font_color", Color(0.78, 0.85, 0.92))
	add_child(hint)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.y = 112.0
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(scroll)
	var stages := HBoxContainer.new()
	stages.add_theme_constant_override("separation", 6)
	scroll.add_child(stages)
	for index in range(6):
		if index > 0:
			var arrow := Label.new()
			arrow.text = "→"
			arrow.add_theme_color_override("font_color", Color(0.25, 0.82, 1.0))
			stages.add_child(arrow)
		var card := Label.new()
		card.custom_minimum_size = Vector2(164, 96)
		card.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		card.add_theme_font_size_override("font_size", 10)
		card.add_theme_color_override("font_color", Color(0.82, 0.94, 1.0))
		stages.add_child(card)
		_stage_labels.append(card)
	var grid := GridContainer.new()
	grid.columns = 2
	add_child(grid)
	_layer = _option(grid, "Body layer", [FULL_BODY, UPPER_BODY])
	_blend_in = _seconds(grid, "Blend in")
	_blend_out = _seconds(grid, "Blend out")
	_interrupt = _option(grid, "If triggered again", INTERRUPT_POLICIES)
	_priority = SpinBox.new()
	_priority.min_value = 0
	_priority.max_value = 100
	_priority.step = 1
	_add_control(grid, "Priority", _priority)
	_return = OptionButton.new()
	_add_control(grid, "Return to", _return)
	_effects = LineEdit.new()
	_effects.placeholder_text = "ENTER_READY_AIM, APPLY_WEAPON_FAMILY"
	_add_control(grid, "Visual effects", _effects)
	_cues = LineEdit.new()
	_cues.placeholder_text = "0.20:MAG_OUT, 0.75:MAG_IN"
	_cues.tooltip_text = "Optional presentation cue markers. Format: seconds:name. These never authorize gameplay."
	_add_control(grid, "Timed visual cues", _cues)
	for control in [_layer, _blend_in, _blend_out, _interrupt, _priority, _return, _effects, _cues]:
		if control is OptionButton:
			(control as OptionButton).item_selected.connect(_emit_change.unbind(1))
		elif control is SpinBox:
			(control as SpinBox).value_changed.connect(_emit_change.unbind(1))
		elif control is LineEdit:
			(control as LineEdit).text_changed.connect(_emit_change.unbind(1))
	var actions := HBoxContainer.new()
	add_child(actions)
	var preview := Button.new()
	preview.text = "▶ Preview Complete Sequence"
	preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview.pressed.connect(func(): preview_requested.emit())
	actions.add_child(preview)
	var verify := Button.new()
	verify.text = "✓ Validate All Contexts"
	verify.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	verify.pressed.connect(func(): verify_requested.emit())
	actions.add_child(verify)
	_validation = Label.new()
	_validation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_validation)


func _option(parent: GridContainer, label: String, values: Array) -> OptionButton:
	var option := OptionButton.new()
	for value in values:
		option.add_item(String(value).replace("_", " ").capitalize())
		option.set_item_metadata(option.item_count - 1, value)
	_add_control(parent, label, option)
	return option


func _seconds(parent: GridContainer, label: String) -> SpinBox:
	var control := SpinBox.new()
	control.min_value = 0.0
	control.max_value = 1.0
	control.step = 0.01
	control.suffix = " s"
	_add_control(parent, label, control)
	return control


func _add_control(parent: GridContainer, label: String, control: Control) -> void:
	parent.add_child(Label.new())
	(parent.get_child(parent.get_child_count() - 1) as Label).text = label
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(control)


func _emit_change() -> void:
	if _syncing:
		return
	sequence_changed.emit({
		"layer": _metadata(_layer),
		"blend_in_seconds": _blend_in.value,
		"blend_out_seconds": _blend_out.value,
		"interrupt_policy": _metadata(_interrupt),
		"priority": int(_priority.value),
		"return_state": _metadata(_return),
		"effects": _csv(_effects.text),
		"timed_cues": _parse_cues(_cues.text),
	})


func _metadata(option: OptionButton) -> String:
	return String(option.get_item_metadata(option.selected)) if option.item_count > 0 else ""


func _select_metadata(option: OptionButton, value: String) -> void:
	for index in range(option.item_count):
		if String(option.get_item_metadata(index)) == value:
			option.select(index)
			return


func _csv(value: String) -> Array[String]:
	var result: Array[String] = []
	for part in value.split(","):
		var clean := part.strip_edges().to_upper()
		if not clean.is_empty() and clean not in result:
			result.append(clean)
	return result


func _parse_cues(value: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for part in value.split(","):
		var pieces := part.strip_edges().split(":", false, 1)
		if pieces.size() == 2 and pieces[0].is_valid_float() and not pieces[1].strip_edges().is_empty():
			result.append({"time": maxf(0.0, float(pieces[0])), "name": pieces[1].strip_edges().to_upper()})
	return result


func _stage(title: String, detail: String) -> String:
	return "%s\n\n%s" % [title, detail]


func _validate(state_name: String, clip_path: String, route: Dictionary, rule: Dictionary) -> String:
	if state_name.is_empty():
		return "NOT READY — connect this trigger to an animation state."
	if clip_path.is_empty():
		return "NOT READY — %s has no animation clip." % state_name
	if String(rule.get("layer", FULL_BODY)) not in [FULL_BODY, UPPER_BODY]:
		return "NOT READY — choose a valid body layer."
	if String(route.get("interrupt_policy", "RESTART")) not in INTERRUPT_POLICIES:
		return "NOT READY — choose a valid interruption rule."
	return "READY — trigger, context, clip, body layer, blend, interruption, and return are defined."
