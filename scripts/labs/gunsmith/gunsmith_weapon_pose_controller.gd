extends RefCounted

const WeaponOwnershipContract := preload("res://scripts/player/weapon_ownership_contract.gd")
const MIN_BARREL_AXIS_LENGTH_METERS := 0.02
const MAX_GRIP_OFFSET_RADIUS_METERS := 0.75
const MAX_HAND_TO_GRIP_ERROR_METERS := 0.40

static func _get_right_hand_world_transform(lab: Node) -> Transform3D:
	var bone_index: int = lab._get_right_hand_bone_index()
	if bone_index < 0 or lab.skeleton == null:
		return lab.ba_right_hand.global_transform if lab.ba_right_hand else Transform3D.IDENTITY
	var skeleton_local_pose: Transform3D = lab.skeleton.get_bone_global_pose(bone_index)
	return lab.skeleton.global_transform * skeleton_local_pose


static func _weapon_anchor_world_transform(lab: Node) -> Transform3D:
	if lab.skeleton == null or lab.weapon_anchor_bone_idx < 0:
		return lab.skeleton.global_transform if lab.skeleton else Transform3D.IDENTITY
	return (
		lab.skeleton.global_transform
		* lab.skeleton.get_bone_global_pose(lab.weapon_anchor_bone_idx)
	)


static func _capture_weapon_anchor(lab: Node) -> void:
	if lab.weapon_root == null or lab.skeleton == null:
		return
	# Store rifle orientation in operator space. Store only the chest position
	# separately. This lets stance carry the rifle without inheriting a bent or
	# rolling torso bone's rotation.
	lab.weapon_anchor_local = lab.skeleton.global_transform.affine_inverse() * lab.weapon_root.global_transform
	lab.weapon_anchor_bone_origin = (
		lab.skeleton.get_bone_global_pose(lab.weapon_anchor_bone_idx).origin
		if lab.weapon_anchor_bone_idx >= 0
		else Vector3.ZERO
	)
	lab.weapon_anchor_ready = true


static func _weapon_anchor_target_transform(lab: Node) -> Transform3D:
	if not lab.weapon_anchor_ready:
		return lab.weapon_root.global_transform if lab.weapon_root else Transform3D.IDENTITY
	var target_local: Transform3D = lab.weapon_anchor_local
	var current_anchor_origin: Vector3 = (
		lab.skeleton.get_bone_global_pose(lab.weapon_anchor_bone_idx).origin
		if lab.weapon_anchor_bone_idx >= 0
		else Vector3.ZERO
	)
	target_local.origin += current_anchor_origin - lab.weapon_anchor_bone_origin
	return lab.skeleton.global_transform * target_local


static func _update_weapon_master_anchor(lab: Node) -> void:
	if (
		lab.weapon_root == null
		or not lab.weapon_anchor_ready
		or not WeaponOwnershipContract.ready_solver_owns_weapon(lab.weapon_owner_state)
		or lab.action_weapon_follow_active
		or lab.action_recovery_elapsed < lab.action_recovery_duration
	):
		return
	# The chest-relative anchor carries the rifle with the operator. The weapon
	# remains the pose master; both arms solve to its authored grip sockets.
	lab.weapon_root.global_transform = lab._weapon_anchor_target_transform()


static func _gunsmith_live_aim_active(lab: Node) -> bool:
	return (
		lab.live_weapon_aim_enabled
		and lab.active_lab_tab_name != "Composure"
		and lab.weapon_master_pose_initialized
		and WeaponOwnershipContract.ready_solver_owns_weapon(lab.weapon_owner_state)
		and not lab.action_weapon_follow_active
		and not lab.is_reloading
		and not lab.authoring_pointer_down
		and lab.dragged_dot_id == ""
		and (lab.animation_frame_editor == null or not lab.animation_frame_editor.active)
	)


static func _update_live_aim_weapon_pose(lab: Node) -> void:
	lab.gunsmith_live_aim_rotation = Quaternion.IDENTITY
	if lab._gun_placement_line_match_active():
		lab._match_weapon_rail_to_blue_line()
		return
	if (
		not lab._gunsmith_live_aim_active()
		or lab.weapon_root == null
		or lab.right_grip_marker == null
		or lab.barrel_base_marker == null
		or lab.muzzle_marker == null
	):
		return
	var trigger_world: Vector3 = lab.right_grip_marker.global_position
	var current_direction: Vector3 = lab._barrel_direction_world()
	if current_direction.length_squared() < 0.50:
		return
	# Gunsmith aim preview is deliberately independent of the inspection camera.
	# Yaw turns around the operator's up axis; pitch follows the yawed weapon-right
	# axis. Both rotate the attached hand-and-rifle unit around the trigger grip.
	var up_axis: Vector3 = lab.skeleton.global_basis.y.normalized() if lab.skeleton != null else Vector3.UP
	var right_axis: Vector3 = current_direction.cross(up_axis).normalized()
	if right_axis.length_squared() < 0.50:
		right_axis = lab.weapon_root.global_basis.x.normalized()
	var yaw_delta := Quaternion(up_axis, deg_to_rad(lab.live_weapon_yaw_deg))
	var yawed_right_axis: Vector3 = (yaw_delta * right_axis).normalized()
	var pitch_delta := Quaternion(yawed_right_axis, deg_to_rad(lab.live_weapon_pitch_deg))
	var aim_delta := (pitch_delta * yaw_delta).normalized()
	lab.gunsmith_live_aim_rotation = aim_delta
	var world_scale: Vector3 = lab.weapon_root.global_basis.get_scale()
	lab.weapon_root.global_basis = (
		Basis(aim_delta) * lab.weapon_root.global_basis.orthonormalized()
	).orthonormalized().scaled(world_scale)
	lab.weapon_root.global_position += trigger_world - lab.right_grip_marker.global_position


