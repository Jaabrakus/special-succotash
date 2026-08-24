extends RefCounted

const JointControlSchema := preload("res://scripts/player/operator_joint_control_schema.gd")
const TUNABLE_BODY_JOINTS := JointControlSchema.SELECTABLE_JOINTS
const JOINT_CHAIN_LINKS: Dictionary = {
	&"head": {&"neck": 0.55, &"spine2": 0.25, &"spine1": 0.10},
	&"neck": {&"spine2": 0.18},
	&"spine2": {&"spine1": 0.35, &"spine": 0.15},
	&"spine1": {&"spine": 0.25},
	&"left_upper_arm": {&"left_shoulder": 0.20},
	&"right_upper_arm": {&"right_shoulder": 0.20},
}

static func _set_elbow_pole_from_world(lab: Node,side: StringName, world_pos: Vector3) -> void:
	if not lab.skeleton:
		return
	var body_basis: Basis = lab.skeleton.global_transform.basis.orthonormalized()
	var wrist_world: Vector3 = lab._right_palm_contact_world() if side == &"right" else lab._left_palm_contact_world()
	var base_world: Vector3 = (
		lab._right_elbow_pole_base_world(wrist_world)
		if side == &"right"
		else lab._left_elbow_pole_base_world(wrist_world)
	)
	var local_offset: Vector3 = body_basis.inverse() * (world_pos - base_world)
	local_offset.x = clampf(local_offset.x, -0.30, 0.30)
	local_offset.y = clampf(local_offset.y, -0.30, 0.30)
	local_offset.z = clampf(local_offset.z, -0.30, 0.30)
	if side == &"right":
		lab.right_elbow_pole_offset = local_offset
	else:
		lab.left_elbow_pole_offset = local_offset
	lab._store_current_stance_elbow_poles()
	lab._update_elbow_slider_controls()


static func _store_current_stance_elbow_poles(lab: Node) -> void:
	lab.elbow_poles_by_stance[lab.preview_posture] = {
		"right": lab.right_elbow_pole_offset,
		"left": lab.left_elbow_pole_offset,
	}


static func _restore_current_stance_elbow_poles(lab: Node) -> void:
	var stance_value: Variant = lab.elbow_poles_by_stance.get(lab.preview_posture, {})
	var stance_poles: Dictionary = stance_value if stance_value is Dictionary else {}
	lab.right_elbow_pole_offset = stance_poles.get("right", Vector3.ZERO)
	lab.left_elbow_pole_offset = stance_poles.get("left", Vector3.ZERO)
	lab._update_elbow_slider_controls()


static func _update_elbow_slider_controls(lab: Node) -> void:
	for entry in [
		["right_elbow_x", lab.right_elbow_pole_offset.x],
		["right_elbow_y", lab.right_elbow_pole_offset.y],
		["right_elbow_z", lab.right_elbow_pole_offset.z],
		["left_elbow_x", lab.left_elbow_pole_offset.x],
		["left_elbow_y", lab.left_elbow_pole_offset.y],
		["left_elbow_z", lab.left_elbow_pole_offset.z],
	]:
		lab._update_slider_value(entry[0], entry[1])


static func _set_elbow_component(lab: Node,value: float, side: StringName, axis: StringName) -> void:
	var offset: Vector3 = lab.right_elbow_pole_offset if side == &"right" else lab.left_elbow_pole_offset
	match axis:
		&"x": offset.x = value
		&"y": offset.y = value
		&"z": offset.z = value
	if side == &"right":
		lab.right_elbow_pole_offset = offset
	else:
		lab.left_elbow_pole_offset = offset
	lab._store_current_stance_elbow_poles()


static func _elbow_poles_save_data(lab: Node) -> Dictionary:
	lab._store_current_stance_elbow_poles()
	var saved: Dictionary = {}
	for posture: StringName in [&"STANDING", &"CROUCHED", &"PRONE"]:
		var stance_poles: Dictionary = lab.elbow_poles_by_stance.get(posture, {})
		saved[String(posture)] = {
			"right": lab._vector_to_data(stance_poles.get("right", Vector3.ZERO)),
			"left": lab._vector_to_data(stance_poles.get("left", Vector3.ZERO)),
		}
	return saved

