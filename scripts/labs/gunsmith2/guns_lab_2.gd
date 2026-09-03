class_name GunsLab2
extends "res://scripts/labs/gun_calibration_lab.gd"

## Focused visual-rig authoring surface.
## It reuses the proven arms-and-weapon preview but never saves gameplay data.

const VISUAL_RIG_CONTRACT := preload(
	"res://scripts/labs/gunsmith2/weapon_visual_rig_contract.gd"
)
const VISUAL_RIG_REPOSITORY := preload(
	"res://scripts/labs/gunsmith2/weapon_visual_rig_repository.gd"
)
const VISUAL_RIG_RESOLVER := preload(
	"res://scripts/labs/gunsmith2/weapon_visual_rig_resolver.gd"
)
const HAND_POSE_2D_CONTROL := preload(
	"res://scripts/labs/gunsmith2/weapon_hand_pose_2d_control.gd"
)
const ROTATION_ORBIT_CONTROL := preload(
	"res://scripts/labs/gunsmith/gunsmith_rotation_orbit_control.gd"
)

var visual_rig_repository = VISUAL_RIG_REPOSITORY.new()
var v2_overlay: Control
var v2_status: Label
var weapon_picker: OptionButton
var visual_rig_picker: OptionButton
var rig_id_edit: LineEdit
var socket_picker: OptionButton
var socket_controls: Dictionary = {}
var scale_control: SpinBox
var last_published_visual_rig_id := ""
var _syncing_v2_controls := false
var hand_pose_target_picker: OptionButton
var hand_pose_side_view: Control
var hand_pose_top_view: Control
var hand_pose_rotation_control: Control
var hand_pose_value_label: Label
var hand_pose_help_label: Label
var selected_pose_target: StringName = &"support_hand"


func _ready() -> void:
	super._ready()
	if overlay != null:
		overlay.visible = false
	_set_camera_preset("hands")
	_build_v2_workspace()
	_refresh_weapon_picker()
	_refresh_visual_rig_picker()
	call_deferred("_sync_v2_controls_from_preview")


func _set_camera_preset(preset_name: String) -> void:
	# Guns Lab 2.0 needs enough distance to judge the complete shoulder-to-palm
	# chains. The legacy hands preset was designed for individual socket edits
	# and crops the weapon/arms when the focused sidebar is visible.
	match preset_name:
		"hands":
			cam_target = Vector3(-0.12, 1.31, -0.04)
			cam_distance = 1.18
			cam_yaw = 52.0
			cam_pitch = -5.0
		"side":
			cam_target = Vector3(0.02, 1.23, -0.04)
			cam_distance = 1.62
			cam_yaw = 90.0
			cam_pitch = -2.0
		"full":
			cam_target = Vector3(0.0, 0.98, 0.0)
			cam_distance = 2.35
			cam_yaw = 35.0
			cam_pitch = -10.0
		_:
			super._set_camera_preset(preset_name)
			return
	_update_camera()


