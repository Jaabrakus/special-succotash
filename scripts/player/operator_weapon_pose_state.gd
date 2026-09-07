extends Node3D

var fire_recoil := preload("res://scripts/player/operator_fire_recoil_pulse.gd").new()
var strafe_left_elbow_flare_degrees: float = 0.0
var authored_shoulder_stock_enabled: bool = false
var authored_shoulder_stock_active: bool = false
var strafe_right_stock_release_m: float = 0.0
var strafe_right_stock_release_frame: StringName = &"aim_forward"
var authored_stock_signed_strafe: float = 0.0
var authored_stock_right_turn_weight: float = -1.0
var authored_stock_release_applied_m: float = 0.0
var authored_stock_release_direction_world := Vector3.ZERO
var ready_shoulder_pocket_downward_m: float = 0.0
var ready_shoulder_pocket_right_wrist_roll_degrees: float = 0.0

## Post-animation, visual-only arm solver. The authoritative reticle and shot
## remain outside this layer; this node only makes the rendered operator reach
## a constrained rifle pose that follows the supplied aim intent.

const ARM_BONES := {
	&"left": [&"mixamorig_LeftArm", &"mixamorig_LeftForeArm", &"mixamorig_LeftHand"],
	&"right": [&"mixamorig_RightArm", &"mixamorig_RightForeArm", &"mixamorig_RightHand"],
}

const BONE_CANDIDATES := {
	&"mixamorig_Spine2": [&"mixamorig_Spine2", &"Bip01 Spine3"],
	&"mixamorig_Head": [&"mixamorig_Head", &"Bip01 Head"],
	&"mixamorig_LeftArm": [&"mixamorig_LeftArm", &"Bip01 L UpperArm"],
	&"mixamorig_LeftForeArm": [&"mixamorig_LeftForeArm", &"Bip01 L Forearm"],
	&"mixamorig_LeftHand": [&"mixamorig_LeftHand", &"Bip01 L Hand"],
	&"mixamorig_RightArm": [&"mixamorig_RightArm", &"Bip01 R UpperArm"],
	&"mixamorig_RightForeArm": [&"mixamorig_RightForeArm", &"Bip01 R Forearm"],
	&"mixamorig_RightHand": [&"mixamorig_RightHand", &"Bip01 R Hand"],
}

const GUN_PLACEMENT_FACE_UP_M := 0.09
const GUN_PLACEMENT_FACE_FORWARD_M := 0.13
const GUN_PLACEMENT_FRAME_BONE := &"mixamorig_Spine2"
# A rigid weapon may settle a few degrees inside an authored palm, but larger
# corrections visibly rotate the pistol grip out of that hand. Weapon-specific
# calibration must absorb anything beyond this presentation allowance.
const MAX_RIGID_GRIP_ALIGNMENT_DEG := 6.0
# A conventional two-hand pistol presentation keeps the dominant trigger palm
# just to the right of the anatomical aim plane. The offset scales with the
# live shoulder width so different operator sizes retain the same silhouette.
const PISTOL_TRIGGER_CENTERLINE_RATIO := 0.08
const PISTOL_CENTERLINE_MAX_SHIFT_M := 0.30
const ArmKinematics := preload("res://scripts/player/operator_arm_kinematics.gd")
const PoseDiagnostics := preload(
	"res://scripts/player/operator_weapon_pose_diagnostics.gd"
)
const PoseGeometry := preload(
	"res://scripts/player/operator_weapon_pose_geometry.gd"
)
const DiveWeaponPresentationProfile := preload(
	"res://scripts/player/operator_dive_weapon_presentation_profile.gd"
)
const SocketIK := preload(
	"res://scripts/player/operator_weapon_socket_ik.gd"
)
const WeaponOwnershipContract := preload(
	"res://scripts/player/weapon_ownership_contract.gd"
)
const GunPlacementProfile := preload("res://scripts/player/weapon_gun_placement_profile.gd")
const MobilityWeaponGripSolver := preload(
	"res://scripts/player/operator_mobility_weapon_grip_solver.gd"
)
const WeaponContactSolver := preload(
	"res://scripts/player/operator_weapon_contact_solver.gd"
)
const WeaponPresentationOwner := preload(
	"res://scripts/player/operator_weapon_presentation_owner.gd"
)
const WeaponStockConstraint := preload(
	"res://scripts/player/operator_weapon_stock_constraint.gd"
)

@export_category("Response")
@export_range(1.0, 30.0, 0.5) var enter_response: float = 18.0
@export_range(1.0, 30.0, 0.5) var exit_response: float = 12.0
@export_range(1.0, 30.0, 0.5) var cover_response: float = 16.0
@export_range(0.0, 1.0, 0.05) var animation_carry_weight: float = 0.65
@export_range(0.0, 0.08, 0.005) var animation_carry_limit_m: float = 0.035
@export_range(0.05, 0.35, 0.01) var ownership_return_seconds: float = 0.18
@export_range(0.0, 0.10, 0.005) var locomotion_weapon_carry_horizontal_limit_m: float = 0.020
@export_range(0.0, 0.12, 0.001) var locomotion_weapon_carry_vertical_limit_m: float = 0.035
@export_range(1.0, 30.0, 0.5) var locomotion_weapon_carry_response: float = 6.0
@export_range(0.0, 0.5, 0.01) var locomotion_weapon_shoulder_sway_gain: float = 0.0
@export_range(0.0, 0.25, 0.01) var mobility_hand_contact_limit_m: float = 0.06