static func _update_slider_value(lab: Node,slider_key: String, val: float) -> void:
	if lab.sliders_map.has(slider_key):
		var s: HSlider = lab.sliders_map[slider_key]["slider"]
		var lbl: Label = lab.sliders_map[slider_key]["label"]
		if s:
			s.set_value_no_signal(val)
			if lbl: lbl.text = "%.2f" % val if absf(val) >= 5.0 else ("%.3f" % val)


static func _setup_elbow_pole_visuals(lab: Node) -> void:
	lab.right_elbow_pole_marker = lab._create_marker(Color(1.0, 0.25, 0.9), "RightElbowIKPole", 0.016)
	lab.left_elbow_pole_marker = lab._create_marker(Color(0.75, 0.35, 1.0), "LeftElbowIKPole", 0.016)
	lab.add_child(lab.right_elbow_pole_marker)
	lab.add_child(lab.left_elbow_pole_marker)
	lab.joint_debug_instance = MeshInstance3D.new()
	lab.joint_debug_instance.name = "ElbowSkeletonFrame"
	lab.joint_debug_instance.mesh = lab.joint_debug_mesh
	var line_material := StandardMaterial3D.new()
	line_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	line_material.vertex_color_use_as_albedo = true
	line_material.no_depth_test = true
	lab.joint_debug_instance.material_override = line_material
	lab.add_child(lab.joint_debug_instance)
	lab._register_interactive_dots()


static func _setup_body_joint_visuals(lab: Node) -> void:
	for joint_name: StringName in TUNABLE_BODY_JOINTS:
		var marker: MeshInstance3D = lab._create_marker(Color(0.15, 0.85, 1.0), "BodyJoint_%s" % String(joint_name), 0.012)
		lab.add_child(marker)
		lab.body_joint_markers[joint_name] = marker
	lab._register_interactive_dots()


static func _update_body_joint_visuals(lab: Node) -> void:
	if lab.runtime_posture_layer == null:
		return
	for joint_name: StringName in lab.body_joint_markers:
		var bone_index := int(lab.runtime_posture_layer.bone_indices.get(joint_name, -1))
		var marker := lab.body_joint_markers[joint_name] as MeshInstance3D
		if lab.active_lab_tab_name == "Composure" or not lab.show_joint_bubbles:
			marker.visible = false
		elif lab.isolate_selected_node:
			marker.visible = (joint_name == lab.selected_body_joint) and (bone_index >= 0)
		else:
			marker.visible = bone_index >= 0
		if bone_index >= 0:
			marker.global_position = lab._bone_world_origin(bone_index)


static func _select_body_joint(lab: Node,joint_name: StringName) -> void:
	if joint_name not in TUNABLE_BODY_JOINTS:
		return
	lab.selected_body_joint = joint_name
	lab._sync_body_joint_controls()
	if lab.hud_status:
		lab.hud_status.text = "🔷 Editing %s for %s. Drag for pitch/yaw; wheel for roll." % [
			String(joint_name).replace("_", " "),
			String(lab.preview_posture).capitalize(),
		]


