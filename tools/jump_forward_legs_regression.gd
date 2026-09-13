extends SceneTree

const Graph := preload("res://scripts/player/operator_locomotion_blend_tree.gd")
const Profile := preload("res://scripts/player/operator_animation_profile.gd")
var failures: Array[String] = []
var scene: Node3D
var driver: Node


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	scene = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	await _frames(65)
	var player := scene.get_node("Player") as CharacterBody3D
	driver = player.get_node("Mannequin/ProductionAnimation")
	var graph = driver.get("locomotion_graph")
	var tree: AnimationTree = graph.animation_tree
	var source: Animation = driver.get("animation_player").get_animation(&"jump_forward_action")
	_check(source != null and source.length > 0.0, "real imported forward jump is available")
	_check(source.loop_mode == Animation.LOOP_NONE, "forward jump cannot wrap into a second takeoff")
	_check(graph.jump_frame_source == source and graph.jump_frame_thighs.size() == 2, "saved source-frame adapter caches both real thigh tracks")
	var jump_clip_path := String(driver.get("clip_paths").get(&"jump_forward_action", ""))
	_check(jump_clip_path.ends_with("jump_forward_action.tres") or jump_clip_path.ends_with("Shooter Pack/jump forward.fbx"), "canonical source is the inspected forward jump")
	_check(graph.jump_lower_body_clip == &"jump_forward_action", "saved shared profile reaches canonical graph")
	var blend: AnimationNodeBlend2 = tree.tree_root.get_node(&"jump_lower_body")
	for bone: StringName in Graph.JUMP_LEG_BONES:
		_check(blend.is_path_filtered(NodePath(".:%s" % bone)), "leg filter includes " + String(bone))
	for bone: StringName in Graph.JUMP_ARM_BONES:
		_check(blend.is_path_filtered(NodePath(".:%s" % bone)), "arm filter includes " + String(bone))
	for bone: StringName in Graph.JUMP_TORSO_BONES:
		_check(blend.is_path_filtered(NodePath(".:%s" % bone)), "torso filter includes " + String(bone))
	_check_fallback(driver.get("available_clips"))
	var entries_before: int = graph.jump_lower_body_entry_count
	var start_y := player.global_position.y
	var apex := start_y
	var saw_air := false
	var saw_loop := false
	var saw_full_layer := false
	var time_before := -1.0
	var max_airborne_arm_delta := 0.0
	var pre_jump_arm_rotations: Dictionary = {}
	var skeleton: Skeleton3D = driver.get("skeleton")
	for bone: StringName in Graph.JUMP_ARM_BONES:
		var b_idx := skeleton.find_bone(bone)
		if b_idx >= 0:
			pre_jump_arm_rotations[bone] = skeleton.get_bone_pose(b_idx).basis.get_rotation_quaternion()
	var max_trigger_contact := 0.0
	var max_support_contact := 0.0
	var max_bore_error := 999.0
	Input.action_press(&"jump")
	await physics_frame
	Input.action_release(&"jump")
	for frame in 160:
		await physics_frame
		apex = maxf(apex, player.global_position.y)
		var movement := StringName(player.call("get_motion_state_name"))
		if movement == &"AIRBORNE":
			saw_air = true
			saw_loop = saw_loop or StringName(driver.get("current_clip")) == &"jump_loop"
			saw_full_layer = saw_full_layer or graph.jump_lower_body_weight > 0.99
			var playhead := float(tree.get("parameters/jump_lower_body_animation/current_position"))
			_check(playhead + 0.0001 >= time_before, "takeoff to fall does not restart the leg playhead")
			time_before = playhead
			for bone: StringName in Graph.JUMP_ARM_BONES:
				var b_idx := skeleton.find_bone(bone)
				if b_idx >= 0 and pre_jump_arm_rotations.has(bone):
					var cur_rot := skeleton.get_bone_pose(b_idx).basis.get_rotation_quaternion()
					max_airborne_arm_delta = maxf(max_airborne_arm_delta, cur_rot.angle_to(pre_jump_arm_rotations[bone]))
			var solver: Node = driver.get("weapon_pose_solver")
			if solver != null:
				max_trigger_contact = maxf(max_trigger_contact, float(solver.get("action_trigger_contact_error_m")))
				max_support_contact = maxf(max_support_contact, float(solver.get("support_hand_error_m")))
				if frame == 20:
					driver.notify_fired()
				if frame >= 20 and frame <= 30:
					max_bore_error = minf(max_bore_error, float(solver.get("weapon_aim_error_deg")))
		if saw_air and movement == &"LOCOMOTION" and player.is_on_floor():
			break
	await _frames(8)
	_check(saw_air and saw_loop and saw_full_layer, "actual jump input selects forward legs throughout takeoff/fall")
	_check(graph.jump_lower_body_entry_count == entries_before + 1, "actual jump starts the leg clip exactly once")
	_check(time_before > 0.1, "real leg playhead advances rather than a missing parameter coercing to zero")
	_check(not graph.jump_lower_body_active and is_zero_approx(graph.jump_lower_body_weight), "landing releases the leg layer")
	_check(apex - start_y >= 0.35 and apex - start_y <= 0.80, "unchanged tactical jump capsule height")
	_check(max_airborne_arm_delta > 0.10, "upper-body arm tracks visibly animate during airborne flight (rotational delta > 0.10 rad)")
	_check(max_trigger_contact <= 0.015, "trigger hand contact <= 0.015m (max=%.4fm)" % max_trigger_contact)
	_check(max_support_contact <= 0.020, "support hand contact <= 0.020m (max=%.4fm)" % max_support_contact)
	_check(max_bore_error <= 6.0, "bore to reticle degrees <= 6.0° during mid-air fire (was %.2f°)" % max_bore_error)
	print("JUMP_FORWARD_LEGS_METRIC rise_m=", apex - start_y, " source_seconds=", source.length, " single_playhead_seconds=", time_before, " arm_delta=", max_airborne_arm_delta, " trigger_gap=", max_trigger_contact, " support_gap=", max_support_contact, " bore_error_deg=", max_bore_error)
	# Compare the same canonical graph evaluation at exactly the same playheads.
	# This is a test-only layer toggle, not an alternate runtime pose path.
	player.set_physics_process(false)
	player.get_node("Mannequin").set_process(false)
	driver.set_process(false)
	tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	graph.request_modern_state(&"jump_up_standing")
	graph.update_locomotion(Vector2.UP, 0.7, 4.0, &"STANDING", 0.6, 1.0)
	tree.advance(0.23)
	_check_pose_mask(tree, graph, "normal jump")
	_check_source_frame(tree, graph, "normal jump")
	_check_evaluated_snapshot(tree, graph)
	_check(graph.trigger_fire(&"STANDING") != &"", "existing fire graph accepts its original event")
	tree.advance(0.04)
	_check(bool(tree.get("parameters/fire_layer/active")), "fire layer remains above the leg override")
	_check_pose_mask(tree, graph, "fire owner")
	_check_source_frame(tree, graph, "fire owner")
	_check(graph.trigger_standing_reload(graph.standing_reload_clip), "existing standing reload owner accepts its original clip")
	tree.advance(0.10)
	_check(bool(tree.get("parameters/standing_reload_layer/active")), "reload layer remains above the leg override")
	_check_pose_mask(tree, graph, "reload owner")
	_check_source_frame(tree, graph, "reload owner")
	var entry_count: int = graph.jump_lower_body_entry_count
	graph.request_modern_state(&"jump_loop")
	tree.advance(0.10)
	_check(graph.jump_lower_body_entry_count == entry_count, "fall stage shares takeoff entry")
	graph.request_modern_state(&"pistol_jump")
	_check(graph.jump_lower_body_active and graph.jump_lower_body_entry_count == entry_count, "pistol apex slot preserves the same jump legs without restart")
	graph.request_modern_state(&"jump_running_air")
	tree.advance(0.10)
	_check(graph.jump_lower_body_active and graph.jump_lower_body_entry_count == entry_count, "jump_running_air preserves the same jump legs without restart")
	graph.request_modern_state(&"jump_running_land")
	graph.update_locomotion(Vector2.ZERO, 0.0, 0.0, &"STANDING", 0.6, 1.0)
	_check(not graph.jump_lower_body_active and graph.jump_lower_body_weight == 0.0, "jump_running_land removes leg override")
	graph.request_modern_state(&"jump_up_standing")
	graph.update_locomotion(Vector2.UP, 0.7, 4.0, &"STANDING", 0.6, 1.0)
	_check(graph.jump_lower_body_active, "subsequent takeoff re-arms leg layer")
	graph.request_modern_state(&"jump_down")
	graph.update_locomotion(Vector2.ZERO, 0.0, 0.0, &"STANDING", 0.6, 1.0)
	_check(not graph.jump_lower_body_active and graph.jump_lower_body_weight == 0.0, "landing removes override without affecting action owner")
	graph.request_modern_state(&"idle")
	graph.request_modern_state(&"jump_loop")
	_check(not graph.jump_lower_body_active, "falling off a ledge does not invent a takeoff")
	print("JUMP_FORWARD_LEGS_REGRESSION ", "PASS" if failures.is_empty() else "FAIL", " ", failures)
	quit(0 if failures.is_empty() else 1)


