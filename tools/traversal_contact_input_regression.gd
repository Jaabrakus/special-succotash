extends SceneTree

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var contact = preload("res://scripts/player/operator_traversal_hand_modifier.gd").new()
	var settings := {"hand_contact": {"enabled": true}}
	var valid := {"slot": "hang", "anchor": Vector3(0, 2, 0), "surface_normal": Vector3.BACK}
	for bad: Dictionary in [{}, {"slot":"hang"}, {"slot":"hang","anchor":Vector3.INF,"surface_normal":Vector3.BACK}, {"slot":"hang","anchor":Vector3.ZERO,"surface_normal":Vector3.UP}, {"slot":"hang","anchor":"invalid","surface_normal":Vector3.BACK}]:
		contact.update_contact(valid, settings, 0.2)
		assert(contact.active and contact.targets.size() == 2)
		contact.update_contact(bad, settings, 0.016)
		assert(not contact.active and contact.weight == 0.0 and contact.targets.is_empty())
	contact.update_contact(valid, settings, 0.2)
	contact.update_contact(valid, {}, 0.016)
	assert(not contact.active)
	var invalid_phase := valid.duplicate()
	invalid_phase.phase = NAN
	contact.update_contact(invalid_phase, settings, 0.016)
	assert(not contact.active and contact.targets.is_empty())
	var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://config/ledge_climb.json"))
	var pull := {"slot":"pull_up", "anchor":Vector3(0,2.15,0), "surface_normal":Vector3.BACK, "start_point":Vector3.ZERO, "landing_point":Vector3(0,2.23,-0.96), "body_point":Vector3(0,2.23,-0.5), "source":str(config.pull_up_visual_root.source), "phase":0.6}
	contact.update_contact(pull, config, 0.2)
	assert(contact.hand_weights[0] == 1.0 and contact.hand_weights[1] == 0.0)
	assert(contact.visual_root_delta.is_finite() and contact.visual_root_delta.y >= -float(config.pull_up_visual_root.max_down_m))
	assert(contact.visual_root_delta.slide(Vector3.UP).length() <= float(config.pull_up_visual_root.max_horizontal_m) + 0.00001)
	pull.source = "res://different_animation.scn"
	contact.update_contact(pull, config, 0.2)
	assert(contact.visual_root_delta == Vector3.ZERO)
	pull.source = str(config.pull_up_visual_root.source)
	pull.phase = 1.0
	contact.update_contact(pull, config, 0.2)
	assert(contact.visual_root_delta == Vector3.ZERO and not contact.active)
	contact.update_contact({}, config, 0.016)
	assert(contact.hand_weights == [0.0,0.0] and contact.targets.is_empty())
	var mantle := {"slot":"low_mantle", "anchor":Vector3(0,1.1,0), "surface_normal":Vector3.BACK, "start_point":Vector3.ZERO, "landing_point":Vector3(0,1.18,-0.9), "body_point":Vector3(0,0.8,0), "source":str(config.visual_root_by_slot.low_mantle.source), "phase":0.1}
	contact.update_contact(mantle, config, 0.2)
	_check(contact.hand_weights == [0.0,0.0], "mantle reach-in precedes locked hand contact")
	mantle.phase = 0.2
	contact.update_contact(mantle, config, 0.2)
	_check(contact.active and contact.hand_weights == [1.0,1.0], "low mantle acquires both hands")
	_check(is_equal_approx(contact.targets[0].distance_to(contact.targets[1]), 0.5), "low mantle uses its own wrist spacing")
	mantle.phase = 0.4
	contact.update_contact(mantle, config, 0.2)
	_check(contact.hand_weights[0] > 0.0 and contact.hand_weights[0] < 0.5 and is_equal_approx(contact.hand_weights[0], contact.hand_weights[1]), "low mantle uses its own early symmetric release")
	var root_settings: Dictionary = config.visual_root_by_slot.low_mantle
	for phase in [0.0, 0.15, 0.3, 0.5, 0.7, 1.0]:
		mantle.phase = phase
		mantle.body_point = Vector3(20,50,-20)
		contact.update_contact(mantle, config, 0.2)
		_check(contact.visual_root_delta.is_finite() and contact.visual_root_delta.y >= -float(root_settings.max_down_m)-0.00001 and contact.visual_root_delta.y <= float(root_settings.max_up_m)+0.00001, "low mantle residual vertical bounds phase " + str(phase))
		_check(contact.visual_root_delta.slide(Vector3.UP).length() <= float(root_settings.max_horizontal_m)+0.00001, "low mantle residual horizontal bound phase " + str(phase))
		if phase == 1.0: _check(contact.visual_root_delta == Vector3.ZERO and not contact.active, "low mantle releases all contact and residual at end")
	mantle.phase = 0.2
	for source in ["", "res://different_animation.scn", str(config.pull_up_visual_root.source)]:
		mantle.source = source
		contact.update_contact(mantle, config, 0.2)
		_check(contact.visual_root_delta == Vector3.ZERO, "low mantle residual rejects missing/mismatched source " + source)
	var missing_root_slot := config.duplicate(true)
	missing_root_slot.visual_root_by_slot.erase("low_mantle")
	mantle.source = str(config.pull_up_visual_root.source)
	contact.update_contact(mantle, missing_root_slot, 0.2)
	_check(contact.visual_root_delta == Vector3.ZERO, "missing low mantle root slot cannot fall back to tall pull-up")
	var missing_contact_slot := config.duplicate(true)
	missing_contact_slot.hand_contact_by_slot.erase("low_mantle")
	mantle.source = str(config.visual_root_by_slot.low_mantle.source)
	contact.update_contact(mantle, missing_contact_slot, 0.2)
	_check(not contact.active and contact.hand_weights == [0.0,0.0], "missing low mantle hand slot cannot fall back to tall pull-up")
	contact.free()
	_verify_separate_support_profiles(config)
	await _verify_evaluated_segment(config, mantle)
	await _verify_braced_wall_clearance(config)
	print("TRAVERSAL_CONTACT_INPUT ", "PASS" if failures.is_empty() else "FAIL", " invalid input, slot/source guards, segment evaluation, release, bounded residual/current body, braced wall clearance", failures)
	quit(0 if failures.is_empty() else 1)

