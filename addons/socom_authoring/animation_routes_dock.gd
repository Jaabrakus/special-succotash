@tool
class_name SocomAnimationRoutesDock
extends VBoxContainer

## Read-only first migration slice. It visualizes the exact presentation route
## used by gameplay and never writes a second animation profile.

signal play_requested

const Repository := preload("res://addons/socom_authoring/animation_route_repository.gd")
const PROFILE_PATH := Repository.PROFILE_PATH

var repository = Repository.new()
var event_picker: OptionButton
var posture_picker: OptionButton
var family_picker: OptionButton
var current_base_input: LineEdit
var validation_label: Label
var event_card: Label
var context_card: Label
var state_card: Label
var layer_card: Label
var return_card: Label
var authority_label: Label
var play_button: Button


func _ready() -> void:
	if event_picker != null:
		return
	_build_interface()
	refresh_profile()


func refresh_profile() -> void:
	var previous_event := _selected_metadata(event_picker)
	var previous_family := _selected_metadata(family_picker)
	repository.load_profile(PROFILE_PATH)
	_fill_picker(event_picker, repository.event_names(), previous_event, "FIRE_ACCEPTED")
	var families: Array[String] = ["ANY"]
	families.append_array(repository.weapon_families())
	_fill_picker(family_picker, families, previous_family, "TWO_HAND_RIFLE")
	_refresh_route()


func select_context(
	event_name: String,
	posture: String,
	weapon_family: String,
	current_base_state: String = "idle_rifle"
) -> void:
	_select_metadata(event_picker, event_name)
	_select_metadata(posture_picker, posture)
	_select_metadata(family_picker, weapon_family if not weapon_family.is_empty() else "ANY")
	current_base_input.text = current_base_state
	_refresh_route()


func get_debug_snapshot() -> Dictionary:
	var event_name := _selected_metadata(event_picker)
	var posture := _selected_metadata(posture_picker)
	var family := _selected_metadata(family_picker)
	if family == "ANY":
		family = ""
	return {
		"source": repository.validation_snapshot(),
		"event": event_name,
		"posture": posture,
		"weapon_family": family,
		"current_base_state": current_base_input.text,
		"plan": repository.resolve(
			event_name,
			posture,
			family,
			current_base_input.text
		),
		"validation_text": validation_label.text,
		"state_text": state_card.text,
		"return_text": return_card.text,
	}


func _build_interface() -> void:
	name = "SOCOMAnimationRoutes"
	custom_minimum_size = Vector2(390.0, 0.0)
	add_theme_constant_override("separation", 8)
	var title := Label.new()
	title.text = "SOCOM ANIMATION ROUTES"
	title.add_theme_font_size_override("font_size", 18)
	add_child(title)
	var boundary := Label.new()
	boundary.text = (
		"Godot editor view • reads the same saved profile as gameplay\n"
		+ "READ ONLY — this first slice cannot change runtime state"
	)
	boundary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	boundary.add_theme_color_override("font_color", Color(0.45, 0.9, 0.72))
	add_child(boundary)
	var source := Label.new()
	source.text = "SOURCE OF TRUTH\n%s" % PROFILE_PATH
	source.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(source)

	var refresh_button := Button.new()
	refresh_button.text = "Refresh Saved Profile"
	refresh_button.pressed.connect(refresh_profile)
	add_child(refresh_button)

	event_picker = _labeled_picker("1. GAMEPLAY EVENT")
	posture_picker = _labeled_picker("2. POSTURE")
	_fill_picker(posture_picker, ["STANDING", "CROUCHED", "PRONE"], "STANDING", "STANDING")
	family_picker = _labeled_picker("3. WEAPON FAMILY")
	current_base_input = LineEdit.new()
	current_base_input.placeholder_text = "Current movement state"
	current_base_input.text = "idle_rifle"
	current_base_input.text_changed.connect(func(_value: String) -> void: _refresh_route())
	add_child(current_base_input)

	validation_label = Label.new()
	validation_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(validation_label)
	var flow_title := Label.new()
	flow_title.text = "LIVE ROUTE — SAME RESOLVER AS PLAYTEST"
	flow_title.add_theme_color_override("font_color", Color(1.0, 0.78, 0.3))
	add_child(flow_title)
	event_card = _flow_card()
	_add_arrow()
	context_card = _flow_card()
	_add_arrow()
	state_card = _flow_card()
	_add_arrow()
	layer_card = _flow_card()
	_add_arrow()
	return_card = _flow_card()

	authority_label = Label.new()
	authority_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	authority_label.add_theme_color_override("font_color", Color(0.72, 0.78, 0.88))
	add_child(authority_label)
	play_button = Button.new()
	play_button.name = "PlayCanonicalGame"
	play_button.text = "▶ Play Canonical Game"
	play_button.tooltip_text = "Runs the project main scene: res://game_launcher.tscn"
	play_button.pressed.connect(func() -> void: play_requested.emit())
	add_child(play_button)


