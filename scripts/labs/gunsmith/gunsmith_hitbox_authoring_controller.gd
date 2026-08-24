extends RefCounted

const HurtboxProfile := preload("res://scripts/combat/socom_hurtbox_profile.gd")


static func refresh_region_picker(lab: Node) -> void:
	if lab.hurtbox_region_picker == null:
		return
	lab.hurtbox_region_picker.clear()
	for region_key: StringName in HurtboxProfile.REGION_KEYS:
		lab.hurtbox_region_picker.add_item(HurtboxProfile.region_label(region_key))
		lab.hurtbox_region_picker.set_item_metadata(
			lab.hurtbox_region_picker.item_count - 1,
			region_key
		)
	for entry: Dictionary in lab.shared_custom_hitboxes:
		var editor_id := StringName(entry.get("id", &""))
		var damage_type := StringName(entry.get("damage_region", &"TORSO"))
		lab.hurtbox_region_picker.add_item("➕ %s · %s" % [
			lab.hitbox_model.display_name(editor_id),
			HurtboxProfile.damage_type_label(damage_type),
		])
		lab.hurtbox_region_picker.set_item_metadata(
			lab.hurtbox_region_picker.item_count - 1,
			editor_id
		)
	for picker_index in lab.hurtbox_region_picker.item_count:
		if StringName(lab.hurtbox_region_picker.get_item_metadata(picker_index)) == lab.selected_hurtbox_region:
			lab.hurtbox_region_picker.select(picker_index)
			break


static func set_shared_scale(lab: Node, value: float, region_key: StringName) -> void:
	lab.shared_hurtbox_scales[region_key] = clampf(
		value,
		HurtboxProfile.MIN_SCALE,
		HurtboxProfile.MAX_SCALE
	)
	apply_preview(lab)


static func select_region(lab: Node, region_key: StringName) -> void:
	if region_key not in lab.hitbox_model.editable_ids():
		return
	lab.selected_hurtbox_region = region_key
	if lab.hurtbox_region_picker:
		for picker_index in lab.hurtbox_region_picker.item_count:
			if StringName(lab.hurtbox_region_picker.get_item_metadata(picker_index)) == region_key:
				lab.hurtbox_region_picker.select(picker_index)
				break
	sync_selected_controls(lab)
	update_markers(lab)
	if lab.hud_status:
		lab.hud_status.text = "🟠 Editing %s. Drag its center, resize it, or paint its damage type." % lab.hitbox_model.display_name(region_key)


static func set_selected_size(lab: Node, value: float) -> void:
	lab.hitbox_model.set_width(lab.selected_hurtbox_region, value)
	apply_preview(lab)


static func set_selected_shape(lab: Node, shape_kind: StringName) -> void:
	if shape_kind not in HurtboxProfile.SHAPE_KEYS:
		return
	var geometry_document: Dictionary = lab.hitbox_model.geometry_for(lab.selected_hurtbox_region)
	HurtboxProfile.set_geometry_shape(
		geometry_document,
		lab.selected_hurtbox_region,
		shape_kind
	)
	lab.hitbox_model.set_geometry(
		lab.selected_hurtbox_region,
		geometry_document[lab.selected_hurtbox_region]
	)
	apply_preview(lab)
	sync_selected_controls(lab)
	if lab.hud_status:
		lab.hud_status.text = "🔶 %s changed to %s." % [
			lab.hitbox_model.display_name(lab.selected_hurtbox_region),
			HurtboxProfile.shape_label(shape_kind),
		]


static func set_selected_length(lab: Node, value: float) -> void:
	var geometry_document: Dictionary = lab.hitbox_model.geometry_for(lab.selected_hurtbox_region)
	HurtboxProfile.set_geometry_length_scale(
		geometry_document,
		lab.selected_hurtbox_region,
		value
	)
	lab.hitbox_model.set_geometry(
		lab.selected_hurtbox_region,
		geometry_document[lab.selected_hurtbox_region]
	)
	apply_preview(lab)


