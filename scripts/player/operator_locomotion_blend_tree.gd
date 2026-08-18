class_name SocomOperatorLocomotionBlendTree
extends RefCounted

## Builds and drives the modern normalized-time locomotion graph while keeping
## a complete legacy clip transition route available for instant fallback.

const DIRECTION_POINTS: Dictionary = {
	&"forward": Vector2(0.0, 1.0),
	&"forward_left": Vector2(-0.7071, 0.7071),
	&"left": Vector2(-1.0, 0.0),
	&"back_left": Vector2(-0.7071, -0.7071),
	&"backward": Vector2(0.0, -1.0),
	&"back_right": Vector2(0.7071, -0.7071),
	&"right": Vector2(1.0, 0.0),
	&"forward_right": Vector2(0.7071, 0.7071),
}

const UPPER_BODY_BONES: Array[StringName] = [
	&"mixamorig_Spine", &"mixamorig_Spine1", &"mixamorig_Spine2",
	&"mixamorig_Neck", &"mixamorig_Head",
	&"mixamorig_LeftShoulder", &"mixamorig_LeftArm", &"mixamorig_LeftForeArm", &"mixamorig_LeftHand",
	&"mixamorig_RightShoulder", &"mixamorig_RightArm", &"mixamorig_RightForeArm", &"mixamorig_RightHand",
	&"mixamorig_LeftHandThumb1", &"mixamorig_LeftHandThumb2", &"mixamorig_LeftHandThumb3",
	&"mixamorig_LeftHandIndex1", &"mixamorig_LeftHandIndex2", &"mixamorig_LeftHandIndex3",
	&"mixamorig_LeftHandMiddle1", &"mixamorig_LeftHandMiddle2", &"mixamorig_LeftHandMiddle3",
	&"mixamorig_LeftHandRing1", &"mixamorig_LeftHandRing2", &"mixamorig_LeftHandRing3",
	&"mixamorig_LeftHandPinky1", &"mixamorig_LeftHandPinky2", &"mixamorig_LeftHandPinky3",
	&"mixamorig_RightHandThumb1", &"mixamorig_RightHandThumb2", &"mixamorig_RightHandThumb3",
	&"mixamorig_RightHandIndex1", &"mixamorig_RightHandIndex2", &"mixamorig_RightHandIndex3",
	&"mixamorig_RightHandMiddle1", &"mixamorig_RightHandMiddle2", &"mixamorig_RightHandMiddle3",
	&"mixamorig_RightHandRing1", &"mixamorig_RightHandRing2", &"mixamorig_RightHandRing3",
	&"mixamorig_RightHandPinky1", &"mixamorig_RightHandPinky2", &"mixamorig_RightHandPinky3",
]

var animation_tree: AnimationTree
var legacy_transition: AnimationNodeTransition
var modern_transition: AnimationNodeTransition
var modern_state_indices: Dictionary = {}
var legacy_clip_indices: Dictionary = {}
var profile
var modern_enabled: bool = true
var full_gait_weight: float = 0.0
var playback_rate: float = 1.0
var current_state: StringName = &"idle"
var shared_phase: float = 0.0
var smoothed_direction := Vector2.UP
var prone_travel_blend: float = 1.0
var standing_transition_layer_nodes: Array[StringName] = []
var standing_transition_ready_nodes: Array[StringName] = []


func build(
	owner: Node,
	animation_player: AnimationPlayer,
	available_clips: Dictionary,
	animation_profile,
	use_modern: bool
) -> AnimationTree:
	profile = animation_profile
	modern_enabled = use_modern
	var root := AnimationNodeBlendTree.new()
	_build_legacy_route(root, available_clips)
	_build_modern_route(root, available_clips)

	var route_blend := AnimationNodeBlend2.new()
	route_blend.sync = true
	root.add_node(&"route_blend", route_blend, Vector2(980.0, 100.0))
	root.connect_node(&"route_blend", 0, &"legacy_transition")
	root.connect_node(&"route_blend", 1, &"modern_transition")
	root.connect_node(&"output", 0, &"route_blend")

	animation_tree = AnimationTree.new()
	animation_tree.name = "OperatorAnimationTree"
	owner.add_child(animation_tree)
	animation_tree.anim_player = animation_tree.get_path_to(animation_player)
	animation_tree.tree_root = root
	animation_tree.active = true
	set_modern_enabled(use_modern)
	request_modern_state(&"idle")
	return animation_tree


func set_modern_enabled(enabled: bool) -> void:
	modern_enabled = enabled
	if animation_tree != null:
		animation_tree.set("parameters/route_blend/blend_amount", 1.0 if enabled else 0.0)


