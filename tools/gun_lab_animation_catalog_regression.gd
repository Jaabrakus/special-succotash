extends SceneTree

var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var packed := load("res://gun_calibration_lab.tscn") as PackedScene
	_expect(packed != null, "gun calibration lab scene loads")
	if packed == null:
		_finish()
		return

	var lab := packed.instantiate()
	root.add_child(lab)
	for _frame in range(20):
		await process_frame

	var entries: Array = lab.get("all_animation_entries")
	var picker := lab.get("all_animation_select") as OptionButton
	var gun_tabs := lab.find_child("GunLabTabs", true, false) as TabContainer
	var reticle_preview := lab.find_child("SharedWeaponReticlePreview", true, false)
	_expect(gun_tabs != null and gun_tabs.get_tab_count() == 3, "gun lab exposes rig, firing, and composure tabs")
	_expect(
		gun_tabs != null and gun_tabs.get_tab_title(1) == "Reticle & Fire",
		"the second gun tab edits reticle and fire behavior"
	)
	_expect(
		gun_tabs != null and gun_tabs.get_tab_title(2) == "Composure",
		"the third gun tab edits the shared composure profile"
	)
	_expect(reticle_preview != null, "gun lab previews the shared gameplay reticle")
	_expect(
		lab.get("runtime_posture_layer") != null,
		"gun lab uses the gameplay squared-shoulder posture layer"
	)
	_expect(
		float(lab.get("preview_hip_level_trim_deg")) >= 4.0,
		"gun lab levels the presentation hips without rewriting source clips"
	)
	_expect(
		bool(lab.get("show_bullet_velocity"))
		and lab.find_child("BulletVelocityToggle", true, false) != null,
		"physical bullet velocity is visible and user-toggleable"
	)
	_expect(
		lab.find_child("StanceStanding", true, false) != null
		and lab.find_child("StanceCrouched", true, false) != null
		and lab.find_child("StanceProne", true, false) != null,
		"stand crouch and prone controls are available in the firing tab"
	)
	var viewport_center: Vector2 = lab.get_viewport().get_visible_rect().size * 0.5
	var preview_center: Vector2 = (lab.call("_preview_screen_rect") as Rect2).get_center()
	var muzzle_sample: Dictionary = lab.call("_muzzle_axis_sample")
	var camera := lab.get("cam") as Camera3D
	var weapon := lab.get("current_weapon_mesh") as Node3D
	var muzzle_marker := lab.get("muzzle_marker") as MeshInstance3D
	var barrel_base := weapon.to_global(lab.call("_calibrated_barrel_base") as Vector3)
	var base_screen := camera.unproject_position(barrel_base)
	var muzzle_screen := camera.unproject_position(muzzle_marker.global_position)
	var reticle_screen := lab.call("_reticle_screen_position") as Vector2
	var screen_barrel_direction := (muzzle_screen - base_screen).normalized()
	var screen_reticle_direction := (reticle_screen - muzzle_screen).normalized()
	_expect(
		screen_barrel_direction.dot(screen_reticle_direction) > 0.999
		and absf(reticle_screen.distance_to(muzzle_screen) - 84.0) < 0.1
		and preview_center.x > viewport_center.x,
		"gun lab reticle sits directly ahead of the physical red muzzle socket"
	)
	var barrel_direction_before_grip_move := lab.call("_barrel_direction_world") as Vector3
	var original_right_grip := lab.get("right_grip_local_pos") as Vector3
	lab.set("right_grip_local_pos", original_right_grip + Vector3(0.0, 0.45, 0.30))
	var barrel_direction_after_grip_move := lab.call("_barrel_direction_world") as Vector3
	lab.set("right_grip_local_pos", original_right_grip)
	_expect(
		barrel_direction_before_grip_move.angle_to(barrel_direction_after_grip_move) < 0.00001,
		"hand-grip placement cannot bend the barrel or bullet velocity"
	)
	_expect(
		absf(
			(lab.call("_bullet_velocity_vector") as Vector3).length()
			- float(lab.get("muzzle_velocity_mps"))
		) < 0.01,
		"green vector magnitude represents the saved muzzle velocity"
	)
	var muzzle_target_before_orbit := Vector3(muzzle_sample.get("position", Vector3.ZERO))
	lab.set("cam_yaw", float(lab.get("cam_yaw")) + 24.0)
	lab.call("_update_camera")
	var muzzle_target_after_orbit := Vector3(
		(lab.call("_muzzle_axis_sample") as Dictionary).get("position", Vector3.ZERO)
	)
	_expect(
		muzzle_target_before_orbit.distance_to(muzzle_target_after_orbit) < 0.001,
		"orbiting the Gunsmith camera cannot steer the muzzle reticle in world space"
	)
	await process_frame
	var aim_sample: Dictionary = lab.call("_camera_aim_sample")
	_expect(
		Vector3(aim_sample.get("position", Vector3.ZERO)).distance_to(
			(lab.get("cam") as Camera3D).global_position
		) > 1.0,
		"center camera ray provides the firing-range aim authority"
	)
	lab.call("_update_fire_debug_lines")
	var fire_debug := lab.get("fire_debug_instance") as MeshInstance3D
	_expect(
		fire_debug != null and fire_debug.visible,
		"the physical muzzle visibly shares an axis with the bore reticle target"
	)
	if reticle_preview != null:
		reticle_preview.call("notify_shot", 3, 1.0)
		_expect(
			float(reticle_preview.get("shot_gap_impulse")) > 0.0
			and (reticle_preview.get("screen_center_override") as Vector2).distance_to(
				lab.call("_reticle_screen_position") as Vector2
			) < 0.01,
			"shot feedback expands symmetrically around the physical muzzle reticle"
		)
	lab.call("_set_preview_posture", &"CROUCHED")
	_expect(
		lab.get("preview_posture") == &"CROUCHED"
		and absf(float(lab.call("_stance_spread_multiplier")) - 0.60) < 0.001,
		"crouch preview applies the gameplay accuracy stance"
	)
	lab.call("_set_preview_posture", &"PRONE")
	_expect(
		lab.get("preview_posture") == &"PRONE"
		and absf(float(lab.call("_stance_spread_multiplier")) - 0.22) < 0.001,
		"prone preview applies the gameplay accuracy stance"
	)
	lab.call("_set_preview_posture", &"STANDING")
	lab.set("current_bloom", 1.0)
	lab.set("fire_cooldown", 0.2)
	lab.call("_update_bloom_recovery", 0.05, true)
	_expect(
		absf(float(lab.get("current_bloom")) - 1.0) < 0.001,
		"bloom does not sawtooth inward while the trigger is held"
	)
	lab.call("_update_bloom_recovery", 0.05, false)
	_expect(
		float(lab.get("current_bloom")) < 1.0,
		"bloom recovers toward center after trigger release"
	)
	lab.set("current_bloom", 0.0)
	lab.set("burst_shot_count", 0)
	lab.set("fire_cooldown", 0.0)
	lab.call("_fire_shot")
	var shot_origin: Vector3 = lab.get("last_shot_origin")
	var shot_end: Vector3 = lab.get("last_shot_end")
	var intended_direction := (
		Vector3((lab.call("_muzzle_axis_sample") as Dictionary).position) - shot_origin
	).normalized()
	var fired_direction := (shot_end - shot_origin).normalized()
	_expect(
		rad_to_deg(intended_direction.angle_to(fired_direction))
		<= float(lab.call("_current_total_spread_deg")) + 0.05,
		"Gunsmith shots follow the physical muzzle reticle instead of the orbit camera"
	)
	var reticle_profile: Dictionary = lab.call("_current_reticle_profile")
	_expect(
		reticle_profile.has("base_gap_px")
		and reticle_profile.has("shot_kick_px")
		and reticle_profile.has("maximum_shot_kick_px"),
		"reticle response is represented by a saveable per-gun profile"
	)
	_expect(lab.get("hand_gizmo_world") != null, "the evolved support-hand gizmo is live")
	_expect(lab.get("weapon_gizmo_world") != null, "the evolved weapon-mount gizmo is live")
	_expect(
		lab.get("handling_family_select") != null,
		"the evolved weapon-family animation mapper is present"
	)
	_expect(
		lab.get("animation_quality_results") != null,
		"the evolved animation compatibility audit is present"
	)
	_expect(entries.size() >= 200, "the lab catalogs every imported operator animation")
	_expect(
		picker != null and picker.item_count == entries.size(),
		"every cataloged animation is exposed in the inspector picker"
	)
	if entries.is_empty() or picker == null:
		lab.queue_free()
		_finish()
		return

	var selected_index := _find_representative_clip(entries)
	picker.select(selected_index)
	var entry: Dictionary = entries[selected_index]
	var clip_key := StringName(entry.get("key", &""))
	var resource_path := String(entry.get("path", ""))
	_expect(
		bool(lab.call("_ensure_preview_clip", clip_key)),
		"a catalog animation retargets onto the live gunsmith skeleton"
	)
	lab.set("selected_animation_key", clip_key)

	var expected_grip := Vector3(0.173, -0.041, 0.026)
	var expected_trigger := Vector3(-0.019, 0.012, 0.031)
	var expected_mount := Vector3(-0.014, 0.022, 0.009)
	lab.set("left_grip_local_pos", expected_grip)
	lab.set("right_grip_local_pos", expected_trigger)
	lab.set("grip_offset_pos", expected_mount)
	lab.call("_save_selected_animation_hand_map")
	var hand_maps: Dictionary = lab.get("animation_hand_maps")
	_expect(hand_maps.has(resource_path), "the selected clip receives its own hand map")

	lab.set("left_grip_local_pos", Vector3.ZERO)
	lab.set("right_grip_local_pos", Vector3.ZERO)
	lab.set("grip_offset_pos", Vector3.ZERO)
	lab.call("_apply_animation_hand_map", clip_key)
	_expect(
		(lab.get("left_grip_local_pos") as Vector3).is_equal_approx(expected_grip),
		"support-hand placement restores per animation"
	)
	_expect(
		(lab.get("right_grip_local_pos") as Vector3).is_equal_approx(expected_trigger),
		"trigger-hand grip restores per animation"
	)
	_expect(
		(lab.get("grip_offset_pos") as Vector3).is_equal_approx(expected_mount),
		"trigger-hand weapon mount restores per animation"
	)

	lab.queue_free()
	await process_frame
	_finish()


func _find_representative_clip(entries: Array) -> int:
	for index in range(entries.size()):
		var path := String((entries[index] as Dictionary).get("path", "")).to_lower()
		if "rifle" in path and "idle" in path:
			return index
	return 0


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("GUN_LAB_ANIMATION_CHECK PASS ", label)
	else:
		failures.append(label)
		push_error("GUN_LAB_ANIMATION_CHECK FAIL %s" % label)


func _finish() -> void:
	if failures.is_empty():
		print("GUN_LAB_ANIMATION_CATALOG_REGRESSION PASS")
		quit(0)
	else:
		print("GUN_LAB_ANIMATION_CATALOG_REGRESSION FAIL ", failures)
		quit(1)