static func set_selected_offset_component(
	lab: Node,
	value: float,
	axis: StringName
) -> void:
	var selected_offset: Vector3 = lab.hitbox_model.offset(lab.selected_hurtbox_region)
	match axis:
		&"x": selected_offset.x = value
		&"y": selected_offset.y = value
		&"z": selected_offset.z = value
	lab.hitbox_model.set_offset(lab.selected_hurtbox_region, selected_offset)
	apply_preview(lab)


static func sync_selected_controls(lab: Node) -> void:
	lab._update_slider_value(
		"hurtbox_selected_size",
		lab.hitbox_model.width(lab.selected_hurtbox_region)
	)
	lab._update_slider_value(
		"hurtbox_selected_length",
		lab.hitbox_model.length(lab.selected_hurtbox_region)
	)
	var selected_offset: Vector3 = lab.hitbox_model.offset(lab.selected_hurtbox_region)
	lab._update_slider_value("hurtbox_offset_x", selected_offset.x)
	lab._update_slider_value("hurtbox_offset_y", selected_offset.y)
	lab._update_slider_value("hurtbox_offset_z", selected_offset.z)
	var length_entry: Dictionary = lab.sliders_map.get("hurtbox_selected_length", {})
	var length_slider := length_entry.get("slider") as HSlider
	if length_slider:
		length_slider.editable = lab.hitbox_model.shape(lab.selected_hurtbox_region) != &"sphere"
	if lab.hurtbox_shape_picker:
		var selected_shape: StringName = lab.hitbox_model.shape(lab.selected_hurtbox_region)
		for shape_index in lab.hurtbox_shape_picker.item_count:
			if StringName(lab.hurtbox_shape_picker.get_item_metadata(shape_index)) == selected_shape:
				lab.hurtbox_shape_picker.select(shape_index)
				break
	if lab.delete_hitbox_button:
		lab.delete_hitbox_button.disabled = lab.hitbox_model.custom_index(lab.selected_hurtbox_region) < 0
	if lab.hurtbox_damage_type_picker:
		var is_custom: bool = lab.hitbox_model.custom_index(lab.selected_hurtbox_region) >= 0
		lab.hurtbox_damage_type_picker.disabled = not is_custom
		var damage_type: StringName = lab.hitbox_model.damage_type(lab.selected_hurtbox_region)
		for type_index in lab.hurtbox_damage_type_picker.item_count:
			if StringName(lab.hurtbox_damage_type_picker.get_item_metadata(type_index)) == damage_type:
				lab.hurtbox_damage_type_picker.select(type_index)
				break


static func apply_preview(lab: Node) -> void:
	if lab.composure_preview_dummy == null:
		return
	if lab.composure_preview_dummy.has_method("apply_hurtbox_tuning"):
		lab.composure_preview_dummy.call("apply_hurtbox_tuning", lab.shared_hurtbox_scales)
	if lab.composure_preview_dummy.has_method("apply_hurtbox_geometry"):
		lab.composure_preview_dummy.call("apply_hurtbox_geometry", lab.shared_hurtbox_geometry)
	if lab.composure_preview_dummy.has_method("apply_custom_hitboxes"):
		lab.composure_preview_dummy.call("apply_custom_hitboxes", lab.shared_custom_hitboxes)
	sync_marker_set(lab)
	update_markers(lab)


static func duplicate_selected(lab: Node) -> void:
	var editor_id: StringName = lab.hitbox_model.duplicate_hitbox(lab.selected_hurtbox_region)
	lab.shared_custom_hitboxes = lab.hitbox_model.custom_hitboxes
	apply_preview(lab)
	refresh_region_picker(lab)
	select_region(lab, editor_id)
	if lab.hud_status:
		lab.hud_status.text = "➕ New physical hitbox created. Drag it into place, resize it, then paint its damage type."


static func delete_selected(lab: Node) -> void:
	var source_region: StringName = lab.hitbox_model.delete_custom(lab.selected_hurtbox_region)
	if source_region == &"":
		lab._show_rig_error("Built-in anatomy cannot be deleted. Select a duplicate first.")
		return
	lab.shared_custom_hitboxes = lab.hitbox_model.custom_hitboxes
	lab.selected_hurtbox_region = source_region
	apply_preview(lab)
	refresh_region_picker(lab)
	select_region(lab, source_region)
	if lab.hud_status:
		lab.hud_status.text = "🗑 Duplicate hitbox removed."


