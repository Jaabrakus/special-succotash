class_name SocomKeyboardMappingLab
extends Control

const KeyboardProfile := preload("res://scripts/input/socom_keyboard_mapping_profile.gd")
const OperatorAnimationDriver := preload("res://scripts/player/operator_animation_driver.gd")
const PlayerController := preload("res://scripts/player/player_controller.gd")
const MAX_HISTORY := 14

var awaiting_action: StringName = &""
var binding_buttons: Dictionary = {}
var status_label: Label
var preview_status: Label
var preview_state_label: Label
var history_label: RichTextLabel
var history_title: Label
var history_entries: Array[String] = []
var root_margin: MarginContainer
var left_panel: PanelContainer
var preview_viewport_container: SubViewportContainer
var preview_viewport: SubViewport
var full_screen_button: Button
var full_preview := false
var previous_window_mode := DisplayServer.WINDOW_MODE_WINDOWED
var preview_model: Node3D
var preview_player: CharacterBody3D
var preview_camera: Camera3D
var animation_driver: Node3D
var animation_player: AnimationPlayer
var preview_fire_time := 0.0
var last_locomotion_animation: StringName = &""


func _ready() -> void:
	KeyboardProfile.apply_project_mapping()
	_build_interface()
	_build_operator_preview()
	_refresh_binding_buttons()
	set_process(true)
	if "--fullscreen-preview" in OS.get_cmdline_user_args():
		_toggle_full_screen_preview.call_deferred()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F11:
			_toggle_full_screen_preview()
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_ESCAPE and full_preview:
			_toggle_full_screen_preview()
			get_viewport().set_input_as_handled()
			return
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
	if preview_model == null or preview_player == null:
		return
	preview_fire_time = maxf(0.0, preview_fire_time - delta)
	_sync_animation_from_gameplay_player()
	preview_camera.position = preview_player.position + Vector3(0.0, 1.18, 3.0)
	preview_camera.look_at(preview_player.position + Vector3(0.0, 0.82, 0.0), Vector3.UP)
	preview_state_label.text = "CURRENT GAMEPLAY STATE  •  %s" % String(
		preview_player.call("get_motion_state_name")
	)


func _build_interface() -> void:
	var background := ColorRect.new()
	background.color = Color("151a23")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	root_margin = MarginContainer.new()
	root_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root_margin.add_theme_constant_override("margin_left", 22)
	root_margin.add_theme_constant_override("margin_right", 22)
	root_margin.add_theme_constant_override("margin_top", 18)
	root_margin.add_theme_constant_override("margin_bottom", 18)
	add_child(root_margin)

	var split := HSplitContainer.new()
	split.split_offset = 500
	root_margin.add_child(split)

	left_panel = PanelContainer.new()
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
	var preview_header := HBoxContainer.new()
	right_column.add_child(preview_header)
	var preview_title := Label.new()
	preview_title.text = "LIVE OPERATOR INPUT PREVIEW"
	preview_title.add_theme_font_size_override("font_size", 20)
	preview_title.add_theme_color_override("font_color", Color("e4c777"))
	preview_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview_header.add_child(preview_title)
	var reset_preview_button := Button.new()
	reset_preview_button.name = "ResetKeyboardOperatorPreview"
	reset_preview_button.text = "Reset Operator"
	reset_preview_button.pressed.connect(_reset_operator_preview)
	preview_header.add_child(reset_preview_button)
	full_screen_button = Button.new()
	full_screen_button.name = "FullScreenKeyboardPreview"
	full_screen_button.text = "Full Screen Animation"
	full_screen_button.pressed.connect(_toggle_full_screen_preview)
	preview_header.add_child(full_screen_button)
	preview_status = Label.new()
	preview_status.name = "KeyboardPreviewStatus"
	preview_status.text = "Press a mapped control. The model and history use the real action name."
	preview_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right_column.add_child(preview_status)
	preview_state_label = Label.new()
	preview_state_label.name = "KeyboardPreviewGameplayState"
	preview_state_label.text = "CURRENT GAMEPLAY STATE  •  STANDING"
	preview_state_label.add_theme_font_size_override("font_size", 12)
	preview_state_label.add_theme_color_override("font_color", Color("8fe6b0"))
	right_column.add_child(preview_state_label)
	preview_viewport_container = SubViewportContainer.new()
	preview_viewport_container.name = "KeyboardOperatorViewport"
	preview_viewport_container.stretch = true
	preview_viewport_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview_viewport_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	preview_viewport_container.custom_minimum_size = Vector2(620, 390)
	right_column.add_child(preview_viewport_container)
	preview_viewport = SubViewport.new()
	preview_viewport.name = "OperatorPreviewViewport"
	preview_viewport.size = Vector2i(720, 440)
	preview_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	preview_viewport.own_world_3d = true
	preview_viewport_container.add_child(preview_viewport)
	preview_viewport_container.set_meta("preview_viewport", preview_viewport)
	preview_viewport_container.gui_input.connect(_on_preview_gui_input)
	history_title = Label.new()
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
	var viewport := preview_viewport
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
	floor_mesh.size = Vector3(20.0, 0.08, 20.0)
	floor.mesh = floor_mesh
	floor.position.y = -0.04
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color("2b3542")
	floor.material_override = floor_material
	viewport.add_child(floor)
	var floor_body := StaticBody3D.new()
	var floor_collision := CollisionShape3D.new()
	var floor_shape := BoxShape3D.new()
	floor_shape.size = Vector3(20.0, 0.08, 20.0)
	floor_collision.shape = floor_shape
	floor_collision.position.y = -0.04
	floor_body.add_child(floor_collision)
	viewport.add_child(floor_body)
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
	preview_camera = Camera3D.new()
	viewport.add_child(preview_camera)
	preview_camera.fov = 45.0
	preview_camera.position = Vector3(0.0, 1.18, 3.0)
	preview_camera.look_at(Vector3(0.0, 0.82, 0.0), Vector3.UP)
	preview_player = PlayerController.new()
	preview_player.name = "KeyboardGameplayPlayer"
	preview_player.position = Vector3(0.0, 0.05, 0.0)
	viewport.add_child(preview_player)
	var player_collision := CollisionShape3D.new()
	player_collision.name = "CollisionShape3D"
	var player_capsule := CapsuleShape3D.new()
	player_capsule.radius = 0.38
	player_capsule.height = 1.85
	player_collision.shape = player_capsule
	player_collision.position.y = 0.925
	preview_player.add_child(player_collision)
	animation_driver = OperatorAnimationDriver.new()
	preview_model = animation_driver
	preview_model.name = "KeyboardPreviewOperator"
	preview_player.add_child(preview_model)
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
			if pressed:
				_append_history(button_text, action, "PRESSED")
				_preview_action(action)
			else:
				if action == &"fire":
					preview_fire_time = 0.0
				if action == &"crouch":
					_append_history(button_text, action, "RELEASED — GAMEPLAY RESOLVES TAP / HOLD")


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
		&"fire":
			preview_fire_time = 0.12
			if animation_driver != null and animation_driver.has_method("notify_fired"):
				animation_driver.call("notify_fired")
		&"reload_weapon", &"throw_grenade":
			_play_animation_for_action(action)
		&"reset_camera":
			_reset_operator_preview()


