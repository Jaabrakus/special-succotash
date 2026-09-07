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
		"aim_pitch": clampf(float(command.aim_pitch), -PI * 0.49, PI * 0.49),
		"jump": bool(command.jump_pressed),
		"jump_held": bool(command.jump_held),
		"direction_held": int(command.direction_held_mask) & 15,
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
	command.aim_pitch = clampf(float(packet.get("aim_pitch", 0.0)), -PI * 0.49, PI * 0.49)
	command.jump_pressed = bool(packet.get("jump", false))
	command.jump_held = bool(packet.get("jump_held", false))
	command.direction_held_mask = int(packet.get("direction_held", 0)) & 15
	command.dive_pressed = bool(packet.get("dive", false))
	command.roll_pressed = bool(packet.get("roll", false))
	command.prone_pressed = bool(packet.get("prone", false))
	command.crouch_held = bool(packet.get("crouch", false))
	command.crouch_released = bool(packet.get("crouch_released", false))
	command.peek_axis = clampf(float(packet.get("peek", 0.0)), -1.0, 1.0)
	return command


static func movement_packet_is_sane(packet: Dictionary) -> bool:
	var held: Variant = packet.get("direction_held", 0)
	if typeof(held) != TYPE_INT or int(held) < 0 or int(held) > 15:
		return false
	if typeof(packet.get("tick")) != TYPE_INT:
		return false
	if typeof(packet.get("move")) != TYPE_VECTOR2:
		return false
	var yaw_type := typeof(packet.get("aim_yaw"))
	if yaw_type not in [TYPE_FLOAT, TYPE_INT]:
		return false
	var axis: Vector2 = packet.get("move", Vector2.ZERO)
	var yaw := float(packet.get("aim_yaw", 0.0))
	var pitch_value: Variant = packet.get("aim_pitch", 0.0)
	if typeof(pitch_value) not in [TYPE_FLOAT, TYPE_INT]: return false
	var pitch := float(pitch_value)
	return axis.is_finite() and axis.length() <= 1.05 and is_finite(yaw) and is_finite(pitch)


static func sanitize_aim_packet(packet: Dictionary) -> Dictionary:
	var direction: Vector3 = packet.get("direction", Vector3.FORWARD)
	var origin: Vector3 = packet.get("reported_muzzle_origin", Vector3.ZERO)
	var sanitized := {
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
	if packet.has("convergence_distance"):
		sanitized["convergence_distance"] = clampf(
			float(packet.get("convergence_distance", 0.0)),
			0.25,
			250.0
		)
	return sanitized


static func _bounded_vector2(value: Variant) -> Vector2:
	if value is not Vector2:
		return Vector2.ZERO
	var axis := value as Vector2
	if not axis.is_finite():
		return Vector2.ZERO
	return axis.limit_length(1.0)


static func sanitize_snapshot(packet: Dictionary) -> Dictionary:
	var entities: Dictionary = packet.get("entities", packet)
	var sanitized_entities := {}
	for raw_id in entities:
		var raw_data = entities[raw_id]
		if raw_data is not Dictionary:
			continue
		var data := raw_data as Dictionary
		var pos: Vector3 = data.get("position", Vector3.ZERO)
		var vel: Vector3 = data.get("velocity", Vector3.ZERO)
		var yaw := float(data.get("yaw", 0.0))
		if not pos.is_finite():
			pos = Vector3.ZERO
		if not vel.is_finite():
			vel = Vector3.ZERO
		if is_nan(yaw) or is_inf(yaw):
			yaw = 0.0
		sanitized_entities[raw_id] = {
			"position": pos,
			"yaw": wrapf(yaw, -PI, PI),
			"velocity": vel,
			"posture": clampi(int(data.get("posture", 0)), 0, 6),
			"health": clampf(float(data.get("health", 100.0)), 0.0, 1000.0),
			"alive": bool(data.get("alive", true)),
			"ack_input_tick": int(data.get("ack_input_tick", -1)),
			"respawn_revision": maxi(0, int(data.get("respawn_revision", 0))),
			"timestamp_ms": float(data.get("timestamp_ms", packet.get("timestamp_ms", 0.0))),
		}
	return {
		"timestamp_ms": float(packet.get("timestamp_ms", Time.get_ticks_msec())),
		"tick": maxi(0, int(packet.get("tick", 0))),
		"entities": sanitized_entities,
	}


static func snapshot_packet_is_sane(packet: Dictionary) -> bool:
	if packet.is_empty():
		return false
	var timestamp = packet.get("timestamp_ms")
	if timestamp != null and typeof(timestamp) not in [TYPE_FLOAT, TYPE_INT]:
		return false
	return true


static func chunk_snapshot_entities(
	entities: Dictionary,
	maximum_entities_per_packet: int = 4
) -> Array[Dictionary]:
	var limit := maxi(1, maximum_entities_per_packet)
	var peer_ids: Array = entities.keys()
	peer_ids.sort()
	var chunks: Array[Dictionary] = []
	var current: Dictionary = {}
	for raw_id in peer_ids:
		current[raw_id] = entities[raw_id]
		if current.size() >= limit:
			chunks.append(current)
			current = {}
	if not current.is_empty():
		chunks.append(current)
	return chunks
