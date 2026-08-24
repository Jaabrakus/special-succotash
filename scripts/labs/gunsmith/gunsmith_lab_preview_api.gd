class_name GunsmithLabPreviewApi
extends "res://scripts/labs/gunsmith/gunsmith_lab_authoring_api.gd"

## Stable weapon-preview/profile compatibility surface.
## Loading, firing, persistence, and dial behavior stays in focused controllers.

func _create_axis_arrow(color: Color, axis_dir: Vector3, arrow_name: String, length: float = 0.26) -> Node3D:
	return GunsmithGizmoFactory.create_axis_arrow(color, axis_dir, arrow_name, length)

func _create_rotation_ring(color: Color, normal_axis: Vector3, radius: float, ring_name: String) -> MeshInstance3D:
	return GunsmithGizmoFactory.create_rotation_ring(color, normal_axis, radius, ring_name)

func _create_marker(color: Color, marker_name: String, radius: float = 0.055) -> MeshInstance3D:
	return GunsmithGizmoFactory.create_marker(color, marker_name, radius)

func _create_selection_box(color: Color, marker_name: String, size: float = 0.065) -> MeshInstance3D:
	return GunsmithGizmoFactory.create_selection_box(color, marker_name, size)

func _load_weapon(file_name: String) -> void:
	GunsmithWeaponPreviewLoader.load_weapon(self, file_name)

func _setup_reload_magazine_proxy() -> void:
	GunsmithWeaponPreviewLoader.setup_reload_magazine_proxy(self)

func _try_load_saved_profile(w_id: String) -> void:
	GunsmithProfileLoader.load(self, w_id)

func _reset_fire_profile_defaults() -> void:
	GunsmithProfileLoader.reset_fire_defaults(self)

func _refresh_fire_controls() -> void:
	GunsmithProfileLoader.refresh_fire_controls(self)

func _default_muzzle_velocity_mps() -> float:
	return GunsmithProfileLoader.default_muzzle_velocity_mps(self)

func _apply_9mm_textures(node: Node) -> void:
	GunsmithWeaponPreviewLoader.apply_9mm_textures(self, node)

func _apply_camo_skin_to_weapon(node: Node, camo_idx: int) -> void:
	GunsmithWeaponPreviewLoader.apply_camo_skin_to_weapon(self, node, camo_idx)

func _load_silencer(s_name: String) -> void:
	GunsmithWeaponFirePreviewController._load_silencer(self, s_name)

func _load_scope(sc_name: String) -> void:
	GunsmithWeaponFirePreviewController._load_scope(self, sc_name)

func _sync_weapon_transform(keep_trigger_attached: bool = true) -> void:
	GunsmithWeaponFirePreviewController._sync_weapon_transform(self, keep_trigger_attached)

func _sync_weapon_translation() -> void:
	GunsmithWeaponFirePreviewController._sync_weapon_translation(self)

func _sync_ballistic_markers() -> void:
	GunsmithWeaponFirePreviewController._sync_ballistic_markers(self)

func _sync_hand_markers() -> void:
	GunsmithWeaponFirePreviewController._sync_hand_markers(self)

func _sync_markers() -> void:
	GunsmithWeaponFirePreviewController._sync_markers(self)

func _preview_screen_rect() -> Rect2:
	return GunsmithWeaponFirePreviewController._preview_screen_rect(self)

func _reticle_screen_position() -> Vector2:
	return GunsmithWeaponFirePreviewController._reticle_screen_position(self)

func _camera_aim_sample() -> Dictionary:
	return GunsmithWeaponFirePreviewController._camera_aim_sample(self)

func _muzzle_axis_sample() -> Dictionary:
	return GunsmithWeaponFirePreviewController._muzzle_axis_sample(self)

func _stance_spread_multiplier() -> float:
	return GunsmithWeaponFirePreviewController._stance_spread_multiplier(self)

func _current_total_spread_deg() -> float:
	return GunsmithWeaponFirePreviewController._current_total_spread_deg(self)

func _composure_stance() -> OperatorComposure.Stance:
	return GunsmithWeaponFirePreviewController._composure_stance(self)

func _update_composure_readout() -> void:
	GunsmithWeaponFirePreviewController._update_composure_readout(self)

func _align_trigger_socket_to_right_hand(update_controls: bool = true) -> void:
	GunsmithWeaponFirePreviewController._align_trigger_socket_to_right_hand(self, update_controls)

func _fire_shot() -> void:
	GunsmithWeaponFirePreviewController._fire_shot(self)

func _apply_pixel_texture(node: Node) -> void:
	if node is MeshInstance3D:
		var mat := StandardMaterial3D.new()
		mat.albedo_texture = PS1_GAS_MASK_TEX
		mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		node.material_override = mat
	for child in node.get_children():
		_apply_pixel_texture(child)

