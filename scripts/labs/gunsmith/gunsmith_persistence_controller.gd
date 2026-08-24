extends RefCounted

const HurtboxProfile := preload("res://scripts/combat/socom_hurtbox_profile.gd")
const WeaponProfileRepository := preload("res://scripts/labs/gunsmith/gunsmith_weapon_profile_repository.gd")
const WeaponSceneExporter := preload("res://scripts/labs/gunsmith/gunsmith_weapon_scene_exporter.gd")
const WEAPON_BASE_PATH := "res://assets/weapons/modular_pack/"

static func _request_save_everything(lab: Node) -> void:
	if lab.hud_status:
		lab.hud_status.text = "💾 Saving every Rig & Hands, animation, composure, posture, and hitbox change…"
		lab.hud_status.tooltip_text = lab.hud_status.text
	lab._save_weapon_config()


static func _save_weapon_config(lab: Node) -> bool:
	if not lab._validate_weapon_rig_before_save():
		return false
	if not HurtboxProfile.save_profile(
		lab.shared_hurtbox_scales,
		lab.shared_hurtbox_geometry,
		lab.shared_custom_hitboxes
	):
		lab._show_rig_error(
			"Shared hitbox profile could not be saved. Weapon save blocked so main cannot drift from this preview."
		)
		return false
	if lab.animation_frame_editor.active:
		lab._capture_animation_frame_pose_key()
	lab._save_selected_animation_hand_map()
	lab._store_current_stance_elbow_poles()
	if lab.runtime_posture_layer and not lab.runtime_posture_layer.save_procedural_profile():
		lab._show_rig_error("Operator joint and posture edits could not be saved. Save blocked.")
		return false
	var saved_stance_hands: Dictionary = lab._hand_maps_without_legacy_mounts(lab.hand_poses_by_stance)
	var saved_animation_hands: Dictionary = lab._hand_maps_without_legacy_mounts(lab.animation_hand_maps)

	var config_data: Dictionary = {
		"schema_version": 3,
		"socket_contract_authored": true,
		"coordinate_space": {
			"grip_offset": "weapon_root_local_meters",
			"weapon_sockets": "weapon_pivot_local_meters"
		},
		"weapon_id": lab.weapon_name.to_lower(),
		"display_name": lab.weapon_name,
		"category": lab.selected_category,
		"camo_skin": lab.camo_skins[lab.selected_camo_idx],
		"model_fbx": WEAPON_BASE_PATH + lab.weapon_name + ".fbx" if (lab.weapon_name != "ak-47" and lab.weapon_name != "9mm_pistol") else ("res://assets/weapons/ps1_ak47/source/ak-47.fbx" if lab.weapon_name == "ak-47" else "res://assets/weapons/9mm_pistol/source/model/model.dae"),
		"silencer_attachment": lab.selected_silencer,
		"scope_attachment": lab.selected_scope,
		"normalized_scale": lab.auto_normalized_scale * lab.user_scale_multiplier,
		"user_scale_multiplier": lab.user_scale_multiplier,
		"model_rotation_degrees": {
			"x": lab.current_weapon_mesh.rotation_degrees.x if lab.current_weapon_mesh else 0.0,
			"y": lab.current_weapon_mesh.rotation_degrees.y if lab.current_weapon_mesh else 0.0,
			"z": lab.current_weapon_mesh.rotation_degrees.z if lab.current_weapon_mesh else 0.0
		},
		"operator_mount": {
			"position": lab._vector3_to_dictionary(lab.weapon_mount_local.origin * lab.trooper_scale),
			"rotation_degrees": lab._vector3_to_dictionary(lab._radians_to_degrees_vector(lab.weapon_mount_local.basis.orthonormalized().get_euler(EULER_ORDER_YXZ)))
		},
		"grip_offset": {
			"pos_x": (lab.auto_grip_center_offset + lab.grip_offset_pos).x,
			"pos_y": (lab.auto_grip_center_offset + lab.grip_offset_pos).y,
			"pos_z": (lab.auto_grip_center_offset + lab.grip_offset_pos).z,
			"rot_x": lab.grip_offset_rot.x,
			"rot_y": lab.grip_offset_rot.y,
			"rot_z": lab.grip_offset_rot.z
		},
		"support_hand_pose": {
			"palm_pitch_deg": lab.palm_pitch,
			"palm_yaw_deg": lab.palm_yaw,
			"palm_roll_deg": lab.palm_roll,
			"finger_curl": lab.finger_curl,
			"thumb_wrap": lab.thumb_wrap
		},
		"elbow_poles": {
			"right": {"x": lab.right_elbow_pole_offset.x, "y": lab.right_elbow_pole_offset.y, "z": lab.right_elbow_pole_offset.z},
			"left": {"x": lab.left_elbow_pole_offset.x, "y": lab.left_elbow_pole_offset.y, "z": lab.left_elbow_pole_offset.z},
			"by_stance": lab._elbow_poles_save_data()
		},
		"stances": saved_stance_hands,
		"animation_hand_maps": saved_animation_hands,
		"animation_frame_pose_keys": lab.animation_frame_editor.save_data(),
		"handling_profile": lab.handling_profile.duplicate(true),
		"gun_placement_line": lab._gun_placement_line_save_data(),
		"weapon_sockets": lab._weapon_sockets_save_data(),
		"ballistics": {
			"fire_rate_rpm": lab.fire_rate_rpm,
			"damage": lab.damage_per_shot,
			"headshot_multiplier": lab.headshot_multiplier,
			"muzzle_velocity_mps": lab.muzzle_velocity_mps,
			"base_spread_deg": lab.base_spread_deg,
			"moving_spread_deg": lab.moving_spread_deg,
			"full_gait_spread_deg": lab.full_gait_spread_deg,
			"opening_burst_motion_multiplier": lab.opening_burst_motion_multiplier,
			"bloom_per_shot_deg": lab.bloom_per_shot_deg,
			"max_recoil_bloom_deg": lab.max_recoil_bloom_deg,
			"bloom_recovery_speed": lab.bloom_recovery_speed,
			"functional_aim_climb_enabled": lab.functional_aim_climb_enabled,
			"aim_climb_pitch_per_shot_deg": lab.aim_climb_pitch_per_shot_deg,
			"aim_climb_yaw_per_shot_deg": lab.aim_climb_yaw_per_shot_deg,
			"aim_climb_max_pitch_deg": lab.aim_climb_max_pitch_deg,
			"aim_climb_max_yaw_deg": lab.aim_climb_max_yaw_deg,
			"aim_climb_recovery_delay_seconds": lab.aim_climb_recovery_delay_seconds,
			"aim_climb_recovery_speed_deg_per_second": lab.aim_climb_recovery_speed_deg_per_second,
			"crouch_spread_multiplier": lab.crouch_spread_multiplier,
			"crouch_bloom_per_shot_deg": lab.crouch_bloom_per_shot_deg,
			"crouch_max_recoil_bloom_deg": lab.crouch_max_recoil_bloom_deg,
			"crouch_bloom_recovery_speed": lab.crouch_bloom_recovery_speed,
			"magazine_capacity": lab.magazine_capacity,
			"reserve_ammo": lab.reserve_ammo,
			"is_silenced": lab.is_silenced
		},
		"reticle": lab._current_reticle_profile(),
		"composure": lab._current_composure_profile()
	}

	var save_result: Dictionary = WeaponProfileRepository.save_and_equip(
		lab.weapon_name.to_lower(),
		config_data
	)
	if not bool(save_result.get("ok", false)):
		lab._show_rig_error(String(save_result.get("error", "Weapon profile save failed.")) + " Save blocked.")
		return false

	lab._export_weapon_packed_scene(config_data)
	var collector := lab.get_node_or_null("/root/PlaytestStateCollector")
	if collector != null:
		var bundle_result: Dictionary = collector.call("collect_saved_state")
		if not bool(bundle_result.get("ok", false)):
			lab._show_rig_error(
				"Rig saved, but gameplay could not collect the latest lab state: %s"
				% str(bundle_result.get("errors", []))
			)
			return false
	if lab.hud_status:
		lab.hud_status.text = "💾 SAVED & EQUIPPED! %s • muzzle (%.3f, %.3f, %.3f) saved exactly." % [
			lab.weapon_name,
			lab.muzzle_local_pos.x,
			lab.muzzle_local_pos.y,
			lab.muzzle_local_pos.z,
		]
		lab.hud_status.add_theme_color_override("font_color", Color(0.2, 1.0, 0.4))
	return true