func _build_v2_workspace() -> void:
	v2_overlay = Control.new()
	v2_overlay.name = "GunsLab2Workspace"
	v2_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(v2_overlay)
	_restore_shared_preview_overlays()

	var panel := PanelContainer.new()
	panel.name = "GunsLab2VisualRigPanel"
	panel.anchor_bottom = 1.0
	panel.offset_left = 16.0
	panel.offset_top = 16.0
	panel.offset_right = 430.0
	panel.offset_bottom = -16.0
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.055, 0.065, 0.078, 0.96)
	panel_style.border_color = Color(0.19, 0.27, 0.32, 0.95)
	panel_style.set_border_width_all(1)
	panel_style.set_corner_radius_all(4)
	panel.add_theme_stylebox_override("panel", panel_style)
	v2_overlay.add_child(panel)

	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 14)
	panel.add_child(margin)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(scroll)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 8)
	scroll.add_child(column)

	var title := Label.new()
	title.text = "GUNS LAB 2.0 — GOLDEN VISUAL RIGS"
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color("8be0bd"))
	column.add_child(title)
	var boundary := Label.new()
	boundary.name = "VisualOnlyContractNotice"
	boundary.text = "Edits arms, mesh placement, and sockets only.\nDamage, cadence, fire modes, loadout, and networking are locked."
	boundary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	boundary.add_theme_color_override("font_color", Color("b9c8d8"))
	column.add_child(boundary)
	column.add_child(HSeparator.new())

	column.add_child(_section_label("WEAPON IDENTITY (READ-ONLY)"))
	weapon_picker = OptionButton.new()
	weapon_picker.name = "GunsLab2WeaponPicker"
	weapon_picker.item_selected.connect(_on_weapon_selected)
	column.add_child(weapon_picker)

	var camera_row := HBoxContainer.new()
	for preset in ["hands", "side", "full"]:
		var button := Button.new()
		button.text = preset.capitalize()
		button.pressed.connect(_set_camera_preset.bind(preset))
		camera_row.add_child(button)
	column.add_child(camera_row)

	column.add_child(HSeparator.new())
	column.add_child(_section_label("LIVE RETICLE + GAMEPLAY REFERENCES"))
	var overlay_notice := Label.new()
	overlay_notice.name = "SharedOverlayOwnerNotice"
	overlay_notice.text = "These are the existing SOCOM reticle and trajectory readers. They preview gameplay data but do not own shots."
	overlay_notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	overlay_notice.add_theme_color_override("font_color", Color("b9c8d8"))
	column.add_child(overlay_notice)
	var reticle_toggle := CheckButton.new()
	reticle_toggle.name = "SharedReticlePreviewToggle"
	reticle_toggle.text = "Show canonical reticle + bounce"
	reticle_toggle.button_pressed = dynamic_reticle != null and dynamic_reticle.visible
	reticle_toggle.toggled.connect(_set_shared_reticle_visible)
	column.add_child(reticle_toggle)
	column.add_child(_overlay_toggle(
		"BulletVelocityToggleV2",
		"Green — bullet velocity",
		show_bullet_velocity,
		func(enabled: bool): show_bullet_velocity = enabled
	))
	column.add_child(_overlay_toggle(
		"BarrelAxisToggleV2",
		"Red — physical muzzle/barrel axis",
		show_barrel_axis,
		func(enabled: bool): show_barrel_axis = enabled
	))
	column.add_child(_overlay_toggle(
		"ReticleIntentToggleV2",
		"Cyan — camera/reticle aim intent",
		show_camera_aim,
		func(enabled: bool): show_camera_aim = enabled
	))
	column.add_child(_overlay_toggle(
		"GunPlacementLineToggleV2",
		"Blue — reticle-locked gun placement line",
		show_eye_sight,
		func(enabled: bool): show_eye_sight = enabled; _update_eye_sight_marker()
	))
	column.add_child(_overlay_toggle(
		"LastShotToggleV2",
		"Yellow — last actual preview shot",
		show_last_shot,
		func(enabled: bool): show_last_shot = enabled
	))
	var preview_action_row := HBoxContainer.new()
	var fire_preview_button := Button.new()
	fire_preview_button.name = "TestReticleKickButton"
	fire_preview_button.text = "TEST FIRE + RETICLE KICK"
	fire_preview_button.pressed.connect(_test_v2_fire_and_reticle)
	preview_action_row.add_child(fire_preview_button)
	var reload_preview_button := Button.new()
	reload_preview_button.name = "TestReloadHandsButton"
	reload_preview_button.text = "TEST RELOAD HANDOFF"
	reload_preview_button.pressed.connect(_trigger_reload_animation)
	preview_action_row.add_child(reload_preview_button)
	column.add_child(preview_action_row)

	column.add_child(HSeparator.new())
	column.add_child(_section_label("VISUAL GEOMETRY"))
	scale_control = _spin_box(0.01, 3.0, 0.001)
	scale_control.name = "VisualMeshScale"
	scale_control.value_changed.connect(_on_scale_changed)
	column.add_child(_labeled_control("Mesh scale", scale_control))

	socket_picker = OptionButton.new()
	socket_picker.name = "GunsLab2SocketPicker"
	for socket_name in [
		"right_hand_grip_target",
		"left_hand_ik_target",
		"muzzle_socket",
		"barrel_base_socket",
		"optic_rail",
		"ejection_port",
	]:
		socket_picker.add_item(socket_name)
	socket_picker.item_selected.connect(_on_socket_selected)
	column.add_child(socket_picker)

	var xyz_row := HBoxContainer.new()
	for axis in ["x", "y", "z"]:
		var axis_column := VBoxContainer.new()
		axis_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var axis_label := Label.new()
		axis_label.text = axis.to_upper()
		axis_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		axis_column.add_child(axis_label)
		var spin := _spin_box(-1.5, 1.5, 0.001)
		spin.name = "Socket%s" % axis.to_upper()
		spin.value_changed.connect(_on_socket_axis_changed.bind(axis))
		axis_column.add_child(spin)
		socket_controls[axis] = spin
		xyz_row.add_child(axis_column)
	column.add_child(xyz_row)

	column.add_child(HSeparator.new())
	column.add_child(_section_label("2D HAND + WEAPON POSE"))
	var pose_intro := Label.new()
	pose_intro.text = "Drag a marker in SIDE and TOP. Use the yellow wheels or mouse wheel to rotate. The 3D character updates live."
	pose_intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pose_intro.add_theme_color_override("font_color", Color("b9c8d8"))
	column.add_child(pose_intro)

	hand_pose_target_picker = OptionButton.new()
	hand_pose_target_picker.name = "HandPoseTargetPicker"
	for entry in [
		["Support hand (blue)", &"support_hand"],
		["Trigger hand / gun anchor (green)", &"trigger_hand"],
		["Support elbow pole (purple)", &"support_elbow"],
		["Trigger elbow pole (pink)", &"trigger_elbow"],
	]:
		hand_pose_target_picker.add_item(String(entry[0]))
		hand_pose_target_picker.set_item_metadata(hand_pose_target_picker.item_count - 1, entry[1])
	hand_pose_target_picker.item_selected.connect(_on_hand_pose_target_selected)
	column.add_child(hand_pose_target_picker)

	hand_pose_side_view = HAND_POSE_2D_CONTROL.new()
	hand_pose_side_view.name = "HandPoseSideView"
	hand_pose_side_view.call("set_view_plane", HAND_POSE_2D_CONTROL.ViewPlane.SIDE)
	hand_pose_side_view.connect("target_changed", _on_hand_pose_target_changed)
	hand_pose_side_view.connect("target_selected", _on_hand_pose_target_picked_in_view)
	hand_pose_side_view.connect("rotation_delta_requested", _on_hand_pose_rotation_delta)
	column.add_child(hand_pose_side_view)

	hand_pose_top_view = HAND_POSE_2D_CONTROL.new()
	hand_pose_top_view.name = "HandPoseTopView"
	hand_pose_top_view.call("set_view_plane", HAND_POSE_2D_CONTROL.ViewPlane.TOP)
	hand_pose_top_view.connect("target_changed", _on_hand_pose_target_changed)
	hand_pose_top_view.connect("target_selected", _on_hand_pose_target_picked_in_view)
	hand_pose_top_view.connect("rotation_delta_requested", _on_hand_pose_rotation_delta)
	column.add_child(hand_pose_top_view)

	hand_pose_rotation_control = ROTATION_ORBIT_CONTROL.new()
	hand_pose_rotation_control.name = "HandPoseRotationWheel"
	hand_pose_rotation_control.connect("axis_delta_requested", _on_hand_pose_rotation_delta)
	hand_pose_rotation_control.connect("hand_direction_delta_requested", _on_hand_pose_direction_delta)
	column.add_child(hand_pose_rotation_control)

	hand_pose_value_label = Label.new()
	hand_pose_value_label.name = "HandPoseExactValues"
	hand_pose_value_label.add_theme_font_size_override("font_size", 11)
	hand_pose_value_label.add_theme_color_override("font_color", Color("8be0bd"))
	column.add_child(hand_pose_value_label)
	hand_pose_help_label = Label.new()
	hand_pose_help_label.name = "HandPoseOwnershipHelp"
	hand_pose_help_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hand_pose_help_label.add_theme_font_size_override("font_size", 11)
	column.add_child(hand_pose_help_label)

	var validate_button := Button.new()
	validate_button.name = "ValidateVisualRig"
	validate_button.text = "VALIDATE ARMS + GUN CONTRACT"
	validate_button.pressed.connect(_validate_current_visual_rig)
	column.add_child(validate_button)

	column.add_child(HSeparator.new())
	column.add_child(_section_label("GOLDEN PROFILE"))
	rig_id_edit = LineEdit.new()
	rig_id_edit.name = "GoldenRigBaseId"
	rig_id_edit.text = "assaultrifle_1"
	rig_id_edit.placeholder_text = "visual rig base ID"
	column.add_child(rig_id_edit)
	visual_rig_picker = OptionButton.new()
	visual_rig_picker.name = "PublishedVisualRigPicker"
	column.add_child(visual_rig_picker)

	var draft_button := Button.new()
	draft_button.name = "SaveVisualRigDraft"
	draft_button.text = "SAVE VISUAL-ONLY DRAFT"
	draft_button.pressed.connect(_save_visual_rig_draft)
	column.add_child(draft_button)
	var publish_button := Button.new()
	publish_button.name = "PublishGoldenVisualRig"
	publish_button.text = "PUBLISH NEW IMMUTABLE VERSION"
	publish_button.pressed.connect(_publish_visual_rig)
	column.add_child(publish_button)
	var assign_button := Button.new()
	assign_button.name = "AssignVisualRigToWeapon"
	assign_button.text = "ASSIGN SELECTED GOLDEN RIG"
	assign_button.pressed.connect(_assign_visual_rig_to_weapon)
	column.add_child(assign_button)
	var apply_and_play_button := Button.new()
	apply_and_play_button.name = "ApplyHandPoseAndPlay"
	apply_and_play_button.text = "APPLY HAND POSE + PLAY GAME"
	apply_and_play_button.tooltip_text = "Validate, publish, assign, and open res://main.tscn in one step."
	apply_and_play_button.pressed.connect(_apply_hand_pose_and_play)
	column.add_child(apply_and_play_button)

	v2_status = Label.new()
	v2_status.name = "GunsLab2Status"
	v2_status.text = "Load a weapon, calibrate its geometry, then save a draft."
	v2_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v2_status.add_theme_color_override("font_color", Color("e5d58c"))
	column.add_child(v2_status)

	var help := Label.new()
	help.text = "F1 Home • F2 Studio history • drag the visible socket markers in the preview"
	help.add_theme_font_size_override("font_size", 11)
	help.add_theme_color_override("font_color", Color("8493a4"))
	column.add_child(help)


