class_name SocomOperatorAnimationDriver
extends Node3D

signal action_completed(clip_name: StringName)
signal action_cancelled(clip_name: StringName)
signal action_release_cue(clip_name: StringName)
signal weapon_family_changed(weapon_id: StringName, family: StringName)

## Thin visual coordinator. CharacterBody owns movement; the camera owns aim.
## Asset loading, blending, transitions, posture and IK contracts are isolated.

const AnimationProfile := preload("res://scripts/player/operator_animation_profile.gd")
const AnimationStateContract := preload("res://scripts/player/operator_animation_state_contract.gd")
const PresentationRouter := preload("res://scripts/player/operator_presentation_router.gd")
const AssetRuntime := preload("res://scripts/player/operator_asset_runtime.gd")
const WeaponContract := preload("res://scripts/weapons/weapon_rig_contract.gd")
const WeaponReloadVisualTimeline := preload("res://scripts/weapons/weapon_reload_visual_timeline.gd")
const LocomotionBlendTree := preload("res://scripts/player/operator_locomotion_blend_tree.gd")
const TransitionStateMachine := preload("res://scripts/player/operator_transition_state_machine.gd")
const PostureLayer := preload("res://scripts/player/operator_posture_layer.gd")
const IKContract := preload("res://scripts/player/operator_ik_contract.gd")
const WeaponPoseSolver := preload("res://scripts/player/operator_weapon_pose_solver.gd")
const WeaponEquipmentRuntime := preload(
	"res://scripts/player/operator_weapon_equipment_runtime.gd"
)
const AnimationAudioEvents := preload("res://scripts/audio/audio_animation_event_manager.gd")
const AnimationFramePoseRuntime := preload(
	"res://scripts/player/operator_animation_frame_pose_runtime.gd"
)
const GrenadeReleaseTimeline := preload(
	"res://scripts/tactical/grenade_animation_release_timeline.gd"
)

@export_group("Runtime route")
@export var use_modern_locomotion: bool = true
@export var use_weapon_socket_contract: bool = true

@export_group("Visual tuning")
@export var trooper_scale: float = 62.0
@export var dive_roll_trim_duration: float = 0.78
@export var roll_trim_duration: float = 0.62
@export_range(0.02, 0.40, 0.01) var transition_blend_seconds: float = 0.12
@export_range(0.02, 0.14, 0.005) var locomotion_blend_seconds: float = 0.075
@export_range(0.02, 0.20, 0.005) var locomotion_enter_speed: float = 0.10
@export_range(0.01, 0.18, 0.005) var locomotion_exit_speed: float = 0.055
@export_range(0.0, 18.0, 0.5) var direction_hysteresis_deg: float = 7.5
@export_range(0.0, 90.0, 0.5) var chest_yaw_limit_deg: float = 42.0
@export_range(0.0, 60.0, 0.5) var chest_pitch_limit_deg: float = 28.0
@export_range(0.0, 90.0, 0.5) var head_yaw_limit_deg: float = 56.0
@export_range(0.0, 60.0, 0.5) var head_pitch_limit_deg: float = 34.0
@export_range(0.0, 0.5, 0.01) var upper_body_gait_roll_retention: float = 0.18
@export_range(0.0, 3.0, 0.05) var neutral_hip_roll_trim_deg: float = 1.50
@export_range(0.0, 18.0, 0.5) var prone_axis_target_pitch_deg: float = 0.0
@export_range(0.0, 120.0, 0.5) var prone_axis_max_correction_deg: float = 90.0
@export_range(1.0, 30.0, 0.5) var prone_straighten_response: float = 14.0
@export_range(6.0, 18.0, 0.1) var maximum_leg_rotation_deg_per_60hz: float = 9.8
@export_range(0.20, 4.0, 0.05) var fire_ready_hold_seconds: float = 1.20
@export_range(1.0, 30.0, 0.5) var ready_enter_response: float = 24.0
@export_range(1.0, 30.0, 0.5) var ready_exit_response: float = 8.0

var animation_profile
var presentation_router
var asset_runtime
var locomotion_graph
var transition_state_machine
var posture_layer
var ik_contract
var weapon_pose_solver
var audio_event_manager: AudioAnimationEventManager
var animation_frame_pose_runtime

# Public runtime references retained for labs, debug views and regressions.
var model_root: Node3D
var animation_player: AnimationPlayer
var animation_tree: AnimationTree
var transition_node: AnimationNodeTransition
var skeleton: Skeleton3D
var dynamic_anim_lib: AnimationLibrary
var weapon_attachment: BoneAttachment3D
var weapon_node: Node3D
var available_clips: Dictionary = {}
var source_animation_names: Dictionary = {}
var clip_paths: Dictionary = {}
var equipped_weapon_handling_profile: Dictionary = {}
var equipped_weapon_config: Dictionary = {}
var equipped_weapon_family: StringName = &"TWO_HAND_RIFLE"

var current_clip: StringName = &""
var previous_clip: StringName = &""
var requested_action: StringName = &""
var requested_action_remaining: float = 0.0
var requested_action_total_duration: float = 0.0
var requested_action_playback_speed: float = 1.0
var right_grip_pos := Vector3(-0.02, 0.08, 0.05)
var right_grip_rot := Vector3(-90.0, 180.0, 0.0)

# Visual inputs supplied by gameplay/network snapshots.
var movement_direction := Vector2.ZERO
var movement_speed_normalized: float = 0.0
var movement_speed_mps: float = 0.0
var movement_gait: StringName = &"WALK"
var movement_intent_direction := Vector2.ZERO
var movement_intent_strength: float = 0.0
var movement_response_mode: StringName = &"IDLE"
var posture: StringName = &"STANDING"
var movement_state: StringName = &"LOCOMOTION"
var aim_yaw_rad: float = 0.0
var aim_pitch_rad: float = 0.0
var weapon_ready_weight: float = 0.0
var requested_weapon_ready_weight: float = 0.0
var firing: bool = false
var obstruction_amount: float = 0.0
var vertical_speed: float = 0.0
var visual_aim_target := Vector3.ZERO
var peek_amount: float = 0.0