static func _weapon_sockets_save_data(lab: Node) -> Dictionary:
	return {
		"right_hand_grip_target": lab._vector3_to_dictionary(lab.right_grip_local_pos),
		"left_hand_ik_target": lab._vector3_to_dictionary(lab.left_grip_local_pos),
		"muzzle_socket": lab._vector3_to_dictionary(lab.muzzle_local_pos),
		"barrel_base_socket": lab._vector3_to_dictionary(lab._calibrated_barrel_base()),
		"ejection_port": lab._vector3_to_dictionary(lab.ejection_local_pos),
		"optic_rail": lab._vector3_to_dictionary(lab.optic_local_pos),
	}

static func _barrel_axis_local(lab: Node) -> Vector3:
	var axis: Vector3 = lab.muzzle_local_pos - lab.barrel_base_local_pos
	if axis.length_squared() <= 0.000001:
		return Vector3.FORWARD
	return axis.normalized()


static func _calibrated_barrel_base(lab: Node) -> Vector3:
	return lab.barrel_base_local_pos


static func _gunsmith_bore_direction_world(lab: Node) -> Vector3:
	if lab.socket_root == null:
		return Vector3.FORWARD
	var clean_basis: Basis = lab.socket_root.global_basis.orthonormalized()
	return (clean_basis * lab._barrel_axis_local()).normalized()


