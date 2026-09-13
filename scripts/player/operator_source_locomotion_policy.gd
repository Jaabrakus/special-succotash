extends RefCounted
## Data-only source-range adapter owned by the existing animation graph.
## Native A/B values are verified; this linear weighting law is an adapter,
## not a recovered implementation of the original PS2 controller.

var entries: Dictionary = {}

func register(prefix: StringName, suffix: StringName, clip_name: StringName, path: String) -> void:
	if not path.ends_with(".tres") or not ResourceLoader.exists(path):
		return
	var animation := load(path) as Animation
	if animation == null:
		return
	var marker: Variant = animation.get_meta("seal_reference", false)
	if not marker is bool or not marker:
		return
	var settings: Variant = animation.get_meta("source_settings", {})
	if not settings is Dictionary:
		return
	var start: Variant = settings.get("transition_speed_A")
	var end: Variant = settings.get("transition_speed_B")
	if not (start is float or start is int) or not (end is float or end is int):
		return
	if not is_finite(float(start)) or not is_finite(float(end)) or float(start) < 0.0 or float(end) <= float(start):
		return
	entries[String(prefix) + "/" + String(suffix)] = {
		"clip": clip_name, "start": float(start), "end": float(end),
		"source": animation.get_meta("source_name", ""), "length": animation.length,
	}

func complete() -> bool:
	for prefix in ["walk", "jog", "run"]:
		for suffix in ["forward", "backward", "left", "right"]:
			if not entries.has(prefix + "/" + suffix):
				return false
	return true

func tier_blends(direction: Vector2, speed_mps: float) -> Vector2:
	if not direction.is_finite() or not is_finite(speed_mps) or not complete():
		return Vector2.ZERO
	var weights := directional_weights(direction)
	var result := Vector2.ZERO
	for suffix in weights:
		for tier in 2:
			var row: Dictionary = entries[("jog/" if tier == 0 else "run/") + String(suffix)]
			result[tier] += float(weights[suffix]) * clampf((speed_mps - float(row.start)) / (float(row.end) - float(row.start)), 0.0, 1.0)
	return result

static func directional_weights(direction: Vector2) -> Dictionary:
	var total := absf(direction.x) + absf(direction.y)
	if total < 0.00001:
		return {&"forward": 1.0}
	var result := {}
	if absf(direction.x) > 0.00001:
		result[&"right" if direction.x > 0.0 else &"left"] = absf(direction.x) / total
	if absf(direction.y) > 0.00001:
		result[&"forward" if direction.y > 0.0 else &"backward"] = absf(direction.y) / total
	return result

func selected_clip(direction: Vector2, jog_blend: float, run_blend: float) -> StringName:
	var weights := Vector3((1.0 - run_blend) * (1.0 - jog_blend), (1.0 - run_blend) * jog_blend, run_blend)
	var tier := 0 if weights.x >= maxf(weights.y, weights.z) else (1 if weights.y >= weights.z else 2)
	var prefix: String = ["walk", "jog", "run"][tier]
	var suffix := "forward"
	if absf(direction.x) > absf(direction.y):
		suffix = "right" if direction.x > 0.0 else "left"
	elif direction.y < 0.0:
		suffix = "backward"
	return StringName(entries.get(prefix + "/" + suffix, {}).get("clip", ""))