var _explicit_visual_inputs: bool = false
var _previous_firing: bool = false
var _previous_movement_state: StringName = &"LOCOMOTION"
var _locomotion_active: bool = false
var _direction_initialized: bool = false
var _stable_direction_octant: int = 0
var _last_transition_reason: StringName = &"none"
var _requested_action_is_transition: bool = false
var _prone_straighten_weight: float = 0.0
var _previous_posture: StringName = &""
var _stabilized_leg_rotations: Dictionary = {}
var _frame_pose_clip_time: float = 0.0
var _active_frame_pose: Dictionary = {}
var _fire_pose_clip: StringName = &""
var _fire_pose_time: float = 0.0
var _fire_pose_duration: float = 0.0
var _last_event_presentation: Dictionary = {}
var _active_reload_visual_slot: String = ""
var _active_reload_visual_clip: StringName = &""
var _reload_visual_time: float = 0.0
var _reload_support_regrip: bool = false
var _requested_action_upper_body_layered: bool = false
var _requested_action_release_cue_emitted: bool = false
var _standing_master_pose_frame_suppressed: bool = false
var _equipped_weapon_visible: bool = true
var _fire_ready_hold_remaining: float = 0.0


func _ready() -> void:
	process_priority = 100
	animation_profile = AnimationProfile.new()
	animation_profile.load_project_map()
	presentation_router = PresentationRouter.new()
	presentation_router.configure(
		animation_profile.clip_paths,
		animation_profile.state_rules,
		animation_profile.event_routes
	)
	equipped_weapon_config = WeaponContract.load_equipped_config()
	var handling: Variant = equipped_weapon_config.get("handling_profile", {})
	equipped_weapon_handling_profile = (
		(handling as Dictionary).duplicate(true) if handling is Dictionary else {}
	)
	equipped_weapon_family = StringName(
		equipped_weapon_handling_profile.get("family", "TWO_HAND_RIFLE")
	)
	animation_frame_pose_runtime = AnimationFramePoseRuntime.new()
	animation_frame_pose_runtime.configure(
		equipped_weapon_config.get("animation_frame_pose_keys", {})
	)
	clip_paths = animation_profile.clip_paths
	transition_state_machine = TransitionStateMachine.new()
	posture_layer = PostureLayer.new()
	asset_runtime = AssetRuntime.new()
	var runtime: Dictionary = asset_runtime.build(
		self,
		animation_profile,
		trooper_scale,
		right_grip_pos,
		right_grip_rot
	)
	model_root = runtime["model_root"]
	animation_player = runtime["animation_player"]
	skeleton = runtime["skeleton"]
	weapon_attachment = runtime["weapon_attachment"]
	weapon_node = runtime["weapon_node"]
	dynamic_anim_lib = runtime["animation_library"]
	available_clips = runtime["available_clips"]
	source_animation_names = runtime["source_animation_names"]
	if animation_player == null or skeleton == null:
		return
	_build_animation_tree()
	posture_layer.bind(skeleton, _neutral_pose_hip_rotation())
	ik_contract = IKContract.new()
	ik_contract.name = "OperatorIKContract"
	add_child(ik_contract)
	ik_contract.bind(skeleton, weapon_node)
	weapon_pose_solver = WeaponPoseSolver.new()
	weapon_pose_solver.name = "WeaponPoseSolver"
	weapon_pose_solver.use_weapon_socket_contract = use_weapon_socket_contract
	add_child(weapon_pose_solver)
	weapon_pose_solver.bind(skeleton, weapon_node)
	weapon_pose_solver.configure_joint_poles(equipped_weapon_config.get("elbow_poles", {}))
	weapon_pose_solver.configure_dynamic_hold(
		equipped_weapon_handling_profile.get("dynamic_hold", {})
	)
	weapon_pose_solver.configure_gun_placement_line(
		equipped_weapon_config.get("gun_placement_line", {})
	)
	audio_event_manager = AnimationAudioEvents.new()
	audio_event_manager.name = "AudioAnimationEvents"
	add_child(audio_event_manager)
	audio_event_manager.bind(animation_player, skeleton)
	_request_clip(&"idle_rifle")


func _process(delta: float) -> void:
	if animation_tree == null:
		return
	if not _explicit_visual_inputs:
		_pull_player_inputs()
	_update_weapon_ready(delta)
	_update_locomotion_latch()
	_cancel_reload_for_posture_change()
	_cancel_reload_for_mobility()
	_cancel_cosmetic_transition_for_gameplay()
	var mobility_owns_full_body := movement_state in [
		&"DIVING", &"ROLLING", &"AIRBORNE", &"LANDING",
	]
	var presentation_ready_weight := 0.0 if mobility_owns_full_body else weapon_ready_weight
	locomotion_graph.update_locomotion(
		movement_direction,
		movement_speed_normalized,
		movement_speed_mps,
		posture,
		presentation_ready_weight,
		delta
	)
	_consider_cosmetic_transition()
	_update_requested_action(delta)
	_update_reload_visuals(delta)
	if posture != _previous_posture:
		_previous_posture = posture
		if asset_runtime != null:
			asset_runtime.apply_animation_hand_map(String(posture), posture)
	if requested_action == &"" or _requested_action_upper_body_layered:
		_request_clip(_select_visual_clip())
	_apply_saved_animation_frame_pose(delta)
	_update_prone_straightening(delta)
	# Grenade clips author their complete upper-body turn. Dive and roll retain
	# the original posture path; suppressing it changes their authored arm data.
	var action_owns_upper_body_rotation := mobility_owns_full_body or (
		requested_action != &""
		and "grenade" in String(requested_action).to_lower()
	)
	var posture_aim_yaw := 0.0 if action_owns_upper_body_rotation else aim_yaw_rad
	var posture_aim_pitch := 0.0 if action_owns_upper_body_rotation else aim_pitch_rad
	posture_layer.apply(
		posture_aim_yaw,
		posture_aim_pitch,
		presentation_ready_weight,
		obstruction_amount,
		0.0,
		deg_to_rad(chest_yaw_limit_deg),
		deg_to_rad(chest_pitch_limit_deg),
		deg_to_rad(head_yaw_limit_deg),
		deg_to_rad(head_pitch_limit_deg),
		_lower_body_separation_weight(),
		upper_body_gait_roll_retention,
		_prone_straighten_weight,
		deg_to_rad(prone_axis_max_correction_deg),
		deg_to_rad(prone_axis_target_pitch_deg),
		posture,
		peek_amount,
		visual_aim_target,
		neutral_hip_roll_trim_deg
	)
	weapon_pose_solver.apply(
		aim_yaw_rad,
		aim_pitch_rad,
		posture,
		movement_state,
		presentation_ready_weight,
		obstruction_amount,
		requested_action,
		_reload_support_regrip,
		visual_aim_target,
		_get_player(),
		delta,
		_locomotion_active or movement_speed_normalized > 0.05
	)
	_stabilize_locomotion_legs(delta)
	_previous_firing = firing
	_previous_movement_state = movement_state


