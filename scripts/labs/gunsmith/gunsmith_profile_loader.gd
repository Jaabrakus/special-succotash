extends RefCounted

const WeaponProfileRepository := preload("res://scripts/labs/gunsmith/gunsmith_weapon_profile_repository.gd")
const RecomCatalogAdapter := preload(
	"res://scripts/labs/gunsmith/gunsmith_recom_catalog_adapter.gd"
)
const OperatorComposureScript := preload("res://scripts/weapons/operator_composure.gd")

static func load(lab: Node,w_id: String) -> void:
	var d: Dictionary = RecomCatalogAdapter.load_editable_profile(w_id)
	if d.is_empty():
		d = WeaponProfileRepository.load_profile(w_id)
	if not d.is_empty():
		lab._loaded_weapon_profile = d.duplicate(true)
		lab._load_operator_mount(lab._loaded_weapon_profile)
		var saved_model_rotation: Variant = d.get("model_rotation_degrees", {})
		if saved_model_rotation is Dictionary and lab.current_weapon_mesh != null:
			lab.current_weapon_mesh.rotation_degrees = lab._vector_from_data(
				saved_model_rotation,
				lab.current_weapon_mesh.rotation_degrees
			)
		lab._load_gun_placement_line_profile(d.get("gun_placement_line", {}))
		if d.get("animation_hand_maps", {}) is Dictionary:
			lab.animation_hand_maps = (d.get("animation_hand_maps", {}) as Dictionary).duplicate(true)
		lab.animation_frame_editor.load_data(d.get("animation_frame_pose_keys", {}))
		if d.get("handling_profile", {}) is Dictionary and not (d.get("handling_profile", {}) as Dictionary).is_empty():
			lab.handling_profile = (d.get("handling_profile", {}) as Dictionary).duplicate(true)
		var sock: Dictionary = d.get("weapon_sockets", {})
		if sock.has("left_hand_ik_target"):
			var ik = sock["left_hand_ik_target"]
			lab.left_grip_local_pos = Vector3(ik.get("x", lab.left_grip_local_pos.x), ik.get("y", lab.left_grip_local_pos.y), ik.get("z", lab.left_grip_local_pos.z))
		elif d.has("left_hand_ik_target"):
			var ik = d["left_hand_ik_target"]
			lab.left_grip_local_pos = Vector3(ik.get("x", lab.left_grip_local_pos.x), ik.get("y", lab.left_grip_local_pos.y), ik.get("z", lab.left_grip_local_pos.z))
		if sock.has("right_hand_grip_target"):
			var right_grip: Dictionary = sock["right_hand_grip_target"]
			lab.right_grip_local_pos = Vector3(
				float(right_grip.get("x", lab.right_grip_local_pos.x)),
				float(right_grip.get("y", lab.right_grip_local_pos.y)),
				float(right_grip.get("z", lab.right_grip_local_pos.z))
			)
			lab.right_grip_profile_loaded = true

		if sock.has("muzzle_socket"):
			var mz = sock["muzzle_socket"]
			lab.muzzle_local_pos = Vector3(mz.get("x", lab.muzzle_local_pos.x), mz.get("y", lab.muzzle_local_pos.y), mz.get("z", lab.muzzle_local_pos.z))
		if sock.has("barrel_base_socket"):
			var bb = sock["barrel_base_socket"]
			lab.barrel_base_local_pos = Vector3(bb.get("x", lab.barrel_base_local_pos.x), bb.get("y", lab.barrel_base_local_pos.y), bb.get("z", lab.barrel_base_local_pos.z))
		if sock.has("ejection_port"):
			var ej = sock["ejection_port"]
			lab.ejection_local_pos = Vector3(ej.get("x", lab.ejection_local_pos.x), ej.get("y", lab.ejection_local_pos.y), ej.get("z", lab.ejection_local_pos.z))
		if sock.has("optic_rail"):
			var op = sock["optic_rail"]
			lab.optic_local_pos = Vector3(op.get("x", lab.optic_local_pos.x), op.get("y", lab.optic_local_pos.y), op.get("z", lab.optic_local_pos.z))
		if d.has("grip_offset"):
			var gp = d["grip_offset"]
			lab.grip_offset_pos = Vector3(gp.get("pos_x", 0.0), gp.get("pos_y", 0.0), gp.get("pos_z", 0.0)) - lab.auto_grip_center_offset
			lab.grip_offset_rot = Vector3(gp.get("rot_x", 0.0), gp.get("rot_y", 0.0), gp.get("rot_z", 0.0))
		if d.has("support_hand_pose"):
			var hand_pose: Dictionary = d["support_hand_pose"]
			lab.palm_pitch = float(hand_pose.get("palm_pitch_deg", lab.palm_pitch))
			lab.palm_yaw = float(hand_pose.get("palm_yaw_deg", lab.palm_yaw))
			lab.palm_roll = float(hand_pose.get("palm_roll_deg", lab.palm_roll))
			lab.finger_curl = float(hand_pose.get("finger_curl", lab.finger_curl))
			lab.thumb_wrap = float(hand_pose.get("thumb_wrap", lab.thumb_wrap))
		var stances_data: Variant = d.get("stances", {})
		if stances_data is Dictionary and not (stances_data as Dictionary).is_empty():
			for posture: StringName in [&"STANDING", &"CROUCHED", &"PRONE"]:
				var stance_dict: Dictionary = (stances_data as Dictionary).get(String(posture), {})
				if not stance_dict.is_empty():
					lab.hand_poses_by_stance[posture] = stance_dict.duplicate(true)
		else:
			for posture: StringName in [&"STANDING", &"CROUCHED", &"PRONE"]:
				var slot: String = "idle_standing" if posture == &"STANDING" else ("idle_crouched" if posture == &"CROUCHED" else "idle_prone")
				var clip: String = String((lab.handling_profile.get("animation_slots", {}) as Dictionary).get(slot, ""))
				var map: Dictionary = lab.animation_hand_maps.get(clip, {})
				if map.is_empty():
					map = lab.animation_hand_maps.get(String(lab.all_animation_paths.get(clip, "")), {})
				if not map.is_empty():
					lab.hand_poses_by_stance[posture] = map.duplicate(true)
		var elbow_poles: Variant = d.get("elbow_poles", {})
		if elbow_poles is Dictionary:
			var pole_data := elbow_poles as Dictionary
			var by_stance: Variant = pole_data.get("by_stance", {})
			if by_stance is Dictionary and not (by_stance as Dictionary).is_empty():
				for posture: StringName in [&"STANDING", &"CROUCHED", &"PRONE"]:
					var saved_stance: Dictionary = (by_stance as Dictionary).get(String(posture), {})
					lab.elbow_poles_by_stance[posture] = {
						"right": lab._vector_from_data(saved_stance.get("right", {}), Vector3.ZERO),
						"left": lab._vector_from_data(saved_stance.get("left", {}), Vector3.ZERO),
					}
			else:
				var legacy_right: Vector3 = lab._vector_from_data(
					pole_data.get("right", {}),
					Vector3.ZERO
				)
				var legacy_left: Vector3 = lab._vector_from_data(
					pole_data.get("left", {}),
					Vector3.ZERO
				)
				for posture: StringName in [&"STANDING", &"CROUCHED", &"PRONE"]:
					lab.elbow_poles_by_stance[posture] = {"right": legacy_right, "left": legacy_left}
			lab._restore_current_stance_elbow_poles()
			lab._restore_current_stance_hands()
		var ballistics: Variant = d.get("ballistics", {})
		if ballistics is Dictionary:
			var fire_values := ballistics as Dictionary
			lab.fire_rate_rpm = int(fire_values.get("fire_rate_rpm", lab.fire_rate_rpm))
			lab.damage_per_shot = int(fire_values.get("damage", lab.damage_per_shot))
			lab.headshot_multiplier = float(fire_values.get("headshot_multiplier", lab.headshot_multiplier))
			lab.muzzle_velocity_mps = float(fire_values.get("muzzle_velocity_mps", lab.muzzle_velocity_mps))
			lab.base_spread_deg = float(fire_values.get("base_spread_deg", lab.base_spread_deg))
			lab.moving_spread_deg = float(fire_values.get("moving_spread_deg", lab.moving_spread_deg))
			lab.full_gait_spread_deg = float(fire_values.get("full_gait_spread_deg", lab.full_gait_spread_deg))
			lab.opening_burst_motion_multiplier = float(fire_values.get(
				"opening_burst_motion_multiplier",
				lab.opening_burst_motion_multiplier
			))
			lab.bloom_per_shot_deg = float(fire_values.get("bloom_per_shot_deg", lab.bloom_per_shot_deg))
			lab.max_recoil_bloom_deg = float(fire_values.get("max_recoil_bloom_deg", lab.max_recoil_bloom_deg))
			lab.bloom_recovery_speed = float(fire_values.get("bloom_recovery_speed", lab.bloom_recovery_speed))
			lab.functional_aim_climb_enabled = bool(fire_values.get("functional_aim_climb_enabled", lab.functional_aim_climb_enabled))
			lab.aim_climb_pitch_per_shot_deg = float(fire_values.get("aim_climb_pitch_per_shot_deg", lab.aim_climb_pitch_per_shot_deg))
			lab.aim_climb_yaw_per_shot_deg = float(fire_values.get("aim_climb_yaw_per_shot_deg", lab.aim_climb_yaw_per_shot_deg))
			lab.aim_climb_max_pitch_deg = float(fire_values.get("aim_climb_max_pitch_deg", lab.aim_climb_max_pitch_deg))
			lab.aim_climb_max_yaw_deg = float(fire_values.get("aim_climb_max_yaw_deg", lab.aim_climb_max_yaw_deg))
			lab.aim_climb_recovery_delay_seconds = float(fire_values.get("aim_climb_recovery_delay_seconds", lab.aim_climb_recovery_delay_seconds))
			lab.aim_climb_recovery_speed_deg_per_second = float(fire_values.get("aim_climb_recovery_speed_deg_per_second", lab.aim_climb_recovery_speed_deg_per_second))
			lab.crouch_spread_multiplier = float(fire_values.get("crouch_spread_multiplier", lab.crouch_spread_multiplier))
			lab.crouch_bloom_per_shot_deg = float(fire_values.get("crouch_bloom_per_shot_deg", lab.crouch_bloom_per_shot_deg))
			lab.crouch_max_recoil_bloom_deg = float(fire_values.get("crouch_max_recoil_bloom_deg", lab.crouch_max_recoil_bloom_deg))
			lab.crouch_bloom_recovery_speed = float(fire_values.get("crouch_bloom_recovery_speed", lab.crouch_bloom_recovery_speed))
			lab.magazine_capacity = int(fire_values.get("magazine_capacity", lab.magazine_capacity))
			lab.reserve_ammo = int(fire_values.get("reserve_ammo", lab.reserve_ammo))
			lab.is_silenced = bool(fire_values.get("is_silenced", lab.is_silenced))
		var reticle: Variant = d.get("reticle", {})
		if reticle is Dictionary:
			var reticle_values := reticle as Dictionary
			lab.reticle_base_gap_px = float(reticle_values.get("base_gap_px", lab.reticle_base_gap_px))
			lab.reticle_max_gap_px = float(reticle_values.get("max_gap_px", lab.reticle_max_gap_px))
			lab.reticle_response_speed = float(reticle_values.get("response_speed", lab.reticle_response_speed))
			lab.reticle_shot_kick_px = float(reticle_values.get("shot_kick_px", lab.reticle_shot_kick_px))
			lab.reticle_shot_kick_return = float(reticle_values.get("shot_kick_return", lab.reticle_shot_kick_return))
			lab.reticle_maximum_shot_kick_px = float(reticle_values.get("maximum_shot_kick_px", lab.reticle_maximum_shot_kick_px))
			lab.reticle_maximum_movement_tick_extension_px = float(reticle_values.get(
				"maximum_movement_tick_extension_px",
				lab.reticle_maximum_movement_tick_extension_px
			))
		lab.catalog_fire_modes.clear()
		for mode: Variant in (d.get("fire_modes", lab.catalog_fire_modes) as Array):
			lab.catalog_fire_modes.append(String(mode))
		lab.catalog_default_fire_mode = String(
			d.get("default_fire_mode", lab.catalog_fire_modes[0] if not lab.catalog_fire_modes.is_empty() else "semi")
		)
		lab.catalog_burst_size = clampi(int(d.get("burst_size", 3)), 2, 3)
		var composure_profile: Variant = d.get("composure", {})
		if composure_profile is Dictionary:
			var composure_values := composure_profile as Dictionary
			lab.composure.configure_weapon(composure_values)
			lab.composure_opening_stress_multiplier = float(
				composure_values.get(
					"opening_stress_multiplier",
					lab.composure_opening_stress_multiplier
				)
			)
			lab.composure_graze_damage_scale = float(
				composure_values.get(
					"graze_damage_scale",
					lab.composure_graze_damage_scale
				)
			)
		# normalized_scale is the final scale consumed by canonical gameplay. The
		# editor multiplier is only the temporary ratio used while moving the scale
		# control; saved profiles already fold it into normalized_scale. Restoring
		# both values multiplied the scale twice in Gunsmith while main.tscn used the
		# correct single normalized value.
		if d.has("normalized_scale"):
			lab.auto_normalized_scale = maxf(
				float(d.get("normalized_scale", lab.auto_normalized_scale)),
				0.000001
			)
			lab.user_scale_multiplier = 1.0
		elif d.has("user_scale_multiplier"):
			lab.user_scale_multiplier = float(
				d.get("user_scale_multiplier", lab.user_scale_multiplier)
			)
		lab._sync_weapon_transform(false)
	lab._load_weapon_contact_graph_profile(d.get("weapon_contact_graph", {}))
	refresh_fire_controls(lab)
	lab._sync_eye_sight_controls()


