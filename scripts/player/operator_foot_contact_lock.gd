class_name SocomOperatorFootContactLock
extends Node3D

## Visual-only direction-change foot contact. The CharacterBody remains fully
## authoritative; this bounded final IK pass prevents a planted foot from
## teleporting when movement intent changes faster than the authored blend.

const SocketIK := preload("res://scripts/player/operator_weapon_socket_ik.gd")

const LEFT_UPPER := &"mixamorig_LeftUpLeg"
const LEFT_KNEE := &"mixamorig_LeftLeg"
const LEFT_FOOT := &"mixamorig_LeftFoot"
const RIGHT_UPPER := &"mixamorig_RightUpLeg"
const RIGHT_KNEE := &"mixamorig_RightLeg"
const RIGHT_FOOT := &"mixamorig_RightFoot"

var skeleton: Skeleton3D
var authority_body: CharacterBody3D
var left_target: Marker3D
var right_target: Marker3D
var left_pole: Marker3D
var right_pole: Marker3D
var left_ik: SkeletonIK3D
var right_ik: SkeletonIK3D
var bone_indices: Dictionary = {}

var previous_direction := Vector2.ZERO
var previous_left_world := Transform3D.IDENTITY
var previous_right_world := Transform3D.IDENTITY
var sample_ready: bool = false
var locked_side: StringName = &""
var locked_world := Transform3D.IDENTITY
var lock_remaining: float = 0.0
var lock_weight: float = 0.0
var last_world_slip_cm: float = 0.0

var lock_seconds: float = 0.08
var release_seconds: float = 0.065
var direction_dot_threshold: float = 0.72


func bind(
	target_skeleton: Skeleton3D,
	target_body: CharacterBody3D,
	contract: SocomOperatorIKContract
) -> void:
	skeleton = target_skeleton
	authority_body = target_body
	if skeleton == null or contract == null:
		return
	for bone_name in [
		LEFT_UPPER, LEFT_KNEE, LEFT_FOOT,
		RIGHT_UPPER, RIGHT_KNEE, RIGHT_FOOT,
	]:
		bone_indices[bone_name] = skeleton.find_bone(bone_name)
	left_target = contract.left_foot_target
	right_target = contract.right_foot_target
	left_pole = _new_marker("LeftKneePole")
	right_pole = _new_marker("RightKneePole")
	left_ik = SocketIK.create(skeleton, "LeftFootContactIK", LEFT_UPPER, LEFT_FOOT)
	right_ik = SocketIK.create(skeleton, "RightFootContactIK", RIGHT_UPPER, RIGHT_FOOT)


func apply(
	direction: Vector2,
	speed_normalized: float,
	posture: StringName,
	movement_state: StringName,
	action: StringName,
	delta: float
) -> void:
	if not _ready_to_solve():
		return
	var left_raw := _bone_world_transform(LEFT_FOOT)
	var right_raw := _bone_world_transform(RIGHT_FOOT)
	var current_direction := (
		direction.normalized()
		if direction.length_squared() > 0.001
		else Vector2.ZERO
	)
	var ordinary_locomotion := (
		action == &""
		and posture in [&"STANDING", &"CROUCHED"]
		and movement_state in [&"STANDING", &"CROUCHED", &"LOCOMOTION"]
		and speed_normalized > 0.20
		and current_direction != Vector2.ZERO
	)
	if not ordinary_locomotion:
		_release_immediately()
		_store_sample(current_direction, left_raw, right_raw)
		return
	if (
		sample_ready
		and previous_direction != Vector2.ZERO
		and previous_direction.dot(current_direction) < direction_dot_threshold
	):
		_begin_lock()
	if locked_side != &"":
		_apply_active_lock(delta)
	_store_sample(current_direction, left_raw, right_raw)