func _stabilize_locomotion_legs(delta: float) -> void:
	if skeleton == null:
		return
	var ordinary_locomotion := (
		(requested_action == &"" or _requested_action_upper_body_layered)
		and posture != &"PRONE"
		and movement_state in [&"STANDING", &"CROUCHED", &"LOCOMOTION"]
	)
	if not ordinary_locomotion:
		_stabilized_leg_rotations.clear()
		return
	var maximum_step := deg_to_rad(maximum_leg_rotation_deg_per_60hz) * clampf(
		delta * 60.0,
		0.25,
		2.0
	)
	for bone_name in [&"mixamorig_LeftUpLeg", &"mixamorig_RightUpLeg"]:
		var bone_index := skeleton.find_bone(bone_name)
		if bone_index < 0:
			continue
		var pose := skeleton.get_bone_global_pose(bone_index)
		var current_rotation := pose.basis.get_rotation_quaternion().normalized()
		var previous_rotation: Quaternion = _stabilized_leg_rotations.get(
			bone_name,
			current_rotation
		)
		var angle := previous_rotation.angle_to(current_rotation)
		var stable_rotation := current_rotation
		if angle > maximum_step and angle > 0.00001:
			stable_rotation = previous_rotation.slerp(
				current_rotation,
				maximum_step / angle
			).normalized()
			pose.basis = Basis(stable_rotation).scaled(pose.basis.get_scale())
			skeleton.set_bone_global_pose_override(bone_index, pose, 1.0, true)
		_stabilized_leg_rotations[bone_name] = stable_rotation
	skeleton.force_update_all_bone_transforms()


func _cancel_cosmetic_transition_for_gameplay() -> void:
	if not _requested_action_is_transition:
		return
	var standing_only_transition := requested_action in [
		&"start_forward", &"start_backward",
		&"stop_forward", &"stop_backward", &"run_to_stop",
		&"turn_90_left", &"turn_90_right",
	]
	var prone_transition := requested_action in [&"prone_stop_forward", &"prone_stop_backward"]
	var stop_cancelled_by_intent := (
		_last_transition_reason == &"stop" and movement_intent_strength >= 0.10
	)
	if (
		stop_cancelled_by_intent
		or
		(posture == &"PRONE" and not prone_transition)
		or (posture == &"CROUCHED" and standing_only_transition)
		or movement_state in [&"DIVING", &"ROLLING", &"AIRBORNE", &"LANDING"]
	):
		requested_action = &""
		requested_action_remaining = 0.0
		_requested_action_is_transition = false


func _cancel_reload_for_mobility() -> void:
	if (
		not _reload_action_is_active()
		or movement_state not in [&"DIVING", &"ROLLING", &"AIRBORNE", &"LANDING"]
	):
		return
	_cancel_active_reload()


func _cancel_reload_for_posture_change() -> void:
	if posture == _previous_posture or not _reload_action_is_active():
		return
	_cancel_active_reload()


func _reload_action_is_active() -> bool:
	return requested_action != &"" and "reload" in String(requested_action).to_lower()


func _cancel_active_reload(emit_cancelled: bool = true) -> void:
	var cancelled_action := requested_action
	if locomotion_graph != null:
		locomotion_graph.cancel_reload_layers()
	requested_action = &""
	requested_action_remaining = 0.0
	_requested_action_is_transition = false
	_requested_action_upper_body_layered = false
	_clear_reload_visuals()
	if weapon_pose_solver != null:
		weapon_pose_solver.interrupt_action_weapon_follow()
	if emit_cancelled and cancelled_action != &"":
		action_cancelled.emit(cancelled_action)


func _consider_cosmetic_transition() -> void:
	var request: Dictionary = transition_state_machine.evaluate(
		movement_direction,
		movement_speed_normalized,
		posture,
		aim_yaw_rad,
		available_clips,
		animation_profile.transitions,
		movement_intent_direction,
		movement_intent_strength,
		movement_response_mode
	)
	var prone_stop_allowed: bool = posture == &"PRONE" and StringName(request["reason"]) == &"stop"
	var allowed: bool = (
		movement_state in [&"STANDING", &"CROUCHED", &"PRONE", &"LOCOMOTION"]
		and (posture != &"PRONE" or prone_stop_allowed)
	)
	if requested_action != &"" or not allowed or request["clip"] == &"":
		return
	requested_action = StringName(request["clip"])
	requested_action_remaining = float(request["duration"])
	requested_action_total_duration = requested_action_remaining
	_requested_action_release_cue_emitted = false
	_last_transition_reason = StringName(request["reason"])
	_requested_action_is_transition = true


func _update_requested_action(delta: float) -> void:
	if requested_action == &"":
		return
	requested_action_remaining = maxf(0.0, requested_action_remaining - delta)
	_emit_action_release_cue_if_due()
	if requested_action_remaining > 0.0:
		if not _requested_action_upper_body_layered:
			_request_clip(requested_action)
		return
	if _reload_action_is_active():
		var completed_reload := requested_action
		_cancel_active_reload(false)
		action_completed.emit(completed_reload)
		return
	var completed_action := requested_action
	requested_action = &""
	requested_action_total_duration = 0.0
	_requested_action_release_cue_emitted = false
	_requested_action_is_transition = false
	_requested_action_upper_body_layered = false
	requested_action_playback_speed = 1.0
	if animation_player != null:
		animation_player.speed_scale = 1.0
	_clear_reload_visuals()
	_update_weapon_visibility()
	action_completed.emit(completed_action)


func _emit_action_release_cue_if_due() -> void:
	if (
		_requested_action_release_cue_emitted
		or not GrenadeReleaseTimeline.is_grenade_clip(requested_action)
		or requested_action_total_duration <= 0.0
	):
		return
	var elapsed_fraction := 1.0 - (
		requested_action_remaining / requested_action_total_duration
	)
	if elapsed_fraction < GrenadeReleaseTimeline.release_fraction(requested_action):
		return
	_requested_action_release_cue_emitted = true
	action_release_cue.emit(requested_action)


