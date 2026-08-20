class_name SocomKeyboardMappingLab
extends Control

const KeyboardProfile := preload("res://scripts/input/socom_keyboard_mapping_profile.gd")
const OperatorAnimationDriver := preload("res://scripts/player/operator_animation_driver.gd")
const MAX_HISTORY := 14
const STANCE_HOLD_THRESHOLD := 0.20
const DIVE_DURATION := 0.78
const ROLL_DURATION := 0.62

var awaiting_action: StringName = &""
var binding_buttons: Dictionary = {}
var status_label: Label
var preview_status: Label
var history_label: RichTextLabel
var history_entries: Array[String] = []
var preview_model: Node3D
var animation_driver: Node3D
var animation_player: AnimationPlayer
var impulse_pitch := 0.0
var preview_peek := 0.0
var preview_fire_time := 0.0
var preview_posture: StringName = &"STANDING"
var preview_motion_state: StringName = &"STANDING"
var preview_action_time := 0.0
var preview_vertical_speed := 0.0
var stance_press_active := false
var stance_hold_timer := 0.0
var stance_held_triggered := false
var last_locomotion_animation: StringName = &""


func _ready() -> void:
	KeyboardProfile.apply_project_mapping()
	_build_interface()
	_build_operator_preview()
	_refresh_binding_buttons()
	set_process(true)


func _input(event: InputEvent) -> void:
	if awaiting_action != &"":
		if event is InputEventKey and event.pressed and not event.echo:
			if event.keycode == KEY_ESCAPE:
				_cancel_rebind()
			else:
				var key_event := InputEventKey.new()
				key_event.physical_keycode = (
					event.physical_keycode
					if event.physical_keycode != 0
					else event.keycode
				)
				_finish_rebind(key_event)
			get_viewport().set_input_as_handled()
			return
		if event is InputEventMouseButton and event.pressed:
			var mouse_event := InputEventMouseButton.new()
			mouse_event.button_index = event.button_index
			_finish_rebind(mouse_event)
			get_viewport().set_input_as_handled()
			return
		return

	if event is InputEventKey and not event.echo:
		_record_matching_actions(event, event.pressed)
	elif event is InputEventMouseButton:
		_record_matching_actions(event, event.pressed)


func _process(delta: float) -> void:
	if preview_model == null:
		return
	var input_vector := Input.get_vector(
		&"move_left",
		&"move_right",
		&"move_forward",
		&"move_back"
	)
	_update_stance_hold(input_vector, delta)
	_update_preview_motion_state(delta)
	if input_vector.length() > 0.05:
		var direction := Vector3(input_vector.x, 0.0, input_vector.y).normalized()
		preview_model.position += direction * delta * 1.15
		preview_model.position.x = clampf(preview_model.position.x, -1.25, 1.25)
		preview_model.position.z = clampf(preview_model.position.z, -1.10, 1.10)
	preview_peek = move_toward(preview_peek, 0.0, delta * 3.5)
	preview_fire_time = maxf(0.0, preview_fire_time - delta)
	if animation_driver != null and animation_driver.has_method("set_visual_inputs"):
		animation_driver.call(
			"set_visual_inputs",
			Vector2(input_vector.x, -input_vector.y),
			preview_posture,
			0.0,
			0.0,
			1.0,
			preview_fire_time > 0.0,
			0.0,
			input_vector.length(),
			preview_motion_state,
			preview_vertical_speed,
			&"FULL" if preview_posture == &"STANDING" and input_vector.length() >= 0.72 else &"WALK",
			input_vector.length() * 2.4,
			Vector3.ZERO,
			Vector2(input_vector.x, -input_vector.y),
			input_vector.length(),
			&"DIRECT",
			preview_peek
		)
	impulse_pitch = lerpf(impulse_pitch, 0.0, 1.0 - exp(-15.0 * delta))
	preview_model.rotation.x = deg_to_rad(impulse_pitch)


