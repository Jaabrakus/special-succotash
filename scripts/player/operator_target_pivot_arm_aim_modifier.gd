@tool
class_name SocomOperatorTargetPivotArmAimModifier
extends SkeletonModifier3D

## Fire/combat-ready adapter for the purchased TargetPivot pattern.
##
## The ready/fire AnimationTree supplies the authored rifle stance. This modifier
## rotates the connected right-arm chain so the weapon-in-hand basis follows the
## accepted SOCOM aim point. It never translates a bone or moves the weapon node;
## the following hand-attachment modifier mounts the rifle to the resulting hand.

const REFERENCE_WEAPON_IN_RIGHT_HAND_BASIS := Basis(
	Vector3(-0.174087, 0.051405, 0.983388),
	Vector3(0.937065, 0.315582, 0.14939),
	Vector3(-0.30266, 0.947505, -0.103108)
)
const RIGHT_ARM_SHARE := 0.68

var pivot: Node3D
var right_arm_target: Node3D
var right_hand_target: Node3D
var right_arm_bone := -1
var right_hand_bone := -1
var aim_world_target := Vector3.ZERO
var process_count := 0
var last_aim_dot := -1.0
var last_arm_origin := Vector3.ZERO
var last_hand_origin := Vector3.ZERO


func bind(
	target_skeleton: Skeleton3D,
	target_pivot: Node3D,
	arm_target: Node3D,
	hand_target: Node3D
) -> void:
	pivot = target_pivot
	right_arm_target = arm_target
	right_hand_target = hand_target
	if target_skeleton == null:
		return
	right_arm_bone = target_skeleton.find_bone(&"mixamorig_RightArm")
	right_hand_bone = target_skeleton.find_bone(&"mixamorig_RightHand")


func set_aim_target(world_target: Vector3) -> void:
	aim_world_target = world_target


func _process_modification() -> void:
	process_count += 1
	var target_skeleton := get_skeleton()
	if (
		target_skeleton == null
		or right_arm_bone < 0
		or right_hand_bone < 0
	):
		return
	var hand_pose := target_skeleton.get_bone_global_pose(right_hand_bone)
	var hand_world := target_skeleton.global_transform * hand_pose
	var aim_direction := aim_world_target - hand_world.origin
	if aim_direction.length_squared() <= 0.000001:
		return

	# Derive the desired right-hand basis from the exact purchased Gun child basis.
	# The bone moves first; the weapon is attached only after this modifier runs.
	var desired_weapon_world := _basis_with_positive_z_forward(aim_direction.normalized())
	var current_hand_world_basis := hand_world.basis.orthonormalized()
	var current_weapon_world := (
		current_hand_world_basis * REFERENCE_WEAPON_IN_RIGHT_HAND_BASIS
	).orthonormalized()
	var full_aim_delta := (
		desired_weapon_world.get_rotation_quaternion()
		* current_weapon_world.get_rotation_quaternion().inverse()
	).normalized()

	# Share most of the rotation with the upper arm so the wrist never becomes the
	# sole aim hinge. Bone origins are deliberately untouched, preserving limb
	# lengths and the skinned arm connection supplied by the base animation.
	var arm_pose := target_skeleton.get_bone_global_pose(right_arm_bone)
	var arm_world := target_skeleton.global_transform * arm_pose
	var arm_delta := Quaternion().slerp(full_aim_delta, RIGHT_ARM_SHARE)
	var desired_arm_world_basis := Basis(
		(arm_delta * arm_world.basis.orthonormalized().get_rotation_quaternion()).normalized()
	).orthonormalized()
	var skeleton_basis_inverse := target_skeleton.global_basis.orthonormalized().inverse()
	target_skeleton.set_bone_global_pose(
		right_arm_bone,
		Transform3D(skeleton_basis_inverse * desired_arm_world_basis, arm_pose.origin)
	)
	target_skeleton.force_update_all_bone_transforms()

	# Finish the residual rotation at the hand. Its origin is sampled after the arm
	# update, so the forearm/hand joint remains connected instead of being pulled to
	# a free-floating gun transform.
	hand_pose = target_skeleton.get_bone_global_pose(right_hand_bone)
	hand_world = target_skeleton.global_transform * hand_pose
	current_hand_world_basis = hand_world.basis.orthonormalized()
	current_weapon_world = (
		current_hand_world_basis * REFERENCE_WEAPON_IN_RIGHT_HAND_BASIS
	).orthonormalized()
	var residual_delta := (
		desired_weapon_world.get_rotation_quaternion()
		* current_weapon_world.get_rotation_quaternion().inverse()
	).normalized()
	var desired_hand_world_basis := Basis(
		(residual_delta * current_hand_world_basis.get_rotation_quaternion()).normalized()
	).orthonormalized()
	target_skeleton.set_bone_global_pose(
		right_hand_bone,
		Transform3D(skeleton_basis_inverse * desired_hand_world_basis, hand_pose.origin)
	)
	target_skeleton.force_update_all_bone_transforms()

	var final_arm_world := (
		target_skeleton.global_transform
		* target_skeleton.get_bone_global_pose(right_arm_bone)
	)
	var final_hand_world := (
		target_skeleton.global_transform
		* target_skeleton.get_bone_global_pose(right_hand_bone)
	)
	last_arm_origin = final_arm_world.origin
	last_hand_origin = final_hand_world.origin
	last_aim_dot = (
		(final_hand_world.basis.orthonormalized() * REFERENCE_WEAPON_IN_RIGHT_HAND_BASIS)
		.z.normalized().dot(aim_direction.normalized())
	)
	# These are the runtime equivalents of the purchased CopyTransform targets.
	# Keeping them synchronized makes the editor visualizer show the actual arm and
	# hand solutions used by play, while TargetPivot remains the shared parent.
	if right_arm_target != null:
		right_arm_target.global_transform = Transform3D(
			final_arm_world.basis.orthonormalized(), final_arm_world.origin
		)
	if right_hand_target != null:
		right_hand_target.global_transform = Transform3D(
			final_hand_world.basis.orthonormalized(), final_hand_world.origin
		)


func _basis_with_positive_z_forward(forward: Vector3) -> Basis:
	var up_reference := Vector3.UP
	if absf(forward.dot(up_reference)) > 0.98:
		up_reference = Vector3.FORWARD
	var right := up_reference.cross(forward).normalized()
	var up := forward.cross(right).normalized()
	return Basis(right, up, forward).orthonormalized()
