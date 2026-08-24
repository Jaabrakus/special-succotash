class_name SocomOperatorTwoHandWeaponCarry
extends RefCounted

## Visual-only rifle placement for authored two-hand clips. The animation owns
## the body and supplies both palm positions. This pass keeps the trigger socket
## on the right palm, aims the rifle through the support palm, and removes wrist
## roll that would turn the complete weapon sideways or upright.


static func place(
	weapon: Node3D,
	trigger_socket: Marker3D,
	support_socket: Marker3D,
	barrel_base_socket: Marker3D,
	muzzle_socket: Marker3D,
	optic_socket: Marker3D,
	trigger_hand_world: Vector3,
	support_hand_world: Vector3,
	world_up: Vector3 = Vector3.UP,
	fallback_direction: Vector3 = Vector3.FORWARD
) -> Dictionary:
	if weapon == null or trigger_socket == null:
		return {"applied": false}

	var barrel_direction := _barrel_direction(
		weapon,
		trigger_socket,
		barrel_base_socket,
		muzzle_socket
	)
	var desired_direction := support_hand_world - trigger_hand_world
	if desired_direction.length_squared() < 0.0025:
		desired_direction = fallback_direction
	if desired_direction.length_squared() < 0.000001:
		return {"applied": false}
	desired_direction = desired_direction.normalized()

	var preserved_scale := weapon.global_basis.get_scale()
	var clean_basis := weapon.global_basis.orthonormalized()
	if barrel_direction.length_squared() > 0.50:
		clean_basis = (
			Basis(Quaternion(barrel_direction, desired_direction)) * clean_basis
		).orthonormalized()
	weapon.global_basis = clean_basis.scaled(preserved_scale)

	var current_up := _rail_up_direction(
		weapon,
		barrel_base_socket,
		optic_socket,
		desired_direction
	)
	var target_up := world_up - desired_direction * world_up.dot(desired_direction)
	if current_up.length_squared() > 0.01 and target_up.length_squared() > 0.01:
		current_up = current_up.normalized()
		target_up = target_up.normalized()
		var roll_radians := current_up.signed_angle_to(
			target_up,
			desired_direction
		)
		weapon.global_basis = (
			Basis(Quaternion(desired_direction, roll_radians))
			* weapon.global_basis.orthonormalized()
		).orthonormalized().scaled(preserved_scale)

	# Rotation changes the socket position. Translate only after the complete
	# basis solve so the trigger contact remains exact.
	weapon.global_position += trigger_hand_world - trigger_socket.global_position
	var support_error := (
		support_socket.global_position.distance_to(support_hand_world)
		if support_socket != null
		else 0.0
	)
	return {
		"applied": true,
		"direction": desired_direction,
		"trigger_error_m": trigger_socket.global_position.distance_to(
			trigger_hand_world
		),
		"support_error_m": support_error,
	}


static func _barrel_direction(
	weapon: Node3D,
	trigger_socket: Marker3D,
	barrel_base_socket: Marker3D,
	muzzle_socket: Marker3D
) -> Vector3:
	if muzzle_socket != null:
		var origin := (
			barrel_base_socket.global_position
			if barrel_base_socket != null
			else trigger_socket.global_position
		)
		var socket_direction := muzzle_socket.global_position - origin
		if socket_direction.length_squared() > 0.000001:
			return socket_direction.normalized()
	return (-weapon.global_basis.z).normalized()


static func _rail_up_direction(
	weapon: Node3D,
	barrel_base_socket: Marker3D,
	optic_socket: Marker3D,
	barrel_direction: Vector3
) -> Vector3:
	var raw_up := weapon.global_basis.y.normalized()
	if barrel_base_socket != null and optic_socket != null:
		var socket_up := optic_socket.global_position - barrel_base_socket.global_position
		if socket_up.length_squared() > 0.000001:
			raw_up = socket_up.normalized()
	return raw_up - barrel_direction * raw_up.dot(barrel_direction)
