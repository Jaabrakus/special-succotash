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
		}
	return snapshot

static func packets(snapshot: Dictionary, timestamp_ms: int, tick: int, capacity: int) -> Array[Dictionary]:
	var chunks := Protocol.chunk_snapshot_entities(snapshot, capacity)
	var result: Array[Dictionary] = []
	for index in chunks.size():
		result.append({"timestamp_ms": timestamp_ms, "tick": tick,
			"chunk_index": index, "chunk_count": chunks.size(), "entities": chunks[index]})
	return result
