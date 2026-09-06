extends RefCounted

# Synchronous visual aim/trigger-arm calculations; no independent frame owner.
const SocketIK := preload("res://scripts/player/operator_weapon_socket_ik.gd")

static func _solve_pistol_trigger_hand_centerline(pose: Node3D, 
	aim_direction: Vector3,
	ready_weight: float = 1.0
) -> void:
	pose.pistol_trigger_centerline_ik_active = false
	pose.pistol_trigger_centerline_shift_m = 0.0
	if (
		pose.skeleton == null
		or pose.right_hand_ik == null
		or pose.trigger_hand_target == null
		or pose.right_elbow_pole == null
	):
		return
	var right_arm_index := int(pose.bone_indices.get(&"mixamorig_RightArm", -1))
	var left_arm_index := int(pose.bone_indices.get(&"mixamorig_LeftArm", -1))
	if right_arm_index < 0 or left_arm_index < 0:
		return
	pose.skeleton.force_update_all_bone_transforms()
	var right_shoulder: Vector3 = pose._bone_world_position(&"mixamorig_RightArm")
	var left_shoulder: Vector3 = pose._bone_world_position(&"mixamorig_LeftArm")
	var shoulder_width: float = right_shoulder.distance_to(left_shoulder)
	if shoulder_width <= 0.05:
		return
	var flat_aim := Vector3(aim_direction.x, 0.0, aim_direction.z).normalized()
	if flat_aim.length_squared() < 0.50:
		return
	var aim_right := flat_aim.cross(Vector3.UP).normalized()
	var shoulder_center: Vector3 = (right_shoulder + left_shoulder) * 0.5
	var palm_world: Transform3D = pose._right_hand_grip_world_transform()
	var current_lateral: float = (palm_world.origin - shoulder_center).dot(aim_right)
	var target_lateral: float = shoulder_width * pose.PISTOL_TRIGGER_CENTERLINE_RATIO
	var solve_weight: float = clampf(ready_weight, 0.0, 1.0)
	var requested_shift := clampf(
		target_lateral - current_lateral,
		-pose.PISTOL_CENTERLINE_MAX_SHIFT_M,
		pose.PISTOL_CENTERLINE_MAX_SHIFT_M
	) * solve_weight
	pose.trigger_hand_target.global_transform = Transform3D(
		palm_world.basis,
		palm_world.origin + aim_right * requested_shift
	)
	var saved_poles: Dictionary = pose.elbow_pole_offsets_by_posture.get(
		pose.last_posture,
		{}
	)
	var saved_right: Vector3 = saved_poles.get("right", Vector3.ZERO)
	var r_forearm_index := int(pose.bone_indices.get(&"mixamorig_RightForeArm", -1))
	var r_hand_index := int(pose.bone_indices.get(&"mixamorig_RightHand", -1))
	var r_hand_pos: Vector3 = (
		pose.skeleton.global_transform * pose.skeleton.get_bone_global_pose(r_hand_index).origin
		if r_hand_index >= 0
		else palm_world.origin
	)
	var natural_elbow: Vector3 = (
		pose._bone_world_position(&"mixamorig_RightForeArm")
		if r_forearm_index >= 0
		else right_shoulder.lerp(r_hand_pos, 0.5)
	)
	var arm_mid: Vector3 = (right_shoulder + r_hand_pos) * 0.5
	var natural_dir: Vector3 = (natural_elbow - arm_mid).normalized()
	if natural_dir.dot(aim_right) < 0.2:
		natural_dir = (natural_dir - aim_right * natural_dir.dot(aim_right) + aim_right * 0.6).normalized()
	pose.right_elbow_pole.global_position = natural_elbow + natural_dir * (0.45 * solve_weight)
	pose.trigger_hand_grip_locked = true
	# Keep the authored trigger-wrist orientation while relocating the palm.
	# Otherwise SkeletonIK3D lets the hand inherit the solved forearm rotation,
	# forcing the rigid pistol correction beyond its calibrated safe limit.
	pose.right_hand_ik.override_tip_basis = true
	var original_max_iterations: int = pose.right_hand_ik.max_iterations
	pose.right_hand_ik.max_iterations = mini(original_max_iterations, 20)
	# Fade the target and elbow guidance toward the authored frame before solving.
	# This preserves exact palm contact while avoiding residual iterations pulling
	# a partially weighted IK result toward the full centerline target.
	SocketIK.solve(
		pose.skeleton,
		pose.bone_indices,
		pose.right_hand_ik,
		pose.trigger_hand_target,
		pose.right_elbow_pole,
		&"mixamorig_RightHand",
		pose.right_palm_anchor_local,
		true,
		1.0,
		3
	)
	pose.right_hand_ik.max_iterations = original_max_iterations
	pose.skeleton.force_update_all_bone_transforms()
	var solved_palm: Vector3 = pose._right_hand_grip_world_transform().origin
	pose.pistol_trigger_centerline_shift_m = solved_palm.distance_to(palm_world.origin)
	# start(true) is intentionally a one-shot solve, so is_running() is false once
	# the result has been applied. This flag records that this frame used the
	# bounded pistol-only modifier; no continuously running IK owner remains.
	pose.pistol_trigger_centerline_ik_active = true


