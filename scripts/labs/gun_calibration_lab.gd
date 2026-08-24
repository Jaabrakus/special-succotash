class_name GunCalibrationLab
extends "res://scripts/labs/gunsmith/gunsmith_lab_preview_api.gd"

## SOCOM-141 AAA Tactical Gunsmith & Biomechanical Arm Engine
## Full Anatomical Human Arm Biomechanics (Anatomical Hinge Elbow, Shoulder Ball-Socket, Palm Alignment)
## Left hand automatically finds and biomechanically grips Socket_LeftHand on any firearm.

func _ready() -> void:
	hitbox_model = GunsmithHitboxModelScript.new()
	hitbox_model.configure(shared_hurtbox_scales, shared_hurtbox_geometry, shared_custom_hitboxes)
	animation_catalog = OperatorAnimationProfile.new()
	animation_catalog.load_project_map()
	presentation_router.configure(
		animation_catalog.clip_paths,
		animation_catalog.state_rules,
		animation_catalog.event_routes
	)
	_scan_all_animation_assets()
	handling_profile = WeaponAnimationProfile.build_default(
		WeaponAnimationProfile.infer_family(weapon_name, selected_category),
		animation_catalog.clip_paths
	)
	_setup_studio_environment()
	_setup_trooper_and_rig()
	_setup_elbow_pole_visuals()
	_setup_body_joint_visuals()
	_setup_target_range()
	_setup_composure_target_preview()
	_load_weapon(selected_weapon_file)
	_build_studio_ui()

func _input(event: InputEvent) -> void:
	GunsmithInputController.handle(self, event)

func _process(delta: float) -> void:
	GunsmithPreviewUpdateController.update(self, delta)


func _update_bloom_recovery(delta: float, trigger_held: bool) -> void:
	if trigger_held:
		return
	if current_bloom > 0.0:
		var recovery_speed := (
			crouch_bloom_recovery_speed
			if preview_posture == &"CROUCHED"
			else bloom_recovery_speed
		)
		current_bloom = maxf(0.0, current_bloom - recovery_speed * delta)
	if fire_cooldown <= 0.0:
		burst_shot_count = 0

func _scan_all_animation_assets() -> void:
	var result: Dictionary = animation_asset_catalog.scan("res://assets/animations/mixamo")
	all_animation_entries = (result.get("entries", []) as Array).duplicate(true)
	all_animation_paths = (result.get("paths", {}) as Dictionary).duplicate(true)

func _setup_target_range() -> void:
	target_board = Node3D.new()
	target_board.position = Vector3(0.0, 1.25, 6.0)
	add_child(target_board)

	var board_mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(1.2, 1.6, 0.08)
	board_mesh.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.25, 0.22, 0.18)
	board_mesh.material_override = mat
	target_board.add_child(board_mesh)

	var board_body := StaticBody3D.new()
	board_body.name = "ReticleTargetBody"
	board_body.set_meta("gun_lab_target", true)
	var board_shape := CollisionShape3D.new()
	var board_box := BoxShape3D.new()
	board_box.size = Vector3(1.2, 1.6, 0.08)
	board_shape.shape = board_box
	board_body.add_child(board_shape)
	target_board.add_child(board_body)

	var bullseye := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.3
	cyl.bottom_radius = 0.3
	cyl.height = 0.1
	bullseye.mesh = cyl
	bullseye.rotation_degrees = Vector3(90, 0, 0)
	bullseye.position = Vector3(0, 0.15, 0.01)
	var bull_mat := StandardMaterial3D.new()
	bull_mat.albedo_color = Color(0.85, 0.15, 0.15)
	bullseye.material_override = bull_mat
	target_board.add_child(bullseye)

func _build_studio_ui() -> void:
	GunsmithStudioView.build(self)





func _build_composure_tab(tab_container: TabContainer) -> void:
	GunsmithComposurePanelScript.build_for_lab(self, tab_container)


func _setup_composure_target_preview() -> void:
	composure_preview_dummy = TargetDummyScript.new() as Node3D
	composure_preview_dummy.name = "ComposureTposeTarget"
	composure_preview_dummy.visible = false
	add_child(composure_preview_dummy)
	call_deferred("_finish_composure_target_preview")


func _finish_composure_target_preview() -> void:
	GunsmithComposurePanelScript.finish_target_preview(self)


func _editable_hitbox_ids() -> Array[StringName]:
	return hitbox_model.editable_ids()
