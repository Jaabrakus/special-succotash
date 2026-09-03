class_name GunsmithWeaponRigPanel
extends RefCounted

## Visible Gunsmith authoring surface for values consumed by gameplay.
## Legacy animation and preview controls stay outside this panel.

const RecomCatalogAdapter := preload(
	"res://scripts/labs/gunsmith/gunsmith_recom_catalog_adapter.gd"
)
const WeaponContactGraphContract := preload(
	"res://scripts/weapons/weapon_contact_graph_contract.gd"
)


static func build(lab: Node, parent: VBoxContainer) -> void:
	var title := Label.new()
	title.text = "SOCOM WEAPON RIG"
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color(0.2, 1.0, 0.6))
	parent.add_child(title)

	var purpose := Label.new()
	purpose.text = "Calibrate the model and physical sockets used by gameplay. Animation poses belong in Animation Studio."
	purpose.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	purpose.add_theme_font_size_override("font_size", 10)
	purpose.add_theme_color_override("font_color", Color(0.62, 0.74, 0.78))
	parent.add_child(purpose)

	_add_section(parent, "1. Runtime Weapon")
	_build_weapon_selector(lab, parent)

	_add_section(parent, "2. Model Alignment")
	_add_model_alignment(lab, parent)

	_add_section(parent, "3. Hand Contact Sockets")
	_add_socket_xyz(lab, parent, "rh", "Trigger Hand", func(): return lab.right_grip_local_pos, -1.50, 1.50, func(value: Vector3):
		lab.right_grip_local_pos = value
		lab._sync_markers()
	)
	_add_socket_xyz(lab, parent, "ik", "Support Hand", func(): return lab.left_grip_local_pos, -1.20, 1.20, func(value: Vector3):
		lab.left_grip_local_pos = value
		lab._sync_markers()
	)

	_add_section(parent, "4. Shared Shoulder / Hand / Spine Targets")
	_build_contact_graph(lab, parent)

	_add_section(parent, "5. Barrel and Effects Sockets")
	_add_socket_xyz(lab, parent, "bb", "Barrel Base", func(): return lab.barrel_base_local_pos, -1.60, 1.60, func(value: Vector3):
		lab.barrel_base_local_pos = value
		lab._sync_markers()
	)
	_add_socket_xyz(lab, parent, "mz", "Muzzle", func(): return lab.muzzle_local_pos, -1.60, 1.60, func(value: Vector3):
		lab.muzzle_local_pos = value
		lab._sync_markers()
	)
	_add_socket_xyz(lab, parent, "ej", "Ejection Port", func(): return lab.ejection_local_pos, -0.80, 0.80, func(value: Vector3):
		lab.ejection_local_pos = value
		lab._sync_markers()
	)
	_add_socket_xyz(lab, parent, "op", "Optic Rail", func(): return lab.optic_local_pos, -0.80, 0.80, func(value: Vector3):
		lab.optic_local_pos = value
		lab._sync_markers()
	)

	var stock_note := Label.new()
	stock_note.text = "Buttstock contact is derived from the trigger grip and barrel axis."
	stock_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stock_note.add_theme_font_size_override("font_size", 10)
	stock_note.add_theme_color_override("font_color", Color(0.78, 0.68, 0.38))
	parent.add_child(stock_note)


