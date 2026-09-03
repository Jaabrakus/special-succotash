class_name SocomOperatorNativeWeaponSocketIK
extends RefCounted

## Arm-only facade for the Godot 4.6+ modifier stack. Foot grounding continues
## using the established SkeletonIK3D helper and is deliberately unaffected.

const NativeTwoBoneIK := preload(
	"res://scripts/player/operator_native_two_bone_ik.gd"
)
const WeaponContactSolver := preload(
	"res://scripts/player/operator_weapon_contact_solver.gd"
)


static func create(
	skeleton: Skeleton3D,
	node_name: String,
	root_bone_index: int,
	middle_bone_index: int,
	tip_bone_index: int
):
	var ik = NativeTwoBoneIK.new()
	ik.bind(
		skeleton,
		node_name,
		root_bone_index,
		middle_bone_index,
		tip_bone_index
	)
	return ik


static func solve(
	skeleton: Skeleton3D,
	bone_indices: Dictionary,
	ik,
	target: Marker3D,
	pole: Marker3D,
	tip_bone_name: StringName,
	palm_anchor: Vector3,
	use_palm_contact: bool,
	weight: float
) -> void:
	if ik == null or target == null or pole == null:
		return
	ik.interpolation = weight
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
	wrist_target = _clamp_wrist_target_to_reach(skeleton, ik, wrist_target)
	# One bounded residual correction absorbs imported palm-anchor scale without
	# moving the authored weapon socket. The modifier itself runs after animation.
	if ik.is_running():
		var hand_index := int(bone_indices.get(tip_bone_name, -1))
		var solved_position := (
			WeaponContactSolver.palm_contact_world(
				skeleton,
				hand_index,
				palm_anchor
			)
			if use_palm_contact
			else (skeleton.global_transform * skeleton.get_bone_global_pose(hand_index)).origin
		)
		var residual := desired_contact.origin - solved_position
		if residual.length() <= 0.08:
			wrist_target.origin += residual
	ik.set_world_target(wrist_target, pole.global_position)
	ik.start(true)
	skeleton.force_update_all_bone_transforms()


static func _clamp_wrist_target_to_reach(
	skeleton: Skeleton3D,
	ik,
	wrist_target: Transform3D
) -> Transform3D:
	if skeleton == null or ik == null or ik.two_bone == null:
		return wrist_target
	var root_index: int = int(ik.two_bone.get_root_bone(0))
	var middle_index: int = int(ik.two_bone.get_middle_bone(0))
	var end_index: int = int(ik.two_bone.get_end_bone(0))
	if root_index < 0 or middle_index < 0 or end_index < 0:
		return wrist_target
	var root_world := (
		skeleton.global_transform * skeleton.get_bone_global_pose(root_index)
	).origin
	var middle_world := (
		skeleton.global_transform * skeleton.get_bone_global_pose(middle_index)
	).origin
	var end_world := (
		skeleton.global_transform * skeleton.get_bone_global_pose(end_index)
	).origin
	var maximum_reach := (
		root_world.distance_to(middle_world)
		+ middle_world.distance_to(end_world)
	) * 0.98
	var requested := wrist_target.origin - root_world
	if maximum_reach > 0.0 and requested.length() > maximum_reach:
		wrist_target.origin = root_world + requested.normalized() * maximum_reach
	return wrist_target


static func stop(ik) -> void:
	if ik != null:
		ik.stop()