func _update_reload_visuals(delta: float) -> void:
	if _active_reload_visual_slot.is_empty() or _active_reload_visual_clip == &"":
		return
	if requested_action == &"":
		_clear_reload_visuals()
		return
	var animation := (
		animation_player.get_animation(_active_reload_visual_clip)
		if animation_player != null
		else null
	)
	var frame_count := maxi(
		1,
		int(round(
			(animation.length if animation else 1.0)
			* 30.0
		))
	)
	_reload_visual_time = minf(
		_reload_visual_time + delta,
		animation.length if animation else 1.0
	)
	var timeline := WeaponReloadVisualTimeline.ensure_profile_timeline(
		equipped_weapon_handling_profile,
		_active_reload_visual_slot,
		frame_count
	)
	var events: Dictionary = timeline.get("events", {})
	var frame_index := clampi(int(round(_reload_visual_time * 30.0)), 0, frame_count)
	var state := WeaponReloadVisualTimeline.state_at_frame(events, frame_index)
	_reload_support_regrip = WeaponReloadVisualTimeline.support_hand_should_regrip(
		events,
		frame_index
	)
	if asset_runtime != null:
		asset_runtime.update_reload_magazine_visual(
			timeline,
			WeaponReloadVisualTimeline.magazine_is_in_left_hand(state)
		)


func _clear_reload_visuals() -> void:
	_active_reload_visual_slot = ""
	_active_reload_visual_clip = &""
	_reload_visual_time = 0.0
	_reload_support_regrip = false
	if asset_runtime != null:
		asset_runtime.update_reload_magazine_visual({}, false)


func _build_animation_tree() -> void:
	if animation_tree != null:
		animation_tree.active = false
		animation_tree.free()
		animation_tree = null
	locomotion_graph = LocomotionBlendTree.new()
	animation_tree = locomotion_graph.build(
		self,
		animation_player,
		available_clips,
		animation_profile,
		use_modern_locomotion,
		equipped_weapon_handling_profile
	)
	transition_node = locomotion_graph.legacy_transition


func _neutral_pose_hip_rotation() -> Quaternion:
	if animation_player == null or not animation_player.has_animation(&"aim_idle"):
		return Quaternion.IDENTITY
	var animation := animation_player.get_animation(&"aim_idle")
	if animation == null:
		return Quaternion.IDENTITY
	for track in range(animation.get_track_count()):
		if animation.track_get_type(track) != Animation.TYPE_ROTATION_3D:
			continue
		if str(animation.track_get_path(track)) != ".:mixamorig_Hips":
			continue
		if animation.track_get_key_count(track) == 0:
			return Quaternion.IDENTITY
		return (animation.track_get_key_value(track, 0) as Quaternion).normalized()
	return Quaternion.IDENTITY


func _lower_body_separation_weight() -> float:
	if posture != &"STANDING":
		return 0.0
	if movement_state in [&"DIVING", &"ROLLING", &"AIRBORNE", &"LANDING"]:
		return 0.0
	# Relaxed rifle locomotion is a complete authored pose: its hips, torso,
	# shoulders, arms, and right-hand weapon carry must turn together. Once the
	# weapon enters Ready Aim, progressively separate the locomotion legs from
	# the reticle-facing upper body. This preserves directional run silhouettes
	# without weakening the approved combat aim state.
	return smoothstep(0.12, 0.82, weapon_ready_weight)


func _select_visual_clip() -> StringName:
	if movement_state == &"DIVING":
		return &"dive_roll"
	if movement_state == &"ROLLING":
		return &"roll"
	if movement_state == &"AIRBORNE":
		if vertical_speed > 1.0:
			return &"jump_up"
		if vertical_speed < -1.0:
			return &"jump_down"
		var equipped_jump := StringName(
			(equipped_weapon_handling_profile.get("locomotion_slots", {}) as Dictionary).get("jump", "")
		)
		if equipped_jump != &"" and available_clips.has(equipped_jump):
			return equipped_jump
		return &"jump_loop"
	if movement_state == &"LANDING":
		return &"jump_down"
	if posture == &"PRONE":
		if not _locomotion_active:
			return &"idle_prone"
		return (
			&"prone_backward"
			if _prone_direction_suffix(movement_direction) == "backward"
			else &"prone_forward"
		)
	if posture == &"CROUCHED":
		if not _locomotion_active:
			return _equipped_action_clip("idle_crouched", &"idle_crouch")
		var crouch_clip := StringName("crouch_%s" % _direction_suffix(movement_direction))
		return crouch_clip if available_clips.has(crouch_clip) else &"crouch_forward"
	if not _locomotion_active:
		return (
			_equipped_action_clip("idle_standing", &"aim_idle")
			if weapon_ready_weight >= 0.5
			else &"idle_rifle"
		)
	var prefix := (
		"walk"
		if weapon_ready_weight >= 0.5
		else "run" if movement_gait == &"FULL" else "walk"
	)
	var slot_name := "%s_%s" % [prefix, _direction_suffix(movement_direction)]
	var directional_fallback := StringName(slot_name)
	var fallback := (
		directional_fallback
		if available_clips.has(directional_fallback)
		else (&"run_forward" if prefix == "run" else &"walk_forward")
	)
	return _equipped_locomotion_clip(slot_name, fallback)


func _equipped_locomotion_clip(slot_name: String, fallback: StringName) -> StringName:
	var slots: Dictionary = equipped_weapon_handling_profile.get("locomotion_slots", {})
	var candidate := StringName(slots.get(slot_name, ""))
	return candidate if candidate != &"" and available_clips.has(candidate) else fallback


func _equipped_action_clip(slot_name: String, fallback: StringName) -> StringName:
	var slots: Dictionary = equipped_weapon_handling_profile.get("animation_slots", {})
	var candidate := StringName(slots.get(slot_name, ""))
	return candidate if candidate != &"" and available_clips.has(candidate) else fallback


func play_action(
	clip_name: StringName,
	blend_seconds: float = -1.0,
	playback_speed: float = 1.0
) -> bool:
	if not available_clips.has(clip_name) or animation_player == null:
		return false
	if requested_action != &"" and requested_action != clip_name:
		var interrupted_action := requested_action
		if _reload_action_is_active():
			_cancel_active_reload(false)
		action_cancelled.emit(interrupted_action)
	var animation := animation_player.get_animation(clip_name)
	requested_action_playback_speed = clampf(playback_speed, 0.25, 3.0)
	animation_player.speed_scale = requested_action_playback_speed
	requested_action = clip_name
	_requested_action_release_cue_emitted = false
	_requested_action_is_transition = false
	_requested_action_upper_body_layered = false
	if clip_name == &"dive_roll":
		requested_action_remaining = dive_roll_trim_duration
	elif clip_name == &"roll":
		requested_action_remaining = roll_trim_duration
	else:
		requested_action_remaining = (
			(animation.length if animation else 1.0)
			/ requested_action_playback_speed
		)
	requested_action_total_duration = requested_action_remaining
	if "reload" in String(clip_name).to_lower():
		_active_reload_visual_slot = "reload_%s" % String(posture).to_lower()
		_active_reload_visual_clip = clip_name
		_reload_visual_time = 0.0
		_reload_support_regrip = false
	else:
		_clear_reload_visuals()
	if posture == &"CROUCHED" and "reload" in String(clip_name).to_lower():
		_requested_action_upper_body_layered = bool(
			locomotion_graph != null
			and locomotion_graph.trigger_crouched_reload(clip_name)
		)
	elif posture == &"STANDING" and "reload" in String(clip_name).to_lower():
		_requested_action_upper_body_layered = bool(
			locomotion_graph != null
			and locomotion_graph.trigger_standing_reload(clip_name)
		)
	if _requested_action_upper_body_layered:
		if asset_runtime != null:
			asset_runtime.apply_animation_hand_map(
				String(clip_paths.get(clip_name, "")),
				posture,
				clip_name
			)
	else:
		_request_clip(clip_name, blend_seconds)
	_update_weapon_visibility()
	return true


