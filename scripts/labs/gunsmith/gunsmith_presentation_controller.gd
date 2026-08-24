extends RefCounted

const GunsmithRotationOrbitControlScript := preload(
	"res://scripts/labs/gunsmith/gunsmith_rotation_orbit_control.gd"
)
const BULLET_VELOCITY_PREVIEW_SECONDS := 0.004
const EYE_ORIGIN_FORWARD_METERS := 0.13
const EYE_ORIGIN_HEIGHT_METERS := 0.09
const GUN_PLACEMENT_DIRECTION_HANDLE_METERS := 2.0


static func setup_rotation_controls(lab: Node) -> void:
	lab.rotation_panel = PanelContainer.new()
	lab.rotation_panel.name = "RotationCornerPanel"
	lab.rotation_panel.anchor_left = 1.0
	lab.rotation_panel.anchor_right = 1.0
	lab.rotation_panel.offset_left = -254.0
	lab.rotation_panel.offset_right = -16.0
	lab.rotation_panel.offset_top = 16.0
	lab.rotation_panel.offset_bottom = 198.0
	lab.rotation_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.035, 0.045, 0.06, 0.90)
	panel_style.border_color = Color(0.25, 0.85, 1.0, 0.70)
	panel_style.set_border_width_all(1)
	panel_style.set_corner_radius_all(8)
	panel_style.content_margin_left = 10.0
	panel_style.content_margin_right = 10.0
	panel_style.content_margin_top = 7.0
	panel_style.content_margin_bottom = 7.0
	lab.rotation_panel.add_theme_stylebox_override("panel", panel_style)
	lab.overlay.add_child(lab.rotation_panel)
	var content := VBoxContainer.new()
	lab.rotation_panel.add_child(content)
	lab.rotation_title_label = Label.new()
	lab.rotation_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lab.rotation_title_label.add_theme_font_size_override("font_size", 12)
	lab.rotation_title_label.add_theme_color_override("font_color", Color(0.75, 0.95, 1.0))
	content.add_child(lab.rotation_title_label)
	lab.rotation_orbit_control = GunsmithRotationOrbitControlScript.new()
	lab.rotation_orbit_control.connect(
		"axis_delta_requested",
		Callable(lab, "_apply_rotation_dial_delta")
	)
	lab.rotation_orbit_control.connect(
		"hand_direction_delta_requested",
		Callable(lab, "_apply_hand_direction_delta")
	)
	content.add_child(lab.rotation_orbit_control)
	var values_row := HBoxContainer.new()
	values_row.alignment = BoxContainer.ALIGNMENT_CENTER
	content.add_child(values_row)
	for axis_name in ["pitch", "yaw", "roll"]:
		var value_label := Label.new()
		value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		value_label.add_theme_font_size_override("font_size", 10)
		value_label.custom_minimum_size.x = 70.0
		var axis_color: Color = GunsmithRotationOrbitControlScript.axis_color(axis_name)
		value_label.add_theme_color_override("font_color", axis_color)
		values_row.add_child(value_label)
		lab.rotation_value_labels[axis_name] = value_label
	refresh_rotation_dials(lab)


static func apply_rotation_delta(lab: Node, axis_name: String, delta_degrees: float) -> void:
	if lab.active_gizmo_id == "hand":
		if axis_name == "pitch":
			lab.palm_pitch = clampf(lab.palm_pitch + delta_degrees, -90.0, 90.0)
		elif axis_name == "yaw":
			lab.palm_yaw = clampf(lab.palm_yaw + delta_degrees, -90.0, 90.0)
		else:
			lab.palm_roll = wrapf(lab.palm_roll + delta_degrees, -180.0, 180.0)
		lab._update_slider_value("p_" + axis_name, rotation_axis_value(lab, axis_name))
	else:
		lab._adjust_weapon_rotation(axis_name, delta_degrees)
	refresh_rotation_dials(lab)


static func apply_hand_direction_delta(lab: Node, yaw_delta: float, pitch_delta: float) -> void:
	lab.palm_yaw = clampf(lab.palm_yaw + yaw_delta, -90.0, 90.0)
	lab.palm_pitch = clampf(lab.palm_pitch + pitch_delta, -90.0, 90.0)
	lab._update_slider_value("p_yaw", lab.palm_yaw)
	lab._update_slider_value("p_pitch", lab.palm_pitch)
	refresh_rotation_dials(lab)


