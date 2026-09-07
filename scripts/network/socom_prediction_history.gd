class_name SocomPredictionHistory
extends RefCounted

## Compares the server's consumed input with that same predicted input. This
## class never moves a body, simulates physics or grants gameplay state.
const CAPACITY := 180
var samples: Dictionary = {}
var correction_offset := Vector3.ZERO
var last_acknowledged_tick := -1

func record(tick: int, position: Vector3, posture: int) -> void:
	samples[tick] = {"position": position, "posture": posture, "offset": correction_offset}
	while samples.size() > CAPACITY:
		samples.erase(samples.keys()[0])

func acknowledge(tick: int, server_position: Vector3) -> Dictionary:
	if tick <= last_acknowledged_tick or not server_position.is_finite():
		return {}
	last_acknowledged_tick = tick
	var sample: Dictionary = samples.get(tick, {})
	var result := {}
	if not sample.is_empty():
		var corrected_past := Vector3(sample.position) + correction_offset - Vector3(sample.offset)
		result = {"error": server_position - corrected_past, "posture": sample.posture}
	for key: int in samples.keys():
		if key <= tick: samples.erase(key)
	return result

func applied(displacement: Vector3) -> void:
	correction_offset += displacement

func clear() -> void:
	samples.clear()
	correction_offset = Vector3.ZERO
	last_acknowledged_tick = -1