func _labeled_picker(label_text: String) -> OptionButton:
	var label := Label.new()
	label.text = label_text
	add_child(label)
	var picker := OptionButton.new()
	picker.item_selected.connect(func(_index: int) -> void: _refresh_route())
	add_child(picker)
	return picker


func _flow_card() -> Label:
	var panel := PanelContainer.new()
	panel.custom_minimum_size.y = 52.0
	add_child(panel)
	var label := Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	panel.add_child(label)
	return label


func _add_arrow() -> void:
	var arrow := Label.new()
	arrow.text = "                  ↓"
	arrow.add_theme_color_override("font_color", Color(0.45, 0.82, 1.0))
	add_child(arrow)


func _fill_picker(
	picker: OptionButton,
	values: Array[String],
	preferred: String,
	fallback: String
) -> void:
	picker.clear()
	for value: String in values:
		picker.add_item(value.replace("_", " ").capitalize())
		picker.set_item_metadata(picker.item_count - 1, value)
	if not _select_metadata(picker, preferred):
		_select_metadata(picker, fallback)


func _select_metadata(picker: OptionButton, value: String) -> bool:
	if picker == null:
		return false
	for index: int in picker.item_count:
		if String(picker.get_item_metadata(index)) == value:
			picker.select(index)
			return true
	return false


func _selected_metadata(picker: OptionButton) -> String:
	if picker == null or picker.selected < 0:
		return ""
	return String(picker.get_item_metadata(picker.selected))


func _refresh_route() -> void:
	if event_picker == null or event_picker.item_count == 0:
		return
	var validation := repository.validation_snapshot()
	if bool(validation.get("ok", false)):
		validation_label.text = "✓ %d clips • %d rules • %d connected events" % [
			int(validation.get("clip_count", 0)),
			int(validation.get("rule_count", 0)),
			int(validation.get("route_count", 0)),
		]
		validation_label.add_theme_color_override("font_color", Color(0.45, 0.9, 0.62))
	else:
		validation_label.text = "PROFILE ERROR\n%s" % "\n".join(validation.get("errors", []))
		validation_label.add_theme_color_override("font_color", Color(1.0, 0.38, 0.38))
	var event_name := _selected_metadata(event_picker)
	var posture := _selected_metadata(posture_picker)
	var family := _selected_metadata(family_picker)
	if family == "ANY":
		family = ""
	var plan := repository.resolve(
		event_name,
		posture,
		family,
		current_base_input.text
	)
	event_card.text = "EVENT\n%s" % event_name
	context_card.text = "CONTEXT\n%s • %s" % [
		posture,
		family if not family.is_empty() else "ANY WEAPON",
	]
	if bool(plan.get("valid", false)):
		state_card.text = "STATE + CLIP\n%s\n%s" % [
			String(plan.get("state", "")),
			String(plan.get("clip_path", "")).get_file(),
		]
		var effects: Array = plan.get("effects", [])
		layer_card.text = "BODY LAYER + EFFECTS\n%s\n%s" % [
			String(plan.get("layer", "FULL_BODY")).replace("_", " "),
			"none" if effects.is_empty() else ", ".join(effects),
		]
		return_card.text = "CONTEXTUAL RETURN\n%s" % String(
			plan.get("resolved_return_state", "CURRENT MOVEMENT")
		)
	else:
		state_card.text = "NOT CONNECTED\n%s" % String(plan.get("error", "Missing route"))
		layer_card.text = "NO PRESENTATION APPLIED"
		return_card.text = "GAMEPLAY REMAINS AUTHORITATIVE"
	authority_label.text = repository.event_description(event_name)