func _refresh_weapon_picker() -> void:
	weapon_picker.clear()
	var categories := GunsmithRecomCatalogAdapter.gunsmith_categories()
	for category: Variant in categories:
		for weapon_id: Variant in categories[category]:
			var clean_id := String(weapon_id)
			weapon_picker.add_item(
				GunsmithRecomCatalogAdapter.display_name(clean_id)
			)
			weapon_picker.set_item_metadata(weapon_picker.item_count - 1, clean_id)
			if clean_id == selected_weapon_file:
				weapon_picker.select(weapon_picker.item_count - 1)


func _refresh_visual_rig_picker() -> void:
	visual_rig_picker.clear()
	for visual_rig_id in visual_rig_repository.list_published():
		visual_rig_picker.add_item(visual_rig_id)
		visual_rig_picker.set_item_metadata(
			visual_rig_picker.item_count - 1,
			visual_rig_id
		)
		if visual_rig_id == last_published_visual_rig_id:
			visual_rig_picker.select(visual_rig_picker.item_count - 1)


func _on_weapon_selected(index: int) -> void:
	var weapon_id := String(weapon_picker.get_item_metadata(index))
	if weapon_id.is_empty():
		return
	_load_weapon(weapon_id)
	rig_id_edit.text = selected_visual_profile_id
	v2_status.text = "%s loaded. Gameplay fields remain read-only." % weapon_display_name
	call_deferred("_sync_v2_controls_from_preview")