func _custom_hitbox_index(editor_id: StringName) -> int:
	return hitbox_model.custom_index(editor_id)
func _hitbox_source_region(editor_id: StringName) -> StringName:
	return hitbox_model.source_region(editor_id)
func _hitbox_damage_type(editor_id: StringName) -> StringName:
	return hitbox_model.damage_type(editor_id)
func _hitbox_display_name(editor_id: StringName) -> String:
	return hitbox_model.display_name(editor_id)
func _hitbox_width(editor_id: StringName) -> float:
	return hitbox_model.width(editor_id)
func _set_hitbox_width(editor_id: StringName, value: float) -> void:
	hitbox_model.set_width(editor_id, value)
func _hitbox_geometry(editor_id: StringName) -> Dictionary:
	return hitbox_model.geometry_for(editor_id)
func _set_hitbox_geometry(editor_id: StringName, geometry_entry: Dictionary) -> void:
	hitbox_model.set_geometry(editor_id, geometry_entry)
func _hitbox_offset(editor_id: StringName) -> Vector3:
	return hitbox_model.offset(editor_id)
func _hitbox_shape(editor_id: StringName) -> StringName:
	return hitbox_model.shape(editor_id)
func _set_hitbox_offset(editor_id: StringName, offset: Vector3) -> void:
	hitbox_model.set_offset(editor_id, offset)
func _hitbox_length(editor_id: StringName) -> float:
	return hitbox_model.length(editor_id)
func _next_custom_hitbox_id(source_region: StringName) -> StringName:
	var suffix := 1
	while true:
		var candidate := StringName("%s_extra_%d" % [String(source_region), suffix])
		if candidate not in hitbox_model.editable_ids():
			return candidate
		suffix += 1
	return &"extra_hitbox"
func _refresh_hurtbox_region_picker() -> void:
	GunsmithHitboxAuthoringController.refresh_region_picker(self)


func _set_shared_hurtbox_scale(value: float, region_key: StringName) -> void:
	GunsmithHitboxAuthoringController.set_shared_scale(self, value, region_key)


func _select_hurtbox_region(region_key: StringName) -> void:
	GunsmithHitboxAuthoringController.select_region(self, region_key)


func _set_selected_hurtbox_size(value: float) -> void:
	GunsmithHitboxAuthoringController.set_selected_size(self, value)


func _set_selected_hurtbox_shape(shape_kind: StringName) -> void:
	GunsmithHitboxAuthoringController.set_selected_shape(self, shape_kind)


func _set_selected_hurtbox_length(value: float) -> void:
	GunsmithHitboxAuthoringController.set_selected_length(self, value)


func _set_selected_hurtbox_offset_component(value: float, axis: StringName) -> void:
	GunsmithHitboxAuthoringController.set_selected_offset_component(self, value, axis)


func _sync_selected_hurtbox_controls() -> void:
	GunsmithHitboxAuthoringController.sync_selected_controls(self)


func _apply_shared_hurtbox_preview() -> void:
	GunsmithHitboxAuthoringController.apply_preview(self)


func _duplicate_selected_hitbox() -> void:
	GunsmithHitboxAuthoringController.duplicate_selected(self)
func _delete_selected_hitbox() -> void:
	GunsmithHitboxAuthoringController.delete_selected(self)
func _set_selected_hurtbox_damage_type(damage_type: StringName) -> void:
	GunsmithHitboxAuthoringController.set_selected_damage_type(self, damage_type)
func _snap_selected_hurtbox_to_rig() -> void:
	GunsmithHitboxAuthoringController.snap_selected_to_rig(self)
func _align_all_hitboxes_to_rig() -> void:
	GunsmithHitboxAuthoringController.align_all_to_rig(self)
func _create_hurtbox_edit_markers() -> void:
	_sync_hurtbox_edit_marker_set()


func _sync_hurtbox_edit_marker_set() -> void:
	GunsmithHitboxAuthoringController.sync_marker_set(self)


func _hurtbox_region_area(region_key: StringName) -> Area3D:
	return GunsmithHitboxAuthoringController.region_area(self, region_key)


func _update_hurtbox_edit_markers() -> void:
	GunsmithHitboxAuthoringController.update_markers(self)


func _save_shared_hurtboxes() -> bool:
	return GunsmithHitboxAuthoringController.save_shared(self)


