extends "res://scripts/player/operator_animation_driver_presentation.gd"

## Read-only animation diagnostics for Labs and regressions.

func get_animation_debug_state() -> Dictionary:
	var snapshot := {
		"gameplay_state": movement_state,
		"previous_gameplay_state": _previous_movement_state,
		"previous_clip": previous_clip,
		"logical_clip": current_clip,
		"source_take": get_source_animation_name(current_clip),
		"resource_path": str(clip_paths.get(current_clip, "")),
		"locomotion_active": _locomotion_active,
		"movement_gait": movement_gait,
		"weapon_ready_weight": weapon_ready_weight,
		"requested_weapon_ready_weight": requested_weapon_ready_weight,
		"fire_ready_hold_remaining": _fire_ready_hold_remaining,
		"locomotion_blend_seconds": locomotion_blend_seconds,
		"direction_octant": _stable_direction_octant,
		"recoil_weight": 0.0,
		"upper_body_recoil_layer": false,
		"upper_body_reload_layer": _requested_action_upper_body_layered,
		"transition_reason": _last_transition_reason,
		"movement_speed_mps": movement_speed_mps,
		"prone_straighten_weight": _prone_straighten_weight,
		"prone_axis_weight": _prone_straighten_weight,
		"prone_axis_target_pitch_deg": prone_axis_target_pitch_deg,
		"prone_axis_max_correction_deg": prone_axis_max_correction_deg,
		"peek_amount": peek_amount,
		"standing_master_pose_active": _standing_master_pose_active(),
		"standing_master_pose_frame_suppressed": _standing_master_pose_frame_suppressed,
		"last_event_presentation": _last_event_presentation.duplicate(true),
		"equipped_weapon_family": equipped_weapon_family,
	}
	if locomotion_graph != null:
		snapshot.merge(locomotion_graph.get_debug_state(), true)
	if posture_layer != null:
		snapshot.merge(posture_layer.get_debug_state(), true)
	if animation_frame_pose_runtime != null:
		snapshot["animation_frame_pose"] = animation_frame_pose_runtime.get_debug_state()
	if ik_contract != null:
		snapshot["ik"] = ik_contract.get_debug_state()
	if weapon_pose_solver != null:
		snapshot["weapon_pose"] = weapon_pose_solver.get_debug_state()
	return snapshot