static func _align_weapon_to_aim(pose: Node3D, 
	aim_direction: Vector3,
	alignment_weight: float = -1.0,
	align_hand_owned_weapon_root: bool = false
) -> void:
	if pose.weapon_node == null:
		pose.weapon_aim_error_deg = 0.0
		pose.wrist_correction_deg = 0.0
		return
	var hand_index := int(pose.bone_indices.get(&"mixamorig_RightHand", -1))
	if hand_index < 0:
		return
	pose.skeleton.force_update_all_bone_transforms()
	var hand_pose: Transform3D = pose.skeleton.get_bone_global_pose(hand_index)
	var inverse_skeleton_basis: Basis = pose.skeleton.global_basis.inverse()
	# Use the physical barrel sockets, not a guessed mesh axis. Pistol meshes and
	# rifle meshes use different imported axes, while this socket ray is the exact
	# visible bore consumed by gameplay diagnostics and camera-lab overlays.
	var barrel_origin: Vector3 = (
		pose.barrel_base_socket.global_position
		if pose.barrel_base_socket != null
		else (pose.trigger_socket.global_position if pose.trigger_socket != null else pose.weapon_node.global_position)
	)
	var current_world: Vector3 = (
		(pose.muzzle_socket.global_position - barrel_origin).normalized()
		if pose.muzzle_socket != null
		else Vector3.ZERO
	)
	var current_local: Vector3 = (inverse_skeleton_basis * current_world).normalized()
	var aim_local: Vector3 = (inverse_skeleton_basis * aim_direction).normalized()
	if current_local.length_squared() < 0.50 or aim_local.length_squared() < 0.50:
		return
	var current_up_world := Vector3.ZERO
	var target_up_world := Vector3.ZERO
	var full_delta := Quaternion(current_local, aim_local).normalized()
	if align_hand_owned_weapon_root:
		# Axial optic-up alignment belongs only to the pistol presentation anchor.
		# Rifle and long-gun socket solvers retain their established bore-only wrist
		# behavior and buttstock/shoulder contract.
		current_up_world = _weapon_optic_up_world(pose, barrel_origin, current_world)
		target_up_world = pose.skeleton.global_basis.y.normalized()
		var current_up_local: Vector3 = (inverse_skeleton_basis * current_up_world).normalized()
		var target_up_local: Vector3 = (inverse_skeleton_basis * target_up_world).normalized()
		full_delta = _aim_frame_alignment_delta(pose, 
			current_local,
			aim_local,
			current_up_local,
			target_up_local
		)
	var required_angle := full_delta.get_angle()
	pose.wrist_correction_deg = rad_to_deg(required_angle)
	# The shoulder and elbow solve position first; the wrist then aligns the
	# attached rifle. Clamp only the visual wrist contribution. Any residual is
	# reported as torso-assist demand instead of allowing an impossible joint.
	var applied_angle := minf(required_angle, deg_to_rad(pose.maximum_wrist_correction_deg))
	var correction_weight := (
		0.0 if required_angle <= 0.00001 else applied_angle / required_angle
	)
	var delta := Quaternion.IDENTITY.slerp(full_delta, correction_weight)
	var solve_weight: float = (
		pose.current_weight if alignment_weight < 0.0 else clampf(alignment_weight, 0.0, 1.0)
	)
	hand_pose.basis = pose._blend_rotated_basis(hand_pose.basis, delta, solve_weight)
	pose.skeleton.set_bone_global_pose_override(hand_index, hand_pose, 1.0, true)
	pose.skeleton.force_update_all_bone_transforms()
	if align_hand_owned_weapon_root and pose.weapon_presentation_owner != null:
		# Pistol aim/fire uses the existing WeaponSolverAnchor so BoneAttachment3D
		# cannot resample this post-animation result. Rotate through the sole weapon
		# mutation boundary, then pivot back onto the physical trigger contact. The
		# full arm/socket solver that previously folded pistol shoulders stays off.
		var world_delta := _aim_frame_alignment_delta(pose, 
			current_world,
			aim_direction,
			current_up_world,
			target_up_world
		)
		var applied_world_delta := Quaternion.IDENTITY.slerp(
			world_delta,
			correction_weight * solve_weight
		).normalized()
		var world_scale: Vector3 = pose.weapon_node.global_basis.get_scale()
		pose.weapon_presentation_owner.set_world_basis((
			Basis(applied_world_delta) * pose.weapon_node.global_basis.orthonormalized()
		).orthonormalized().scaled(world_scale))
		if pose.trigger_socket != null:
			pose.weapon_presentation_owner.translate_world(
				pose._right_hand_grip_world_transform().origin - pose.trigger_socket.global_position
			)
	var solved_world: Vector3 = (
		(pose.muzzle_socket.global_position - (
			pose.barrel_base_socket.global_position
			if pose.barrel_base_socket != null
			else pose.trigger_socket.global_position
		)).normalized()
		if pose.muzzle_socket != null and (pose.barrel_base_socket != null or pose.trigger_socket != null)
		else Vector3.ZERO
	)
	pose.weapon_aim_error_deg = (
		rad_to_deg(solved_world.angle_to(aim_direction))
		if solved_world.length_squared() > 0.50
		else 0.0
	)
	if pose.weapon_aim_error_deg > 1.0:
		pose.torso_assist_requested = true