func play_semantic_action(
	action_name: StringName,
	blend_seconds: float = -1.0,
	playback_speed: float = 1.0
) -> bool:
	var clip_name: StringName = _resolve_equipped_weapon_action(action_name)
	return clip_name != &"" and play_action(clip_name, blend_seconds, playback_speed)


func play_semantic_action_timed(
	action_name: StringName,
	target_duration_seconds: float,
	blend_seconds: float = -1.0
) -> bool:
	var clip_name: StringName = _resolve_equipped_weapon_action(action_name)
	if clip_name == &"" or animation_player == null:
		return false
	var animation := animation_player.get_animation(clip_name)
	if animation == null:
		return false
	var target_duration := clampf(target_duration_seconds, 0.25, 10.0)
	var playback_speed := clampf(animation.length / target_duration, 0.25, 3.0)
	return play_action(clip_name, blend_seconds, playback_speed)


func weapon_reload_duration_seconds() -> float:
	return clampf(
		float(equipped_weapon_handling_profile.get("reload_duration_seconds", 1.75)),
		0.25,
		10.0
	)


func set_equipped_weapon_visible(enabled: bool) -> void:
	_equipped_weapon_visible = enabled
	_update_weapon_visibility()


func set_bomb_backpack_visible(enabled: bool) -> void:
	if asset_runtime != null:
		asset_runtime.set_bomb_backpack_visible(enabled)


func cancel_grenade_action() -> bool:
	if animation_player != null:
		animation_player.speed_scale = 1.0
	requested_action_playback_speed = 1.0
	if requested_action == &"" or "grenade" not in String(requested_action).to_lower():
		return false
	var cancelled_action := requested_action
	requested_action = &""
	requested_action_remaining = 0.0
	requested_action_total_duration = 0.0
	_requested_action_release_cue_emitted = false
	_requested_action_is_transition = false
	_requested_action_upper_body_layered = false
	if weapon_pose_solver != null:
		weapon_pose_solver.interrupt_action_weapon_follow()
	_request_clip(_select_visual_clip(), 0.08)
	_update_weapon_visibility()
	action_cancelled.emit(cancelled_action)
	return true


func _update_weapon_visibility() -> void:
	if weapon_node == null:
		return
	var grenade_action_active := (
		requested_action != &""
		and "grenade" in String(requested_action).to_lower()
	)
	weapon_node.visible = _equipped_weapon_visible and not grenade_action_active


func resolve_semantic_action(action_name: StringName) -> StringName:
	return _resolve_equipped_weapon_action(action_name)


func _resolve_equipped_weapon_action(action_name: StringName) -> StringName:
	var slots: Dictionary = equipped_weapon_handling_profile.get("animation_slots", {})
	if not slots.is_empty() and action_name in [&"fire", &"reload"]:
		var posture_suffix := String(posture).to_lower()
		if posture_suffix == "standing":
			posture_suffix = "standing"
		elif posture_suffix == "crouched":
			posture_suffix = "crouched"
		elif posture_suffix == "prone":
			posture_suffix = "prone"
		var slot_name := "%s_%s" % [String(action_name), posture_suffix]
		var candidate := StringName(slots.get(slot_name, ""))
		if candidate != &"" and available_clips.has(candidate):
			return candidate
	return animation_profile.resolve_semantic_action(action_name, posture)


func _load_equipped_weapon_handling_profile() -> Dictionary:
	var config := WeaponContract.load_equipped_config()
	var handling: Variant = config.get("handling_profile", {})
	return (handling as Dictionary).duplicate(true) if handling is Dictionary else {}


func get_connected_route(route_name: StringName) -> Array[StringName]:
	return animation_profile.connected_route(route_name)


func resolve_presentation_event(
	event_name: StringName,
	extra_context: Dictionary = {}
) -> Dictionary:
	if presentation_router == null:
		return {}
	return presentation_router.resolve(event_name, _presentation_context(extra_context))


func present_event(
	event_name: StringName,
	extra_context: Dictionary = {}
) -> Dictionary:
	if presentation_router == null:
		return {}
	_last_event_presentation = presentation_router.present(
		event_name,
		_presentation_context(extra_context),
		Callable(self, "_apply_presentation_plan")
	)
	return _last_event_presentation.duplicate(true)


func describe_presentation_plan(plan: Dictionary) -> String:
	return presentation_router.describe(plan) if presentation_router != null else "Presentation router is not ready."


func _presentation_context(extra_context: Dictionary = {}) -> Dictionary:
	var context := extra_context.duplicate(true)
	context["posture"] = String(posture)
	context["weapon_family"] = String(equipped_weapon_family)
	context["current_base_state"] = String(_select_visual_clip())
	return context


func _apply_presentation_plan(plan: Dictionary) -> bool:
	match StringName(plan.get("event", "")):
		&"FIRE_ACCEPTED":
			return _apply_fire_presentation(plan)
		&"RELOAD_STARTED":
			var target_duration := float(
				(plan.get("context", {}) as Dictionary).get(
					"target_duration_seconds",
					weapon_reload_duration_seconds()
				)
			)
			return _play_presentation_action_timed(plan, target_duration)
		_:
			var clip_name := StringName(plan.get("state", ""))
			return play_action(
				clip_name,
				float(plan.get("blend_in_seconds", transition_blend_seconds))
			)


func _play_presentation_action_timed(plan: Dictionary, target_duration_seconds: float) -> bool:
	var clip_name := StringName(plan.get("state", ""))
	if clip_name == &"" or animation_player == null:
		return false
	var animation := animation_player.get_animation(clip_name)
	if animation == null:
		return false
	var target_duration := clampf(target_duration_seconds, 0.25, 10.0)
	var playback_speed := clampf(animation.length / target_duration, 0.25, 3.0)
	return play_action(
		clip_name,
		float(plan.get("blend_in_seconds", transition_blend_seconds)),
		playback_speed
	)