static func rotation_axis_value(lab: Node, axis_name: String) -> float:
	if lab.active_gizmo_id == "hand":
		if axis_name == "pitch": return lab.palm_pitch
		if axis_name == "yaw": return lab.palm_yaw
		return lab.palm_roll
	if lab._editing_action_weapon_frame():
		if axis_name == "pitch": return lab.animation_frame_weapon_rotation_correction_deg.x
		if axis_name == "yaw": return lab.animation_frame_weapon_rotation_correction_deg.y
		return lab.animation_frame_weapon_rotation_correction_deg.z
	if axis_name == "pitch": return lab.grip_offset_rot.x
	if axis_name == "yaw": return lab.grip_offset_rot.y
	return lab.grip_offset_rot.z


static func refresh_rotation_dials(lab: Node) -> void:
	if lab.rotation_title_label:
		lab.rotation_title_label.text = (
			"🔵 HUMAN HAND GRIP"
			if lab.active_gizmo_id == "hand"
			else (
				"🟠 FRAME WEAPON CORRECTION — MUZZLE AXIS"
				if lab._editing_action_weapon_frame()
				else "🟠 WEAPON-MOUNT ROTATION"
			)
		)
	if lab.rotation_orbit_control:
		lab.rotation_orbit_control.call("set_display_state", lab.active_gizmo_id == "hand", {
			"pitch": rotation_axis_value(lab, "pitch"),
			"yaw": rotation_axis_value(lab, "yaw"),
			"roll": rotation_axis_value(lab, "roll"),
		})
	for axis_name in ["pitch", "yaw", "roll"]:
		if not lab.rotation_value_labels.has(axis_name):
			continue
		var value_label: Label = lab.rotation_value_labels[axis_name]
		var display_name := String(axis_name).to_upper()
		if lab.active_gizmo_id == "hand":
			if axis_name == "pitch": display_name = "BEND"
			elif axis_name == "yaw": display_name = "TURN"
			else: display_name = "AROUND"
		value_label.text = "%s  %.1f°" % [
			display_name,
			rotation_axis_value(lab, axis_name),
		]


static func update_fire_debug_lines(lab: Node) -> void:
	if lab.fire_debug_instance == null:
		return
	if lab.active_lab_tab_name == "Composure":
		lab.fire_debug_instance.visible = false
		return
	lab.fire_debug_mesh.clear_surfaces()
	if not lab.show_bullet_velocity and not lab.show_barrel_axis and not lab.show_camera_aim and not lab.show_eye_sight and not lab.show_last_shot:
		lab.fire_debug_instance.visible = false
		return
	lab.fire_debug_instance.visible = true
	lab.fire_debug_mesh.surface_begin(Mesh.PRIMITIVE_LINES, lab.fire_debug_material)
	var target: Vector3 = (
		lab.current_aim_target
		if lab.current_aim_target != Vector3.ZERO
		else lab._camera_aim_sample().position
	)
	if lab.show_bullet_velocity and lab.muzzle_marker:
		add_fire_debug_segment(
			lab,
			lab.muzzle_marker.global_position,
			lab.muzzle_marker.global_position
				+ lab._bullet_velocity_vector() * BULLET_VELOCITY_PREVIEW_SECONDS,
			Color(0.15, 1.0, 0.18)
		)
	if lab.show_barrel_axis and lab.weapon_pivot and lab.muzzle_marker:
		var barrel_base: Vector3 = lab.weapon_pivot.to_global(lab._calibrated_barrel_base())
		var barrel_direction: Vector3 = lab._barrel_direction_world()
		add_fire_debug_segment(
			lab,
			barrel_base,
			lab.muzzle_marker.global_position + barrel_direction * 5.0,
			Color(1.0, 0.12, 0.08)
		)
	if lab.show_camera_aim and lab.cam:
		add_fire_debug_segment(lab, lab.cam.global_position, target, Color(0.1, 0.9, 1.0))
	if lab.show_eye_sight and lab.eye_sight_marker:
		var eye_direction: Vector3 = lab._eye_sight_direction_world()
		add_fire_debug_segment(
			lab,
			lab.eye_sight_marker.global_position,
			lab.eye_sight_marker.global_position + eye_direction * 50.0,
			Color(0.25, 0.55, 1.0)
		)
	if lab.show_last_shot and lab.last_shot_origin != lab.last_shot_end:
		add_fire_debug_segment(
			lab,
			lab.last_shot_origin,
			lab.last_shot_end,
			Color(1.0, 0.88, 0.15)
		)
	lab.fire_debug_mesh.surface_end()


