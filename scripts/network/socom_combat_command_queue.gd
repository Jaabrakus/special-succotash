class_name SocomCombatCommandQueue
extends RefCounted

var _shots: Dictionary = {}
var _sequences: Dictionary = {}
var _reloads: Dictionary = {}

func enqueue(peer: int, packet: Dictionary, capacity: int) -> bool:
	if typeof(packet.get("sequence")) != TYPE_INT:
		return false
	var sequence := int(packet.sequence)
	var queue: Array = _shots.get(peer, [])
	if sequence <= last_sequence(peer) or queue.size() >= capacity:
		return false
	queue.append(packet.duplicate(true))
	_shots[peer] = queue
	_sequences[peer] = sequence
	cancel_reload(peer)
	return true

func has_shots(peer: int) -> bool:
	return not (_shots.get(peer, []) as Array).is_empty()

func pop_ready(peer: int, weapon_ready: bool) -> Dictionary:
	if not weapon_ready or not has_shots(peer):
		return {}
	var queue: Array = _shots[peer]
	return queue.pop_front()

func defer_reload(peer: int) -> void:
	_reloads[peer] = true

func consume_reload(peer: int) -> bool:
	if has_shots(peer) or not reload_pending(peer):
		return false
	cancel_reload(peer)
	return true

func cancel_reload(peer: int) -> void:
	_reloads.erase(peer)

func reload_pending(peer: int) -> bool:
	return bool(_reloads.get(peer, false))

func reset_peer(peer: int, preserve_sequence: bool = false) -> void:
	_shots[peer] = []
	cancel_reload(peer)
	if not preserve_sequence:
		_sequences[peer] = -1

func remove_peer(peer: int) -> void:
	_shots.erase(peer)
	_sequences.erase(peer)
	cancel_reload(peer)

func peer_ids() -> Array:
	return _shots.keys()

func snapshot(peer: int) -> Array:
	return (_shots.get(peer, []) as Array).duplicate(true)

func last_sequence(peer: int) -> int:
	return int(_sequences.get(peer, -1))