static func set_selected_damage_type(lab: Node, damage_type: StringName) -> void:
	if not lab.hitbox_model.set_damage_type(lab.selected_hurtbox_region, damage_type):
		return
	lab.shared_custom_hitboxes = lab.hitbox_model.custom_hitboxes
	apply_preview(lab)
	refresh_region_picker(lab)
	if lab.hud_status:
		lab.hud_status.text = "🎨 %s painted as %s damage." % [
			lab.hitbox_model.display_name(lab.selected_hurtbox_region),
			HurtboxProfile.damage_type_label(damage_type),
		]


static func snap_selected_to_rig(lab: Node) -> void:
	lab.hitbox_model.snap_to_rig(lab.selected_hurtbox_region)
	apply_preview(lab)
	sync_selected_controls(lab)
	if lab.hud_status:
		lab.hud_status.text = "🦴 %s snapped to its animated rig bones. Width and paint were preserved." % lab.hitbox_model.display_name(lab.selected_hurtbox_region)


static func align_all_to_rig(lab: Node) -> void:
	lab.hitbox_model.align_builtins_to_rig()
	lab.shared_hurtbox_geometry = lab.hitbox_model.geometry
	apply_preview(lab)
	sync_selected_controls(lab)
	if lab.hud_status:
		lab.hud_status.text = "🦴 Built-in hitboxes aligned to the animated rig. Authored duplicates were preserved."


static func sync_marker_set(lab: Node) -> void:
	var desired_ids: Array[StringName] = lab.hitbox_model.editable_ids()
	for existing_id: StringName in lab.hurtbox_edit_markers.keys():
		if existing_id in desired_ids:
			continue
		var old_marker := lab.hurtbox_edit_markers[existing_id] as MeshInstance3D
		if is_instance_valid(old_marker):
			old_marker.queue_free()
		lab.hurtbox_edit_markers.erase(existing_id)
	for region_key: StringName in desired_ids:
		if lab.hurtbox_edit_markers.has(region_key):
			continue
		var marker: MeshInstance3D = lab._create_marker(
			Color(1.0, 0.52, 0.12),
			"HitboxCenter_%s" % String(region_key),
			0.014
		)
		marker.visible = false
		lab.add_child(marker)
		lab.hurtbox_edit_markers[region_key] = marker
	lab._register_interactive_dots()


static func region_area(lab: Node, region_key: StringName) -> Area3D:
	if lab.composure_preview_dummy == null or not lab.composure_preview_dummy.has_method("get_hurtbox_rig"):
		return null
	var rig := lab.composure_preview_dummy.call("get_hurtbox_rig") as Node3D
	if rig == null:
		return null
	return rig.call("get_editor_hitbox_area", region_key) as Area3D


static func update_markers(lab: Node) -> void:
	for region_key: StringName in lab.hurtbox_edit_markers:
		var marker := lab.hurtbox_edit_markers[region_key] as MeshInstance3D
		var area: Area3D = region_area(lab, region_key)
		marker.visible = lab.composure_preview_active and area != null
		if area != null:
			marker.global_position = area.global_position
			marker.scale = Vector3.ONE * (1.45 if region_key == lab.selected_hurtbox_region else 1.0)


static func save_shared(lab: Node) -> bool:
	if not HurtboxProfile.save_profile(
		lab.shared_hurtbox_scales,
		lab.shared_hurtbox_geometry,
		lab.shared_custom_hitboxes
	):
		lab._show_rig_error("Could not save the shared gameplay hitbox profile.")
		return false
	if lab.hud_status:
		lab.hud_status.text = "✅ Shared hitboxes saved. Main targets and network operators will load these exact sizes."
		lab.hud_status.tooltip_text = lab.hud_status.text
		lab.hud_status.add_theme_color_override("font_color", Color(0.2, 1.0, 0.4))
	return true
