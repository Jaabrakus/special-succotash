class_name GunsmithFrameEditorView
extends RefCounted

## Owns frame-editor controls and their presentation. The Gunsmith coordinator
## retains animation state, pose capture, persistence, and gameplay contracts.

const FrameTimeline := preload("res://scripts/labs/gunsmith/gunsmith_frame_timeline.gd")
const ReloadTimeline := preload("res://scripts/weapons/weapon_reload_visual_timeline.gd")


static func build(lab, parent: VBoxContainer) -> void:
	var title := Label.new()
	title.text = "FRAME POSE EDITOR"
	title.add_theme_color_override("font_color", Color(0.35, 0.9, 1.0))
	parent.add_child(title)
	lab.animation_frame_editor_title = Label.new()
	lab.animation_frame_editor_title.text = "Select Frames beside an animation state."
	lab.animation_frame_editor_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lab.animation_frame_editor_title.add_theme_font_size_override("font_size", 10)
	parent.add_child(lab.animation_frame_editor_title)
	var help := Label.new()
	help.text = "Click Frames for an action to open its lifecycle at frame 0. The green barrel-base → muzzle line is the weapon axis. Orange weapon edits become clip-local frame keys; they do not change the shared gun mount."
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.add_theme_font_size_override("font_size", 10)
	parent.add_child(help)
	build_timeline(lab)


static func build_timeline(lab) -> void:
	if lab.animation_frame_panel != null or lab.overlay == null:
		return
	lab.animation_frame_panel = PanelContainer.new()
	lab.animation_frame_panel.name = "GunsmithFrameTimelinePanel"
	lab.animation_frame_panel.anchor_left = 0.37
	lab.animation_frame_panel.anchor_top = 1.0
	lab.animation_frame_panel.anchor_right = 1.0
	lab.animation_frame_panel.anchor_bottom = 1.0
	lab.animation_frame_panel.offset_top = -184.0
	lab.animation_frame_panel.offset_right = -16.0
	lab.animation_frame_panel.offset_bottom = -16.0
	lab.animation_frame_panel.visible = false
	lab.overlay.add_child(lab.animation_frame_panel)
	var container := VBoxContainer.new()
	lab.animation_frame_panel.add_child(container)
	lab.animation_frame_readout = Label.new()
	lab.animation_frame_readout.text = "Frame —"
	lab.animation_frame_readout.add_theme_font_size_override("font_size", 11)
	container.add_child(lab.animation_frame_readout)
	lab.animation_frame_timeline = FrameTimeline.new()
	lab.animation_frame_timeline.name = "AnimationFrameLifecycle"
	lab.animation_frame_timeline.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lab.animation_frame_timeline.frame_scrubbed.connect(lab._seek_animation_frame_index)
	container.add_child(lab.animation_frame_timeline)
	var controls := HBoxContainer.new()
	container.add_child(controls)
	lab.animation_frame_edit_button = _button("", "✎ Edit Current Animation", "Pause and edit the explicitly selected reaction clip. This does not close the frame editor.", lab._toggle_current_animation_frame_editor)
	controls.add_child(lab.animation_frame_edit_button)
	var previous := _button("", "◀ Frame", "", lab._step_animation_frame_editor.bind(-1))
	controls.add_child(previous)
	lab.animation_frame_edit_controls.append(previous)
	lab.animation_frame_play_button = _button("", "▶ Play", "", lab._toggle_animation_frame_editor_playback)
	controls.add_child(lab.animation_frame_play_button)
	lab.animation_frame_edit_controls.append(lab.animation_frame_play_button)
	var next := _button("", "Frame ▶", "", lab._step_animation_frame_editor.bind(1))
	controls.add_child(next)
	lab.animation_frame_edit_controls.append(next)
	var capture := _button("SetAnimationCorrectionKey", "◆ Set Correction Key", "Save the current correction here. It holds forward and blends toward the next key.", lab._capture_animation_frame_pose_key)
	controls.add_child(capture)
	lab.animation_frame_edit_controls.append(capture)
	var save_apply := _button("SaveApplyAnimationRig", "💾 Save + Apply Rig", "Capture this frame key, save the weapon profile, and equip the corrections on the gameplay rig", lab._save_weapon_config)
	controls.add_child(save_apply)
	lab.animation_frame_edit_controls.append(save_apply)
	lab.reload_event_controls_row = HBoxContainer.new()
	lab.reload_event_controls_row.name = "ReloadLifecycleControls"
	container.add_child(lab.reload_event_controls_row)
	lab.reload_event_status = Label.new()
	lab.reload_event_status.text = "RELOAD VISUALS"
	lab.reload_event_status.custom_minimum_size.x = 178.0
	lab.reload_event_status.add_theme_font_size_override("font_size", 10)
	lab.reload_event_controls_row.add_child(lab.reload_event_status)
	for event_name in ReloadTimeline.EVENT_ORDER:
		var event_button := _button(
			"SetReloadEvent_" + event_name,
			"Set " + String(ReloadTimeline.EVENT_LABELS.get(event_name, event_name)),
			"Set this reload handoff at the current frame. This changes visuals only.",
			lab._set_reload_event_at_current_frame.bind(event_name)
		)
		lab.reload_event_controls_row.add_child(event_button)
		lab.reload_event_buttons[event_name] = event_button
		lab.animation_frame_edit_controls.append(event_button)
	refresh(lab)


