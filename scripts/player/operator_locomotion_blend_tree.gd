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

const PRESENTATION_RELAXED_RIFLE := &"RELAXED_RIFLE"
const PRESENTATION_READY_AIM := &"READY_AIM"

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
var weapon_handling_profile: Dictionary = {}
var modern_enabled: bool = true
var full_gait_weight: float = 0.0
var playback_rate: float = 1.0
var current_state: StringName = &"idle"
var shared_phase: float = 0.0
var smoothed_direction := Vector2.UP
var rendered_direction := Vector2.UP
var prone_travel_blend: float = 1.0
var standing_transition_layer_nodes: Array[StringName] = []
var standing_transition_ready_nodes: Array[StringName] = []
var fire_transition: AnimationNodeTransition
var fire_layer_node: AnimationNodeOneShot
var fire_clips_by_posture: Dictionary = {}
var fire_layer_available: bool = false
var fire_trigger_count: int = 0
var active_fire_clip: StringName = &""
var crouched_reload_clip: StringName = &""
var crouched_reload_layer_available: bool = false
var crouched_reload_trigger_count: int = 0
var standing_reload_clip: StringName = &""
var standing_reload_layer_available: bool = false
var standing_reload_trigger_count: int = 0
var presentation_mode: StringName = PRESENTATION_RELAXED_RIFLE
var upper_body_ready_blend: float = 0.0


