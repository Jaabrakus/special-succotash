extends RefCounted

## Unconnected geometry experiment; no runtime consumer or independent node.
const IK := preload("res://scripts/player/operator_weapon_socket_ik.gd")
const Contacts := preload("res://scripts/player/operator_weapon_contact_solver.gd")
const RecoilEnvelope := preload("res://scripts/player/operator_fire_recoil_pulse.gd")

static func apply(pose: Node3D, target: Vector3, ready: float, body: Node3D, aim_weight: float = -1.0) -> Dictionary:
	if pose.last_posture != &"PRONE" or pose.last_requested_action != &"":
		return {"applied":false}
	pose.skeleton.clear_bones_global_pose_override()
	pose.skeleton.force_update_all_bone_transforms()
	var right: Transform3D = pose._right_hand_grip_world_transform()
	var left: Transform3D = pose._left_hand_grip_world_transform()
	var rp: Vector3 = pose._bone_world_position(&"mixamorig_RightForeArm")
	var lp: Vector3 = pose._bone_world_position(&"mixamorig_LeftForeArm")
	pose._set_weapon_solver_owned(true)
	pose._weapon_transform_on_trigger_hand(right, true)
	var source: Basis = pose.weapon_node.global_basis
	var desired: Vector3 = (target-pose.muzzle_socket.global_position).normalized()
	var bore: Vector3 = (pose.muzzle_socket.global_position-pose.barrel_base_socket.global_position).normalized()
	var delta := Quaternion(bore, desired).normalized()
	var required := delta.get_angle()
	var allowed: float = deg_to_rad(pose.maximum_wrist_correction_deg)
	var weight: float = clampf(aim_weight if aim_weight >= 0.0 else ready,0.0,1.0) * minf(1.0, allowed / maxf(required, 0.00001))
	delta = Quaternion.IDENTITY.slerp(delta, weight)
	pose.weapon_presentation_owner.set_world_basis(Basis(delta)*source)
	pose.weapon_presentation_owner.translate_world(right.origin-pose.trigger_socket.global_position)
	# Reuse the existing pose owner's world collision query and clearance caps.
	# This lifts the rigid gun, not the player/capsule or individual sockets.
	var floor_lift := maxf(
		pose._required_floor_lift(body,pose.trigger_socket.global_position,pose.prone_hand_floor_clearance_m),
		pose._required_floor_lift(body,pose.support_socket.global_position,pose.prone_hand_floor_clearance_m))
	floor_lift = maxf(floor_lift,pose._required_floor_lift(body,pose.muzzle_socket.global_position,pose.prone_muzzle_floor_clearance_m))
	floor_lift = minf(floor_lift,pose.prone_maximum_floor_lift_m)
	pose.weapon_presentation_owner.translate_world(Vector3.UP*floor_lift)
	var support_basis := (Basis(delta)*left.basis).orthonormalized()
	pose._update_support_contact_elbow_pole(pose.support_socket.global_position)
	if ready < 0.25:
		var blend: float = smoothstep(0.0,0.25,ready)
		var idle_basis: Basis = Contacts.support_contact_basis(pose.support_socket.global_basis,pose.weapon_node.get_meta("support_hand_pose",{}))
		support_basis = Basis(idle_basis.get_rotation_quaternion().slerp(support_basis.get_rotation_quaternion(),blend))
		lp = pose.left_elbow_pole.global_position.lerp(lp,blend)
	# Keep the final blended elbow plane above the floor, including relaxed
	# prone carry. A pole is only a hint; the probe checks the actual elbow.
	rp.y += pose._required_floor_lift(body,rp,pose.prone_elbow_floor_clearance_m+0.01)
	lp.y += pose._required_floor_lift(body,lp,pose.prone_elbow_floor_clearance_m+0.01)
	pose.trigger_hand_target.global_transform = Transform3D((Basis(delta)*right.basis).orthonormalized(),pose.trigger_socket.global_position)
	pose.support_hand_target.global_transform = Transform3D(support_basis,pose.support_socket.global_position)
	pose.right_elbow_pole.global_position = rp
	pose.left_elbow_pole.global_position = lp
	pose.trigger_hand_grip_locked = true
	pose.support_hand_grip_locked = true
	pose.right_hand_ik.override_tip_basis = true
	pose.left_hand_ik.override_tip_basis = true
	IK.solve(pose.skeleton,pose.bone_indices,pose.right_hand_ik,pose.trigger_hand_target,pose.right_elbow_pole,&"mixamorig_RightHand",pose.right_palm_anchor_local,true,1.0,8)
	IK.solve(pose.skeleton,pose.bone_indices,pose.left_hand_ik,pose.support_hand_target,pose.left_elbow_pole,&"mixamorig_LeftHand",pose.left_palm_anchor_local,true,1.0,8)
	pose.skeleton.force_update_all_bone_transforms()
	var right_floor_plane := _clear_actual_elbow(pose,body,&"Right")
	var left_floor_plane := _clear_actual_elbow(pose,body,&"Left")
	return {"applied":true,"required_bore_rotation_deg":rad_to_deg(required),"cap_deg":pose.maximum_wrist_correction_deg,"floor_lift":floor_lift,
		"right_floor_plane":right_floor_plane,"left_floor_plane":left_floor_plane,
		"muzzle_height":pose.muzzle_socket.global_position.y,"trigger_height":pose.trigger_socket.global_position.y,
		"support_height":pose.support_socket.global_position.y,"left_elbow_height":pose._bone_world_position(&"mixamorig_LeftForeArm").y,
		"right_elbow_height":pose._bone_world_position(&"mixamorig_RightForeArm").y}