@export_category("Rifle Pose")
@export_range(0.45, 0.90, 0.01) var trigger_reach_ratio: float = 0.72
@export_range(0.55, 0.96, 0.01) var support_reach_ratio: float = 0.84
@export_range(0.02, 0.30, 0.01) var grip_half_width: float = 0.12
@export_range(0.08, 0.38, 0.01) var support_forward_offset: float = 0.20
@export_range(-0.30, 0.20, 0.01) var grip_height_offset: float = -0.06
@export_range(0.15, 0.70, 0.01) var elbow_flare: float = 0.42
@export_range(-0.30, 0.30, 0.01) var elbow_height: float = -0.08
@export_range(0.10, 0.70, 0.01) var tucked_reach_ratio: float = 0.48
@export_range(1, 4, 1) var solve_iterations: int = 3

@export_category("Prone Ground Clearance")
@export_range(0.04, 0.20, 0.005) var prone_hand_floor_clearance_m: float = 0.10
@export_range(0.03, 0.16, 0.005) var prone_elbow_floor_clearance_m: float = 0.065
@export_range(0.04, 0.20, 0.005) var prone_muzzle_floor_clearance_m: float = 0.085
@export_range(0.0, 0.30, 0.005) var prone_ready_grip_drop_m: float = 0.16
@export_range(0.0, 0.25, 0.005) var prone_maximum_grip_above_chest_m: float = 0.10
@export_range(0.70, 1.0, 0.01) var prone_support_reach_scale: float = 0.84
@export_range(0.12, 0.60, 0.01) var prone_minimum_elbow_outward_m: float = 0.46
@export_range(-0.10, 0.20, 0.005) var prone_elbow_raise_m: float = 0.0
@export_range(0.0, 0.25, 0.005) var prone_maximum_elbow_above_chest_m: float = 0.08
@export_range(1.0, 30.0, 0.5) var prone_floor_response: float = 18.0
@export_range(0.05, 0.25, 0.005) var prone_maximum_floor_lift_m: float = 0.12
@export_range(0.20, 1.20, 0.05) var prone_floor_probe_up_m: float = 0.60
@export_range(0.20, 1.50, 0.05) var prone_floor_probe_down_m: float = 0.90

@export_category("Anatomical Guardrails")
## These limits form a compact human-motion model. They prevent the solver
## from satisfying the reticle by folding an elbow through the ribcage or by
## hyperextending an arm. The torso/orientation layer remains responsible for
## turning the body when a target exceeds this comfortable envelope.
@export_range(20.0, 80.0, 1.0) var minimum_elbow_angle_deg: float = 42.0
@export_range(105.0, 170.0, 1.0) var maximum_elbow_angle_deg: float = 150.0
@export_range(0.20, 0.70, 0.01) var minimum_forward_reach_ratio: float = 0.38
@export_range(45.0, 120.0, 1.0) var shoulder_yaw_limit_deg: float = 92.0
@export_range(20.0, 85.0, 1.0) var shoulder_pitch_up_limit_deg: float = 68.0
@export_range(20.0, 85.0, 1.0) var shoulder_pitch_down_limit_deg: float = 58.0
@export_range(20.0, 80.0, 1.0) var torso_assist_angle_deg: float = 38.0
@export_range(25.0, 90.0, 1.0) var maximum_wrist_correction_deg: float = 72.0
@export var weapon_forward_local := Vector3.BACK

@export_category("Weapon Socket Contract")
@export var use_weapon_socket_contract: bool = true
@export_range(0.0, 45.0, 1.0) var blocked_low_ready_pitch_deg: float = 24.0
@export_range(0.0, 45.0, 1.0) var blocked_crouch_pitch_deg: float = 20.0
@export_range(0.0, 45.0, 1.0) var blocked_prone_pitch_deg: float = 16.0
@export_range(0.0, 1.0, 0.05) var blocked_pose_threshold: float = 0.55

