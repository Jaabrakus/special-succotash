class_name SocomNetworkProtocol
extends RefCounted

## Serialization boundary for the multiplayer vertical slice. Gameplay objects
## remain typed locally; only plain Dictionaries and engine value types cross
## ENet. Keeping this conversion in one place makes packet validation testable.

const MovementCommand := preload("res://scripts/network/socom_movement_command.gd")


static func movement_to_packet(command) -> Dictionary:
	if command == null:
		return {}
	return {
		"tick": int(command.simulation_tick),
		"move": Vector2(command.move_axis).limit_length(1.0),
		"aim_yaw": wrapf(float(command.aim_yaw), -PI, PI),
		"jump": bool(command.jump_pressed),
		"dive": bool(command.dive_pressed),
		"roll": bool(command.roll_pressed),
		"prone": bool(command.prone_pressed),
		"crouch": bool(command.crouch_held),
		"crouch_released": bool(command.crouch_released),
		"peek": clampf(float(command.peek_axis), -1.0, 1.0),
	}


static func packet_to_movement(packet: Dictionary):
	var command = MovementCommand.new()
	command.simulation_tick = maxi(0, int(packet.get("tick", 0)))
	command.move_axis = _bounded_vector2(packet.get("move", Vector2.ZERO))
	command.aim_yaw = wrapf(float(packet.get("aim_yaw", 0.0)), -PI, PI)
	command.jump_pressed = bool(packet.get("jump", false))
	command.dive_pressed = bool(packet.get("dive", false))
	command.roll_pressed = bool(packet.get("roll", false))
	command.prone_pressed = bool(packet.get("prone", false))
	command.crouch_held = bool(packet.get("crouch", false))
	command.crouch_released = bool(packet.get("crouch_released", false))
	command.peek_axis = clampf(float(packet.get("peek", 0.0)), -1.0, 1.0)
	return command


static func movement_packet_is_sane(packet: Dictionary) -> bool:
	if typeof(packet.get("tick")) != TYPE_INT:
		return false
	if typeof(packet.get("move")) != TYPE_VECTOR2:
		return false
	var yaw_type := typeof(packet.get("aim_yaw"))
	if yaw_type not in [TYPE_FLOAT, TYPE_INT]:
		return false
	var axis: Vector2 = packet.get("move", Vector2.ZERO)
	var yaw := float(packet.get("aim_yaw", 0.0))
	return axis.is_finite() and axis.length() <= 1.05 and not is_nan(yaw) and not is_inf(yaw)


static func sanitize_aim_packet(packet: Dictionary) -> Dictionary:
	var direction: Vector3 = packet.get("direction", Vector3.FORWARD)
	var origin: Vector3 = packet.get("reported_muzzle_origin", Vector3.ZERO)
	return {
		"sequence": maxi(0, int(packet.get("sequence", 0))),
		"simulation_tick": maxi(0, int(packet.get("simulation_tick", 0))),
		"yaw": clampf(float(packet.get("yaw", 0.0)), -PI, PI),
		"pitch": clampf(
			float(packet.get("pitch", 0.0)),
			deg_to_rad(-89.0),
			deg_to_rad(89.0)
		),
		"reported_muzzle_origin": origin if origin.is_finite() else Vector3.ZERO,
		"direction": (
			direction.normalized()
			if direction.is_finite() and direction.length_squared() > 0.0001
			else Vector3.FORWARD
		),
	}


static func _bounded_vector2(value: Variant) -> Vector2:
	if value is not Vector2:
		return Vector2.ZERO
	var axis := value as Vector2
	if not axis.is_finite():
		return Vector2.ZERO
	return axis.limit_length(1.0)