static func _adjust_selected_joint_rotation(lab: Node,delta_degrees: Vector3) -> void:
	if lab.runtime_posture_layer == null:
		return
	match JointControlSchema.control_mode(lab.selected_body_joint):
		&"elbow_pole":
			var side: StringName = &"right" if lab.selected_body_joint == &"right_forearm" else &"left"
			var offset: Vector3 = lab.right_elbow_pole_offset if side == &"right" else lab.left_elbow_pole_offset
			offset += delta_degrees * 0.0025
			if side == &"right":
				lab.right_elbow_pole_offset = offset
			else:
				lab.left_elbow_pole_offset = offset
			lab._store_current_stance_elbow_poles()
		&"hand_target":
			var delta := delta_degrees * 0.0015
			if lab.selected_body_joint == &"left_hand":
				lab.left_grip_local_pos += delta
				lab.left_grip_local_pos = lab.left_grip_local_pos.clamp(Vector3(-0.40, -0.20, -0.20), Vector3(1.20, 0.20, 0.20))
			else:
				lab.right_grip_local_pos += delta
				lab.right_grip_local_pos = lab.right_grip_local_pos.clamp(Vector3(-1.50, -1.50, -1.50), Vector3(1.50, 1.50, 1.50))
			lab._sync_markers()
		_:
			lab._apply_joint_chain_delta(lab.selected_body_joint, delta_degrees)
	lab._sync_body_joint_controls()


static func _set_body_joint_component(lab: Node,value: float, axis: StringName) -> void:
	if lab.runtime_posture_layer == null:
		return
	var mode: StringName = JointControlSchema.control_mode(lab.selected_body_joint)
	if mode == &"elbow_pole":
		var side: StringName = &"right" if lab.selected_body_joint == &"right_forearm" else &"left"
		lab._set_elbow_component(value, side, axis)
		lab._sync_body_joint_controls()
		return
	if mode == &"hand_target":
		var target: Vector3 = lab.left_grip_local_pos if lab.selected_body_joint == &"left_hand" else lab.right_grip_local_pos
		match axis:
			&"x": target.x = value
			&"y": target.y = value
			&"z": target.z = value
		if lab.selected_body_joint == &"left_hand":
			lab.left_grip_local_pos = target
		else:
			lab.right_grip_local_pos = target
		lab._sync_markers()
		lab._sync_body_joint_controls()
		return
	var rotation: Vector3 = lab.runtime_posture_layer.get_procedural_rotation_degrees(lab.preview_posture, lab.selected_body_joint)
	match axis:
		&"x":
			lab._apply_joint_chain_delta(lab.selected_body_joint, Vector3(value - rotation.x, 0.0, 0.0))
		&"y":
			lab._apply_joint_chain_delta(lab.selected_body_joint, Vector3(0.0, value - rotation.y, 0.0))
		&"z":
			lab._apply_joint_chain_delta(lab.selected_body_joint, Vector3(0.0, 0.0, value - rotation.z))
	lab._sync_body_joint_controls()


static func _apply_joint_chain_delta(lab: Node,joint_name: StringName, delta_degrees: Vector3) -> void:
	var rotation: Vector3 = lab.runtime_posture_layer.get_procedural_rotation_degrees(lab.preview_posture, joint_name)
	lab.runtime_posture_layer.set_procedural_rotation_degrees(
		lab.preview_posture,
		joint_name,
		rotation + delta_degrees
	)
	var links: Dictionary = JOINT_CHAIN_LINKS.get(joint_name, {})
	for linked_joint: StringName in links:
		var linked_rotation: Vector3 = lab.runtime_posture_layer.get_procedural_rotation_degrees(
			lab.preview_posture,
			linked_joint
		)
		lab.runtime_posture_layer.set_procedural_rotation_degrees(
			lab.preview_posture,
			linked_joint,
			linked_rotation + delta_degrees * float(links[linked_joint])
		)


