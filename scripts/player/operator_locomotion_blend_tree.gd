class_name SocomOperatorLocomotionBlendTree
extends RefCounted

# Immutable provenance within one play session, shared by every graph. Resource
# metadata is checked once rather than loading a clip from frame-update paths.
static var source_clip_classification_cache: Dictionary = {}

const ModernRouteBuilder := preload("res://scripts/player/operator_locomotion_route_builder.gd")
const SourceLocomotionPolicy := preload("res://scripts/player/operator_source_locomotion_policy.gd")
const GaitPhaseSync := preload("res://scripts/player/operator_gait_phase_sync.gd")
var source_policy := SourceLocomotionPolicy.new()
var source_animation_player: AnimationPlayer
var gait_phase_sync := GaitPhaseSync.new()
var source_controller_active := false
var jog_gait_weight := 0.0
var source_grounded_clip: StringName = &""
var grounded_idle_clips: Dictionary = {}
const PistolUpperLayer := preload("res://scripts/player/operator_pistol_upper_layer.gd")
const ReloadStanceBlend := preload("res://scripts/player/operator_reload_stance_blend.gd")
var crouched_reload_pose = ReloadStanceBlend.new()
var standing_reload_pose = ReloadStanceBlend.new()
var active_reload_pose = null
const TraversalEquipLayer := preload("res://scripts/player/operator_traversal_equip_layer.gd")
var traversal_equip = TraversalEquipLayer.new()

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

const JUMP_LEG_BONES: Array[StringName] = [
	&"mixamorig_LeftUpLeg", &"mixamorig_LeftLeg", &"mixamorig_LeftFoot", &"mixamorig_LeftToeBase",
	&"mixamorig_RightUpLeg", &"mixamorig_RightLeg", &"mixamorig_RightFoot", &"mixamorig_RightToeBase",
]

const JUMP_ARM_BONES: Array[StringName] = [
	&"mixamorig_LeftShoulder", &"mixamorig_LeftArm", &"mixamorig_LeftForeArm", &"mixamorig_LeftHand",
	&"mixamorig_RightShoulder", &"mixamorig_RightArm", &"mixamorig_RightForeArm", &"mixamorig_RightHand",
]

const JUMP_TORSO_BONES: Array[StringName] = [
	&"mixamorig_Hips",
	&"mixamorig_Spine",
	&"mixamorig_Spine1",
	&"mixamorig_Spine2",
	&"mixamorig_Neck",
	&"mixamorig_Head",
]

const AIM_FRAME_BONES: Array[StringName] = [
	&"mixamorig_Spine",
	&"mixamorig_Spine1",
	&"mixamorig_Spine2",
	&"mixamorig_Neck",
	&"mixamorig_Head",
]

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