func _check_pose_mask(tree: AnimationTree, graph: RefCounted, label: String) -> void:
	var skeleton: Skeleton3D = driver.get("skeleton")
	skeleton.clear_bones_global_pose_override()
	tree.set("parameters/jump_lower_body/blend_amount", 0.0)
	tree.advance(0.0)
	var original: Dictionary = {}
	for index in skeleton.get_bone_count():
		original[StringName(skeleton.get_bone_name(index))] = skeleton.get_bone_pose(index)
	tree.set("parameters/jump_lower_body/blend_amount", 1.0)
	tree.advance(0.0)
	graph.apply_jump_source_frame(skeleton)
	var aim_frame_error := 0.0
	var leg_difference := 0.0
	var arm_difference := 0.0
	for bone: StringName in Graph.AIM_FRAME_BONES + [&"mixamorig_Hips"]:
		var index := skeleton.find_bone(bone)
		if index < 0:
			continue
		var before: Transform3D = original[bone]
		var after := skeleton.get_bone_pose(index)
		aim_frame_error = maxf(aim_frame_error, before.origin.distance_to(after.origin))
		aim_frame_error = maxf(aim_frame_error, before.basis.x.distance_to(after.basis.x))
		aim_frame_error = maxf(aim_frame_error, before.basis.y.distance_to(after.basis.y))
		aim_frame_error = maxf(aim_frame_error, before.basis.z.distance_to(after.basis.z))
	for bone: StringName in Graph.JUMP_LEG_BONES:
		var index := skeleton.find_bone(bone)
		var before: Transform3D = original[bone]
		leg_difference = maxf(leg_difference, before.basis.get_rotation_quaternion().angle_to(skeleton.get_bone_pose(index).basis.get_rotation_quaternion()))
	for bone: StringName in Graph.JUMP_ARM_BONES:
		var index := skeleton.find_bone(bone)
		if index < 0:
			continue
		var before: Transform3D = original[bone]
		arm_difference = maxf(arm_difference, before.basis.get_rotation_quaternion().angle_to(skeleton.get_bone_pose(index).basis.get_rotation_quaternion()))
	_check(aim_frame_error > 0.10, label + " visibly articulates forward-jump torso tracks (delta > 0.10)")
	_check(leg_difference > 0.01, label + " visibly selects different forward-jump legs")
	_check(arm_difference > 0.10, label + " visibly articulates forward-jump arm tracks (rotational delta > 0.10 rad)")
	print("JUMP_FORWARD_MASK_METRIC ", label, " aim_frame_error=", aim_frame_error, " leg_difference_rad=", leg_difference, " arm_difference_rad=", arm_difference)


