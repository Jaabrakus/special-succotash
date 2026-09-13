extends RefCounted

# Builds resources once; transition timing remains in the locomotion coordinator.
static func build(graph: RefCounted, root: AnimationNodeBlendTree, available_clips: Dictionary) -> void:
	var walk_space: AnimationNodeBlendSpace2D = graph._direction_space(&"walk", available_clips)
	var full_space: AnimationNodeBlendSpace2D = graph._direction_space(&"run", available_clips)
	var crouch_space: AnimationNodeBlendSpace2D = graph._direction_space(&"crouch", available_clips)
	var prone_space: AnimationNodeBlendSpace1D = graph._prone_direction_space(available_clips)
	root.add_node(&"walk_space", walk_space, Vector2(-640.0, -50.0))
	root.add_node(&"full_space", full_space, Vector2(-640.0, 150.0))
	root.add_node(&"crouch_space", crouch_space, Vector2(-640.0, 430.0))
	root.add_node(&"prone_space", prone_space, Vector2(-640.0, 610.0))
	var walking_source: StringName = &"walk_space"
	if graph.source_controller_active:
		root.add_node(&"jog_space", graph._direction_space(&"jog", available_clips))
		var walk_jog := AnimationNodeBlend2.new()
		walk_jog.sync = true
		root.add_node(&"source_walk_jog", walk_jog)
		root.connect_node(&"source_walk_jog", 0, &"walk_space")
		root.connect_node(&"source_walk_jog", 1, &"jog_space")
		walking_source = &"source_walk_jog"

	var speed_blend := AnimationNodeBlend2.new()
	speed_blend.sync = true
	root.add_node(&"standing_speed_blend", speed_blend, Vector2(-300.0, 40.0))
	root.connect_node(&"standing_speed_blend", 0, walking_source)
	root.connect_node(&"standing_speed_blend", 1, &"full_space")
	var standing_source: StringName = &"standing_speed_blend"
	var crouch_source: StringName = &"crouch_space"
	if graph.source_firing_enabled():
		for prefix: String in ["walk", "run", "crouch"]:
			root.add_node(StringName("firing_%s_space" % prefix), graph._direction_space(StringName(prefix), available_clips, true))
		var firing_walk_source: StringName = &"firing_walk_space"
		if graph.source_controller_active:
			root.add_node(&"firing_jog_space", graph._direction_space(&"jog", available_clips, true))
			var walk_jog := AnimationNodeBlend2.new()
			walk_jog.sync = true
			root.add_node(&"source_firing_walk_jog", walk_jog)
			root.connect_node(&"source_firing_walk_jog", 0, &"firing_walk_space")
			root.connect_node(&"source_firing_walk_jog", 1, &"firing_jog_space")
			firing_walk_source = &"source_firing_walk_jog"
		var firing_speed := AnimationNodeBlend2.new()
		firing_speed.sync = true
		root.add_node(&"firing_speed_blend", firing_speed)
		root.connect_node(&"firing_speed_blend", 0, firing_walk_source)
		root.connect_node(&"firing_speed_blend", 1, &"firing_run_space")
		for stance: String in ["standing", "crouch"]:
			var ready := AnimationNodeBlend2.new()
			ready.sync = true
			var node_name := StringName(stance + "_source_ready")
			root.add_node(node_name, ready)
			root.connect_node(node_name, 0, standing_source if stance == "standing" else crouch_source)
			root.connect_node(node_name, 1, &"firing_speed_blend" if stance == "standing" else &"firing_crouch_space")
		standing_source = &"standing_source_ready"
		crouch_source = &"crouch_source_ready"
	var standing_scale := AnimationNodeTimeScale.new()
	root.add_node(&"standing_time_scale", standing_scale, Vector2(-40.0, 40.0))
	root.connect_node(&"standing_time_scale", 0, standing_source)

	var crouch_scale := AnimationNodeTimeScale.new()
	root.add_node(&"crouch_time_scale", crouch_scale, Vector2(-40.0, 430.0))
	root.connect_node(&"crouch_time_scale", 0, crouch_source)
	var prone_scale := AnimationNodeTimeScale.new()
	root.add_node(&"prone_time_scale", prone_scale, Vector2(-40.0, 610.0))
	root.connect_node(&"prone_time_scale", 0, &"prone_space")
	if graph.source_controller_active:
		var standing_spaces: Array[StringName] = [&"walk_space", &"jog_space", &"full_space", &"firing_walk_space", &"firing_jog_space", &"firing_run_space"]
		var crouch_spaces: Array[StringName] = [&"crouch_space", &"firing_crouch_space"]
		graph.gait_phase_sync.bind(root, &"standing", standing_spaces, 0.6333333, graph.source_animation_player)
		graph.gait_phase_sync.bind(root, &"crouched", crouch_spaces, 0.6333333, graph.source_animation_player)

	var is_pistol_family: bool = (
		graph.weapon_handling_profile.get("locomotion_family", "") == "PISTOL"
		or graph.weapon_handling_profile.get("family", "") in ["TWO_HAND_PISTOL", "ONE_HAND"]
	)
	var equipped_idle: StringName = (
		graph._weapon_action_clip("idle_standing", &"pistol_idle", available_clips)
		if is_pistol_family
		else graph._weapon_action_clip("idle_standing", &"idle_rifle", available_clips)
	)
	var equipped_ready: StringName = (
		graph._weapon_action_clip(
			"ready_standing",
			graph._weapon_action_clip(
				"idle_standing",
				&"pistol_idle" if is_pistol_family else &"aim_idle",
				available_clips
			),
			available_clips
		)
	)
	var equipped_crouch_idle: StringName = (
		graph._weapon_action_clip("idle_crouched", &"pistol_idle_kneeling", available_clips)
		if is_pistol_family
		else graph._weapon_action_clip("idle_crouched", &"idle_crouch", available_clips)
	)
	var equipped_prone_idle: StringName = graph._weapon_action_clip("idle_prone", &"idle_prone", available_clips)
	graph.source_idle_blend_times = {
		&"idle": graph.profile.source_idle_blend_seconds(equipped_idle),
		&"idle_crouch": graph.profile.source_idle_blend_seconds(equipped_crouch_idle),
	}
	graph.grounded_idle_clips = {&"STANDING": equipped_idle, &"CROUCHED": equipped_crouch_idle, &"PRONE": equipped_prone_idle}
	var equipped_crouch_ready: StringName = (
		graph._weapon_action_clip("ready_crouched", &"pistol_idle_kneeling", available_clips)
		if is_pistol_family
		else graph._weapon_action_clip(
			"ready_crouched",
			&"aim_idle_crouch",
			available_clips
		)
	)
	# Optional nonstationary sources keep a newly authored stationary pair from
	# leaking baked posture corrections into moving, start/stop, or jump layers.
	# All other profiles retain their existing sources through these fallbacks.
	var moving_idle: StringName = graph._weapon_action_clip("idle_standing_moving", equipped_idle, available_clips)
	var moving_ready: StringName = graph._weapon_action_clip("ready_standing_moving", equipped_ready, available_clips)
	var moving_crouch_ready: StringName = graph._weapon_action_clip("ready_crouched_moving", equipped_crouch_ready, available_clips)
	root.add_node(&"modern_idle_rifle", graph._animation_node(equipped_idle), Vector2(-640.0, -250.0))
	root.add_node(&"modern_aim_idle", graph._animation_node(equipped_ready), Vector2(-640.0, -160.0))
	root.add_node(&"modern_idle_crouch", graph._animation_node(equipped_crouch_idle), Vector2(-640.0, 360.0))
	root.add_node(&"modern_idle_prone", graph._animation_node(equipped_prone_idle), Vector2(-640.0, 560.0))
	# Ready/recovery is split in two. Each route's AIM_FRAME owns Spine-to-Head,
	# while its recovery layer contributes only the clavicle-to-hand chain.
	# The default source is shared; stationary-only authored pairs opt out above.
	root.add_node(&"crouch_upper_aim_idle", graph._animation_node(moving_crouch_ready), Vector2(-300.0, 390.0))
	root.add_node(
		&"crouch_aim_frame_source",
		graph._animation_node(moving_crouch_ready),
		Vector2(-300.0, 430.0)
	)
	var crouch_aim_frame := AnimationNodeBlend2.new()
	crouch_aim_frame.sync = true
	crouch_aim_frame.filter_enabled = true
	for bone_name: StringName in graph.AIM_FRAME_BONES:
		crouch_aim_frame.set_filter_path(NodePath(".:%s" % bone_name), true)
	root.add_node(&"crouch_aim_frame", crouch_aim_frame, Vector2(120.0, 430.0))
	root.connect_node(&"crouch_aim_frame", 0, &"crouch_time_scale")
	root.connect_node(&"crouch_aim_frame", 1, &"crouch_aim_frame_source")
	var crouch_upper_body := AnimationNodeBlend2.new()
	crouch_upper_body.sync = true
	crouch_upper_body.filter_enabled = true
	for bone_name: StringName in graph.FIRE_RECOVERY_LIMB_BONES:
		crouch_upper_body.set_filter_path(NodePath(".:%s" % bone_name), true)
	root.add_node(&"crouch_upper_body", crouch_upper_body, Vector2(400.0, 430.0))
	root.connect_node(&"crouch_upper_body", 0, &"crouch_aim_frame")
	root.connect_node(&"crouch_upper_body", 1, &"crouch_upper_aim_idle")
	root.add_node(&"crouch_idle_aim_idle", graph._animation_node(equipped_crouch_ready), Vector2(-300.0, 345.0))
	root.add_node(
		&"crouch_idle_aim_frame_source",
		graph._animation_node(equipped_crouch_ready),
		Vector2(-300.0, 325.0)
	)
	var crouch_idle_aim_frame := AnimationNodeBlend2.new()
	crouch_idle_aim_frame.sync = true
	crouch_idle_aim_frame.filter_enabled = not graph.source_firing_enabled()
	for bone_name: StringName in graph.AIM_FRAME_BONES:
		crouch_idle_aim_frame.set_filter_path(NodePath(".:%s" % bone_name), true)
	root.add_node(&"crouch_idle_aim_frame", crouch_idle_aim_frame, Vector2(120.0, 345.0))
	root.connect_node(&"crouch_idle_aim_frame", 0, &"modern_idle_crouch")
	root.connect_node(&"crouch_idle_aim_frame", 1, &"crouch_idle_aim_frame_source")
	var crouch_idle_upper_body := AnimationNodeBlend2.new()
	crouch_idle_upper_body.sync = true
	crouch_idle_upper_body.filter_enabled = true
	for bone_name: StringName in graph.FIRE_RECOVERY_LIMB_BONES:
		crouch_idle_upper_body.set_filter_path(NodePath(".:%s" % bone_name), true)
	root.add_node(&"crouch_idle_upper_body", crouch_idle_upper_body, Vector2(400.0, 360.0))
	root.connect_node(&"crouch_idle_upper_body", 0, &"crouch_idle_aim_frame")
	root.connect_node(&"crouch_idle_upper_body", 1, &"crouch_idle_aim_idle")
	var standing_upper_ready_blend := AnimationNodeBlend2.new()
	standing_upper_ready_blend.sync = true
	root.add_node(&"standing_upper_ready_blend", standing_upper_ready_blend, Vector2(-40.0, 230.0))
	root.add_node(&"standing_upper_idle_rifle", graph._animation_node(moving_idle), Vector2(-640.0, 220.0))
	root.add_node(&"standing_upper_aim_idle", graph._animation_node(moving_ready), Vector2(-640.0, 300.0))
	root.add_node(
		&"standing_aim_frame_source",
		graph._animation_node(moving_ready),
		Vector2(-300.0, 80.0)
	)
	root.connect_node(&"standing_upper_ready_blend", 0, &"standing_upper_idle_rifle")
	root.connect_node(&"standing_upper_ready_blend", 1, &"standing_upper_aim_idle")

	var standing_aim_frame := AnimationNodeBlend2.new()
	standing_aim_frame.sync = true
	standing_aim_frame.filter_enabled = true
	for bone_name: StringName in graph.AIM_FRAME_BONES:
		standing_aim_frame.set_filter_path(NodePath(".:%s" % bone_name), true)
	root.add_node(&"standing_aim_frame", standing_aim_frame, Vector2(120.0, 40.0))
	root.connect_node(&"standing_aim_frame", 0, &"standing_time_scale")
	root.connect_node(&"standing_aim_frame", 1, &"standing_aim_frame_source")

	var standing_upper_body := AnimationNodeBlend2.new()
	standing_upper_body.sync = true
	standing_upper_body.filter_enabled = true
	for bone_name: StringName in graph.FIRE_RECOVERY_LIMB_BONES:
		standing_upper_body.set_filter_path(NodePath(".:%s" % bone_name), true)
	root.add_node(&"standing_upper_body", standing_upper_body, Vector2(400.0, 40.0))
	root.connect_node(&"standing_upper_body", 0, &"standing_aim_frame")
	root.connect_node(&"standing_upper_body", 1, &"standing_upper_ready_blend")

	# Standing idle needs the same ownership split as standing locomotion. The
	# weapon's authored standing-ready clip owns only the upper body while the
	# standing base continues to own hips and legs.
	root.add_node(&"standing_idle_base", graph._animation_node(equipped_idle), Vector2(-300.0, -90.0))
	var standing_fire: StringName = graph.profile.resolve_family_animation_slot(
		StringName(graph.weapon_handling_profile.get("family", "")), "firing_standing", available_clips)
	if graph.source_firing_enabled() and not is_pistol_family and standing_fire != &"":
		root.add_node(&"source_standing_alert", graph._animation_node(equipped_ready))
		root.add_node(&"source_standing_fire", graph._animation_node(standing_fire))
		var ready_fire := AnimationNodeBlend2.new()
		ready_fire.sync = true
		root.add_node(&"standing_idle_aim_frame_source", ready_fire)
		root.connect_node(&"standing_idle_aim_frame_source", 0, &"source_standing_alert")
		root.connect_node(&"standing_idle_aim_frame_source", 1, &"source_standing_fire")
		graph.source_standing_fire_split = true
	else:
		root.add_node(&"standing_idle_aim_frame_source", graph._animation_node(equipped_ready))
	var standing_idle_aim_frame := AnimationNodeBlend2.new()
	standing_idle_aim_frame.sync = true
	standing_idle_aim_frame.filter_enabled = not graph.source_firing_enabled()
	for bone_name: StringName in graph.AIM_FRAME_BONES:
		standing_idle_aim_frame.set_filter_path(NodePath(".:%s" % bone_name), true)
	root.add_node(&"standing_idle_aim_frame", standing_idle_aim_frame, Vector2(120.0, -90.0))
	root.connect_node(&"standing_idle_aim_frame", 0, &"standing_idle_base")
	root.connect_node(&"standing_idle_aim_frame", 1, &"standing_idle_aim_frame_source")
	var standing_idle_upper_body := AnimationNodeBlend2.new()
	standing_idle_upper_body.sync = true
	standing_idle_upper_body.filter_enabled = true
	for bone_name: StringName in graph.FIRE_RECOVERY_LIMB_BONES:
		standing_idle_upper_body.set_filter_path(NodePath(".:%s" % bone_name), true)
	root.add_node(&"standing_idle_upper_body", standing_idle_upper_body, Vector2(400.0, -160.0))
	root.connect_node(&"standing_idle_upper_body", 0, &"standing_idle_aim_frame")
	root.connect_node(&"standing_idle_upper_body", 1, &"modern_aim_idle")

	var state_sources: Dictionary = {
		&"idle": &"standing_idle_upper_body",
		&"standing": &"standing_upper_body",
		&"idle_crouch": &"crouch_idle_upper_body",
		&"crouch": &"crouch_upper_body",
		&"idle_prone": &"modern_idle_prone",
		&"prone": &"prone_time_scale",
	}
	if graph.source_firing_enabled():
		root.add_node(&"source_prone_ready_pose", graph._animation_node(graph._weapon_action_clip("ready_prone", equipped_prone_idle, available_clips)))
		var prone_ready := AnimationNodeBlend2.new()
		prone_ready.sync = true
		root.add_node(&"prone_source_ready", prone_ready)
		root.connect_node(&"prone_source_ready", 0, &"modern_idle_prone")
		root.connect_node(&"prone_source_ready", 1, &"source_prone_ready_pose")
		state_sources[&"idle_prone"] = &"prone_source_ready"
	for raw_clip_name in available_clips.keys():
		var clip_name := StringName(raw_clip_name)
		if graph._is_directional_locomotion(clip_name) or clip_name in [&"idle_rifle", &"aim_idle", &"aim_idle_crouch", &"idle_crouch"]:
			continue
		var node_name := StringName("modern_state_%s" % clip_name)
		var source_name := node_name
		root.add_node(node_name, graph._animation_node(clip_name), Vector2(40.0, 540.0 + state_sources.size() * 42.0))
		if graph.source_jump_clip(clip_name):
			var jump_seek := StringName("%s_source_jump_seek" % node_name)
			root.add_node(jump_seek, AnimationNodeTimeSeek.new())
			root.connect_node(jump_seek, 0, source_name)
			source_name = jump_seek
			graph.source_jump_seek_paths[clip_name] = StringName("parameters/%s/seek_request" % jump_seek)
		if graph.combo_seek_paths.has(clip_name):
			var seek_name := StringName("%s_combo_seek" % node_name)
			root.add_node(seek_name, AnimationNodeTimeSeek.new(), Vector2(140.0, 540.0 + state_sources.size() * 42.0))
			root.connect_node(seek_name, 0, source_name)
			source_name = seek_name
			graph.combo_seek_paths[clip_name].append(StringName("parameters/%s/seek_request" % seek_name))
		if graph._uses_action_time_scale(clip_name):
			var scale_name := StringName("%s_time_scale" % node_name)
			root.add_node(scale_name, AnimationNodeTimeScale.new(), Vector2(180.0, 540.0 + state_sources.size() * 42.0))
			root.connect_node(scale_name, 0, node_name)
			source_name = scale_name
			graph.modern_clip_time_scale_paths[clip_name] = StringName("parameters/%s/scale" % scale_name)
		if graph._uses_upper_body_ready_layer(clip_name):
			var layer_name := StringName("%s_upper_body" % node_name)
			var transition_upper_body := AnimationNodeBlend2.new()
			transition_upper_body.sync = true
			transition_upper_body.filter_enabled = true
			for bone_name: StringName in graph.FIRE_RECOVERY_LIMB_BONES:
				transition_upper_body.set_filter_path(NodePath(".:%s" % bone_name), true)
			root.add_node(layer_name, transition_upper_body, Vector2(300.0, 540.0 + state_sources.size() * 42.0))
			var transition_ready_name := StringName("%s_ready" % node_name)
			var transition_ready := AnimationNodeBlend2.new()
			transition_ready.sync = true
			var transition_idle_name := StringName("%s_idle_rifle" % node_name)
			var transition_aim_name := StringName("%s_aim_idle" % node_name)
			root.add_node(transition_ready_name, transition_ready, Vector2(40.0, 560.0 + state_sources.size() * 42.0))
			root.add_node(transition_idle_name, graph._animation_node(moving_idle), Vector2(-260.0, 550.0 + state_sources.size() * 42.0))
			root.add_node(transition_aim_name, graph._animation_node(moving_ready), Vector2(-260.0, 570.0 + state_sources.size() * 42.0))
			root.connect_node(transition_ready_name, 0, transition_idle_name)
			root.connect_node(transition_ready_name, 1, transition_aim_name)
			var transition_base_source := source_name
			if graph._is_standing_locomotion_transition(clip_name):
				var aim_frame_name := StringName("%s_aim_frame" % node_name)
				var aim_frame_source_name := StringName(
					"%s_aim_frame_source" % node_name
				)
				var transition_aim_frame := AnimationNodeBlend2.new()
				transition_aim_frame.sync = true
				transition_aim_frame.filter_enabled = true
				for bone_name: StringName in graph.AIM_FRAME_BONES:
					transition_aim_frame.set_filter_path(
						NodePath(".:%s" % bone_name),
						true
					)
				root.add_node(
					aim_frame_name,
					transition_aim_frame,
					Vector2(210.0, 540.0 + state_sources.size() * 42.0)
				)
				root.add_node(
					aim_frame_source_name,
					graph._animation_node(moving_ready),
					Vector2(-80.0, 590.0 + state_sources.size() * 42.0)
				)
				root.connect_node(aim_frame_name, 0, source_name)
				root.connect_node(aim_frame_name, 1, aim_frame_source_name)
				graph.standing_transition_aim_frame_nodes.append(aim_frame_name)
				transition_base_source = aim_frame_name
			root.connect_node(layer_name, 0, transition_base_source)
			root.connect_node(layer_name, 1, transition_ready_name)
			if graph._is_jump_mobility_clip(clip_name):
				graph.airborne_upper_body_layer_nodes.append(layer_name)
			else:
				graph.standing_transition_layer_nodes.append(layer_name)
			graph.standing_transition_ready_nodes.append(transition_ready_name)
			state_sources[clip_name] = layer_name
		else:
			state_sources[clip_name] = source_name

	graph.modern_transition = AnimationNodeTransition.new()
	graph.modern_transition.input_count = state_sources.size()
	graph.modern_transition.xfade_time = 0.10
	# A synced Transition evaluates every inactive input at weight zero. This route
	# also contains every one-shot action, so syncing it would evaluate dozens of
	# dormant branches each frame. Continuous bases retain their last playheads via
	# reset=false below; directional gait points phase-match inside their cyclic
	# BlendSpaces. Intentional actions alone restart at frame zero.
	graph.modern_transition.sync = false
	root.add_node(&"modern_transition", graph.modern_transition, Vector2(640.0, 150.0))
	var state_index := 0
	for raw_state_name in state_sources.keys():
		var state_name := StringName(raw_state_name)
		graph.modern_transition.set_input_name(state_index, state_name)
		graph.modern_transition.set_input_reset(
			state_index,
			state_name not in [
				&"idle", &"standing", &"idle_crouch", &"crouch",
				&"idle_prone", &"prone",
			]
		)
		root.connect_node(&"modern_transition", state_index, StringName(state_sources[state_name]))
		graph.modern_state_indices[state_name] = state_index
		state_index += 1
