class_name GunsmithContactGraphController
extends RefCounted

const ContactGraph := preload(
	"res://scripts/weapons/weapon_contact_graph_contract.gd"
)

const TARGET_LABELS := {
	"right_shoulder": "Right Shoulder",
	"trigger_hand": "Trigger Hand",
	"support_hand": "Support Hand",
	"spine_aim": "Spine Aim",
}

const TARGET_COLORS := {
	"right_shoulder": Color(1.0, 0.18, 0.18),
	"trigger_hand": Color(0.2, 1.0, 0.3),
	"support_hand": Color(0.1, 0.75, 1.0),
	"spine_aim": Color(1.0, 0.75, 0.15),
}


static func setup(lab: Node) -> void:
	if lab.weapon_contact_target_pivot != null and is_instance_valid(lab.weapon_contact_target_pivot):
		lab.weapon_contact_target_pivot.free()
	lab.weapon_contact_targets.clear()
	lab.weapon_contact_base_transforms.clear()
	lab.weapon_contact_target_pivot = Marker3D.new()
	lab.weapon_contact_target_pivot.name = "TargetPivot"
	lab.add_child(lab.weapon_contact_target_pivot)
	var pivot_world := _bone_world_transform(lab, lab.weapon_anchor_bone_idx)
	lab.weapon_contact_target_pivot.global_transform = Transform3D(
		lab.skeleton.global_basis.orthonormalized(),
		pivot_world.origin
	)
	for target_id in ContactGraph.TARGET_IDS:
		var marker: MeshInstance3D = lab._create_marker(
			TARGET_COLORS[target_id],
			_node_name(target_id),
			0.022
		)
		lab.weapon_contact_target_pivot.add_child(marker)
		var base_world := _target_base_world(lab, target_id)
		var base_local: Transform3D = lab.weapon_contact_target_pivot.global_transform.affine_inverse() * base_world
		lab.weapon_contact_base_transforms[target_id] = base_local
		lab.weapon_contact_targets[target_id] = marker
	sync(lab)
	lab._register_interactive_dots()


static func load_profile(lab: Node, raw: Variant) -> void:
	lab.weapon_contact_graph_profile = ContactGraph.parse(raw)
	if lab.weapon_contact_target_pivot != null:
		sync(lab)


static func save_data(lab: Node) -> Dictionary:
	return ContactGraph.parse(lab.weapon_contact_graph_profile)


static func sync(lab: Node) -> void:
	for target_id in ContactGraph.TARGET_IDS:
		var marker: MeshInstance3D = lab.weapon_contact_targets.get(target_id)
		if marker == null:
			continue
		var base: Transform3D = lab.weapon_contact_base_transforms.get(
			target_id,
			Transform3D.IDENTITY
		)
		marker.transform = ContactGraph.apply_offset(
			base,
			lab.weapon_contact_graph_profile,
			target_id
		)
	refresh_controls(lab)


static func apply_world_drag(lab: Node, target_id: String, world_position: Vector3) -> void:
	if not lab.weapon_contact_base_transforms.has(target_id):
		return
	var base: Transform3D = lab.weapon_contact_base_transforms[target_id]
	var requested_local: Vector3 = lab.weapon_contact_target_pivot.to_local(world_position)
	var local_delta := base.basis.orthonormalized().inverse() * (requested_local - base.origin)
	ContactGraph.set_target_position_offset(
		lab.weapon_contact_graph_profile,
		target_id,
		local_delta.clamp(Vector3.ONE * -0.35, Vector3.ONE * 0.35)
	)
	lab.selected_weapon_contact_target = target_id
	sync(lab)


static func set_selected_target(lab: Node, target_id: String) -> void:
	if target_id not in ContactGraph.TARGET_IDS:
		return
	lab.selected_weapon_contact_target = target_id
	refresh_controls(lab)


static func set_selected_component(
	lab: Node,
	kind: String,
	axis: int,
	value: float
) -> void:
	var target_id: String = lab.selected_weapon_contact_target
	if kind == "position":
		var position := ContactGraph.target_position_offset(
			lab.weapon_contact_graph_profile,
			target_id
		)
		position[axis] = value
		ContactGraph.set_target_position_offset(
			lab.weapon_contact_graph_profile,
			target_id,
			position
		)
	else:
		var rotation := ContactGraph.target_rotation_offset_degrees(
			lab.weapon_contact_graph_profile,
			target_id
		)
		rotation[axis] = value
		ContactGraph.set_target_rotation_offset_degrees(
			lab.weapon_contact_graph_profile,
			target_id,
			rotation
		)
	sync(lab)


static func refresh_controls(lab: Node) -> void:
	var target_id: String = lab.selected_weapon_contact_target
	var position := ContactGraph.target_position_offset(
		lab.weapon_contact_graph_profile,
		target_id
	)
	var rotation := ContactGraph.target_rotation_offset_degrees(
		lab.weapon_contact_graph_profile,
		target_id
	)
	for entry in [
		["cg_pos_x", position.x], ["cg_pos_y", position.y], ["cg_pos_z", position.z],
		["cg_rot_x", rotation.x], ["cg_rot_y", rotation.y], ["cg_rot_z", rotation.z],
	]:
		lab._update_slider_value(entry[0], entry[1])


static func _target_base_world(lab: Node, target_id: String) -> Transform3D:
	match target_id:
		"right_shoulder":
			return _bone_world_transform(lab, lab.right_arm_idx)
		"trigger_hand":
			return _bone_world_transform(lab, lab.right_hand_idx)
		"support_hand":
			if lab.left_grip_marker != null:
				return lab.left_grip_marker.global_transform
			return _bone_world_transform(lab, lab.left_hand_idx)
		"spine_aim":
			return _bone_world_transform(lab, lab.weapon_anchor_bone_idx)
	return lab.skeleton.global_transform


static func _bone_world_transform(lab: Node, bone_index: int) -> Transform3D:
	if lab.skeleton == null or bone_index < 0:
		return lab.global_transform
	return lab.skeleton.global_transform * lab.skeleton.get_bone_global_pose(bone_index)


static func _node_name(target_id: String) -> String:
	match target_id:
		"right_shoulder": return "RHUpperArmWeaponTarget"
		"trigger_hand": return "RHWeaponTarget"
		"support_hand": return "LHWeaponContactTarget"
		"spine_aim": return "SpineTargetWeaponAim"
	return target_id