func build(
	owner: Node,
	animation_player: AnimationPlayer,
	available_clips: Dictionary,
	animation_profile,
	use_modern: bool,
	equipped_weapon_profile: Dictionary = {}
) -> AnimationTree:
	profile = animation_profile
	weapon_handling_profile = equipped_weapon_profile.duplicate(true)
	modern_enabled = use_modern
	var root := AnimationNodeBlendTree.new()
	_build_legacy_route(root, available_clips)
	_build_modern_route(root, available_clips)

	var route_blend := AnimationNodeBlend2.new()
	route_blend.sync = true
	root.add_node(&"route_blend", route_blend, Vector2(980.0, 100.0))
	root.connect_node(&"route_blend", 0, &"legacy_transition")
	root.connect_node(&"route_blend", 1, &"modern_transition")
	_build_crouched_reload_layer(root, available_clips)
	var action_source := (
		&"crouched_reload_layer"
		if crouched_reload_layer_available
		else &"route_blend"
	)
	_build_standing_reload_layer(root, available_clips, action_source)
	if standing_reload_layer_available:
		action_source = &"standing_reload_layer"
	_build_fire_layer(root, available_clips, action_source)
	root.connect_node(
		&"output",
		0,
		&"fire_layer" if fire_layer_available else action_source
	)

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
	var rendered_direction_alpha := 1.0 - exp(
		-float(profile.locomotion.get("rendered_direction_response", 8.0)) * delta
	)
	# Logical A/D selection is immediate for input readability and animation
	# routing. The separate rendered coordinate eases through the synchronized
	# BlendSpace so that instant authority does not create a one-frame leg pop.
	if pure_lateral:
		smoothed_direction = Vector2(signf(target_direction.x), 0.0)
	else:
		smoothed_direction = smoothed_direction.lerp(target_direction, direction_alpha)
	if smoothed_direction.length_squared() > 0.001:
		smoothed_direction = smoothed_direction.normalized()
	rendered_direction = rendered_direction.lerp(target_direction, rendered_direction_alpha)
	if rendered_direction.length_squared() > 0.001:
		rendered_direction = rendered_direction.normalized()
	# Prone already has authored ground-contact timing and a dedicated forward /
	# backward blend. Keep its original direction response so a standing strafe
	# presentation fix cannot shift the crawl phase or lift knees off the floor.
	if posture == &"PRONE":
		rendered_direction = smoothed_direction
	presentation_mode = (
		PRESENTATION_READY_AIM
		if ready_weight >= 0.50
		else PRESENTATION_RELAXED_RIFLE
	)
	var normalized_ready := clampf(ready_weight, 0.0, 1.0)
	var movement_amount := smoothstep(0.08, 0.55, speed_normalized)
	var dynamic_hold: Variant = weapon_handling_profile.get("dynamic_hold", {})
	var ready_locomotion_inheritance := 0.22
	if dynamic_hold is Dictionary:
		ready_locomotion_inheritance = clampf(
			float(
				(dynamic_hold as Dictionary).get(
					"ready_locomotion_inheritance",
					ready_locomotion_inheritance
				)
			),
			0.0,
			0.35
		)
	# Aim Idle remains the dominant firing pose, but a moving player retains a
	# small amount of the active rifle-walk torso and arm motion. The right-hand
	# weapon mount therefore breathes with the body instead of looking pinned in
	# space while the legs move underneath it.
	upper_body_ready_blend = normalized_ready * (
		1.0 - ready_locomotion_inheritance * movement_amount
	)
	# Relaxed locomotion uses the authored rifle-run family. A ready weapon
	# deliberately drops the visual legs to the rifle-walk family while Aim Idle
	# owns the torso. CharacterBody speed and collision stay unchanged.
	var target_full_weight: float = (
		profile.full_gait_weight(speed_normalized)
		* (1.0 - clampf(ready_weight, 0.0, 1.0))
	)
	var speed_alpha := 1.0 - exp(-float(profile.locomotion["speed_blend_response"]) * delta)
	full_gait_weight = lerpf(full_gait_weight, target_full_weight, speed_alpha)
	playback_rate = profile.playback_rate(actual_speed_mps, posture, full_gait_weight)
	# During a sharp direction change, briefly slow the visual foot cycle while
	# the authoritative CharacterBody remains fully responsive. This is the
	# planted weight transfer that prevents the run clip's own fastest hip frame
	# from stacking on top of the directional blend.
	if posture != &"PRONE":
		var direction_alignment := clampf(rendered_direction.dot(target_direction), 0.0, 1.0)
		playback_rate *= lerpf(
			float(profile.locomotion.get("direction_turn_playback_floor", 0.72)),
			1.0,
			direction_alignment
		)
	shared_phase = fmod(shared_phase + delta * playback_rate, 1.0)
	animation_tree.set("parameters/walk_space/blend_position", rendered_direction)
	animation_tree.set("parameters/full_space/blend_position", rendered_direction)
	animation_tree.set("parameters/crouch_space/blend_position", rendered_direction)
	var prone_target := -1.0 if smoothed_direction.y < -0.05 and absf(smoothed_direction.y) >= absf(smoothed_direction.x) * 0.72 else 1.0
	prone_travel_blend = lerpf(prone_travel_blend, prone_target, direction_alpha)
	animation_tree.set("parameters/prone_space/blend_position", prone_travel_blend)
	animation_tree.set("parameters/standing_speed_blend/blend_amount", full_gait_weight)
	animation_tree.set(
		"parameters/standing_upper_body/blend_amount",
		upper_body_ready_blend
	)
	animation_tree.set(
		"parameters/standing_idle_upper_body/blend_amount",
		clampf(ready_weight, 0.0, 1.0)
	)
	for layer_name in standing_transition_layer_nodes:
		animation_tree.set(
			"parameters/%s/blend_amount" % layer_name,
			upper_body_ready_blend
		)
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


func trigger_fire(
	posture: StringName,
	event_clip: StringName = &""
) -> StringName:
	if animation_tree == null or not fire_layer_available:
		return &""
	var normalized_posture := posture
	if normalized_posture not in [&"STANDING", &"CROUCHED", &"PRONE"]:
		normalized_posture = &"STANDING"
	var mapped_clip := StringName(fire_clips_by_posture.get(normalized_posture, ""))
	active_fire_clip = event_clip if event_clip == mapped_clip else mapped_clip
	if active_fire_clip == &"":
		return &""
	if fire_layer_node != null:
		fire_layer_node.fadein_time = profile.state_blend_in_seconds(
			active_fire_clip,
			0.025
		)
		fire_layer_node.fadeout_time = profile.state_blend_out_seconds(
			active_fire_clip,
			0.065
		)
		fire_layer_node.filter_enabled = profile.state_layer(active_fire_clip) == "UPPER_BODY"
	animation_tree.set(
		"parameters/fire_transition/transition_request",
		normalized_posture
	)
	animation_tree.set(
		"parameters/fire_layer/request",
		AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE
	)
	fire_trigger_count += 1
	return active_fire_clip