static func reset_fire_defaults(lab: Node) -> void:
	lab.fire_rate_rpm = 650
	lab.damage_per_shot = 34
	lab.headshot_multiplier = 3.5
	lab.muzzle_velocity_mps = default_muzzle_velocity_mps(lab)
	lab.is_silenced = false
	lab.base_spread_deg = 0.28
	lab.moving_spread_deg = 0.95
	lab.full_gait_spread_deg = 1.55
	lab.opening_burst_motion_multiplier = 0.35
	lab.bloom_per_shot_deg = 0.32
	lab.bloom_recovery_speed = 10.0
	lab.max_recoil_bloom_deg = 2.4
	lab.functional_aim_climb_enabled = false
	lab.aim_climb_pitch_per_shot_deg = 0.35
	lab.aim_climb_yaw_per_shot_deg = 0.0
	lab.aim_climb_max_pitch_deg = 3.5
	lab.aim_climb_max_yaw_deg = 0.75
	lab.aim_climb_recovery_delay_seconds = 0.10
	lab.aim_climb_recovery_speed_deg_per_second = 6.0
	lab.crouch_spread_multiplier = 0.72
	lab.crouch_bloom_per_shot_deg = 1.35
	lab.crouch_max_recoil_bloom_deg = 1.70
	lab.crouch_bloom_recovery_speed = 18.0
	lab.magazine_capacity = 30
	lab.reserve_ammo = 90
	lab.reticle_base_gap_px = 10.0
	lab.reticle_max_gap_px = 46.0
	lab.reticle_response_speed = 24.0
	lab.reticle_shot_kick_px = 10.5
	lab.reticle_shot_kick_return = 18.0
	lab.reticle_maximum_shot_kick_px = 12.5
	lab.reticle_maximum_movement_tick_extension_px = 16.0
	lab.composure = OperatorComposureScript.new()
	lab.composure_opening_stress_multiplier = 0.28
	lab.composure_graze_damage_scale = 0.38
	lab.current_bloom = 0.0
	lab.burst_shot_count = 0