static func update_eye_sight_marker(lab: Node) -> void:
	if lab.eye_sight_marker == null:
		return
	lab.eye_sight_marker.visible = lab.show_eye_sight and lab.active_lab_tab_name != "Composure"
	if lab.eye_sight_direction_marker != null:
		lab.eye_sight_direction_marker.visible = lab.eye_sight_marker.visible
	if not lab.eye_sight_marker.visible or lab.skeleton == null or lab.head_idx < 0:
		return
	var head_origin: Vector3 = lab._bone_world_origin(lab.head_idx)
	var operator_right: Vector3 = lab.skeleton.global_basis.x.normalized()
	var operator_up: Vector3 = lab.skeleton.global_basis.y.normalized()
	var operator_forward: Vector3 = lab.skeleton.global_basis.z.normalized()
	if not lab.gun_placement_anchor_local_by_posture.has(lab.preview_posture):
		var initial_origin := (
			head_origin
			+ operator_up * EYE_ORIGIN_HEIGHT_METERS
			+ operator_forward * EYE_ORIGIN_FORWARD_METERS
		)
		lab.gun_placement_anchor_local_by_posture[lab.preview_posture] = (
			lab.skeleton.to_local(initial_origin)
		)
	var neutral_origin: Vector3 = lab.skeleton.to_global(
		lab.gun_placement_anchor_local_by_posture[lab.preview_posture]
	)
	var origin_offset: Vector3 = lab._eye_sight_origin_offset()
	lab.eye_sight_marker.global_position = (
		neutral_origin
		+ operator_right * origin_offset.x
		+ operator_up * origin_offset.y
		+ operator_forward * origin_offset.z
	)
	if lab.eye_sight_direction_marker != null:
		lab.eye_sight_direction_marker.global_position = (
			lab.eye_sight_marker.global_position
			+ lab._eye_sight_direction_world()
			* GUN_PLACEMENT_DIRECTION_HANDLE_METERS
		)


static func add_fire_debug_segment(
	lab: Node,
	start: Vector3,
	finish: Vector3,
	color: Color
) -> void:
	lab.fire_debug_mesh.surface_set_color(color)
	lab.fire_debug_mesh.surface_add_vertex(start)
	lab.fire_debug_mesh.surface_set_color(color)
	lab.fire_debug_mesh.surface_add_vertex(finish)


static func draw_active_selection_brackets(lab: Node) -> void:
	if not lab.cam or not lab.reticle_canvas:
		return
	var target_world := Vector3.ZERO
	var selected_id := ""
	var color := Color(1.0, 0.55, 0.08)
	if lab.active_lab_tab_name == "Composure":
		var hitbox_marker := lab.hurtbox_edit_markers.get(lab.selected_hurtbox_region) as MeshInstance3D
		if hitbox_marker == null or not hitbox_marker.visible:
			return
		target_world = hitbox_marker.global_position
		selected_id = "hurtbox:%s" % String(lab.selected_hurtbox_region)
		color = Color(1.0, 0.52, 0.12)
	elif lab.active_gizmo_id == "hand":
		if not lab.left_grip_marker or not is_instance_valid(lab.left_grip_marker):
			return
		target_world = lab.left_grip_marker.global_position
		selected_id = "left_ik"
		color = Color(0.0, 0.95, 1.0)
	else:
		if not lab.weapon_gizmo_world or not is_instance_valid(lab.weapon_gizmo_world):
			return
		target_world = lab.weapon_gizmo_world.global_position
		selected_id = "weapon_mount"
	if lab.cam.is_position_behind(target_world):
		return
	var center: Vector2 = lab.cam.unproject_position(target_world)
	var is_hovered: bool = lab.hovered_dot_id == selected_id or lab.dragged_dot_id == selected_id
	var radius := 17.0 if is_hovered else 14.0
	var arm := 7.0
	color = Color.WHITE if is_hovered else color
	var width := 3.0 if is_hovered else 2.0
	lab.reticle_canvas.draw_line(center + Vector2(-radius, -radius), center + Vector2(-radius + arm, -radius), color, width, true)
	lab.reticle_canvas.draw_line(center + Vector2(-radius, -radius), center + Vector2(-radius, -radius + arm), color, width, true)
	lab.reticle_canvas.draw_line(center + Vector2(radius, -radius), center + Vector2(radius - arm, -radius), color, width, true)
	lab.reticle_canvas.draw_line(center + Vector2(radius, -radius), center + Vector2(radius, -radius + arm), color, width, true)
	lab.reticle_canvas.draw_line(center + Vector2(-radius, radius), center + Vector2(-radius + arm, radius), color, width, true)
	lab.reticle_canvas.draw_line(center + Vector2(-radius, radius), center + Vector2(-radius, radius - arm), color, width, true)
	lab.reticle_canvas.draw_line(center + Vector2(radius, radius), center + Vector2(radius - arm, radius), color, width, true)
	lab.reticle_canvas.draw_line(center + Vector2(radius, radius), center + Vector2(radius, radius - arm), color, width, true)