func _on_gun_lab_tab_changed(tab_index: int, tab_container: TabContainer) -> void:
	var selected := tab_container.get_tab_control(tab_index)
	active_lab_tab_name = selected.name if selected != null else ""
	var show_composure := selected != null and selected.name == "Composure"
	composure_preview_active = show_composure
	if trooper_node:
		trooper_node.visible = not show_composure
	if composure_preview_dummy:
		composure_preview_dummy.visible = show_composure
	if hand_gizmo_world:
		hand_gizmo_world.visible = not show_composure
	if weapon_gizmo_world:
		weapon_gizmo_world.visible = not show_composure
	for editor_marker in [
		right_elbow_pole_marker,
		left_elbow_pole_marker,
		left_grip_marker,
		right_grip_marker,
		muzzle_marker,
		barrel_base_marker,
		ejection_marker,
		optic_marker,
		eye_sight_marker,
		eye_sight_direction_marker,
	]:
		if editor_marker != null:
			(editor_marker as Node3D).visible = not show_composure
	if joint_debug_instance:
		joint_debug_instance.visible = not show_composure
	_update_body_joint_visuals()
	_update_hurtbox_edit_markers()
	if show_composure:
		cam_target = Vector3(0.0, 1.02, 0.0)
		cam_distance = 3.15
		cam_pitch = -2.0
		cam_yaw = 180.0
		_update_camera()

func _add_slider(parent: Control, key: String, label_text: String, min_val: float, max_val: float, initial_val: float, callback: Callable) -> void:
	var row := HBoxContainer.new()
	row.custom_minimum_size.y = 26
	parent.add_child(row)

	var lbl := Label.new()
	lbl.text = label_text + ":"
	lbl.custom_minimum_size.x = 160
	lbl.add_theme_font_size_override("font_size", 11)
	row.add_child(lbl)

	var slider := HSlider.new()
	slider.min_value = min_val
	slider.max_value = max_val
	slider.step = 0.005 if max_val <= 2.0 else (0.01 if max_val <= 10.0 else 0.5)
	slider.value = initial_val
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.custom_minimum_size.x = 170

	var val_lbl := Label.new()
	val_lbl.text = "%.2f" % initial_val if absf(max_val) >= 5.0 else ("%.3f" % initial_val)
	val_lbl.custom_minimum_size.x = 60
	val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val_lbl.add_theme_font_size_override("font_size", 11)
	val_lbl.add_theme_color_override("font_color", Color(1.0, 0.9, 0.4))

	slider.value_changed.connect(func(v: float):
		val_lbl.text = "%.2f" % v if absf(max_val) >= 5.0 else ("%.3f" % v)
		callback.call(v)
	)
	row.add_child(slider)
	row.add_child(val_lbl)

	sliders_map[key] = {"slider": slider, "label": val_lbl, "name_label": lbl, "row": row}

func _current_reticle_profile() -> Dictionary:
	return {
		"base_gap_px": reticle_base_gap_px,
		"max_gap_px": reticle_max_gap_px,
		"response_speed": reticle_response_speed,
		"shot_kick_px": reticle_shot_kick_px,
		"shot_kick_return": reticle_shot_kick_return,
		"maximum_shot_kick_px": reticle_maximum_shot_kick_px,
		"maximum_movement_tick_extension_px": reticle_maximum_movement_tick_extension_px,
		"shot_bounce_duration": composure.shot_bounce_duration,
		"fire_interval_seconds": 60.0 / float(maxi(fire_rate_rpm, 60)),
	}


func _current_composure_profile() -> Dictionary:
	var profile := composure.export_profile()
	profile["opening_stress_multiplier"] = composure_opening_stress_multiplier
	profile["graze_damage_scale"] = composure_graze_damage_scale
	return profile


func _apply_reticle_preview_profile() -> void:
	if dynamic_reticle:
		dynamic_reticle.apply_profile(_current_reticle_profile())


func _update_fire_debug_lines() -> void:
	GunsmithPresentationController.update_fire_debug_lines(self)


func _update_eye_sight_marker() -> void:
	GunsmithPresentationController.update_eye_sight_marker(self)


func _eye_sight_correction() -> Vector3:
	if runtime_posture_layer == null:
		return Vector3.ZERO
	var reference := runtime_posture_layer.get_eye_sight_reference_degrees(
		preview_posture
	)
	return Vector3(reference.x, reference.y, 0.0)