static func _sync_body_joint_controls(lab: Node) -> void:
	if lab.runtime_posture_layer == null:
		return
	var mode: StringName = JointControlSchema.control_mode(lab.selected_body_joint)
	var values := Vector3.ZERO
	var maximums := Vector3(55.0, 55.0, 55.0)
	if mode == &"elbow_pole":
		values = lab.right_elbow_pole_offset if lab.selected_body_joint == &"right_forearm" else lab.left_elbow_pole_offset
		maximums = Vector3(0.30, 0.30, 0.30)
	elif mode == &"hand_target":
		values = lab.left_grip_local_pos if lab.selected_body_joint == &"left_hand" else lab.right_grip_local_pos
		maximums = Vector3(1.20, 0.20, 0.20) if lab.selected_body_joint == &"left_hand" else Vector3(1.50, 1.50, 1.50)
	else:
		values = lab.runtime_posture_layer.get_procedural_rotation_degrees(lab.preview_posture, lab.selected_body_joint)
		maximums = lab.runtime_posture_layer.get_procedural_axis_limits_degrees(lab.selected_body_joint)
	var keys := ["body_joint_pitch", "body_joint_yaw", "body_joint_roll"]
	var labels: PackedStringArray = JointControlSchema.axis_labels(lab.selected_body_joint)
	for index in range(3):
		var entry: Dictionary = lab.sliders_map.get(keys[index], {})
		var slider := entry.get("slider") as HSlider
		var name_label := entry.get("name_label") as Label
		if slider:
			slider.min_value = -maximums[index]
			slider.max_value = maximums[index]
			slider.step = 0.005 if maximums[index] <= 2.0 else 0.5
			slider.set_value_no_signal(values[index])
		if name_label:
			name_label.text = labels[index] + ":"
		lab._update_slider_value(keys[index], values[index])
	if lab.selected_joint_title:
		lab.selected_joint_title.text = "SELECTED JOINT — %s" % JointControlSchema.display_name(lab.selected_body_joint).to_upper()
	if lab.selected_joint_help:
		lab.selected_joint_help.text = JointControlSchema.help_text(lab.selected_body_joint)
	if lab.hud_status:
		lab.hud_status.text = "%s — %s" % [JointControlSchema.display_name(lab.selected_body_joint), JointControlSchema.help_text(lab.selected_body_joint)]


static func _bone_world_origin(lab: Node,bone_index: int) -> Vector3:
	if not lab.skeleton or bone_index < 0:
		return Vector3.ZERO
	return (lab.skeleton.global_transform * lab.skeleton.get_bone_global_pose(bone_index)).origin


static func _update_elbow_pole_visuals(lab: Node) -> void:
	if not lab.skeleton or not lab.right_elbow_pole_marker or not lab.left_elbow_pole_marker:
		return
	var right_pole: Vector3 = lab._right_elbow_pole_world(lab._right_palm_contact_world())
	var left_pole: Vector3 = lab._left_elbow_pole_world(lab._left_palm_contact_world())
	lab.right_elbow_pole_marker.global_position = right_pole
	lab.left_elbow_pole_marker.global_position = left_pole
	lab.joint_debug_mesh.clear_surfaces()
	lab.joint_debug_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	lab._add_debug_segment(lab._bone_world_origin(lab.right_arm_idx), lab._bone_world_origin(lab.right_forearm_idx), Color(0.1, 0.95, 1.0))
	lab._add_debug_segment(lab._bone_world_origin(lab.right_forearm_idx), lab._bone_world_origin(lab.right_hand_idx), Color(0.1, 0.95, 1.0))
	lab._add_debug_segment(lab._bone_world_origin(lab.right_arm_idx), right_pole, Color(1.0, 0.25, 0.9))
	lab._add_debug_segment(lab._bone_world_origin(lab.left_arm_idx), lab._bone_world_origin(lab.left_forearm_idx), Color(0.1, 0.95, 1.0))
	lab._add_debug_segment(lab._bone_world_origin(lab.left_forearm_idx), lab._bone_world_origin(lab.left_hand_idx), Color(0.1, 0.95, 1.0))
	lab._add_debug_segment(lab._bone_world_origin(lab.left_arm_idx), left_pole, Color(0.75, 0.35, 1.0))
	lab.joint_debug_mesh.surface_end()


static func _add_debug_segment(lab: Node,from: Vector3, to: Vector3, color: Color) -> void:
	lab.joint_debug_mesh.surface_set_color(color)
	lab.joint_debug_mesh.surface_add_vertex(from)
	lab.joint_debug_mesh.surface_set_color(color)
	lab.joint_debug_mesh.surface_add_vertex(to)
