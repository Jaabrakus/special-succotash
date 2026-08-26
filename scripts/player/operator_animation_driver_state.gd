extends Node3D

signal action_completed(clip_name: StringName)
signal action_cancelled(clip_name: StringName)
signal action_release_cue(clip_name: StringName)
signal action_recovery_cue(clip_name: StringName)
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
const FootContactLock := preload("res://scripts/player/operator_foot_contact_lock.gd")
const WeaponPoseSolver := preload("res://scripts/player/operator_weapon_pose_solver.gd")
const WeaponGripContact := preload("res://scripts/player/operator_weapon_grip_contact.gd")
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
const GrenadeProfile := preload("res://scripts/tactical/tactical_grenade_profile.gd")
const PosePipeline := preload("res://scripts/player/operator_pose_pipeline.gd")
const FireUpperBodyLatch := preload(
	"res://scripts/player/operator_fire_upper_body_latch.gd"
)
const PoseHandoff := preload(
	"res://scripts/player/operator_pose_handoff.gd"
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
var foot_contact_lock
var weapon_pose_solver
var weapon_grip_contact: SocomOperatorWeaponGripContact
var audio_event_manager: AudioAnimationEventManager
var animation_frame_pose_runtime
var pose_pipeline
var fire_upper_body_latch
var pose_handoff

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
var _requested_action_recovery_cue_emitted: bool = false
var _standing_master_pose_frame_suppressed: bool = false
var _equipped_weapon_visible: bool = true
var _fire_ready_hold_remaining: float = 0.0
var _grenade_recovery_blend_seconds_cached: float = 0.12
var _presentation_posture: StringName = &"STANDING"
var _presentation_ready_weight: float = 0.0
var _presentation_fire_selected: bool = false
