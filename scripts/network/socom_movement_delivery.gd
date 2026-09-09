class_name SocomMovementDelivery
extends RefCounted

## Bounded transport redundancy only; never simulates or grants movement.
const Protocol := preload("res://scripts/network/socom_network_protocol.gd")
const PROFILE_PATH := "res://config/network/movement_delivery.json"
const STRIDE := 32
const FLAGS := ["jump", "jump_held", "dive", "roll", "prone", "crouch", "crouch_released"]
var profile: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PROFILE_PATH))
var history: Array[Dictionary] = []
var epoch := -1

func outgoing(packet: Dictionary, respawn_epoch: int) -> Dictionary:
	if epoch != respawn_epoch:
		history.clear()
		epoch = respawn_epoch
	# Paused input can resend the same tick. It must not contain itself as history.
	while not history.is_empty() and int(history.back().tick) >= int(packet.tick):
		history.pop_back()
	var result := packet.duplicate()
	var bytes := PackedByteArray()
	bytes.resize(history.size() * STRIDE)
	for index in history.size():
		var previous := history[index]
		var start := index * STRIDE
		bytes.encode_s64(start, int(previous.tick))
		bytes.encode_float(start + 8, previous.move.x)
		bytes.encode_float(start + 12, previous.move.y)
		bytes.encode_float(start + 16, previous.aim_yaw)
		bytes.encode_float(start + 20, previous.aim_pitch)
		bytes.encode_float(start + 24, previous.peek)
		var bits := 0
		for flag in FLAGS.size():
			if bool(previous.get(FLAGS[flag], false)): bits |= 1 << flag
		bytes.encode_u16(start + 28, bits)
		bytes[start + 30] = int(previous.direction_held)
		bytes[start + 31] = int(previous.get("peek_held", 0))
	result["movement_history"] = bytes
	result["movement_epoch"] = respawn_epoch
	if history.is_empty() or int(packet.tick) > int(history.back().tick):
		history.append(packet.duplicate())
	while history.size() > clampi(int(profile.history_commands), 0, 11): history.pop_front()
	return result

func incoming(packet: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not Protocol.movement_packet_is_sane(packet): return result
	var data: Variant = packet.get("movement_history", PackedByteArray())
	if not data is PackedByteArray: return result
	var bytes: PackedByteArray = data
	if bytes.size() > 11 * STRIDE or bytes.size() % STRIDE != 0: return result
	var last_tick := -1
	for index in bytes.size() / STRIDE:
		var start := index * STRIDE
		var tick := bytes.decode_s64(start)
		var bits := bytes.decode_u16(start + 28)
		if tick < 0 or tick <= last_tick or tick >= int(packet.tick) or bits > 127: return []
		var previous := {"tick": tick, "move": Vector2(bytes.decode_float(start + 8), bytes.decode_float(start + 12)),
			"aim_yaw": bytes.decode_float(start + 16), "aim_pitch": bytes.decode_float(start + 20),
			"peek": bytes.decode_float(start + 24), "direction_held": int(bytes[start + 30]), "peek_held": int(bytes[start + 31])}
		for flag in FLAGS.size(): previous[FLAGS[flag]] = bool(bits & (1 << flag))
		if not Protocol.movement_packet_is_sane(previous): return []
		result.append(previous)
		last_tick = tick
	result.append(packet)
	return result