static func _align_hand_owned_weapon_root_to_aim(pose: Node3D, 
	aim_direction: Vector3,
	ready_weight: float = 1.0
) -> void:
	if (
		pose.weapon_node == null
		or pose.weapon_presentation_owner == null
		or pose.muzzle_socket == null
		or (pose.barrel_base_socket == null and pose.trigger_socket == null)
	):
		return
	var barrel_origin: Vector3 = (
		pose.barrel_base_socket.global_position
		if pose.barrel_base_socket != null
		else pose.trigger_socket.global_position
	)
	var current: Vector3 = (pose.muzzle_socket.global_position - barrel_origin).normalized()
	var target := aim_direction.normalized()
	if current.length_squared() < 0.50 or target.length_squared() < 0.50:
		return
	var current_up: Vector3 = _weapon_optic_up_world(pose, barrel_origin, current)
	var target_up: Vector3 = pose.skeleton.global_basis.y.normalized()
	var full_correction := _aim_frame_alignment_delta(pose, 
		current,
		target,
		current_up,
		target_up
	)
	var error := full_correction.get_angle()
	# This diagnostic retains its historical name, but for animation-owned
	# pistols it is the bounded rigid weapon-root correction. No wrist bone is
	# written by this path.
	pose.wrist_correction_deg = rad_to_deg(error)
	var applied := minf(error, deg_to_rad(pose.maximum_wrist_correction_deg))
	var amount := 0.0 if error <= 0.00001 else applied / error
	var correction := Quaternion.IDENTITY.slerp(
		full_correction,
		amount * clampf(ready_weight, 0.0, 1.0)
	).normalized()
	var world_scale: Vector3 = pose.weapon_node.global_basis.get_scale()
	pose.weapon_presentation_owner.set_world_basis((
		Basis(correction) * pose.weapon_node.global_basis.orthonormalized()
	).orthonormalized().scaled(world_scale))
	if pose.trigger_socket != null:
		pose.weapon_presentation_owner.translate_world(
			pose._right_hand_grip_world_transform().origin - pose.trigger_socket.global_position
		)
	barrel_origin = (
		pose.barrel_base_socket.global_position
		if pose.barrel_base_socket != null
		else pose.trigger_socket.global_position
	)
	var solved: Vector3 = (pose.muzzle_socket.global_position - barrel_origin).normalized()
	pose.weapon_aim_error_deg = rad_to_deg(solved.angle_to(target))