var skeleton: Skeleton3D
var weapon_node: Node3D
var trigger_socket: Marker3D
var support_socket: Marker3D
var muzzle_socket: Marker3D
var barrel_base_socket: Marker3D
var optic_socket: Marker3D
var stock_socket: Marker3D
var stock_constraint: SocomOperatorWeaponStockConstraint
var trigger_hand_target: Marker3D
var support_hand_target: Marker3D
var right_elbow_pole: Marker3D
var left_elbow_pole: Marker3D
var aim_target_marker: Marker3D
var bone_indices: Dictionary = {}
var current_weight: float = 0.0
var desired_weight: float = 0.0
var target_reachable: bool = true
var trigger_hand_error_m: float = 0.0
var support_hand_error_m: float = 0.0
var last_aim_direction := Vector3.FORWARD
var last_target_point := Vector3.ZERO
var last_posture: StringName = &"STANDING"
var last_movement_state: StringName = &"STANDING"
var last_requested_action: StringName = &""
var last_reload_support_regrip := false
var last_ready_weight := 0.0
var last_peek_amount := 0.0
var left_lean_weapon_handoff_active := false
var anatomical_adjustment_m: float = 0.0
var torso_assist_requested: bool = false
var aim_yaw_demand_deg: float = 0.0
var aim_pitch_demand_deg: float = 0.0
var right_elbow_angle_deg: float = 0.0
var left_elbow_angle_deg: float = 0.0
var weapon_aim_error_deg: float = 0.0
var wrist_correction_deg: float = 0.0
var cover_pose_amount: float = 0.0
var cover_pose_name: StringName = &"CLEAR"
var shot_blocked: bool = false
var socket_contract_active: bool = false
var adaptive_support_socket: bool = false
var elbow_pole_offsets_by_posture: Dictionary = {}
var weapon_animation_parent: Node
var weapon_hand_mount_transform := Transform3D.IDENTITY
var weapon_solver_anchor: Node3D
var weapon_presentation_owner: SocomOperatorWeaponPresentationOwner
var weapon_solver_owned: bool = false
var right_hand_owns_ready_weapon: bool = false
var animation_drives_ready_hands: bool = false
var hand_socket_ik_enabled: bool = true
var support_hand_socket_ik_enabled: bool = false
var animation_owned_aim_alignment_enabled: bool = false
var animation_owned_aim_alignment_active: bool = false
var pistol_trigger_centerline_ik_active: bool = false
var pistol_trigger_centerline_shift_m: float = 0.0
var support_hand_ik_blend_seconds: float = 0.35
var ownership_return_start := Transform3D.IDENTITY
var ownership_return_elapsed: float = 0.18
var action_weapon_follow_active: bool = false
var action_weapon_follow_start := Transform3D.IDENTITY
var action_weapon_hand_offset := Transform3D.IDENTITY
var action_weapon_barrel_local := Vector3.FORWARD
var action_weapon_swing_deg: float = 0.0
var action_weapon_chest_start_origin := Vector3.ZERO
var action_weapon_follow_elapsed: float = 0.0
var action_weapon_follow_blend_seconds: float = 0.12
var action_weapon_chest_owned: bool = false
var weapon_owner: StringName = WeaponOwnershipContract.HOLSTERED_ANIMATION
var previous_weapon_owner: StringName = WeaponOwnershipContract.HOLSTERED_ANIMATION
var weapon_owner_transition_count: int = 0
var right_palm_anchor_local := Vector3.ZERO
var left_palm_anchor_local := Vector3.ZERO
var action_trigger_contact_error_m: float = 0.0
var action_support_contact_error_m: float = 0.0
var support_hand_mode: StringName = &"IK_TO_WEAPON"
var trigger_hand_grip_basis_by_posture: Dictionary = {}
var support_hand_grip_basis_by_posture: Dictionary = {}
var trigger_hand_grip_locked := false
var trigger_hand_grip_rotation_error_deg := 0.0
var support_hand_grip_locked := false
var support_hand_grip_rotation_error_deg := 0.0
var right_hand_ik: SkeletonIK3D
var left_hand_ik: SkeletonIK3D
var animation_frame_pose: Dictionary = {}
var frame_socket_override_active := false
var frame_trigger_socket_base := Vector3.ZERO
var frame_support_socket_base := Vector3.ZERO
var support_socket_clamped := false
var prone_floor_lift_m: float = 0.0
var prone_floor_smoothed_lift_m: float = 0.0
var muzzle_floor_clearance_m: float = INF
var prone_floor_contact_detected: bool = false
var gun_placement_line_by_posture: Dictionary = {}
var gun_placement_anchor_local_by_posture: Dictionary = {}
var gun_placement_frame_origin_local_by_posture: Dictionary = {}
var gun_placement_shoulder_delta_local_by_posture: Dictionary = {}
var ready_trigger_shoulder_offset_by_posture: Dictionary = {}
var gun_placement_baseline_basis_by_posture: Dictionary = {}
var gun_placement_line_active: bool = false
var gun_placement_line_authored: bool = false
var rail_to_blue_line_event_remaining: float = 0.0
var gun_placement_error_m: float = 0.0
var gun_placement_roll_error_deg: float = 0.0
var last_gun_placement_origin := Vector3.ZERO
var last_gun_placement_direction := Vector3.FORWARD
var gun_placement_locomotion_carry_local := Vector3.ZERO
var gun_placement_locomotion_active := false
var gun_placement_apply_delta := 1.0 / 60.0
var gun_placement_shoulder_alternation_m := 0.0
var gun_placement_relative_yaw_rad: float = 0.0
var stable_chest_anchor_world := Vector3.ZERO
var stable_chest_anchor_active := false
var dive_weapon_presentation: Dictionary = DiveWeaponPresentationProfile.load_profile()
var last_unobstructed_render_direction := Vector3.ZERO
var obstruction_direction_hold_active := false
