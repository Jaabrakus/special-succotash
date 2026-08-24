class_name GunsmithLabAnimationApi
extends "res://scripts/labs/gunsmith/gunsmith_lab_state.gd"

## Stable Animation Studio compatibility surface.
## Behavior lives in focused controllers; this layer preserves the lab API used by UI and tests.

func _solve_trigger_hand_engine() -> void:
	GunsmithHandSolver.solve_trigger_hand(self)

func _right_hand_world_transform() -> Transform3D:
	return GunsmithHandSolver.right_hand_world_transform(self)

func _right_hand_grip_world_transform() -> Transform3D:
	return GunsmithHandSolver.right_hand_grip_world_transform(self)

func _left_hand_world_transform() -> Transform3D:
	return GunsmithHandSolver.left_hand_world_transform(self)

func _begin_action_weapon_follow() -> void:
	GunsmithActionWeaponController.begin_follow(self)

func _finish_action_weapon_follow() -> void:
	GunsmithActionWeaponController.finish_follow(self)

func _update_action_weapon_ownership(delta: float) -> void:
	GunsmithActionWeaponController.update_ownership(self, delta)

func _editing_action_weapon_frame() -> bool:
	return GunsmithActionWeaponController.editing_action_frame(self)

func _animation_frame_weapon_correction_transform() -> Transform3D:
	return GunsmithActionWeaponController.frame_correction_transform(self)

func _adjust_weapon_rotation(axis_name: String, delta_degrees: float) -> float:
	return GunsmithActionWeaponController.adjust_rotation(self, axis_name, delta_degrees)

func _adjust_weapon_translation(axis_name: String, delta_meters: float) -> float:
	return GunsmithActionWeaponController.adjust_translation(self, axis_name, delta_meters)

func _active_reload_timeline() -> Dictionary:
	return GunsmithActionWeaponController.active_reload_timeline(self)

func _active_reload_frame_count() -> int:
	return GunsmithActionWeaponController.active_reload_frame_count(self)

func _active_reload_frame_index() -> int:
	return GunsmithActionWeaponController.active_reload_frame_index(self)

func _update_reload_support_handoff() -> void:
	GunsmithActionWeaponController.update_reload_support_handoff(self)

func _update_reload_magazine_visual() -> void:
	GunsmithActionWeaponController.update_reload_magazine_visual(self)

func _right_elbow_magnet_for(wrist_world: Vector3) -> Vector3:
	return GunsmithHandSolver.right_elbow_magnet_for(self, wrist_world)

func _right_elbow_pole_base_world(wrist_world: Vector3) -> Vector3:
	return GunsmithHandSolver.right_elbow_pole_base_world(self, wrist_world)

func _right_elbow_pole_world(wrist_world: Vector3) -> Vector3:
	return GunsmithHandSolver.right_elbow_pole_world(self, wrist_world)

func _solve_biomechanical_arm_engine() -> void:
	GunsmithHandSolver.solve_support_hand(self)

func _left_elbow_magnet_for(wrist_world: Vector3) -> Vector3:
	return GunsmithHandSolver.left_elbow_magnet_for(self, wrist_world)

func _left_elbow_pole_base_world(wrist_world: Vector3) -> Vector3:
	return GunsmithHandSolver.left_elbow_pole_base_world(self, wrist_world)

func _left_elbow_pole_world(wrist_world: Vector3) -> Vector3:
	return GunsmithHandSolver.left_elbow_pole_world(self, wrist_world)

func _update_stance_weapon_rebase(delta: float) -> void:
	GunsmithHandSolver.update_stance_rebase(self, delta)

func _apply_hand_and_finger_posing() -> void:
	GunsmithHandSolver.apply_finger_posing(self)

func _trigger_reload_animation() -> void:
	GunsmithEventPreviewController.trigger_reload(self)

func _posture_fire_slot() -> String:
	return GunsmithEventPreviewController.posture_fire_slot(self)

func _fire_event_presentation() -> Dictionary:
	return GunsmithEventPreviewController.fire_event_presentation(self)

func _preview_fire_animation(presentation: Dictionary = {}) -> void:
	GunsmithEventPreviewController.preview_fire(self, presentation)

func _set_support_hand_attached(attached: bool, announce: bool = true) -> void:
	GunsmithEventPreviewController.set_support_hand_attached(self, attached, announce)

func _build_handling_animation_ui(parent: VBoxContainer) -> void:
	GunsmithHandlingPanel.build(self, parent)

func _open_animation_studio_corrections() -> void:
	var error := get_tree().change_scene_to_file("res://animation_library_lab.tscn")
	if error != OK and hud_status:
		hud_status.text = "⚠ Animation Studio could not be opened (%s)." % error_string(error)

func _build_animation_frame_editor_ui(parent: VBoxContainer) -> void:
	GunsmithFrameEditorView.build(self, parent)

func _build_animation_frame_timeline_overlay() -> void:
	GunsmithFrameEditorView.build_timeline(self)

func _on_handling_family_selected(index: int) -> void:
	GunsmithEventPreviewController.on_handling_family_selected(self, index)

func _auto_build_animation_set() -> void:
	GunsmithEventPreviewController.auto_build_animation_set(self)

func _on_animation_slot_selected(index: int, slot_name: String, selector: OptionButton) -> void:
	GunsmithEventPreviewController.on_animation_slot_selected(self, index, slot_name, selector)

func _refresh_handling_ui(sync_selectors: bool = true) -> void:
	GunsmithEventPreviewController.refresh_handling_ui(self, sync_selectors)

func _preview_animation_slot(slot_name: String, forced_clip_name: StringName = &"") -> void:
	GunsmithEventPreviewController.preview_animation_slot(self, slot_name, forced_clip_name)

