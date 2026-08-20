class_name UniversalCharacterRigSolver
extends Node

@export var skeleton_path: NodePath
@export var bone_map: RigBoneMap = RigBoneMap.new()
@export var weights: CharacterRigWeights = CharacterRigWeights.new()

var skeleton: Skeleton3D
var targets := CharacterRigTargets.new()

var enabled: bool = true

var _bone_indices: Dictionary = {}
var _base_pose_rotations: Dictionary = {}

var right_arm_solver := ArmRigSolver.new()
var left_arm_solver := ArmRigSolver.new()


func _ready() -> void:
	if bone_map == null:
		bone_map = RigBoneMap.new()
	if weights == null:
		weights = CharacterRigWeights.new()

	skeleton = get_node_or_null(skeleton_path) as Skeleton3D
	if skeleton == null:
		# Search parent or children
		skeleton = _find_skeleton(get_parent()) if get_parent() else null

	if skeleton != null:
		_cache_bones()
		_setup_arm_solvers()


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for child in node.get_children():
		var found := _find_skeleton(child)
		if found:
			return found
	return null


func _cache_bones() -> void:
	_bone_indices.clear()

	var names := {
		"hips": bone_map.hips,
		"spine": bone_map.spine,
		"spine1": bone_map.spine1,
		"spine2": bone_map.spine2,
		"neck": bone_map.neck,
		"head": bone_map.head,

		"right_shoulder": bone_map.right_shoulder,
		"right_arm": bone_map.right_arm,
		"right_forearm": bone_map.right_forearm,
		"right_hand": bone_map.right_hand,

		"left_shoulder": bone_map.left_shoulder,
		"left_arm": bone_map.left_arm,
		"left_forearm": bone_map.left_forearm,
		"left_hand": bone_map.left_hand,

		"right_up_leg": bone_map.right_up_leg,
		"right_leg": bone_map.right_leg,
		"right_foot": bone_map.right_foot,

		"left_up_leg": bone_map.left_up_leg,
		"left_leg": bone_map.left_leg,
		"left_foot": bone_map.left_foot
	}

	for key in names:
		var idx := skeleton.find_bone(names[key])
		_bone_indices[key] = idx


func _setup_arm_solvers() -> void:
	if not right_arm_solver.get_parent():
		add_child(right_arm_solver)
	if not left_arm_solver.get_parent():
		add_child(left_arm_solver)
	right_arm_solver.setup(
		skeleton,
		_bone_indices.get("right_arm", -1),
		_bone_indices.get("right_forearm", -1),
		_bone_indices.get("right_hand", -1)
	)
	left_arm_solver.setup(
		skeleton,
		_bone_indices.get("left_arm", -1),
		_bone_indices.get("left_forearm", -1),
		_bone_indices.get("left_hand", -1)
	)


func capture_animation_pose() -> void:
	_base_pose_rotations.clear()
	if skeleton == null:
		return
	for i in range(skeleton.get_bone_count()):
		_base_pose_rotations[i] = skeleton.get_bone_pose_rotation(i)


func solve(delta: float) -> void:
	if not enabled or skeleton == null:
		return

	capture_animation_pose()

	_solve_pelvis(delta)
	_solve_feet(delta)
	_solve_spine(delta)
	_solve_clavicles(delta)
	_solve_right_arm(delta)
	_solve_left_arm(delta)
	_solve_head_and_look(delta)
	_apply_joint_limits()
	_relax_pose()


func _solve_pelvis(_delta: float) -> void:
	if not targets.pelvis.enabled:
		return
	var hips_idx: int = _bone_indices.get("hips", -1)
	if hips_idx < 0:
		return
	if targets.pelvis.position_only:
		var current_pos := skeleton.get_bone_pose_position(hips_idx)
		var desired_local := skeleton.global_transform.affine_inverse() * targets.pelvis.transform.origin
		skeleton.set_bone_pose_position(hips_idx, current_pos.lerp(desired_local, weights.pelvis_weight * targets.pelvis.weight))


func _solve_feet(_delta: float) -> void:
	# Foot IK channels
	pass


