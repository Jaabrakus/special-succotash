class_name GunsmithLabAuthoringApi
extends "res://scripts/labs/gunsmith/gunsmith_lab_animation_api.gd"

## Stable 3D rig-authoring compatibility surface.
## Gizmo, rig, preview-scene, and weapon-pose behavior stays in focused controllers.

func _setup_unscaled_hand_gizmo() -> void:
	GunsmithGizmoInteractionController._setup_unscaled_hand_gizmo(self)

func _setup_unscaled_weapon_gizmo() -> void:
	GunsmithGizmoInteractionController._setup_unscaled_weapon_gizmo(self)

func _set_active_gizmo(gizmo_id: String) -> void:
	GunsmithGizmoInteractionController._set_active_gizmo(self, gizmo_id)

func _register_interactive_dots() -> void:
	GunsmithGizmoInteractionController._register_interactive_dots(self)

func _setup_weapon_contact_graph() -> void:
	GunsmithContactGraphController.setup(self)

func _load_weapon_contact_graph_profile(raw: Variant) -> void:
	GunsmithContactGraphController.load_profile(self, raw)

func _weapon_contact_graph_save_data() -> Dictionary:
	return GunsmithContactGraphController.save_data(self)

func _sync_weapon_contact_graph() -> void:
	GunsmithContactGraphController.sync(self)

func _set_weapon_contact_target(target_id: String) -> void:
	GunsmithContactGraphController.set_selected_target(self, target_id)

func _set_weapon_contact_component(kind: String, axis: int, value: float) -> void:
	GunsmithContactGraphController.set_selected_component(self, kind, axis, value)

func _drag_weapon_contact_target(target_id: String, world_position: Vector3) -> void:
	GunsmithContactGraphController.apply_world_drag(self, target_id, world_position)

func _find_dot_under_mouse(screen_pos: Vector2) -> String:
	return GunsmithGizmoInteractionController._find_dot_under_mouse(self, screen_pos)

func _screen_point_segment_distance(point: Vector2, segment_start: Vector2, segment_end: Vector2) -> float:
	return GunsmithGizmoInteractionController._screen_point_segment_distance(self, point, segment_start, segment_end)

func _ring_pick_distance(screen_pos: Vector2, center: Vector3, basis: Basis, axis_name: String, radius: float) -> float:
	return GunsmithGizmoInteractionController._ring_pick_distance(self, screen_pos, center, basis, axis_name, radius)

func _get_dot_mesh_by_id(dot_id: String) -> MeshInstance3D:
	return GunsmithGizmoInteractionController._get_dot_mesh_by_id(self, dot_id)

func _highlight_dot(dot_id: String) -> void:
	GunsmithGizmoInteractionController._highlight_dot(self, dot_id)

func _apply_dot_world_drag(dot_id: String, world_pos: Vector3) -> void:
	GunsmithGizmoInteractionController._apply_dot_world_drag(self, dot_id, world_pos)

func _pointer_over_editor_ui(screen_position: Vector2) -> bool:
	return GunsmithGizmoInteractionController._pointer_over_editor_ui(self, screen_position)

func _cancel_3d_authoring_pointer() -> void:
	GunsmithGizmoInteractionController._cancel_3d_authoring_pointer(self)

func _set_elbow_pole_from_world(side: StringName, world_pos: Vector3) -> void:
	GunsmithRigAuthoringController._set_elbow_pole_from_world(self, side, world_pos)

func _store_current_stance_elbow_poles() -> void:
	GunsmithRigAuthoringController._store_current_stance_elbow_poles(self)

func _restore_current_stance_elbow_poles() -> void:
	GunsmithRigAuthoringController._restore_current_stance_elbow_poles(self)

func _update_elbow_slider_controls() -> void:
	GunsmithRigAuthoringController._update_elbow_slider_controls(self)

func _set_elbow_component(value: float, side: StringName, axis: StringName) -> void:
	GunsmithRigAuthoringController._set_elbow_component(self, value, side, axis)

func _elbow_poles_save_data() -> Dictionary:
	return GunsmithRigAuthoringController._elbow_poles_save_data(self)

func _update_slider_value(slider_key: String, val: float) -> void:
	GunsmithRigAuthoringController._update_slider_value(self, slider_key, val)

func _setup_elbow_pole_visuals() -> void:
	GunsmithRigAuthoringController._setup_elbow_pole_visuals(self)

func _setup_body_joint_visuals() -> void:
	GunsmithRigAuthoringController._setup_body_joint_visuals(self)

func _update_body_joint_visuals() -> void:
	GunsmithRigAuthoringController._update_body_joint_visuals(self)

func _select_body_joint(joint_name: StringName) -> void:
	GunsmithRigAuthoringController._select_body_joint(self, joint_name)

func _adjust_selected_joint_rotation(delta_degrees: Vector3) -> void:
	GunsmithRigAuthoringController._adjust_selected_joint_rotation(self, delta_degrees)

func _set_body_joint_component(value: float, axis: StringName) -> void:
	GunsmithRigAuthoringController._set_body_joint_component(self, value, axis)

func _apply_joint_chain_delta(joint_name: StringName, delta_degrees: Vector3) -> void:
	GunsmithRigAuthoringController._apply_joint_chain_delta(self, joint_name, delta_degrees)

func _sync_body_joint_controls() -> void:
	GunsmithRigAuthoringController._sync_body_joint_controls(self)

