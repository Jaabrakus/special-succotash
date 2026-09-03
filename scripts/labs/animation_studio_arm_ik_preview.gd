class_name SocomAnimationStudioArmIkPreview
extends RefCounted

const WEAPON_CONTACT_SOLVER := preload(
	"res://scripts/player/operator_weapon_contact_solver.gd"
)
const NATIVE_TWO_BONE_IK := preload(
	"res://scripts/player/operator_native_two_bone_ik.gd"
)

## Editor-only two-arm preview for animation correction keys. Gameplay keeps
## its own authoritative visual solver; this helper only shows the saved hand
## contacts and elbow-pole shape inside Animation Studio.

var bound_skeleton: Skeleton3D
var left_ik
var right_ik
var left_shoulder_index := -1
var right_shoulder_index := -1
var left_elbow_index := -1
var right_elbow_index := -1
var left_hand_index := -1
var right_hand_index := -1
var hips_index := -1
var left_palm_anchor_local := Vector3.ZERO
var right_palm_anchor_local := Vector3.ZERO


func stop() -> void:
	if is_instance_valid(left_ik):
		left_ik.stop()
	if is_instance_valid(right_ik):
		right_ik.stop()
	if is_instance_valid(bound_skeleton):
		bound_skeleton.clear_bones_global_pose_override()


func solve(
	skeleton: Skeleton3D,
	left_target: Marker3D,
	right_target: Marker3D,
	left_elbow_offset: Vector3,
	right_elbow_offset: Vector3,
	right_hand_rotation_degrees: Vector3,
	solve_left: bool = true,
	solve_right: bool = true,
	left_hand_rotation_degrees: Vector3 = Vector3.ZERO
) -> bool:
	if skeleton == null or left_target == null or right_target == null:
		return false
	if not _ensure_skeleton(skeleton):
		return false
	# Both hands must solve to their authored grip markers. Using the current
	# right-hand bone as its own target made the trigger arm a no-op, so changing
	# its elbow pole moved the editor dot without moving the visible elbow.
	var right_hand_world := right_target.global_transform
	right_hand_world.basis = (
		right_hand_world.basis.orthonormalized()
		* Basis.from_euler(right_hand_rotation_degrees * (PI / 180.0), EULER_ORDER_YXZ)
	).orthonormalized()
	right_hand_world = WEAPON_CONTACT_SOLVER.wrist_target_for_contact(
		skeleton,
		right_hand_world,
		right_palm_anchor_local
	)
	right_hand_world = _clamp_target_to_arm_reach(
		right_shoulder_index,
		right_elbow_index,
		right_hand_index,
		right_hand_world
	)
	# The support marker lives below the scaled operator/weapon preview tree.
	# Feeding that inherited scale (or any resulting shear) into SkeletonIK3D
	# while override_tip_basis is enabled deforms the skinned forearm. Keep the
	# authored palm orientation, but make the IK target a rotation-only basis,
	# exactly as we already do for the trigger hand above.
	var left_hand_world := left_target.global_transform
	left_hand_world.basis = (
		left_hand_world.basis.orthonormalized()
		* Basis.from_euler(
			left_hand_rotation_degrees * (PI / 180.0),
			EULER_ORDER_YXZ
		)
	).orthonormalized()
	left_hand_world = WEAPON_CONTACT_SOLVER.wrist_target_for_contact(
		skeleton,
		left_hand_world,
		left_palm_anchor_local
	)
	left_hand_world = _clamp_target_to_arm_reach(
		left_shoulder_index,
		left_elbow_index,
		left_hand_index,
		left_hand_world
	)
	if solve_right:
		_solve_arm(
			right_ik,
			right_hand_world,
			_elbow_world(right_shoulder_index, right_hand_world.origin, right_elbow_offset, true)
		)
	else:
		right_ik.stop()
	if solve_left:
		var left_elbow_pole := WEAPON_CONTACT_SOLVER.support_elbow_pole(
			bound_skeleton,
			left_shoulder_index,
			right_shoulder_index,
			hips_index,
			left_hand_world.origin,
			left_hand_rotation_degrees.z,
			left_elbow_offset
		)
		_solve_arm(
			left_ik,
			left_hand_world,
			left_elbow_pole
		)
	else:
		left_ik.stop()
	return solve_left or solve_right


