extends RefCounted

const Contact := preload("res://scripts/player/operator_weapon_contact_solver.gd")
const SocketIK := preload("res://scripts/player/operator_weapon_socket_ik.gd")
const MAX_CARRY_ADJUSTMENT_M := 0.10

# The authored right palm owns idle carry. Only an unreachable support wrist
# requests a bounded inward correction, through the existing right-arm solver.
static func fit(pose: Node) -> void:
	var skeleton := pose.get("skeleton") as Skeleton3D
	var right_ik := pose.get("right_hand_ik") as SkeletonIK3D
	var target := pose.get("trigger_hand_target") as Marker3D
	var pole := pose.get("right_elbow_pole") as Marker3D
	var support := pose.get("support_hand_target") as Marker3D
	var indices: Dictionary = pose.get("bone_indices")
	if skeleton == null or right_ik == null or target == null or pole == null or support == null:
		return
	var shoulder: Vector3 = pose.call("_bone_world_position", &"mixamorig_LeftArm")
	var elbow: Vector3 = pose.call("_bone_world_position", &"mixamorig_LeftForeArm")
	var wrist: Vector3 = pose.call("_bone_world_position", &"mixamorig_LeftHand")
	var reach := shoulder.distance_to(elbow) + elbow.distance_to(wrist)
	var goal := Contact.wrist_target_for_contact(skeleton, support.global_transform, pose.get("left_palm_anchor_local"))
	var displacement := goal.origin - shoulder
	var maximum_reach := reach * 0.965
	if displacement.length() <= maximum_reach or reach <= 0.01:
		return
	var correction := -displacement.normalized() * minf(displacement.length() - maximum_reach, MAX_CARRY_ADJUSTMENT_M)
	var palm: Transform3D = pose.call("_right_hand_grip_world_transform")
	target.global_transform = Transform3D(palm.basis, palm.origin + correction)
	var right_shoulder: Vector3 = pose.call("_bone_world_position", &"mixamorig_RightArm")
	var right_elbow: Vector3 = pose.call("_bone_world_position", &"mixamorig_RightForeArm")
	var elbow_out := right_elbow - right_shoulder.lerp(palm.origin, 0.5)
	if elbow_out.length_squared() < 0.000001:
		elbow_out = skeleton.global_basis.x.normalized()
	pole.global_position = right_elbow + elbow_out.normalized() * 0.2
	pose.set("trigger_hand_grip_locked", true)
	right_ik.override_tip_basis = true
	SocketIK.solve(skeleton, indices, right_ik, target, pole,
		&"mixamorig_RightHand", pose.get("right_palm_anchor_local"), true, 1.0, 3)
	pose.call("_weapon_transform_on_trigger_hand", pose.call("_right_hand_grip_world_transform"), true)
	var socket := pose.get("support_socket") as Marker3D
	support.global_position = socket.global_position