static func _weapon_optic_up_world(pose: Node3D, barrel_origin: Vector3, barrel_direction: Vector3) -> Vector3:
	var up := Vector3.ZERO
	if pose.optic_socket != null:
		up = pose.optic_socket.global_position - barrel_origin
		up -= barrel_direction * up.dot(barrel_direction)
	if up.length_squared() < 0.0000000001:
		up = pose.skeleton.global_basis.y
		up -= barrel_direction * up.dot(barrel_direction)
	return up.normalized()


static func _aim_frame_alignment_delta(pose: Node3D, 
	current_forward: Vector3,
	target_forward: Vector3,
	current_up: Vector3,
	target_up: Vector3
) -> Quaternion:
	var source_forward := current_forward.normalized()
	var destination_forward := target_forward.normalized()
	if (
		source_forward.length_squared() < 0.50
		or destination_forward.length_squared() < 0.50
	):
		return Quaternion.IDENTITY
	var aim_delta := Quaternion(
		source_forward,
		destination_forward
	).normalized()
	var aligned_up := aim_delta * current_up.normalized()
	aligned_up -= destination_forward * aligned_up.dot(destination_forward)
	var desired_up := target_up.normalized()
	desired_up -= destination_forward * desired_up.dot(destination_forward)
	if aligned_up.length_squared() < 0.000001 or desired_up.length_squared() < 0.000001:
		return aim_delta
	aligned_up = aligned_up.normalized()
	desired_up = desired_up.normalized()
	var roll_angle := atan2(
		destination_forward.dot(aligned_up.cross(desired_up)),
		aligned_up.dot(desired_up)
	)
	return (Quaternion(destination_forward, roll_angle) * aim_delta).normalized()

static func _update_socket_weapon_error(pose: Node3D) -> void:
	if pose.muzzle_socket == null or (pose.barrel_base_socket == null and pose.trigger_socket == null):
		return
	var barrel_origin: Vector3 = (
		pose.barrel_base_socket.global_position
		if pose.barrel_base_socket != null
		else pose.trigger_socket.global_position
	)
	var barrel_direction: Vector3 = (pose.muzzle_socket.global_position - barrel_origin).normalized()
	if barrel_direction.length_squared() < 0.50:
		return
	pose.weapon_aim_error_deg = rad_to_deg(barrel_direction.angle_to(pose.last_aim_direction))
	pose.wrist_correction_deg = 0.0



static func _measure_gunsmith_weapon_roll_error(pose: Node3D, 
	barrel_direction: Vector3,
	desired_roll_degrees: float
) -> float:
	if (
		pose.weapon_node == null
		or pose.skeleton == null
		or pose.optic_socket == null
		or pose.muzzle_socket == null
	):
		return 0.0
	var direction := barrel_direction.normalized()
	if direction.length_squared() < 0.50:
		return 0.0
	var barrel_origin: Vector3 = (
		pose.barrel_base_socket.global_position
		if pose.barrel_base_socket != null
		else pose.trigger_socket.global_position
	)
	# Optic-above-barrel is a model-independent weapon-up reference. Unlike a
	# mesh axis, it survives FBX axis conversion and the saved grip transform.
	var actual_up: Vector3 = pose.optic_socket.global_position - barrel_origin
	actual_up -= direction * actual_up.dot(direction)
	var desired_up: Vector3 = pose.skeleton.global_basis.y.normalized()
	desired_up -= direction * desired_up.dot(direction)
	if actual_up.length_squared() < 0.000001 or desired_up.length_squared() < 0.000001:
		return 0.0
	actual_up = actual_up.normalized()
	desired_up = desired_up.normalized()
	if not is_zero_approx(desired_roll_degrees):
		desired_up = Quaternion(
			direction,
			deg_to_rad(desired_roll_degrees)
		) * desired_up
	return atan2(
		direction.dot(actual_up.cross(desired_up)),
		actual_up.dot(desired_up)
	)
