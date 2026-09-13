extends RefCounted

## Presentation adaptation shared by native rifle and pistol poses. Rotates
## one upper-body group; relative elbows/wrists stay authored. Not ISO code.
static func apply(pose: Node3D, yaw: float, pitch: float, weight: float,
		target: Vector3, body: Node3D, maximum_degrees: float) -> float:
	if weight <= 0.001 or pose.skeleton == null or pose.muzzle_socket == null or pose.barrel_base_socket == null:
		return 0.0
	var spine: int = pose.skeleton.find_bone("mixamorig_Spine2")
	if spine < 0: return 0.0
	var budget := deg_to_rad(clampf(maximum_degrees, 0.0, 85.0)) if is_finite(maximum_degrees) else 0.0
	var applied := 0.0
	for iteration in 3:
		var bore: Vector3 = pose.barrel_base_socket.global_position.direction_to(pose.muzzle_socket.global_position)
		var direction: Vector3 = pose._resolve_aim_direction(yaw, pitch, target, pose.muzzle_socket.global_position, body)
		if bore.length_squared() < 0.5 or direction.length_squared() < 0.5: break
		var angle := bore.angle_to(direction)
		if angle < 0.0001 or budget < 0.0001: break
		var amount := minf(angle, budget) * clampf(weight, 0.0, 1.0)
		var rotation := Quaternion.IDENTITY.slerp(Quaternion(bore, direction), amount / angle)
		var world: Transform3D = pose.skeleton.global_transform * pose.skeleton.get_bone_global_pose(spine)
		world.basis = Basis(rotation) * world.basis
		pose.skeleton.set_bone_global_pose_override(spine, pose.skeleton.global_transform.affine_inverse() * world, 1.0, true)
		pose.skeleton.force_update_all_bone_transforms()
		pose._weapon_transform_on_trigger_hand(pose._right_hand_grip_world_transform(), true)
		applied += rad_to_deg(amount)
		budget -= amount
		if weight < 0.999: break
	return applied