func _check_source_frame(tree: AnimationTree, graph: RefCounted, label: String) -> void:
	var skeleton: Skeleton3D = driver.get("skeleton")
	var source: Animation = graph.jump_frame_source
	for amount: float in [0.0, 0.25, 0.5, 1.0]:
		tree.set("parameters/jump_lower_body/blend_amount", amount)
		tree.advance(0.0)
		var time := float(tree.get("parameters/jump_lower_body_animation/current_position"))
		var source_global := _sample_source_globals(skeleton, source, time)
		var before_local: Array[Transform3D] = []
		var before_global: Array[Transform3D] = []
		for index in skeleton.get_bone_count():
			before_local.append(skeleton.get_bone_pose(index))
			before_global.append(skeleton.get_bone_global_pose(index))
		graph.apply_jump_source_frame(skeleton)
		var maximum_angle := 0.0
		for index in skeleton.get_bone_count():
			var bone := StringName(skeleton.get_bone_name(index))
			var current := skeleton.get_bone_pose(index)
			_check(current.origin.is_equal_approx(before_local[index].origin), label + " source frame never writes bone position")
			if amount == 0.0 or bone not in [&"mixamorig_LeftUpLeg", &"mixamorig_RightUpLeg"]:
				_check(current.is_equal_approx(before_local[index]), label + " only opted thigh rotations change")
			var global := skeleton.get_bone_global_pose(index)
			if bone in Graph.UPPER_BODY_BONES + [&"mixamorig_Hips"]:
				_check(global.is_equal_approx(before_global[index]), label + " complete global upper-body and pelvis pose preserved")
			var parent := skeleton.get_bone_parent(index)
			if parent >= 0:
				var old_length := before_global[index].origin.distance_to(before_global[parent].origin)
				var new_length := global.origin.distance_to(skeleton.get_bone_global_pose(parent).origin)
				_check(absf(old_length - new_length) < 0.00001, label + " source-frame conversion never stretches joints")
			if amount == 1.0 and bone in Graph.JUMP_LEG_BONES:
				var error := rad_to_deg(global.basis.orthonormalized().get_rotation_quaternion().normalized().angle_to(source_global[index].basis.orthonormalized().get_rotation_quaternion().normalized()))
				maximum_angle = maxf(maximum_angle, error)
				_check(error < 0.06, label + " actual source thigh-to-toe rotations survive different base pelvis")
		print("JUMP_SOURCE_FRAME_METRIC ", label, " weight=", amount, " source_angle_error_deg=", maximum_angle)
	# Disabled flag is literal original-route compatibility even after cache bind.
	var settings: Dictionary = graph.profile.jump_lower_body
	settings.match_source_parent_frame = false
	tree.advance(0.0)
	var hips := skeleton.find_bone("mixamorig_LeftUpLeg")
	var before := skeleton.get_bone_pose(hips)
	graph.apply_jump_source_frame(skeleton)
	_check(before.is_equal_approx(skeleton.get_bone_pose(hips)), "disabled source-frame flag preserves original route")
	settings.match_source_parent_frame = true