static func refresh_fire_controls(lab: Node) -> void:
	if lab.fire_profile_title:
		lab.fire_profile_title.text = "RETICLE & FIRE — %s" % lab.weapon_display_name
	if lab.composure_profile_title:
		lab.composure_profile_title.text = "COMPOSURE — %s" % lab.weapon_display_name
	lab._update_slider_value("rpm", float(lab.fire_rate_rpm))
	lab._update_slider_value("dmg", float(lab.damage_per_shot))
	lab._update_slider_value("headshot_multiplier", lab.headshot_multiplier)
	lab._update_slider_value("muzzle_velocity", lab.muzzle_velocity_mps)
	lab._update_slider_value("base_spread", lab.base_spread_deg)
	lab._update_slider_value("moving_spread", lab.moving_spread_deg)
	lab._update_slider_value("full_gait_spread", lab.full_gait_spread_deg)
	lab._update_slider_value("opening_motion_control", lab.opening_burst_motion_multiplier)
	lab._update_slider_value("bloom", lab.bloom_per_shot_deg)
	lab._update_slider_value("max_bloom", lab.max_recoil_bloom_deg)
	lab._update_slider_value("rec", lab.bloom_recovery_speed)
	lab._update_slider_value("aim_climb_per_shot", lab.aim_climb_pitch_per_shot_deg)
	lab._update_slider_value("aim_climb_limit", lab.aim_climb_max_pitch_deg)
	lab._update_slider_value("aim_climb_yaw", lab.aim_climb_yaw_per_shot_deg)
	lab._update_slider_value("aim_climb_yaw_limit", lab.aim_climb_max_yaw_deg)
	lab._update_slider_value("aim_climb_delay", lab.aim_climb_recovery_delay_seconds)
	lab._update_slider_value("aim_climb_recovery", lab.aim_climb_recovery_speed_deg_per_second)
	lab._update_slider_value("crouch_spread", lab.crouch_spread_multiplier)
	lab._update_slider_value("crouch_bloom", lab.crouch_bloom_per_shot_deg)
	lab._update_slider_value("crouch_max_bloom", lab.crouch_max_recoil_bloom_deg)
	lab._update_slider_value("crouch_recovery", lab.crouch_bloom_recovery_speed)
	lab._update_slider_value("magazine_capacity", float(lab.magazine_capacity))
	lab._update_slider_value("reserve_ammo", float(lab.reserve_ammo))
	lab._update_slider_value("reticle_base", lab.reticle_base_gap_px)
	lab._update_slider_value("reticle_max", lab.reticle_max_gap_px)
	lab._update_slider_value("reticle_response", lab.reticle_response_speed)
	lab._update_slider_value("reticle_kick", lab.reticle_shot_kick_px)
	lab._update_slider_value("reticle_return", lab.reticle_shot_kick_return)
	lab._update_slider_value("reticle_kick_limit", lab.reticle_maximum_shot_kick_px)
	lab._update_slider_value("reticle_movement_length", lab.reticle_maximum_movement_tick_extension_px)
	lab._update_slider_value("composure_shot_stress", lab.composure.shot_stress)
	lab._update_slider_value("composure_movement_stress", lab.composure.movement_stress)
	lab._update_slider_value("composure_turning_stress", lab.composure.turning_stress)
	lab._update_slider_value("composure_attack", lab.composure.stress_attack_speed)
	lab._update_slider_value("composure_recovery", lab.composure.recovery_speed)
	lab._update_slider_value("composure_core", lab.composure.minimum_core_scale)
	lab._update_slider_value("composure_spring", lab.composure.visual_spring)
	lab._update_slider_value("composure_damping", lab.composure.visual_damping)
	lab._update_slider_value("composure_bounce_time", lab.composure.shot_bounce_duration)
	lab._update_slider_value("composure_bounce_strength", lab.composure.shot_bounce_strength)
	lab._update_slider_value("composure_opening", lab.composure_opening_stress_multiplier)
	lab._update_slider_value("composure_moving_first", lab.composure.moving_first_shot_multiplier)
	lab._update_slider_value("composure_second", lab.composure.second_shot_multiplier)
	lab._update_slider_value("composure_graze", lab.composure_graze_damage_scale)
	lab._apply_reticle_preview_profile()


static func default_muzzle_velocity_mps(lab: Node) -> float:
	match lab.selected_category:
		"Pistols", "Revolvers": return 350.0
		"SMGs": return 400.0
		"Shotguns": return 420.0
		"Sniper Rifles": return 850.0
		_: return 715.0