func trigger_crouched_reload(clip_name: StringName) -> bool:
	if (
		animation_tree == null
		or not crouched_reload_layer_available
		or clip_name != crouched_reload_clip
	):
		return false
	animation_tree.set(
		"parameters/crouched_reload_layer/request",
		AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE
	)
	crouched_reload_trigger_count += 1
	return true


func trigger_standing_reload(clip_name: StringName) -> bool:
	if (
		animation_tree == null
		or not standing_reload_layer_available
		or clip_name != standing_reload_clip
	):
		return false
	animation_tree.set(
		"parameters/standing_reload_layer/request",
		AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE
	)
	standing_reload_trigger_count += 1
	return true


func cancel_reload_layers() -> void:
	if animation_tree == null:
		return
	if crouched_reload_layer_available:
		animation_tree.set(
			"parameters/crouched_reload_layer/request",
			AnimationNodeOneShot.ONE_SHOT_REQUEST_ABORT
		)
	if standing_reload_layer_available:
		animation_tree.set(
			"parameters/standing_reload_layer/request",
			AnimationNodeOneShot.ONE_SHOT_REQUEST_ABORT
		)


func get_debug_state() -> Dictionary:
	return {
		"modern_enabled": modern_enabled,
		"modern_state": current_state,
		"full_gait_weight": full_gait_weight,
		"playback_rate": playback_rate,
		"shared_phase": shared_phase,
		"smoothed_direction": smoothed_direction,
		"rendered_direction": rendered_direction,
		"prone_travel_blend": prone_travel_blend,
		"fire_layer_available": fire_layer_available,
		"fire_trigger_count": fire_trigger_count,
		"active_fire_clip": active_fire_clip,
		"crouched_reload_layer_available": crouched_reload_layer_available,
		"crouched_reload_clip": crouched_reload_clip,
		"crouched_reload_trigger_count": crouched_reload_trigger_count,
		"standing_reload_layer_available": standing_reload_layer_available,
		"standing_reload_clip": standing_reload_clip,
		"standing_reload_trigger_count": standing_reload_trigger_count,
		"presentation_mode": presentation_mode,
		"upper_body_ready_blend": upper_body_ready_blend,
	}


func _build_crouched_reload_layer(
	root: AnimationNodeBlendTree,
	available_clips: Dictionary
) -> void:
	crouched_reload_clip = _weapon_action_clip(
		"reload_crouched",
		&"reload",
		available_clips
	)
	if crouched_reload_clip == &"" or not available_clips.has(crouched_reload_clip):
		return
	if profile.state_layer(crouched_reload_clip) != "UPPER_BODY":
		return
	root.add_node(
		&"crouched_reload_animation",
		_animation_node(crouched_reload_clip),
		Vector2(980.0, 470.0)
	)
	var reload_layer := AnimationNodeOneShot.new()
	reload_layer.fadein_time = profile.state_blend_in_seconds(crouched_reload_clip, 0.08)
	reload_layer.fadeout_time = profile.state_blend_out_seconds(crouched_reload_clip, 0.12)
	reload_layer.sync = true
	reload_layer.filter_enabled = true
	for bone_name: StringName in UPPER_BODY_BONES:
		reload_layer.set_filter_path(NodePath(".:%s" % bone_name), true)
	root.add_node(&"crouched_reload_layer", reload_layer, Vector2(1230.0, 330.0))
	root.connect_node(&"crouched_reload_layer", 0, &"route_blend")
	root.connect_node(&"crouched_reload_layer", 1, &"crouched_reload_animation")
	crouched_reload_layer_available = true