func _restore_shared_preview_overlays() -> void:
	# The base Gunsmith already creates the canonical dynamic-reticle preview and
	# selection/aim canvas. Guns Lab 2 hides only the old sidebar, then reparents
	# those two readers so it never creates a competing reticle implementation.
	if dynamic_reticle != null:
		dynamic_reticle.reparent(v2_overlay, true)
		dynamic_reticle.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v2_overlay.move_child(dynamic_reticle, 0)
	if reticle_canvas != null:
		reticle_canvas.reparent(v2_overlay, true)
		reticle_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v2_overlay.move_child(reticle_canvas, 1 if dynamic_reticle != null else 0)


func _set_shared_reticle_visible(enabled: bool) -> void:
	if dynamic_reticle != null:
		dynamic_reticle.visible = enabled
	if reticle_canvas != null:
		reticle_canvas.visible = enabled


func _test_v2_fire_and_reticle() -> void:
	if fire_cooldown > 0.0:
		fire_cooldown = 0.0
	_fire_shot()
	show_last_shot = true
	v2_status.text = "Preview shot fired. The reticle kick, muzzle origin, bore, and last-shot line use the existing Gunsmith readers."


func _on_socket_selected(_index: int) -> void:
	_sync_v2_controls_from_preview()


func _on_scale_changed(value: float) -> void:
	if _syncing_v2_controls:
		return
	user_scale_multiplier = value / maxf(auto_normalized_scale, 0.000001)
	_sync_weapon_transform()