func _ensure_skeleton(next_skeleton: Skeleton3D) -> bool:
	if (
		bound_skeleton == next_skeleton
		and left_ik != null
		and right_ik != null
		and is_instance_valid(left_ik.two_bone)
		and is_instance_valid(right_ik.two_bone)
	):
		return true
	stop()
	bound_skeleton = next_skeleton
	left_shoulder_index = _find_bone(["mixamorig_LeftArm", "mixamorig:LeftArm", "ArmUpper.L", "Bip01 L UpperArm"])
	right_shoulder_index = _find_bone(["mixamorig_RightArm", "mixamorig:RightArm", "ArmUpper.R", "Bip01 R UpperArm"])
	left_elbow_index = _find_bone(["mixamorig_LeftForeArm", "mixamorig:LeftForeArm", "ArmLower.L", "Bip01 L Forearm"])
	right_elbow_index = _find_bone(["mixamorig_RightForeArm", "mixamorig:RightForeArm", "ArmLower.R", "Bip01 R Forearm"])
	left_hand_index = _find_bone(["mixamorig_LeftHand", "mixamorig:LeftHand", "Hand.L.001", "Bip01 L Hand"])
	right_hand_index = _find_bone(["mixamorig_RightHand", "mixamorig:RightHand", "Hand.R.001", "Bip01 R Hand"])
	hips_index = _find_bone(["mixamorig_Hips", "mixamorig:Hips", "Hips", "Bip01 Pelvis"])
	if (
		left_shoulder_index < 0
		or right_shoulder_index < 0
		or left_elbow_index < 0
		or right_elbow_index < 0
		or left_hand_index < 0
		or right_hand_index < 0
	):
		return false
	left_palm_anchor_local = WEAPON_CONTACT_SOLVER.calculate_palm_anchor(
		bound_skeleton,
		"Left",
		left_hand_index
	)
	right_palm_anchor_local = WEAPON_CONTACT_SOLVER.calculate_palm_anchor(
		bound_skeleton,
		"Right",
		right_hand_index
	)
	left_ik = _make_ik(
		"PresentationLeftHandTwoBoneIK",
		left_shoulder_index,
		left_elbow_index,
		left_hand_index
	)
	right_ik = _make_ik(
		"PresentationRightHandTwoBoneIK",
		right_shoulder_index,
		right_elbow_index,
		right_hand_index
	)
	return left_ik != null and right_ik != null


func _make_ik(
	node_name: String,
	root_index: int,
	middle_index: int,
	tip_index: int
):
	var ik = NATIVE_TWO_BONE_IK.new()
	ik.bind(
		bound_skeleton,
		node_name,
		root_index,
		middle_index,
		tip_index
	)
	ik.override_tip_basis = true
	ik.interpolation = 1.0
	ik.stop()
	return ik


func _solve_arm(ik, target: Transform3D, elbow_world: Vector3) -> void:
	ik.override_tip_basis = true
	ik.interpolation = 1.0
	ik.set_world_target(target, elbow_world)
	ik.start(true)
	bound_skeleton.force_update_all_bone_transforms()


func get_debug_state() -> Dictionary:
	return {
		"solver": "TwoBoneIK3D",
		"left_running": left_ik != null and left_ik.is_running(),
		"right_running": right_ik != null and right_ik.is_running(),
		"left_modifier": (
			left_ik.two_bone.name
			if left_ik != null and is_instance_valid(left_ik.two_bone)
			else &""
		),
		"right_modifier": (
			right_ik.two_bone.name
			if right_ik != null and is_instance_valid(right_ik.two_bone)
			else &""
		),
		"left_target": (
			left_ik.internal_target.name
			if left_ik != null and is_instance_valid(left_ik.internal_target)
			else &""
		),
		"left_pole": (
			left_ik.internal_pole.name
			if left_ik != null and is_instance_valid(left_ik.internal_pole)
			else &""
		),
		"right_target": (
			right_ik.internal_target.name
			if right_ik != null and is_instance_valid(right_ik.internal_target)
			else &""
		),
		"right_pole": (
			right_ik.internal_pole.name
			if right_ik != null and is_instance_valid(right_ik.internal_pole)
			else &""
		),
	}