func _sample_source_globals(skeleton: Skeleton3D, source: Animation, time: float) -> Array[Transform3D]:
	var locals: Array[Transform3D] = []
	for index in skeleton.get_bone_count():
		locals.append(skeleton.get_bone_rest(index))
	for track in source.get_track_count():
		var path := source.track_get_path(track)
		if path.get_subname_count() == 0:
			continue
		var index := skeleton.find_bone(path.get_subname(path.get_subname_count() - 1))
		if index < 0:
			continue
		if source.track_get_type(track) == Animation.TYPE_ROTATION_3D:
			locals[index].basis = Basis(source.rotation_track_interpolate(track, time))
		elif source.track_get_type(track) == Animation.TYPE_POSITION_3D:
			locals[index].origin = source.position_track_interpolate(track, time)
	var globals: Array[Transform3D] = []
	for index in skeleton.get_bone_count():
		var parent := skeleton.get_bone_parent(index)
		globals.append(globals[parent] * locals[index] if parent >= 0 else locals[index])
	return globals


func _check_evaluated_snapshot(tree: AnimationTree, graph: RefCounted) -> void:
	var skeleton: Skeleton3D = driver.get("skeleton")
	tree.set("parameters/jump_lower_body/blend_amount", 0.25)
	tree.advance(0.0)
	var evaluated: Vector2 = graph.get_evaluated_jump_source_frame()
	graph.apply_jump_source_frame(skeleton, evaluated)
	var expected: Array[Quaternion] = []
	for bone: StringName in [&"mixamorig_LeftUpLeg", &"mixamorig_RightUpLeg"]:
		expected.append(skeleton.get_bone_pose_rotation(skeleton.find_bone(bone)))
	tree.advance(0.0)
	# Driver commands the NEXT blend before its final posture pass. It must not
	# apply that future blend amount to this already-evaluated .25-weight pose.
	tree.set("parameters/jump_lower_body/blend_amount", 1.0)
	graph.apply_jump_source_frame(skeleton, evaluated)
	var item := 0
	for bone: StringName in [&"mixamorig_LeftUpLeg", &"mixamorig_RightUpLeg"]:
		var current := skeleton.get_bone_pose_rotation(skeleton.find_bone(bone))
		_check(rad_to_deg(expected[item].angle_to(current)) < 0.06, "captured evaluated frame ignores next-frame blend commands")
		item += 1


func _check_fallback(available: Dictionary) -> void:
	var profile := Profile.new()
	profile.load_project_map()
	var graph := Graph.new()
	graph.profile = profile
	var missing := available.duplicate()
	missing.erase(&"jump_forward_action")
	_check(graph._build_jump_lower_body_layer(AnimationNodeBlendTree.new(), missing) == &"route_blend", "missing source keeps original route")
	profile.jump_lower_body.enabled = false
	_check(graph._build_jump_lower_body_layer(AnimationNodeBlendTree.new(), available) == &"route_blend", "disabled source keeps original route")


func _frames(count: int) -> void:
	for frame in count:
		await process_frame


func _check(condition: bool, message: String) -> void:
	if not condition and not failures.has(message):
		failures.append(message)
		push_error("JUMP_FORWARD_LEGS " + message)
