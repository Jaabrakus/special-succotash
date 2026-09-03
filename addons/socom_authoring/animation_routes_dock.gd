@tool
class_name SocomAnimationRoutesDock
extends VBoxContainer

## Godot-native animation-route authoring. Gameplay and the editor consume the
## same profile, contracts, and resolver; edits remain drafts until explicit save.

signal play_requested
signal pose_lineup_requested
signal document_transaction_requested(
	action_name: String,
	before_document: Dictionary,
	after_document: Dictionary
)

const Repository := preload("res://addons/socom_authoring/animation_route_repository.gd")
const LanguageParser := preload("res://scripts/labs/animation_state_language_parser.gd")
const PROFILE_PATH := Repository.PROFILE_PATH

var repository = Repository.new()
var language_parser = LanguageParser.new()
var profile_path := PROFILE_PATH
var event_picker: OptionButton
var posture_picker: OptionButton
var family_picker: OptionButton
var current_base_input: LineEdit
var source_label: Label
var validation_label: Label
var event_card: Label
var context_card: Label
var state_card: Label
var layer_card: Label
var return_card: Label
var authority_label: Label
var play_button: Button
var state_picker: OptionButton
var rule_input: LineEdit
var proposal_label: Label
var approve_button: Button
var discard_button: Button
var save_button: Button
var pending_proposal: Dictionary = {}


func _ready() -> void:
	if event_picker != null:
		return
	_build_interface()
	refresh_profile(true)


func refresh_profile(force: bool = false) -> void:
	if repository.is_dirty() and not force:
		_show_status("Draft not reloaded. Save, undo, or discard it first.", false)
		return
	var previous_event := _selected_metadata(event_picker)
	var previous_family := _selected_metadata(family_picker)
	var previous_state := _selected_metadata(state_picker)
	repository.load_profile(profile_path)
	_fill_picker(event_picker, repository.event_names(), previous_event, "FIRE_ACCEPTED")
	var families: Array[String] = ["ANY"]
	families.append_array(repository.weapon_families())
	_fill_picker(family_picker, families, previous_family, "TWO_HAND_RIFLE")
	var states: Array[String] = []
	for raw_state: Variant in repository.slots.keys():
		states.append(String(raw_state))
	states.sort()
	_fill_picker(state_picker, states, previous_state, "combat_fire")
	pending_proposal.clear()
	_update_proposal_controls()
	_refresh_route()


func configure_profile_path(path: String) -> void:
	profile_path = path
	if source_label != null:
		source_label.text = "SOURCE OF TRUTH\n%s" % profile_path
	refresh_profile(true)


func propose_rule(command: String, selected_state: String = "") -> Dictionary:
	var state_name := selected_state
	if state_name.is_empty():
		state_name = _selected_metadata(state_picker)
	var parsed: Dictionary = language_parser.propose(command, state_name)
	if not bool(parsed.get("valid", false)):
		pending_proposal.clear()
		_show_proposal_error(String(parsed.get("message", "Rule could not be understood.")))
		return {"ok": false, "errors": [String(parsed.get("message", "Invalid rule."))]}
	var family := _selected_metadata(family_picker)
	parsed["weapon_family"] = "" if family == "ANY" else family
	parsed["source_rule"] = command.strip_edges()
	var event_name := String(parsed.get("event", ""))
	var existing_route: Variant = repository.routes.get(event_name, {})
	if existing_route is Dictionary:
		parsed["interrupt_policy"] = String(
			(existing_route as Dictionary).get("interrupt_policy", "RESTART")
		)
		parsed["priority"] = int((existing_route as Dictionary).get("priority", 50))
		parsed["effects"] = (existing_route as Dictionary).get("effects", []).duplicate()
	var built := repository.build_route_proposal(parsed)
	if not bool(built.get("ok", false)):
		pending_proposal.clear()
		_show_proposal_error("\n".join(built.get("errors", [])))
		return built
	pending_proposal = built.duplicate(true)
	proposal_label.text = "READY TO APPROVE\n%s\nNo source file has changed." % String(
		built.get("summary", "Validated route proposal")
	)
	proposal_label.add_theme_color_override("font_color", Color(0.45, 0.9, 0.62))
	_update_proposal_controls()
	return built


func approve_pending_proposal() -> bool:
	if not bool(pending_proposal.get("ok", false)):
		return false
	var before := repository.document_snapshot()
	var after: Dictionary = pending_proposal.get("document", {}).duplicate(true)
	var summary := String(pending_proposal.get("summary", "Edit animation route"))
	if document_transaction_requested.get_connections().is_empty():
		apply_document_snapshot(after)
	else:
		document_transaction_requested.emit("SOCOM Route: %s" % summary, before, after)
	pending_proposal.clear()
	proposal_label.text = "Approved as an in-memory draft. Cmd/Ctrl+Z undoes it."
	proposal_label.add_theme_color_override("font_color", Color(0.45, 0.82, 1.0))
	_update_proposal_controls()
	return true


func discard_pending_proposal() -> void:
	pending_proposal.clear()
	proposal_label.text = "No pending proposal."
	proposal_label.add_theme_color_override("font_color", Color(0.72, 0.78, 0.88))
	_update_proposal_controls()