func _on_socket_axis_changed(value: float, axis: String) -> void:
	if _syncing_v2_controls:
		return
	var vector := _selected_socket_vector()
	vector[axis] = value
	_set_selected_socket_vector(vector)
	_sync_markers()
	_stage_current_hand_pose()
	_refresh_hand_pose_2d()


func _sync_v2_controls_from_preview() -> void:
	_syncing_v2_controls = true
	if scale_control != null:
		scale_control.value = auto_normalized_scale * user_scale_multiplier
	var vector := _selected_socket_vector()
	for axis in ["x", "y", "z"]:
		var spin := socket_controls.get(axis) as SpinBox
		if spin != null:
			spin.value = vector[axis]
	_syncing_v2_controls = false
	_refresh_hand_pose_2d()


func _on_hand_pose_target_selected(index: int) -> void:
	selected_pose_target = StringName(hand_pose_target_picker.get_item_metadata(index))
	_refresh_hand_pose_2d()


func _on_hand_pose_target_picked_in_view(target_id: StringName) -> void:
	selected_pose_target = target_id
	for index in range(hand_pose_target_picker.item_count):
		if StringName(hand_pose_target_picker.get_item_metadata(index)) == target_id:
			hand_pose_target_picker.select(index)
			break
	_refresh_hand_pose_2d()


func _on_hand_pose_target_changed(target_id: StringName, value: Vector3) -> void:
	selected_pose_target = target_id
	match target_id:
		&"trigger_hand": right_grip_local_pos = value
		&"support_hand": left_grip_local_pos = value
		&"trigger_elbow": right_elbow_pole_offset = value
		&"support_elbow": left_elbow_pole_offset = value
	if target_id in [&"trigger_hand", &"support_hand"]:
		_sync_markers()
	else:
		_store_current_stance_elbow_poles()
	_stage_current_hand_pose()
	_sync_v2_controls_from_preview()


