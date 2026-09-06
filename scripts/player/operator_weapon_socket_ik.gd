class_name SocomOperatorWeaponSocketIK
extends RefCounted

## Shared two-bone socket solve. It owns IK mechanics only. The pose
## coordinator still decides which system owns each hand and the rifle.

const WeaponContactSolver := preload(
	"res://scripts/player/operator_weapon_contact_solver.gd"
)


static func create(
	skeleton: Skeleton3D,
	node_name: String,
	root_bone_name: String,
	tip_bone_name: String
) -> SkeletonIK3D:
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


static func solve(
	skeleton: Skeleton3D,
	bone_indices: Dictionary,
	ik: SkeletonIK3D,
	target: Marker3D,
	pole: Marker3D,
	tip_bone_name: StringName,
	palm_anchor: Vector3,
	use_palm_contact: bool,
	weight: float,
	correction_passes: int = 8
) -> void:
	if ik == null or target == null or pole == null:
		return
	ik.interpolation = weight
	ik.magnet = skeleton.global_transform.affine_inverse() * pole.global_position
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
	for _correction in range(clampi(correction_passes, 1, 8)):
		ik.target = Transform3D(wrist_target.basis, internal_position)
		ik.stop()
		ik.start(true)
		skeleton.force_update_all_bone_transforms()
		# Imported bone scales can leave a deterministic residual. Correct only
		# the private IK target. Never mutate the authored weapon socket.
		var solved_position := (
			WeaponContactSolver.palm_contact_world(
				skeleton,
				hand_index,
				palm_anchor
			)
			if use_palm_contact
			else _bone_world_position(skeleton, bone_indices, tip_bone_name)
		)
		var residual := desired_contact.origin - solved_position
		if residual.length() <= 0.001:
			break
		internal_position += residual


static func stop(ik: SkeletonIK3D) -> void:
	if ik != null and ik.is_running():
		ik.stop()


static func _bone_world_position(
	skeleton: Skeleton3D,
	bone_indices: Dictionary,
	bone_name: StringName
) -> Vector3:
	var index := int(bone_indices.get(bone_name, -1))
	if index < 0:
		return skeleton.global_position
	return skeleton.global_transform * skeleton.get_bone_global_pose(index).origin
