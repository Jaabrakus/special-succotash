class_name SocomReloadAuthority
extends RefCounted

## Deadline policy only. Host supplies trusted time/profile/context; no RPC or
## animation completion can write ammunition through this component.
var _active: Dictionary = {}

static func duration_seconds(config: Dictionary) -> float:
	var values: Dictionary = config.get("ballistics", {})
	var handling: Dictionary = config.get("handling_profile", {})
	return clampf(float(values.get("reload_duration_seconds",
		handling.get("reload_duration_seconds", 1.75))), 0.25, 10.0)

func begin(peer_id: int, context: String, duration: float, now_msec: int) -> bool:
	if peer_id <= 0 or context.is_empty() or _active.has(peer_id) or not is_finite(duration):
		return false
	_active[peer_id] = {
		"context": context,
		"deadline": now_msec + int(ceil(clampf(duration, 0.25, 10.0) * 1000.0)),
	}
	return true

func consume_ready(peer_id: int, context: String, now_msec: int) -> bool:
	var entry: Dictionary = _active.get(peer_id, {})
	if entry.is_empty():
		return false
	if String(entry.context) != context:
		cancel(peer_id)
		return false
	if now_msec < int(entry.deadline):
		return false
	cancel(peer_id)
	return true

func cancel(peer_id: int) -> void:
	_active.erase(peer_id)

func peer_ids() -> Array:
	return _active.keys()

func is_active(peer_id: int) -> bool:
	return _active.has(peer_id)

func is_due(peer_id: int, now_msec: int) -> bool:
	var entry: Dictionary = _active.get(peer_id, {})
	return not entry.is_empty() and now_msec >= int(entry.deadline)

func clear() -> void:
	_active.clear()
