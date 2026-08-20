class_name SocomOperatorAnimationDriver
extends Node3D

## Thin visual coordinator. CharacterBody owns movement; the camera owns aim.
## Asset loading, blending, transitions, posture and IK contracts are isolated.

const AnimationProfile := preload("res://scripts/player/operator_animation_profile.gd")
const AssetRuntime := preload("res://scripts/player/operator_asset_runtime.gd")
const WeaponContract := preload("res://scripts/weapons/weapon_rig_contract.gd")
const WeaponReloadVisualTimeline := preload("res://scripts/weapons/weapon_reload_visual_timeline.gd")
const LocomotionBlendTree := preload("res://scripts/player/operator_locomotion_blend_tree.gd")
const TransitionStateMachine := preload("res://scripts/player/operator_transition_state_machine.gd")
const PostureLayer := preload("res://scripts/player/operator_posture_layer.gd")
const IKContract := preload("res://scripts/player/operator_ik_contract.gd")
const WeaponPoseSolver := preload("res://scripts/player/operator_weapon_pose_solver.gd")
const AnimationAudioEvents := preload("res://scripts/audio/audio_animation_event_manager.gd")
const AnimationFramePoseRuntime := preload(
	"res://scripts/player/operator_animation_frame_pose_runtime.gd"
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
@export_range(0.04, 0.30, 0.01) var recoil_duration: float = 0.12
@export_range(0.0, 12.0, 0.25) var recoil_pitch_deg: float = 3.5
@export_range(0.0, 90.0, 0.5) var chest_yaw_limit_deg: float = 42.0
@export_range(0.0, 60.0, 0.5) var chest_pitch_limit_deg: float = 28.0
@export_range(0.0, 90.0, 0.5) var head_yaw_limit_deg: float = 56.0
@export_range(0.0, 60.0, 0.5) var head_pitch_limit_deg: float = 34.0
@export_range(0.0, 0.5, 0.01) var upper_body_gait_roll_retention: float = 0.18
@export_range(0.0, 3.0, 0.05) var neutral_hip_roll_trim_deg: float = 1.20
@export_range(0.0, 18.0, 0.5) var prone_axis_target_pitch_deg: float = 0.0
@export_range(0.0, 120.0, 0.5) var prone_axis_max_correction_deg: float = 90.0
@export_range(1.0, 30.0, 0.5) var prone_straighten_response: float = 14.0
@export_range(6.0, 18.0, 0.1) var maximum_leg_rotation_deg_per_60hz: float = 9.8

var animation_profile
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

var current_clip: StringName = &""
var previous_clip: StringName = &""
var requested_action: StringName = &""
var requested_action_remaining: float = 0.0
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
var _recoil_remaining: float = 0.0
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
var _active_reload_visual_slot: String = ""
var _active_reload_visual_clip: StringName = &""
var _reload_visual_time: float = 0.0
var _reload_support_regrip: bool = false


func _ready() -> void:
	process_priority = 100
	animation_profile = AnimationProfile.new()
	animation_profile.load_project_map()
	equipped_weapon_config = WeaponContract.load_equipped_config()
	var handling: Variant = equipped_weapon_config.get("handling_profile", {})
	equipped_weapon_handling_profile = (
		(handling as Dictionary).duplicate(true) if handling is Dictionary else {}
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
	_update_locomotion_latch()
	if firing and not _previous_firing:
		_trigger_fire_recoil()
	_cancel_cosmetic_transition_for_gameplay()
	locomotion_graph.update_locomotion(
		movement_direction,
		movement_speed_normalized,
		movement_speed_mps,
		posture,
		weapon_ready_weight,
		delta
	)
	_consider_cosmetic_transition()
	_update_requested_action(delta)
	_update_reload_visuals(delta)
	if posture != _previous_posture:
		_previous_posture = posture
		if asset_runtime != null:
			asset_runtime.apply_animation_hand_map(String(posture), posture)
	if requested_action == &"":
		_request_clip(_select_visual_clip())
	_apply_saved_animation_frame_pose(delta)
	_update_prone_straightening(delta)
	posture_layer.apply(
		aim_yaw_rad,
		aim_pitch_rad,
		weapon_ready_weight,
		obstruction_amount,
		-deg_to_rad(recoil_pitch_deg) * _recoil_weight(),
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
		weapon_ready_weight,
		obstruction_amount,
		requested_action,
		_reload_support_regrip,
		visual_aim_target,
		_get_player(),
		delta
	)
	_stabilize_locomotion_legs(delta)
	_recoil_remaining = maxf(0.0, _recoil_remaining - delta)
	_previous_firing = firing
	_previous_movement_state = movement_state


func _stabilize_locomotion_legs(delta: float) -> void:
	if skeleton == null:
		return
	var ordinary_locomotion := (
		requested_action == &""
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
	_last_transition_reason = StringName(request["reason"])
	_requested_action_is_transition = true


func _update_requested_action(delta: float) -> void:
	if requested_action == &"":
		return
	requested_action_remaining = maxf(0.0, requested_action_remaining - delta)
	if requested_action_remaining > 0.0:
		_request_clip(requested_action)
		return
	requested_action = &""
	_requested_action_is_transition = false
	_clear_reload_visuals()


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
	# Standing torso orientation is reticle-authoritative at all times. Do not
	# fade this by movement speed: doing so lets the hip animation pull the chest
	# off target during starts, stops, partial input, and direction reversals.
	return 1.0


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
		return _equipped_action_clip(
			"idle_standing",
			&"aim_idle" if weapon_ready_weight >= 0.5 else &"idle_rifle"
		)
	var prefix := "run" if movement_gait == &"FULL" else "walk"
	var slot_name := "%s_%s" % [prefix, _direction_suffix(movement_direction)]
	var directional_fallback := StringName(slot_name)
	var fallback := (
		directional_fallback
		if available_clips.has(directional_fallback)
		else (&"run_forward" if movement_gait == &"FULL" else &"walk_forward")
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


func play_action(clip_name: StringName, blend_seconds: float = 0.12) -> bool:
	if not available_clips.has(clip_name) or animation_player == null:
		return false
	var animation := animation_player.get_animation(clip_name)
	requested_action = clip_name
	_requested_action_is_transition = false
	if clip_name == &"dive_roll":
		requested_action_remaining = dive_roll_trim_duration
	elif clip_name == &"roll":
		requested_action_remaining = roll_trim_duration
	else:
		requested_action_remaining = animation.length if animation else 1.0
	if "reload" in String(clip_name).to_lower():
		_active_reload_visual_slot = "reload_%s" % String(posture).to_lower()
		_active_reload_visual_clip = clip_name
		_reload_visual_time = 0.0
		_reload_support_regrip = false
	else:
		_clear_reload_visuals()
	_request_clip(clip_name, blend_seconds)
	return true


func play_semantic_action(action_name: StringName, blend_seconds: float = 0.12) -> bool:
	var clip_name: StringName = _resolve_equipped_weapon_action(action_name)
	return clip_name != &"" and play_action(clip_name, blend_seconds)


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


func notify_fired() -> bool:
	_trigger_fire_recoil()
	if skeleton == null or locomotion_graph == null:
		return false
	_fire_pose_clip = locomotion_graph.trigger_fire(posture)
	_fire_pose_time = 0.0
	var fire_animation := (
		animation_player.get_animation(_fire_pose_clip)
		if animation_player != null and _fire_pose_clip != &""
		else null
	)
	_fire_pose_duration = fire_animation.length if fire_animation != null else 0.0
	return true


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
				posture if requested_action == &"" else &""
			)
	var blend := blend_seconds
	if blend < 0.0:
		blend = locomotion_blend_seconds if _is_locomotion_clip(previous_clip) and _is_locomotion_clip(clip_name) else transition_blend_seconds
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
	if posture_layer != null:
		posture_layer.set_animation_frame_rotation_overrides(
			_active_frame_pose.get("joint_rotations", {})
		)
	if weapon_pose_solver != null:
		weapon_pose_solver.set_animation_frame_pose(_active_frame_pose)


func _modern_state_for_clip(clip_name: StringName) -> StringName:
	if requested_action != &"":
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


func _trigger_fire_recoil() -> void:
	_recoil_remaining = recoil_duration


func _recoil_weight() -> float:
	if recoil_duration <= 0.0 or _recoil_remaining <= 0.0:
		return 0.0
	var phase := 1.0 - clampf(_recoil_remaining / recoil_duration, 0.0, 1.0)
	return sin(phase * PI) * exp(-phase * 2.2)


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
	weapon_ready_weight = clampf(ready_weight, 0.0, 1.0)
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
		"locomotion_blend_seconds": locomotion_blend_seconds,
		"direction_octant": _stable_direction_octant,
		"recoil_weight": _recoil_weight(),
		"upper_body_recoil_layer": true,
		"transition_reason": _last_transition_reason,
		"movement_speed_mps": movement_speed_mps,
		"prone_straighten_weight": _prone_straighten_weight,
		"prone_axis_weight": _prone_straighten_weight,
		"prone_axis_target_pitch_deg": prone_axis_target_pitch_deg,
		"prone_axis_max_correction_deg": prone_axis_max_correction_deg,
		"peek_amount": peek_amount,
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