static func refresh(lab: Node) -> void:
	var title := lab.find_child("SelectedWeaponRigLabel", true, false) as Label
	if title != null:
		title.text = "%s • %s" % [lab.weapon_display_name, lab.selected_category]
	var values := {
		"grip_x": lab.grip_offset_pos.x,
		"grip_y": lab.grip_offset_pos.y,
		"grip_z": lab.grip_offset_pos.z,
		"rot_pitch": lab.grip_offset_rot.x,
		"rot_yaw": lab.grip_offset_rot.y,
		"rot_roll": lab.grip_offset_rot.z,
		"scale_mult": lab.user_scale_multiplier,
		"rh_x": lab.right_grip_local_pos.x,
		"rh_y": lab.right_grip_local_pos.y,
		"rh_z": lab.right_grip_local_pos.z,
		"ik_x": lab.left_grip_local_pos.x,
		"ik_y": lab.left_grip_local_pos.y,
		"ik_z": lab.left_grip_local_pos.z,
		"bb_x": lab.barrel_base_local_pos.x,
		"bb_y": lab.barrel_base_local_pos.y,
		"bb_z": lab.barrel_base_local_pos.z,
		"mz_x": lab.muzzle_local_pos.x,
		"mz_y": lab.muzzle_local_pos.y,
		"mz_z": lab.muzzle_local_pos.z,
		"ej_x": lab.ejection_local_pos.x,
		"ej_y": lab.ejection_local_pos.y,
		"ej_z": lab.ejection_local_pos.z,
		"op_x": lab.optic_local_pos.x,
		"op_y": lab.optic_local_pos.y,
		"op_z": lab.optic_local_pos.z,
	}
	var contact_position: Vector3 = WeaponContactGraphContract.target_position_offset(
		lab.weapon_contact_graph_profile,
		lab.selected_weapon_contact_target
	)
	var contact_rotation: Vector3 = WeaponContactGraphContract.target_rotation_offset_degrees(
		lab.weapon_contact_graph_profile,
		lab.selected_weapon_contact_target
	)
	values.merge({
		"cg_pos_x": contact_position.x,
		"cg_pos_y": contact_position.y,
		"cg_pos_z": contact_position.z,
		"cg_rot_x": contact_rotation.x,
		"cg_rot_y": contact_rotation.y,
		"cg_rot_z": contact_rotation.z,
	})
	for control_name: String in values:
		lab._update_slider_value(control_name, float(values[control_name]))


static func _build_weapon_selector(lab: Node, parent: VBoxContainer) -> void:
	var category_select := OptionButton.new()
	category_select.name = "RuntimeWeaponCategorySelect"
	var categories: Array = lab.weapon_categories.keys()
	for category: String in categories:
		category_select.add_item(category)
		category_select.set_item_metadata(category_select.item_count - 1, category)
		if category == lab.selected_category:
			category_select.select(category_select.item_count - 1)
	parent.add_child(category_select)

	var weapon_select := OptionButton.new()
	weapon_select.name = "RuntimeWeaponSelect"
	weapon_select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(weapon_select)

	var selected_label := Label.new()
	selected_label.name = "SelectedWeaponRigLabel"
	selected_label.text = "%s • %s" % [lab.weapon_display_name, lab.selected_category]
	selected_label.add_theme_font_size_override("font_size", 11)
	selected_label.add_theme_color_override("font_color", Color(0.3, 0.9, 1.0))
	parent.add_child(selected_label)

	var populate := func(category: String):
		weapon_select.clear()
		for weapon_id: String in lab.weapon_categories.get(category, []):
			weapon_select.add_item(RecomCatalogAdapter.display_name(weapon_id))
			weapon_select.set_item_metadata(weapon_select.item_count - 1, weapon_id)
			if weapon_id == lab.selected_weapon_file:
				weapon_select.select(weapon_select.item_count - 1)
	populate.call(lab.selected_category)

	category_select.item_selected.connect(func(index: int):
		lab.selected_category = String(category_select.get_item_metadata(index))
		populate.call(lab.selected_category)
		if weapon_select.item_count > 0:
			lab.selected_weapon_file = String(weapon_select.get_item_metadata(0))
			lab._load_weapon(lab.selected_weapon_file)
			refresh(lab)
	)
	weapon_select.item_selected.connect(func(index: int):
		lab.selected_weapon_file = String(weapon_select.get_item_metadata(index))
		lab._load_weapon(lab.selected_weapon_file)
		refresh(lab)
	)


static func _add_model_alignment(lab: Node, parent: VBoxContainer) -> void:
	lab._add_slider(parent, "grip_x", "Model X", -0.25, 0.25, lab.grip_offset_pos.x, func(value: float): lab.grip_offset_pos.x = value; lab._sync_weapon_translation())
	lab._add_slider(parent, "grip_y", "Model Y", -0.25, 0.25, lab.grip_offset_pos.y, func(value: float): lab.grip_offset_pos.y = value; lab._sync_weapon_translation())
	lab._add_slider(parent, "grip_z", "Model Z", -0.25, 0.25, lab.grip_offset_pos.z, func(value: float): lab.grip_offset_pos.z = value; lab._sync_weapon_translation())
	lab._add_slider(parent, "rot_pitch", "Model Pitch", -180.0, 180.0, lab.grip_offset_rot.x, func(value: float): lab.grip_offset_rot.x = value; lab._sync_weapon_transform(); lab._refresh_rotation_dials())
	lab._add_slider(parent, "rot_yaw", "Model Yaw", -180.0, 180.0, lab.grip_offset_rot.y, func(value: float): lab.grip_offset_rot.y = value; lab._sync_weapon_transform(); lab._refresh_rotation_dials())
	lab._add_slider(parent, "rot_roll", "Model Roll", -180.0, 180.0, lab.grip_offset_rot.z, func(value: float): lab.grip_offset_rot.z = value; lab._sync_weapon_transform(); lab._refresh_rotation_dials())
	lab._add_slider(parent, "scale_mult", "Model Scale", 0.5, 2.0, lab.user_scale_multiplier, func(value: float): lab.user_scale_multiplier = value; lab._sync_weapon_transform())