func update_locomotion(
	direction: Vector2,
	speed_normalized: float,
	actual_speed_mps: float,
	posture: StringName,
	ready_weight: float,
	delta: float
) -> void:
	if animation_tree == null:
		return
	var target_direction := direction.normalized() if direction.length_squared() > 0.001 else smoothed_direction
	var lateral_threshold := float(profile.locomotion.get("lateral_snap_threshold", 0.92))
	var pure_lateral := (
		absf(target_direction.x) >= lateral_threshold
		and absf(target_direction.y) <= 1.0 - lateral_threshold
	)
	var direction_alpha := 1.0 - exp(-float(profile.locomotion["direction_response"]) * delta)
	if pure_lateral:
		# A/D owns immediate travel direction while the prone playhead remains
		# on its existing synchronized forward crawl.
		smoothed_direction = Vector2(signf(target_direction.x), 0.0)
	else:
		smoothed_direction = smoothed_direction.lerp(target_direction, direction_alpha)
	if smoothed_direction.length_squared() > 0.001:
		smoothed_direction = smoothed_direction.normalized()
	var target_full_weight: float = profile.full_gait_weight(speed_normalized)
	var speed_alpha := 1.0 - exp(-float(profile.locomotion["speed_blend_response"]) * delta)
	full_gait_weight = lerpf(full_gait_weight, target_full_weight, speed_alpha)
	playback_rate = profile.playback_rate(actual_speed_mps, posture, full_gait_weight)
	shared_phase = fmod(shared_phase + delta * playback_rate, 1.0)
	animation_tree.set("parameters/walk_space/blend_position", smoothed_direction)
	animation_tree.set("parameters/full_space/blend_position", smoothed_direction)
	animation_tree.set("parameters/crouch_space/blend_position", smoothed_direction)
	var prone_target := -1.0 if smoothed_direction.y < -0.05 and absf(smoothed_direction.y) >= absf(smoothed_direction.x) * 0.72 else 1.0
	prone_travel_blend = lerpf(prone_travel_blend, prone_target, direction_alpha)
	animation_tree.set("parameters/prone_space/blend_position", prone_travel_blend)
	animation_tree.set("parameters/standing_speed_blend/blend_amount", full_gait_weight)
	animation_tree.set("parameters/standing_upper_body/blend_amount", 1.0)
	for layer_name in standing_transition_layer_nodes:
		animation_tree.set("parameters/%s/blend_amount" % layer_name, 1.0)
	for ready_name in standing_transition_ready_nodes:
		animation_tree.set(
			"parameters/%s/blend_amount" % ready_name,
			clampf(ready_weight, 0.0, 1.0)
		)
	animation_tree.set("parameters/standing_time_scale/scale", playback_rate)
	animation_tree.set("parameters/crouch_time_scale/scale", playback_rate)
	animation_tree.set("parameters/prone_time_scale/scale", playback_rate)
	animation_tree.set("parameters/idle_ready_blend/blend_amount", clampf(ready_weight, 0.0, 1.0))
	animation_tree.set("parameters/standing_upper_ready_blend/blend_amount", clampf(ready_weight, 0.0, 1.0))


func request_modern_state(state_name: StringName) -> bool:
	if animation_tree == null or not modern_state_indices.has(state_name):
		return false
	current_state = state_name
	animation_tree.set("parameters/modern_transition/transition_request", state_name)
	return true


func request_legacy_clip(clip_name: StringName, blend_seconds: float) -> bool:
	if animation_tree == null or not legacy_clip_indices.has(clip_name):
		return false
	legacy_transition.xfade_time = maxf(blend_seconds, 0.0)
	animation_tree.set("parameters/legacy_transition/transition_request", clip_name)
	return true


func get_debug_state() -> Dictionary:
	return {
		"modern_enabled": modern_enabled,
		"modern_state": current_state,
		"full_gait_weight": full_gait_weight,
		"playback_rate": playback_rate,
		"shared_phase": shared_phase,
		"smoothed_direction": smoothed_direction,
		"prone_travel_blend": prone_travel_blend,
	}


func _build_legacy_route(root: AnimationNodeBlendTree, available_clips: Dictionary) -> void:
	legacy_transition = AnimationNodeTransition.new()
	legacy_transition.input_count = available_clips.size()
	legacy_transition.xfade_time = 0.08
	root.add_node(&"legacy_transition", legacy_transition, Vector2(640.0, -260.0))
	var index := 0
	for raw_clip_name in available_clips.keys():
		var clip_name := StringName(raw_clip_name)
		var node_name := StringName("legacy_%s" % clip_name)
		legacy_transition.set_input_name(index, clip_name)
		root.add_node(node_name, _animation_node(clip_name), Vector2(-900.0, -500.0 + index * 30.0))
		root.connect_node(&"legacy_transition", index, node_name)
		legacy_clip_indices[clip_name] = index
		index += 1


