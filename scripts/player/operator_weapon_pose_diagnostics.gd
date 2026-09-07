class_name SocomOperatorWeaponPoseDiagnostics
extends RefCounted

## Read-only snapshot builder for the weapon presentation coordinator. Keeping
## diagnostics outside the live solve makes the coordinator easier to audit and
## prevents debug/UI growth from changing pose ownership code.

const WeaponOwnershipContract := preload(
	"res://scripts/player/weapon_ownership_contract.gd"
)


static func capture(source) -> Dictionary:
	var pose_owners := WeaponOwnershipContract.resolve_pose_owners(
		source.last_movement_state,
		source.last_requested_action,
		source.current_weight,
		source.action_weapon_follow_active,
		source.last_reload_support_regrip,
		source.last_posture
	)
	return {
		"fire_recoil_weight": source.fire_recoil.weight(),
		"active": source.current_weight > 0.001,
		"weight": source.current_weight,
		"desired_weight": source.desired_weight,
		"target_reachable": source.target_reachable,
		"trigger_hand_error_m": source.trigger_hand_error_m,
		"support_hand_error_m": source.support_hand_error_m,
		"trigger_hand_position": (
			source._right_hand_grip_world_transform().origin
			if source.right_hand_owns_ready_weapon
			else source._bone_world_position(&"mixamorig_RightHand")
		),
		"support_hand_position": source._bone_world_position(&"mixamorig_LeftHand"),
		"trigger_hand_target": source.trigger_hand_target.global_position,
		"support_hand_target": source.support_hand_target.global_position,
		"weapon_world_position": (
			source.weapon_node.global_position
			if source.weapon_node != null
			else Vector3.ZERO
		),
		"aim_direction": source.last_aim_direction,
		"aim_target": source.last_target_point,
		"posture": source.last_posture,
		"anatomical_adjustment_m": source.anatomical_adjustment_m,
		"torso_assist_requested": source.torso_assist_requested,
		"aim_yaw_demand_deg": source.aim_yaw_demand_deg,
		"aim_pitch_demand_deg": source.aim_pitch_demand_deg,
		"right_elbow_angle_deg": source.right_elbow_angle_deg,
		"left_elbow_angle_deg": source.left_elbow_angle_deg,
		"right_elbow_position": source._bone_world_position(&"mixamorig_RightForeArm"),
		"left_elbow_position": source._bone_world_position(&"mixamorig_LeftForeArm"),
		"head_position": source._bone_world_position(&"mixamorig_Head"),
		"prone_grip_ceiling_y": (
			source.stable_chest_anchor_world.y
			+ source.prone_maximum_grip_above_chest_m
		),
		"prone_elbow_ceiling_y": (
			source.stable_chest_anchor_world.y
			+ source.prone_maximum_elbow_above_chest_m
		),
		"right_elbow_pole_position": source.right_elbow_pole.global_position,
		"left_elbow_pole_position": source.left_elbow_pole.global_position,
		"weapon_aim_error_deg": source.weapon_aim_error_deg,
		"wrist_correction_deg": source.wrist_correction_deg,
		"socket_contract_active": source.socket_contract_active,
		"adaptive_support_socket": source.adaptive_support_socket,
		"weapon_solver_owned": source.weapon_solver_owned,
		"weapon_parent_is_animation_mount": (
			source.weapon_node != null
			and source.weapon_animation_parent != null
			and source.weapon_node.get_parent() == source.weapon_animation_parent
		),
		"animation_mount_position_error_m": (
			source.weapon_node.transform.origin.distance_to(
				source.weapon_hand_mount_transform.origin
			)
			if source.weapon_node != null
			and source.weapon_animation_parent != null
			and source.weapon_node.get_parent() == source.weapon_animation_parent
			else -1.0
		),
		"weapon_owner": source.weapon_owner,
		"previous_weapon_owner": source.previous_weapon_owner,
		"weapon_owner_transition_count": source.weapon_owner_transition_count,
		"arm_owner": WeaponOwnershipContract.arm_owner(source.weapon_owner),
		"action_weapon_follow_active": source.action_weapon_follow_active,
		"action_weapon_chest_owned": source.action_weapon_chest_owned,
		"action_weapon_swing_deg": source.action_weapon_swing_deg,
		"stable_chest_anchor_world": source.stable_chest_anchor_world,
		"dive_weapon_presentation": source.dive_weapon_presentation.duplicate(true),
		"action_trigger_contact_error_m": source.action_trigger_contact_error_m,
		"action_support_contact_error_m": source.action_support_contact_error_m,
		"support_hand_mode": source.support_hand_mode,
		"pose_owners": pose_owners,
		"ownership_conflicts": WeaponOwnershipContract.ownership_conflicts(
			pose_owners,
			source.weapon_owner,
			source.support_hand_mode
		),
		"trigger_hand_grip_locked": source.trigger_hand_grip_locked,
		"trigger_hand_grip_rotation_error_deg": source.trigger_hand_grip_rotation_error_deg,
		"support_hand_grip_locked": source.support_hand_grip_locked,
		"support_hand_grip_rotation_error_deg": source.support_hand_grip_rotation_error_deg,
		"animation_frame_weapon_rotation_correction_deg": (
			source._animation_frame_weapon_rotation_degrees()
		),
		"right_hand_owns_ready_weapon": source.right_hand_owns_ready_weapon,
		"animation_drives_ready_hands": source.animation_drives_ready_hands,
		"hand_socket_ik_enabled": source.hand_socket_ik_enabled,
		"support_hand_socket_ik_enabled": source.support_hand_socket_ik_enabled,
		"animation_owned_aim_alignment_enabled": (
			source.animation_owned_aim_alignment_enabled
		),
		"authored_shoulder_stock_enabled": source.authored_shoulder_stock_enabled,
		"authored_shoulder_stock_active": source.authored_shoulder_stock_active,
		"authored_stock_release_applied_m": source.authored_stock_release_applied_m,
		"authored_stock_right_turn_weight": source.authored_stock_right_turn_weight,
		"authored_stock_release_frame": source.strafe_right_stock_release_frame,
		"authored_stock_release_direction_world": source.authored_stock_release_direction_world,
		"animation_owned_aim_alignment_active": (
			source.animation_owned_aim_alignment_active
		),
		"pistol_trigger_centerline_ik_active": (
			source.pistol_trigger_centerline_ik_active
		),
		"pistol_trigger_centerline_shift_m": (
			source.pistol_trigger_centerline_shift_m
		),
		"right_hand_ik_running": (
			source.right_hand_ik != null and source.right_hand_ik.is_running()
		),
		"support_socket_clamped": source.support_socket_clamped,
		"animation_carry_weight": source.animation_carry_weight,
		"animation_carry_limit_m": source.animation_carry_limit_m,
		"buttstock_constraint": (
			source.stock_constraint.get_debug_state()
			if source.stock_constraint != null
			else {}
		),
		"ownership_return_active": (
			source.ownership_return_elapsed < source.ownership_return_seconds
		),
		"cover_pose_amount": source.cover_pose_amount,
		"cover_pose_name": source.cover_pose_name,
		"shot_blocked": source.shot_blocked,
		"prone_floor_lift_m": source.prone_floor_lift_m,
		"muzzle_floor_clearance_m": source.muzzle_floor_clearance_m,
		"prone_floor_contact_detected": source.prone_floor_contact_detected,
		"animation_frame_pose_active": not source.animation_frame_pose.is_empty(),
		"gun_placement_line_active": (
			source._gun_placement_line_active_for(source.last_posture)
		),
		"gun_placement_line_authored": source.gun_placement_line_authored,
		"rail_to_blue_line_event_active": source.rail_to_blue_line_event_remaining > 0.0,
		"rail_to_blue_line_event_remaining": source.rail_to_blue_line_event_remaining,
		"gun_placement_frame_bone": &"mixamorig_Spine2",
		"gun_placement_anchor_space": (
			&"LIVE_HEAD_PREVIEW"
			if source.rail_to_blue_line_event_remaining > 0.0
			and source.last_posture in [&"CROUCHED", &"PRONE"]
			else &"STABLE_CHEST"
		),
		"gun_placement_baseline_active": (
			source.gun_placement_baseline_basis_by_posture.has(source.last_posture)
		),
		"gun_placement_error_m": source.gun_placement_error_m,
		"gun_placement_roll_error_deg": source.gun_placement_roll_error_deg,
		"gun_placement_origin": source.last_gun_placement_origin,
		"gun_placement_direction": source.last_gun_placement_direction,
		"gun_placement_locomotion_carry_local": source.gun_placement_locomotion_carry_local,
		"gun_placement_locomotion_active": source.gun_placement_locomotion_active,
		"gun_placement_shoulder_alternation_m": source.gun_placement_shoulder_alternation_m,
		"obstruction_direction_hold_active": source.obstruction_direction_hold_active,
		"last_unobstructed_render_direction": source.last_unobstructed_render_direction,
	}