func _build_interface() -> void:
	var background := ColorRect.new()
	background.color = Color("151a23")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	var root_margin := MarginContainer.new()
	root_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root_margin.add_theme_constant_override("margin_left", 22)
	root_margin.add_theme_constant_override("margin_right", 22)
	root_margin.add_theme_constant_override("margin_top", 18)
	root_margin.add_theme_constant_override("margin_bottom", 18)
	add_child(root_margin)

	var split := HSplitContainer.new()
	split.split_offset = 500
	root_margin.add_child(split)

	var left_panel := PanelContainer.new()
	left_panel.custom_minimum_size.x = 480
	split.add_child(left_panel)
	var left_margin := MarginContainer.new()
	left_margin.add_theme_constant_override("margin_left", 18)
	left_margin.add_theme_constant_override("margin_right", 18)
	left_margin.add_theme_constant_override("margin_top", 16)
	left_margin.add_theme_constant_override("margin_bottom", 16)
	left_panel.add_child(left_margin)
	var left_column := VBoxContainer.new()
	left_column.add_theme_constant_override("separation", 8)
	left_margin.add_child(left_column)
	var title := Label.new()
	title.text = "KEYBOARD MAPPING LAB"
	title.add_theme_font_size_override("font_size", 25)
	title.add_theme_color_override("font_color", Color("8bc5e8"))
	left_column.add_child(title)
	var help := Label.new()
	help.text = "Click a binding, then press a keyboard key or mouse button. This edits the same Input Map used by main gameplay."
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.add_theme_color_override("font_color", Color("aeb9c9"))
	left_column.add_child(help)
	left_column.add_child(HSeparator.new())

	var keyboard_title := Label.new()
	keyboard_title.text = "PLAYTEST CONTROL DECK — CLICK ANY KEYCAP TO REMAP"
	keyboard_title.add_theme_font_size_override("font_size", 13)
	keyboard_title.add_theme_color_override("font_color", Color("e4c777"))
	left_column.add_child(keyboard_title)
	var keyboard_scroll := ScrollContainer.new()
	keyboard_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_column.add_child(keyboard_scroll)
	var keyboard_deck := VBoxContainer.new()
	keyboard_deck.name = "PlaytestKeyboardDeck"
	keyboard_deck.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	keyboard_deck.add_theme_constant_override("separation", 8)
	keyboard_scroll.add_child(keyboard_deck)
	_build_playtest_keyboard(keyboard_deck)

	var command_row := HBoxContainer.new()
	left_column.add_child(command_row)
	var save_button := Button.new()
	save_button.name = "SaveKeyboardMappingButton"
	save_button.text = "Save + Apply to Game"
	save_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	save_button.pressed.connect(_save_mapping)
	command_row.add_child(save_button)
	var reset_button := Button.new()
	reset_button.name = "ResetKeyboardMappingButton"
	reset_button.text = "Reset Defaults"
	reset_button.pressed.connect(_reset_defaults)
	command_row.add_child(reset_button)
	status_label = Label.new()
	status_label.name = "KeyboardMappingStatus"
	status_label.text = "Current project controls loaded. Changes are previewed immediately."
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.add_theme_color_override("font_color", Color("8fe6b0"))
	left_column.add_child(status_label)

	var right_column := VBoxContainer.new()
	right_column.add_theme_constant_override("separation", 8)
	split.add_child(right_column)
	var preview_title := Label.new()
	preview_title.text = "LIVE OPERATOR INPUT PREVIEW"
	preview_title.add_theme_font_size_override("font_size", 20)
	preview_title.add_theme_color_override("font_color", Color("e4c777"))
	right_column.add_child(preview_title)
	preview_status = Label.new()
	preview_status.name = "KeyboardPreviewStatus"
	preview_status.text = "Press a mapped control. The model and history use the real action name."
	preview_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right_column.add_child(preview_status)
	var viewport_container := SubViewportContainer.new()
	viewport_container.name = "KeyboardOperatorViewport"
	viewport_container.stretch = true
	viewport_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	viewport_container.custom_minimum_size = Vector2(620, 410)
	right_column.add_child(viewport_container)
	var viewport := SubViewport.new()
	viewport.name = "OperatorPreviewViewport"
	viewport.size = Vector2i(720, 440)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.own_world_3d = true
	viewport_container.add_child(viewport)
	viewport_container.set_meta("preview_viewport", viewport)
	var history_title := Label.new()
	history_title.text = "INPUT HISTORY — BUTTON → ACTION"
	history_title.add_theme_color_override("font_color", Color("79d8f2"))
	right_column.add_child(history_title)
	history_label = RichTextLabel.new()
	history_label.name = "KeyboardInputHistory"
	history_label.bbcode_enabled = true
	history_label.fit_content = false
	history_label.custom_minimum_size.y = 150
	history_label.scroll_following = true
	right_column.add_child(history_label)