func notify_fired() -> bool:
	var plan := present_event(&"FIRE_ACCEPTED")
	return bool(plan.get("applied", false))


func _apply_fire_presentation(plan: Dictionary) -> bool:
	if skeleton == null or locomotion_graph == null:
		return false
	var event_fire_clip := StringName(plan.get("state", ""))
	var effect_duration := float(plan.get("blend_in_seconds", 0.04)) + float(plan.get("blend_out_seconds", 0.10))
	if animation_player != null and animation_player.has_animation(event_fire_clip):
		effect_duration = maxf(effect_duration, animation_player.get_animation(event_fire_clip).length)
	var presentation_effects: Array = plan.get("effects", [])
	if AnimationStateContract.ENTER_READY_AIM in presentation_effects:
		_trigger_fire_ready_aim()
	if (
		weapon_pose_solver != null
		and AnimationStateContract.RAIL_TO_BLUE_LINE in presentation_effects
		and movement_state not in [&"DIVING", &"ROLLING", &"AIRBORNE", &"LANDING"]
	):
		weapon_pose_solver.trigger_rail_to_blue_line(effect_duration)
	if _standing_fire_uses_aim_idle(event_fire_clip):
		# Standing imports the complete Gunsmith Aim Idle baseline. Bloom and
		# reticle kick remain as shot feedback; the fire take must not replace the
		# authored torso, weapon transform, dimensions, or grip sockets.
		_fire_pose_clip = &""
		_fire_pose_time = 0.0
		_fire_pose_duration = 0.0
		return true
	_fire_pose_clip = locomotion_graph.trigger_fire(posture, event_fire_clip)
	_fire_pose_time = 0.0
	var fire_animation := (
		animation_player.get_animation(_fire_pose_clip)
		if animation_player != null and _fire_pose_clip != &""
		else null
	)
	_fire_pose_duration = fire_animation.length if fire_animation != null else 0.0
	return true


func notify_weapon_equipped(raw_config: Dictionary) -> bool:
	return WeaponEquipmentRuntime.apply(self, raw_config)


func set_trooper_scale(new_scale: float) -> void:
	trooper_scale = new_scale
	if asset_runtime != null:
		asset_runtime.set_operator_scale(new_scale)


func set_modern_locomotion_enabled(enabled: bool) -> void:
	use_modern_locomotion = enabled
	if locomotion_graph != null:
		locomotion_graph.set_modern_enabled(enabled)


func _request_clip(clip_name: StringName, blend_seconds: float = -1.0) -> void:
	if not available_clips.has(clip_name):
		return
	if clip_name != current_clip:
		if weapon_pose_solver != null:
			weapon_pose_solver.clear_animation_frame_pose()
		previous_clip = current_clip
		current_clip = clip_name
		_frame_pose_clip_time = 0.0
		if asset_runtime != null:
			asset_runtime.apply_animation_hand_map(
				String(clip_paths.get(clip_name, "")),
				posture if requested_action == &"" or _requested_action_upper_body_layered else &"",
				clip_name
			)
	var blend := blend_seconds
	if blend < 0.0:
		var fallback_blend := (
			locomotion_blend_seconds
			if _is_locomotion_clip(previous_clip) and _is_locomotion_clip(clip_name)
			else transition_blend_seconds
		)
		blend = animation_profile.transition_blend_seconds(
			previous_clip,
			clip_name,
			fallback_blend
		)
	if not use_modern_locomotion:
		locomotion_graph.request_legacy_clip(clip_name, blend)
		return
	locomotion_graph.modern_transition.xfade_time = maxf(blend, 0.0)
	if not locomotion_graph.request_modern_state(_modern_state_for_clip(clip_name)):
		locomotion_graph.set_modern_enabled(false)
		locomotion_graph.request_legacy_clip(clip_name, blend)


func _apply_saved_animation_frame_pose(delta: float) -> void:
	if animation_frame_pose_runtime == null or current_clip == &"":
		return
	var pose_clip := current_clip
	var pose_time := _frame_pose_clip_time
	# Standing locomotion replaces its upper body with the equipped Aim Idle
	# clip. Sample the Gunsmith correction keys from that same upper-body source,
	# not from the walk/run clip that owns only the legs.
	if (
		posture == &"STANDING"
		and weapon_ready_weight >= 0.50
		and movement_state not in [&"DIVING", &"ROLLING", &"AIRBORNE", &"LANDING"]
	):
		var ready_pose_clip := _standing_ready_frame_pose_clip()
		if ready_pose_clip != &"":
			pose_clip = ready_pose_clip
	if _requested_action_upper_body_layered and _active_reload_visual_clip != &"":
		pose_clip = _active_reload_visual_clip
		pose_time = _reload_visual_time
	if _fire_pose_clip != &"" and _fire_pose_time < _fire_pose_duration:
		pose_clip = _fire_pose_clip
		_fire_pose_time = minf(_fire_pose_time + maxf(delta, 0.0), _fire_pose_duration)
		pose_time = _fire_pose_time
	var animation := animation_player.get_animation(pose_clip) if animation_player != null else null
	var duration: float = animation.length if animation != null else 0.0
	var playback_rate_value := (
		float(locomotion_graph.playback_rate) if locomotion_graph != null else 1.0
	)
	_frame_pose_clip_time += maxf(delta, 0.0) * maxf(playback_rate_value, 0.0)
	if duration > 0.0:
		if _is_locomotion_clip(current_clip) and locomotion_graph != null:
			_frame_pose_clip_time = clampf(float(locomotion_graph.shared_phase), 0.0, 1.0) * duration
		elif animation.loop_mode != Animation.LOOP_NONE:
			_frame_pose_clip_time = fmod(_frame_pose_clip_time, duration)
		else:
			_frame_pose_clip_time = minf(_frame_pose_clip_time, duration)
	if pose_clip == current_clip:
		pose_time = _frame_pose_clip_time
	var candidates: Array = [
		String(pose_clip),
		String(clip_paths.get(pose_clip, "")),
		String(get_source_animation_name(pose_clip)),
	]
	_active_frame_pose = animation_frame_pose_runtime.sample(
		candidates,
		pose_time
	)
	_standing_master_pose_frame_suppressed = false
	if (
		_standing_master_pose_active()
		and bool(_standing_master_pose_profile().get("suppress_saved_frame_pose", true))
		and not _standing_reload_pose_active()
	):
		# Gunsmith keeps the saved keys for editing and reload authoring. Gameplay
		# standing uses the imported Aim Idle as its only torso baseline; the blue
		# line owns the rifle and the weapon sockets own both hands.
		_active_frame_pose = {}
		_standing_master_pose_frame_suppressed = true
	if posture_layer != null:
		posture_layer.set_animation_frame_rotation_overrides(
			_active_frame_pose.get("joint_rotations", {})
		)
	if weapon_pose_solver != null:
		weapon_pose_solver.set_animation_frame_pose(_active_frame_pose)