func _on_hand_pose_rotation_delta(axis_name: StringName, delta_degrees: float) -> void:
	if selected_pose_target in [&"support_hand", &"support_elbow"]:
		match axis_name:
			&"pitch": palm_pitch = clampf(palm_pitch + delta_degrees, -90.0, 90.0)
			&"yaw": palm_yaw = clampf(palm_yaw + delta_degrees, -90.0, 90.0)
			&"roll": palm_roll = wrapf(palm_roll + delta_degrees, -180.0, 180.0)
	else:
		match axis_name:
			&"pitch": grip_offset_rot.x = wrapf(grip_offset_rot.x + delta_degrees, -180.0, 180.0)
			&"yaw": grip_offset_rot.y = wrapf(grip_offset_rot.y + delta_degrees, -180.0, 180.0)
			&"roll": grip_offset_rot.z = wrapf(grip_offset_rot.z + delta_degrees, -180.0, 180.0)
		_sync_weapon_transform()
	_stage_current_hand_pose()
	_refresh_hand_pose_2d()


func _on_hand_pose_direction_delta(yaw_delta: float, pitch_delta: float) -> void:
	_on_hand_pose_rotation_delta(&"yaw", yaw_delta)
	_on_hand_pose_rotation_delta(&"pitch", pitch_delta)


func _stage_current_hand_pose() -> void:
	hand_poses_by_stance[preview_posture] = _current_hand_pose_snapshot()
	_store_current_stance_elbow_poles()
	_loaded_weapon_profile["support_hand_pose"] = {
		"palm_pitch_deg": palm_pitch,
		"palm_yaw_deg": palm_yaw,
		"palm_roll_deg": palm_roll,
		"finger_curl": finger_curl,
		"thumb_wrap": thumb_wrap,
	}
	_loaded_weapon_profile["elbow_poles"] = {"by_stance": _elbow_poles_save_data()}
	_loaded_weapon_profile["stances"] = hand_poses_by_stance.duplicate(true)


func _refresh_hand_pose_2d() -> void:
	if hand_pose_side_view == null or hand_pose_top_view == null:
		return
	var targets := {
		&"trigger_hand": right_grip_local_pos,
		&"support_hand": left_grip_local_pos,
		&"trigger_elbow": right_elbow_pole_offset,
		&"support_elbow": left_elbow_pole_offset,
	}
	var buttstock := right_grip_local_pos - _barrel_axis_local() * 0.30 + Vector3.UP * 0.08
	var rotations := (
		Vector3(palm_pitch, palm_yaw, palm_roll)
		if selected_pose_target in [&"support_hand", &"support_elbow"]
		else grip_offset_rot
	)
	for pose_view in [hand_pose_side_view, hand_pose_top_view]:
		pose_view.call(
			"set_pose_state",
			targets,
			selected_pose_target,
			barrel_base_local_pos,
			muzzle_local_pos,
			buttstock,
			rotations
		)
	if hand_pose_rotation_control != null:
		hand_pose_rotation_control.call(
			"set_display_state",
			selected_pose_target in [&"support_hand", &"support_elbow"],
			{"pitch": rotations.x, "yaw": rotations.y, "roll": rotations.z}
		)
	if hand_pose_value_label != null:
		var value: Vector3 = targets[selected_pose_target]
		hand_pose_value_label.text = "%s  X %.3f  Y %.3f  Z %.3f  •  P %.1f°  Y %.1f°  R %.1f°" % [
			String(selected_pose_target).replace("_", " ").capitalize(),
			value.x, value.y, value.z,
			rotations.x, rotations.y, rotations.z,
		]
	if hand_pose_help_label != null:
		hand_pose_help_label.text = (
			"Blue target + purple pole: TwoBoneIK places and turns the support palm."
			if selected_pose_target in [&"support_hand", &"support_elbow"]
			else "Green target anchors the gun to the animated trigger hand. Its wheels rotate the weapon mount; the gun remains the master object."
		)