func _build_playtest_keyboard(parent: VBoxContainer) -> void:
	_add_keycap_row(parent, [
		&"peek_left", &"move_forward", &"peek_right", &"reload_weapon",
	], Color("35596d"))
	_add_keycap_row(parent, [
		&"move_left", &"move_back", &"move_right", &"throw_grenade",
	], Color("35596d"))
	_add_keycap_row(parent, [
		&"dive", &"crouch", &"jump", &"fire",
	], Color("53633e"))
	_add_keycap_row(parent, [
		&"cycle_grenade", &"reset_camera",
	], Color("426a80"))
	var unbound_title := Label.new()
	unbound_title.text = "UNBOUND PLAYTEST ACTIONS"
	unbound_title.add_theme_font_size_override("font_size", 11)
	unbound_title.add_theme_color_override("font_color", Color("8492a6"))
	parent.add_child(unbound_title)
	_add_keycap_row(parent, [&"prone", &"roll"], Color("55434b"))


func _add_keycap_row(
	parent: VBoxContainer,
	actions: Array[StringName],
	key_color: Color
) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 7)
	parent.add_child(row)
	for action: StringName in actions:
		var button := Button.new()
		button.name = "Bind_%s" % String(action)
		button.custom_minimum_size = Vector2(84, 64)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.add_theme_font_size_override("font_size", 12)
		var normal := StyleBoxFlat.new()
		normal.bg_color = key_color
		normal.border_color = key_color.lightened(0.28)
		normal.set_border_width_all(1)
		normal.set_corner_radius_all(5)
		button.add_theme_stylebox_override("normal", normal)
		var hover := normal.duplicate() as StyleBoxFlat
		hover.bg_color = key_color.lightened(0.16)
		button.add_theme_stylebox_override("hover", hover)
		button.pressed.connect(_begin_rebind.bind(action))
		row.add_child(button)
		binding_buttons[action] = button


func _build_operator_preview() -> void:
	var container := find_child("KeyboardOperatorViewport", true, false) as SubViewportContainer
	var viewport := container.get_meta("preview_viewport") as SubViewport
	var environment_node := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("667286")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("d6e0ef")
	environment.ambient_light_energy = 0.72
	environment_node.environment = environment
	viewport.add_child(environment_node)
	var floor := MeshInstance3D.new()
	var floor_mesh := BoxMesh.new()
	floor_mesh.size = Vector3(4.2, 0.08, 3.4)
	floor.mesh = floor_mesh
	floor.position.y = -0.04
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color("2b3542")
	floor.material_override = floor_material
	viewport.add_child(floor)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-48.0, -28.0, 0.0)
	light.light_energy = 1.35
	light.shadow_enabled = true
	viewport.add_child(light)
	var fill := OmniLight3D.new()
	fill.position = Vector3(-1.5, 2.4, 2.0)
	fill.omni_range = 7.0
	fill.light_energy = 2.0
	viewport.add_child(fill)
	var camera := Camera3D.new()
	viewport.add_child(camera)
	camera.position = Vector3(0.0, 1.35, 4.1)
	camera.look_at(Vector3(0.0, 0.95, 0.0), Vector3.UP)
	animation_driver = OperatorAnimationDriver.new()
	preview_model = animation_driver
	preview_model.name = "KeyboardPreviewOperator"
	viewport.add_child(preview_model)
	animation_player = animation_driver.get("animation_player") as AnimationPlayer
	_play_idle_if_available()


func _begin_rebind(action: StringName) -> void:
	awaiting_action = action
	status_label.text = "Press a new key or mouse button for %s. Escape cancels." % String(
		KeyboardProfile.ACTION_LABELS.get(action, action)
	)
	var button := binding_buttons.get(action) as Button
	if button:
		button.text = "Press input…"