static func _gun_placement_line_match_active(lab: Node) -> bool:
	return (
		lab.match_weapon_rail_to_blue_line
		and lab.show_eye_sight
		and lab.active_lab_tab_name == "Reticle & Fire"
		and lab.weapon_master_pose_initialized
		and WeaponOwnershipContract.ready_solver_owns_weapon(lab.weapon_owner_state)
		and not lab.action_weapon_follow_active
		and not lab.is_reloading
		and not lab.authoring_pointer_down
		and lab.dragged_dot_id == ""
		and (lab.animation_frame_editor == null or not lab.animation_frame_editor.active)
	)


static func _match_weapon_rail_to_blue_line(lab: Node) -> bool:
	if (
		lab.weapon_root == null
		or lab.optic_marker == null
		or lab.barrel_base_marker == null
		or lab.muzzle_marker == null
		or lab.eye_sight_marker == null
	):
		return false
	var current_direction: Vector3 = lab._barrel_direction_world()
	var target_direction: Vector3 = lab._eye_sight_direction_world()
	if current_direction.length_squared() < 0.50 or target_direction.length_squared() < 0.50:
		return false
	var aim_delta := Quaternion(current_direction, target_direction).normalized()
	lab.gunsmith_live_aim_rotation = aim_delta
	var world_scale: Vector3 = lab.weapon_root.global_basis.get_scale()
	lab.weapon_root.global_basis = (
		Basis(aim_delta) * lab.weapon_root.global_basis.orthonormalized()
	).orthonormalized().scaled(world_scale)
	# The optic is attached to the gun. Translate the whole weapon after the
	# rotation so the saved rail point lands exactly on the blue line origin.
	lab.weapon_root.global_position += (
		lab.eye_sight_marker.global_position - lab.optic_marker.global_position
	)
	return true


static func _right_hand_pose_is_ready(lab: Node) -> bool:
	var bone_index: int = lab._get_right_hand_bone_index()
	if bone_index < 0 or lab.skeleton == null:
		return false
	var pose: Transform3D = lab.skeleton.get_bone_global_pose(bone_index)
	var rest: Transform3D = lab.skeleton.get_bone_global_rest(bone_index)
	if not pose.origin.is_finite():
		return false
	if absf(pose.basis.determinant()) < 0.0001:
		return false
	if pose.origin.length() < 0.05 and rest.origin.length() > 0.25:
		return false
	return true


static func _load_operator_mount(lab: Node,profile: Dictionary) -> void:
	var mount_value: Variant = profile.get("operator_mount", null)
	var inv_scale: float = 1.0 / lab.trooper_scale
	if typeof(mount_value) != TYPE_DICTIONARY:
		var mount_basis := Basis.from_euler(Vector3(deg_to_rad(-90.0), deg_to_rad(180.0), 0.0)).scaled(Vector3.ONE * inv_scale)
		lab.weapon_mount_local = Transform3D(mount_basis, Vector3(-0.02, 0.08, 0.05) * inv_scale)
		return
	var mount: Dictionary = mount_value
	var fallback_rotation_degrees: Vector3 = lab._radians_to_degrees_vector(
		lab.weapon_mount_local.basis.orthonormalized().get_euler(EULER_ORDER_YXZ)
	)
	var mount_position: Vector3 = lab._dictionary_to_vector3(
		mount.get("position", {}),
		Vector3(-0.02, 0.08, 0.05)
	) * inv_scale
	var mount_rotation_degrees: Vector3 = lab._dictionary_to_vector3(
		mount.get("rotation_degrees", {}),
		fallback_rotation_degrees
	)
	var mount_rotation_radians: Vector3 = lab._degrees_to_radians_vector(mount_rotation_degrees)
	var mount_basis := Basis.from_euler(mount_rotation_radians, EULER_ORDER_YXZ).scaled(Vector3.ONE * inv_scale)
	lab.weapon_mount_local = Transform3D(
		mount_basis,
		mount_position
	)


