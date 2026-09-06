extends RefCounted

# Authored action and hand-follow paths; the existing pose node retains state.
const WeaponOwnershipContract := preload("res://scripts/player/weapon_ownership_contract.gd")
const MobilityWeaponGripSolver := preload("res://scripts/player/operator_mobility_weapon_grip_solver.gd")
const SocketIK := preload("res://scripts/player/operator_weapon_socket_ik.gd")
const WeaponContactSolver := preload("res://scripts/player/operator_weapon_contact_solver.gd")
const PistolCarryReach := preload("res://scripts/player/operator_pistol_carry_reach.gd")

static func apply_action(pose: Node3D, reload_action_active: bool, reload_support_regrip: bool, posture: StringName, world_aim_target: Vector3, body: Node3D, delta: float) -> void:
	pose._release_trigger_hand_grip_lock()
	pose._release_support_hand_grip_lock()
	if reload_action_active:
		pose._attach_reload_weapon_to_right_hand()
	elif WeaponOwnershipContract.weapon_uses_action_follow(pose.weapon_owner):
		pose._update_action_weapon_follow(
			delta,
			WeaponOwnershipContract.uses_stable_chest_translation(pose.weapon_owner)
		)
		if pose.weapon_owner == WeaponOwnershipContract.MOBILITY_CHEST_CARRY:
			# The full-body take moves the torso and legs. The rifle stays inside a
			# stable chest carry, then both animated arms follow its saved sockets.
			var mobility_grip := MobilityWeaponGripSolver.solve(
				pose.skeleton, pose.weapon_node, pose.trigger_socket, pose.support_socket,
				pose.right_hand_ik, pose.left_hand_ik, pose.trigger_hand_target,
				pose.support_hand_target, pose.right_elbow_pole, pose.left_elbow_pole,
				body, pose.bone_indices, pose.right_palm_anchor_local,
				pose.left_palm_anchor_local, pose.mobility_hand_contact_limit_m,
				pose.minimum_forward_reach_ratio, pose.minimum_elbow_angle_deg,
				pose.maximum_elbow_angle_deg
			)
			pose.trigger_hand_grip_locked = bool(mobility_grip.get("applied", false))
			pose.support_hand_grip_locked = pose.trigger_hand_grip_locked
			pose.action_trigger_contact_error_m = float(
				mobility_grip.get("trigger_error_m", INF)
			)
			pose.action_support_contact_error_m = float(
				mobility_grip.get("support_error_m", INF)
			)
	if reload_action_active and pose.right_hand_ik and pose.right_hand_ik.is_running():
		pose.right_hand_ik.stop()
	if reload_action_active and reload_support_regrip and pose.support_socket != null:
		pose._solve_reload_support_arm_guardrail(
			posture,
			world_aim_target,
			body,
			pose.support_socket.global_position
		)
	elif reload_action_active:
		pose._solve_reload_support_arm_guardrail(posture, world_aim_target, body)
	elif pose.weapon_owner != WeaponOwnershipContract.MOBILITY_CHEST_CARRY:
		pose._stop_socket_ik()
	pose.right_elbow_angle_deg = pose._current_elbow_angle(&"right")
	pose.left_elbow_angle_deg = pose._current_elbow_angle(&"left")
	pose.current_weight = 0.0
	pose.desired_weight = 0.0
	return