func _finish_rebind(event: InputEvent) -> void:
	var action := awaiting_action
	awaiting_action = &""
	if not KeyboardProfile.replace_binding(action, event):
		status_label.text = "That input cannot be used for this keyboard mapping."
		_refresh_binding_buttons()
		return
	status_label.text = "%s → %s. Click Save + Apply to keep it." % [
		KeyboardProfile.event_label(event),
		String(KeyboardProfile.ACTION_LABELS.get(action, action)),
	]
	_refresh_binding_buttons()
	_append_history(KeyboardProfile.event_label(event), action, "REBOUND")


func _cancel_rebind() -> void:
	awaiting_action = &""
	status_label.text = "Rebind canceled."
	_refresh_binding_buttons()


func _refresh_binding_buttons() -> void:
	for action: StringName in KeyboardProfile.ACTION_ORDER:
		var button := binding_buttons.get(action) as Button
		if button:
			button.text = "%s\n%s" % [
				KeyboardProfile.binding_text(action),
				String(KeyboardProfile.ACTION_LABELS.get(action, action)),
			]


func _save_mapping() -> void:
	if KeyboardProfile.save_current_mapping():
		status_label.text = "Saved. Camera + Playable Range will load these exact controls."
		status_label.add_theme_color_override("font_color", Color("7ff29d"))
	else:
		status_label.text = "Could not save config/input/keyboard_mapping.json."
		status_label.add_theme_color_override("font_color", Color("ff7575"))


func _reset_defaults() -> void:
	KeyboardProfile.reset_to_defaults()
	_refresh_binding_buttons()
	status_label.text = "Defaults restored in preview. Click Save + Apply to keep them."


func _record_matching_actions(event: InputEvent, pressed: bool) -> void:
	for action: StringName in KeyboardProfile.ACTION_ORDER:
		if InputMap.event_is_action(event, action, true):
			var button_text := KeyboardProfile.event_label(event)
			if action == &"crouch":
				if pressed:
					_start_stance_press(button_text)
				else:
					_finish_stance_press(button_text)
			elif pressed:
				_append_history(button_text, action, "PRESSED")
				_preview_action(action)
			elif action == &"fire":
				preview_fire_time = 0.0


func _append_history(button_text: String, action: StringName, state: String) -> void:
	var action_label := String(KeyboardProfile.ACTION_LABELS.get(action, action))
	history_entries.push_front("[color=#8fdfff]%s[/color] → [color=#f1d77a]%s[/color]  [color=#8492a6]%s[/color]" % [
		button_text,
		action_label,
		state,
	])
	if history_entries.size() > MAX_HISTORY:
		history_entries.resize(MAX_HISTORY)
	history_label.text = "\n".join(history_entries)


func _preview_action(action: StringName) -> void:
	preview_status.text = "%s = %s" % [
		KeyboardProfile.binding_text(action),
		String(KeyboardProfile.ACTION_LABELS.get(action, action)),
	]
	match action:
		&"jump":
			preview_motion_state = &"AIRBORNE"
			preview_action_time = 0.0
			preview_vertical_speed = 4.8
			preview_model.position.y = 0.20
			var tween := create_tween()
			tween.tween_property(preview_model, "position:y", 0.0, 0.55).set_trans(Tween.TRANS_QUAD)
		&"peek_left":
			preview_peek = -1.0
		&"peek_right":
			preview_peek = 1.0
		&"fire":
			impulse_pitch = -5.0
			preview_fire_time = 0.12
			if animation_driver != null and animation_driver.has_method("notify_fired"):
				animation_driver.call("notify_fired")
		&"reload_weapon":
			_play_animation_for_action(action)
		&"dive":
			_start_committed_action(&"DIVING")
		&"roll":
			_start_committed_action(&"ROLLING")
		&"prone":
			preview_posture = &"CROUCHED" if preview_posture == &"PRONE" else &"PRONE"
			preview_motion_state = preview_posture
		&"reset_camera":
			preview_model.position = Vector3.ZERO
		_:
			_play_animation_for_action(action)


func _start_stance_press(button_text: String) -> void:
	stance_press_active = true
	stance_hold_timer = 0.0
	stance_held_triggered = false
	_append_history(button_text, &"crouch", "DOWN — TAP OR HOLD")
	preview_status.text = "%s held: tap changes stance • hold drops prone • hold while moving dives" % button_text