static func _barrel_direction_world(lab: Node) -> Vector3:
	return lab._gunsmith_bore_direction_world()


static func _bullet_velocity_vector(lab: Node) -> Vector3:
	return lab._barrel_direction_world() * lab.muzzle_velocity_mps

static func _save_and_play_latest_playground(lab: Node) -> void:
	# One canonical handoff: the live build never guesses which lab or scene is
	# newest. Save the selected weapon contract, then enter main.tscn.
	if not lab._save_weapon_config():
		return
	if lab.hud_status:
		lab.hud_status.text = "✅ Rig saved. Opening the latest gameplay playground…"
	lab.call_deferred("_open_latest_playground")

static func _open_latest_playground(lab: Node) -> void:
	var nav := lab.get_node_or_null("/root/StudioNavigation")
	if nav != null:
		nav.call("open_scene", "res://main.tscn")
	else:
		var change_error := lab.get_tree().change_scene_to_file("res://main.tscn")
		if change_error != OK and lab.hud_status:
			lab.hud_status.text = "Could not open the latest playground (%s)." % error_string(change_error)

static func _export_weapon_packed_scene(lab: Node,config_data: Dictionary) -> void:
	var export_result := WeaponSceneExporter.export_scene({
		"weapon_id": lab.weapon_name.to_lower(),
		"display_name": lab.weapon_name,
		"weapon_mesh": lab.current_weapon_mesh,
		"silencer_mesh": lab.current_silencer_mesh,
		"scope_mesh": lab.current_scope_mesh,
		"left_hand_socket": lab.left_grip_local_pos,
		"right_hand_socket": lab.right_grip_local_pos,
		"muzzle_socket": lab.muzzle_local_pos,
		"barrel_base_socket": lab._calibrated_barrel_base(),
		"ejection_socket": lab.ejection_local_pos,
		"optic_socket": lab.optic_local_pos,
	})
	if bool(export_result.get("ok", false)):
		if lab.hud_status:
			lab.hud_status.text = "✅ SAVED + EQUIPPED: %s | Character will load this exact rig" % lab.weapon_name.to_lower()
		print("Successfully exported ready-to-use game asset to: ", export_result.get("path", ""))
	else:
		push_error("Gunsmith scene export failed: %s" % export_result.get("error", "unknown error"))

# ─── UI ───────────────────────────────────────────────────────────────────────
