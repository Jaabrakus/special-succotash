extends SceneTree

var failures: Array[String] = []


func _initialize() -> void:
	var packed := load("res://animation_library_lab.tscn") as PackedScene
	_expect(packed != null, "Animation Studio scene loads")
	if packed == null:
		_finish()
		return
	var studio := packed.instantiate()
	root.add_child(studio)
	await process_frame
	await process_frame
	var pose_button := studio.find_child("PoseModeButton", true, false) as Button
	var picker := studio.find_child("AnimationRigJointPicker", true, false) as OptionButton
	var toggle := studio.find_child("AnimationCorrectionOverlayToggle", true, false) as CheckButton
	var panel := studio.find_child("AnimationCorrectionControls", true, false) as Control
	var save_button := studio.find_child("SaveAnimationCorrectionKey", true, false) as Button
	var delete_button := studio.find_child("DeleteAnimationCorrectionKey", true, false) as Button
	_expect(
		str(studio.get("current_category")) == "LIVE IN GAME",
		"Animation Studio opens on the approved playable set"
	)
	var opening_entries: Array = studio.get("filtered_entries")
	var opening_index := int(studio.get("clip_index"))
	_expect(
		not opening_entries.is_empty()
		and opening_index >= 0
		and opening_index < opening_entries.size()
		and String((opening_entries[opening_index] as Dictionary).get("path", ""))
		== "res://assets/animations/mixamo/Shooter Pack/rifle aiming idle.fbx",
		"Animation Studio opens on the approved aim-idle pose"
	)
	_expect(pose_button != null and pose_button.text == "Rig & Hands", "Pose workspace is labeled Rig & Hands")
	_expect(picker != null and picker.item_count >= 22, "shared joint picker includes arms, hands, and complete legs")
	_expect(toggle != null, "animation rig correction toggle exists")
	_expect(panel != null and not panel.visible, "rig controls start safely collapsed")
	_expect(save_button != null and delete_button != null, "correction key controls exist")
	if toggle and panel:
		studio.call("_show_editor_page", "Pose")
		await process_frame
		var aim_reticle := studio.find_child(
			"AnimationStudioAimReferenceReticle", true, false
		) as Control
		_expect(
			aim_reticle != null and aim_reticle.visible,
			"Rig & Hands shows the fixed Studio aim-reference reticle"
		)
		if aim_reticle != null:
			var expected_center: Vector2 = studio.call("_animation_workbench_center_screen")
			var actual_center: Vector2 = aim_reticle.call("get_authoritative_center")
			_expect(
				actual_center.is_equal_approx(expected_center),
				"Studio reticle stays centered in the unobstructed model workbench"
			)
		_expect(not panel.visible, "Rig & Hands keeps corrections opt-in")
		studio.call("_update_animation_rig_visual_overlay")
		var reference_overlay := studio.find_child(
			"AnimationStudioGunsmithRigOverlay", true, false
		) as Node3D
		var reference_joint := studio.find_child(
			"FineJoint_left_upper_leg", true, false
		) as Node3D
		var reference_blue_origin := studio.find_child(
			"GunPlacementLineOrigin", true, false
		) as Node3D
		_expect(
			reference_overlay != null and reference_overlay.visible
			and reference_joint != null and reference_joint.visible
			and reference_blue_origin != null and reference_blue_origin.visible,
			"Rig & Hands shows joint and blue-line reference nodes before corrections are enabled"
		)
		studio.call("_toggle_animation_correction_overlay", true)
		toggle.set_pressed_no_signal(true)
		await process_frame
		_expect(panel.visible, "explicit correction mode opens the rig controls")
		await process_frame
		var rig_overlay := studio.find_child("AnimationStudioGunsmithRigOverlay", true, false) as Node3D
		_expect(rig_overlay != null and rig_overlay.visible, "one-for-one Gunsmith rig overlay is visible")
		studio.call("_set_animation_preview_ownership", {
			"display": "Crouch Run Backwards",
			"key": "raw_crouch_run_backwards",
			"path": "res://assets/animations/mixamo/Crouch Run Backwards.fbx",
		})
		_expect(
			not studio.call("_animation_preview_uses_ready_hand_solver"),
			"unclassified clips cannot activate gameplay rifle grip correction"
		)
		studio.call("_set_animation_preview_ownership", {
			"display": "Reload",
			"key": "reload",
			"path": "res://assets/animations/mixamo/Reloading.fbx",
		})
		studio.call("_sync_animation_preview_weapon_parent")
		studio.call("_update_animation_rig_visual_overlay")
		_expect(
			studio.get("animation_preview_weapon_owner")
			== &"RELOAD_RIGHT_HAND",
			"reload preview gives the authored action ownership of the arms"
		)
		var action_weapon := studio.get("weapon_node") as Node3D
		var action_attachment := studio.get("socket_attachment") as BoneAttachment3D
		_expect(
			action_weapon != null and action_weapon.get_parent() == action_attachment,
			"action clips return weapon ownership to the authored right hand"
		)
		var action_right_hand := studio.find_child("RightHandGripTarget", true, false) as Node3D
		var action_right_elbow := studio.find_child("RightElbowIKPole", true, false) as Node3D
		_expect(
			action_right_hand != null and not action_right_hand.visible
			and action_right_elbow != null and not action_right_elbow.visible,
			"action clips do not connect both elbows to rifle grip targets"
		)
		studio.call("_set_animation_preview_ownership", {
			"display": "[Rifle] Idle",
			"key": "idle_rifle",
			"path": "res://assets/animations/mixamo/Lite Rifle Pack/idle.fbx",
		})
		studio.call("_sync_animation_preview_weapon_parent")
		studio.call("_update_animation_rig_visual_overlay")
		_expect(
			studio.call("_animation_preview_uses_ready_hand_solver"),
			"ready rifle clips reconnect the two-hand grip solver"
		)
		var ready_weapon := studio.get("weapon_node") as Node3D
		var studio_player := studio.get("animation_player") as AnimationPlayer
		var pause_time_before := studio_player.current_animation_position if studio_player != null else -1.0
		studio.call("_pause_for_pose_edit")
		var pause_time_immediate := studio_player.current_animation_position if studio_player != null else -1.0
		for _settle_frame in range(3):
			await process_frame
		print(
			"ANIMATION_RIG_PAUSE_TIME before=%.4f immediate=%.4f settled=%.4f" % [
				pause_time_before,
				pause_time_immediate,
				studio_player.current_animation_position if studio_player != null else -1.0,
			]
		)
		var paused_weapon_transform := ready_weapon.global_transform if ready_weapon != null else Transform3D.IDENTITY
		for _solve_index in range(8):
			studio.call("_apply_two_hand_ik")
			await process_frame
		if ready_weapon != null:
			print(
				"ANIMATION_RIG_PAUSE_METRIC position_delta=%.6f basis_equal=%s" % [
					ready_weapon.global_position.distance_to(paused_weapon_transform.origin),
					str(ready_weapon.global_basis.is_equal_approx(paused_weapon_transform.basis)),
				]
			)
		_expect(
			ready_weapon != null
			and ready_weapon.global_transform.is_equal_approx(paused_weapon_transform),
			"paused Ready Aim keeps a stable rifle instead of entering a hand-to-weapon feedback loop"
		)
		_expect(
			ready_weapon != null
			and ready_weapon.get_parent() == action_attachment,
			"ready clips preserve the exact Gunsmith right-hand mount"
		)
		if ready_weapon != null and action_attachment != null:
			var gunsmith_mount := ready_weapon.transform
			studio.call("_set_animation_preview_ownership", {
				"display": "Reload",
				"key": "reload",
				"path": "res://assets/animations/mixamo/Reloading.fbx",
			})
			studio.call("_sync_animation_preview_weapon_parent")
			print(
				"ANIMATION_RIG_MOUNT_METRIC position_delta=%.6f basis_equal=%s" % [
					ready_weapon.position.distance_to(gunsmith_mount.origin),
					str(ready_weapon.basis.is_equal_approx(gunsmith_mount.basis)),
				]
			)
			studio.call("_set_animation_preview_ownership", {
				"display": "[Rifle] Idle",
				"key": "idle_rifle",
				"path": "res://assets/animations/mixamo/Lite Rifle Pack/idle.fbx",
			})
			studio.call("_sync_animation_preview_weapon_parent")
			_expect(
				ready_weapon.get_parent() == action_attachment
				and ready_weapon.transform.is_equal_approx(gunsmith_mount),
				"state changes preserve the saved Gunsmith mount without reparenting"
			)
		var trigger_pole := studio.find_child("RightElbowIKPole", true, false) as Node3D
		var support_pole := studio.find_child("LeftElbowIKPole", true, false) as Node3D
		_expect(trigger_pole != null and not trigger_pole.visible, "trigger arm stays owned by the imported animation")
		_expect(support_pole != null and support_pole.visible, "support elbow correction is visible in Studio")
		_expect(studio.find_child("Socket_Muzzle", true, false) != null, "muzzle socket marker is visible in Studio")
		_expect(studio.find_child("Socket_Optic", true, false) != null, "optic rail marker is visible in Studio")
		_expect(studio.find_child("GunPlacementLineOrigin", true, false) != null, "blue placement origin is visible in Studio")
		_expect(studio.find_child("GunPlacementDirectionHandle", true, false) != null, "blue placement direction handle is visible in Studio")
		_expect(studio.find_child("GunsmithRigReferenceLines", true, false) != null, "barrel rail and placement lines are present")
		_expect(studio.find_child("FineJoint_left_upper_leg", true, false) != null, "small left thigh node is visible")
		_expect(studio.find_child("FineJoint_right_lower_leg", true, false) != null, "small right knee node is visible")
		_expect(studio.find_child("FineJoint_left_foot", true, false) != null, "small left ankle node is visible")
		_expect(studio.find_child("FineJoint_right_toe", true, false) != null, "small right toe node is visible")
		var large_knee := studio.find_child("Bubble_RIGHT_KNEE", true, false) as Node3D
		_expect(large_knee != null and not large_knee.visible, "old large anatomical nodes are hidden in Rig & Hands")
		var weapon_mount_button := studio.find_child("SelectWeaponMount", true, false) as Button
		var left_hand_button := studio.find_child("SelectLeftHand", true, false) as Button
		var left_elbow_button := studio.find_child("SelectLeftElbowPole", true, false) as Button
		var blue_dot_button := studio.find_child("SelectPlacementOrigin", true, false) as Button
		var blue_aim_button := studio.find_child("SelectPlacementDirection", true, false) as Button
		var elbow_toggle := studio.find_child("AnimationElbowGuidesToggle", true, false) as CheckButton
		_expect(
			weapon_mount_button != null and left_hand_button != null
			and left_elbow_button != null
			and blue_dot_button != null and blue_aim_button != null,
			"weapon mount, support arm, and both blue dots have explicit selectors"
		)
		_expect(elbow_toggle != null, "pink elbow guides have a labeled visibility toggle")
		if weapon_mount_button:
			weapon_mount_button.emit_signal("pressed")
			_expect(studio.get("animation_rig_selected_target") == &"weapon_mount", "weapon-mount selector replaces cyclic trigger-hand IK")
		if left_hand_button:
			left_hand_button.emit_signal("pressed")
			var left_before: Vector3 = studio.get("correction_left_hand")
			studio.call("_begin_animation_rig_target_drag", &"left_hand")
			studio.call("_drag_animation_rig_target_screen", &"left_hand", Vector2(-20.0, 10.0))
			var left_after: Vector3 = studio.get("correction_left_hand")
			_expect(left_after.x < left_before.x and left_after.y < left_before.y, "left-hand dot supports direct screen drag")
		if left_elbow_button:
			left_elbow_button.emit_signal("pressed")
			var left_elbow_before: Vector3 = studio.get("correction_left_elbow")
			studio.call("_begin_animation_rig_target_drag", &"left_elbow_pole")
			studio.call("_drag_animation_rig_target_screen", &"left_elbow_pole", Vector2(-18.0, 10.0))
			studio.call("_end_animation_rig_target_drag", &"left_elbow_pole")
			var left_elbow_after: Vector3 = studio.get("correction_left_elbow")
			_expect(
				left_elbow_after.x < left_elbow_before.x
				and left_elbow_after.y < left_elbow_before.y,
				"left elbow dot supports direct screen drag"
			)
		if blue_dot_button:
			blue_dot_button.emit_signal("pressed")
			var blue_before: Vector3 = studio.get("correction_placement_position")
			studio.call("_begin_animation_rig_target_drag", &"placement_origin")
			studio.call("_drag_animation_rig_target_screen", &"placement_origin", Vector2(12.0, -12.0))
			var blue_after: Vector3 = studio.get("correction_placement_position")
			_expect(blue_after.x > blue_before.x and blue_after.y > blue_before.y, "blue placement dot supports direct screen drag")
		if blue_aim_button:
			blue_aim_button.emit_signal("pressed")
			var aim_before: Vector3 = studio.get("correction_placement_rotation")
			studio.call("_begin_animation_rig_target_drag", &"placement_direction")
			studio.call("_drag_animation_rig_target_screen", &"placement_direction", Vector2(15.0, -10.0))
			var aim_after: Vector3 = studio.get("correction_placement_rotation")
			_expect(aim_after.is_equal_approx(aim_before), "far blue dot is locked to the reticle")
		if elbow_toggle:
			elbow_toggle.emit_signal("toggled", false)
			studio.call("_update_animation_rig_visual_overlay")
			var pink_elbow := studio.find_child("RightElbowIKPole", true, false) as Node3D
			_expect(pink_elbow != null and not pink_elbow.visible, "pink elbow guides can be hidden")
			elbow_toggle.emit_signal("toggled", true)
		var pose_gizmo := studio.find_child("PoseTransformGizmo", true, false) as Node3D
		var studio_camera := studio.get("camera") as Camera3D
		if pose_gizmo and studio_camera:
			var gizmo_screen := studio_camera.unproject_position(pose_gizmo.global_position)
			var viewport_size := root.get_visible_rect().size
			_expect(
				gizmo_screen.distance_to(Vector2(viewport_size.x * 0.72, viewport_size.y * 0.18)) < 3.0,
				"transform gizmo stays in the upper workbench corner"
			)
		var elbow_before: Vector3 = studio.get("correction_left_elbow")
		studio.call("_begin_animation_rig_target_drag", &"left_elbow_pole")
		studio.call("_drag_animation_rig_target", &"left_elbow_pole", "x", Vector2(40.0, 0.0), false)
		var elbow_after: Vector3 = studio.get("correction_left_elbow")
		_expect(
			elbow_after.x > elbow_before.x,
			"elbow pole is directly draggable"
		)
		var line_before: Vector3 = studio.get("correction_placement_rotation")
		studio.call("_begin_animation_rig_target_drag", &"placement_direction")
		studio.call("_drag_animation_rig_target", &"placement_direction", "y", Vector2(25.0, 0.0), true)
		var line_after: Vector3 = studio.get("correction_placement_rotation")
		_expect(
			is_equal_approx(line_after.y, line_before.y),
			"blue placement yaw cannot drift away from the reticle"
		)
		for item_index in range(picker.item_count):
			if String(picker.get_item_metadata(item_index)) == "head":
				studio.call("_select_animation_rig_joint", item_index)
				break
		var selected_head := String(studio.get("selected_pose_bone"))
		studio.call("_set_pose_slider_value", "rot_x", 8.0)
		var head_offsets: Dictionary = studio.get("bone_rot_offsets")
		_expect("head" in selected_head.to_lower(), "head is selectable from the shared skeleton rig")
		_expect(head_offsets.has(selected_head), "head rotation is editable on the current animation")
		for item_index in range(picker.item_count):
			if String(picker.get_item_metadata(item_index)) == "left_upper_leg":
				studio.call("_select_animation_rig_joint", item_index)
				break
		studio.call("_set_pose_slider_value", "rot_x", 12.0)
		var leg_pose: Dictionary = studio.call("_animation_correction_pose")
		var leg_rotations: Dictionary = leg_pose.get("joint_rotations", {})
		_expect(leg_rotations.has("left_upper_leg"), "small leg nodes write per-animation correction keys")
		var muzzle_marker := studio.get("weapon_muzzle_marker") as Marker3D
		if muzzle_marker:
			var muzzle_before := muzzle_marker.position
			studio.call("_begin_animation_rig_target_drag", &"muzzle")
			studio.call("_drag_animation_rig_target", &"muzzle", "x", Vector2(20.0, 0.0), false)
			studio.call("_store_animation_socket_reference")
			var edited_config: Dictionary = studio.get("gunsmith_weapon_config")
			var edited_muzzle := (
				edited_config.get("weapon_sockets", {}).get("muzzle_socket", {})
				as Dictionary
			)
			_expect(muzzle_marker.position.x > muzzle_before.x, "muzzle socket is directly draggable")
			_expect(
				absf(float(edited_muzzle.get("x", 0.0)) - muzzle_marker.position.x) < 0.0001,
				"muzzle socket edit uses the shared weapon profile"
			)
	studio.queue_free()
	_finish()


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("ANIMATION_RIG_HANDS_UI_CHECK PASS ", label)
	else:
		failures.append(label)
		push_error("ANIMATION_RIG_HANDS_UI_CHECK FAIL %s" % label)


func _finish() -> void:
	if failures.is_empty():
		print("ANIMATION_RIG_HANDS_UI_REGRESSION PASS")
		quit(0)
	else:
		push_error("ANIMATION_RIG_HANDS_UI_REGRESSION FAIL %s" % str(failures))
		quit(1)