func _update_stance_hold(input_vector: Vector2, delta: float) -> void:
	if not stance_press_active or stance_held_triggered:
		return
	stance_hold_timer += delta
	if stance_hold_timer < STANCE_HOLD_THRESHOLD:
		return
	stance_held_triggered = true
	if preview_posture != &"PRONE" and input_vector.length() >= 0.72:
		_start_committed_action(&"DIVING")
		_append_history(KeyboardProfile.binding_text(&"crouch"), &"crouch", "HOLD + MOVE → DIVE")
		preview_status.text = "Hold stance while moving = dive to prone"
	else:
		preview_posture = &"PRONE"
		preview_motion_state = &"PRONE"
		_append_history(KeyboardProfile.binding_text(&"crouch"), &"crouch", "HOLD → PRONE")
		preview_status.text = "Hold stance = prone"


func _finish_stance_press(button_text: String) -> void:
	if not stance_press_active:
		return
	if not stance_held_triggered:
		if preview_posture == &"CROUCHED":
			preview_posture = &"STANDING"
		elif preview_posture == &"PRONE":
			preview_posture = &"CROUCHED"
		else:
			preview_posture = &"CROUCHED"
		preview_motion_state = preview_posture
		_append_history(button_text, &"crouch", "TAP → %s" % preview_posture)
		preview_status.text = "Tap stance = %s" % preview_posture.to_lower()
	stance_press_active = false
	stance_hold_timer = 0.0
	stance_held_triggered = false


func _start_committed_action(state: StringName) -> void:
	if preview_posture == &"PRONE":
		return
	preview_motion_state = state
	preview_posture = &"STANDING" if state == &"DIVING" else &"CROUCHED"
	preview_action_time = 0.0


func _update_preview_motion_state(delta: float) -> void:
	preview_vertical_speed = 0.0
	match preview_motion_state:
		&"DIVING":
			preview_action_time += delta
			if preview_action_time >= DIVE_DURATION:
				preview_posture = &"PRONE"
				preview_motion_state = &"PRONE"
		&"ROLLING":
			preview_action_time += delta
			if preview_action_time >= ROLL_DURATION:
				preview_posture = &"CROUCHED"
				preview_motion_state = &"CROUCHED"
		&"AIRBORNE":
			preview_action_time += delta
			preview_vertical_speed = 4.8 if preview_action_time < 0.26 else -3.5
			if preview_action_time >= 0.58:
				preview_motion_state = &"LANDING"
				preview_action_time = 0.0
		&"LANDING":
			preview_action_time += delta
			if preview_action_time >= 0.18:
				preview_motion_state = preview_posture


func _play_animation_for_action(action: StringName) -> void:
	if animation_driver != null and animation_driver.has_method("play_semantic_action"):
		var semantic_action: StringName = {
			&"reload_weapon": &"reload",
			&"throw_grenade": &"grenade_quick",
		}.get(action, action)
		if bool(animation_driver.call("play_semantic_action", semantic_action, 0.12)):
			return
	if animation_player == null:
		return
	var keywords: Dictionary = {
		&"move_forward": ["walk", "run", "move"],
		&"move_back": ["walk", "run", "move"],
		&"move_left": ["strafe", "walk"],
		&"move_right": ["strafe", "walk"],
		&"jump": ["jump"],
		&"crouch": ["crouch"],
		&"prone": ["prone"],
		&"roll": ["roll"],
		&"dive": ["dive"],
		&"fire": ["fire", "shoot"],
		&"reload_weapon": ["reload"],
		&"throw_grenade": ["throw", "grenade"],
	}
	for keyword: String in keywords.get(action, []):
		for animation_name: StringName in animation_player.get_animation_list():
			if keyword in String(animation_name).to_lower():
				if animation_player.current_animation != animation_name:
					animation_player.play(animation_name, 0.12)
				last_locomotion_animation = animation_name
				return


func _play_idle_if_available() -> void:
	if animation_player == null:
		return
	if not last_locomotion_animation.is_empty() and animation_player.is_playing():
		return
	for animation_name: StringName in animation_player.get_animation_list():
		if "idle" in String(animation_name).to_lower():
			animation_player.play(animation_name, 0.15)
			last_locomotion_animation = &""
			return


func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child in node.get_children():
		var found := _find_animation_player(child)
		if found != null:
			return found
	return null