func _verify_separate_support_profiles(config: Dictionary) -> void:
	var contact = preload("res://scripts/player/operator_traversal_hand_modifier.gd").new()
	for slot in ["hang_free", "pull_up_free"]:
		var source := str(config.visual_root_by_slot[slot].source)
		var presentation := {"slot":slot,"phase":0.1,"anchor":Vector3(0,2.15,0),"surface_normal":Vector3.BACK,"source":source,"start_point":Vector3.ZERO,"body_point":Vector3(0,0.2,0),"landing_point":Vector3(0,2.2,-0.96)}
		contact.update_contact(presentation, config, 0.2)
		_check(contact.active and source.ends_with("CMC_Climb_To_Standing_FreeHang.scn"), "free support selects its own source "+slot)
		_check(not contact.root_profile.has("wall_clearance"), "free support does not invent a foot-bracing wall "+slot)
		var missing := config.duplicate(true)
		missing.hand_contact_by_slot.erase(slot)
		contact.update_contact(presentation, missing, 0.2)
		_check(not contact.active, "missing free contact does not borrow braced settings "+slot)
	for slot in ["narrow_idle", "narrow_left", "narrow_right"]:
		var presentation := {"slot":slot,"phase":0.0,"anchor":Vector3.ZERO,"surface_normal":Vector3.BACK,"source":str(config.visual_root_by_slot[slot].source)}
		contact.update_contact(presentation, config, 0.2)
		_check(contact.active and contact.hand_weights == [0.0,0.0] and contact.visual_root_delta == Vector3.ZERO, "narrow pose aligns without hanging IK or body offset "+slot)
	contact.free()

func _check(ok: bool, label: String) -> void:
	print("CONTACT_INPUT_CHECK ", "PASS " if ok else "FAIL ", label)
	if not ok: failures.append(label)

