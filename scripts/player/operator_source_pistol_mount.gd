extends RefCounted

## Pure contact calibration. The existing weapon owner remains the only writer.
## Offset units are metres, not the imported skeleton's often tiny bone units.
const MAX_PALM_OFFSET_M := 0.08

static func contact_transform(palm_world: Transform3D, enabled: bool, offset_m: Vector3) -> Transform3D:
	if not enabled or offset_m == Vector3.ZERO or not offset_m.is_finite():
		return palm_world
	var result := palm_world
	result.origin += palm_world.basis.orthonormalized() * offset_m.limit_length(MAX_PALM_OFFSET_M)
	return result