# FIRE_RECOVERY limb ownership remains deliberately separate from AIM_FRAME.
# The recovery animation owns only the clavicle-to-fingertip chains that
# establish the two-handed rifle hold.
const FIRE_RECOVERY_LIMB_BONES: Array[StringName] = [
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

const FIRE_EXCLUDED_BONES: Array[StringName] = [
	&"mixamorig_Neck",
	&"mixamorig_Head",
]

const PRONE_FIRE_STABLE_FRAME_BONES: Array[StringName] = [
	&"mixamorig_Spine",
	&"mixamorig_Spine1",
	&"mixamorig_Spine2",
	&"mixamorig_LeftShoulder",
	&"mixamorig_RightShoulder",
]

var animation_tree: AnimationTree
var legacy_transition: AnimationNodeTransition
var modern_transition: AnimationNodeTransition
var source_idle_blend_times: Dictionary = {}
var modern_state_indices: Dictionary = {}
var legacy_clip_indices: Dictionary = {}
var modern_clip_time_scale_paths: Dictionary = {}
var legacy_clip_time_scale_paths: Dictionary = {}
var combo_seek_paths: Dictionary = {}
var profile
var weapon_handling_profile: Dictionary = {}
var modern_enabled: bool = true
var full_gait_weight: float = 0.0
var playback_rate: float = 1.0
var current_state: StringName = &"idle"
var source_cardinal_spaces: Dictionary = {}
var shared_phase: float = 0.0
var smoothed_direction := Vector2.UP
var rendered_direction := Vector2.UP
var prone_travel_blend: float = 1.0
var standing_transition_layer_nodes: Array[StringName] = []
var standing_transition_ready_nodes: Array[StringName] = []
var standing_transition_aim_frame_nodes: Array[StringName] = []
var airborne_upper_body_layer_nodes: Array[StringName] = []
var fire_transition: AnimationNodeTransition
var fire_layer_node: AnimationNodeOneShot
var fire_clips_by_posture: Dictionary = {}
var fire_layer_available: bool = false
var fire_trigger_count: int = 0
var active_fire_clip: StringName = &""
var crouched_reload_clip: StringName = &""
var crouched_reload_animation_node: AnimationNodeAnimation
var crouched_reload_layer_available: bool = false
var crouched_reload_trigger_count: int = 0
var standing_reload_clip: StringName = &""
var standing_reload_animation_node: AnimationNodeAnimation
var standing_reload_layer_available: bool = false
var standing_reload_trigger_count: int = 0
var presentation_mode: StringName = PRESENTATION_RELAXED_RIFLE
var source_standing_fire_split := false
var source_standing_fire_weight := 0.0
var upper_body_ready_blend: float = 0.0
var locomotion_carry_weight: float = 0.0
var evaluated_locomotion_carry_weight: float = 0.0
var evaluated_carry_direction := Vector2.UP
var evaluated_locomotion_source_weight: float = 0.0
var jump_lower_body_clip: StringName = &""
var jump_lower_body_active: bool = false
var jump_lower_body_weight: float = 0.0
var jump_lower_body_entry_count: int = 0
var jump_frame_source: Animation
var jump_frame_hips_index: int = -1
var jump_frame_hip_chain: Array[Dictionary] = []
var jump_frame_thighs: Array[Dictionary] = []
var source_jump_seek_paths: Dictionary = {}


func build(
	owner: Node,
	animation_player: AnimationPlayer,
	available_clips: Dictionary,
	animation_profile,
	use_modern: bool,
	equipped_weapon_profile: Dictionary = {}
) -> AnimationTree:
	profile = animation_profile
	source_animation_player = animation_player
	weapon_handling_profile = equipped_weapon_profile.duplicate(true)
	source_policy = SourceLocomotionPolicy.new()
	gait_phase_sync = GaitPhaseSync.new()
	modern_enabled = use_modern
	_configure_source_controller(available_clips)
	source_cardinal_spaces.clear()
	source_standing_fire_split = false
	source_standing_fire_weight = 0.0
	source_jump_seek_paths.clear()
	jump_lower_body_clip = &""
	if profile != null and profile.get("jump_lower_body") is Dictionary \
			and bool(profile.jump_lower_body.get("enabled", false)):
		var selected := StringName(profile.jump_lower_body.get("clip", ""))
		if available_clips.has(selected):
			jump_lower_body_clip = selected
	var root := AnimationNodeBlendTree.new()
	_build_legacy_route(root, available_clips)
	_build_modern_route(root, available_clips)

	var route_blend := AnimationNodeBlend2.new()
	# Only one locomotion implementation owns presentation at a time. Advancing
	# the zero-weight legacy graph doubles graph work and became visible after the
	# modern square-shoulder layers grew. Freeze the inactive route; its playhead
	# has no presentation meaning until the route is explicitly selected.
	route_blend.sync = false
	root.add_node(&"route_blend", route_blend, Vector2(980.0, 100.0))
	root.connect_node(&"route_blend", 0, &"legacy_transition")
	root.connect_node(&"route_blend", 1, &"modern_transition")
	var locomotion_source := _build_jump_lower_body_layer(root, available_clips)
	locomotion_source = PistolUpperLayer.build(self, root, locomotion_source)
	_build_crouched_reload_layer(root, available_clips, locomotion_source)
	var action_source := (
		&"crouched_reload_layer"
		if crouched_reload_layer_available
		else locomotion_source
	)
	_build_standing_reload_layer(root, available_clips, action_source)
	if standing_reload_layer_available:
		action_source = &"standing_reload_layer"
	_build_fire_layer(root, available_clips, action_source)
	var final_source: StringName = traversal_equip.build(root, &"fire_layer" if fire_layer_available else action_source, available_clips, UPPER_BODY_BONES)
	root.connect_node(
		&"output",
		0,
		final_source
	)

	animation_tree = AnimationTree.new()
	traversal_equip.tree = animation_tree
	crouched_reload_pose.tree = animation_tree
	standing_reload_pose.tree = animation_tree
	animation_tree.name = "OperatorAnimationTree"
	owner.add_child(animation_tree)
	animation_tree.anim_player = animation_tree.get_path_to(animation_player)
	animation_tree.tree_root = root
	animation_tree.active = true
	_bind_jump_source_frame(owner.get("skeleton") as Skeleton3D, animation_player)
	set_modern_enabled(use_modern)
	request_modern_state(&"idle")
	return animation_tree


func set_modern_enabled(enabled: bool) -> void:
	modern_enabled = enabled
	if animation_tree != null:
		animation_tree.set("parameters/route_blend/blend_amount", 1.0 if enabled else 0.0)
		if not enabled and jump_lower_body_clip != &"":
			jump_lower_body_active = false
			jump_lower_body_weight = 0.0
			animation_tree.set("parameters/jump_lower_body/blend_amount", 0.0)


func clear_jump_overlay_for_full_body_action() -> void:
	# Traversal/death return before update_locomotion, which normally publishes
	# this weight. A stale airborne overlay otherwise replaces the new full pose.
	jump_lower_body_active = false
	jump_lower_body_weight = 0.0
	if animation_tree != null and jump_lower_body_clip != &"":
		animation_tree.set("parameters/jump_lower_body/blend_amount", 0.0)


func clear_combat_overlays_for_full_body_action() -> void:
	# These are cosmetic graph nodes only; the weapon/reload coordinator keeps
	# its accepted action clock and ammunition state.
	cancel_reload_layers()
	if animation_tree != null and fire_layer_available:
		animation_tree.set("parameters/fire_layer/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_ABORT)


func publish_source_standing_fire(selected: bool, delta: float) -> void:
	if animation_tree == null or not source_standing_fire_split:
		return
	var target := 1.0 if selected else 0.0
	var response := 14.0 if selected else 8.0
	source_standing_fire_weight = lerpf(source_standing_fire_weight, target, 1.0 - exp(-response * maxf(delta, 0.0)))
	if absf(source_standing_fire_weight - target) < 0.001:
		source_standing_fire_weight = target
	animation_tree.set("parameters/standing_idle_aim_frame_source/blend_amount", source_standing_fire_weight)


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
	# The tree evaluated these published inputs before the priority-100 pose
	# pass. Preserve that frame for chest/weapon presentation before publishing
	# next-frame movement values. This is not a second blend or animation clock.
	evaluated_locomotion_carry_weight = locomotion_carry_weight
	evaluated_carry_direction = rendered_direction
	evaluated_locomotion_source_weight = evaluated_modern_state_weight([&"standing", &"crouch"], delta)
	if jump_lower_body_clip != &"":
		var fade := maxf(float(profile.jump_lower_body.get("blend_seconds", 0.06)), 0.001)
		jump_lower_body_weight = move_toward(jump_lower_body_weight, float(jump_lower_body_active and modern_enabled), maxf(delta, 0.0) / fade)
		animation_tree.set("parameters/jump_lower_body/blend_amount", jump_lower_body_weight)
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
		smoothed_direction = Vector2.from_angle(lerp_angle(
			smoothed_direction.angle(), target_direction.angle(), direction_alpha
		))
	# Interpolate headings, not normalized vector chords: with opposite inputs,
	# lerp(...).normalized() returns the old direction forever at normal frame
	# deltas. Angular easing keeps the cyclic gait alive through a full reversal.
	if posture == &"CROUCHED":
		# This is a blend coordinate, not a heading to normalize. The center
		# point below shares the lateral gait, so A/D cross-fades through the
		# same take instead of detouring through taller backward/diagonal poses.
		rendered_direction = rendered_direction.lerp(target_direction, rendered_direction_alpha)
	else:
		rendered_direction = Vector2.from_angle(lerp_angle(
			rendered_direction.angle(), target_direction.angle(), rendered_direction_alpha
		))
	# Prone already has authored ground-contact timing and a dedicated forward /
	# backward blend. Keep its original direction response so a standing strafe
	# presentation fix cannot shift the crawl phase or lift knees off the floor.
	if posture == &"PRONE":
		rendered_direction = smoothed_direction
	_publish_ready_mask(posture, speed_normalized, ready_weight)
	# Standing uses one continuous sprint matrix. Aim/fire only replaces the
	# upper body; it must never change the lower-body gait back to Rifle Walk.
	var standing_sprint_only := (
		posture == &"STANDING"
		and bool(profile.locomotion.get("standing_sprint_only", false))
		and not source_controller_active
	)
	var target_full_weight: float = (
		1.0
		if standing_sprint_only
		else profile.full_gait_weight(speed_normalized)
	)
	var speed_alpha := 1.0 - exp(-float(profile.locomotion["speed_blend_response"]) * delta)
	var cadence_gait_weight := full_gait_weight
	if source_controller_active and source_policy.complete():
		var source_tiers := source_policy.tier_blends(rendered_direction, actual_speed_mps)
		# Cadence follows current velocity/ranges, not a delayed pose cross-fade.
		# Otherwise reaching full body speed can transiently overclock the clips.
		cadence_gait_weight = source_tiers.y
		jog_gait_weight = lerpf(jog_gait_weight, source_tiers.x, speed_alpha)
		full_gait_weight = lerpf(full_gait_weight, source_tiers.y, speed_alpha)
		source_grounded_clip = source_policy.selected_clip(rendered_direction, jog_gait_weight, full_gait_weight)
	else:
		full_gait_weight = lerpf(full_gait_weight, target_full_weight, speed_alpha)
		cadence_gait_weight = full_gait_weight
	playback_rate = profile.playback_rate(actual_speed_mps, posture, cadence_gait_weight)
	# Short stops preserve the active gait playhead; a stopped body must not keep
	# jogging in place at the ordinary minimum animation rate during that grace.
	var microstep_speed := float(profile.locomotion.get("microstep_speed_mps", 0.0))
	if posture != &"PRONE" and microstep_speed > 0.0:
		playback_rate *= clampf(actual_speed_mps / microstep_speed, 0.0, 1.0)
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
	if source_controller_active:
		animation_tree.set("parameters/jog_space/blend_position", rendered_direction)
		animation_tree.set("parameters/source_walk_jog/blend_amount", jog_gait_weight)
	animation_tree.set("parameters/crouch_space/blend_position", rendered_direction)
	if source_firing_enabled():
		for space_name in ["firing_walk_space", "firing_run_space", "firing_crouch_space"]:
			animation_tree.set("parameters/%s/blend_position" % space_name, rendered_direction)
		animation_tree.set("parameters/firing_speed_blend/blend_amount", full_gait_weight)
		if source_controller_active:
			animation_tree.set("parameters/firing_jog_space/blend_position", rendered_direction)
			animation_tree.set("parameters/source_firing_walk_jog/blend_amount", jog_gait_weight)
	if source_controller_active:
		var walk_weight := (1.0 - full_gait_weight) * (1.0 - jog_gait_weight)
		var jog_weight := (1.0 - full_gait_weight) * jog_gait_weight
		# Match the evaluated locomotion blend, not the independent idle firing fade.
		var fire_weight := float(animation_tree.get("parameters/standing_source_ready/blend_amount")) if source_firing_enabled() else 0.0
		var crouch_ready := float(animation_tree.get("parameters/crouch_source_ready/blend_amount")) if source_firing_enabled() else 0.0
		var standing_weights: Array[float] = [walk_weight * (1.0-fire_weight), jog_weight * (1.0-fire_weight), full_gait_weight * (1.0-fire_weight), walk_weight * fire_weight, jog_weight * fire_weight, full_gait_weight * fire_weight]
		var crouch_weights: Array[float] = [1.0-crouch_ready, crouch_ready]
		gait_phase_sync.apply(animation_tree, &"standing", standing_weights)
		gait_phase_sync.apply(animation_tree, &"crouched", crouch_weights)
	var prone_target := -1.0 if smoothed_direction.y < -0.05 and absf(smoothed_direction.y) >= absf(smoothed_direction.x) * 0.72 else 1.0
	prone_travel_blend = lerpf(prone_travel_blend, prone_target, direction_alpha)
	animation_tree.set("parameters/prone_space/blend_position", prone_travel_blend)
	animation_tree.set("parameters/standing_speed_blend/blend_amount", full_gait_weight)
	for layer_name in standing_transition_layer_nodes:
		animation_tree.set(
			"parameters/%s/blend_amount" % layer_name,
			clampf(ready_weight, 0.0, 1.0) if bool(profile.locomotion.get("preserve_source_locomotion", false)) else 1.0
		)
	for layer_name in airborne_upper_body_layer_nodes:
		animation_tree.set(
			"parameters/%s/blend_amount" % layer_name,
			clampf(ready_weight, 0.0, 1.0) if bool(profile.locomotion.get("preserve_source_locomotion", false)) else 1.0
		)
	animation_tree.set("parameters/standing_time_scale/scale", playback_rate)
	animation_tree.set("parameters/crouch_time_scale/scale", playback_rate)
	animation_tree.set("parameters/prone_time_scale/scale", playback_rate)


func publish_accepted_moving_pistol_ready(posture: StringName, speed_normalized: float) -> void:
	# The accepted event supplies readiness only. Publish its already-defined
	# upper-body weights before the next normal tree evaluation; never advance
	# gait phase, blend direction, route, speed, or an animation clock here.
	if animation_tree == null or not modern_enabled:
		return
	if weapon_handling_profile.get("family", "") != "TWO_HAND_PISTOL" or posture not in [&"STANDING", &"CROUCHED"]:
		return
	_publish_ready_mask(posture, speed_normalized, 1.0)


func _publish_ready_mask(posture: StringName, speed_normalized: float, ready_weight: float) -> void:
	presentation_mode = (
		PRESENTATION_READY_AIM
		if ready_weight >= 0.50
		else PRESENTATION_RELAXED_RIFLE
	)
	var normalized_ready := clampf(ready_weight, 0.0, 1.0)
	var movement_amount := smoothstep(0.08, 0.55, speed_normalized)
	var dynamic_hold: Variant = weapon_handling_profile.get("dynamic_hold", {})
	var ready_locomotion_inheritance := 0.22
	var relaxed_idle_upper_body_weight := 0.0
	var locomotion_ready_carry_weight := 0.0
	if dynamic_hold is Dictionary:
		locomotion_ready_carry_weight = clampf(
			float(dynamic_hold.get("locomotion_ready_carry_weight", 0.0)), 0.0, 1.0
		)
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
		relaxed_idle_upper_body_weight = clampf(
			float(
				(dynamic_hold as Dictionary).get(
					"relaxed_idle_upper_body_weight",
					relaxed_idle_upper_body_weight
				)
			),
			0.0,
			1.0
		)
	if bool(profile.locomotion.get("preserve_source_locomotion", false)):
		# Relaxed source motion owns the whole body. Ready/fire is explicit,
		# with no unrelated gait-arm contribution blended into its held pose.
		locomotion_ready_carry_weight = 0.0
		relaxed_idle_upper_body_weight = 0.0
		ready_locomotion_inheritance = 0.0
	# Aim Idle remains the dominant firing pose, but a moving player retains a
	# small amount of the active rifle-walk torso and arm motion. The right-hand
	# weapon mount therefore breathes with the body instead of looking pinned in
	# space while the legs move underneath it.
	# Movement-only carry reuses the accepted ready silhouette without setting
	# readiness or accepting a shot. Other profiles default to the original path.
	locomotion_carry_weight = (
		locomotion_ready_carry_weight * movement_amount
		if posture in [&"STANDING", &"CROUCHED"] else 0.0
	)
	var moving_pose_ready := maxf(normalized_ready, locomotion_carry_weight)
	upper_body_ready_blend = moving_pose_ready * (
		1.0 - ready_locomotion_inheritance * movement_amount
	)
	if source_firing_enabled():
		# Full directional firing takes own hips, torso and arms together.
		for stance in ["standing", "crouch", "prone"]:
			animation_tree.set("parameters/%s_source_ready/blend_amount" % stance, normalized_ready)
		moving_pose_ready = 0.0
		upper_body_ready_blend = 0.0
	# The relaxed standing pose is the complete Idle Rifle take. Aim Idle enters
	# only when ready/fire owns the upper body; do not mix two unrelated arm poses
	# into the neutral stance.
	var idle_upper_body_blend := normalized_ready
	if posture == &"STANDING" and speed_normalized <= 0.05:
		idle_upper_body_blend = maxf(
			idle_upper_body_blend,
			relaxed_idle_upper_body_weight
		)
	animation_tree.set(
		"parameters/standing_upper_body/blend_amount",
		upper_body_ready_blend
	)
	animation_tree.set(
		"parameters/standing_aim_frame/blend_amount",
		moving_pose_ready
	)
	animation_tree.set(
		"parameters/standing_idle_upper_body/blend_amount",
		0.0 if source_firing_enabled() else idle_upper_body_blend
	)
	animation_tree.set(
		"parameters/standing_idle_aim_frame/blend_amount",
		normalized_ready
	)
	animation_tree.set(
		"parameters/crouch_upper_body/blend_amount",
		moving_pose_ready
	)
	animation_tree.set(
		"parameters/crouch_aim_frame/blend_amount",
		moving_pose_ready
	)
	animation_tree.set(
		"parameters/crouch_idle_upper_body/blend_amount",
		0.0 if source_firing_enabled() else normalized_ready
	)
	animation_tree.set(
		"parameters/crouch_idle_aim_frame/blend_amount",
		normalized_ready
	)
	for ready_name in standing_transition_ready_nodes:
		animation_tree.set(
			"parameters/%s/blend_amount" % ready_name,
			normalized_ready
		)
	for aim_frame_name in standing_transition_aim_frame_nodes:
		animation_tree.set(
			"parameters/%s/blend_amount" % aim_frame_name,
			normalized_ready
		)
	animation_tree.set("parameters/standing_upper_ready_blend/blend_amount", moving_pose_ready)


func source_grounded_blend_seconds(from_state: StringName, to_state: StringName, fallback: float) -> float:
	if not bool(profile.locomotion.get("source_idle_blending", false)) \
			or weapon_handling_profile.get("family", "") != "TWO_HAND_RIFLE":
		return fallback
	# This first pass only interprets the destination idle's BlendTime. Do not
	# infer missing gait timings, playback enums, action exits or PS2 blend curves.
	if from_state not in [&"standing", &"idle", &"crouch", &"idle_crouch"]:
		return fallback
	var seconds := float(source_idle_blend_times.get(to_state, -1.0))
	return seconds if seconds >= 0.0 else fallback


func request_modern_state(state_name: StringName, blend_seconds: float = -1.0) -> bool:
	if animation_tree == null or not modern_state_indices.has(state_name):
		return false
	_update_jump_lower_body_state(state_name)
	var actual_state := StringName(
		animation_tree.get("parameters/modern_transition/current_state")
	)
	var dynamic_hold: Dictionary = weapon_handling_profile.get("dynamic_hold", {})
	var preserve_ready_handoff: bool = (
		modern_enabled
		and weapon_handling_profile.get("family", "") == "TWO_HAND_PISTOL"
		and bool(dynamic_hold.get("authored_compressed_idle_enabled", false))
		and upper_body_ready_blend > 0.001
		and _same_stationary_locomotion_pair(actual_state, state_name)
	)
	if preserve_ready_handoff:
		var previous_index := int(animation_tree.get("parameters/modern_transition/prev_index"))
		var previous_state := (
			StringName(modern_transition.get_input_name(previous_index))
			if previous_index >= 0 and previous_index < modern_transition.input_count
			else &""
		)
		if (
			_same_stationary_locomotion_pair(actual_state, previous_state)
			and float(animation_tree.get("parameters/modern_transition/prev_xfading")) > 0.0
		):
			# Finish the current same-stance pose cross-fade before reversing it.
			# The driver repeats current input every frame, so there is no stale
			# queue or second clock. Actions and posture changes never enter here.
			current_state = actual_state
			return true
		if actual_state != state_name:
			var ready_aim: Dictionary = weapon_handling_profile.get("ready_aim", {})
			var requested_blend := blend_seconds if blend_seconds >= 0.0 else modern_transition.xfade_time
			modern_transition.xfade_time = maxf(
				requested_blend,
				maxf(float(ready_aim.get("locomotion_blend_seconds", 0.0)), 0.0)
			)
	elif blend_seconds >= 0.0:
		var source_policy: bool = bool(profile.locomotion.get("source_idle_blending", false)) \
			and weapon_handling_profile.get("family", "") == "TWO_HAND_RIFLE"
		# Repeated input must not replace a chosen source fade with the driver's
		# fallback, or turn a reload-to-idle fade into a grounded-to-idle fade.
		if not source_policy or actual_state != state_name:
			modern_transition.xfade_time = maxf(source_grounded_blend_seconds(actual_state, state_name, blend_seconds), 0.0)
	# Continuous locomotion calls this every driver pass. A same-state request is
	# not a new animation event and must not touch the active playhead.
	if actual_state == state_name:
		current_state = state_name
		return true
	current_state = state_name
	animation_tree.set("parameters/modern_transition/transition_request", state_name)
	return true


func _build_jump_lower_body_layer(root: AnimationNodeBlendTree, available_clips: Dictionary) -> StringName:
	var settings: Dictionary = profile.jump_lower_body
	var selected := StringName(settings.get("clip", ""))
	if not bool(settings.get("enabled", false)) or selected == &"" or not available_clips.has(selected):
		return &"route_blend"
	jump_lower_body_clip = selected
	root.add_node(&"jump_lower_body_animation", _animation_node(selected), Vector2(980.0, -170.0))
	root.add_node(&"jump_lower_body_seek", AnimationNodeTimeSeek.new(), Vector2(1140.0, -170.0))
	root.connect_node(&"jump_lower_body_seek", 0, &"jump_lower_body_animation")
	var legs := AnimationNodeBlend2.new()
	legs.sync = false
	legs.filter_enabled = true
	for bone: StringName in JUMP_LEG_BONES:
		legs.set_filter_path(NodePath(".:%s" % bone), true)
	for bone: StringName in JUMP_ARM_BONES:
		legs.set_filter_path(NodePath(".:%s" % bone), true)
	for bone: StringName in JUMP_TORSO_BONES:
		legs.set_filter_path(NodePath(".:%s" % bone), true)
	root.add_node(&"jump_lower_body", legs, Vector2(1230.0, 100.0))
	root.connect_node(&"jump_lower_body", 0, &"route_blend")
	root.connect_node(&"jump_lower_body", 1, &"jump_lower_body_seek")
	return &"jump_lower_body"


func _update_jump_lower_body_state(state_name: StringName) -> void:
	if jump_lower_body_clip == &"" or not modern_enabled:
		return
	# A fall from a ledge is not a new jump. Only takeoff starts this presentation
	# playhead; apex/fall (including pistol slots) continue it without a restart.
	var takeoff := state_name in [&"jump_up", &"jump_up_standing", &"pistol_jump"]
	var airborne := takeoff or state_name in [&"jump_loop", &"jump_running_air", &"pistol_jump", &"pistol_jump_alt"]
	if takeoff and not jump_lower_body_active:
		jump_lower_body_entry_count += 1
		animation_tree.set("parameters/jump_lower_body_seek/seek_request", 0.0)
		jump_lower_body_active = true
	elif not airborne:
		jump_lower_body_active = false


func _bind_jump_source_frame(target: Skeleton3D, player: AnimationPlayer) -> void:
	jump_frame_source = null
	jump_frame_hips_index = -1
	jump_frame_hip_chain.clear()
	jump_frame_thighs.clear()
	if target == null or jump_lower_body_clip == &"" or not bool(profile.jump_lower_body.get("match_source_parent_frame", false)):
		return
	if not player.has_animation(jump_lower_body_clip):
		return
	var source := player.get_animation(jump_lower_body_clip)
	var rotation_tracks: Dictionary = {}
	for track in source.get_track_count():
		if source.track_get_type(track) != Animation.TYPE_ROTATION_3D:
			continue
		var path := source.track_get_path(track)
		if path.get_subname_count() > 0:
			rotation_tracks[StringName(path.get_subname(path.get_subname_count() - 1))] = track
	jump_frame_hips_index = target.find_bone("mixamorig_Hips")
	if jump_frame_hips_index < 0:
		return
	var parent := jump_frame_hips_index
	while parent >= 0:
		jump_frame_hip_chain.push_front({
			"track": int(rotation_tracks.get(StringName(target.get_bone_name(parent)), -1)),
			"rest": target.get_bone_rest(parent).basis.orthonormalized().get_rotation_quaternion().normalized(),
		})
		parent = target.get_bone_parent(parent)
	for bone: StringName in [&"mixamorig_LeftUpLeg", &"mixamorig_RightUpLeg"]:
		var index := target.find_bone(bone)
		if index < 0 or target.get_bone_parent(index) != jump_frame_hips_index or not rotation_tracks.has(bone):
			jump_frame_thighs.clear()
			return
		jump_frame_thighs.append({"index": index, "track": int(rotation_tracks[bone])})
	jump_frame_source = source


func get_evaluated_jump_source_frame() -> Vector2:
	if animation_tree == null or jump_frame_source == null:
		return Vector2.ZERO
	return Vector2(
		float(animation_tree.get("parameters/jump_lower_body/blend_amount")),
		float(animation_tree.get("parameters/jump_lower_body_animation/current_position"))
	)


func apply_jump_source_frame(target: Skeleton3D, evaluated_frame := Vector2(-1.0, -1.0)) -> void:
	# The graph evaluated these local leg tracks under its selected base hips.
	# Rebase only their two roots into the imported source's parent frame, using
	# this same evaluated playhead/weight captured before graph commands change.
	# Apply after posture finalizes the parent hips. No second animation clock.
	if not modern_enabled or animation_tree == null or target == null or jump_frame_source == null:
		return
	var frame := get_evaluated_jump_source_frame() if evaluated_frame.x < 0.0 else evaluated_frame
	var amount := clampf(frame.x, 0.0, 1.0)
	if amount <= 0.001 or not bool(profile.jump_lower_body.get("match_source_parent_frame", false)):
		return
	var time := frame.y
	var source_hips := Quaternion.IDENTITY
	for item: Dictionary in jump_frame_hip_chain:
		var rotation: Quaternion = jump_frame_source.rotation_track_interpolate(int(item.track), time) if int(item.track) >= 0 else item.rest
		source_hips = (source_hips * rotation).normalized()
	var current_hips := target.get_bone_global_pose(jump_frame_hips_index).basis.orthonormalized().get_rotation_quaternion().normalized()
	var parent_delta := (current_hips.inverse() * source_hips).normalized()
	for item: Dictionary in jump_frame_thighs:
		var index := int(item.index)
		var desired := (parent_delta * jump_frame_source.rotation_track_interpolate(int(item.track), time)).normalized()
		var current := target.get_bone_pose_rotation(index).normalized()
		target.set_bone_pose_rotation(index, current.slerp(desired, amount).normalized())


func _same_stationary_locomotion_pair(first: StringName, second: StringName) -> bool:
	return (
		(first in [&"idle", &"standing"] and second in [&"idle", &"standing"])
		or (first in [&"idle_crouch", &"crouch"] and second in [&"idle_crouch", &"crouch"])
	)


func authored_stationary_pose_weight(delta: float) -> float:
	if (
		not modern_enabled
		or animation_tree == null
		or modern_transition == null
		or weapon_handling_profile.get("family", "") != "TWO_HAND_PISTOL"
	):
		return 0.0
	var dynamic_hold: Dictionary = weapon_handling_profile.get("dynamic_hold", {})
	if not bool(dynamic_hold.get("authored_compressed_idle_enabled", false)):
		return 0.0
	return evaluated_modern_state_weight([&"idle", &"idle_crouch"], delta)


func evaluated_modern_state_weight(states: Array[StringName], delta: float) -> float:
	if not modern_enabled or animation_tree == null or modern_transition == null:
		return 0.0
	# Read the pose already evaluated this frame, before the driver queues a new
	# state or changes xfade_time. AnimationTree runs at idle priority 0; the pose
	# coordinator runs at 100 with this same unscaled frame delta.
	var current_index := int(animation_tree.get("parameters/modern_transition/current_index"))
	if current_index < 0 or current_index >= modern_transition.input_count:
		return 0.0
	var current_native := float(
		modern_transition.get_input_name(current_index) in states
	)
	var previous_index := int(animation_tree.get("parameters/modern_transition/prev_index"))
	if (
		previous_index < 0
		or previous_index >= modern_transition.input_count
		or modern_transition.xfade_time <= 0.0
	):
		return current_native
	# Godot 4.7.1 exposes these runtime parameters in release builds as well.
	# Transition blends using the old remainder, then subtracts abs(delta). Add
	# that delta back to recover the actual pose weight, not next frame's weight.
	# Do not use current_delta: child locomotion TimeScale nodes can scale it.
	var remaining := float(animation_tree.get("parameters/modern_transition/prev_xfading"))
	var previous_weight := clampf(
		(remaining + absf(delta)) / modern_transition.xfade_time, 0.0, 1.0
	)
	if modern_transition.xfade_curve != null:
		previous_weight = clampf(modern_transition.xfade_curve.sample(previous_weight), 0.0, 1.0)
	var previous_native := float(
		modern_transition.get_input_name(previous_index) in states
	)
	return lerpf(current_native, previous_native, previous_weight)


func request_legacy_clip(clip_name: StringName, blend_seconds: float) -> bool:
	if animation_tree == null or not legacy_clip_indices.has(clip_name):
		return false
	# A held request is not another entry event. Preserve the fade selected at
	# entry, just as the source-enabled route preserves its active transition.
	if StringName(animation_tree.get("parameters/legacy_transition/current_state")) == clip_name:
		return true
	legacy_transition.xfade_time = maxf(blend_seconds, 0.0)
	animation_tree.set("parameters/legacy_transition/transition_request", clip_name)
	return true


func set_clip_playback_speed(clip_name: StringName, playback_speed: float) -> void:
	if animation_tree == null:
		return
	var resolved_speed := clampf(playback_speed, 0.25, 3.0)
	if modern_clip_time_scale_paths.has(clip_name):
		animation_tree.set(modern_clip_time_scale_paths[clip_name], resolved_speed)
	if legacy_clip_time_scale_paths.has(clip_name):
		animation_tree.set(legacy_clip_time_scale_paths[clip_name], resolved_speed)


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
		_configure_fire_filter(normalized_posture)
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


func _configure_fire_filter(posture: StringName) -> void:
	if fire_layer_node == null:
		return
	# Source ready locomotion owns the direction-specific firing stance.
	# Keep accepted-event timing and separate recoil; do not replace its arms
	# with the generic stationary OneShot on every accepted shot.
	var source_rifle := source_rifle_fire_pose(posture)
	if source_rifle:
		fire_layer_node.filter_enabled = true
	for bone_name: StringName in UPPER_BODY_BONES:
		var owns_bone := not source_rifle and bone_name not in FIRE_EXCLUDED_BONES
		if posture == &"PRONE" and bone_name in PRONE_FIRE_STABLE_FRAME_BONES:
			owns_bone = false
		if posture == &"PRONE" and bool(crouched_reload_pose.settings.stable_prone_fire_arms) \
				and bone_name in [&"mixamorig_RightArm", &"mixamorig_RightForeArm", &"mixamorig_LeftArm", &"mixamorig_LeftForeArm"]:
			owns_bone = false
		fire_layer_node.set_filter_path(NodePath(".:%s" % bone_name), owns_bone)


func source_rifle_fire_pose(posture: StringName) -> bool:
	return source_firing_enabled() and weapon_handling_profile.get("family", "") == "TWO_HAND_RIFLE" and posture in [&"STANDING", &"CROUCHED"]


func trigger_crouched_reload(clip_name: StringName) -> bool:
	if (
		animation_tree == null
		or not crouched_reload_layer_available
		or crouched_reload_animation_node == null
		or clip_name == &""
	):
		return false
	# This lower reload layer is also the prone entry route. It remains alive
	# while the locomotion graph changes posture underneath it, so one accepted
	# reload has one uninterrupted visual playhead across prone/crouch/stand.
	crouched_reload_animation_node.animation = clip_name
	crouched_reload_pose.start(clip_name)
	active_reload_pose = crouched_reload_pose
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
		or standing_reload_animation_node == null
		or clip_name == &""
	):
		return false
	standing_reload_animation_node.animation = clip_name
	standing_reload_pose.start(clip_name)
	active_reload_pose = standing_reload_pose
	animation_tree.set(
		"parameters/standing_reload_layer/request",
		AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE
	)
	standing_reload_trigger_count += 1
	return true


func cancel_reload_layers() -> void:
	active_reload_pose = null
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
		"source_controller_active": source_controller_active,
		"source_grounded_clip": source_grounded_clip,
		"jog_gait_weight": jog_gait_weight,
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
		"locomotion_carry_weight": locomotion_carry_weight,
	}