func _bone_world_origin(bone_index: int) -> Vector3:
	return GunsmithRigAuthoringController._bone_world_origin(self, bone_index)

func _update_elbow_pole_visuals() -> void:
	GunsmithRigAuthoringController._update_elbow_pole_visuals(self)

func _add_debug_segment(from: Vector3, to: Vector3, color: Color) -> void:
	GunsmithRigAuthoringController._add_debug_segment(self, from, to, color)

func _setup_studio_environment() -> void:
	GunsmithPreviewSceneController._setup_studio_environment(self)

func _update_camera() -> void:
	GunsmithPreviewSceneController._update_camera(self)

func _set_camera_preset(preset_name: String) -> void:
	GunsmithPreviewSceneController._set_camera_preset(self, preset_name)

func _setup_trooper_and_rig() -> void:
	GunsmithPreviewSceneController._setup_trooper_and_rig(self)

func _neutral_preview_hip_rotation() -> Quaternion:
	return GunsmithPreviewSceneController._neutral_preview_hip_rotation(self)

func _get_gunsmith_fixed_aim_target() -> Vector3:
	return GunsmithPreviewSceneController._get_gunsmith_fixed_aim_target(self)

func _apply_runtime_posture_preview() -> void:
	GunsmithPreviewSceneController._apply_runtime_posture_preview(self)

func _initialize_weapon_master_pose() -> void:
	GunsmithPreviewSceneController._initialize_weapon_master_pose(self)

func _set_weapon_ik_enabled(enabled: bool) -> void:
	GunsmithPreviewSceneController._set_weapon_ik_enabled(self, enabled)

func _set_save_enabled(enabled: bool) -> void:
	GunsmithPreviewSceneController._set_save_enabled(self, enabled)

func _get_right_hand_bone_index() -> int:
	return GunsmithPreviewSceneController._get_right_hand_bone_index(self)

func _get_right_hand_world_transform() -> Transform3D:
	return GunsmithWeaponPoseController._get_right_hand_world_transform(self)

func _weapon_anchor_world_transform() -> Transform3D:
	return GunsmithWeaponPoseController._weapon_anchor_world_transform(self)

func _capture_weapon_anchor() -> void:
	GunsmithWeaponPoseController._capture_weapon_anchor(self)

func _weapon_anchor_target_transform() -> Transform3D:
	return GunsmithWeaponPoseController._weapon_anchor_target_transform(self)

func _update_weapon_master_anchor() -> void:
	GunsmithWeaponPoseController._update_weapon_master_anchor(self)

func _gunsmith_live_aim_active() -> bool:
	return GunsmithWeaponPoseController._gunsmith_live_aim_active(self)

func _update_live_aim_weapon_pose() -> void:
	GunsmithWeaponPoseController._update_live_aim_weapon_pose(self)

func _gun_placement_line_match_active() -> bool:
	return GunsmithWeaponPoseController._gun_placement_line_match_active(self)

func _match_weapon_rail_to_blue_line() -> bool:
	return GunsmithWeaponPoseController._match_weapon_rail_to_blue_line(self)

func _right_hand_pose_is_ready() -> bool:
	return GunsmithWeaponPoseController._right_hand_pose_is_ready(self)

func _load_operator_mount(profile: Dictionary) -> void:
	GunsmithWeaponPoseController._load_operator_mount(self, profile)

func _dictionary_to_vector3(value: Variant, fallback: Vector3) -> Vector3:
	return GunsmithWeaponPoseController._dictionary_to_vector3(self, value, fallback)

func _vector3_to_dictionary(v: Vector3) -> Dictionary:
	return GunsmithWeaponPoseController._vector3_to_dictionary(self, v)

func _degrees_to_radians_vector(value: Vector3) -> Vector3:
	return GunsmithWeaponPoseController._degrees_to_radians_vector(self, value)

func _radians_to_degrees_vector(value: Vector3) -> Vector3:
	return GunsmithWeaponPoseController._radians_to_degrees_vector(self, value)

func _world_drag_to_parent_local_delta(parent_node: Node3D, world_start: Vector3, world_current: Vector3) -> Vector3:
	return GunsmithWeaponPoseController._world_drag_to_parent_local_delta(self, parent_node, world_start, world_current)

func _show_rig_error(msg: String) -> void:
	GunsmithWeaponPoseController._show_rig_error(self, msg)

func _validate_weapon_rig_before_save() -> bool:
	return GunsmithWeaponPoseController._validate_weapon_rig_before_save(self)

func _finish_weapon_bootstrap() -> void:
	await GunsmithWeaponPoseController._finish_weapon_bootstrap(self)

func _calculate_palm_anchor(side: String, hand_index: int) -> Vector3:
	return WeaponContactSolver.calculate_palm_anchor(skeleton, side, hand_index)

func _right_palm_contact_world() -> Vector3:
	return WeaponContactSolver.palm_contact_world(skeleton, right_hand_idx, right_palm_anchor_local)

func _left_palm_contact_world() -> Vector3:
	return WeaponContactSolver.palm_contact_world(skeleton, left_hand_idx, left_palm_anchor_local)

func _get_bone_global_rest(bone_idx: int) -> Transform3D:
	var chain: Array[Transform3D] = []
	var current_idx := bone_idx
	while current_idx >= 0:
		chain.push_front(skeleton.get_bone_rest(current_idx))
		current_idx = skeleton.get_bone_parent(current_idx)
	var result := Transform3D.IDENTITY
	for local_rest in chain:
		result = result * local_rest
	return result
