extends RefCounted

const WeaponOwnershipContract := preload("res://scripts/player/weapon_ownership_contract.gd")
const WeaponContactSolver := preload(
	"res://scripts/player/operator_weapon_contact_solver.gd"
)

enum GripStyle {
	CLASSIC_CRADLE,
	C_CLAMP_TACTICAL,
	MAGWELL_GRIP,
	VERTICAL_FOREGRIP,
	ANGLED_AFG,
}


static func solve_trigger_hand(lab: Node) -> void:
	if not lab.skeleton or not lab.right_hand_ik or not lab.right_grip_marker or not is_instance_valid(lab.right_grip_marker):
		return
	if not lab.weapon_master_pose_initialized:
		return
	if WeaponOwnershipContract.weapon_follows_right_hand(lab.weapon_owner_state):
		if lab.right_hand_ik.is_running():
			lab.right_hand_ik.stop()
		return
	var hand_pose: Transform3D = lab.skeleton.get_bone_global_pose(lab.right_hand_idx)
	var desired_basis: Basis = (
		lab.skeleton.global_transform.basis * hand_pose.basis
	).orthonormalized()
	if lab._gunsmith_live_aim_active():
		desired_basis = (
			Basis(lab.gunsmith_live_aim_rotation) * desired_basis
		).orthonormalized()
	var wrist_target: Transform3D = WeaponContactSolver.wrist_target_for_contact(
		lab.skeleton,
		Transform3D(desired_basis, lab.right_grip_marker.global_position),
		lab.right_palm_anchor_local
	)
	var wrist_position: Vector3 = wrist_target.origin
	lab.right_hand_ik.override_tip_basis = true
	var internal_wrist_position := wrist_position
	for _correction in range(4):
		lab.right_hand_ik.target = Transform3D(desired_basis, internal_wrist_position)
		lab.right_hand_ik.magnet = right_elbow_magnet_for(lab, internal_wrist_position)
		lab.right_hand_ik.stop()
		lab.right_hand_ik.start(true)
		lab.skeleton.force_update_all_bone_transforms()
		var residual: Vector3 = lab.right_grip_marker.global_position - lab._right_palm_contact_world()
		if residual.length() <= 0.001:
			break
		internal_wrist_position += residual
	if lab._gunsmith_live_aim_active():
		var desired_hand_world := Transform3D(desired_basis, wrist_position)
		var desired_hand_local: Transform3D = (
			lab.skeleton.global_transform.affine_inverse() * desired_hand_world
		)
		var current_hand_pose: Transform3D = lab.skeleton.get_bone_global_pose(
			lab.right_hand_idx
		)
		desired_hand_local.basis = desired_hand_local.basis.orthonormalized().scaled(
			current_hand_pose.basis.get_scale()
		)
		lab.skeleton.set_bone_global_pose_override(
			lab.right_hand_idx,
			desired_hand_local,
			1.0,
			false
		)
		lab.skeleton.force_update_all_bone_transforms()


static func right_hand_world_transform(lab: Node) -> Transform3D:
	if not lab.skeleton or lab.right_hand_idx < 0:
		return Transform3D.IDENTITY
	return lab.skeleton.global_transform * lab.skeleton.get_bone_global_pose(lab.right_hand_idx)


static func right_hand_grip_world_transform(lab: Node) -> Transform3D:
	var hand_world: Transform3D = right_hand_world_transform(lab)
	if lab.skeleton == null:
		return hand_world
	return Transform3D(
		hand_world.basis.orthonormalized(),
		lab._right_palm_contact_world()
	)


static func left_hand_world_transform(lab: Node) -> Transform3D:
	if not lab.skeleton or lab.left_hand_idx < 0:
		return Transform3D.IDENTITY
	return lab.skeleton.global_transform * lab.skeleton.get_bone_global_pose(lab.left_hand_idx)


static func right_elbow_magnet_for(lab: Node, wrist_world: Vector3) -> Vector3:
	if not lab.skeleton or lab.right_arm_idx < 0:
		return Vector3.ZERO
	return lab.skeleton.global_transform.affine_inverse() * right_elbow_pole_world(
		lab,
		wrist_world
	)


static func right_elbow_pole_base_world(lab: Node, wrist_world: Vector3) -> Vector3:
	var shoulder_world: Vector3 = (
		lab.skeleton.global_transform
		* lab.skeleton.get_bone_global_pose(lab.right_arm_idx)
	).origin
	var midpoint := (shoulder_world + wrist_world) * 0.5
	var body_right: Vector3 = lab.skeleton.global_transform.basis.x.normalized()
	var body_up: Vector3 = lab.skeleton.global_transform.basis.y.normalized()
	var body_forward: Vector3 = lab.skeleton.global_transform.basis.z.normalized()
	return midpoint - body_right * 0.28 - body_up * 0.08 + body_forward * 0.10


static func right_elbow_pole_world(lab: Node, wrist_world: Vector3) -> Vector3:
	var body_basis: Basis = lab.skeleton.global_transform.basis.orthonormalized()
	return right_elbow_pole_base_world(lab, wrist_world) + body_basis * lab.right_elbow_pole_offset