func _build_modern_route(root: AnimationNodeBlendTree, available_clips: Dictionary) -> void:
	var walk_space := _direction_space(&"walk", available_clips)
	var full_space := _direction_space(&"run", available_clips)
	var crouch_space := _direction_space(&"crouch", available_clips)
	var prone_space := _prone_direction_space(available_clips)
	root.add_node(&"walk_space", walk_space, Vector2(-640.0, -50.0))
	root.add_node(&"full_space", full_space, Vector2(-640.0, 150.0))
	root.add_node(&"crouch_space", crouch_space, Vector2(-640.0, 430.0))
	root.add_node(&"prone_space", prone_space, Vector2(-640.0, 610.0))

	var speed_blend := AnimationNodeBlend2.new()
	speed_blend.sync = true
	root.add_node(&"standing_speed_blend", speed_blend, Vector2(-300.0, 40.0))
	root.connect_node(&"standing_speed_blend", 0, &"walk_space")
	root.connect_node(&"standing_speed_blend", 1, &"full_space")
	var standing_scale := AnimationNodeTimeScale.new()
	root.add_node(&"standing_time_scale", standing_scale, Vector2(-40.0, 40.0))
	root.connect_node(&"standing_time_scale", 0, &"standing_speed_blend")

	var crouch_scale := AnimationNodeTimeScale.new()
	root.add_node(&"crouch_time_scale", crouch_scale, Vector2(-40.0, 430.0))
	root.connect_node(&"crouch_time_scale", 0, &"crouch_space")
	var prone_scale := AnimationNodeTimeScale.new()
	root.add_node(&"prone_time_scale", prone_scale, Vector2(-40.0, 610.0))
	root.connect_node(&"prone_time_scale", 0, &"prone_space")

	var idle_blend := AnimationNodeBlend2.new()
	idle_blend.sync = true
	root.add_node(&"idle_ready_blend", idle_blend, Vector2(-40.0, -180.0))
	root.add_node(&"modern_idle_rifle", _animation_node(_fallback_clip(&"idle_rifle", available_clips)), Vector2(-640.0, -250.0))
	root.add_node(&"modern_aim_idle", _animation_node(_fallback_clip(&"aim_idle", available_clips)), Vector2(-640.0, -160.0))
	root.connect_node(&"idle_ready_blend", 0, &"modern_idle_rifle")
	root.connect_node(&"idle_ready_blend", 1, &"modern_aim_idle")
	root.add_node(&"modern_idle_crouch", _animation_node(_fallback_clip(&"idle_crouch", available_clips)), Vector2(-640.0, 360.0))
	var standing_upper_ready_blend := AnimationNodeBlend2.new()
	standing_upper_ready_blend.sync = true
	root.add_node(&"standing_upper_ready_blend", standing_upper_ready_blend, Vector2(-40.0, 230.0))
	root.add_node(&"standing_upper_idle_rifle", _animation_node(_fallback_clip(&"idle_rifle", available_clips)), Vector2(-640.0, 220.0))
	root.add_node(&"standing_upper_aim_idle", _animation_node(_fallback_clip(&"aim_idle", available_clips)), Vector2(-640.0, 300.0))
	root.connect_node(&"standing_upper_ready_blend", 0, &"standing_upper_idle_rifle")
	root.connect_node(&"standing_upper_ready_blend", 1, &"standing_upper_aim_idle")

	var standing_upper_body := AnimationNodeBlend2.new()
	standing_upper_body.sync = true
	standing_upper_body.filter_enabled = true
	for bone_name: StringName in UPPER_BODY_BONES:
		standing_upper_body.set_filter_path(NodePath(".:%s" % bone_name), true)
	root.add_node(&"standing_upper_body", standing_upper_body, Vector2(300.0, 40.0))
	root.connect_node(&"standing_upper_body", 0, &"standing_time_scale")
	root.connect_node(&"standing_upper_body", 1, &"standing_upper_ready_blend")

	var state_sources: Dictionary = {
		&"idle": &"idle_ready_blend",
		&"standing": &"standing_upper_body",
		&"idle_crouch": &"modern_idle_crouch",
		&"crouch": &"crouch_time_scale",
		&"prone": &"prone_time_scale",
	}
	for raw_clip_name in available_clips.keys():
		var clip_name := StringName(raw_clip_name)
		if _is_directional_locomotion(clip_name) or clip_name in [&"idle_rifle", &"aim_idle", &"idle_crouch"]:
			continue
		var node_name := StringName("modern_state_%s" % clip_name)
		root.add_node(node_name, _animation_node(clip_name), Vector2(40.0, 540.0 + state_sources.size() * 42.0))
		if _is_standing_locomotion_transition(clip_name):
			var layer_name := StringName("%s_upper_body" % node_name)
			var transition_upper_body := AnimationNodeBlend2.new()
			transition_upper_body.sync = true
			transition_upper_body.filter_enabled = true
			for bone_name: StringName in UPPER_BODY_BONES:
				transition_upper_body.set_filter_path(NodePath(".:%s" % bone_name), true)
			root.add_node(layer_name, transition_upper_body, Vector2(300.0, 540.0 + state_sources.size() * 42.0))
			var transition_ready_name := StringName("%s_ready" % node_name)
			var transition_ready := AnimationNodeBlend2.new()
			transition_ready.sync = true
			var transition_idle_name := StringName("%s_idle_rifle" % node_name)
			var transition_aim_name := StringName("%s_aim_idle" % node_name)
			root.add_node(transition_ready_name, transition_ready, Vector2(40.0, 560.0 + state_sources.size() * 42.0))
			root.add_node(transition_idle_name, _animation_node(_fallback_clip(&"idle_rifle", available_clips)), Vector2(-260.0, 550.0 + state_sources.size() * 42.0))
			root.add_node(transition_aim_name, _animation_node(_fallback_clip(&"aim_idle", available_clips)), Vector2(-260.0, 570.0 + state_sources.size() * 42.0))
			root.connect_node(transition_ready_name, 0, transition_idle_name)
			root.connect_node(transition_ready_name, 1, transition_aim_name)
			root.connect_node(layer_name, 0, node_name)
			root.connect_node(layer_name, 1, transition_ready_name)
			standing_transition_layer_nodes.append(layer_name)
			standing_transition_ready_nodes.append(transition_ready_name)
			state_sources[clip_name] = layer_name
		else:
			state_sources[clip_name] = node_name

	modern_transition = AnimationNodeTransition.new()
	modern_transition.input_count = state_sources.size()
	modern_transition.xfade_time = 0.10
	root.add_node(&"modern_transition", modern_transition, Vector2(640.0, 150.0))
	var state_index := 0
	for raw_state_name in state_sources.keys():
		var state_name := StringName(raw_state_name)
		modern_transition.set_input_name(state_index, state_name)
		root.connect_node(&"modern_transition", state_index, StringName(state_sources[state_name]))
		modern_state_indices[state_name] = state_index
		state_index += 1


