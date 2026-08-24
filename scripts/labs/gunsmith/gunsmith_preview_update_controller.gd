class_name GunsmithPreviewUpdateController
extends RefCounted

## Runs the existing Gunsmith preview passes in their established order.
## It owns no simulation or profile state.

static func update(lab, delta: float) -> void:
	if lab.fire_cooldown > 0.0:
		lab.fire_cooldown = maxf(0.0, lab.fire_cooldown - delta)

	lab.fire_input_held = (
		Input.is_key_pressed(KEY_SPACE)
		or (
			lab.mouse_fire_armed
			and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
		)
	) and (
		not lab.is_orbiting
		and not lab.is_panning
		and not lab.is_reloading
		and not lab.authoring_pointer_down
		and lab.dragged_dot_id == ""
	)
	lab._update_bloom_recovery(delta, lab.fire_input_held)
	lab.composure.advance(
		delta,
		lab.composure_preview_movement,
		lab.composure_preview_turning,
		lab._composure_stance()
	)
	if lab.composure_preview_dummy != null and lab.composure_preview_dummy.has_method("set_precision_core_debug"):
		lab.composure_preview_dummy.call(
			"set_precision_core_debug",
			lab.composure_preview_active,
			lab.composure.get_precision_core_scale()
		)
	lab._update_composure_readout()

	if lab.fire_input_held:
		if lab.fire_cooldown <= 0.0:
			lab._fire_shot()

	if lab.animation_player:
		if not lab.animation_frame_editor.active or lab.animation_frame_editor.playing:
			lab.animation_player.advance(delta)
		if lab.animation_frame_editor.active:
			lab._update_animation_frame_editor()
	if not lab.weapon_master_pose_initialized:
		lab._initialize_weapon_master_pose()
	# Build the final authored + procedural hand pose before either weapon owner
	# consumes it. Reload/action follow must never trail the visible hand by one
	# update, and the ready anchor must use the same final posture sample.
	lab._apply_runtime_posture_preview()
	lab._update_action_weapon_ownership(delta)
	lab._update_reload_support_handoff()
	lab._update_weapon_master_anchor()
	lab._update_live_aim_weapon_pose()

	lab._solve_trigger_hand_engine()
	lab._solve_biomechanical_arm_engine()
	lab._apply_hand_and_finger_posing()
	if lab.skeleton:
		lab.skeleton.force_update_all_bone_transforms()
	lab._update_reload_magazine_visual()
	lab._update_elbow_pole_visuals()
	lab._update_body_joint_visuals()
	lab._update_hurtbox_edit_markers()
	lab._update_eye_sight_marker()
	lab._update_animation_quality_readout(delta)

	if lab.hand_gizmo_world and lab.left_grip_marker and is_instance_valid(lab.left_grip_marker):
		lab.hand_gizmo_world.global_position = lab.left_grip_marker.global_position
		if lab.current_weapon_mesh:
			lab.hand_gizmo_world.global_basis = lab.current_weapon_mesh.global_basis.orthonormalized()

	if lab.weapon_gizmo_world and lab.weapon_pivot and is_instance_valid(lab.weapon_pivot):
		lab.weapon_gizmo_world.global_position = lab.weapon_pivot.global_position
		if lab.weapon_root:
			lab.weapon_gizmo_world.global_basis = lab.weapon_root.global_basis.orthonormalized()

	if lab.dynamic_reticle and lab.cam:
		lab.current_aim_target = lab._camera_aim_sample().position
		var aim_sample: Dictionary = lab._muzzle_axis_sample()
		var total_spread: float = lab._current_total_spread_deg()
		lab.dynamic_reticle.update_reticle_state(
			clampf(total_spread / maxf(lab.max_recoil_bloom_deg, 0.001), 0.0, 1.0),
			bool(aim_sample.target_locked),
			lab._reticle_screen_position(),
			false,
			lab.composure_preview_movement
		)
	lab._update_fire_debug_lines()
	if lab.reticle_canvas:
		lab.reticle_canvas.queue_redraw()