func get_debug_state() -> Dictionary:
	return {
		"active": locked_side != &"",
		"side": locked_side,
		"weight": lock_weight,
		"remaining": lock_remaining,
		"world_slip_cm": last_world_slip_cm,
	}


func _begin_lock() -> void:
	locked_side = (
		&"LEFT"
		if previous_left_world.origin.y <= previous_right_world.origin.y
		else &"RIGHT"
	)
	locked_world = (
		previous_left_world if locked_side == &"LEFT" else previous_right_world
	)
	lock_remaining = lock_seconds
	lock_weight = 1.0
	last_world_slip_cm = 0.0


func _apply_active_lock(delta: float) -> void:
	var stable_delta := minf(maxf(delta, 0.0), 1.0 / 30.0)
	var target := left_target if locked_side == &"LEFT" else right_target
	var pole := left_pole if locked_side == &"LEFT" else right_pole
	var ik := left_ik if locked_side == &"LEFT" else right_ik
	var knee_name := LEFT_KNEE if locked_side == &"LEFT" else RIGHT_KNEE
	var upper_name := LEFT_UPPER if locked_side == &"LEFT" else RIGHT_UPPER
	var foot_name := LEFT_FOOT if locked_side == &"LEFT" else RIGHT_FOOT
	target.global_transform = locked_world
	pole.global_position = _bone_world_transform(knee_name).origin
	# The direction-pop limiter owns both upper legs between ordinary frames.
	# Release only the planted chain immediately before the final foot solve;
	# the limiter may reacquire it on the next authored sample. This avoids a
	# persistent override silently defeating IK without changing prone/action
	# behavior on the opposite path.
	var upper_index := int(bone_indices.get(upper_name, -1))
	if upper_index >= 0:
		var upper_pose := skeleton.get_bone_global_pose(upper_index)
		skeleton.set_bone_global_pose_override(
			upper_index,
			upper_pose,
			0.0,
			false
		)
		skeleton.force_update_all_bone_transforms()
	SocketIK.solve(
		skeleton,
		bone_indices,
		ik,
		target,
		pole,
		foot_name,
		Vector3.ZERO,
		false,
		lock_weight
	)
	skeleton.force_update_all_bone_transforms()
	var solved := _bone_world_transform(foot_name).origin
	last_world_slip_cm = Vector2(
		solved.x - locked_world.origin.x,
		solved.z - locked_world.origin.z
	).length() * 100.0
	if lock_remaining > 0.0:
		lock_remaining = maxf(lock_remaining - stable_delta, 0.0)
	else:
		lock_weight = move_toward(
			lock_weight,
			0.0,
			stable_delta / maxf(release_seconds, 0.001)
		)
	if lock_remaining <= 0.0 and lock_weight <= 0.001:
		_release_immediately()


func _release_immediately() -> void:
	SocketIK.stop(left_ik)
	SocketIK.stop(right_ik)
	locked_side = &""
	lock_remaining = 0.0
	lock_weight = 0.0


func _store_sample(
	direction: Vector2,
	left_world: Transform3D,
	right_world: Transform3D
) -> void:
	previous_direction = direction
	previous_left_world = left_world
	previous_right_world = right_world
	sample_ready = true


func _ready_to_solve() -> bool:
	return (
		skeleton != null
		and authority_body != null
		and left_target != null
		and right_target != null
		and left_ik != null
		and right_ik != null
		and int(bone_indices.get(LEFT_FOOT, -1)) >= 0
		and int(bone_indices.get(RIGHT_FOOT, -1)) >= 0
	)


func _bone_world_transform(bone_name: StringName) -> Transform3D:
	var bone_index := int(bone_indices.get(bone_name, -1))
	if bone_index < 0:
		return Transform3D.IDENTITY
	return skeleton.global_transform * skeleton.get_bone_global_pose(bone_index)


func _new_marker(marker_name: String) -> Marker3D:
	var marker := Marker3D.new()
	marker.name = marker_name
	add_child(marker)
	return marker
