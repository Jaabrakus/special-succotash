class_name SocomSnapshotEncoder
extends RefCounted

const Protocol := preload("res://scripts/network/socom_network_protocol.gd")

## Read-only projection of explicit operators; no transport or scene ownership.
static func capture(operators: Dictionary, peer_ids: Array) -> Dictionary:
	var snapshot := {}
	for raw_id in peer_ids:
		var operator: Variant = operators.get(raw_id)
		if operator == null:
			continue
		snapshot[raw_id] = {
			"position": operator.global_position, "yaw": operator.rotation.y,
			"velocity": operator.velocity, "posture": operator.posture,
			"health": operator.current_health, "alive": operator.alive,
			"ack_input_tick": operator.consumed_input_tick,
			"respawn_revision": operator.respawn_revision,
			"presentation": {"motion_state": operator.motion_state,
				"aim_angles": operator.network_aim_angles,
				"desired_movement": operator.desired_movement_direction,
				"movement_strength": operator.movement_input_strength,
				"peek": operator.peek_amount},
		}
	return snapshot

static func packets(snapshot: Dictionary, timestamp_ms: int, tick: int, capacity: int) -> Array[Dictionary]:
	var chunks := Protocol.chunk_snapshot_entities(snapshot, capacity)
	var result: Array[Dictionary] = []
	for index in chunks.size():
		result.append({"timestamp_ms": timestamp_ms, "tick": tick,
			"chunk_index": index, "chunk_count": chunks.size(), "entities": chunks[index]})
	return result