static func _dictionary_to_vector3(lab: Node,value: Variant, fallback: Vector3) -> Vector3:
	if typeof(value) != TYPE_DICTIONARY:
		return fallback
	var data: Dictionary = value
	return Vector3(
		float(data.get("x", fallback.x)),
		float(data.get("y", fallback.y)),
		float(data.get("z", fallback.z))
	)


static func _vector3_to_dictionary(lab: Node,v: Vector3) -> Dictionary:
	return {"x": v.x, "y": v.y, "z": v.z}


static func _degrees_to_radians_vector(lab: Node,value: Vector3) -> Vector3:
	return Vector3(deg_to_rad(value.x), deg_to_rad(value.y), deg_to_rad(value.z))


static func _radians_to_degrees_vector(lab: Node,value: Vector3) -> Vector3:
	return Vector3(rad_to_deg(value.x), rad_to_deg(value.y), rad_to_deg(value.z))


static func _world_drag_to_parent_local_delta(lab: Node,parent_node: Node3D, world_start: Vector3, world_current: Vector3) -> Vector3:
	if parent_node == null:
		return world_current - world_start
	var parent_inverse: Transform3D = parent_node.global_transform.affine_inverse()
	var local_start: Vector3 = parent_inverse * world_start
	var local_current: Vector3 = parent_inverse * world_current
	return local_current - local_start


static func _show_rig_error(lab: Node,msg: String) -> void:
	push_warning(msg)
	if lab.hud_status:
		lab.hud_status.text = "⚠️ " + msg
		lab.hud_status.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))


static func _validate_weapon_rig_before_save(lab: Node) -> bool:
	if not lab.weapon_master_pose_initialized:
		lab._show_rig_error("The weapon pose has not finished initializing. Save blocked.")
		return false
	var serialized_grip_position: Vector3 = lab.auto_grip_center_offset + lab.grip_offset_pos
	if not serialized_grip_position.is_finite():
		lab._show_rig_error("Grip offset contains a non-finite value. Save blocked.")
		return false
	if serialized_grip_position.length() > MAX_GRIP_OFFSET_RADIUS_METERS:
		lab._show_rig_error("Grip offset is outside safe local range (%.2fm > %.2fm). Save blocked." % [serialized_grip_position.length(), MAX_GRIP_OFFSET_RADIUS_METERS])
		return false
	var hand_world: Transform3D = lab._get_right_hand_world_transform()
	var grip_target_world: Vector3 = (
		lab.right_grip_marker.global_position
		if lab.right_grip_marker
		else (lab.weapon_pivot.global_transform * lab.right_grip_local_pos if lab.weapon_pivot else Vector3.ZERO)
	)
	var hand_to_grip_error: float = hand_world.origin.distance_to(grip_target_world)
	if hand_to_grip_error > MAX_HAND_TO_GRIP_ERROR_METERS:
		lab._show_rig_error("Right-hand grip target is detached by %.3fm (max %.2fm). Save blocked." % [hand_to_grip_error, MAX_HAND_TO_GRIP_ERROR_METERS])
		return false
	if not lab.muzzle_local_pos.is_finite() or not lab.barrel_base_local_pos.is_finite():
		lab._show_rig_error("Muzzle or barrel-base socket contains a non-finite value. Save blocked.")
		return false
	var barrel_axis_length: float = lab.muzzle_local_pos.distance_to(lab.barrel_base_local_pos)
	if barrel_axis_length < MIN_BARREL_AXIS_LENGTH_METERS:
		lab._show_rig_error(
			"Muzzle must stay at least %.2fm from the barrel-base socket. Save blocked."
			% MIN_BARREL_AXIS_LENGTH_METERS
		)
		return false
	return true


static func _finish_weapon_bootstrap(lab: Node) -> void:
	if lab.animation_player != null:
		lab.animation_player.advance(0.0)
	await lab.get_tree().process_frame

	if not lab._right_hand_pose_is_ready():
		push_error("Gunsmith bootstrap aborted: right-hand pose was not valid.")
		return

	var hand_world: Transform3D = lab._get_right_hand_world_transform()
	if lab.weapon_root:
		lab.weapon_root.global_transform = hand_world * lab.weapon_mount_local
		lab._capture_weapon_anchor()

	lab.weapon_master_pose_initialized = true

	lab._sync_weapon_transform(false)
	lab._sync_markers()
	lab._register_interactive_dots()

	if lab.left_hand_ik and lab.left_grip_marker:
		lab.left_hand_ik.target_node = NodePath()

	lab._set_weapon_ik_enabled(true)
	lab._set_save_enabled(true)
	if lab.hud_status:
		lab.hud_status.text = "Ready! (Biomechanical Engine Active | Drag Blue Dot to place hand | Space to Fire)"
		lab.hud_status.add_theme_color_override("font_color", Color(0.4, 1.0, 0.4))