func _build_crouched_reload_layer(
	root: AnimationNodeBlendTree,
	available_clips: Dictionary,
	base_source: StringName = &"route_blend"
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
	crouched_reload_animation_node = _animation_node(crouched_reload_clip)
	root.add_node(
		&"crouched_reload_animation",
		crouched_reload_animation_node,
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
	root.connect_node(&"crouched_reload_layer", 0, base_source)
	root.connect_node(&"crouched_reload_layer", 1, crouched_reload_pose.build(root, "crouched_reload", crouched_reload_animation_node))
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
	standing_reload_animation_node = _animation_node(standing_reload_clip)
	root.add_node(
		&"standing_reload_animation",
		standing_reload_animation_node,
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
	root.connect_node(&"standing_reload_layer", 1, standing_reload_pose.build(root, "standing_reload", standing_reload_animation_node))
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
	# Fire owns the torso, both clavicles, and the complete arm/hand chains. The
	# posture stage keeps the head, then the muzzle stage aligns the physical
	# barrel to authoritative shot direction and hand IK closes the contacts.
	for bone_name: StringName in UPPER_BODY_BONES:
		if bone_name not in FIRE_EXCLUDED_BONES:
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
	var combo_profile: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://config/jump_direction_combos.json"))
	var death_profile: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://config/operator_death.json"))
	legacy_transition = AnimationNodeTransition.new()
	legacy_transition.input_count = available_clips.size()
	legacy_transition.xfade_time = 0.08
	root.add_node(&"legacy_transition", legacy_transition, Vector2(640.0, -260.0))
	var index := 0
	for raw_clip_name in available_clips.keys():
		var clip_name := StringName(raw_clip_name)
		var node_name := StringName("legacy_%s" % clip_name)
		var source_name := node_name
		legacy_transition.set_input_name(index, clip_name)
		root.add_node(node_name, _animation_node(clip_name), Vector2(-900.0, -500.0 + index * 30.0))
		if String(clip_name).begins_with("traversal_") or String(clip_name) in combo_profile.clips.values() or String(clip_name) in combo_profile.crouch_clips.values() or String(clip_name) in [death_profile.standing_clip, death_profile.crouched_clip, death_profile.prone_clip]:
			var seek_name := StringName("%s_combo_seek" % node_name)
			root.add_node(seek_name, AnimationNodeTimeSeek.new(), Vector2(-760.0, -500.0 + index * 30.0))
			root.connect_node(seek_name, 0, source_name)
			source_name = seek_name
			combo_seek_paths[clip_name] = [StringName("parameters/%s/seek_request" % seek_name)]
		if _uses_action_time_scale(clip_name):
			var scale_name := StringName("%s_time_scale" % node_name)
			root.add_node(scale_name, AnimationNodeTimeScale.new(), Vector2(-650.0, -500.0 + index * 30.0))
			root.connect_node(scale_name, 0, node_name)
			source_name = scale_name
			legacy_clip_time_scale_paths[clip_name] = StringName("parameters/%s/scale" % scale_name)
		root.connect_node(&"legacy_transition", index, source_name)
		legacy_clip_indices[clip_name] = index
		index += 1


func _build_modern_route(root: AnimationNodeBlendTree, available_clips: Dictionary) -> void:
	ModernRouteBuilder.build(self, root, available_clips)

func sync_jump_combo(clip_name: StringName, elapsed: float) -> void:
	if combo_seek_paths.has(clip_name):
		for path: StringName in combo_seek_paths[clip_name]:
			animation_tree.set(path, maxf(elapsed, 0.0))

func source_jump_clip(clip: StringName) -> bool:
	return bool(profile.locomotion.get("preserve_source_locomotion", false)) and bool(profile.source_jump.get("enabled", false)) and profile.source_jump.get("clips", {}).has(String(clip)) and is_source_clip(String(profile.clip_paths.get(clip, "")))

func sync_source_jump(clip: StringName, time: float) -> void:
	if source_jump_seek_paths.has(clip):
		animation_tree.set(source_jump_seek_paths[clip], maxf(time, 0.0))

func evaluated_source_jump_weight(delta: float) -> float:
	var states: Array[StringName] = []
	states.assign(source_jump_seek_paths.keys())
	return evaluated_modern_state_weight(states, delta)


func source_firing_enabled() -> bool:
	return bool(profile.locomotion.get("preserve_source_locomotion", false)) and bool(profile.locomotion.get("source_firing_locomotion", false))


static func is_source_clip(path: String) -> bool:
	# A source-looking filename outside these project-owned folders is not
	# provenance. Reject traversal/non-canonical spellings before caching them.
	if path != path.simplify_path() or not path.ends_with(".tres"):
		return false
	var native_reference := path.begins_with("res://assets/animations/seal_reference/")
	var processed_source := path.begins_with("res://assets/animations/seal_gameplay/") or path.begins_with("res://assets/animations/seal_firing_reference/")
	if not native_reference and not processed_source:
		return false
	if source_clip_classification_cache.has(path):
		return bool(source_clip_classification_cache[path])
	var accepted := false
	if ResourceLoader.exists(path, "Animation"):
		var animation := ResourceLoader.load(path, "Animation") as Animation
		if animation != null:
			# Keep derived gameplay/firing resources classified: coherent jump
			# windows carry source_asset metadata and need not have source_name.
			accepted = processed_source
			if native_reference:
				var marker: Variant = animation.get_meta("seal_reference", false)
				var source_name := String(animation.get_meta("source_name", ""))
				accepted = marker is bool and marker and source_name == path.get_file().get_basename() and (source_name.begins_with("seal_") or source_name.begins_with("death_"))
	source_clip_classification_cache[path] = accepted
	return accepted


func _configure_source_controller(available_clips: Dictionary) -> void:
	# Validate before choosing graph topology, so incomplete metadata really
	# retains the previous controller rather than a half-enabled source graph.
	source_controller_active = false
	source_policy = SourceLocomotionPolicy.new()
	source_grounded_clip = &""
	jog_gait_weight = 0.0
	if not modern_enabled or not bool(profile.locomotion.get("source_three_tier", false)) \
			or not bool(profile.locomotion.get("preserve_source_locomotion", false)) \
			or weapon_handling_profile.get("family", "") != "TWO_HAND_RIFLE":
		return
	for prefix: StringName in [&"walk", &"jog", &"run"]:
		for suffix: StringName in [&"forward", &"backward", &"left", &"right"]:
			var logical := StringName("%s_%s" % [prefix, suffix])
			var clip := _weapon_locomotion_clip(String(logical), logical, available_clips, false, false)
			var path := String(profile.clip_paths.get(clip, ""))
			if available_clips.has(clip) and is_source_clip(path):
				source_policy.register(prefix, suffix, clip, path)
	source_controller_active = source_policy.complete()


func _direction_space(prefix: StringName, available_clips: Dictionary, firing := false) -> AnimationNodeBlendSpace2D:
	var space := AnimationNodeBlendSpace2D.new()
	var source_only := bool(profile.locomotion.get("preserve_source_locomotion", false))
	# Godot 4.7's old `sync = true` means independent clocks, not matching gait
	# phase. Cyclic Mutable normalizes every directional point to one foot cycle.
	space.sync_mode = AnimationNodeBlendSpace2D.SYNC_MODE_CYCLIC_MUTABLE
	space.min_space = Vector2(-1.0, -1.0)
	space.max_space = Vector2(1.0, 1.0)
	space.x_label = "Strafe"
	space.y_label = "Forward"
	if prefix == &"crouch":
		var center_clip := _weapon_locomotion_clip("crouch_forward", &"crouch_forward", available_clips, firing)
		if available_clips.has(center_clip):
			space.add_blend_point(_animation_node(center_clip), Vector2.ZERO, -1, &"center")
	for suffix: StringName in DIRECTION_POINTS:
		if bool(profile.locomotion.get("preserve_source_locomotion", false)) and suffix not in [&"forward", &"backward", &"left", &"right"]:
			# Diagonals interpolate the actual cardinal takes, never legacy mirrored
			# legs. All points retain the existing shared gait phase.
			continue
		var logical_name := StringName("%s_%s" % [prefix, suffix])
		var clip_name := _weapon_locomotion_clip(String(logical_name), logical_name, available_clips, firing)
		if available_clips.has(clip_name):
			source_only = source_only and is_source_clip(String(profile.clip_paths.get(clip_name, "")))
			space.add_blend_point(
				_animation_node(clip_name),
				DIRECTION_POINTS[suffix],
				-1,
				suffix
			)
	source_cardinal_spaces[String(prefix) + ("_firing" if firing else "")] = source_only and space.get_blend_point_count() >= 4
	return space


func source_gait_is_active() -> bool:
	if not modern_enabled:
		return false
	if current_state == &"standing":
		return bool(source_cardinal_spaces.get(&"walk", false)) and bool(source_cardinal_spaces.get(&"run", false))
	return current_state == &"crouch" and bool(source_cardinal_spaces.get(&"crouch", false))


func _weapon_locomotion_clip(
	slot_name: String,
	fallback: StringName,
	available_clips: Dictionary,
	firing := false,
	allow_arbitrary_fallback := true
) -> StringName:
	var routes: Dictionary = weapon_handling_profile.get("locomotion_slots", {})
	var family := StringName(weapon_handling_profile.get("family", ""))
	var override_clip: StringName = profile.resolve_family_animation_slot(family, ("locomotion_ready/" if firing else "locomotion/") + slot_name, available_clips)
	if override_clip != &"":
		return override_clip
	var candidate := StringName(routes.get(slot_name, ""))
	if candidate != &"" and available_clips.has(candidate):
		return candidate
	if not allow_arbitrary_fallback and not available_clips.has(fallback):
		return &""
	return _fallback_clip(fallback, available_clips)


func _weapon_action_clip(
	slot_name: String,
	fallback: StringName,
	available_clips: Dictionary
) -> StringName:
	# Explicit animation-set overrides share the saved profile with the runtime.
	# Sparse or invalid overrides preserve the weapon's existing slot contract.
	var family := StringName(weapon_handling_profile.get("family", ""))
	var override_clip: StringName = profile.resolve_family_animation_slot(family, slot_name, available_clips)
	if override_clip != &"":
		return override_clip
	var routes: Dictionary = weapon_handling_profile.get("animation_slots", {})
	var candidate := StringName(routes.get(slot_name, ""))
	if candidate != &"" and available_clips.has(candidate):
		return candidate
	return _fallback_clip(fallback, available_clips)


func _prone_direction_space(available_clips: Dictionary) -> AnimationNodeBlendSpace1D:
	var space := AnimationNodeBlendSpace1D.new()
	space.sync_mode = AnimationNodeBlendSpace1D.SYNC_MODE_CYCLIC_MUTABLE
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


func _uses_upper_body_ready_layer(clip_name: StringName) -> bool:
	if source_jump_clip(clip_name) or (jump_lower_body_clip != &"" and clip_name == jump_lower_body_clip):
		# A source jump or jump action clip already owns torso/arms. The standing
		# fire-ready pose must not replace them mid-jump when accepted-shot grace is active.
		return false
	return _is_standing_locomotion_transition(clip_name) or _is_jump_mobility_clip(clip_name)


func _is_jump_mobility_clip(clip_name: StringName) -> bool:
	return clip_name in [&"jump_up", &"jump_loop", &"jump_down"]


func _animation_node(clip_name: StringName) -> AnimationNodeAnimation:
	var node := AnimationNodeAnimation.new()
	node.animation = clip_name
	if source_jump_clip(clip_name):
		node.use_custom_timeline = true
		node.stretch_time_scale = false
		node.timeline_length = float(profile.source_jump.clips[String(clip_name)].end_seconds)
		node.loop_mode = Animation.LOOP_NONE
	return node


func _fallback_clip(preferred: StringName, available_clips: Dictionary) -> StringName:
	if available_clips.has(preferred):
		return preferred
	return StringName(available_clips.keys()[0]) if not available_clips.is_empty() else &""


func _is_directional_locomotion(clip_name: StringName) -> bool:
	var text := String(clip_name)
	for suffix: StringName in DIRECTION_POINTS:
		if text in ["walk_%s" % suffix, "jog_%s" % suffix, "run_%s" % suffix, "crouch_%s" % suffix]:
			return true
	return false


func _uses_action_time_scale(clip_name: StringName) -> bool:
	return "grenade" in String(clip_name).to_lower()