func _preview_selected_catalog_animation() -> void:
	GunsmithAnimationFrameController._preview_selected_catalog_animation(self)

func _edit_animation_slot(slot_name: String) -> void:
	GunsmithAnimationFrameController._edit_animation_slot(self, slot_name)

func _edit_selected_catalog_animation() -> void:
	GunsmithAnimationFrameController._edit_selected_catalog_animation(self)

func _toggle_current_animation_frame_editor() -> void:
	GunsmithAnimationFrameController._toggle_current_animation_frame_editor(self)

func _pause_animation_frame_editor_for_authoring() -> void:
	GunsmithAnimationFrameController._pause_animation_frame_editor_for_authoring(self)

func _set_animation_edit_candidate(slot_name: String, clip_name: StringName) -> void:
	GunsmithAnimationFrameController._set_animation_edit_candidate(self, slot_name, clip_name)

func _enter_animation_frame_editor(slot_name: String, clip_name: StringName) -> void:
	GunsmithAnimationFrameController._enter_animation_frame_editor(self, slot_name, clip_name)

func _leave_animation_frame_editor() -> void:
	GunsmithAnimationFrameController._leave_animation_frame_editor(self)

func _toggle_animation_frame_editor_playback() -> void:
	GunsmithAnimationFrameController._toggle_animation_frame_editor_playback(self)

func _step_animation_frame_editor(frame_delta: int) -> void:
	GunsmithAnimationFrameController._step_animation_frame_editor(self, frame_delta)

func _seek_animation_frame_editor(normalized_time: float) -> void:
	GunsmithAnimationFrameController._seek_animation_frame_editor(self, normalized_time)

func _seek_animation_frame_index(frame_index: int) -> void:
	GunsmithAnimationFrameController._seek_animation_frame_index(self, frame_index)

func _update_animation_frame_editor() -> void:
	GunsmithAnimationFrameController._update_animation_frame_editor(self)

func _refresh_animation_frame_editor_ui() -> void:
	GunsmithAnimationFrameController._refresh_animation_frame_editor_ui(self)

func _is_reload_frame_editor() -> bool:
	return GunsmithAnimationFrameController._is_reload_frame_editor(self)

func _current_reload_events() -> Dictionary:
	return GunsmithAnimationFrameController._current_reload_events(self)

func _set_reload_event_at_current_frame(event_name: String) -> void:
	GunsmithAnimationFrameController._set_reload_event_at_current_frame(self, event_name)

func _capture_animation_frame_pose_key() -> void:
	GunsmithAnimationFrameController._capture_animation_frame_pose_key(self)

func _apply_animation_frame_pose_for_current_time() -> void:
	GunsmithAnimationFrameController._apply_animation_frame_pose_for_current_time(self)

func _snapshot_animation_frame_pose() -> Dictionary:
	return GunsmithAnimationFrameController._snapshot_animation_frame_pose(self)

func _restore_animation_frame_pose(pose_data: Dictionary) -> void:
	GunsmithAnimationFrameController._restore_animation_frame_pose(self, pose_data)

func _finish_preview_to_idle() -> void:
	GunsmithAnimationPreviewController._finish_preview_to_idle(self)

func _posture_idle_slot() -> String:
	return GunsmithAnimationPreviewController._posture_idle_slot(self)

func _posture_idle_clip() -> StringName:
	return GunsmithAnimationPreviewController._posture_idle_clip(self)

func _set_preview_posture(posture_name: StringName) -> void:
	GunsmithAnimationPreviewController._set_preview_posture(self, posture_name)

func _restore_current_stance_hands() -> void:
	GunsmithAnimationPreviewController._restore_current_stance_hands(self)

func _save_selected_animation_hand_map() -> void:
	GunsmithAnimationPreviewController._save_selected_animation_hand_map(self)

func _apply_animation_hand_map(clip_key: StringName) -> void:
	GunsmithAnimationPreviewController._apply_animation_hand_map(self, clip_key)

func _vector_to_data(value: Vector3) -> Dictionary:
	return GunsmithAnimationPreviewController._vector_to_data(self, value)

func _current_hand_pose_snapshot() -> Dictionary:
	return GunsmithAnimationPreviewController._current_hand_pose_snapshot(self)

func _hand_maps_without_legacy_mounts(raw_maps: Dictionary) -> Dictionary:
	return GunsmithAnimationPreviewController._hand_maps_without_legacy_mounts(self, raw_maps)

func _vector_from_data(raw_value: Variant, fallback: Vector3) -> Vector3:
	return GunsmithAnimationPreviewController._vector_from_data(self, raw_value, fallback)

func _apply_weapon_ownership_policy(policy: Dictionary, reload_action: bool) -> void:
	GunsmithAnimationPreviewController._apply_weapon_ownership_policy(self, policy, reload_action)

func _update_animation_quality_readout(delta: float) -> void:
	GunsmithAnimationPreviewController._update_animation_quality_readout(self, delta)

func _audit_all_equipped_animation_states() -> void:
	await GunsmithAnimationPreviewController._audit_all_equipped_animation_states(self)

func _auto_fix_failed_animation_states() -> void:
	await GunsmithAnimationPreviewController._auto_fix_failed_animation_states(self)

func _undo_animation_autofix() -> void:
	GunsmithAnimationPreviewController._undo_animation_autofix(self)

func _measure_animation_quality(slot_name: String, clip_name: StringName) -> Dictionary:
	return await GunsmithAnimationPreviewController._measure_animation_quality(self, slot_name, clip_name)

func _ensure_preview_clip(clip_name: StringName) -> bool:
	return GunsmithAnimationPreviewController._ensure_preview_clip(self, clip_name)

func slot_name_is_looping(clip_name: StringName) -> bool:
	return GunsmithAnimationPreviewController.slot_name_is_looping(self, clip_name)