func _solve_spine(_delta: float) -> void:
	if not targets.weapon_aim_enabled:
		return
	var chest_idx: int = _bone_indices.get("spine2", -1)
	if chest_idx < 0:
		return

	var chest_world := _bone_world_transform(chest_idx)
	var aim_dir := (targets.weapon_aim_direction_world).normalized()
	if aim_dir.length_squared() < 0.0001:
		return

	var current_forward := (-chest_world.basis.z).normalized()
	var rot_quat := Quaternion(current_forward, aim_dir)
	var desired_basis := Basis(rot_quat) * chest_world.basis
	var blended_basis := chest_world.basis.slerp(desired_basis, weights.spine_weight)
	_set_bone_world_basis(chest_idx, blended_basis)


func _solve_clavicles(_delta: float) -> void:
	if targets.right_hand.enabled:
		_solve_right_reach_compensation()
	if targets.left_hand.enabled:
		_solve_left_reach_compensation()


func _solve_right_reach_compensation() -> void:
	var shoulder_idx: int = _bone_indices.get("right_shoulder", -1)
	if shoulder_idx < 0:
		return
	var shoulder_world := _bone_world_transform(shoulder_idx)
	var target_world := targets.right_hand.transform.origin
	var arm_len := _estimate_arm_length("right")
	var reach_factor := _calculate_reach_factor(shoulder_world.origin, target_world, arm_len)
	if reach_factor > 0.001:
		_apply_clavicle_compensation(shoulder_idx, target_world, reach_factor * weights.clavicle_weight)


func _solve_left_reach_compensation() -> void:
	var shoulder_idx: int = _bone_indices.get("left_shoulder", -1)
	if shoulder_idx < 0:
		return
	var shoulder_world := _bone_world_transform(shoulder_idx)
	var target_world := targets.left_hand.transform.origin
	var arm_len := _estimate_arm_length("left")
	var reach_factor := _calculate_reach_factor(shoulder_world.origin, target_world, arm_len)
	if reach_factor > 0.001:
		_apply_clavicle_compensation(shoulder_idx, target_world, reach_factor * weights.clavicle_weight)


func _calculate_reach_factor(shoulder_world: Vector3, target_world: Vector3, arm_length: float) -> float:
	if arm_length <= 0.001:
		return 0.0
	var distance := shoulder_world.distance_to(target_world)
	var normalized := distance / arm_length
	return clampf(inverse_lerp(0.75, 1.10, normalized), 0.0, 1.0)


func _estimate_arm_length(side: String) -> float:
	var arm_idx: int = _bone_indices.get(side + "_arm", -1)
	var fore_idx: int = _bone_indices.get(side + "_forearm", -1)
	var hand_idx: int = _bone_indices.get(side + "_hand", -1)
	if arm_idx < 0 or fore_idx < 0 or hand_idx < 0:
		return 0.55
	var p1 := skeleton.get_bone_global_pose(arm_idx).origin
	var p2 := skeleton.get_bone_global_pose(fore_idx).origin
	var p3 := skeleton.get_bone_global_pose(hand_idx).origin
	return p1.distance_to(p2) + p2.distance_to(p3)


func _apply_clavicle_compensation(bone_idx: int, target_world: Vector3, strength: float) -> void:
	var bone_world := _bone_world_transform(bone_idx)
	var to_target := (target_world - bone_world.origin).normalized()
	var forward := (-bone_world.basis.z).normalized()
	var rot_quat := Quaternion(forward, to_target)
	var target_basis := Basis(rot_quat) * bone_world.basis
	_set_bone_world_basis(bone_idx, bone_world.basis.slerp(target_basis, clampf(strength, 0.0, 0.45)))


func _solve_right_arm(_delta: float) -> void:
	if not targets.right_hand.enabled:
		right_arm_solver.enabled = false
		return
	right_arm_solver.enabled = true
	right_arm_solver.target_world = targets.right_hand.transform
	if targets.right_elbow.enabled:
		right_arm_solver.has_pole = true
		right_arm_solver.pole_world = targets.right_elbow.transform.origin
	else:
		right_arm_solver.has_pole = false
	right_arm_solver.weight = targets.right_hand.weight * weights.right_arm_weight
	right_arm_solver.solve()