static func refresh(lab) -> void:
	if lab.animation_frame_panel:
		lab.animation_frame_panel.visible = true
	if lab.animation_frame_editor_title:
		lab.animation_frame_editor_title.text = (
			"Editing %s → %s • orange weapon edits are frame-local" % [lab.animation_frame_editor.slot_name, lab.animation_frame_editor.clip_name]
			if lab.animation_frame_editor.active
			else "Select Frames beside an animation state."
		)
	var frame_weapon_editing: bool = lab._editing_action_weapon_frame()
	for slider_key in ["grip_x", "grip_y", "grip_z", "rot_pitch", "rot_yaw", "rot_roll"]:
		var slider_data: Variant = lab.sliders_map.get(slider_key, {})
		if slider_data is Dictionary:
			var mount_slider := (slider_data as Dictionary).get("slider") as HSlider
			var mount_row := (slider_data as Dictionary).get("row") as Control
			if mount_slider:
				mount_slider.editable = not frame_weapon_editing
			if mount_row:
				mount_row.tooltip_text = "Shared mount is locked in Frames. Use the orange 3D weapon control for this frame only." if frame_weapon_editing else "Calibrates the shared weapon mount for every animation."
	if lab.animation_frame_play_button:
		lab.animation_frame_play_button.text = "⏸ Pause" if lab.animation_frame_editor.playing else "▶ Play"
	if lab.animation_frame_edit_button:
		if lab.animation_frame_editor.active:
			lab.animation_frame_edit_button.text = "✎ Pause & Edit %s" % lab.animation_frame_editor.clip_name if lab.animation_frame_editor.playing else "✎ Editing %s" % lab.animation_frame_editor.clip_name
		elif lab.animation_edit_candidate_clip != &"":
			lab.animation_frame_edit_button.text = "✎ Edit %s" % lab.animation_edit_candidate_clip
		else:
			lab.animation_frame_edit_button.text = "✎ Edit Current Animation"
	for control in lab.animation_frame_edit_controls:
		if control:
			control.disabled = not lab.animation_frame_editor.active
	var editing_reload: bool = lab._is_reload_frame_editor()
	if lab.reload_event_controls_row:
		lab.reload_event_controls_row.visible = editing_reload
	for event_name in lab.reload_event_buttons:
		var reload_button := lab.reload_event_buttons[event_name] as Button
		if reload_button:
			reload_button.disabled = not editing_reload
	if lab.animation_frame_scrubber:
		var normalized := 0.0
		if lab.animation_frame_editor.duration_seconds > 0.0:
			normalized = lab.animation_frame_editor.time_seconds / lab.animation_frame_editor.duration_seconds
		lab.animation_frame_scrubber.set_value_no_signal(normalized)
	if lab.animation_frame_readout:
		lab.animation_frame_readout.text = (
			"Frame %d / %d • %.3f s%s" % [lab.animation_frame_editor.frame_index(), lab.animation_frame_editor.frame_count(), lab.animation_frame_editor.time_seconds, " • SAVED POSE KEY" if lab.animation_frame_editor.has_current_pose() else ""]
			if lab.animation_frame_editor.active
			else "FRAME EDITOR READY • Click Edit Current Animation"
		)
	if lab.animation_frame_timeline:
		var reload_events: Dictionary = lab._current_reload_events() if editing_reload else {}
		lab.animation_frame_timeline.configure(lab.animation_frame_editor.frame_count(), lab.animation_frame_editor.frame_index(), lab.animation_frame_editor.saved_frame_indices(), reload_events)
	if lab.reload_event_status and editing_reload:
		lab.reload_event_status.text = "RELOAD • " + ReloadTimeline.state_at_frame(lab._current_reload_events(), lab.animation_frame_editor.frame_index())


static func _button(
	name_value: String,
	text_value: String,
	tooltip: String,
	callback: Callable
) -> Button:
	var button := Button.new()
	if not name_value.is_empty():
		button.name = name_value
	button.text = text_value
	button.tooltip_text = tooltip
	button.pressed.connect(callback)
	return button