static func _build_contact_graph(lab: Node, parent: VBoxContainer) -> void:
	var note := Label.new()
	note.text = "Reference-style TargetPivot. Drag the colored targets in 3D or edit their position/rotation offsets here. SOCOM remains the camera and shot owner."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_font_size_override("font_size", 10)
	parent.add_child(note)

	var enabled := CheckButton.new()
	enabled.name = "WeaponContactGraphEnabled"
	enabled.text = "Use contact graph in gameplay presentation"
	enabled.button_pressed = bool(lab.weapon_contact_graph_profile.get("enabled", true))
	enabled.toggled.connect(func(value: bool):
		lab.weapon_contact_graph_profile["enabled"] = value
		lab._sync_weapon_contact_graph()
	)
	parent.add_child(enabled)

	var picker := OptionButton.new()
	picker.name = "WeaponContactTargetPicker"
	for target_id in WeaponContactGraphContract.TARGET_IDS:
		picker.add_item(String(target_id).replace("_", " ").capitalize())
		picker.set_item_metadata(picker.item_count - 1, target_id)
		if target_id == lab.selected_weapon_contact_target:
			picker.select(picker.item_count - 1)
	picker.item_selected.connect(func(index: int):
		lab._set_weapon_contact_target(String(picker.get_item_metadata(index)))
		refresh(lab)
	)
	parent.add_child(picker)

	for axis in 3:
		var component_axis: int = axis
		var axis_name: String = ["X", "Y", "Z"][axis]
		lab._add_slider(
			parent,
			"cg_pos_%s" % axis_name.to_lower(),
			"Position Offset %s (m)" % axis_name,
			-0.35,
			0.35,
			0.0,
			func(value: float): lab._set_weapon_contact_component("position", component_axis, value)
		)
	for axis in 3:
		var component_axis: int = axis
		var axis_name: String = ["X", "Y", "Z"][axis]
		lab._add_slider(
			parent,
			"cg_rot_%s" % axis_name.to_lower(),
			"Rotation Offset %s (deg)" % axis_name,
			-90.0,
			90.0,
			0.0,
			func(value: float): lab._set_weapon_contact_component("rotation", component_axis, value)
		)
	refresh(lab)


static func _add_socket_xyz(
	lab: Node,
	parent: VBoxContainer,
	key: String,
	label_text: String,
	read_current: Callable,
	minimum: float,
	maximum: float,
	changed: Callable
) -> void:
	var initial: Vector3 = read_current.call()
	var label := Label.new()
	label.text = label_text
	label.add_theme_font_size_override("font_size", 11)
	parent.add_child(label)
	lab._add_slider(parent, "%s_x" % key, "X", minimum, maximum, initial.x, func(value: float): _set_vector_axis(read_current, changed, 0, value))
	lab._add_slider(parent, "%s_y" % key, "Y", minimum, maximum, initial.y, func(value: float): _set_vector_axis(read_current, changed, 1, value))
	lab._add_slider(parent, "%s_z" % key, "Z", minimum, maximum, initial.z, func(value: float): _set_vector_axis(read_current, changed, 2, value))


static func _set_vector_axis(read_current: Callable, changed: Callable, axis: int, component: float) -> void:
	var value: Vector3 = read_current.call()
	value[axis] = component
	changed.call(value)


static func _add_section(parent: VBoxContainer, text: String) -> void:
	parent.add_child(HSeparator.new())
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", Color(0.35, 0.92, 0.82))
	parent.add_child(label)