func _standing_master_pose_profile() -> Dictionary:
	var raw_profile: Variant = equipped_weapon_handling_profile.get(
		"standing_master_pose",
		{}
	)
	return raw_profile as Dictionary if raw_profile is Dictionary else {}


func _standing_master_pose_active() -> bool:
	return (
		posture == &"STANDING"
		and bool(_standing_master_pose_profile().get("enabled", false))
	)


func _standing_fire_uses_aim_idle(event_state: StringName = &"") -> bool:
	if posture != &"STANDING":
		return false
	if bool(
		equipped_weapon_handling_profile.get(
			"standing_fire_uses_aim_idle",
			false
		)
	):
		return true
	if event_state == &"":
		event_state = animation_profile.resolve_animation_event(
			&"FIRE_ACCEPTED",
			posture,
			equipped_weapon_family
		)
	if event_state != &"":
		return event_state == &"aim_idle"
	return false


func _standing_reload_pose_active() -> bool:
	return (
		_requested_action_upper_body_layered
		and "reload" in String(requested_action).to_lower()
	)


func _standing_ready_frame_pose_clip() -> StringName:
	var animation_slots: Variant = equipped_weapon_handling_profile.get(
		"animation_slots",
		{}
	)
	if not animation_slots is Dictionary:
		return &"aim_idle" if available_clips.has(&"aim_idle") else &""
	var configured := StringName(
		(animation_slots as Dictionary).get("idle_standing", "aim_idle")
	)
	if configured != &"" and available_clips.has(configured):
		return configured
	return &"aim_idle" if available_clips.has(&"aim_idle") else &""


func _modern_state_for_clip(clip_name: StringName) -> StringName:
	if requested_action != &"" and not _requested_action_upper_body_layered:
		return clip_name
	if posture == &"CROUCHED":
		return &"crouch" if _locomotion_active else &"idle_crouch"
	if movement_state in [&"DIVING", &"ROLLING", &"AIRBORNE", &"LANDING"]:
		return clip_name
	if posture == &"PRONE":
		return &"prone" if _locomotion_active else &"idle_prone"
	return &"standing" if _locomotion_active else &"idle"


func _is_locomotion_clip(clip_name: StringName) -> bool:
	var text := String(clip_name)
	return text.begins_with("walk_") or text.begins_with("run_") or text.begins_with("crouch_") or text.begins_with("prone_") or text in ["idle_rifle", "aim_idle", "idle_crouch", "idle_prone"]


func _direction_suffix(direction: Vector2) -> String:
	if direction.length_squared() < 0.001:
		return "forward"
	var angle := wrapf(atan2(direction.x, direction.y), -PI, PI)
	var sector_width := PI / 4.0
	var candidate := wrapi(int(round(angle / sector_width)), 0, 8)
	if not _direction_initialized:
		_stable_direction_octant = candidate
		_direction_initialized = true
	else:
		var stable_center := float(_stable_direction_octant) * sector_width
		var threshold := sector_width * 0.5 + deg_to_rad(direction_hysteresis_deg)
		if absf(wrapf(angle - stable_center, -PI, PI)) > threshold:
			_stable_direction_octant = candidate
	match _stable_direction_octant:
		0: return "forward"
		1: return "forward_right"
		2: return "right"
		3: return "back_right"
		4: return "backward"
		5: return "back_left"
		6: return "left"
		_: return "forward_left"


func _prone_direction_suffix(direction: Vector2) -> String:
	# Side input steers a continuous forward crawl. It must never select a
	# different turn clip because that resets the hands-and-knees cycle.
	return "backward" if direction.y < -0.05 and absf(direction.y) >= absf(direction.x) * 0.72 else "forward"


func _update_prone_straightening(delta: float) -> void:
	# Stable prone poses all share one pelvis-to-head axis. The previous fix ran
	# only during forward travel and pitched the first spine joint, which left
	# idle prone crooked and introduced a visible bend at the waist.
	var stable_prone := (
		posture == &"PRONE"
		and movement_state not in [&"DIVING", &"ROLLING", &"AIRBORNE", &"LANDING"]
	)
	var target := 1.0 if stable_prone else 0.0
	_prone_straighten_weight = lerpf(
		_prone_straighten_weight,
		target,
		1.0 - exp(-prone_straighten_response * delta)
	)


func _update_locomotion_latch() -> void:
	if _locomotion_active and movement_speed_normalized <= locomotion_exit_speed:
		_locomotion_active = false
		_direction_initialized = false
	elif not _locomotion_active and movement_speed_normalized >= locomotion_enter_speed:
		_locomotion_active = true
		_direction_initialized = false


func _pull_player_inputs() -> void:
	var player := _get_player()
	if player == null:
		return
	var local_velocity := player.global_basis.inverse() * player.velocity
	movement_direction = Vector2(local_velocity.x, -local_velocity.z)
	movement_speed_mps = movement_direction.length()
	movement_speed_normalized = clampf(movement_speed_mps / 6.5, 0.0, 1.0)
	if movement_direction.length_squared() > 0.001:
		movement_direction = movement_direction.normalized() * movement_speed_normalized
	posture = player.get_posture_name() if player.has_method("get_posture_name") else &"STANDING"
	peek_amount = float(player.call("get_peek_amount")) if player.has_method("get_peek_amount") else 0.0
	movement_state = player.get_motion_state_name() if player.has_method("get_motion_state_name") else &"LOCOMOTION"
	vertical_speed = player.velocity.y