func _ensure_65_bone_contract() -> void:
	for side in ["Left", "Right"]:
		var hand_index := skeleton.find_bone("mixamorig_%sHand" % side)
		if hand_index < 0:
			continue
		for finger in ["Middle", "Ring", "Pinky"]:
			var parent_index := hand_index
			for segment in range(1, 5):
				var bone_name := "mixamorig_%sHand%s%d" % [side, finger, segment]
				var bone_index := skeleton.find_bone(bone_name)
				if bone_index < 0:
					bone_index = skeleton.add_bone(bone_name)
					var index_reference := skeleton.find_bone("mixamorig_%sHandIndex%d" % [side, segment])
					if index_reference >= 0:
						skeleton.set_bone_rest(bone_index, skeleton.get_bone_rest(index_reference))
				skeleton.set_bone_parent(bone_index, parent_index)
				parent_index = bone_index

func _retarget_aim_anim(src_anim: Animation) -> Animation:
	var retargeted := src_anim.duplicate()
	var root_n := animation_player.get_node(animation_player.root_node)
	var skel_path := root_n.get_path_to(skeleton)
	for i in range(retargeted.get_track_count() - 1, -1, -1):
		var old_path := str(retargeted.track_get_path(i))
		var raw_bone := old_path.split(":")[-1]
		var norm := raw_bone.replace("mixamorig:", "mixamorig_")
		if not norm.begins_with("mixamorig_"):
			norm = "mixamorig_" + norm
		var target_bone := ""
		if skeleton.find_bone(raw_bone) != -1:
			target_bone = raw_bone
		elif skeleton.find_bone(norm) != -1:
			target_bone = norm
		if target_bone != "":
			retargeted.track_set_path(i, NodePath(str(skel_path) + ":" + target_bone))
			if ("Hips" in raw_bone or "root" in raw_bone.to_lower()) and retargeted.track_get_type(i) == Animation.TYPE_POSITION_3D:
				for k in range(retargeted.track_get_key_count(i)):
					var pos: Vector3 = retargeted.track_get_key_value(i, k)
					pos.x = 0.0
					pos.z = 0.0
					pos.y *= 0.0191988
					retargeted.track_set_key_value(i, k, pos)
		else:
			retargeted.remove_track(i)
	return retargeted

func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for child in node.get_children():
		var found := _find_skeleton(child)
		if found:
			return found
	return null

func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child in node.get_children():
		var found := _find_animation_player(child)
		if found:
			return found
	return null

func _request_save_everything() -> void:
	GunsmithPersistenceController._request_save_everything(self)

func _save_weapon_config() -> bool:
	return GunsmithPersistenceController._save_weapon_config(self)

func _weapon_sockets_save_data() -> Dictionary:
	return GunsmithPersistenceController._weapon_sockets_save_data(self)

func _barrel_axis_local() -> Vector3:
	return GunsmithPersistenceController._barrel_axis_local(self)

func _calibrated_barrel_base() -> Vector3:
	return GunsmithPersistenceController._calibrated_barrel_base(self)

func _gunsmith_bore_direction_world() -> Vector3:
	return GunsmithPersistenceController._gunsmith_bore_direction_world(self)

func _barrel_direction_world() -> Vector3:
	return GunsmithPersistenceController._barrel_direction_world(self)

func _bullet_velocity_vector() -> Vector3:
	return GunsmithPersistenceController._bullet_velocity_vector(self)

func _save_and_play_latest_playground() -> void:
	GunsmithPersistenceController._save_and_play_latest_playground(self)

func _open_latest_playground() -> void:
	GunsmithPersistenceController._open_latest_playground(self)

func _export_weapon_packed_scene(config_data: Dictionary) -> void:
	GunsmithPersistenceController._export_weapon_packed_scene(self, config_data)

func _setup_rotation_corner_controls() -> void:
	GunsmithPresentationController.setup_rotation_controls(self)

func _apply_rotation_dial_delta(axis_name: String, delta_degrees: float) -> void:
	GunsmithPresentationController.apply_rotation_delta(self, axis_name, delta_degrees)

func _apply_hand_direction_delta(yaw_delta: float, pitch_delta: float) -> void:
	GunsmithPresentationController.apply_hand_direction_delta(self, yaw_delta, pitch_delta)

func _rotation_axis_value(axis_name: String) -> float:
	return GunsmithPresentationController.rotation_axis_value(self, axis_name)

func _refresh_rotation_dials() -> void:
	GunsmithPresentationController.refresh_rotation_dials(self)
