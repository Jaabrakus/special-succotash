class_name SocomOperatorWeaponPoseSolver
extends Node3D

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
const STANDING_CHEST_ANCHOR_LOCAL := Vector3(0.0, 1.52, 0.0)
const CROUCHED_CHEST_ANCHOR_LOCAL := Vector3(0.0, 1.12, 0.0)
const PRONE_CHEST_ANCHOR_LOCAL := Vector3(0.0, 0.42, 0.02)
const ArmKinematics := preload("res://scripts/player/operator_arm_kinematics.gd")
const WeaponOwnershipContract := preload(
	"res://scripts/player/weapon_ownership_contract.gd"
)
const GunPlacementProfile := preload("res://scripts/player/weapon_gun_placement_profile.gd")
const TwoHandWeaponCarry := preload(
	"res://scripts/player/operator_two_hand_weapon_carry.gd"
)
const WeaponContactSolver := preload(
	"res://scripts/player/operator_weapon_contact_solver.gd"
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
@export_range(0.70, 1.0, 0.01) var prone_support_reach_scale: float = 0.84
@export_range(0.12, 0.60, 0.01) var prone_minimum_elbow_outward_m: float = 0.46
@export_range(1.0, 30.0, 0.5) var prone_floor_response: float = 18.0
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
var weapon_solver_owned: bool = false
var right_hand_owns_ready_weapon: bool = false
var animation_drives_ready_hands: bool = false
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
var last_unobstructed_render_direction := Vector3.ZERO
var obstruction_direction_hold_active := false


func bind(target_skeleton: Skeleton3D, attached_weapon: Node3D) -> void:
	skeleton = target_skeleton
	weapon_node = attached_weapon
	weapon_animation_parent = weapon_node.get_parent() if weapon_node != null else null
	weapon_hand_mount_transform = weapon_node.transform if weapon_node != null else Transform3D.IDENTITY
	weapon_solver_anchor = Node3D.new()
	weapon_solver_anchor.name = "WeaponSolverAnchor"
	add_child(weapon_solver_anchor)
	trigger_socket = _find_weapon_socket("Socket_RightHand")
	support_socket = _find_weapon_socket("Socket_LeftHand")
	muzzle_socket = _find_weapon_socket("Socket_Muzzle")
	barrel_base_socket = _find_weapon_socket("Socket_BarrelBase")
	optic_socket = _find_weapon_socket("Socket_Optic")
	socket_contract_active = (
		use_weapon_socket_contract
		and trigger_socket != null
		and support_socket != null
		and muzzle_socket != null
	)
	adaptive_support_socket = (
		support_socket != null
		and not bool(support_socket.get_meta("authored_weapon_socket", false))
	)
	bone_indices.clear()
	if skeleton == null:
		return
	for side: StringName in ARM_BONES:
		var names: Array = ARM_BONES[side]
		for bone_name in names:
			bone_indices[StringName(bone_name)] = _resolve_bone_index(StringName(bone_name))
	bone_indices[GUN_PLACEMENT_FRAME_BONE] = _resolve_bone_index(
		GUN_PLACEMENT_FRAME_BONE
	)
	bone_indices[&"mixamorig_Head"] = _resolve_bone_index(&"mixamorig_Head")
	right_palm_anchor_local = _calculate_palm_anchor(
		"Right",
		int(bone_indices.get(&"mixamorig_RightHand", -1))
	)
	left_palm_anchor_local = _calculate_palm_anchor(
		"Left",
		int(bone_indices.get(&"mixamorig_LeftHand", -1))
	)
	_calibrate_hand_mount_contact()
	_build_targets()
	_build_socket_ik()


func rebind_weapon(attached_weapon: Node3D) -> void:
	_stop_socket_ik()
	weapon_node = attached_weapon
	weapon_animation_parent = weapon_node.get_parent() if weapon_node != null else null
	weapon_hand_mount_transform = weapon_node.transform if weapon_node != null else Transform3D.IDENTITY
	trigger_socket = _find_weapon_socket("Socket_RightHand")
	support_socket = _find_weapon_socket("Socket_LeftHand")
	muzzle_socket = _find_weapon_socket("Socket_Muzzle")
	barrel_base_socket = _find_weapon_socket("Socket_BarrelBase")
	optic_socket = _find_weapon_socket("Socket_Optic")
	socket_contract_active = (
		use_weapon_socket_contract
		and trigger_socket != null
		and support_socket != null
		and muzzle_socket != null
	)
	adaptive_support_socket = (
		support_socket != null
		and not bool(support_socket.get_meta("authored_weapon_socket", false))
	)
	_calibrate_hand_mount_contact()
	weapon_solver_owned = false
	action_weapon_follow_active = false
	gun_placement_baseline_basis_by_posture.clear()
	trigger_hand_grip_basis_by_posture.clear()
	support_hand_grip_basis_by_posture.clear()


func _calibrate_hand_mount_contact() -> void:
	if (
		weapon_node == null
		or trigger_socket == null
		or skeleton == null
		or weapon_animation_parent == null
		or weapon_node.get_parent() != weapon_animation_parent
	):
		return
	skeleton.force_update_all_bone_transforms()
	var palm_world := _right_hand_grip_world_transform().origin
	weapon_node.global_position += palm_world - trigger_socket.global_position
	# This corrected transform is the sole persistent hand mount. Ready, relaxed,
	# reload recovery and weapon swaps all return to the same palm contact.
	weapon_hand_mount_transform = weapon_node.transform


func configure_joint_poles(raw_poles: Variant) -> void:
	elbow_pole_offsets_by_posture.clear()
	if not raw_poles is Dictionary:
		return
	var pole_document := raw_poles as Dictionary
	var by_stance: Variant = pole_document.get("by_stance", {})
	if by_stance is Dictionary:
		for posture_name in (by_stance as Dictionary).keys():
			var stance_value: Variant = (by_stance as Dictionary)[posture_name]
			if stance_value is Dictionary:
				elbow_pole_offsets_by_posture[StringName(posture_name)] = {
					"right": _vector_from_data((stance_value as Dictionary).get("right", {})),
					"left": _vector_from_data((stance_value as Dictionary).get("left", {})),
				}
	if elbow_pole_offsets_by_posture.is_empty():
		var fallback := {
			"right": _vector_from_data(pole_document.get("right", {})),
			"left": _vector_from_data(pole_document.get("left", {})),
		}
		for posture_name: StringName in [&"STANDING", &"CROUCHED", &"PRONE"]:
			elbow_pole_offsets_by_posture[posture_name] = fallback.duplicate(true)


func configure_dynamic_hold(raw_profile: Variant) -> void:
	if not raw_profile is Dictionary:
		return
	var profile := raw_profile as Dictionary
	animation_carry_weight = clampf(
		float(profile.get("animation_carry_weight", animation_carry_weight)),
		0.0,
		1.0
	)
	animation_carry_limit_m = clampf(
		float(profile.get("animation_carry_limit_m", animation_carry_limit_m)),
		0.0,
		0.08
	)
	ownership_return_seconds = clampf(
		float(profile.get("reload_return_blend_seconds", ownership_return_seconds)),
		0.05,
		0.35
	)
	maximum_wrist_correction_deg = clampf(
		float(profile.get("hand_owned_aim_correction_limit_deg", maximum_wrist_correction_deg)),
		25.0,
		180.0
	)
	right_hand_owns_ready_weapon = bool(
		profile.get("right_hand_owns_weapon", right_hand_owns_ready_weapon)
	)
	animation_drives_ready_hands = bool(
		profile.get("animation_drives_ready_hands", animation_drives_ready_hands)
	)

func configure_gun_placement_line(raw_profile: Variant) -> void:
	gun_placement_line_by_posture.clear()
	gun_placement_baseline_basis_by_posture.clear()
	trigger_hand_grip_basis_by_posture.clear()
	support_hand_grip_basis_by_posture.clear()
	gun_placement_anchor_local_by_posture.clear()
	gun_placement_frame_origin_local_by_posture.clear()
	gun_placement_shoulder_delta_local_by_posture.clear()
	ready_trigger_shoulder_offset_by_posture.clear()
	gun_placement_locomotion_carry_local = Vector3.ZERO
	gun_placement_shoulder_alternation_m = 0.0
	gun_placement_line_active = false
	gun_placement_line_authored = false
	rail_to_blue_line_event_remaining = 0.0
	var parsed := GunPlacementProfile.parse(raw_profile)
	gun_placement_line_by_posture = parsed.get("by_posture", {})
	gun_placement_line_authored = bool(parsed.get("authored", false))
	gun_placement_line_active = (
		gun_placement_line_authored and bool(parsed.get("runtime_enabled", false))
	)


func trigger_rail_to_blue_line(duration_seconds: float) -> bool:
	if not gun_placement_line_authored:
		return false
	rail_to_blue_line_event_remaining = maxf(
		rail_to_blue_line_event_remaining,
		maxf(duration_seconds, 0.05)
	)
	if weapon_node != null:
		ownership_return_start = weapon_node.global_transform
		ownership_return_elapsed = 0.0
	return true


func release_visual_control() -> void:
	rail_to_blue_line_event_remaining = 0.0
	current_weight = 0.0
	desired_weight = 0.0
	_release_trigger_hand_grip_lock()
	_release_support_hand_grip_lock()
	_stop_socket_ik()
	_set_weapon_solver_owned(false)


func set_animation_frame_pose(raw_pose: Variant) -> void:
	var next_pose := raw_pose as Dictionary if raw_pose is Dictionary else {}
	if next_pose.is_empty():
		_clear_frame_socket_override()
		animation_frame_pose = {}
		return
	if not frame_socket_override_active:
		frame_trigger_socket_base = trigger_socket.position if trigger_socket != null else Vector3.ZERO
		frame_support_socket_base = support_socket.position if support_socket != null else Vector3.ZERO
		frame_socket_override_active = true
	animation_frame_pose = next_pose.duplicate(true)
	if (
		trigger_socket != null
		and animation_frame_pose.has("right_hand_target")
		and animation_frame_pose["right_hand_target"] is Dictionary
	):
		trigger_socket.position = _vector_from_data(animation_frame_pose["right_hand_target"])
	if (
		support_socket != null
		and animation_frame_pose.has("left_hand_target")
		and animation_frame_pose["left_hand_target"] is Dictionary
	):
		support_socket.position = _vector_from_data(animation_frame_pose["left_hand_target"])


func clear_animation_frame_pose() -> void:
	set_animation_frame_pose({})


func interrupt_action_weapon_follow() -> void:
	action_weapon_follow_active = false
	ownership_return_elapsed = ownership_return_seconds
	clear_animation_frame_pose()
	_stop_socket_ik()


func _animation_frame_weapon_correction_transform() -> Transform3D:
	if animation_frame_pose.is_empty():
		return Transform3D.IDENTITY
	var position := _vector_from_data(
		animation_frame_pose.get("weapon_hand_position_correction", {})
	)
	var rotation_degrees := _animation_frame_weapon_rotation_degrees()
	return Transform3D(
		Basis.from_euler(
			Vector3(
				deg_to_rad(rotation_degrees.x),
				deg_to_rad(rotation_degrees.y),
				deg_to_rad(rotation_degrees.z)
			),
			EULER_ORDER_YXZ
		),
		position
	)


func _animation_frame_weapon_rotation_degrees() -> Vector3:
	return _vector_from_data(
		animation_frame_pose.get("weapon_hand_rotation_correction_deg", {})
	)


func _animation_frame_hand_rotation_basis(side: StringName) -> Basis:
	var field := "%s_hand_rotation_correction_deg" % String(side)
	var rotation_degrees := _vector_from_data(animation_frame_pose.get(field, {}))
	return Basis.from_euler(rotation_degrees * (PI / 180.0), EULER_ORDER_YXZ).orthonormalized()


func _clear_frame_socket_override() -> void:
	if not frame_socket_override_active:
		return
	if trigger_socket != null:
		trigger_socket.position = frame_trigger_socket_base
	if support_socket != null:
		support_socket.position = frame_support_socket_base
	frame_socket_override_active = false


func apply(
	aim_yaw: float,
	aim_pitch: float,
	posture: StringName,
	movement_state: StringName,
	ready_weight: float,
	obstruction_amount: float,
	requested_action: StringName,
	reload_support_regrip: bool,
	world_aim_target: Vector3,
	body: Node3D,
	delta: float,
	locomotion_active_hint: bool = false
) -> void:
	if skeleton == null or body == null:
		return
	var rail_event_was_active := rail_to_blue_line_event_remaining > 0.0
	rail_to_blue_line_event_remaining = maxf(
		rail_to_blue_line_event_remaining - maxf(delta, 0.0),
		0.0
	)
	if rail_event_was_active and rail_to_blue_line_event_remaining <= 0.0 and weapon_node:
		# Blend back to the animation-owned ready pose after the fire overlay ends.
		ownership_return_start = weapon_node.global_transform
		ownership_return_elapsed = 0.0
	support_socket_clamped = false
	# The pose is rebuilt from the animation result every frame. Clearing the
	# prior visual override prevents the IK result from feeding back into its
	# own measurements and lets animation remain the source pose.
	skeleton.clear_bones_global_pose_override()
	skeleton.force_update_all_bone_transforms()
	var sampled_trigger_hand_position := _bone_world_position(&"mixamorig_RightHand")
	var sampled_trigger_palm_position := _right_hand_grip_world_transform().origin
	var sampled_support_hand_position := _bone_world_position(&"mixamorig_LeftHand")
	last_posture = posture
	last_movement_state = movement_state
	last_requested_action = requested_action
	last_reload_support_regrip = reload_support_regrip
	last_ready_weight = ready_weight
	# Keep the presentation target current even while the rifle is at low ready.
	# Fire can enter ready aim on this frame; a stale target would make the visual
	# rail solve toward the previous camera direction before the next update.
	if world_aim_target != Vector3.ZERO:
		last_target_point = world_aim_target
		if aim_target_marker != null:
			aim_target_marker.global_position = world_aim_target
	stable_chest_anchor_world = _stable_chest_anchor(body, posture, movement_state)
	stable_chest_anchor_active = true
	gun_placement_relative_yaw_rad = aim_yaw
	gun_placement_apply_delta = clampf(delta, 0.0, 0.05)
	gun_placement_locomotion_active = (
		locomotion_active_hint
		or (
			body is CharacterBody3D
			and Vector2(
				(body as CharacterBody3D).velocity.x,
				(body as CharacterBody3D).velocity.z
			).length() > 0.15
		)
	)
	_set_weapon_owner(
		WeaponOwnershipContract.resolve(
			movement_state,
			requested_action,
			ready_weight,
			action_weapon_follow_active
		)
	)
	var reload_action_active := weapon_owner == WeaponOwnershipContract.RELOAD_RIGHT_HAND
	var action_owns_arms := WeaponOwnershipContract.action_owns_arms(weapon_owner)
	support_hand_mode = WeaponOwnershipContract.support_hand_owner(
		weapon_owner,
		reload_support_regrip
	)
	if action_owns_arms:
		_release_trigger_hand_grip_lock()
		_release_support_hand_grip_lock()
		if WeaponOwnershipContract.weapon_follows_right_hand(weapon_owner):
			# Mobility preserves the authored arm take. The right palm carries rifle
			# translation and barrel yaw/pitch, while barrel roll remains bounded.
			# Left-hand IK stays released until recovery reaches the saved ready pose.
			_update_action_weapon_follow(
				delta,
				WeaponOwnershipContract.uses_stable_chest_translation(weapon_owner)
			)
			if weapon_owner == WeaponOwnershipContract.MOBILITY_RIGHT_HAND:
				_stabilize_authored_two_hand_carry(
					sampled_trigger_hand_position,
					sampled_support_hand_position,
					(-body.global_basis.z).normalized()
				)
		if reload_action_active and right_hand_ik and right_hand_ik.is_running():
			right_hand_ik.stop()
		if reload_action_active and reload_support_regrip and support_socket != null:
			_solve_reload_support_arm_guardrail(
				posture,
				world_aim_target,
				body,
				support_socket.global_position
			)
		elif reload_action_active:
			_solve_reload_support_arm_guardrail(posture, world_aim_target, body)
		else:
			_stop_socket_ik()
		right_elbow_angle_deg = _current_elbow_angle(&"right")
		left_elbow_angle_deg = _current_elbow_angle(&"left")
		current_weight = 0.0
		desired_weight = 0.0
		return
	desired_weight = clampf(ready_weight, 0.0, 1.0)
	var response := enter_response if desired_weight > current_weight else exit_response
	current_weight = lerpf(
		current_weight,
		desired_weight,
		1.0 - exp(-response * delta)
	)
	if current_weight <= 0.001:
		_release_trigger_hand_grip_lock()
		_release_support_hand_grip_lock()
		_set_weapon_solver_owned(false)
		if weapon_owner == WeaponOwnershipContract.RELAXED_RIFLE_LOCOMOTION:
			# The imported right hand owns the canonical Gunsmith mount in relaxed
			# locomotion. Do not derive a second weapon transform from both palms;
			# that creates a weapon -> support hand -> weapon feedback loop. The
			# support palm follows the stable foregrip below.
			if support_socket != null and left_hand_ik != null:
				support_hand_target.global_position = support_socket.global_position
				_lock_support_hand_grip_to_weapon()
				_solve_socket_arm(
					left_hand_ik,
					support_hand_target,
					left_elbow_pole,
					&"mixamorig_LeftHand"
				)
				skeleton.force_update_all_bone_transforms()
		return
	_set_weapon_solver_owned(true)
	_capture_gunsmith_ready_baseline(posture)

	var right_shoulder := _bone_world_position(&"mixamorig_RightArm")
	var left_shoulder := _bone_world_position(&"mixamorig_LeftArm")
	var shoulder_center := (right_shoulder + left_shoulder) * 0.5
	if not ready_trigger_shoulder_offset_by_posture.has(posture):
		ready_trigger_shoulder_offset_by_posture[posture] = (
			skeleton.global_basis.orthonormalized().inverse()
			* (sampled_trigger_palm_position - stable_chest_anchor_world)
		)
	# The reticle target is a world point. The barrel must point from the muzzle
	# to that point, not from the shoulder center. Using the shoulder introduced
	# visible parallax in prone even though both rays looked almost parallel.
	var visual_aim_origin := (
		muzzle_socket.global_position
		if muzzle_socket != null
		else shoulder_center
	)
	var aim_direction := _resolve_aim_direction(
		aim_yaw,
		aim_pitch,
		world_aim_target,
		visual_aim_origin,
		body
	)
	last_aim_direction = aim_direction
	var body_forward := (-body.global_basis.z).normalized()
	var body_right := body.global_basis.x.normalized()
	var flat_aim := Vector3(aim_direction.x, 0.0, aim_direction.z).normalized()
	if flat_aim.length_squared() > 0.50:
		aim_yaw_demand_deg = rad_to_deg(atan2(flat_aim.dot(body_right), flat_aim.dot(body_forward)))
	aim_pitch_demand_deg = rad_to_deg(asin(clampf(aim_direction.y, -1.0, 1.0)))
	torso_assist_requested = absf(aim_yaw_demand_deg) > torso_assist_angle_deg
	last_target_point = (
		world_aim_target
		if world_aim_target != Vector3.ZERO
		else shoulder_center + aim_direction * 20.0
	)
	var world_up := Vector3.UP
	var aim_right := aim_direction.cross(world_up).normalized()
	if aim_right.length_squared() < 0.50:
		aim_right = body.global_basis.x.normalized()

	var right_reach := _arm_length(&"right")
	var left_reach := _arm_length(&"left")
	var support_arm_reach := (
		left_reach * prone_support_reach_scale
		if posture == &"PRONE"
		else left_reach
	)
	var obstruction_target := clampf(obstruction_amount, 0.0, 1.0)
	obstruction_direction_hold_active = (
		obstruction_target > 0.02
		or cover_pose_amount > 0.02
	)
	cover_pose_amount = lerpf(
		cover_pose_amount,
		obstruction_target,
		1.0 - exp(-cover_response * clampf(delta, 0.0, 0.05))
	)
	var tuck := cover_pose_amount
	shot_blocked = cover_pose_amount >= blocked_pose_threshold
	cover_pose_name = (
		(
			&"PRONE_TUCK"
			if posture == &"PRONE"
			else (&"CROUCH_LOW_READY" if posture == &"CROUCHED" else &"LOW_READY")
		)
		if shot_blocked
		else (&"REFRAMING" if cover_pose_amount > 0.02 else &"CLEAR")
	)
	var trigger_ratio := lerpf(trigger_reach_ratio, tucked_reach_ratio, tuck)
	var raw_trigger_position := (
		shoulder_center
		+ aim_direction * right_reach * trigger_ratio
		+ aim_right * grip_half_width
		+ world_up * lerpf(grip_height_offset, 0.10, tuck)
	)
	var raw_support_position := (
		shoulder_center
		+ aim_direction * (
			support_arm_reach * lerpf(support_reach_ratio, tucked_reach_ratio, tuck)
		)
		- aim_right * grip_half_width
		+ world_up * lerpf(grip_height_offset - 0.01, 0.12, tuck)
	)
	# The support hand advances along the foregrip only while both arms can
	# reach it. This keeps the pose useful with different weapon proportions.
	raw_support_position += aim_direction * support_forward_offset * (1.0 - tuck)
	if posture == &"PRONE":
		# Prone shoulders are rolled by the authored crawl pose. Reusing the
		# standing shoulder-relative height puts the rifle and both elbows over
		# the operator's head. Lower the complete two-hand grip toward the floor;
		# the clearance solve below raises it only if the ground requires it.
		raw_trigger_position -= world_up * prone_ready_grip_drop_m
		raw_support_position -= world_up * prone_ready_grip_drop_m
	var desired_floor_lift := 0.0
	if posture == &"PRONE":
		desired_floor_lift = maxf(
			_required_floor_lift(body, raw_trigger_position, prone_hand_floor_clearance_m),
			_required_floor_lift(body, raw_support_position, prone_hand_floor_clearance_m)
		)
	prone_floor_lift_m = lerpf(
		prone_floor_lift_m,
		desired_floor_lift,
		1.0 - exp(-prone_floor_response * clampf(delta, 0.0, 0.05))
	)
	if posture == &"PRONE" and prone_floor_lift_m > 0.0001:
		raw_trigger_position += world_up * prone_floor_lift_m
		raw_support_position += world_up * prone_floor_lift_m
	var trigger_position := _fit_human_reach(
		right_shoulder,
		raw_trigger_position,
		aim_direction,
		right_reach
	)
	if (
		gun_placement_locomotion_active
		and ready_trigger_shoulder_offset_by_posture.has(posture)
	):
		var neutral_trigger := (
			stable_chest_anchor_world
			+ skeleton.global_basis.orthonormalized()
			* Vector3(ready_trigger_shoulder_offset_by_posture[posture])
		)
		var authored_carry := sampled_trigger_palm_position - neutral_trigger
		if authored_carry.length() > animation_carry_limit_m:
			authored_carry = authored_carry.normalized() * animation_carry_limit_m
		trigger_position = neutral_trigger + authored_carry * animation_carry_weight
	var support_position := _fit_human_reach(
		left_shoulder,
		raw_support_position,
		aim_direction,
		support_arm_reach
	)
	if (
		requested_action == &""
		and animation_carry_weight > 0.0
		and not gun_placement_locomotion_active
	):
		var carry_delta := sampled_trigger_hand_position - trigger_position
		if carry_delta.length() > animation_carry_limit_m:
			carry_delta = carry_delta.normalized() * animation_carry_limit_m
		trigger_position += carry_delta * animation_carry_weight
	if posture == &"PRONE":
		var settled_floor_lift := maxf(
			_required_floor_lift(body, trigger_position, prone_hand_floor_clearance_m),
			_required_floor_lift(body, support_position, prone_hand_floor_clearance_m)
		)
		if settled_floor_lift > 0.0001:
			trigger_position += world_up * settled_floor_lift
			support_position += world_up * settled_floor_lift
			prone_floor_lift_m += settled_floor_lift
	anatomical_adjustment_m = maxf(
		raw_trigger_position.distance_to(trigger_position),
		raw_support_position.distance_to(support_position)
	)
	target_reachable = (
		raw_trigger_position.distance_to(trigger_position) <= 0.005
		and raw_support_position.distance_to(support_position) <= 0.005
	)
	trigger_hand_target.global_position = trigger_position
	support_hand_target.global_position = support_position
	aim_target_marker.global_position = last_target_point
	var prone_pole_raise := 0.12 if posture == &"PRONE" else 0.0
	var saved_poles: Dictionary = elbow_pole_offsets_by_posture.get(posture, {})
	var right_saved: Vector3 = saved_poles.get("right", Vector3.ZERO)
	var left_saved: Vector3 = saved_poles.get("left", Vector3.ZERO)
	if (
		animation_frame_pose.has("right_elbow_pole")
		and animation_frame_pose["right_elbow_pole"] is Dictionary
	):
		right_saved = _vector_from_data(animation_frame_pose["right_elbow_pole"])
	if (
		animation_frame_pose.has("left_elbow_pole")
		and animation_frame_pose["left_elbow_pole"] is Dictionary
	):
		left_saved = _vector_from_data(animation_frame_pose["left_elbow_pole"])
	var right_elbow_outward := elbow_flare + right_saved.x
	var left_elbow_outward := elbow_flare + left_saved.x
	if posture == &"PRONE":
		# A saved extreme inward pole must not fold either elbow across the neck.
		right_elbow_outward = maxf(right_elbow_outward, prone_minimum_elbow_outward_m)
		left_elbow_outward = maxf(left_elbow_outward, prone_minimum_elbow_outward_m)
	right_elbow_pole.global_position = (
		right_shoulder
		+ aim_right * right_elbow_outward
		+ aim_direction * (0.16 + right_saved.z)
		+ world_up * (elbow_height + prone_pole_raise + right_saved.y)
	)
	left_elbow_pole.global_position = (
		left_shoulder
		- aim_right * left_elbow_outward
		+ aim_direction * (0.16 + left_saved.z)
		+ world_up * (elbow_height + prone_pole_raise + left_saved.y)
	)
	if posture == &"PRONE":
		right_elbow_pole.global_position += world_up * _required_floor_lift(
			body,
			right_elbow_pole.global_position,
			prone_elbow_floor_clearance_m
		)
		left_elbow_pole.global_position += world_up * _required_floor_lift(
			body,
			left_elbow_pole.global_position,
			prone_elbow_floor_clearance_m
		)
	_solve_ready_weapon_pose(
		trigger_position,
		support_position,
		aim_direction,
		body_forward,
		left_shoulder,
		support_arm_reach,
		delta
	)
	if posture == &"PRONE" and muzzle_socket != null:
		var muzzle_lift := _required_floor_lift(
			body,
			muzzle_socket.global_position,
			prone_muzzle_floor_clearance_m
		)
		if muzzle_lift > 0.0001:
			trigger_position += world_up * muzzle_lift
			support_position += world_up * muzzle_lift
			right_elbow_pole.global_position += world_up * muzzle_lift
			left_elbow_pole.global_position += world_up * muzzle_lift
			prone_floor_lift_m += muzzle_lift
			_solve_ready_weapon_pose(
				trigger_position,
				support_position,
				aim_direction,
				body_forward,
				left_shoulder,
				support_arm_reach,
				delta
			)
	muzzle_floor_clearance_m = _floor_clearance(body, muzzle_socket.global_position) if muzzle_socket != null else INF
	prone_floor_contact_detected = posture == &"PRONE" and muzzle_floor_clearance_m < INF
	_update_errors()


func _solve_ready_weapon_pose(
	trigger_position: Vector3,
	support_position: Vector3,
	aim_direction: Vector3,
	body_forward: Vector3,
	left_shoulder: Vector3,
	left_reach: float,
	delta: float
) -> void:
	if socket_contract_active:
		if right_hand_owns_ready_weapon and not _gun_placement_line_active_for(last_posture):
			if animation_drives_ready_hands and not gun_placement_locomotion_active:
				_release_trigger_hand_grip_lock()
				if right_hand_ik != null and right_hand_ik.is_running():
					right_hand_ik.stop()
			else:
				trigger_hand_target.global_position = trigger_position
				_solve_socket_arm(
					right_hand_ik,
					trigger_hand_target,
					right_elbow_pole,
					&"mixamorig_RightHand"
				)
			_place_hand_owned_weapon(aim_direction, body_forward, delta)
			# This branch moves the weapon from the animated right hand instead of
			# solving the hand toward a world-space rifle. Keep the shared contact
			# target on the resulting trigger socket so diagnostics and later
			# ownership transitions measure the same hand-owned relationship.
			if trigger_socket != null:
				trigger_hand_target.global_position = trigger_socket.global_position
			if adaptive_support_socket:
				support_socket.global_position = support_position
			else:
				var authored_support := support_socket.global_position
				var reachable_support := _fit_human_reach(
					left_shoulder,
					authored_support,
					aim_direction,
					left_reach
				)
				if authored_support.distance_to(reachable_support) > 0.005:
					support_socket.global_position = reachable_support
					support_socket_clamped = true
			support_hand_target.global_position = support_socket.global_position
			_lock_support_hand_grip_to_weapon()
			_solve_socket_arm(
				left_hand_ik,
				support_hand_target,
				left_elbow_pole,
				&"mixamorig_LeftHand"
			)
		else:
			if _gun_placement_line_active_for(last_posture):
				_place_gunsmith_line_weapon(aim_direction, body_forward, delta)
				# The Aim Idle clip owns the natural wrist basis. Live blue-line
				# rotation moves the palm to the trigger socket without forcing a
				# second rigid wrist twist that can detach the hand at large aim angles.
				if right_hand_ik != null:
					right_hand_ik.override_tip_basis = false
			else:
				if right_hand_ik != null:
					right_hand_ik.override_tip_basis = true
				_place_socketed_weapon(trigger_position, aim_direction, body_forward, delta)
			if adaptive_support_socket:
				support_socket.global_position = support_position
			elif _gun_placement_line_active_for(last_posture):
				var authored_support := support_socket.global_position
				var reachable_support := _fit_human_reach(
					left_shoulder,
					authored_support,
					aim_direction,
					left_reach
				)
				if authored_support.distance_to(reachable_support) > 0.005:
					support_socket.global_position = reachable_support
					support_socket_clamped = true
			trigger_hand_target.global_position = trigger_socket.global_position
			support_hand_target.global_position = support_socket.global_position
			_lock_support_hand_grip_to_weapon()
			if _gun_placement_line_active_for(last_posture):
				# The saved placement line owns the rifle in ready state. Solve the
				# trigger hand to its socket with the same residual-corrected IK used
				# by the support hand. Keep the imported Aim Idle wrist basis: forcing
				# the socket basis here adds a second roll and twists the standing arm.
				_lock_trigger_hand_grip_to_weapon()
				_solve_socket_arm(
					right_hand_ik,
					trigger_hand_target,
					right_elbow_pole,
					&"mixamorig_RightHand"
				)
			else:
				_solve_socket_arm(
					right_hand_ik,
					trigger_hand_target,
					right_elbow_pole,
					&"mixamorig_RightHand"
				)
			_solve_socket_arm(left_hand_ik, support_hand_target, left_elbow_pole, &"mixamorig_LeftHand")
		skeleton.force_update_all_bone_transforms()
		_update_socket_weapon_error()
	else:
		_align_weapon_to_aim(aim_direction)


func _place_gunsmith_line_weapon(
	aim_direction: Vector3,
	body_forward: Vector3,
	delta: float
) -> void:
	if weapon_node == null or optic_socket == null or muzzle_socket == null:
		return
	var placement_origin := _gun_placement_origin(last_posture)
	var placement_direction := _gun_placement_direction(
		last_posture,
		_render_weapon_direction(aim_direction, body_forward)
	)
	var world_scale := weapon_node.global_basis.get_scale()
	var baseline_local: Variant = gun_placement_baseline_basis_by_posture.get(
		last_posture,
		null
	)
	if baseline_local is Basis:
		# Rebuild from the exact ready pose captured from the Gunsmith-authored
		# mount. Reload and mobility clips may rotate the weapon temporarily, but
		# their final frame cannot become the next ready pose's sideways twist.
		weapon_node.global_basis = (
			skeleton.global_basis.orthonormalized()
			* (baseline_local as Basis)
		).orthonormalized().scaled(world_scale)
	var barrel_origin: Vector3 = (
		barrel_base_socket.global_position
		if barrel_base_socket != null
		else trigger_socket.global_position
	)
	var current_barrel := (muzzle_socket.global_position - barrel_origin).normalized()
	if current_barrel.length_squared() < 0.50 or placement_direction.length_squared() < 0.50:
		return
	var aim_delta := Quaternion(current_barrel, placement_direction).normalized()
	weapon_node.global_basis = (
		Basis(aim_delta) * weapon_node.global_basis.orthonormalized()
	).orthonormalized().scaled(world_scale)
	var stance: Dictionary = gun_placement_line_by_posture.get(last_posture, {})
	_correct_gunsmith_weapon_roll(
		placement_direction,
		float(stance.get("roll_degrees", 0.0)),
		world_scale
	)
	weapon_node.global_position += placement_origin - optic_socket.global_position
	if rail_to_blue_line_event_remaining > 0.0:
		# An accepted shot must present the rail on the same reticle ray used by
		# ballistics on that frame. Blending into this pose made the bullet leave
		# before the visible rifle arrived. Recovery still uses the normal blend.
		ownership_return_elapsed = ownership_return_seconds
	else:
		_apply_ownership_return(weapon_node.global_transform, delta)
	last_gun_placement_origin = placement_origin
	last_gun_placement_direction = placement_direction
	gun_placement_error_m = optic_socket.global_position.distance_to(placement_origin)
	gun_placement_roll_error_deg = absf(
		_measure_gunsmith_weapon_roll_error(
			placement_direction,
			float(stance.get("roll_degrees", 0.0))
		)
	)


func _correct_gunsmith_weapon_roll(
	barrel_direction: Vector3,
	desired_roll_degrees: float,
	world_scale: Vector3
) -> void:
	var roll_error := _measure_gunsmith_weapon_roll_error(
		barrel_direction,
		desired_roll_degrees
	)
	if is_nan(roll_error) or is_inf(roll_error) or absf(roll_error) <= 0.00001:
		return
	weapon_node.global_basis = (
		Basis(Quaternion(barrel_direction.normalized(), roll_error))
		* weapon_node.global_basis.orthonormalized()
	).orthonormalized().scaled(world_scale)


func _measure_gunsmith_weapon_roll_error(
	barrel_direction: Vector3,
	desired_roll_degrees: float
) -> float:
	if (
		weapon_node == null
		or skeleton == null
		or optic_socket == null
		or muzzle_socket == null
	):
		return 0.0
	var direction := barrel_direction.normalized()
	if direction.length_squared() < 0.50:
		return 0.0
	var barrel_origin := (
		barrel_base_socket.global_position
		if barrel_base_socket != null
		else trigger_socket.global_position
	)
	# Optic-above-barrel is a model-independent weapon-up reference. Unlike a
	# mesh axis, it survives FBX axis conversion and the saved grip transform.
	var actual_up := optic_socket.global_position - barrel_origin
	actual_up -= direction * actual_up.dot(direction)
	var desired_up := skeleton.global_basis.y.normalized()
	desired_up -= direction * desired_up.dot(direction)
	if actual_up.length_squared() < 0.000001 or desired_up.length_squared() < 0.000001:
		return 0.0
	actual_up = actual_up.normalized()
	desired_up = desired_up.normalized()
	if not is_zero_approx(desired_roll_degrees):
		desired_up = Quaternion(
			direction,
			deg_to_rad(desired_roll_degrees)
		) * desired_up
	return atan2(
		direction.dot(actual_up.cross(desired_up)),
		actual_up.dot(desired_up)
	)


func _capture_gunsmith_ready_baseline(posture: StringName) -> void:
	if (
		weapon_node == null
		or skeleton == null
		or gun_placement_baseline_basis_by_posture.has(posture)
		or not _gun_placement_line_active_for(posture)
	):
		return
	gun_placement_baseline_basis_by_posture[posture] = (
		skeleton.global_basis.orthonormalized().inverse()
		* weapon_node.global_basis.orthonormalized()
	).orthonormalized()
	trigger_hand_grip_basis_by_posture[posture] = (
		weapon_node.global_basis.orthonormalized().inverse()
		* _bone_world_basis(&"mixamorig_RightHand")
	).orthonormalized()


func _gun_placement_origin(posture: StringName) -> Vector3:
	if not gun_placement_anchor_local_by_posture.has(posture):
		var operator_right := skeleton.global_basis.x.normalized()
		var operator_up := skeleton.global_basis.y.normalized()
		var operator_forward := skeleton.global_basis.z.normalized()
		var head_index := _resolve_bone_index(&"mixamorig_Head")
		var head_origin := (
			skeleton.global_transform * skeleton.get_bone_global_pose(head_index).origin
			if head_index >= 0
			else skeleton.global_position
		)
		var stance: Dictionary = gun_placement_line_by_posture.get(posture, {})
		var offset: Vector3 = stance.get("position_offset_meters", Vector3.ZERO)
		# Reconstruct the existing operator-local Gunsmith point exactly once.
		# Moving this complete point into chest space preserves the saved neutral
		# placement instead of reinterpreting its X/Y/Z values after every turn.
		var initial_origin := (
			head_origin
			+ operator_up * GUN_PLACEMENT_FACE_UP_M
			+ operator_forward * GUN_PLACEMENT_FACE_FORWARD_M
			+ operator_right * offset.x
			+ operator_up * offset.y
			+ operator_forward * offset.z
		)
		# Save the Gunsmith point relative to the actual Spine2 origin. Keep the
		# offset in stable skeleton axes: raw clip rotation must not roll the rifle
		# or swing a long chest-to-optic lever through a large vertical arc.
		var frame_pose_local := _gun_placement_frame_pose_local()
		gun_placement_anchor_local_by_posture[posture] = (
			skeleton.to_local(initial_origin) - frame_pose_local.origin
		)
		gun_placement_frame_origin_local_by_posture[posture] = skeleton.to_local(
			_gun_placement_carry_reference_world()
		)
		gun_placement_shoulder_delta_local_by_posture[posture] = (
			_gun_placement_shoulder_height_delta_local()
		)
	var current_frame_origin_local := skeleton.to_local(
		_gun_placement_carry_reference_world()
	)
	var captured_frame_origin_local: Vector3 = gun_placement_frame_origin_local_by_posture.get(
		posture,
		current_frame_origin_local
	)
	if not gun_placement_locomotion_active:
		# Learn the planted shoulder frame continuously so idle settling and a
		# deliberate reticle-driven torso turn do not become false gait travel.
		gun_placement_frame_origin_local_by_posture[posture] = current_frame_origin_local
		captured_frame_origin_local = current_frame_origin_local
		gun_placement_shoulder_delta_local_by_posture[posture] = (
			_gun_placement_shoulder_height_delta_local()
		)
	var frame_travel := current_frame_origin_local - captured_frame_origin_local
	var neutral_shoulder_delta := float(
		gun_placement_shoulder_delta_local_by_posture.get(posture, 0.0)
	)
	gun_placement_shoulder_alternation_m = (
		_gun_placement_shoulder_height_delta_local() - neutral_shoulder_delta
		if gun_placement_locomotion_active
		else 0.0
	)
	# The Gunsmith line supplies the neutral ready pose, but it must not pin the
	# rendered rifle in world space while the locomotion clip moves the chest.
	# Carry only a human-sized amount of that animated translation. The gameplay
	# muzzle, reticle ray, camera and shared/network aim remain outside this solver.
	var target_carry := Vector3(
		clampf(
			frame_travel.x
			+ gun_placement_shoulder_alternation_m
			* locomotion_weapon_shoulder_sway_gain,
			-locomotion_weapon_carry_horizontal_limit_m,
			locomotion_weapon_carry_horizontal_limit_m
		),
		clampf(
			frame_travel.y,
			-locomotion_weapon_carry_vertical_limit_m,
			locomotion_weapon_carry_vertical_limit_m
		),
		clampf(
			frame_travel.z,
			-locomotion_weapon_carry_horizontal_limit_m,
			locomotion_weapon_carry_horizontal_limit_m
		)
	)
	gun_placement_locomotion_carry_local = gun_placement_locomotion_carry_local.lerp(
		target_carry,
		1.0 - exp(-locomotion_weapon_carry_response * gun_placement_apply_delta)
	)
	var neutral_origin := skeleton.to_global(
		_gun_placement_frame_pose_local().origin
		+ Vector3(gun_placement_anchor_local_by_posture[posture])
		+ gun_placement_locomotion_carry_local
	)
	var chest_pivot := _gun_placement_torso_pivot_world()
	var torso_yaw := Quaternion(
		Vector3.UP,
		wrapf(gun_placement_relative_yaw_rad, -PI, PI)
	)
	return chest_pivot + torso_yaw * (neutral_origin - chest_pivot)


func _gun_placement_torso_pivot_world() -> Vector3:
	return _gun_placement_frame_world_transform().origin


func _gun_placement_frame_pose_local() -> Transform3D:
	if stable_chest_anchor_active:
		return Transform3D(
			Basis.IDENTITY,
			skeleton.to_local(stable_chest_anchor_world)
		)
	var frame_index := _resolve_bone_index(GUN_PLACEMENT_FRAME_BONE)
	if frame_index < 0:
		return Transform3D.IDENTITY
	return skeleton.get_bone_global_pose(frame_index)


func _gun_placement_frame_world_transform() -> Transform3D:
	if skeleton == null:
		return Transform3D.IDENTITY
	if stable_chest_anchor_active:
		return Transform3D(
			skeleton.global_basis.orthonormalized(),
			stable_chest_anchor_world
		)
	return skeleton.global_transform * _gun_placement_frame_pose_local()


func _stable_chest_anchor(
	body: Node3D,
	posture: StringName,
	movement_state: StringName
) -> Vector3:
	var local_anchor := STANDING_CHEST_ANCHOR_LOCAL
	if posture == &"CROUCHED":
		local_anchor = CROUCHED_CHEST_ANCHOR_LOCAL
	elif posture == &"PRONE":
		local_anchor = PRONE_CHEST_ANCHOR_LOCAL
	if movement_state == &"DIVING":
		var dive_phase := (
			clampf(float(body.call("get_action_phase")), 0.0, 1.0)
			if body.has_method("get_action_phase")
			else 0.0
		)
		local_anchor = STANDING_CHEST_ANCHOR_LOCAL.lerp(
			PRONE_CHEST_ANCHOR_LOCAL,
			smoothstep(0.0, 0.70, dive_phase)
		)
	elif movement_state == &"ROLLING":
		var roll_phase := (
			clampf(float(body.call("get_action_phase")), 0.0, 1.0)
			if body.has_method("get_action_phase")
			else 0.0
		)
		local_anchor = CROUCHED_CHEST_ANCHOR_LOCAL.lerp(
			Vector3(0.0, 0.66, 0.0),
			sin(roll_phase * PI)
		)
	return body.global_transform * local_anchor


func _gun_placement_carry_reference_world() -> Vector3:
	# The Spine2 joint is the rotation pivot, but its origin barely translates
	# when a gait expresses weight through chest/shoulder rotation. The shoulder
	# midpoint captures the visible upper-body travel that the rifle must share.
	var right_index := _resolve_bone_index(&"mixamorig_RightArm")
	var left_index := _resolve_bone_index(&"mixamorig_LeftArm")
	if right_index < 0 or left_index < 0:
		return _gun_placement_torso_pivot_world()
	var right_origin := skeleton.global_transform * skeleton.get_bone_global_pose(
		right_index
	).origin
	var left_origin := skeleton.global_transform * skeleton.get_bone_global_pose(
		left_index
	).origin
	return (right_origin + left_origin) * 0.5


func _gun_placement_shoulder_height_delta_local() -> float:
	var right_index := _resolve_bone_index(&"mixamorig_RightArm")
	var left_index := _resolve_bone_index(&"mixamorig_LeftArm")
	if right_index < 0 or left_index < 0:
		return 0.0
	return (
		skeleton.get_bone_global_pose(right_index).origin.y
		- skeleton.get_bone_global_pose(left_index).origin.y
	)


func _gun_placement_direction(posture: StringName, base_direction: Vector3) -> Vector3:
	var direction := base_direction.normalized()
	if direction.length_squared() < 0.50:
		direction = skeleton.global_basis.z.normalized()
	# Gameplay replaces the static Gunsmith direction with the live reticle ray.
	# The saved line supplies placement; shot and network aim remain exact.
	return direction


func _gun_placement_line_active_for(posture: StringName) -> bool:
	if (
		(not gun_placement_line_active and rail_to_blue_line_event_remaining <= 0.0)
		or optic_socket == null
	):
		return false
	var stance: Dictionary = gun_placement_line_by_posture.get(posture, {})
	return bool(stance.get("authored", false))


func _required_floor_lift(body: Node3D, point: Vector3, clearance: float) -> float:
	var measured := _floor_clearance(body, point)
	if measured == INF:
		return 0.0
	return maxf(clearance - measured, 0.0)


func _floor_clearance(body: Node3D, point: Vector3) -> float:
	if body == null or body.get_world_3d() == null:
		return INF
	var query := PhysicsRayQueryParameters3D.create(
		point + Vector3.UP * prone_floor_probe_up_m,
		point - Vector3.UP * prone_floor_probe_down_m
	)
	query.collide_with_areas = false
	if body is CollisionObject3D:
		query.exclude = [(body as CollisionObject3D).get_rid()]
	var hit := body.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return INF
	var normal := Vector3(hit.get("normal", Vector3.UP)).normalized()
	if normal.dot(Vector3.UP) < 0.45:
		return INF
	return (point - Vector3(hit.get("position", point))).dot(normal)


func get_debug_state() -> Dictionary:
	var pose_owners := WeaponOwnershipContract.resolve_pose_owners(
		last_movement_state,
		last_requested_action,
		current_weight,
		action_weapon_follow_active,
		last_reload_support_regrip,
		last_posture
	)
	return {
		"active": current_weight > 0.001,
		"weight": current_weight,
		"desired_weight": desired_weight,
		"target_reachable": target_reachable,
		"trigger_hand_error_m": trigger_hand_error_m,
		"support_hand_error_m": support_hand_error_m,
		"trigger_hand_position": (
			_right_hand_grip_world_transform().origin
			if right_hand_owns_ready_weapon
			else _bone_world_position(&"mixamorig_RightHand")
		),
		"support_hand_position": _bone_world_position(&"mixamorig_LeftHand"),
		"trigger_hand_target": trigger_hand_target.global_position,
		"support_hand_target": support_hand_target.global_position,
		"weapon_world_position": (
			weapon_node.global_position if weapon_node != null else Vector3.ZERO
		),
		"aim_direction": last_aim_direction,
		"aim_target": last_target_point,
		"posture": last_posture,
		"anatomical_adjustment_m": anatomical_adjustment_m,
		"torso_assist_requested": torso_assist_requested,
		"aim_yaw_demand_deg": aim_yaw_demand_deg,
		"aim_pitch_demand_deg": aim_pitch_demand_deg,
		"right_elbow_angle_deg": right_elbow_angle_deg,
		"left_elbow_angle_deg": left_elbow_angle_deg,
		"right_elbow_position": _bone_world_position(&"mixamorig_RightForeArm"),
		"left_elbow_position": _bone_world_position(&"mixamorig_LeftForeArm"),
		"head_position": _bone_world_position(&"mixamorig_Head"),
		"right_elbow_pole_position": right_elbow_pole.global_position,
		"left_elbow_pole_position": left_elbow_pole.global_position,
		"weapon_aim_error_deg": weapon_aim_error_deg,
		"wrist_correction_deg": wrist_correction_deg,
		"socket_contract_active": socket_contract_active,
		"adaptive_support_socket": adaptive_support_socket,
		"weapon_solver_owned": weapon_solver_owned,
		"weapon_parent_is_animation_mount": (
			weapon_node != null
			and weapon_animation_parent != null
			and weapon_node.get_parent() == weapon_animation_parent
		),
		"animation_mount_position_error_m": (
			weapon_node.transform.origin.distance_to(weapon_hand_mount_transform.origin)
			if weapon_node != null
			and weapon_animation_parent != null
			and weapon_node.get_parent() == weapon_animation_parent
			else -1.0
		),
		"weapon_owner": weapon_owner,
		"previous_weapon_owner": previous_weapon_owner,
		"weapon_owner_transition_count": weapon_owner_transition_count,
		"arm_owner": WeaponOwnershipContract.arm_owner(weapon_owner),
		"action_weapon_follow_active": action_weapon_follow_active,
		"action_weapon_chest_owned": action_weapon_chest_owned,
		"action_weapon_swing_deg": action_weapon_swing_deg,
		"action_trigger_contact_error_m": action_trigger_contact_error_m,
		"support_hand_mode": support_hand_mode,
		"pose_owners": pose_owners,
		"ownership_conflicts": WeaponOwnershipContract.ownership_conflicts(
			pose_owners,
			weapon_owner,
			support_hand_mode
		),
		"trigger_hand_grip_locked": trigger_hand_grip_locked,
		"trigger_hand_grip_rotation_error_deg": trigger_hand_grip_rotation_error_deg,
		"support_hand_grip_locked": support_hand_grip_locked,
		"support_hand_grip_rotation_error_deg": support_hand_grip_rotation_error_deg,
		"animation_frame_weapon_rotation_correction_deg": _animation_frame_weapon_rotation_degrees(),
		"right_hand_owns_ready_weapon": right_hand_owns_ready_weapon,
		"animation_drives_ready_hands": animation_drives_ready_hands,
		"support_socket_clamped": support_socket_clamped,
		"animation_carry_weight": animation_carry_weight,
		"animation_carry_limit_m": animation_carry_limit_m,
		"ownership_return_active": ownership_return_elapsed < ownership_return_seconds,
		"cover_pose_amount": cover_pose_amount,
		"cover_pose_name": cover_pose_name,
		"shot_blocked": shot_blocked,
		"prone_floor_lift_m": prone_floor_lift_m,
		"muzzle_floor_clearance_m": muzzle_floor_clearance_m,
		"prone_floor_contact_detected": prone_floor_contact_detected,
		"animation_frame_pose_active": not animation_frame_pose.is_empty(),
		"gun_placement_line_active": _gun_placement_line_active_for(last_posture),
		"gun_placement_line_authored": gun_placement_line_authored,
		"rail_to_blue_line_event_active": rail_to_blue_line_event_remaining > 0.0,
		"rail_to_blue_line_event_remaining": rail_to_blue_line_event_remaining,
		"gun_placement_frame_bone": GUN_PLACEMENT_FRAME_BONE,
		"gun_placement_anchor_space": &"STABLE_CHEST",
		"gun_placement_baseline_active": gun_placement_baseline_basis_by_posture.has(
			last_posture
		),
		"gun_placement_error_m": gun_placement_error_m,
		"gun_placement_roll_error_deg": gun_placement_roll_error_deg,
		"gun_placement_origin": last_gun_placement_origin,
		"gun_placement_direction": last_gun_placement_direction,
		"gun_placement_locomotion_carry_local": gun_placement_locomotion_carry_local,
		"gun_placement_locomotion_active": gun_placement_locomotion_active,
		"gun_placement_shoulder_alternation_m": gun_placement_shoulder_alternation_m,
		"obstruction_direction_hold_active": obstruction_direction_hold_active,
		"last_unobstructed_render_direction": last_unobstructed_render_direction,
	}


func _find_weapon_socket(socket_name: String) -> Marker3D:
	if weapon_node == null:
		return null
	return weapon_node.find_child(socket_name, true, false) as Marker3D


func _set_weapon_owner(next_owner: StringName) -> void:
	if next_owner == weapon_owner:
		return
	previous_weapon_owner = weapon_owner
	weapon_owner = next_owner
	weapon_owner_transition_count += 1


func _set_weapon_solver_owned(enabled: bool) -> void:
	if weapon_node == null or weapon_solver_owned == enabled:
		return
	var was_solver_owned := weapon_solver_owned
	var next_parent: Node = weapon_solver_anchor if enabled else weapon_animation_parent
	if next_parent == null or weapon_node.get_parent() == next_parent:
		weapon_solver_owned = enabled
		if enabled and not was_solver_owned:
			_finish_action_weapon_follow()
		return
	if enabled:
		# Relaxed carry writes a temporary hand-local transform after the animation
		# sample. Never promote that visual correction into the next ready pose.
		# Restore the exact Gunsmith mount before preserving world space under the
		# solver anchor.
		if weapon_animation_parent != null and weapon_node.get_parent() == weapon_animation_parent:
			weapon_node.transform = weapon_hand_mount_transform
		weapon_node.reparent(next_parent, true)
	else:
		# Leaving Ready Aim returns the rifle to the exact Gunsmith-authored
		# right-hand mount. Preserving the solver's last world transform here
		# converted the aim pose into a new hand-local offset, so the next run clip
		# moved its hand while the rifle appeared to remain behind.
		weapon_node.reparent(next_parent, false)
		weapon_node.transform = weapon_hand_mount_transform
	weapon_solver_owned = enabled
	if enabled:
		_finish_action_weapon_follow()
	else:
		ownership_return_elapsed = ownership_return_seconds


func _update_action_weapon_follow(delta: float, chest_owned: bool = false) -> void:
	if weapon_node == null or skeleton == null:
		return
	action_weapon_chest_owned = chest_owned
	var hand_index := int(bone_indices.get(&"mixamorig_RightHand", -1))
	if hand_index < 0:
		return
	var hand_world := _right_hand_grip_world_transform()
	if not action_weapon_follow_active:
		# Keep the weapon in the solver's world-space parent and drive the action
		# explicitly. Reparenting directly under BoneAttachment3D produced a one-frame
		# attachment update jump when the reload crossfade began.
		if weapon_solver_anchor != null and weapon_node.get_parent() != weapon_solver_anchor:
			weapon_node.reparent(weapon_solver_anchor, true)
		action_weapon_follow_start = weapon_node.global_transform
		action_weapon_chest_start_origin = _gun_placement_torso_pivot_world()
		var start_barrel := (
			(muzzle_socket.global_position - barrel_base_socket.global_position).normalized()
			if muzzle_socket != null and barrel_base_socket != null
			else -weapon_node.global_basis.z.normalized()
		)
		action_weapon_barrel_local = (
			action_weapon_follow_start.basis.orthonormalized().inverse()
			* start_barrel
		).normalized()
		var attached_start := weapon_node.global_transform
		if trigger_socket != null:
			attached_start.origin += hand_world.origin - trigger_socket.global_position
		action_weapon_hand_offset = hand_world.affine_inverse() * attached_start
		action_weapon_follow_elapsed = 0.0
		action_weapon_follow_active = true
		weapon_solver_owned = false
	var desired_transform: Transform3D
	if chest_owned:
		# Let the right hand steer barrel yaw and pitch, but remove twist around the
		# barrel. The arm can move through the dive without rolling the rifle sideways.
		var hand_desired := (
			hand_world
			* _animation_frame_weapon_correction_transform()
			* action_weapon_hand_offset
		)
		var start_basis := action_weapon_follow_start.basis.orthonormalized()
		var start_barrel := (start_basis * action_weapon_barrel_local).normalized()
		var desired_barrel := (
			hand_desired.basis.orthonormalized() * action_weapon_barrel_local
		).normalized()
		var swing := Quaternion.IDENTITY
		if start_barrel.length_squared() > 0.50 and desired_barrel.length_squared() > 0.50:
			swing = Quaternion(start_barrel, desired_barrel).normalized()
		action_weapon_swing_deg = rad_to_deg(start_barrel.angle_to(desired_barrel))
		desired_transform = action_weapon_follow_start
		desired_transform.basis = (
			Basis(swing) * start_basis
		).orthonormalized().scaled(action_weapon_follow_start.basis.get_scale())
		desired_transform.origin += (
			_gun_placement_torso_pivot_world() - action_weapon_chest_start_origin
		)
	else:
		action_weapon_swing_deg = 0.0
		desired_transform = (
			hand_world
			* _animation_frame_weapon_correction_transform()
			* action_weapon_hand_offset
		)
	var amount := clampf(
		action_weapon_follow_elapsed / maxf(action_weapon_follow_blend_seconds, 0.001),
		0.0,
		1.0
	)
	amount = amount * amount * (3.0 - 2.0 * amount)
	weapon_node.global_transform = action_weapon_follow_start.interpolate_with(
		desired_transform,
		amount
	)
	if trigger_socket != null:
		# Gunsmith authors the orange trigger point against the palm center, not
		# the wrist bone origin. Keep that exact contract while the reload hand
		# owns the rifle so the gameplay clip matches the editor preview. Blend the
		# positional correction with ownership so reload cannot snap the rifle on
		# its first frame. For mobility, preserve the chest-owned rifle basis but
		# keep exact trigger-to-palm translation; the dive wrist must never detach
		# merely because it travels farther than the previous correction limit.
		var hand_correction := hand_world.origin - trigger_socket.global_position
		weapon_node.global_position += hand_correction
		action_trigger_contact_error_m = trigger_socket.global_position.distance_to(
			hand_world.origin
		)
	action_weapon_follow_elapsed = minf(
		# Advance by at least one rendered 60 Hz frame. Headless/editor previews can
		# report a near-zero delta while still presenting frames, which previously
		# left reload ownership permanently at the beginning of its blend.
		action_weapon_follow_elapsed + maxf(delta, 1.0 / 60.0),
		action_weapon_follow_blend_seconds
	)


func _is_reload_action(action_name: StringName) -> bool:
	return "reload" in String(action_name).to_lower()


func _is_grenade_action(action_name: StringName) -> bool:
	return "grenade" in String(action_name).to_lower()


func _solve_reload_support_arm_guardrail(
	posture: StringName,
	world_aim_target: Vector3,
	body: Node3D,
	desired_hand_position: Vector3 = Vector3.INF
) -> void:
	if left_hand_ik != null and left_hand_ik.is_running():
		left_hand_ik.stop()
	var shoulder := _bone_world_position(&"mixamorig_LeftArm")
	var animated_hand := (
		_bone_world_position(&"mixamorig_LeftHand")
		if not desired_hand_position.is_finite()
		else desired_hand_position
	)
	var aim_direction := world_aim_target - shoulder
	if aim_direction.length_squared() < 0.01:
		aim_direction = -body.global_basis.z
	aim_direction = aim_direction.normalized()
	var aim_right := aim_direction.cross(Vector3.UP).normalized()
	if aim_right.length_squared() < 0.50:
		aim_right = body.global_basis.x.normalized()
	var saved_poles: Dictionary = elbow_pole_offsets_by_posture.get(posture, {})
	var left_saved: Vector3 = saved_poles.get("left", Vector3.ZERO)
	left_elbow_pole.global_position = (
		shoulder
		- aim_right * (elbow_flare + left_saved.x)
		+ aim_direction * (0.16 + left_saved.z)
		+ Vector3.UP * (elbow_height + left_saved.y)
	)
	# Preserve the imported reload hand path. The two-bone solve shortens only
	# unreachable or hyperextended reaches and selects the outward elbow plane.
	var safe_hand := _fit_human_reach(
		shoulder,
		animated_hand,
		aim_direction,
		_arm_length(&"left")
	)
	support_hand_target.global_position = safe_hand
	var previous_weight := current_weight
	current_weight = 1.0
	left_hand_ik.override_tip_basis = false
	_solve_socket_arm(
		left_hand_ik,
		support_hand_target,
		left_elbow_pole,
		&"mixamorig_LeftHand"
	)
	current_weight = previous_weight
	skeleton.force_update_all_bone_transforms()


func _right_hand_grip_world_transform() -> Transform3D:
	var hand_index := int(bone_indices.get(&"mixamorig_RightHand", -1))
	if skeleton == null or hand_index < 0:
		return Transform3D.IDENTITY
	var hand_pose := skeleton.get_bone_global_pose(hand_index)
	var hand_world := skeleton.global_transform * hand_pose
	return Transform3D(
		hand_world.basis.orthonormalized(),
		WeaponContactSolver.palm_contact_world(
			skeleton,
			hand_index,
			right_palm_anchor_local
		)
	)


func _calculate_palm_anchor(side: String, hand_index: int) -> Vector3:
	return WeaponContactSolver.calculate_palm_anchor(
		skeleton,
		side,
		hand_index
	)


func _finish_action_weapon_follow() -> void:
	if not action_weapon_follow_active:
		return
	action_weapon_follow_active = false
	action_weapon_chest_owned = false
	ownership_return_start = weapon_node.global_transform
	ownership_return_elapsed = 0.0


func _build_socket_ik() -> void:
	right_hand_ik = _create_socket_ik(
		"RuntimeRightHandIK",
		"mixamorig_RightArm",
		"mixamorig_RightHand"
	)
	left_hand_ik = _create_socket_ik(
		"RuntimeLeftHandIK",
		"mixamorig_LeftArm",
		"mixamorig_LeftHand"
	)


func _create_socket_ik(node_name: String, root_bone_name: String, tip_bone_name: String) -> SkeletonIK3D:
	var ik := SkeletonIK3D.new()
	ik.name = node_name
	ik.root_bone = root_bone_name
	ik.tip_bone = tip_bone_name
	ik.use_magnet = true
	ik.interpolation = 1.0
	ik.override_tip_basis = false
	ik.max_iterations = 40
	ik.min_distance = 0.00002
	skeleton.add_child(ik)
	ik.stop()
	return ik


func _solve_socket_arm(
	ik: SkeletonIK3D,
	target: Marker3D,
	pole: Marker3D,
	tip_bone_name: StringName
) -> void:
	if ik == null or target == null or pole == null:
		return
	ik.interpolation = current_weight
	ik.magnet = skeleton.global_transform.affine_inverse() * pole.global_position
	var palm_anchor := Vector3.ZERO
	var use_palm_contact := false
	if tip_bone_name == &"mixamorig_RightHand" and trigger_hand_grip_locked:
		palm_anchor = right_palm_anchor_local
		use_palm_contact = true
	elif tip_bone_name == &"mixamorig_LeftHand" and support_hand_grip_locked:
		palm_anchor = left_palm_anchor_local
		use_palm_contact = true
	var desired_contact := target.global_transform
	var wrist_target := (
		WeaponContactSolver.wrist_target_for_contact(
			skeleton,
			desired_contact,
			palm_anchor
		)
		if use_palm_contact
		else desired_contact
	)
	var internal_position := wrist_target.origin
	var hand_index := int(bone_indices.get(tip_bone_name, -1))
	for _correction in range(8):
		ik.target = Transform3D(wrist_target.basis, internal_position)
		ik.stop()
		ik.start(true)
		skeleton.force_update_all_bone_transforms()
		# Imported Mixamo bone scales can leave a small deterministic residual.
		# Offset only the internal IK target; the saved socket stays unchanged.
		var solved_position := (
			WeaponContactSolver.palm_contact_world(
				skeleton,
				hand_index,
				palm_anchor
			)
			if use_palm_contact
			else _bone_world_position(tip_bone_name)
		)
		var residual := desired_contact.origin - solved_position
		if residual.length() <= 0.001:
			break
		internal_position += residual


func _stop_socket_ik() -> void:
	if right_hand_ik != null and right_hand_ik.is_running():
		right_hand_ik.stop()
	if left_hand_ik != null and left_hand_ik.is_running():
		left_hand_ik.stop()
	_release_trigger_hand_grip_lock()
	_release_support_hand_grip_lock()


func _lock_trigger_hand_grip_to_weapon() -> void:
	if (
		right_hand_ik == null
		or trigger_hand_target == null
		or weapon_node == null
		or skeleton == null
		or not trigger_hand_grip_basis_by_posture.has(last_posture)
	):
		return
	var grip_basis: Basis = trigger_hand_grip_basis_by_posture[last_posture]
	grip_basis = (
		grip_basis * _animation_frame_hand_rotation_basis(&"right")
	).orthonormalized()
	trigger_hand_target.global_basis = (
		weapon_node.global_basis.orthonormalized() * grip_basis
	).orthonormalized()
	right_hand_ik.override_tip_basis = true
	trigger_hand_grip_locked = true


func _release_trigger_hand_grip_lock() -> void:
	trigger_hand_grip_locked = false
	trigger_hand_grip_rotation_error_deg = 0.0
	if right_hand_ik != null:
		right_hand_ik.override_tip_basis = false


func _lock_support_hand_grip_to_weapon() -> void:
	if (
		left_hand_ik == null
		or support_hand_target == null
		or support_socket == null
		or weapon_node == null
		or skeleton == null
	):
		return
	var weapon_basis := weapon_node.global_basis.orthonormalized()
	if (
		not support_hand_grip_basis_by_posture.has(last_posture)
		or not gun_placement_locomotion_active
	):
		support_hand_grip_basis_by_posture[last_posture] = (
			weapon_basis.inverse() * _bone_world_basis(&"mixamorig_LeftHand")
		).orthonormalized()
	var grip_basis: Basis = support_hand_grip_basis_by_posture.get(
		last_posture,
		Basis.IDENTITY
	)
	grip_basis = (
		grip_basis * _animation_frame_hand_rotation_basis(&"left")
	).orthonormalized()
	support_hand_target.global_basis = (weapon_basis * grip_basis).orthonormalized()
	left_hand_ik.override_tip_basis = true
	support_hand_grip_locked = true


func _release_support_hand_grip_lock() -> void:
	support_hand_grip_locked = false
	support_hand_grip_rotation_error_deg = 0.0
	if left_hand_ik != null:
		left_hand_ik.override_tip_basis = false


func _place_socketed_weapon(
	trigger_goal: Vector3,
	aim_direction: Vector3,
	body_forward: Vector3,
	delta: float
) -> void:
	if weapon_node == null or trigger_socket == null:
		return
	var render_direction := _render_weapon_direction(aim_direction, body_forward)
	var world_scale := weapon_node.global_basis.get_scale()
	var barrel_origin: Vector3 = (
		barrel_base_socket.global_position
		if barrel_base_socket != null
		else trigger_socket.global_position
	)
	var current_barrel := (muzzle_socket.global_position - barrel_origin).normalized()
	if current_barrel.length_squared() > 0.99:
		# Calibrated assets may use +X, -Z, or another import axis. Rotate the
		# authored barrel socket line itself instead of assuming a mesh axis.
		var aim_delta := Quaternion(current_barrel, render_direction.normalized())
		weapon_node.global_basis = (
			Basis(aim_delta) * weapon_node.global_basis.orthonormalized()
		).orthonormalized().scaled(world_scale)
	else:
		var stable_up := Vector3.UP
		if absf(render_direction.dot(stable_up)) > 0.96:
			stable_up = Vector3.FORWARD
		weapon_node.global_basis = Basis.looking_at(
			render_direction.normalized(),
			stable_up,
			false
		).scaled(world_scale)
	weapon_node.global_position += trigger_goal - trigger_socket.global_position
	_apply_ownership_return(weapon_node.global_transform, delta)


func _place_hand_owned_weapon(
	aim_direction: Vector3,
	body_forward: Vector3,
	delta: float
) -> void:
	if weapon_node == null or skeleton == null:
		return
	var hand_index := int(bone_indices.get(&"mixamorig_RightHand", -1))
	if hand_index < 0:
		return
	# Gunsmith sockets describe the visible palm contact, not the wrist-bone
	# origin.  Using the wrist here placed the rifle one palm-length away from
	# the hand (about seven centimetres on the production operator) even though
	# both systems believed they owned the same grip.
	var hand_world := _right_hand_grip_world_transform()
	_weapon_transform_on_trigger_hand(hand_world)
	var barrel_origin := (
		barrel_base_socket.global_position
		if barrel_base_socket != null
		else (trigger_socket.global_position if trigger_socket != null else weapon_node.global_position)
	)
	var current_barrel := (
		(muzzle_socket.global_position - barrel_origin).normalized()
		if muzzle_socket != null
		else Vector3.ZERO
	)
	var render_direction := _render_weapon_direction(aim_direction, body_forward)
	if current_barrel.length_squared() > 0.50 and render_direction.length_squared() > 0.50:
		var required_angle := current_barrel.angle_to(render_direction)
		wrist_correction_deg = rad_to_deg(required_angle)
		# Aim is a whole-arm presentation problem. Rotating only the wrist made the
		# hand twist while the elbow stayed frozen, then left a large residual when
		# the wrist safety clamp was reached. Keep the authored palm position, give
		# the two-bone chain the desired palm orientation, and let its elbow pole
		# distribute the correction through the shoulder and forearm.
		var world_delta := Quaternion(current_barrel, render_direction).normalized()
		trigger_hand_target.global_transform = Transform3D(
			(Basis(world_delta) * hand_world.basis.orthonormalized()).orthonormalized(),
			hand_world.origin
		)
		trigger_hand_grip_locked = true
		right_hand_ik.override_tip_basis = true
		_solve_socket_arm(
			right_hand_ik,
			trigger_hand_target,
			right_elbow_pole,
			&"mixamorig_RightHand"
		)
		skeleton.force_update_all_bone_transforms()
		hand_world = _right_hand_grip_world_transform()
	var target_transform := _weapon_transform_on_trigger_hand(hand_world)
	_apply_ownership_return(target_transform, delta)
	var solved_barrel_origin := (
		barrel_base_socket.global_position
		if barrel_base_socket != null
		else (trigger_socket.global_position if trigger_socket != null else weapon_node.global_position)
	)
	var solved_barrel := (
		(muzzle_socket.global_position - solved_barrel_origin).normalized()
		if muzzle_socket != null
		else Vector3.ZERO
	)
	weapon_aim_error_deg = (
		rad_to_deg(solved_barrel.angle_to(render_direction))
		if solved_barrel.length_squared() > 0.50
		else 0.0
	)


func _weapon_transform_on_trigger_hand(hand_world: Transform3D) -> Transform3D:
	var target_transform := hand_world * weapon_hand_mount_transform
	weapon_node.global_transform = target_transform
	if trigger_socket != null:
		weapon_node.global_position += hand_world.origin - trigger_socket.global_position
	return weapon_node.global_transform


func _stabilize_authored_two_hand_carry(
	trigger_hand_world: Vector3,
	support_hand_world: Vector3,
	fallback_direction: Vector3
) -> void:
	if weapon_node == null or trigger_socket == null:
		return
	TwoHandWeaponCarry.place(
		weapon_node,
		trigger_socket,
		support_socket,
		barrel_base_socket,
		muzzle_socket,
		optic_socket,
		trigger_hand_world,
		support_hand_world,
		Vector3.UP,
		fallback_direction
	)


func _render_weapon_direction(aim_direction: Vector3, body_forward: Vector3) -> Vector3:
	var stable_aim := aim_direction.normalized()
	if not obstruction_direction_hold_active and stable_aim.length_squared() > 0.50:
		last_unobstructed_render_direction = stable_aim
	elif obstruction_direction_hold_active:
		# A close wall can put the camera-selected surface behind the moved muzzle.
		# Re-solving muzzle-to-target from there flips the rifle by almost 180 degrees
		# and makes both arm IK chains chase opposite poses. Hold the last clear aim
		# direction while the visual weapon performs its bounded low-ready tuck.
		stable_aim = (
			last_unobstructed_render_direction
			if last_unobstructed_render_direction.length_squared() > 0.50
			else body_forward.normalized()
		)
	var blocked_pitch_deg := blocked_low_ready_pitch_deg
	if last_posture == &"CROUCHED":
		blocked_pitch_deg = blocked_crouch_pitch_deg
	elif last_posture == &"PRONE":
		blocked_pitch_deg = blocked_prone_pitch_deg
	# Lower the held clear direction around its own horizontal right axis. Using
	# body_forward here can introduce a large yaw reversal when the camera looks
	# across the body near a wall, which makes the rifle and both IK arms spin.
	var pitch_axis := stable_aim.cross(Vector3.UP).normalized()
	var low_ready_direction := (
		stable_aim.rotated(pitch_axis, -deg_to_rad(blocked_pitch_deg)).normalized()
		if pitch_axis.length_squared() > 0.50
		else stable_aim
	)
	if low_ready_direction.length_squared() < 0.50:
		low_ready_direction = stable_aim
	return stable_aim.slerp(low_ready_direction, cover_pose_amount).normalized()


func _apply_ownership_return(target_transform: Transform3D, delta: float) -> void:
	weapon_node.global_transform = target_transform
	if ownership_return_elapsed < ownership_return_seconds:
		var amount := clampf(
			ownership_return_elapsed / maxf(ownership_return_seconds, 0.001),
			0.0,
			1.0
		)
		amount = amount * amount * (3.0 - 2.0 * amount)
		weapon_node.global_transform = ownership_return_start.interpolate_with(
			target_transform,
			amount
		)
		ownership_return_elapsed = minf(
			ownership_return_elapsed + maxf(delta, 0.0),
			ownership_return_seconds
		)


func _update_socket_weapon_error() -> void:
	if muzzle_socket == null or (barrel_base_socket == null and trigger_socket == null):
		return
	var barrel_origin: Vector3 = (
		barrel_base_socket.global_position
		if barrel_base_socket != null
		else trigger_socket.global_position
	)
	var barrel_direction := (muzzle_socket.global_position - barrel_origin).normalized()
	if barrel_direction.length_squared() < 0.50:
		return
	weapon_aim_error_deg = rad_to_deg(barrel_direction.angle_to(last_aim_direction))
	wrist_correction_deg = 0.0


func _build_targets() -> void:
	trigger_hand_target = _marker("TriggerHandIKTarget")
	support_hand_target = _marker("SupportHandIKTarget")
	right_elbow_pole = _marker("RightElbowPole")
	left_elbow_pole = _marker("LeftElbowPole")
	aim_target_marker = _marker("WeaponAimTarget")


func _marker(node_name: String) -> Marker3D:
	var marker := Marker3D.new()
	marker.name = node_name
	add_child(marker)
	return marker


func _vector_from_data(raw: Variant) -> Vector3:
	if raw is Vector3:
		return raw
	if not raw is Dictionary:
		return Vector3.ZERO
	var data := raw as Dictionary
	return Vector3(
		float(data.get("x", 0.0)),
		float(data.get("y", 0.0)),
		float(data.get("z", 0.0))
	)


func _resolve_aim_direction(
	aim_yaw: float,
	aim_pitch: float,
	world_target: Vector3,
	origin: Vector3,
	body: Node3D
) -> Vector3:
	return ArmKinematics.resolve_aim_direction(
		aim_yaw, aim_pitch, world_target, origin, body
	)


func _arm_length(side: StringName) -> float:
	var names: Array = ARM_BONES[side]
	var root := _bone_world_position(StringName(names[0]))
	var middle := _bone_world_position(StringName(names[1]))
	var hand := _bone_world_position(StringName(names[2]))
	return maxf(root.distance_to(middle) + middle.distance_to(hand), 0.15)


func _fit_human_reach(
	origin: Vector3,
	target: Vector3,
	aim_direction: Vector3,
	reach: float
) -> Vector3:
	return ArmKinematics.fit_human_reach(
		origin,
		target,
		aim_direction,
		reach,
		minimum_forward_reach_ratio,
		minimum_elbow_angle_deg,
		maximum_elbow_angle_deg
	)


func _blend_rotated_basis(source: Basis, delta: Quaternion, weight: float) -> Basis:
	return ArmKinematics.blend_rotated_basis(source, delta, weight)


func _align_weapon_to_aim(aim_direction: Vector3) -> void:
	if weapon_node == null:
		weapon_aim_error_deg = 0.0
		wrist_correction_deg = 0.0
		return
	var hand_index := int(bone_indices.get(&"mixamorig_RightHand", -1))
	if hand_index < 0:
		return
	skeleton.force_update_all_bone_transforms()
	var hand_pose := skeleton.get_bone_global_pose(hand_index)
	# BoneAttachment3D follows the hand pose. Computing the barrel direction
	# from that invariant local relationship avoids a one-frame attachment lag.
	var weapon_forward_in_hand := (
		weapon_node.basis * weapon_forward_local
	).normalized()
	var current_local := (hand_pose.basis * weapon_forward_in_hand).normalized()
	var inverse_skeleton_basis := skeleton.global_basis.inverse()
	var aim_local := (inverse_skeleton_basis * aim_direction).normalized()
	if current_local.length_squared() < 0.50 or aim_local.length_squared() < 0.50:
		return
	var required_angle := current_local.angle_to(aim_local)
	wrist_correction_deg = rad_to_deg(required_angle)
	# The shoulder and elbow solve position first; the wrist then aligns the
	# attached rifle. Clamp only the visual wrist contribution. Any residual is
	# reported as torso-assist demand instead of allowing an impossible joint.
	var applied_angle := minf(required_angle, deg_to_rad(maximum_wrist_correction_deg))
	var correction_weight := (
		0.0 if required_angle <= 0.00001 else applied_angle / required_angle
	)
	var full_delta := Quaternion(current_local, aim_local)
	var delta := Quaternion.IDENTITY.slerp(full_delta, correction_weight)
	hand_pose.basis = _blend_rotated_basis(hand_pose.basis, delta, current_weight)
	skeleton.set_bone_global_pose_override(hand_index, hand_pose, 1.0, true)
	skeleton.force_update_all_bone_transforms()
	var solved_local := (hand_pose.basis * weapon_forward_in_hand).normalized()
	weapon_aim_error_deg = rad_to_deg(solved_local.angle_to(aim_local))
	if weapon_aim_error_deg > 1.0:
		torso_assist_requested = true


func _resolve_bone_index(canonical_name: StringName) -> int:
	if skeleton == null:
		return -1
	var candidates: Array = BONE_CANDIDATES.get(
		canonical_name,
		[canonical_name]
	)
	for candidate in candidates:
		var index := skeleton.find_bone(StringName(candidate))
		if index >= 0:
			return index
	return -1


func _bone_world_position(bone_name: StringName) -> Vector3:
	var index := int(bone_indices.get(bone_name, -1))
	if index < 0:
		return skeleton.global_position
	return skeleton.global_transform * skeleton.get_bone_global_pose(index).origin


func _bone_world_basis(bone_name: StringName) -> Basis:
	var index := int(bone_indices.get(bone_name, -1))
	if index < 0:
		return skeleton.global_basis.orthonormalized()
	return (
		skeleton.global_basis.orthonormalized()
		* skeleton.get_bone_global_pose(index).basis.orthonormalized()
	).orthonormalized()


func _update_errors() -> void:
	var trigger_error_target := trigger_hand_target.global_position
	var trigger_hand_position := _bone_world_position(&"mixamorig_RightHand")
	if right_hand_owns_ready_weapon and socket_contract_active and trigger_socket != null:
		trigger_error_target = trigger_socket.global_position
		# Gunsmith calibrates the orange trigger point against the palm center,
		# not the wrist-bone origin. Compare like with like or a correctly attached
		# rifle falsely reports the whole wrist-to-palm length as separation.
		trigger_hand_position = _right_hand_grip_world_transform().origin
	trigger_hand_error_m = trigger_hand_position.distance_to(
		trigger_error_target
	)
	var support_hand_position := _bone_world_position(&"mixamorig_LeftHand")
	if support_hand_grip_locked:
		support_hand_position = WeaponContactSolver.palm_contact_world(
			skeleton,
			int(bone_indices.get(&"mixamorig_LeftHand", -1)),
			left_palm_anchor_local
		)
	support_hand_error_m = support_hand_position.distance_to(
		support_hand_target.global_position
	)
	trigger_hand_grip_rotation_error_deg = (
		rad_to_deg(
			Quaternion(_bone_world_basis(&"mixamorig_RightHand")).angle_to(
				Quaternion(trigger_hand_target.global_basis.orthonormalized())
			)
		)
		if trigger_hand_grip_locked
		else 0.0
	)
	support_hand_grip_rotation_error_deg = (
		rad_to_deg(
			Quaternion(_bone_world_basis(&"mixamorig_LeftHand")).angle_to(
				Quaternion(support_hand_target.global_basis.orthonormalized())
			)
		)
		if support_hand_grip_locked
		else 0.0
	)
	right_elbow_angle_deg = _current_elbow_angle(&"right")
	left_elbow_angle_deg = _current_elbow_angle(&"left")


func _current_elbow_angle(side: StringName) -> float:
	var names: Array = ARM_BONES[side]
	var shoulder := _bone_world_position(StringName(names[0]))
	var elbow := _bone_world_position(StringName(names[1]))
	var hand := _bone_world_position(StringName(names[2]))
	var upper := (shoulder - elbow).normalized()
	var lower := (hand - elbow).normalized()
	if upper.length_squared() < 0.50 or lower.length_squared() < 0.50:
		return 0.0
	return rad_to_deg(acos(clampf(upper.dot(lower), -1.0, 1.0)))