func _verify_evaluated_segment(config: Dictionary, mantle: Dictionary) -> void:
	var body := Node3D.new()
	root.add_child(body)
	body.position = Vector3(0,1.1,-0.3)
	var skeleton := Skeleton3D.new()
	body.add_child(skeleton)
	skeleton.add_bone("mixamorig_Hips")
	var player := AnimationPlayer.new()
	skeleton.add_child(player)
	player.root_node = NodePath("..")
	var clip := Animation.new()
	clip.length = 1.0
	var track := clip.add_track(Animation.TYPE_POSITION_3D)
	clip.track_set_path(track, NodePath(".:mixamorig_Hips"))
	clip.position_track_insert_key(track, 0.0, Vector3.ZERO)
	clip.position_track_insert_key(track, 1.0, Vector3.ZERO)
	var library := AnimationLibrary.new()
	library.add_animation("traversal_low_mantle", clip)
	player.add_animation_library("", library)
	var graph := AnimationNodeBlendTree.new()
	for label: String in ["modern_state_traversal_low_mantle", "legacy_traversal_low_mantle"]:
		var node := AnimationNodeAnimation.new()
		node.animation = &"traversal_low_mantle"
		graph.add_node(StringName(label), node)
	graph.add_node(&"route_blend", AnimationNodeBlend2.new())
	graph.connect_node(&"route_blend", 0, &"legacy_traversal_low_mantle")
	graph.connect_node(&"route_blend", 1, &"modern_state_traversal_low_mantle")
	graph.connect_node(&"output", 0, &"route_blend")
	var tree := AnimationTree.new()
	skeleton.add_child(tree)
	tree.tree_root = graph
	tree.anim_player = tree.get_path_to(player)
	tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	tree.active = true
	tree.set("parameters/route_blend/blend_amount", 1.0)
	var contact = preload("res://scripts/player/operator_traversal_hand_modifier.gd").new()
	skeleton.add_child(contact)
	contact.animation_tree = tree
	contact.body_node = body
	contact.animation_clip = &"traversal_low_mantle"
	contact.animation_duration = 1.0
	contact.animation_start_phase = float(config.presentation_segments.low_mantle.start_phase)
	contact.animation_end_phase = float(config.presentation_segments.low_mantle.end_phase)
	await process_frame
	for route in [0.0, 1.0]:
		tree.set("parameters/route_blend/blend_amount", route)
		# Time zero initialization followed by the midpoint of .30→1.0.
		tree.advance(0.0)
		var node_name := "modern_state_traversal_low_mantle" if route > 0.5 else "legacy_traversal_low_mantle"
		var current := float(tree.get("parameters/" + node_name + "/current_position"))
		tree.advance(0.65-current)
		mantle.phase = 0.1
		mantle.body_point = Vector3.ZERO
		contact.update_contact(mantle, config, 0.2)
		contact._process_modification()
		_check(absf(contact.evaluated_phase-0.5) < 0.0001, "evaluated .65 source time maps to .5 segment phase route " + str(route))
		_check(contact.evaluated_hand_weights == [0.0,0.0], "release follows evaluated segment, not queued phase route " + str(route))
		var evaluated := mantle.duplicate()
		evaluated.phase = 0.5
		evaluated.body_point = body.global_position
		var expected: Vector3 = contact._root_residual(evaluated, config.visual_root_by_slot.low_mantle)
		_check(contact.visual_root_delta.distance_to(expected) < 0.0001, "residual uses evaluated phase and current body route " + str(route))
	body.free()