func _direction_space(prefix: StringName, available_clips: Dictionary) -> AnimationNodeBlendSpace2D:
	var space := AnimationNodeBlendSpace2D.new()
	space.sync = true
	space.min_space = Vector2(-1.0, -1.0)
	space.max_space = Vector2(1.0, 1.0)
	space.x_label = "Strafe"
	space.y_label = "Forward"
	for suffix: StringName in DIRECTION_POINTS:
		var clip_name := StringName("%s_%s" % [prefix, suffix])
		if available_clips.has(clip_name):
			space.add_blend_point(
				_animation_node(clip_name),
				DIRECTION_POINTS[suffix],
				-1,
				suffix
			)
	return space


func _prone_direction_space(available_clips: Dictionary) -> AnimationNodeBlendSpace1D:
	var space := AnimationNodeBlendSpace1D.new()
	space.sync = true
	space.min_space = -1.0
	space.max_space = 1.0
	space.value_label = "Prone travel"
	var forward_clip := _fallback_clip(&"prone_forward", available_clips)
	var backward_clip := _fallback_clip(&"prone_backward", available_clips)
	# One node per authored cycle guarantees that lateral steering cannot create
	# another playhead. Direction changes blend between matching normalized times.
	space.add_blend_point(_animation_node(backward_clip), -1.0, -1, &"backward")
	space.add_blend_point(_animation_node(forward_clip), 1.0, -1, &"forward")
	return space


func _is_standing_locomotion_transition(clip_name: StringName) -> bool:
	return clip_name in [
		&"start_forward", &"start_backward",
		&"stop_forward", &"stop_backward", &"run_to_stop",
		&"turn_90_left", &"turn_90_right",
	]


func _animation_node(clip_name: StringName) -> AnimationNodeAnimation:
	var node := AnimationNodeAnimation.new()
	node.animation = clip_name
	return node


func _fallback_clip(preferred: StringName, available_clips: Dictionary) -> StringName:
	if available_clips.has(preferred):
		return preferred
	return StringName(available_clips.keys()[0]) if not available_clips.is_empty() else &""


func _is_directional_locomotion(clip_name: StringName) -> bool:
	var text := String(clip_name)
	for suffix: StringName in DIRECTION_POINTS:
		if text in ["walk_%s" % suffix, "run_%s" % suffix, "crouch_%s" % suffix]:
			return true
	return false