func _build_standing_reload_layer(
	root: AnimationNodeBlendTree,
	available_clips: Dictionary,
	base_source: StringName
) -> void:
	standing_reload_clip = _weapon_action_clip(
		"reload_standing",
		&"reload",
		available_clips
	)
	if standing_reload_clip == &"" or not available_clips.has(standing_reload_clip):
		return
	if profile.state_layer(standing_reload_clip) != "UPPER_BODY":
		return
	root.add_node(
		&"standing_reload_animation",
		_animation_node(standing_reload_clip),
		Vector2(980.0, 550.0)
	)
	var reload_layer := AnimationNodeOneShot.new()
	reload_layer.fadein_time = profile.state_blend_in_seconds(standing_reload_clip, 0.08)
	reload_layer.fadeout_time = profile.state_blend_out_seconds(standing_reload_clip, 0.12)
	reload_layer.sync = true
	reload_layer.filter_enabled = true
	for bone_name: StringName in UPPER_BODY_BONES:
		reload_layer.set_filter_path(NodePath(".:%s" % bone_name), true)
	root.add_node(&"standing_reload_layer", reload_layer, Vector2(1450.0, 330.0))
	root.connect_node(&"standing_reload_layer", 0, base_source)
	root.connect_node(&"standing_reload_layer", 1, &"standing_reload_animation")
	standing_reload_layer_available = true


func _build_fire_layer(
	root: AnimationNodeBlendTree,
	available_clips: Dictionary,
	base_source: StringName
) -> void:
	fire_clips_by_posture = {
		&"STANDING": _event_fire_clip(
			&"STANDING",
			"fire_standing",
			&"combat_fire",
			available_clips
		),
		&"CROUCHED": _event_fire_clip(
			&"CROUCHED",
			"fire_crouched",
			&"crouch_fire",
			available_clips
		),
		&"PRONE": _event_fire_clip(
			&"PRONE",
			"fire_prone",
			&"prone_fire",
			available_clips
		),
	}
	for posture_name: StringName in fire_clips_by_posture:
		if not available_clips.has(fire_clips_by_posture[posture_name]):
			return

	fire_transition = AnimationNodeTransition.new()
	fire_transition.input_count = 3
	fire_transition.xfade_time = 0.025
	root.add_node(&"fire_transition", fire_transition, Vector2(980.0, 330.0))
	var posture_order: Array[StringName] = [&"STANDING", &"CROUCHED", &"PRONE"]
	for index in posture_order.size():
		var posture_name := posture_order[index]
		var node_name := StringName("fire_%s" % String(posture_name).to_lower())
		fire_transition.set_input_name(index, posture_name)
		root.add_node(
			node_name,
			_animation_node(StringName(fire_clips_by_posture[posture_name])),
			Vector2(650.0, 300.0 + index * 70.0)
		)
		root.connect_node(&"fire_transition", index, node_name)

	fire_layer_node = AnimationNodeOneShot.new()
	fire_layer_node.fadein_time = profile.state_blend_in_seconds(&"combat_fire", 0.025)
	fire_layer_node.fadeout_time = profile.state_blend_out_seconds(&"combat_fire", 0.065)
	fire_layer_node.sync = true
	fire_layer_node.filter_enabled = profile.state_layer(&"combat_fire") == "UPPER_BODY"
	for bone_name: StringName in UPPER_BODY_BONES:
		fire_layer_node.set_filter_path(NodePath(".:%s" % bone_name), true)
	root.add_node(&"fire_layer", fire_layer_node, Vector2(1230.0, 110.0))
	root.connect_node(&"fire_layer", 0, base_source)
	root.connect_node(&"fire_layer", 1, &"fire_transition")
	fire_layer_available = true