func _solve_left_arm(_delta: float) -> void:
	if not targets.left_hand.enabled:
		left_arm_solver.enabled = false
		return
	left_arm_solver.enabled = true
	left_arm_solver.target_world = targets.left_hand.transform
	if targets.left_elbow.enabled:
		left_arm_solver.has_pole = true
		left_arm_solver.pole_world = targets.left_elbow.transform.origin
	else:
		left_arm_solver.has_pole = false
	left_arm_solver.weight = targets.left_hand.weight * weights.left_arm_weight
	left_arm_solver.solve()


func _solve_head_and_look(_delta: float) -> void:
	if not targets.look_enabled:
		return
	var head_idx: int = _bone_indices.get("head", -1)
	if head_idx < 0:
		return
	var head_world := _bone_world_transform(head_idx)
	var to_target := (targets.look_target_world - head_world.origin).normalized()
	if to_target.length_squared() < 0.001:
		return
	var forward := (-head_world.basis.z).normalized()
	var rot_quat := Quaternion(forward, to_target)
	var desired_basis := Basis(rot_quat) * head_world.basis
	_set_bone_world_basis(head_idx, head_world.basis.slerp(desired_basis, weights.head_weight))


func _apply_joint_limits() -> void:
	var head_idx: int = _bone_indices.get("head", -1)
	if head_idx >= 0:
		_clamp_bone_rotation(head_idx, Vector3(-weights.max_head_pitch_deg, -weights.max_head_yaw_deg, -20.0), Vector3(weights.max_head_pitch_deg, weights.max_head_yaw_deg, 20.0))


func _clamp_bone_rotation(bone_idx: int, min_deg: Vector3, max_deg: Vector3) -> void:
	var rot := skeleton.get_bone_pose_rotation(bone_idx).get_euler()
	var deg := Vector3(rad_to_deg(rot.x), rad_to_deg(rot.y), rad_to_deg(rot.z))
	deg.x = clampf(deg.x, min_deg.x, max_deg.x)
	deg.y = clampf(deg.y, min_deg.y, max_deg.y)
	deg.z = clampf(deg.z, min_deg.z, max_deg.z)
	skeleton.set_bone_pose_rotation(bone_idx, Quaternion.from_euler(Vector3(deg_to_rad(deg.x), deg_to_rad(deg.y), deg_to_rad(deg.z))))


func _relax_pose() -> void:
	for _i in range(weights.relaxation_iterations):
		_relax_bone_toward_animation(_bone_indices.get("right_shoulder", -1), 0.12)
		_relax_bone_toward_animation(_bone_indices.get("left_shoulder", -1), 0.12)
		_relax_bone_toward_animation(_bone_indices.get("neck", -1), 0.10)


func _relax_bone_toward_animation(bone_idx: int, amount: float) -> void:
	if bone_idx < 0 or not _base_pose_rotations.has(bone_idx):
		return
	var current := skeleton.get_bone_pose_rotation(bone_idx)
	var base: Quaternion = _base_pose_rotations[bone_idx]
	skeleton.set_bone_pose_rotation(bone_idx, current.slerp(base, amount))


func _bone_world_transform(bone_idx: int) -> Transform3D:
	return skeleton.global_transform * skeleton.get_bone_global_pose(bone_idx)


func _set_bone_world_basis(bone_idx: int, world_basis: Basis) -> void:
	var current_world := _bone_world_transform(bone_idx)
	var desired_world := Transform3D(world_basis, current_world.origin)
	var desired_skeleton_space := skeleton.global_transform.affine_inverse() * desired_world

	var parent_idx := skeleton.get_bone_parent(bone_idx)
	if parent_idx < 0:
		skeleton.set_bone_pose_rotation(bone_idx, desired_skeleton_space.basis.get_rotation_quaternion())
		return

	var parent_global := skeleton.get_bone_global_pose(parent_idx)
	var local_pose := parent_global.affine_inverse() * desired_skeleton_space
	skeleton.set_bone_pose_rotation(bone_idx, local_pose.basis.get_rotation_quaternion())