func _reset_operator_preview() -> void:
	preview_fire_time = 0.0
	if preview_player != null:
		preview_player.position = Vector3(0.0, 0.05, 0.0)
		preview_player.rotation = Vector3.ZERO
		preview_player.velocity = Vector3.ZERO
		preview_player.set("posture", 0)
		preview_player.set("motion_state", 0)
		preview_player.set("action_elapsed", 0.0)
		preview_player.set("action_duration", 0.0)
		preview_player.set("stance_hold_timer", 0.0)
		preview_player.set("stance_held_triggered", false)
		preview_player.set("peek_amount", 0.0)
		preview_player.call("_apply_posture_collider")
	if animation_driver != null:
		animation_driver.set("requested_action", &"")
		animation_driver.set("requested_action_remaining", 0.0)
	preview_status.text = "Operator reset to the real grounded standing state."


func _sync_animation_from_gameplay_player() -> void:
	if animation_driver == null or not animation_driver.has_method("set_visual_inputs"):
		return
	var local_velocity := preview_player.global_basis.inverse() * preview_player.velocity
	var visual_direction := Vector2(local_velocity.x, -local_velocity.z)
	var actual_speed := visual_direction.length()
	var top_speed := maxf(float(preview_player.get("move_speed")), 0.001)
	var normalized_speed := clampf(actual_speed / top_speed, 0.0, 1.0)
	if visual_direction.length_squared() > 0.001:
		visual_direction = visual_direction.normalized() * normalized_speed
	var desired_world: Vector3 = preview_player.call("get_desired_movement_direction")
	var local_desired := preview_player.global_basis.inverse() * desired_world
	var desired_visual := Vector2(local_desired.x, -local_desired.z)
	var desired_strength := clampf(desired_world.length(), 0.0, 1.0)
	if desired_visual.length_squared() > 0.001:
		desired_visual = desired_visual.normalized() * desired_strength
	animation_driver.call(
		"set_visual_inputs",
		visual_direction,
		StringName(preview_player.call("get_posture_name")),
		0.0,
		0.0,
		1.0,
		preview_fire_time > 0.0,
		0.0,
		normalized_speed,
		StringName(preview_player.call("get_motion_state_name")),
		preview_player.velocity.y,
		StringName(preview_player.call("get_movement_gait_name")),
		actual_speed,
		preview_player.global_position + Vector3(0.0, 1.25, -20.0),
		desired_visual,
		desired_strength,
		StringName(preview_player.call("get_horizontal_response_mode")),
		float(preview_player.call("get_peek_amount"))
	)


func _toggle_full_screen_preview() -> void:
	full_preview = not full_preview
	if full_preview:
		previous_window_mode = DisplayServer.window_get_mode()
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	left_panel.visible = not full_preview
	history_title.visible = not full_preview
	history_label.visible = not full_preview
	preview_status.visible = not full_preview
	root_margin.add_theme_constant_override("margin_left", 4 if full_preview else 22)
	root_margin.add_theme_constant_override("margin_right", 4 if full_preview else 22)
	root_margin.add_theme_constant_override("margin_top", 4 if full_preview else 18)
	root_margin.add_theme_constant_override("margin_bottom", 4 if full_preview else 18)
	preview_viewport_container.custom_minimum_size = (
		Vector2.ZERO if full_preview else Vector2(620, 390)
	)
	full_screen_button.text = (
		"Exit Full Screen (Esc / F11)" if full_preview else "Full Screen Animation"
	)
	if not full_preview:
		DisplayServer.window_set_mode(previous_window_mode)
func _on_preview_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.double_click and event.button_index == MOUSE_BUTTON_LEFT:
		_toggle_full_screen_preview()


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