func _clamp_target_to_arm_reach(
	shoulder_index: int,
	elbow_index: int,
	hand_index: int,
	target: Transform3D
) -> Transform3D:
	var shoulder := _bone_world_transform(shoulder_index).origin
	var elbow := _bone_world_transform(elbow_index).origin
	var hand := _bone_world_transform(hand_index).origin
	var maximum_reach := (
		shoulder.distance_to(elbow) + elbow.distance_to(hand)
	) * 0.98
	var requested := target.origin - shoulder
	if requested.length() > maximum_reach and maximum_reach > 0.0:
		target.origin = shoulder + requested.normalized() * maximum_reach
	return target


func _elbow_world(
	shoulder_index: int,
	hand_world: Vector3,
	offset: Vector3,
	is_right: bool,
	left_palm_roll_degrees: float = 0.0
) -> Vector3:
	var shoulder_world := _bone_world_transform(shoulder_index).origin
	var opposite_shoulder_index := left_shoulder_index if is_right else right_shoulder_index
	var opposite_shoulder_world := _bone_world_transform(opposite_shoulder_index).origin
	var shoulder_midpoint := shoulder_world.lerp(opposite_shoulder_world, 0.5)
	var anatomical_right := (
		_bone_world_transform(right_shoulder_index).origin
		- _bone_world_transform(left_shoulder_index).origin
	).normalized()
	var anatomical_up := Vector3.UP
	if hips_index >= 0:
		anatomical_up = (
			shoulder_midpoint - _bone_world_transform(hips_index).origin
		).normalized()
	# Shoulder width and torso length define the body frame. Imported skeleton
	# axes are asset-space conventions and, on this operator, local forward is
	# world-up. Using those axes was the reason the support elbow climbed into
	# the face whenever the hand solver tried to move it forward.
	anatomical_up = (
		anatomical_up
		- anatomical_right * anatomical_up.dot(anatomical_right)
	).normalized()
	if anatomical_up.length_squared() < 0.5:
		anatomical_up = Vector3.UP
	var anatomical_forward := anatomical_up.cross(anatomical_right).normalized()
	var anatomical_outward := anatomical_right if is_right else -anatomical_right
	var outward := 0.28 if is_right else 0.38
	var downward := 0.08 if is_right else 0.10
	var forward := 0.10 if is_right else 0.08
	if not is_right:
		# Match Gunsmith's cradle behavior. A rolled support palm needs a lower,
		# slightly tighter elbow plane; otherwise SkeletonIK lifts the elbow across
		# the operator's face to satisfy the wrist basis.
		var upright_factor := (
			cos(deg_to_rad(left_palm_roll_degrees)) + 1.0
		) * 0.5
		outward = lerpf(0.24, outward, upright_factor)
		downward = lerpf(0.18, downward, upright_factor)
	return (
		shoulder_world.lerp(hand_world, 0.5)
		+ anatomical_outward * outward
		- anatomical_up * downward
		+ anatomical_forward * forward
		+ anatomical_outward * offset.x
		+ anatomical_up * offset.y
		+ anatomical_forward * offset.z
	)


func _bone_world_transform(bone_index: int) -> Transform3D:
	return bound_skeleton.global_transform * bound_skeleton.get_bone_global_pose(bone_index)


func _find_bone(candidates: Array[String]) -> int:
	for candidate in candidates:
		var index := bound_skeleton.find_bone(candidate)
		if index >= 0:
			return index
	return -1