func _selected_socket_name() -> String:
	return socket_picker.get_item_text(socket_picker.selected) if socket_picker != null else ""


func _selected_socket_vector() -> Vector3:
	match _selected_socket_name():
		"right_hand_grip_target": return right_grip_local_pos
		"left_hand_ik_target": return left_grip_local_pos
		"muzzle_socket": return muzzle_local_pos
		"barrel_base_socket": return barrel_base_local_pos
		"optic_rail": return optic_local_pos
		"ejection_port": return ejection_local_pos
	return Vector3.ZERO


func _set_selected_socket_vector(value: Vector3) -> void:
	match _selected_socket_name():
		"right_hand_grip_target": right_grip_local_pos = value
		"left_hand_ik_target": left_grip_local_pos = value
		"muzzle_socket": muzzle_local_pos = value
		"barrel_base_socket": barrel_base_local_pos = value
		"optic_rail": optic_local_pos = value
		"ejection_port": ejection_local_pos = value


func _current_visual_source_profile() -> Dictionary:
	_stage_current_hand_pose()
	var profile := _loaded_weapon_profile.duplicate(true)
	profile["model_fbx"] = selected_model_path
	profile["normalized_scale"] = auto_normalized_scale * user_scale_multiplier
	profile["user_scale_multiplier"] = user_scale_multiplier
	profile["model_rotation_degrees"] = _vector3_to_dictionary(
		current_weapon_mesh.rotation_degrees if current_weapon_mesh != null else Vector3.ZERO
	)
	profile["operator_mount"] = {
		"position": _vector3_to_dictionary(weapon_mount_local.origin * trooper_scale),
		"rotation_degrees": _vector3_to_dictionary(
			_radians_to_degrees_vector(
				weapon_mount_local.basis.orthonormalized().get_euler(EULER_ORDER_YXZ)
			)
		),
	}
	profile["grip_offset"] = {
		"pos_x": (auto_grip_center_offset + grip_offset_pos).x,
		"pos_y": (auto_grip_center_offset + grip_offset_pos).y,
		"pos_z": (auto_grip_center_offset + grip_offset_pos).z,
		"rot_x": grip_offset_rot.x,
		"rot_y": grip_offset_rot.y,
		"rot_z": grip_offset_rot.z,
	}
	profile["weapon_sockets"] = _weapon_sockets_save_data()
	profile["support_hand_pose"] = {
		"palm_pitch_deg": palm_pitch,
		"palm_yaw_deg": palm_yaw,
		"palm_roll_deg": palm_roll,
		"finger_curl": finger_curl,
		"thumb_wrap": thumb_wrap,
	}
	profile["elbow_poles"] = {"by_stance": _elbow_poles_save_data()}
	profile["stances"] = hand_poses_by_stance.duplicate(true)
	profile["handling_profile"] = handling_profile.duplicate(true)
	return profile


func _validate_current_visual_rig() -> Dictionary:
	var document := VISUAL_RIG_CONTRACT.extract(
		_current_visual_source_profile(),
		rig_id_edit.text,
		1,
		"draft"
	)
	var result := VISUAL_RIG_CONTRACT.validate(document, false)
	if bool(result.get("ok", false)):
		v2_status.text = "VALID: mesh, scale, bore, hands, and required sockets pass."
		v2_status.add_theme_color_override("font_color", Color("77e0a1"))
	else:
		v2_status.text = "BLOCKED: %s" % str(result.get("errors", []))
		v2_status.add_theme_color_override("font_color", Color("ff8d82"))
	return result


func _save_visual_rig_draft() -> void:
	var validation := _validate_current_visual_rig()
	if not bool(validation.get("ok", false)):
		return
	var result: Dictionary = visual_rig_repository.save_draft(
		rig_id_edit.text,
		_current_visual_source_profile()
	)
	v2_status.text = (
		"Draft saved: %s" % String(result.get("path", ""))
		if bool(result.get("ok", false))
		else "Draft failed: %s" % String(result.get("error", "unknown error"))
	)