func _event_fire_clip(
	posture_name: StringName,
	weapon_slot: String,
	fallback: StringName,
	available_clips: Dictionary
) -> StringName:
	var event_clip: StringName = profile.resolve_animation_event(
		&"FIRE_ACCEPTED",
		posture_name,
		StringName(weapon_handling_profile.get("family", ""))
	)
	if event_clip != &"" and available_clips.has(event_clip):
		return event_clip
	return _weapon_action_clip(weapon_slot, fallback, available_clips)


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
	var equipped_idle := _fallback_clip(&"idle_rifle", available_clips)
	var equipped_ready := _weapon_action_clip("idle_standing", &"aim_idle", available_clips)
	var equipped_crouch_idle := _weapon_action_clip("idle_crouched", &"idle_crouch", available_clips)
	root.add_node(&"modern_idle_rifle", _animation_node(equipped_idle), Vector2(-640.0, -250.0))
	root.add_node(&"modern_aim_idle", _animation_node(equipped_ready), Vector2(-640.0, -160.0))
	root.connect_node(&"idle_ready_blend", 0, &"modern_idle_rifle")
	root.connect_node(&"idle_ready_blend", 1, &"modern_aim_idle")
	root.add_node(&"modern_idle_crouch", _animation_node(equipped_crouch_idle), Vector2(-640.0, 360.0))
	var standing_upper_ready_blend := AnimationNodeBlend2.new()
	standing_upper_ready_blend.sync = true
	root.add_node(&"standing_upper_ready_blend", standing_upper_ready_blend, Vector2(-40.0, 230.0))
	root.add_node(&"standing_upper_idle_rifle", _animation_node(equipped_idle), Vector2(-640.0, 220.0))
	root.add_node(&"standing_upper_aim_idle", _animation_node(equipped_ready), Vector2(-640.0, 300.0))
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

	# Standing idle needs the same ownership split as standing locomotion. The
	# weapon's authored standing-ready clip owns only the upper body while the
	# standing base continues to own hips and legs.
	var standing_idle_upper_body := AnimationNodeBlend2.new()
	standing_idle_upper_body.sync = true
	standing_idle_upper_body.filter_enabled = true
	for bone_name: StringName in UPPER_BODY_BONES:
		standing_idle_upper_body.set_filter_path(NodePath(".:%s" % bone_name), true)
	root.add_node(&"standing_idle_base", _animation_node(equipped_idle), Vector2(-300.0, -90.0))
	root.add_node(&"standing_idle_upper_body", standing_idle_upper_body, Vector2(300.0, -160.0))
	root.connect_node(&"standing_idle_upper_body", 0, &"standing_idle_base")
	root.connect_node(&"standing_idle_upper_body", 1, &"idle_ready_blend")

	var state_sources: Dictionary = {
		&"idle": &"standing_idle_upper_body",
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
			root.add_node(transition_aim_name, _animation_node(equipped_ready), Vector2(-260.0, 570.0 + state_sources.size() * 42.0))
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
		var logical_name := StringName("%s_%s" % [prefix, suffix])
		var clip_name := _weapon_locomotion_clip(String(logical_name), logical_name, available_clips)
		if available_clips.has(clip_name):
			space.add_blend_point(
				_animation_node(clip_name),
				DIRECTION_POINTS[suffix],
				-1,
				suffix
			)
	return space


func _weapon_locomotion_clip(
	slot_name: String,
	fallback: StringName,
	available_clips: Dictionary
) -> StringName:
	var routes: Dictionary = weapon_handling_profile.get("locomotion_slots", {})
	var candidate := StringName(routes.get(slot_name, ""))
	if candidate != &"" and available_clips.has(candidate):
		return candidate
	return _fallback_clip(fallback, available_clips)


func _weapon_action_clip(
	slot_name: String,
	fallback: StringName,
	available_clips: Dictionary
) -> StringName:
	var routes: Dictionary = weapon_handling_profile.get("animation_slots", {})
	var candidate := StringName(routes.get(slot_name, ""))
	if candidate != &"" and available_clips.has(candidate):
		return candidate
	return _fallback_clip(fallback, available_clips)


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
