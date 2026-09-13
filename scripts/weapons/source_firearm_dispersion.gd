extends RefCounted

## Original ZSealEtc 0x592260 direction algebra. No RNG/aim/state owner here.
## Golden original execution: config/reference/socom2_fire_direction_vectors.json.
const DISTRIBUTION := "source_signed_square_axes_v1"
const AXIS_RADIUS_FACTOR := 0.7070000171661377 # Original 0x3f34fdf4.


static func signed_square(value: float) -> float:
	return value * absf(value)


static func raw_direction(direction: Vector3, accuracy: Vector3, signed_draws: Vector2) -> Vector3:
	# Preserve original non-unit axes. Do not normalize away source pitch scaling.
	var right := direction.cross(Vector3.UP)
	var up := right.cross(direction)
	# Separate vector operations retain the original float32 multiply then add
	# boundaries; GDScript scalar float expressions otherwise use float64.
	var squares := signed_draws * signed_draws
	if signed_draws.x < 0.0:
		squares.x = -squares.x
	if signed_draws.y < 0.0:
		squares.y = -squares.y
	var offsets := squares * accuracy.z + Vector2(accuracy.x, accuracy.y)
	return (direction + right * offsets.x) + up * offsets.y


static func direction_in_envelope(direction: Vector3, tangent_radius: float, signed_draws: Vector2) -> Vector3:
	# Camera owns the center. Fit the source's square to the already-visible
	# circular bloom; do not reinterpret raw source dilation as angle degrees.
	var accuracy := Vector3(0.0, 0.0, maxf(tangent_radius, 0.0) * AXIS_RADIUS_FACTOR)
	return raw_direction(direction, accuracy, signed_draws).normalized()
