extends SceneTree

var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var packed := load("res://animation_library_lab.tscn") as PackedScene
	_expect(packed != null, "Animation Studio scene loads")
	if packed == null:
		_finish()
		return
	var studio := packed.instantiate()
	root.add_child(studio)
	await process_frame
	await process_frame
	_expect(
		studio.process_priority == 100,
		"Studio applies weapon and hand IK after the imported animation sample"
	)
	var states_button := studio.find_child("StatesModeButton", true, false) as Button
	_expect(states_button != null, "Studio exposes the Animation States workspace")
	_expect(
		studio.find_child("StateSlotSelector", true, false) != null,
		"state clip selector is visible to authoring"
	)
	_expect(
		studio.find_child("StateLayerSelector", true, false) != null,
		"state body ownership is editable"
	)
	_expect(
		studio.find_child("StateBlendIn", true, false) != null
		and studio.find_child("StateBlendOut", true, false) != null,
		"state entry and exit blends are editable"
	)
	_expect(
		studio.find_child("StateReturnSelector", true, false) != null,
		"state return target is editable"
	)
	_expect(
		studio.find_child("PreviewStateButton", true, false) != null
		and studio.find_child("SaveAnimationStatesButton", true, false) != null,
		"state preview and Save/Apply actions are available"
	)
	_expect(
		studio.find_child("AnimationEventPalette", true, false) != null
		and studio.find_child("ConnectEventToStateButton", true, false) != null,
		"semantic events can be dragged or connected to states"
	)
	_expect(
		studio.find_child("NaturalLanguageStateInput", true, false) != null
		and studio.find_child("ApplyStateProposalButton", true, false) != null,
		"natural-language state proposals require visible approval"
	)
	_expect(
		studio.find_child("AnimationCatalogLegend", true, false) != null,
		"clip browser explains live, candidate, and unclassified animations"
	)
	_expect(
		studio.find_child("VerifySelectedEventRouteButton", true, false) != null
		and studio.find_child("DisconnectSelectedEventButton", true, false) != null,
		"event routes can be verified and removed without editing data files"
	)
	_expect(
		studio.find_child("PreviewSelectedEventButton", true, false) != null
		and studio.find_child("AnimationEventPostureSelector", true, false) != null
		and studio.find_child("AnimationEventFamilySelector", true, false) != null
		and studio.find_child("PresentationPlanCard", true, false) != null
		and studio.find_child("GameplayDictionaryCard", true, false) != null,
		"Studio explains and resolves each event through the shared dictionary and router"
	)
	_expect(
		studio.find_child("SimpleStateWorkflowGuide", true, false) != null
		and studio.find_child("SimpleStateCurrentCue", true, false) != null
		and studio.find_child("SimpleStatePrimaryAction", true, false) != null
		and studio.find_child("SimpleStateSaveAndTest", true, false) != null,
		"States provides a large guided Event to State to Animation workflow"
	)
	if states_button != null:
		states_button.emit_signal("pressed")
		await process_frame
		await process_frame
		_expect(
			String(studio.get("active_editor_page")) == "States",
			"one click opens the state authoring workspace"
		)
		var aim_reticle := studio.find_child(
			"AnimationStudioAimReferenceReticle", true, false
		) as Control
		_expect(
			aim_reticle != null and aim_reticle.visible,
			"States shows the same fixed aim-reference reticle used by Rig & Hands"
		)
		_expect(
			String(studio.call("_animation_correction_posture", "Rifle Prone Forward")) == "PRONE"
			and String(studio.call("_animation_correction_posture", "Moving Backward In Crawl Position")) == "PRONE"
			and String(studio.call("_animation_correction_posture", "Rifle Idle Crouching")) == "CROUCHED"
			and String(studio.call("_animation_correction_posture", "Pistol Kneeling Idle")) == "CROUCHED",
			"blue placement anchors recognize prone/crawl and crouch/kneeling animation names"
		)
		if aim_reticle != null:
			var original_center: Vector2 = aim_reticle.call("get_authoritative_center")
			studio.set("orbit_yaw", float(studio.get("orbit_yaw")) + 0.35)
			studio.call("_update_camera")
			studio.call("_update_animation_studio_aim_reticle")
			_expect(
				(aim_reticle.call("get_authoritative_center") as Vector2).is_equal_approx(original_center),
				"orbit inspection cannot move the fixed Studio reticle"
			)
		var states_rig_overlay := studio.find_child(
			"AnimationStudioGunsmithRigOverlay", true, false
		) as Node3D
		var blue_origin := states_rig_overlay.find_child(
			"GunPlacementLineOrigin", true, false
		) as Node3D if states_rig_overlay != null else null
		var blue_direction := states_rig_overlay.find_child(
			"GunPlacementDirectionHandle", true, false
		) as Node3D if states_rig_overlay != null else null
		var right_hand_dot := states_rig_overlay.find_child(
			"RightHandGripTarget", true, false
		) as Node3D if states_rig_overlay != null else null
		var left_hand_dot := states_rig_overlay.find_child(
			"LeftHandGripTarget", true, false
		) as Node3D if states_rig_overlay != null else null
		_expect(
			states_rig_overlay != null and states_rig_overlay.visible
			and blue_origin != null and blue_origin.visible
			and blue_direction != null and blue_direction.visible,
			"States keeps the small rig dots and blue placement line visible"
		)
		_expect(
			right_hand_dot != null and right_hand_dot.visible
			and left_hand_dot != null and left_hand_dot.visible,
			"States shows both hand reference dots without enabling pose editing"
		)
		# The test rotated the inspection camera above. Refresh the visual line
		# before recording its pre-fire direction, as the live process does.
		studio.call("_update_animation_rig_visual_overlay")
		var blue_reference_before_fire := (
			blue_origin.global_position if blue_origin != null else Vector3.ZERO
		)
		var blue_direction_before_fire := (
			(blue_direction.global_position - blue_origin.global_position).normalized()
			if blue_direction != null and blue_origin != null
			else Vector3.ZERO
		)
		_expect(
			studio.find_child("UseSelectedClipForStateButton", true, false) != null,
			"every animation row exposes one explicit Use + Play state action"
		)
		var preview_skeleton := studio.get("skeleton") as Skeleton3D
		if preview_skeleton != null:
			var head_index := preview_skeleton.find_bone("mixamorig_Head")
			if head_index < 0:
				head_index = preview_skeleton.find_bone("mixamorig:Head")
			if head_index < 0:
				head_index = preview_skeleton.find_bone("head")
			_expect(head_index >= 0, "state preview exposes a head bone for rotation isolation")
			if head_index >= 0:
				var head_name := String(preview_skeleton.get_bone_name(head_index))
				var raw_head_rotation := preview_skeleton.get_bone_pose_rotation(head_index)
				studio.set("bone_rot_offsets", {head_name: Vector3(0.0, 35.0, 0.0)})
				studio.call("_apply_bone_rot_overrides")
				_expect(
					preview_skeleton.get_bone_pose_rotation(head_index).is_equal_approx(
						raw_head_rotation
					),
					"transient Pose rotations cannot leak into a States animation"
				)
				studio.set("bone_rot_offsets", {})
		var frame_parent_chain := studio.find_child(
			"FrameParentChain", true, false
		) as Label
		_expect(
			frame_parent_chain != null
			and frame_parent_chain.text.contains("CLIP:")
			and frame_parent_chain.text.contains("FRAMES"),
			"timeline shows the state-to-clip-to-frames parent chain"
		)
		studio.set("selected_state_slot", "combat_fire")
		var language_input := studio.find_child(
			"NaturalLanguageStateInput", true, false
		) as LineEdit
		var approve_button := studio.find_child(
			"ApplyStateProposalButton", true, false
		) as Button
		if language_input != null and approve_button != null:
			language_input.text = (
				"When a valid rifle shot happens, play Firing Rifle on the torso and arms. "
				+ "Blend in over 0.04 seconds, blend out over 0.10 seconds, "
				+ "and return to the current aim movement."
			)
			studio.call("_propose_natural_language_state")
			_expect(approve_button.visible, "natural language creates a review-only proposal")
			studio.call("_apply_natural_language_state_proposal")
			var routes: Dictionary = studio.get("event_routes")
			var fire_route: Dictionary = routes.get("FIRE_ACCEPTED", {})
			_expect(
				String(fire_route.get("default_state", "")) == "combat_fire",
				"approved proposal connects FIRE_ACCEPTED to the selected state"
			)
			var rules: Dictionary = studio.get("state_rules")
			var fire_rule: Dictionary = rules.get("combat_fire", {})
			_expect(
				String(fire_rule.get("layer", "")) == "UPPER_BODY"
				and String(fire_rule.get("return_state", "")) == "CURRENT_BASE"
				and String(fire_rule.get("authoring_mode", "")) == "SOCOM_RULES"
				and not String(fire_rule.get("source_rule", "")).is_empty(),
				"approved proposal owns torso and arms, returns contextually, and keeps the human rule"
			)
			studio.call("_verify_selected_event_route")
			var route_label := studio.find_child(
				"AnimationEventRouteLabel", true, false
			) as Label
			_expect(
				route_label != null and route_label.text.begins_with("VERIFIED DRAFT"),
				"route verifier resolves standing, crouched, and prone through the runtime contract"
			)
			var pre_fire_animation: StringName = studio.get("animation_player").current_animation
			var ready_transition: Dictionary = studio.call("_state_event_ready_transition")
			var expected_reticle_direction: Vector3 = studio.call(
				"_state_event_reticle_direction_world"
			)
			var expected_posture: String = studio.call(
				"_animation_correction_posture",
				studio.call("_active_animation_correction_clip_key")
			)
			var expected_event_state := String(fire_route.get("default_state", ""))
			var family_states: Dictionary = fire_route.get("family_states", {})
			var rifle_route: Dictionary = family_states.get("TWO_HAND_RIFLE", {})
			var posture_states: Dictionary = rifle_route.get(
				"posture_states",
				fire_route.get("posture_states", {})
			)
			expected_event_state = String(
				posture_states.get(
					expected_posture,
					rifle_route.get("default_state", expected_event_state)
				)
			)
			studio.call("_preview_selected_animation_event")
			await process_frame
			_expect(
				String(studio.get("selected_state_slot")) == expected_event_state,
				"event preview resolves through the authored route instead of a separate Lab clip"
			)
			_expect(
				studio.get("state_event_weapon_solver") != null
				and float(studio.get("state_event_effect_active_seconds")) > 0.0,
				"Fire Accepted preview executes the shared blue-line weapon effect"
			)
			var fire_preview_direction: Vector3 = studio.get(
				"state_event_effect_forward_direction"
			)
			_expect(
				expected_reticle_direction.length_squared() > 0.50
				and fire_preview_direction.length_squared() > 0.50
				and expected_reticle_direction.dot(fire_preview_direction) >= 0.999,
				"Fire Accepted captures the fixed reticle direction once"
			)
			_expect(
				(
					not String(ready_transition.get("ready_path", "")).is_empty()
					and not String(studio.get("state_event_return_animation_path")).is_empty()
				)
				or studio.get("animation_player").current_animation == pre_fire_animation,
				"Fire Accepted enters a mapped ready base or preserves an incompatible full-body clip"
			)
			studio.call("_update_animation_rig_visual_overlay")
			var blue_direction_after_fire := (
				(blue_direction.global_position - blue_origin.global_position).normalized()
				if blue_direction != null and blue_origin != null
				else Vector3.ZERO
			)
			print("ANIMATION_STATE_BLUE_LINE_METRIC origin_delta=%.6f direction_dot=%.6f before=%s after=%s captured=%s" % [
				blue_origin.global_position.distance_to(blue_reference_before_fire) if blue_origin != null else INF,
				blue_direction_after_fire.dot(blue_direction_before_fire),
				str(blue_direction_before_fire),
				str(blue_direction_after_fire),
				str(studio.get("state_event_effect_forward_direction")),
			])
			_expect(
				blue_origin != null
				and blue_origin.global_position.distance_to(blue_reference_before_fire) <= 0.05,
				"Fire Accepted keeps the blue placement origin head-relative and bounded"
			)
			_expect(
				blue_direction != null
				and blue_origin != null
				and blue_direction_after_fire.dot(blue_direction_before_fire) >= 0.999,
				"Fire Accepted keeps the blue line aimed at the same fixed reticle"
			)
			_expect(
				String(studio.get("state_event_effect_posture")) == expected_posture,
				"Fire Accepted matches the posture of the animation being inspected"
			)
			var head_look_radians: Vector2 = studio.get("state_event_head_look_radians")
			_expect(
				head_look_radians.length() > 0.001
				and absf(rad_to_deg(head_look_radians.x)) <= 56.01
				and absf(rad_to_deg(head_look_radians.y)) <= 34.01,
				"Fire Accepted turns the head toward the blue-line target within human limits"
			)
			if preview_skeleton != null:
				var event_head_index := preview_skeleton.find_bone("mixamorig_Head")
				if event_head_index < 0:
					event_head_index = preview_skeleton.find_bone("mixamorig:Head")
				if event_head_index < 0:
					event_head_index = preview_skeleton.find_bone("head")
				if event_head_index >= 0:
					var state_animation_player := studio.get("animation_player") as AnimationPlayer
					var event_position: float = state_animation_player.current_animation_position
					state_animation_player.seek(event_position, true)
					studio.call("_update_state_event_effect_preview", 0.0)
					var stable_head_rotation := preview_skeleton.get_bone_pose_rotation(
						event_head_index
					)
					for repeat in range(4):
						# Deliberately leave the same paused/end frame in place. The
						# head-look layer must recognize its own last output instead of
						# multiplying another yaw/pitch rotation onto it.
						studio.call("_update_state_event_effect_preview", 0.0)
					_expect(
						preview_skeleton.get_bone_pose_rotation(event_head_index).is_equal_approx(
							stable_head_rotation
						),
						"Fire Accepted head look is stable when the same animation frame repeats"
					)
			var preview_weapon := studio.get("weapon_node") as Node3D
			var preview_hand_mount := studio.get("socket_attachment") as BoneAttachment3D
			var preview_mount_keeper: Variant = studio.get(
				"animation_weapon_ownership_preview"
			)
			var preview_solver: Variant = studio.get("state_event_weapon_solver")
			studio.set("state_event_effect_active_seconds", 0.001)
			studio.set("state_event_effect_release_seconds", 0.45)
			studio.call("_update_state_event_effect_preview", 0.01)
			_expect(
				bool(studio.get("state_event_return_pose_captured"))
				and not (studio.get("state_event_return_bone_poses") as Dictionary).is_empty(),
				"Fire Accepted captures its solved upper body before contextual return"
			)
			studio.call("_prepare_state_event_return_frame")
			studio.call("_update_state_event_effect_preview", 1.0 / 60.0)
			studio.call("_prepare_state_event_return_frame")
			studio.call("_update_state_event_effect_preview", 1.0 / 60.0)
			var return_blend_weight := float(
				studio.get("state_event_return_blend_weight")
			)
			_expect(
				return_blend_weight > 0.0 and return_blend_weight < 1.0,
				"Fire Accepted blends back into the live movement pose instead of snapping"
			)
			studio.set("state_event_effect_active_seconds", 0.0)
			studio.set("state_event_effect_release_seconds", 0.001)
			studio.call("_update_state_event_effect_preview", 0.01)
			_expect(
				preview_weapon != null
				and preview_hand_mount != null
				and preview_weapon.get_parent() == preview_hand_mount
				and preview_weapon.transform.is_equal_approx(
					preview_mount_keeper.get("hand_local_transform")
				),
				"completed Fire Accepted preview restores the canonical right-hand mount"
			)
			_expect(
				not bool(studio.get("state_event_return_pose_captured"))
				and (studio.get("state_event_return_bone_poses") as Dictionary).is_empty(),
				"completed Fire Accepted preview clears its temporary return pose"
			)
			_expect(
				String(studio.get("state_event_return_animation_path")).is_empty(),
				"completed Fire Accepted preview restores and clears its contextual movement return"
			)
			var workflow_cue := studio.find_child(
				"SimpleStateCurrentCue", true, false
			) as Label
			_expect(
				workflow_cue != null
				and workflow_cue.text.contains("EVENT  FIRE_ACCEPTED")
				and workflow_cue.text.contains("RAIL → FIXED RETICLE")
				and workflow_cue.text.contains("RUN → WALK / IDLE → AIM IDLE"),
				"guided cue explains the temporary ready-aim movement switch"
			)
			studio.call("_on_route_event_selected", "FIRE_ACCEPTED")
			_expect(
				String(studio.get("selected_animation_event")) == "FIRE_ACCEPTED"
				and String(studio.get("selected_state_slot")) == expected_event_state,
				"clicking an orange graph event immediately selects and previews its live route"
			)
			var plan_card := studio.find_child(
				"PresentationPlanCard", true, false
			) as Label
			_expect(
				plan_card != null
				and plan_card.text.contains("FIRE_ACCEPTED")
				and plan_card.text.contains(expected_event_state),
				"low-code plan card shows the event-to-clip decision used by runtime"
			)
			studio.call("_disconnect_selected_event")
			routes = studio.get("event_routes")
			_expect(
				not routes.has("FIRE_ACCEPTED"),
				"remove route deletes the selected event connection from the unsaved draft"
			)
	studio.queue_free()
	_finish()


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("ANIMATION_STATE_STUDIO_CHECK PASS ", label)
	else:
		failures.append(label)
		push_error("ANIMATION_STATE_STUDIO_CHECK FAIL %s" % label)


func _finish() -> void:
	if failures.is_empty():
		print("ANIMATION_STATE_STUDIO_REGRESSION PASS")
		quit(0)
	else:
		print("ANIMATION_STATE_STUDIO_REGRESSION FAIL ", failures)
		quit(1)
