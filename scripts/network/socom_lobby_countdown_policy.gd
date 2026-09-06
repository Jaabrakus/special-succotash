class_name SocomLobbyCountdownPolicy
extends RefCounted

static func advance(active: bool, ready: bool, remaining: float, shown: int, delta: float) -> Dictionary:
	var result := {"remaining": remaining, "shown": shown, "cancel": false, "broadcast": false, "start": false}
	if not active:
		return result
	if not ready:
		result.cancel = true
		result.broadcast = true
		return result
	result.remaining = maxf(0.0, remaining - delta)
	result.shown = ceili(result.remaining)
	result.broadcast = result.shown != shown
	result.start = result.remaining <= 0.0
	return result