func set_visual_inputs(
	direction: Vector2,
	posture_name: StringName,
	aim_yaw: float,
	aim_pitch: float,
	ready_weight: float,
	is_firing: bool,
	obstruction: float,
	speed_normalized: float = -1.0,
	state_name: StringName = &"LOCOMOTION",
	vertical_velocity: float = 0.0,
	gait_name: StringName = &"WALK",
	actual_speed_mps: float = -1.0,
	world_aim_target: Vector3 = Vector3.ZERO,
	desired_direction: Vector2 = Vector2.ZERO,
	desired_strength: float = -1.0,
	response_mode: StringName = &"IDLE",
	peek: float = 0.0
) -> void:
	_explicit_visual_inputs = true
	movement_direction = direction
	movement_speed_normalized = clampf(speed_normalized if speed_normalized >= 0.0 else direction.length(), 0.0, 1.0)
	movement_gait = &"FULL" if gait_name == &"FULL" else &"WALK"
	movement_speed_mps = actual_speed_mps if actual_speed_mps >= 0.0 else movement_speed_normalized * float(animation_profile.locomotion["full_nominal_speed_mps"])
	posture = posture_name
	aim_yaw_rad = aim_yaw
	aim_pitch_rad = aim_pitch
	requested_weapon_ready_weight = clampf(ready_weight, 0.0, 1.0)
	firing = is_firing
	obstruction_amount = clampf(obstruction, 0.0, 1.0)
	movement_state = state_name
	vertical_speed = vertical_velocity
	visual_aim_target = world_aim_target
	movement_intent_direction = desired_direction
	movement_intent_strength = clampf(
		desired_strength if desired_strength >= 0.0 else desired_direction.length(),
		0.0,
		1.0
	)
	movement_response_mode = response_mode
	peek_amount = clampf(peek, -1.0, 1.0)


func _trigger_fire_ready_aim() -> void:
	var ready_profile: Variant = equipped_weapon_handling_profile.get("ready_aim", {})
	var hold_seconds := fire_ready_hold_seconds
	if ready_profile is Dictionary:
		hold_seconds = float(
			(ready_profile as Dictionary).get("fire_hold_seconds", hold_seconds)
		)
	_fire_ready_hold_remaining = maxf(hold_seconds, 0.0)
	# A valid shot must raise the weapon immediately. Only the return is eased.
	weapon_ready_weight = 1.0


func _update_weapon_ready(delta: float) -> void:
	_fire_ready_hold_remaining = maxf(
		_fire_ready_hold_remaining - maxf(delta, 0.0),
		0.0
	)
	var ready_target := maxf(
		requested_weapon_ready_weight,
		1.0 if _fire_ready_hold_remaining > 0.0 else 0.0
	)
	var response := (
		ready_enter_response
		if ready_target > weapon_ready_weight
		else ready_exit_response
	)
	weapon_ready_weight = lerpf(
		weapon_ready_weight,
		ready_target,
		1.0 - exp(-response * maxf(delta, 0.0))
	)
	if ready_target <= 0.0 and weapon_ready_weight <= 0.001:
		weapon_ready_weight = 0.0


func clear_fire_ready_aim() -> void:
	_fire_ready_hold_remaining = 0.0
	if requested_weapon_ready_weight <= 0.0:
		weapon_ready_weight = 0.0


func set_pose_preview_paused(paused: bool) -> void:
	if animation_player != null:
		animation_player.speed_scale = 0.0 if paused else 1.0


func set_procedural_pose_rotation(
	posture_name: StringName,
	bone_name: StringName,
	rotation_degrees: Vector3
) -> void:
	if posture_layer != null:
		posture_layer.set_procedural_rotation_degrees(
			posture_name,
			bone_name,
			rotation_degrees
		)


func get_procedural_pose_rotation(
	posture_name: StringName,
	bone_name: StringName
) -> Vector3:
	return (
		posture_layer.get_procedural_rotation_degrees(posture_name, bone_name)
		if posture_layer != null
		else Vector3.ZERO
	)


func save_procedural_pose_profile() -> bool:
	return posture_layer != null and posture_layer.save_procedural_profile()


func reload_procedural_pose_profile() -> bool:
	return posture_layer != null and posture_layer.reload_procedural_profile()


func get_animation_debug_state() -> Dictionary:
	var snapshot := {
		"gameplay_state": movement_state,
		"previous_gameplay_state": _previous_movement_state,
		"previous_clip": previous_clip,
		"logical_clip": current_clip,
		"source_take": get_source_animation_name(current_clip),
		"resource_path": str(clip_paths.get(current_clip, "")),
		"locomotion_active": _locomotion_active,
		"movement_gait": movement_gait,
		"weapon_ready_weight": weapon_ready_weight,
		"requested_weapon_ready_weight": requested_weapon_ready_weight,
		"fire_ready_hold_remaining": _fire_ready_hold_remaining,
		"locomotion_blend_seconds": locomotion_blend_seconds,
		"direction_octant": _stable_direction_octant,
		"recoil_weight": 0.0,
		"upper_body_recoil_layer": false,
		"upper_body_reload_layer": _requested_action_upper_body_layered,
		"transition_reason": _last_transition_reason,
		"movement_speed_mps": movement_speed_mps,
		"prone_straighten_weight": _prone_straighten_weight,
		"prone_axis_weight": _prone_straighten_weight,
		"prone_axis_target_pitch_deg": prone_axis_target_pitch_deg,
		"prone_axis_max_correction_deg": prone_axis_max_correction_deg,
		"peek_amount": peek_amount,
		"standing_master_pose_active": _standing_master_pose_active(),
		"standing_master_pose_frame_suppressed": _standing_master_pose_frame_suppressed,
		"last_event_presentation": _last_event_presentation.duplicate(true),
		"equipped_weapon_family": equipped_weapon_family,
	}
	if locomotion_graph != null:
		snapshot.merge(locomotion_graph.get_debug_state(), true)
	if posture_layer != null:
		snapshot.merge(posture_layer.get_debug_state(), true)
	if animation_frame_pose_runtime != null:
		snapshot["animation_frame_pose"] = animation_frame_pose_runtime.get_debug_state()
	if ik_contract != null:
		snapshot["ik"] = ik_contract.get_debug_state()
	if weapon_pose_solver != null:
		snapshot["weapon_pose"] = weapon_pose_solver.get_debug_state()
	return snapshot


func get_clip_names() -> Array[StringName]:
	var names: Array[StringName] = []
	for clip_name in available_clips.keys():
		names.append(clip_name as StringName)
	names.sort()
	return names


func has_clip(clip_name: StringName) -> bool:
	return available_clips.has(clip_name)


func get_source_animation_name(clip_name: StringName) -> StringName:
	return asset_runtime.get_source_animation_name(clip_name) if asset_runtime != null else &""


func _get_player() -> CharacterBody3D:
	var node: Node = get_parent()
	while node != null:
		if node is CharacterBody3D:
			return node as CharacterBody3D
		node = node.get_parent()
	return null
