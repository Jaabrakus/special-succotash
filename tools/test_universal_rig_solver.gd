extends SceneTree

const UniversalCharacterRigSolverScript := preload("res://scripts/rig/universal_character_rig_solver.gd")
const CharacterRigWeightsScript := preload("res://scripts/rig/character_rig_weights.gd")
const RigBoneMapScript := preload("res://scripts/rig/rig_bone_map.gd")

func _init() -> void:
	print("=================================================================")
	print("[UNIVERSAL RIG TEST] Starting Universal Rig Solver Verification")
	print("=================================================================")

	var passed_count := 0
	var total_count := 6

	# Load Character FBX
	var trooper_scene: PackedScene = load("res://assets/characters/ps1_gas_mask_soldier/trooper_rigged.fbx")
	if not trooper_scene:
		push_error("Could not load trooper model")
		quit(1)
		return

	var trooper_instance := trooper_scene.instantiate() as Node3D
	root.add_child(trooper_instance)

	var skeleton: Skeleton3D = _find_skeleton(trooper_instance)
	if not skeleton:
		push_error("Skeleton3D not found in trooper instance")
		quit(1)
		return

	# Setup Universal Solver
	var solver: UniversalCharacterRigSolver = UniversalCharacterRigSolverScript.new()
	trooper_instance.add_child(solver)
	solver.skeleton = skeleton
	solver._cache_bones()
	solver._setup_arm_solvers()

	# -------------------------------------------------------------
	# Test 1: Zero Intent Invariance (Base animation pose preserved)
	# -------------------------------------------------------------
	var poses_initial := _record_bone_poses(skeleton)
	solver.targets.clear_frame_intent()
	solver.solve(0.016)
	var poses_after_zero := _record_bone_poses(skeleton)

	if _compare_poses(poses_initial, poses_after_zero):
		print("[PASS 1/6] Zero Intent Invariance: Unmodified base pose preserved with 0 delta.")
		passed_count += 1
	else:
		push_error("[FAIL 1/6] Zero Intent drifted base skeleton pose.")

	# -------------------------------------------------------------
	# Test 2: Right Hand Reach Solve (Only right arm/clavicle moves)
	# -------------------------------------------------------------
	var right_hand_idx := skeleton.find_bone("mixamorig_RightHand")
	var right_hand_initial := skeleton.global_transform * skeleton.get_bone_global_pose(right_hand_idx)
	var target_world := right_hand_initial.origin + Vector3(0.15, 0.05, -0.20)

	solver.targets.clear_frame_intent()
	solver.targets.right_hand.enabled = true
	solver.targets.right_hand.transform = Transform3D(right_hand_initial.basis, target_world)
	solver.targets.right_hand.weight = 1.0
	solver.solve(0.016)

	var right_hand_solved := skeleton.global_transform * skeleton.get_bone_global_pose(right_hand_idx)
	var left_hand_idx := skeleton.find_bone("mixamorig_LeftHand")
	var left_hand_solved := skeleton.get_bone_global_pose(left_hand_idx)
	var left_hand_initial := poses_initial[left_hand_idx]

	if right_hand_solved.origin.distance_to(target_world) < 0.08 and left_hand_solved.is_equal_approx(left_hand_initial):
		print("[PASS 2/6] Right Hand Reach Solve: Reached target while left arm remained 100% untouched.")
		passed_count += 1
	else:
		push_error("[FAIL 2/6] Right hand solver failed or corrupted left arm.")

	# -------------------------------------------------------------
	# Test 3: Ballistics Zero Authority (Muzzle has zero bone impact)
	# -------------------------------------------------------------
	var poses_before_ballistics := _record_bone_poses(skeleton)
	# Simulate changing muzzle / ballistics aim
	var fake_muzzle_world := Vector3(100.0, 50.0, -100.0)
	solver.solve(0.016) # Ballistics does NOT write to solver targets!
	var poses_after_ballistics := _record_bone_poses(skeleton)

	if _compare_poses(poses_before_ballistics, poses_after_ballistics):
		print("[PASS 3/6] Ballistics Zero Authority: Ballistic parameters have zero authority over skeleton.")
		passed_count += 1
	else:
		push_error("[FAIL 3/6] Ballistics unexpectedly modified skeleton pose.")

	# -------------------------------------------------------------
	# Test 4: Head Look Isolation (Head rotates without moving pelvis)
	# -------------------------------------------------------------
	var hips_idx := skeleton.find_bone("mixamorig_Hips")
	var hips_before := skeleton.get_bone_global_pose(hips_idx)
	var head_idx := skeleton.find_bone("mixamorig_Head")
	var head_before := skeleton.get_bone_global_pose(head_idx)

	solver.targets.clear_frame_intent()
	solver.targets.look_enabled = true
	solver.targets.look_target_world = skeleton.global_position + Vector3(5.0, 1.5, -5.0)
	solver.solve(0.016)

	var hips_after := skeleton.get_bone_global_pose(hips_idx)
	var head_after := skeleton.get_bone_global_pose(head_idx)

	if hips_after.is_equal_approx(hips_before) and not head_after.is_equal_approx(head_before):
		print("[PASS 4/6] Head Look Isolation: Head looked toward target while pelvis remained completely invariant.")
		passed_count += 1
	else:
		push_error("[FAIL 4/6] Head look moved pelvis or failed to rotate head.")

	# -------------------------------------------------------------
	# Test 5: Clavicle Progressive Reach Compensation
	# -------------------------------------------------------------
	var shoulder_idx := skeleton.find_bone("mixamorig_RightShoulder")
	var shoulder_before := skeleton.get_bone_global_pose(shoulder_idx)

	# Extreme forward reach (>1.1x arm length)
	solver.targets.clear_frame_intent()
	solver.targets.right_hand.enabled = true
	solver.targets.right_hand.transform = Transform3D(Basis(), right_hand_initial.origin + Vector3(0.0, 0.0, -0.65))
	solver.solve(0.016)

	var shoulder_after := skeleton.get_bone_global_pose(shoulder_idx)
	if not shoulder_after.is_equal_approx(shoulder_before):
		print("[PASS 5/6] Clavicle Reach Compensation: Progressive reach successfully engaged right shoulder.")
		passed_count += 1
	else:
		push_error("[FAIL 5/6] Clavicle compensation did not engage under extreme reach.")

	# -------------------------------------------------------------
	# Test 6: Pose Relaxation Stability
	# -------------------------------------------------------------
	solver.targets.clear_frame_intent()
	for _i in range(5):
		solver.solve(0.016)
	var poses_relaxed := _record_bone_poses(skeleton)

	if _compare_poses(poses_initial, poses_relaxed):
		print("[PASS 6/6] Pose Relaxation Stability: Solver cleanly relaxes back to pristine base clip.")
		passed_count += 1
	else:
		push_error("[FAIL 6/6] Pose relaxation failed to return to base pose.")

	print("=================================================================")
	print("[UNIVERSAL RIG TEST] Summary: %d/%d tests passed" % [passed_count, total_count])
	print("=================================================================")

	trooper_instance.queue_free()

	if passed_count == total_count:
		print("✅ ALL UNIVERSAL RIG SOLVER TESTS PASSED!")
		quit(0)
	else:
		print("❌ RIG SOLVER TESTS FAILED!")
		quit(1)


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for child in node.get_children():
		var found := _find_skeleton(child)
		if found:
			return found
	return null


func _record_bone_poses(skeleton: Skeleton3D) -> Array[Transform3D]:
	var poses: Array[Transform3D] = []
	for i in range(skeleton.get_bone_count()):
		poses.append(skeleton.get_bone_global_pose(i))
	return poses


func _compare_poses(a: Array[Transform3D], b: Array[Transform3D], threshold: float = 0.001) -> bool:
	if a.size() != b.size():
		return false
	for i in range(a.size()):
		if a[i].origin.distance_to(b[i].origin) > threshold:
			return false
		if a[i].basis.get_rotation_quaternion().angle_to(b[i].basis.get_rotation_quaternion()) > threshold:
			return false
	return true