func apply_document_snapshot(snapshot: Dictionary) -> void:
	var result := repository.replace_document(snapshot)
	if not bool(result.get("ok", false)):
		_show_status("Draft rejected: %s" % "\n".join(result.get("errors", [])), false)
		return
	pending_proposal.clear()
	_update_proposal_controls()
	_refresh_route()


func save_approved_draft() -> Dictionary:
	var result := repository.save_profile(profile_path)
	if bool(result.get("ok", false)):
		_show_status("✓ Saved validated route profile atomically.", true)
	else:
		_show_status(String(result.get("error", "Save failed.")), false)
	_update_proposal_controls()
	return result


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
		"dirty": repository.is_dirty(),
		"pending_proposal": pending_proposal.duplicate(true),
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
		"Godot-native authoring • same profile and resolver as gameplay\n"
		+ "Proposals stay in memory until you explicitly save"
	)
	boundary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	boundary.add_theme_color_override("font_color", Color(0.45, 0.9, 0.72))
	add_child(boundary)
	var pose_lineup_button := Button.new()
	pose_lineup_button.text = "Open Gun Pose Lineup — Native 3D Editor"
	pose_lineup_button.tooltip_text = (
		"Opens every important rifle state side-by-side in Godot's real 3D editor "
		+ "with the native Scene hierarchy, Inspector, TargetPivot nodes, and gizmos."
	)
	pose_lineup_button.pressed.connect(func() -> void: pose_lineup_requested.emit())
	add_child(pose_lineup_button)
	source_label = Label.new()
	source_label.text = "SOURCE OF TRUTH\n%s" % profile_path
	source_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(source_label)

	var refresh_button := Button.new()
	refresh_button.text = "Refresh Saved Profile"
	refresh_button.pressed.connect(func() -> void: refresh_profile(false))
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

	var authoring_title := Label.new()
	authoring_title.text = "AUTHOR A ROUTE — REVIEW BEFORE APPLYING"
	authoring_title.add_theme_color_override("font_color", Color(1.0, 0.78, 0.3))
	add_child(authoring_title)
	state_picker = _labeled_picker("ANIMATION STATE / CLIP")
	rule_input = LineEdit.new()
	rule_input.placeholder_text = (
		"When a valid rifle shot happens, play this on torso and arms, "
		+ "blend in 0.04, blend out 0.10, return to current movement"
	)
	rule_input.text_submitted.connect(func(_value: String) -> void: _propose_from_interface())
	add_child(rule_input)
	var propose_button := Button.new()
	propose_button.text = "1. Build Reviewable Proposal"
	propose_button.pressed.connect(_propose_from_interface)
	add_child(propose_button)
	proposal_label = Label.new()
	proposal_label.text = "No pending proposal."
	proposal_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(proposal_label)
	var proposal_actions := HBoxContainer.new()
	add_child(proposal_actions)
	approve_button = Button.new()
	approve_button.text = "2. Approve Draft"
	approve_button.pressed.connect(approve_pending_proposal)
	proposal_actions.add_child(approve_button)
	discard_button = Button.new()
	discard_button.text = "Discard Proposal"
	discard_button.pressed.connect(discard_pending_proposal)
	proposal_actions.add_child(discard_button)
	save_button = Button.new()
	save_button.text = "3. Save Approved Draft"
	save_button.tooltip_text = "Validates again, checks for disk conflicts, then replaces the JSON atomically."
	save_button.pressed.connect(save_approved_draft)
	add_child(save_button)
	var undo_hint := Label.new()
	undo_hint.text = "Approved drafts use Godot Undo/Redo (Cmd/Ctrl+Z). Save is the only disk write."
	undo_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	undo_hint.add_theme_color_override("font_color", Color(0.72, 0.78, 0.88))
	add_child(undo_hint)
	_update_proposal_controls()

	play_button = Button.new()
	play_button.name = "PlayCanonicalGame"
	play_button.text = "▶ Play Canonical Game"
	play_button.tooltip_text = "Runs the project main scene: res://game_launcher.tscn"
	play_button.pressed.connect(func() -> void: play_requested.emit())
	add_child(play_button)


func _propose_from_interface() -> void:
	propose_rule(rule_input.text)


func _show_proposal_error(message: String) -> void:
	proposal_label.text = "PROPOSAL NEEDS ATTENTION\n%s\nNothing was changed." % message
	proposal_label.add_theme_color_override("font_color", Color(1.0, 0.45, 0.35))
	_update_proposal_controls()


func _show_status(message: String, success: bool) -> void:
	validation_label.text = message
	validation_label.add_theme_color_override(
		"font_color",
		Color(0.45, 0.9, 0.62) if success else Color(1.0, 0.45, 0.35)
	)


func _update_proposal_controls() -> void:
	if approve_button == null:
		return
	var has_proposal := bool(pending_proposal.get("ok", false))
	approve_button.disabled = not has_proposal
	discard_button.disabled = not has_proposal
	save_button.disabled = not repository.is_dirty() or not repository.errors.is_empty()


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
		validation_label.text = "%s %d clips • %d rules • %d connected events" % [
			"● UNSAVED DRAFT •" if repository.is_dirty() else "✓",
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
	_update_proposal_controls()