func _verify_braced_wall_clearance(config: Dictionary) -> void:
	# Test-only fixture: the runtime modifier remains the sole presentation writer.
	var braced_source := "res://assets/external/agls_intake/imported/climbing/CMC_Climb_To_Standing.scn"
	var mapping: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://config/operator_animation_map.json"))
	_check(mapping.clips.traversal_hang == braced_source and mapping.clips.traversal_pull_up == braced_source and config.pull_up_visual_root.source == braced_source, "hang, pull-up and residual share the selected braced source")
	var wall_settings: Dictionary = config.pull_up_visual_root.wall_clearance
	var maximum := float(wall_settings.maximum_offset_m)
	_check(is_finite(maximum) and maximum > 0.0 and maximum <= 0.8, "braced clearance limit remains finite and at most 0.8m")
	var body := Node3D.new()
	root.add_child(body)
	var skeleton := Skeleton3D.new()
	body.add_child(skeleton)
	skeleton.add_bone("mixamorig_Hips")
	for bone: String in ["LeftLeg", "RightLeg", "LeftFoot", "RightFoot", "LeftToeBase", "RightToeBase"]:
		skeleton.add_bone("mixamorig_" + bone)
		skeleton.set_bone_parent(skeleton.get_bone_count()-1, 0)
	var contact = preload("res://scripts/player/operator_traversal_hand_modifier.gd").new()
	skeleton.add_child(contact)
	await process_frame
	var original_body := body.global_transform
	var presentation := {"slot":"hang", "phase":0.0, "anchor":Vector3(0,2,0), "surface_normal":Vector3.BACK, "source":braced_source}
	var bounded := _wall_sample(contact, skeleton, presentation, config, 1.0, -5.0)
	_check(bounded.is_finite() and bounded.length() <= maximum+0.00001 and is_equal_approx(bounded.z, maximum), "deep wall penetration is capped by the saved limit")
	_check(is_zero_approx(bounded.x) and is_zero_approx(bounded.y), "wall correction is outward only")
	var modest := _wall_sample(contact, skeleton, presentation, config, 1.0, -0.2)
	_check(is_equal_approx(modest.z, float(wall_settings.outset_m)+0.2), "reachable wall penetration resolves to the saved outset")
	var points_clear: bool = contact.evaluated_wall_points.size() == 6
	for point: Dictionary in contact.evaluated_wall_points:
		points_clear = points_clear and point.point.is_finite() and float(point.outside_m) >= float(wall_settings.outset_m)-0.00001
	_check(points_clear, "all six knee/foot/toe witnesses finish outside the wall")
	var previous := INF
	var max_step := 0.0
	var release_bounded := true
	var release_monotonic := true
	var release_start := 2.0-float(wall_settings.get("top_margin_m", 0.04))
	var release_end := 2.0+float(wall_settings.get("release_above_top_m", 0.25))
	for index in 101:
		var height := lerpf(release_start-0.01, release_end+0.01, float(index)/100.0)
		var correction := _wall_sample(contact, skeleton, presentation, config, height, -0.2)
		release_bounded = release_bounded and correction.is_finite() and correction.z >= -0.00001 and correction.z <= maximum+0.00001
		if is_finite(previous):
			release_monotonic = release_monotonic and correction.z <= previous+0.00001
			max_step = maxf(max_step, absf(correction.z-previous))
		previous = correction.z
	_check(release_bounded, "all 101 wall release samples remain finite and bounded")
	_check(release_monotonic, "all 101 wall release samples decrease as feet clear the top")
	_check(is_zero_approx(previous) and max_step < 0.01, "wall clearance releases continuously without a top-edge snap")
	for source: String in ["", "res://different_animation.scn", "res://assets/external/agls_intake/imported/climbing/CMC_FreeHang_Climb_Up.scn"]:
		var mismatched := presentation.duplicate()
		mismatched.source = source
		_check(_wall_sample(contact, skeleton, mismatched, config, 1.0, -0.2) == Vector3.ZERO and contact.evaluated_wall_points.is_empty(), "wall correction rejects mismatched source " + source)
	for bad: Dictionary in [{"anchor":Vector3.INF}, {"anchor":Vector3(NAN,2,0)}, {"surface_normal":Vector3.INF}, {"surface_normal":Vector3.ZERO}, {"phase":NAN}]:
		_wall_sample(contact, skeleton, presentation, config, 1.0, -0.2)
		var invalid := presentation.duplicate()
		invalid.merge(bad, true)
		contact.update_contact(invalid, config, 0.2)
		contact._process_modification()
		_check(not contact.active and contact.wall_clearance_delta == Vector3.ZERO and contact.evaluated_wall_points.is_empty(), "invalid public input clears previous wall correction " + str(bad))
	_check(body.global_transform == original_body, "wall clearance never writes the movement owner transform")
	body.free()

func _wall_sample(contact: SkeletonModifier3D, skeleton: Skeleton3D, presentation: Dictionary, config: Dictionary, height: float, depth: float) -> Vector3:
	skeleton.set_bone_pose_position(0, Vector3.ZERO)
	for index in range(1, skeleton.get_bone_count()):
		skeleton.set_bone_pose_position(index, Vector3(0, height, depth))
	skeleton.force_update_all_bone_transforms()
	contact.update_contact(presentation, config, 0.2)
	contact._apply_wall_clearance(skeleton, presentation)
	return contact.wall_clearance_delta
