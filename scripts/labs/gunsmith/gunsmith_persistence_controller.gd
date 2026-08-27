extends RefCounted

const WeaponProfileRepository := preload("res://scripts/labs/gunsmith/gunsmith_weapon_profile_repository.gd")
const WeaponSceneExporter := preload("res://scripts/labs/gunsmith/gunsmith_weapon_scene_exporter.gd")
const RecomCatalogAdapter := preload(
	"res://scripts/labs/gunsmith/gunsmith_recom_catalog_adapter.gd"
)
const WEAPON_BASE_PATH := "res://assets/weapons/modular_pack/"

static func _request_save_everything(lab: Node) -> void:
	if lab.hud_status:
		lab.hud_status.text = "Saving the selected weapon rig and equipping it…"
		lab.hud_status.tooltip_text = lab.hud_status.text
	lab._save_weapon_config()


static func _save_weapon_config(lab: Node) -> bool:
	if not lab._validate_weapon_rig_before_save():
		return false
	var loaded_profile: Dictionary = lab._loaded_weapon_profile
	var saved_stance_hands: Dictionary = (
		(loaded_profile.get("stances", {}) as Dictionary).duplicate(true)
		if loaded_profile.get("stances", {}) is Dictionary
		else {}
	)
	var saved_animation_hands: Dictionary = (
		(loaded_profile.get("animation_hand_maps", {}) as Dictionary).duplicate(true)
		if loaded_profile.get("animation_hand_maps", {}) is Dictionary
		else {}
	)
	var saved_frame_pose_keys: Dictionary = (
		(loaded_profile.get("animation_frame_pose_keys", {}) as Dictionary).duplicate(true)
		if loaded_profile.get("animation_frame_pose_keys", {}) is Dictionary
		else {}
	)
	var saved_support_pose: Dictionary = (
		(loaded_profile.get("support_hand_pose", {}) as Dictionary).duplicate(true)
		if loaded_profile.get("support_hand_pose", {}) is Dictionary
		else {}
	)
	var saved_elbow_poles: Dictionary = (
		(loaded_profile.get("elbow_poles", {}) as Dictionary).duplicate(true)
		if loaded_profile.get("elbow_poles", {}) is Dictionary
		else {}
	)
	var saved_handling_profile: Dictionary = (
		(loaded_profile.get("handling_profile", {}) as Dictionary).duplicate(true)
		if loaded_profile.get("handling_profile", {}) is Dictionary
		else lab.handling_profile.duplicate(true)
	)
	var saved_placement_line: Dictionary = (
		(loaded_profile.get("gun_placement_line", {}) as Dictionary).duplicate(true)
		if loaded_profile.get("gun_placement_line", {}) is Dictionary
		else {}
	)
	synchronize_ready_contact(
		saved_stance_hands,
		saved_animation_hands,
		saved_frame_pose_keys,
		lab.left_grip_local_pos
	)

	var config_data: Dictionary = {
		"schema_version": 3,
		"socket_contract_authored": true,
		"coordinate_space": {
			"grip_offset": "weapon_root_local_meters",
			"weapon_sockets": "weapon_pivot_local_meters"
		},
		"weapon_id": lab.weapon_name.to_lower(),
		"display_name": lab.weapon_display_name,
		"category": lab.selected_category,
		"camo_skin": lab.camo_skins[lab.selected_camo_idx],
		"model_fbx": lab.selected_model_path,
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
		"support_hand_pose": saved_support_pose,
		"elbow_poles": saved_elbow_poles,
		"stances": saved_stance_hands,
		"animation_hand_maps": saved_animation_hands,
		"animation_frame_pose_keys": saved_frame_pose_keys,
		"handling_profile": saved_handling_profile,
		"gun_placement_line": saved_placement_line,
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
		"composure": lab._current_composure_profile(),
		"fire_modes": lab.catalog_fire_modes.duplicate(),
		"default_fire_mode": lab.catalog_default_fire_mode,
		"burst_size": lab.catalog_burst_size,
	}
	config_data = RecomCatalogAdapter.decorate_saved_profile(
		config_data,
		lab.selected_catalog_weapon_id
	)

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
			lab.weapon_display_name,
			lab.muzzle_local_pos.x,
			lab.muzzle_local_pos.y,
			lab.muzzle_local_pos.z,
		]
		lab.hud_status.add_theme_color_override("font_color", Color(0.2, 1.0, 0.4))
	return true


static func synchronize_ready_contact(
	stance_hands: Dictionary,
	animation_hands: Dictionary,
	frame_pose_keys: Dictionary,
	support_socket: Vector3
) -> void:
	var support_data := {
		"x": support_socket.x,
		"y": support_socket.y,
		"z": support_socket.z,
	}
	var standing: Dictionary = stance_hands.get("STANDING", {})
	if not standing.is_empty():
		standing["left_grip"] = support_data.duplicate(true)
		stance_hands["STANDING"] = standing
	var aim_idle: Dictionary = animation_hands.get("aim_idle", {})
	if not aim_idle.is_empty():
		aim_idle["left_grip"] = support_data.duplicate(true)
		animation_hands["aim_idle"] = aim_idle
	var aim_idle_frames: Dictionary = frame_pose_keys.get("aim_idle", {})
	var first_frame: Dictionary = aim_idle_frames.get("0", {})
	if not first_frame.is_empty():
		first_frame["left_hand_target"] = support_data.duplicate(true)
		aim_idle_frames["0"] = first_frame
		frame_pose_keys["aim_idle"] = aim_idle_frames


static func _weapon_sockets_save_data(lab: Node) -> Dictionary:
	var buttstock: Vector3 = (
		lab.right_grip_local_pos
		- _barrel_axis_local(lab) * 0.30
		+ Vector3.UP * 0.08
	)
	return {
		"right_hand_grip_target": lab._vector3_to_dictionary(lab.right_grip_local_pos),
		"left_hand_ik_target": lab._vector3_to_dictionary(lab.left_grip_local_pos),
		"muzzle_socket": lab._vector3_to_dictionary(lab.muzzle_local_pos),
		"barrel_base_socket": lab._vector3_to_dictionary(lab._calibrated_barrel_base()),
		"buttstock_socket": lab._vector3_to_dictionary(buttstock),
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
		"display_name": lab.weapon_display_name,
		"weapon_mesh": lab.current_weapon_mesh,
		"silencer_mesh": lab.current_silencer_mesh,
		"scope_mesh": lab.current_scope_mesh,
		"left_hand_socket": lab.left_grip_local_pos,
		"right_hand_socket": lab.right_grip_local_pos,
		"muzzle_socket": lab.muzzle_local_pos,
		"barrel_base_socket": lab._calibrated_barrel_base(),
		"buttstock_socket": (
			lab.right_grip_local_pos
			- _barrel_axis_local(lab) * 0.30
			+ Vector3.UP * 0.08
		),
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