static func _clear_actual_elbow(pose: Node3D, body: Node3D, side: StringName) -> Dictionary:
	var skeleton: Skeleton3D = pose.skeleton
	var arm_index: int = pose.bone_indices.get(StringName("mixamorig_%sArm"%side),-1)
	var elbow_index: int = pose.bone_indices.get(StringName("mixamorig_%sForeArm"%side),-1)
	var hand_index: int = pose.bone_indices.get(StringName("mixamorig_%sHand"%side),-1)
	var upper: Transform3D = skeleton.global_transform*skeleton.get_bone_global_pose(arm_index)
	var fore: Transform3D = skeleton.global_transform*skeleton.get_bone_global_pose(elbow_index)
	var wrist: Transform3D = skeleton.global_transform*skeleton.get_bone_global_pose(hand_index)
	var clearance: float = pose._floor_clearance(body,fore.origin)
	var result := {"before_clearance_m":clearance,"swivel_degrees":0.0,"feasible":true,
		"segment_length_delta_m":0.0,"shoulder_delta_m":0.0,"wrist_delta_m":0.0}
	var needed: float = pose.prone_elbow_floor_clearance_m-clearance
	if needed<=0.0 or not is_finite(clearance):
		return result
	var axis := (wrist.origin-upper.origin).normalized()
	var center := upper.origin+axis*(fore.origin-upper.origin).dot(axis)
	var radial := fore.origin-center
	# The fixed-endpoint elbow circle has height A*cos(theta)+B*sin(theta).
	# Pick its nearest floor-safe point instead of treating the IK pole as an
	# endpoint. This changes only the arm plane, never its length or wrist pose.
	var a := radial.y
	var b := axis.cross(radial).y
	var radius_y := sqrt(a*a+b*b)
	var required_y := fore.origin.y+needed-center.y
	if radius_y<0.000001 or required_y>radius_y:
		result.feasible=false
		return result
	var phase := atan2(b,a)
	var arc := acos(clampf(required_y/radius_y,-1.0,1.0))
	var first := wrapf(phase-arc,-PI,PI)
	var second := wrapf(phase+arc,-PI,PI)
	var angle := first if absf(first)<=absf(second) else second
	if absf(angle)>deg_to_rad(RecoilEnvelope.MAX_SWIVEL_DEGREES):
		result.feasible=false
		return result
	var before_upper_length := upper.origin.distance_to(fore.origin)
	var before_fore_length := fore.origin.distance_to(wrist.origin)
	var rotation := Basis(axis,angle)
	fore.origin=upper.origin+rotation*(fore.origin-upper.origin)
	fore.basis=rotation*fore.basis
	upper.basis=rotation*upper.basis
	var to_skeleton := skeleton.global_transform.affine_inverse()
	skeleton.set_bone_global_pose_override(arm_index,to_skeleton*upper,1.0,true)
	skeleton.set_bone_global_pose_override(elbow_index,to_skeleton*fore,1.0,true)
	skeleton.set_bone_global_pose_override(hand_index,to_skeleton*wrist,1.0,true)
	skeleton.force_update_all_bone_transforms()
	var actual_upper: Transform3D = skeleton.global_transform*skeleton.get_bone_global_pose(arm_index)
	var actual_fore: Transform3D = skeleton.global_transform*skeleton.get_bone_global_pose(elbow_index)
	var actual_wrist: Transform3D = skeleton.global_transform*skeleton.get_bone_global_pose(hand_index)
	result.swivel_degrees=rad_to_deg(angle)
	result.segment_length_delta_m=maxf(absf(before_upper_length-actual_upper.origin.distance_to(actual_fore.origin)),absf(before_fore_length-actual_fore.origin.distance_to(actual_wrist.origin)))
	result.shoulder_delta_m=actual_upper.origin.distance_to(upper.origin)
	result.wrist_delta_m=actual_wrist.origin.distance_to(wrist.origin)
	return result