func _publish_visual_rig() -> void:
	var result: Dictionary = visual_rig_repository.publish(rig_id_edit.text)
	if bool(result.get("ok", false)):
		last_published_visual_rig_id = String(result.get("visual_rig_id", ""))
		v2_status.text = "Published immutable golden rig: %s" % last_published_visual_rig_id
		v2_status.add_theme_color_override("font_color", Color("77e0a1"))
		_refresh_visual_rig_picker()
	else:
		v2_status.text = "Publish blocked: %s %s" % [
			String(result.get("error", "")),
			str(result.get("errors", [])),
		]


func _assign_visual_rig_to_weapon() -> void:
	if visual_rig_picker.item_count == 0:
		v2_status.text = "Publish a golden rig before assignment."
		return
	var visual_rig_id := String(
		visual_rig_picker.get_item_metadata(visual_rig_picker.selected)
	)
	var result: Dictionary = visual_rig_repository.assign_to_weapon(
		weapon_name,
		visual_rig_id
	)
	v2_status.text = (
		"Assigned %s to %s. Gameplay data was preserved." % [visual_rig_id, weapon_name]
		if bool(result.get("ok", false))
		else "Assignment failed: %s" % String(result.get("error", "unknown error"))
	)


func _apply_hand_pose_and_play() -> void:
	var validation := _validate_current_visual_rig()
	if not bool(validation.get("ok", false)):
		return
	var draft_result: Dictionary = visual_rig_repository.save_draft(
		rig_id_edit.text,
		_current_visual_source_profile()
	)
	if not bool(draft_result.get("ok", false)):
		v2_status.text = "Apply blocked while saving the visual draft: %s" % String(
			draft_result.get("error", "unknown error")
		)
		return
	var publish_result: Dictionary = visual_rig_repository.publish(rig_id_edit.text)
	if not bool(publish_result.get("ok", false)):
		v2_status.text = "Apply blocked while publishing: %s" % String(
			publish_result.get("error", "unknown error")
		)
		return
	last_published_visual_rig_id = String(publish_result.get("visual_rig_id", ""))
	var target_weapon_id := selected_weapon_file if not selected_weapon_file.is_empty() else weapon_name
	var assign_result: Dictionary = visual_rig_repository.assign_to_weapon(
		target_weapon_id,
		last_published_visual_rig_id
	)
	if not bool(assign_result.get("ok", false)):
		v2_status.text = "Pose published but assignment failed: %s" % String(
			assign_result.get("error", "unknown error")
		)
		return
	VISUAL_RIG_RESOLVER.clear_cache()
	_refresh_visual_rig_picker()
	v2_status.text = "Applied %s to %s. Opening the canonical game…" % [
		last_published_visual_rig_id,
		target_weapon_id,
	]
	call_deferred("_open_canonical_game_after_visual_apply")


func _open_canonical_game_after_visual_apply() -> void:
	var navigation := get_node_or_null("/root/StudioNavigation")
	if navigation != null:
		navigation.call("open_scene", "res://main.tscn")
		return
	var change_error := get_tree().change_scene_to_file("res://main.tscn")
	if change_error != OK:
		v2_status.text = "Pose applied, but the game could not open: %s" % error_string(change_error)


func _section_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", Color("7fb9d8"))
	return label


func _overlay_toggle(
	control_name: String,
	label_text: String,
	enabled: bool,
	callback: Callable
) -> CheckButton:
	var toggle := CheckButton.new()
	toggle.name = control_name
	toggle.text = label_text
	toggle.button_pressed = enabled
	toggle.toggled.connect(callback)
	return toggle


func _labeled_control(label_text: String, control: Control) -> Control:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = label_text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	row.add_child(control)
	return row


func _spin_box(minimum: float, maximum: float, increment: float) -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = minimum
	spin.max_value = maximum
	spin.step = increment
	spin.custom_minimum_size.x = 106.0
	return spin
