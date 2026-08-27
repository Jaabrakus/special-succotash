extends SceneTree

const GunsmithRecomCatalogAdapter := preload(
	"res://scripts/labs/gunsmith/gunsmith_recom_catalog_adapter.gd"
)

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
	var runtime_rig_controls := lab.find_child("RuntimeWeaponRigControls", true, false) as VBoxContainer
	var legacy_setup := lab.find_child("LegacyWeaponSetupCompatibility", true, false) as VBoxContainer
	var reticle_preview := lab.find_child("SharedWeaponReticlePreview", true, false)
	var live_aim_toggle := lab.find_child("LiveAimPreviewToggle", true, false) as CheckButton
	_expect(gun_tabs != null and gun_tabs.get_tab_count() == 3, "gun lab exposes rig, firing, and composure tabs")
	_expect(
		gun_tabs != null and gun_tabs.get_tab_title(0) == "Weapon Rig",
		"the first gun tab exposes only the runtime weapon-rig workflow"
	)
	_expect(
		runtime_rig_controls != null and runtime_rig_controls.visible,
		"the runtime weapon selector, model alignment, and sockets are visible"
	)
	_expect(
		legacy_setup != null and not legacy_setup.visible,
		"preview-only and animation-specific weapon setup controls stay hidden"
	)
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
		live_aim_toggle != null and live_aim_toggle.button_pressed,
		"Gunsmith exposes an enabled live yaw/pitch preview"
	)
	_expect(
		(lab.get("sliders_map") as Dictionary).has("live_weapon_yaw")
		and (lab.get("sliders_map") as Dictionary).has("live_weapon_pitch"),
		"Gunsmith exposes dedicated weapon yaw and pitch controls"
	)
	var muzzle_z_slider := (
		((lab.get("sliders_map") as Dictionary).get("mz_z", {}) as Dictionary).get("slider")
		as HSlider
	)
	_expect(
		muzzle_z_slider != null
		and muzzle_z_slider.min_value <= -1.60
		and muzzle_z_slider.max_value >= 1.60,
		"the muzzle controls include the complete saved weapon-local range"
	)
	var loaded_muzzle_position := lab.get("muzzle_local_pos") as Vector3
	var loaded_profile_value: Variant = GunsmithRecomCatalogAdapter.load_editable_profile(
		String(lab.get("weapon_name"))
	)
	var loaded_profile_muzzle: Dictionary = (
		((loaded_profile_value as Dictionary).get("weapon_sockets", {}) as Dictionary).get(
			"muzzle_socket", {}
		) as Dictionary
		if loaded_profile_value is Dictionary
		else {}
	)
	_expect(
		loaded_muzzle_position.is_equal_approx(Vector3(
			float(loaded_profile_muzzle.get("x", INF)),
			float(loaded_profile_muzzle.get("y", INF)),
			float(loaded_profile_muzzle.get("z", INF))
		)),
		"reopening Gunsmith restores the muzzle XYZ from the saved weapon profile"
	)
	var positive_z_muzzle_probe := Vector3(0.111, 0.123, 0.424)
	lab.set("muzzle_local_pos", positive_z_muzzle_probe)
	var serialized_socket_probe := lab.call("_weapon_sockets_save_data") as Dictionary
	var serialized_muzzle_probe: Dictionary = serialized_socket_probe.get("muzzle_socket", {})
	_expect(
		Vector3(
			float(serialized_muzzle_probe.get("x", 0.0)),
			float(serialized_muzzle_probe.get("y", 0.0)),
			float(serialized_muzzle_probe.get("z", 0.0))
		).is_equal_approx(positive_z_muzzle_probe),
		"saving preserves the exact visible muzzle XYZ without replacing its Z value"
	)
	lab.set("muzzle_local_pos", loaded_muzzle_position)
	lab.call("_sync_ballistic_markers")
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
	lab.call("_fire_shot")
	await process_frame
	var attached_frame_editor = lab.get("animation_frame_editor")
	var standing_fire_clip := StringName(
		(lab.get("handling_profile") as Dictionary).get("animation_slots", {}).get(
			"fire_standing",
			""
		)
	)
	_expect(
		attached_frame_editor != null
		and bool(attached_frame_editor.get("active"))
		and bool(attached_frame_editor.get("playing"))
		and StringName(attached_frame_editor.get("clip_name")) == standing_fire_clip,
		"a Gunsmith shot attaches its mapped fire clip to the live frame editor"
	)
	lab.call("_toggle_current_animation_frame_editor")
	_expect(
		bool(attached_frame_editor.get("active"))
		and not bool(attached_frame_editor.get("playing"))
		and StringName(attached_frame_editor.get("clip_name")) == standing_fire_clip,
		"Edit Current pauses the attached fire clip instead of closing or guessing"
	)
	lab.call("_leave_animation_frame_editor")
	lab.call("_finish_preview_to_idle")
	lab.call("_toggle_current_animation_frame_editor")
	_expect(
		bool(attached_frame_editor.get("active"))
		and StringName(attached_frame_editor.get("clip_name")) == standing_fire_clip,
		"Edit Current reopens the explicit fire reaction after the preview returns to idle"
	)
	lab.call("_leave_animation_frame_editor")
	var viewport_center: Vector2 = lab.get_viewport().get_visible_rect().size * 0.5
	var preview_center: Vector2 = (lab.call("_preview_screen_rect") as Rect2).get_center()
	var muzzle_sample: Dictionary = lab.call("_muzzle_axis_sample")
	var camera := lab.get("cam") as Camera3D
	var muzzle_marker := lab.get("muzzle_marker") as MeshInstance3D
	var barrel_base_marker := lab.get("barrel_base_marker") as MeshInstance3D
	var barrel_base := barrel_base_marker.global_position
	var base_screen := camera.unproject_position(barrel_base)
	var muzzle_screen := camera.unproject_position(muzzle_marker.global_position)
	var muzzle_press := InputEventMouseButton.new()
	muzzle_press.button_index = MOUSE_BUTTON_LEFT
	muzzle_press.pressed = true
	muzzle_press.position = muzzle_screen
	lab.call("_input", muzzle_press)
	_expect(
		bool(lab.get("authoring_pointer_down"))
		and not bool(lab.get("mouse_fire_armed"))
		and not bool(lab.get("fire_input_held"))
		and String(lab.get("dragged_dot_id")) == "muzzle",
		"the red muzzle marker owns the press and never arms mouse fire"
	)
	var muzzle_release := InputEventMouseButton.new()
	muzzle_release.button_index = MOUSE_BUTTON_LEFT
	muzzle_release.pressed = false
	muzzle_release.position = muzzle_screen
	lab.call("_input", muzzle_release)
	var reticle_screen := lab.call("_reticle_screen_position") as Vector2
	_expect(
		reticle_screen.distance_to(preview_center) < 0.1
		and preview_center.x > viewport_center.x,
		"gun lab reticle stays fixed at the playable preview center"
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
	lab.call("_update_weapon_master_anchor")
	var barrel_direction_before_live_aim := lab.call("_barrel_direction_world") as Vector3
	var trigger_position_before_live_aim := (lab.get("right_grip_marker") as Node3D).global_position
	var camera_transform_before_live_aim := camera.global_transform
	lab.set("live_weapon_yaw_deg", 24.0)
	lab.set("live_weapon_pitch_deg", -12.0)
	lab.call("_update_live_aim_weapon_pose")
	lab.call("_solve_trigger_hand_engine")
	var barrel_direction_after_live_aim := lab.call("_barrel_direction_world") as Vector3
	var live_rotation_deg := rad_to_deg(
		barrel_direction_before_live_aim.angle_to(barrel_direction_after_live_aim)
	)
	var live_trigger_error := trigger_position_before_live_aim.distance_to(
		(lab.get("right_grip_marker") as Node3D).global_position
	)
	var live_camera_error := camera_transform_before_live_aim.origin.distance_to(
		camera.global_transform.origin
	) + camera_transform_before_live_aim.basis.get_rotation_quaternion().angle_to(
		camera.global_transform.basis.get_rotation_quaternion()
	)
	print("GUN_LAB_LIVE_AIM_METRIC rotation_deg=%.2f trigger_error_m=%.5f camera_error=%.5f" % [
		live_rotation_deg,
		live_trigger_error,
		live_camera_error,
	])
	_expect(
		live_rotation_deg > 5.0
		and live_trigger_error < 0.001,
		"Gunsmith live preview rotates yaw/pitch around the attached trigger grip"
	)
	_expect(
		live_camera_error < 0.00001,
		"weapon yaw and pitch leave the Gunsmith inspection camera fixed"
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
			"shot feedback expands symmetrically around the fixed center reticle"
		)
	lab.call("_set_preview_posture", &"CROUCHED")
	for _frame in range(16):
		await process_frame
	var crouch_grip_error := (lab.get("right_grip_marker") as Node3D).global_position.distance_to(
		lab.call("_right_palm_contact_world") as Vector3
	)
	print("GUN_LAB_CROUCH_TRIGGER_ERROR_M %.5f posture=%s spread=%.3f owner=%s support=%s" % [
		crouch_grip_error,
		String(lab.get("preview_posture")),
		float(lab.call("_stance_spread_multiplier")),
		String(lab.get("weapon_owner_state")),
		String(lab.get("support_hand_policy")),
	])
	_expect(
		lab.get("preview_posture") == &"CROUCHED"
		and absf(float(lab.call("_stance_spread_multiplier")) - 0.72) < 0.001
		and crouch_grip_error < 0.01,
		"crouch preview preserves the gameplay stance and trigger-hand attachment"
	)
	lab.call("_set_preview_posture", &"PRONE")
	for _frame in range(16):
		await process_frame
	var prone_grip_error := (lab.get("right_grip_marker") as Node3D).global_position.distance_to(
		lab.call("_right_palm_contact_world") as Vector3
	)
	print("GUN_LAB_PRONE_TRIGGER_ERROR_M %.5f" % prone_grip_error)
	_expect(
		lab.get("preview_posture") == &"PRONE"
		and absf(float(lab.call("_stance_spread_multiplier")) - 0.22) < 0.001
		and prone_grip_error < 0.01,
		"prone preview preserves the gameplay stance and trigger-hand attachment"
	)
	_expect(
		(lab.get("sliders_map") as Dictionary).has("right_elbow_x")
		and (lab.get("sliders_map") as Dictionary).has("left_elbow_z"),
		"both elbow IK poles expose persistent XYZ tuning controls"
	)
	_expect(
		lab.find_child("RightElbowIKPole", true, false) != null
		and lab.find_child("LeftElbowIKPole", true, false) != null
		and lab.find_child("ElbowSkeletonFrame", true, false) != null
		and lab.find_child("BodyJoint_head", true, false) != null
		and lab.find_child("BodyJoint_left_upper_arm", true, false) != null,
		"the Gunsmith exposes selectable elbow poles and upper-body joint markers"
	)
	lab.call("_set_preview_posture", &"STANDING")
	lab.call("_set_elbow_component", 0.12, &"left", &"x")
	lab.call("_set_preview_posture", &"CROUCHED")
	lab.call("_set_elbow_component", -0.08, &"left", &"x")
	lab.call("_set_preview_posture", &"STANDING")
	_expect(
		absf((lab.get("left_elbow_pole_offset") as Vector3).x - 0.12) < 0.001,
		"elbow-pole tuning restores independently for each stance"
	)
	var posture_layer = lab.get("runtime_posture_layer")
	posture_layer.call(
		"set_procedural_rotation_degrees",
		&"STANDING",
		&"head",
		Vector3(7.0, -4.0, 2.0)
	)
	lab.call("_set_preview_posture", &"CROUCHED")
	var crouched_head_rotation: Vector3 = posture_layer.call(
		"get_procedural_rotation_degrees", &"CROUCHED", &"head"
	)
	lab.call("_set_preview_posture", &"STANDING")
	var standing_head_rotation: Vector3 = posture_layer.call(
		"get_procedural_rotation_degrees", &"STANDING", &"head"
	)
	_expect(
		standing_head_rotation.is_equal_approx(Vector3(7.0, -4.0, 2.0))
		and not crouched_head_rotation.is_equal_approx(standing_head_rotation),
		"head and limb corrections carry across animations but remain stance-specific"
	)
	var neck_before: Vector3 = posture_layer.call(
		"get_procedural_rotation_degrees", &"STANDING", &"neck"
	)
	var upper_spine_before: Vector3 = posture_layer.call(
		"get_procedural_rotation_degrees", &"STANDING", &"spine2"
	)
	lab.call("_select_body_joint", &"head")
	lab.call("_adjust_selected_joint_rotation", Vector3(4.0, 0.0, 0.0))
	var neck_after: Vector3 = posture_layer.call(
		"get_procedural_rotation_degrees", &"STANDING", &"neck"
	)
	var upper_spine_after: Vector3 = posture_layer.call(
		"get_procedural_rotation_degrees", &"STANDING", &"spine2"
	)
	_expect(
		absf((neck_after - neck_before).x - 2.2) < 0.01
		and absf((upper_spine_after - upper_spine_before).x - 1.0) < 0.01,
		"head editing forms a bounded continuation arc through neck and upper spine"
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
		and reticle_profile.has("maximum_shot_kick_px")
		and reticle_profile.has("maximum_movement_tick_extension_px"),
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
	var fixed_weapon_mount := lab.get("grip_offset_pos") as Vector3
	lab.set("left_grip_local_pos", expected_grip)
	lab.set("right_grip_local_pos", expected_trigger)
	lab.call("_save_selected_animation_hand_map")
	var hand_maps: Dictionary = lab.get("animation_hand_maps")
	_expect(hand_maps.has(resource_path), "the selected clip receives its own hand map")

	lab.set("left_grip_local_pos", Vector3.ZERO)
	lab.set("right_grip_local_pos", Vector3.ZERO)
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
		(lab.get("grip_offset_pos") as Vector3).is_equal_approx(fixed_weapon_mount),
		"animation hand maps preserve the one weapon-level mount"
	)

	var standing_reload_frames := lab.find_child(
		"AnimationFrames_reload_standing",
		true,
		false
	) as Button
	_expect(
		standing_reload_frames != null,
		"each mapped action exposes one direct Frames button"
	)
	if standing_reload_frames != null:
		standing_reload_frames.pressed.emit()
		await process_frame
	var standing_reload_clip := StringName(
		(lab.get("handling_profile") as Dictionary).get("animation_slots", {}).get(
			"reload_standing",
			""
		)
	)
	_expect(
		attached_frame_editor != null
		and bool(attached_frame_editor.get("active"))
		and not bool(attached_frame_editor.get("playing"))
		and String(attached_frame_editor.get("slot_name")) == "reload_standing"
		and StringName(attached_frame_editor.get("clip_name")) == standing_reload_clip
		and int(attached_frame_editor.call("frame_index")) == 0,
		"the action button opens its exact lifecycle paused at frame zero"
	)
	_expect(
		not bool(lab.call("_gunsmith_live_aim_active")),
		"Frames mode freezes live aim so the selected lifecycle pose remains editable"
	)
	var shared_mount_rotation_before_frame_edit := lab.get("grip_offset_rot") as Vector3
	var frame_barrel_before := lab.call("_barrel_direction_world") as Vector3
	var frame_trigger_error_before := (lab.get("right_grip_marker") as Node3D).global_position.distance_to(
		lab.call("_right_palm_contact_world") as Vector3
	)
	lab.call("_adjust_weapon_rotation", "pitch", 12.0)
	await process_frame
	var frame_barrel_after := lab.call("_barrel_direction_world") as Vector3
	var frame_trigger_error := (lab.get("right_grip_marker") as Node3D).global_position.distance_to(
		lab.call("_right_palm_contact_world") as Vector3
	)
	print("GUN_LAB_FRAME_WEAPON_METRIC correction_pitch=%.2f barrel_rotation_deg=%.2f trigger_before_m=%.5f trigger_after_m=%.5f shared_mount_delta_deg=%.3f" % [
		(lab.get("animation_frame_weapon_rotation_correction_deg") as Vector3).x,
		rad_to_deg(frame_barrel_before.angle_to(frame_barrel_after)),
		frame_trigger_error_before,
		frame_trigger_error,
		shared_mount_rotation_before_frame_edit.distance_to(
			lab.get("grip_offset_rot") as Vector3
		),
	])
	_expect(
		absf((lab.get("animation_frame_weapon_rotation_correction_deg") as Vector3).x - 12.0) < 0.001
		and (lab.get("grip_offset_rot") as Vector3).is_equal_approx(
			shared_mount_rotation_before_frame_edit
		)
		and rad_to_deg(frame_barrel_before.angle_to(frame_barrel_after)) > 5.0
		and frame_trigger_error < 0.01,
		"reload-frame weapon rotation follows the muzzle axis around the attached hand without changing the shared mount"
	)
	lab.call("_capture_animation_frame_pose_key")
	var reload_frame_pose := attached_frame_editor.call("current_pose") as Dictionary
	_expect(
		reload_frame_pose.has("weapon_hand_rotation_correction_deg")
		and absf(float(
			(reload_frame_pose.get("weapon_hand_rotation_correction_deg", {}) as Dictionary).get("x", 0.0)
		) - 12.0) < 0.001,
		"the weapon correction is stored only in the selected reload clip and frame"
	)
	var reload_clip_keys: Dictionary = (
		(attached_frame_editor.get("pose_keys") as Dictionary).get(
			String(standing_reload_clip),
			{}
		) as Dictionary
	)
	var reload_terminal_pose: Dictionary = reload_clip_keys.get(
		str(attached_frame_editor.call("frame_count")),
		{}
	)
	var terminal_weapon_rotation: Dictionary = reload_terminal_pose.get(
		"weapon_hand_rotation_correction_deg",
		{}
	)
	_expect(
		absf(float(terminal_weapon_rotation.get("x", 1.0))) < 0.001
		and absf(float(terminal_weapon_rotation.get("y", 1.0))) < 0.001
		and absf(float(terminal_weapon_rotation.get("z", 1.0))) < 0.001,
		"reload weapon pitch and yaw automatically return to aim-idle neutral on the final frame"
	)
	var frame_editor_skeleton := lab.get("skeleton") as Skeleton3D
	var paused_frame_pose := _snapshot_skeleton_pose(frame_editor_skeleton)
	for _paused_update in range(12):
		await process_frame
	_expect(
		_skeleton_pose_matches(frame_editor_skeleton, paused_frame_pose),
		"a paused lifecycle frame stays fixed while runtime posture and IK update"
	)
	_expect(
		lab.find_child("AnimationFrameLifecycle", true, false) != null
		and lab.find_child("SetAnimationCorrectionKey", true, false) != null
		and lab.find_child("SaveApplyAnimationRig", true, false) != null,
		"the selected action exposes its frame ruler, correction key, and save/apply control"
	)
	lab.call("_toggle_animation_frame_editor_playback")
	await process_frame
	var editing_muzzle_screen := camera.unproject_position(muzzle_marker.global_position)
	var editing_muzzle_press := InputEventMouseButton.new()
	editing_muzzle_press.button_index = MOUSE_BUTTON_LEFT
	editing_muzzle_press.pressed = true
	editing_muzzle_press.position = editing_muzzle_screen
	lab.call("_input", editing_muzzle_press)
	_expect(
		not bool(attached_frame_editor.get("playing"))
		and not bool(lab.get("fire_input_held"))
		and String(lab.get("dragged_dot_id")) == "muzzle",
		"grabbing a rig control pauses the lifecycle on the visible frame without firing"
	)
	await process_frame
	var pose_before_muzzle_drag := _snapshot_skeleton_pose(frame_editor_skeleton)
	var muzzle_before_drag := muzzle_marker.global_position
	lab.call(
		"_apply_dot_world_drag",
		"muzzle",
		muzzle_before_drag + camera.global_basis.x.normalized() * 0.08
	)
	for _muzzle_drag_update in range(4):
		await process_frame
	_expect(
		muzzle_marker.global_position.distance_to(muzzle_before_drag) > 0.01
		and _skeleton_pose_matches(frame_editor_skeleton, pose_before_muzzle_drag),
		"dragging the muzzle moves only the ballistic socket and preserves the paused model pose"
	)
	var editing_muzzle_release := InputEventMouseButton.new()
	editing_muzzle_release.button_index = MOUSE_BUTTON_LEFT
	editing_muzzle_release.pressed = false
	editing_muzzle_release.position = editing_muzzle_screen
	lab.call("_input", editing_muzzle_release)

	lab.queue_free()
	await process_frame
	_finish()


func _find_representative_clip(entries: Array) -> int:
	for index in range(entries.size()):
		var path := String((entries[index] as Dictionary).get("path", "")).to_lower()
		if "rifle" in path and "idle" in path:
			return index
	return 0


func _snapshot_skeleton_pose(skeleton: Skeleton3D) -> Array[Transform3D]:
	var poses: Array[Transform3D] = []
	if skeleton == null:
		return poses
	for bone_index in range(skeleton.get_bone_count()):
		poses.append(skeleton.get_bone_pose(bone_index))
	return poses


func _skeleton_pose_matches(skeleton: Skeleton3D, expected: Array[Transform3D]) -> bool:
	if skeleton == null or skeleton.get_bone_count() != expected.size():
		return false
	for bone_index in range(expected.size()):
		if not skeleton.get_bone_pose(bone_index).is_equal_approx(expected[bone_index]):
			return false
	return true


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