static func solve_support_hand(lab: Node) -> void:
	if not lab.skeleton or not lab.left_grip_marker or not is_instance_valid(lab.left_grip_marker):
		return
	if not lab.left_hand_ik or not lab.weapon_master_pose_initialized:
		return
	if lab.support_hand_policy != WeaponOwnershipContract.SUPPORT_IK_TO_WEAPON or not lab.support_hand_attached:
		if lab.left_hand_ik.is_running():
			lab.left_hand_ik.stop()
		return
	var palm_rot := Basis.from_euler(Vector3(
		deg_to_rad(lab.palm_pitch),
		deg_to_rad(lab.palm_yaw),
		deg_to_rad(lab.palm_roll)
	))
	var desired_global_basis: Basis = (
		lab.left_grip_marker.global_transform.basis.orthonormalized() * palm_rot
	).orthonormalized()
	var wrist_target: Transform3D = WeaponContactSolver.wrist_target_for_contact(
		lab.skeleton,
		Transform3D(desired_global_basis, lab.left_grip_marker.global_position),
		lab.left_palm_anchor_local
	)
	var wrist_global_position: Vector3 = wrist_target.origin
	lab.left_hand_ik.target = Transform3D(desired_global_basis, wrist_global_position)
	lab.left_hand_ik.override_tip_basis = true
	lab.left_hand_ik.magnet = left_elbow_magnet_for(lab, wrist_global_position)
	lab.left_hand_ik.stop()
	lab.left_hand_ik.start(true)
	lab.skeleton.force_update_all_bone_transforms()


static func left_elbow_magnet_for(lab: Node, wrist_world: Vector3) -> Vector3:
	if not lab.skeleton or lab.left_arm_idx < 0:
		return Vector3.ZERO
	return lab.skeleton.global_transform.affine_inverse() * left_elbow_pole_world(
		lab,
		wrist_world
	)


static func left_elbow_pole_base_world(lab: Node, wrist_world: Vector3) -> Vector3:
	var shoulder_world: Vector3 = (
		lab.skeleton.global_transform
		* lab.skeleton.get_bone_global_pose(lab.left_arm_idx)
	).origin
	var midpoint := (shoulder_world + wrist_world) * 0.5
	var body_right: Vector3 = lab.skeleton.global_transform.basis.x.normalized()
	var body_up: Vector3 = lab.skeleton.global_transform.basis.y.normalized()
	var body_forward: Vector3 = lab.skeleton.global_transform.basis.z.normalized()
	var outward := 0.38
	var downward := 0.08
	var forward := 0.10
	match lab.current_grip_style:
		GripStyle.CLASSIC_CRADLE:
			outward = 0.38; downward = 0.10; forward = 0.08
		GripStyle.C_CLAMP_TACTICAL:
			outward = 0.46; downward = 0.03; forward = 0.14
		GripStyle.MAGWELL_GRIP:
			outward = 0.30; downward = 0.12; forward = 0.06
		GripStyle.VERTICAL_FOREGRIP:
			outward = 0.34; downward = 0.11; forward = 0.08
		GripStyle.ANGLED_AFG:
			outward = 0.40; downward = 0.08; forward = 0.12
	var roll_rad := deg_to_rad(lab.palm_roll)
	var palm_upright_factor := (cos(roll_rad) + 1.0) * 0.5
	outward = lerpf(0.24, outward, palm_upright_factor)
	downward = lerpf(0.18, downward, palm_upright_factor)
	return midpoint + body_right * outward - body_up * downward + body_forward * forward


static func left_elbow_pole_world(lab: Node, wrist_world: Vector3) -> Vector3:
	var body_basis: Basis = lab.skeleton.global_transform.basis.orthonormalized()
	return left_elbow_pole_base_world(lab, wrist_world) + body_basis * lab.left_elbow_pole_offset


static func update_stance_rebase(lab: Node, delta: float) -> void:
	lab.stance_rebase_remaining = maxf(0.0, lab.stance_rebase_remaining - delta)


static func apply_finger_posing(lab: Node) -> void:
	if not lab.skeleton or lab.support_hand_policy != WeaponOwnershipContract.SUPPORT_IK_TO_WEAPON or not lab.support_hand_attached:
		return
	var idx1: int = lab.skeleton.find_bone("mixamorig_LeftHandIndex1")
	var idx2: int = lab.skeleton.find_bone("mixamorig_LeftHandIndex2")
	var idx3: int = lab.skeleton.find_bone("mixamorig_LeftHandIndex3")
	var curl_rad := deg_to_rad(lab.finger_curl * 80.0)
	if idx1 >= 0:
		lab.skeleton.set_bone_pose_rotation(idx1, Quaternion(Vector3.RIGHT, curl_rad * 0.45))
	if idx2 >= 0:
		lab.skeleton.set_bone_pose_rotation(idx2, Quaternion(Vector3.RIGHT, curl_rad * 0.35))
	if idx3 >= 0:
		lab.skeleton.set_bone_pose_rotation(idx3, Quaternion(Vector3.RIGHT, curl_rad * 0.20))
	var th1: int = lab.skeleton.find_bone("mixamorig_LeftHandThumb1")
	var th2: int = lab.skeleton.find_bone("mixamorig_LeftHandThumb2")
	var thumb_rad := deg_to_rad(lab.thumb_wrap * 65.0)
	if th1 >= 0:
		lab.skeleton.set_bone_pose_rotation(
			th1,
			Quaternion(Vector3.FORWARD, thumb_rad * 0.5)
			* Quaternion(Vector3.UP, thumb_rad * 0.3)
		)
	if th2 >= 0:
		lab.skeleton.set_bone_pose_rotation(
			th2,
			Quaternion(Vector3.FORWARD, thumb_rad * 0.5)
		)