func _eye_sight_origin_offset() -> Vector3:
	if runtime_posture_layer == null:
		return Vector3.ZERO
	return runtime_posture_layer.get_eye_sight_origin_offset_meters(
		preview_posture
	)


func _reset_gun_placement_line_profile() -> void:
	gun_placement_anchor_local_by_posture.clear()
	if runtime_posture_layer == null:
		return
	for posture: StringName in [&"STANDING", &"CROUCHED", &"PRONE"]:
		runtime_posture_layer.set_eye_sight_reference_degrees(posture, Vector2.ZERO)
		runtime_posture_layer.set_eye_sight_origin_offset_meters(
			posture,
			Vector3.ZERO
		)


func _load_gun_placement_line_profile(raw_profile: Variant) -> void:
	if runtime_posture_layer == null or not raw_profile is Dictionary:
		return
	var profile := raw_profile as Dictionary
	var by_stance: Variant = profile.get("by_stance", {})
	if not by_stance is Dictionary:
		return
	for posture: StringName in [&"STANDING", &"CROUCHED", &"PRONE"]:
		var raw_stance: Variant = (by_stance as Dictionary).get(String(posture), {})
		if not raw_stance is Dictionary:
			continue
		var stance := raw_stance as Dictionary
		# Legacy authored pitch/yaw is migrated away. Direction is always the
		# active reticle ray; only the origin and weapon roll remain authored.
		runtime_posture_layer.set_eye_sight_reference_degrees(posture, Vector2.ZERO)
		runtime_posture_layer.set_eye_sight_origin_offset_meters(
			posture,
			_vector_from_data(
				stance.get("position_offset_meters", {}),
				Vector3.ZERO
			)
		)


func _gun_placement_line_save_data() -> Dictionary:
	var by_stance: Dictionary = {}
	for posture: StringName in [&"STANDING", &"CROUCHED", &"PRONE"]:
		var position := (
			runtime_posture_layer.get_eye_sight_origin_offset_meters(posture)
			if runtime_posture_layer != null
			else Vector3.ZERO
		)
		by_stance[String(posture)] = {
			"position_offset_meters": _vector3_to_dictionary(position),
			"pitch_degrees": 0.0,
			"yaw_degrees": 0.0,
		}
	return {
		"space": "operator_local_weapon_placement",
		"direction_mode": "reticle_locked",
		"by_stance": by_stance,
	}


func _eye_sight_direction_world() -> Vector3:
	if skeleton == null or cam == null or eye_sight_marker == null:
		return Vector3.FORWARD
	return GunPlacementProfile.reticle_locked_direction(
		cam,
		eye_sight_marker.global_position,
		_reticle_screen_position()
	)


func _set_eye_sight_component(value: float, component: StringName) -> void:
	if runtime_posture_layer == null:
		return
	var correction := _eye_sight_correction()
	if component == &"pitch":
		correction.x = value
	elif component == &"yaw":
		correction.y = value
	runtime_posture_layer.set_eye_sight_reference_degrees(
		preview_posture,
		Vector2(correction.x, correction.y)
	)


func _set_eye_sight_origin_component(value: float, component: StringName) -> void:
	if runtime_posture_layer == null:
		return
	var offset := _eye_sight_origin_offset()
	if component == &"x":
		offset.x = value
	elif component == &"y":
		offset.y = value
	elif component == &"z":
		offset.z = value
	runtime_posture_layer.set_eye_sight_origin_offset_meters(
		preview_posture,
		offset
	)
	_update_eye_sight_marker()


func _sync_eye_sight_controls() -> void:
	var correction := _eye_sight_correction()
	_update_slider_value("eye_sight_pitch", correction.x)
	_update_slider_value("eye_sight_yaw", correction.y)
	var origin_offset := _eye_sight_origin_offset()
	_update_slider_value("eye_origin_x", origin_offset.x)
	_update_slider_value("eye_origin_y", origin_offset.y)
	_update_slider_value("eye_origin_z", origin_offset.z)


func _add_fire_debug_segment(start: Vector3, finish: Vector3, color: Color) -> void:
	GunsmithPresentationController.add_fire_debug_segment(self, start, finish, color)


func _draw_socom_reticle() -> void:
	# The shared SocomDynamicReticle owns the actual reticle. This transparent
	# overlay only draws calibration selection brackets above it.
	_draw_active_selection_brackets()

func _draw_active_selection_brackets() -> void:
	GunsmithPresentationController.draw_active_selection_brackets(self)
