extends RefCounted

## Pure local-space drawing data. No input, camera, bloom state or shot writes.
const SHAPES := ["offset", "horizon", "tripod", "split_halo"]

static func build(shape: String, gap_px: float, style: Dictionary) -> Array[PackedVector2Array]:
	var strokes: Array[PackedVector2Array] = []
	var spacing := clampf(float(style.get("spacing_scale", 1.0)), 0.25, 3.0)
	var gap := maxf(gap_px, 0.0) * spacing
	match shape:
		"offset":
			# Original selected concept: paired side brackets and a lower datum.
			var arm := clampf(float(style.get("arm_length_px", 9.0)), 2.0, 24.0)
			strokes.append(PackedVector2Array([Vector2(-gap - arm, -5.0), Vector2(-gap, -5.0), Vector2(-gap, 4.0)]))
			strokes.append(PackedVector2Array([Vector2(gap + arm, -5.0), Vector2(gap, -5.0), Vector2(gap, 4.0)]))
			strokes.append(PackedVector2Array([Vector2(-4.0, gap + 4.0), Vector2(4.0, gap + 4.0)]))
			strokes.append(PackedVector2Array([Vector2(0.0, gap + 4.0), Vector2(0.0, gap + arm + 2.0)]))
		"horizon":
			# Shallow lower cradle, flat wings and one lower index. Open above aim.
			strokes.append(_arc(Vector2(0.0, -4.0), gap + 7.0, 28.0, 152.0, 28))
			var wing_y := (gap + 7.0) * 0.47 - 4.0
			strokes.append(PackedVector2Array([Vector2(-gap - 13.0, wing_y), Vector2(-gap - 5.0, wing_y)]))
			strokes.append(PackedVector2Array([Vector2(gap + 5.0, wing_y), Vector2(gap + 13.0, wing_y)]))
			strokes.append(PackedVector2Array([Vector2(0.0, gap + 8.0), Vector2(0.0, gap + 13.0)]))
		"tripod":
			# Three fixed-orientation hooks translate radially; never spin.
			var arm := clampf(float(style.get("arm_length_px", 9.0)), 2.0, 24.0)
			var hook := PackedVector2Array([
				Vector2(-5.0, gap + 2.0), Vector2(4.0, gap + 2.0),
				Vector2(7.0, gap + 5.0), Vector2(7.0, gap + arm + 3.0),
			])
			for index in 3:
				strokes.append(_rotate(hook, float(index) * TAU / 3.0))
		"split_halo":
			# Move fixed-radius fragments apart. Bloom does not thicken/stretch arcs.
			var fragment := _arc(Vector2(gap - 10.0 * spacing, 0.0), 17.0 * spacing, -26.0, 26.0, 16)
			for index in 4:
				strokes.append(_rotate(fragment, float(index) * PI * 0.5))
	return strokes

static func fade_stroke(stroke: PackedVector2Array, tint: Color, alpha_samples: Array) -> Dictionary:
	# Bounded subsegments let the original alpha ramp follow a bent custom mark.
	# Offset's cardinal outward axis keeps the alpha ramp stable as bloom opens.
	var points := PackedVector2Array()
	if stroke.is_empty():
		return {"points": points, "colors": PackedColorArray()}
	points.append(stroke[0])
	for index in range(1, stroke.size()):
		var start := stroke[index - 1]
		var end := stroke[index]
		var steps := clampi(int(ceil(start.distance_to(end))), 1, 32)
		for step in range(1, steps + 1):
			points.append(start.lerp(end, float(step) / float(steps)))
	var inner := INF
	var outer := 0.0
	var axis := Vector2.RIGHT if absf(stroke[0].x) > absf(stroke[0].y) else Vector2.DOWN
	for point in points:
		inner = minf(inner, absf(point.dot(axis)))
		outer = maxf(outer, absf(point.dot(axis)))
	var colors := PackedColorArray()
	for point in points:
		var progress := (absf(point.dot(axis)) - inner) / (outer - inner) if outer > inner else 0.0
		var color := tint
		color.a *= sample_alpha(alpha_samples, progress)
		colors.append(color)
	return {"points": points, "colors": colors}

static func sample_alpha(alpha_samples: Array, progress: float) -> float:
	if alpha_samples.is_empty():
		return 1.0
	var position := clampf(progress, 0.0, 1.0) * float(alpha_samples.size() - 1)
	var index := int(floor(position))
	return clampf(lerpf(float(alpha_samples[index]), float(alpha_samples[mini(index + 1, alpha_samples.size() - 1)]), position - float(index)) / 255.0, 0.0, 1.0)

static func _arc(center: Vector2, radius: float, start_deg: float, end_deg: float, segments: int) -> PackedVector2Array:
	var points := PackedVector2Array()
	for index in segments + 1:
		var angle := deg_to_rad(lerpf(start_deg, end_deg, float(index) / float(segments)))
		points.append(center + Vector2(cos(angle), sin(angle)) * radius)
	return points

static func _rotate(points: PackedVector2Array, angle: float) -> PackedVector2Array:
	var rotated := PackedVector2Array()
	for point in points:
		rotated.append(point.rotated(angle))
	return rotated