static func apply_hand_follow(pose: Node3D, aim_yaw: float, aim_pitch: float, ready_weight: float, sampled_trigger_palm_position: Vector3, world_aim_target: Vector3, body: Node3D, delta: float, accepted_shot_aim_weight: float) -> void:
	# The authored pose and right-hand attachment keep sole ownership of the
	# spine and trigger arm. A separate bounded support-only pass may close the
	# left palm onto the physical foregrip without moving those owners. Pistol
	# ready/fire presentation temporarily uses the existing world-space weapon
	# anchor so BoneAttachment3D cannot resample away its reticle correction.
	var use_animation_aim_anchor: bool = (
		pose.animation_owned_aim_alignment_enabled and ready_weight > 0.001
	)
	if not use_animation_aim_anchor:
		pose._release_trigger_hand_grip_lock()
		SocketIK.stop(pose.right_hand_ik)
	# Finalize the hand-owned pistol mount before solving its support palm.
	# BoneAttachment notifications otherwise resample the moving right wrist
	# after this pass, moving the socket away from the already-solved left hand.
	# Idle still follows the authored right palm; only ready may align to aim.
	pose._set_weapon_solver_owned(pose.animation_owned_aim_alignment_enabled)
	if pose.animation_owned_aim_alignment_enabled and not use_animation_aim_anchor:
		pose._weapon_transform_on_trigger_hand(pose._right_hand_grip_world_transform(), true)
	pose.desired_weight = (
		1.0
		if pose.support_hand_socket_ik_enabled
		and pose.support_hand_mode == &"IK_TO_WEAPON"
		and pose.support_socket != null
		and pose.left_hand_ik != null
		else 0.0
	)
	pose.current_weight = move_toward(
		pose.current_weight,
		pose.desired_weight,
		clampf(delta, 0.0, 0.05) / pose.support_hand_ik_blend_seconds
	)
	var animation_aim_direction := Vector3.ZERO
	if use_animation_aim_anchor:
		# Each frame starts from the immutable calibrated mount on the current
		# animated right palm. The detached presentation anchor then receives one
		# bounded correction, so neither drift nor attachment resampling can
		# accumulate across frames.
		pose._weapon_transform_on_trigger_hand(pose._right_hand_grip_world_transform(), true)
		var animation_aim_origin: Vector3 = (
			pose.muzzle_socket.global_position
			if pose.muzzle_socket != null
			else sampled_trigger_palm_position
		)
		animation_aim_direction = pose._resolve_aim_direction(
			aim_yaw,
			aim_pitch,
			world_aim_target,
			animation_aim_origin,
			body
		)
		# The animation supplies the human arm shape, but its trigger palm can
		# cross toward the left shoulder while the upper-body mask blends in.
		# Center only that palm, then attach and aim the pistol from the solved
		# contact. The left hand follows the final physical support socket below.
		pose._solve_pistol_trigger_hand_centerline(animation_aim_direction, ready_weight)
		pose._weapon_transform_on_trigger_hand(pose._right_hand_grip_world_transform(), true)
		var solved_aim_origin: Vector3 = (
			pose.muzzle_socket.global_position
			if pose.muzzle_socket != null
			else pose._right_hand_grip_world_transform().origin
		)
		animation_aim_direction = pose._resolve_aim_direction(
			aim_yaw,
			aim_pitch,
			world_aim_target,
			solved_aim_origin,
			body
		)
		pose.last_aim_direction = animation_aim_direction
		pose.last_target_point = (
			world_aim_target
			if world_aim_target != Vector3.ZERO
			else animation_aim_origin + animation_aim_direction * 20.0
		)
		pose.aim_target_marker.global_position = pose.last_target_point
		pose.animation_owned_aim_alignment_active = true
		# Finalize the presentation-owned weapon root after the bounded trigger
		# palm solve and before the support contact is measured or solved.
		# A compressed authored idle can extend its arms smoothly while the
		# accepted shot already points at the reticle. Only this bounded rigid
		# correction receives the optional shot weight; torso/arm blending and
		# ownership still use the original readiness scalar.
		pose._align_hand_owned_weapon_root_to_aim(
			animation_aim_direction,
			accepted_shot_aim_weight if accepted_shot_aim_weight >= 0.0 else ready_weight
		)
	if pose.current_weight > 0.001:
		pose.support_hand_target.global_position = pose.support_socket.global_position
		var raw_support_pose: Variant = pose.weapon_node.get_meta(
			"support_hand_pose",
			{}
		)
		var support_pose: Dictionary = (
			raw_support_pose
			if raw_support_pose is Dictionary
			else {}
		)
		var support_rotation_degrees := Vector3(
			float(support_pose.get("palm_pitch_deg", 0.0)),
			float(support_pose.get("palm_yaw_deg", 0.0)),
			float(support_pose.get("palm_roll_deg", 0.0))
		)
		pose.support_hand_target.global_basis = (
			pose.support_socket.global_basis.orthonormalized()
			* Basis.from_euler(
				support_rotation_degrees * (PI / 180.0),
				EULER_ORDER_YXZ
			)
		).orthonormalized()
		if pose.animation_owned_aim_alignment_enabled and not use_animation_aim_anchor:
			PistolCarryReach.fit(pose)
		pose._update_support_contact_elbow_pole(pose.support_socket.global_position)
		# The saved Gunsmith contact owns only this wrist basis. The same bounded
		# modifier closes the palm and rotates the hand onto the handguard without
		# changing the rifle, trigger arm, shoulder, or torso.
		pose.support_hand_grip_locked = true
		pose.left_hand_ik.override_tip_basis = true
		pose._solve_socket_arm(
			pose.left_hand_ik,
			pose.support_hand_target,
			pose.left_elbow_pole,
			&"mixamorig_LeftHand"
		)
		pose.skeleton.force_update_all_bone_transforms()
		pose.support_hand_error_m = pose.support_socket.global_position.distance_to(
			WeaponContactSolver.palm_contact_world(
				pose.skeleton,
				int(pose.bone_indices.get(&"mixamorig_LeftHand", -1)),
				pose.left_palm_anchor_local
			)
		)
		if pose.animation_owned_aim_alignment_active and pose.trigger_socket != null:
			# The root was finalized before the support solve. Measure the same final
			# frame without rotating the pistol out of either palm afterward.
			pose.trigger_hand_error_m = pose.trigger_socket.global_position.distance_to(
				pose._right_hand_grip_world_transform().origin
			)
			pose.support_hand_error_m = pose.support_socket.global_position.distance_to(
				WeaponContactSolver.palm_contact_world(
					pose.skeleton,
					int(pose.bone_indices.get(&"mixamorig_LeftHand", -1)),
					pose.left_palm_anchor_local
				)
			)
	else:
		SocketIK.stop(pose.left_hand_ik)
		pose._release_support_hand_grip_lock()
		if pose.animation_owned_aim_alignment_active and pose.trigger_socket != null:
			pose.trigger_hand_error_m = pose.trigger_socket.global_position.distance_to(
				pose._right_hand_grip_world_transform().origin
			)
	pose.right_elbow_angle_deg = pose._current_elbow_angle(&"right")
	pose.left_elbow_angle_deg = pose._current_elbow_angle(&"left")
	return
