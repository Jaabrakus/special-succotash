class_name SocomOperatorArmKinematics
extends RefCounted

## Pure geometry used by the visual weapon-pose solver. It has no scene,
## animation, weapon ownership, or gameplay authority state.


static func resolve_aim_direction(
	aim_yaw: float,
	aim_pitch: float,
	world_target: Vector3,
	origin: Vector3,
	body: Node3D
) -> Vector3:
	if world_target != Vector3.ZERO and origin.distance_to(world_target) > 0.10:
		return (world_target - origin).normalized()
	var yaw_basis := Basis(Vector3.UP, body.global_rotation.y + aim_yaw)
	var yaw_forward := yaw_basis * Vector3.FORWARD
	var right := yaw_basis * Vector3.RIGHT
	return (Basis(right, aim_pitch) * yaw_forward).normalized()


static func fit_human_reach(
	origin: Vector3,
	target: Vector3,
	aim_direction: Vector3,
	reach: float,
	minimum_forward_reach_ratio: float,
	minimum_elbow_angle_deg: float,
	maximum_elbow_angle_deg: float
) -> Vector3:
	var fitted := target
	var forward_reach := (fitted - origin).dot(aim_direction)
	var minimum_forward := reach * minimum_forward_reach_ratio
	if forward_reach < minimum_forward:
		fitted += aim_direction * (minimum_forward - forward_reach)
	var delta := fitted - origin
	if delta.length_squared() < 0.000001:
		delta = aim_direction * minimum_forward
	var direction := delta.normalized()
	var upper := reach * 0.5
	var lower := reach - upper
	var minimum_distance := distance_for_elbow_angle(
		upper,
		lower,
		deg_to_rad(minimum_elbow_angle_deg)
	)
	var maximum_distance := minf(
		distance_for_elbow_angle(upper, lower, deg_to_rad(maximum_elbow_angle_deg)),
		reach * 0.965
	)
	return origin + direction * clampf(delta.length(), minimum_distance, maximum_distance)


static func distance_for_elbow_angle(upper: float, lower: float, angle: float) -> float:
	return sqrt(maxf(
		upper * upper + lower * lower - 2.0 * upper * lower * cos(angle),
		0.0001
	))


static func blend_rotated_basis(source: Basis, delta: Quaternion, weight: float) -> Basis:
	var source_rotation := source.get_rotation_quaternion().normalized()
	var solved_rotation := (delta * source_rotation).normalized()
	var blended := source_rotation.slerp(solved_rotation, clampf(weight, 0.0, 1.0))
	return Basis(blended).scaled(source.get_scale())
