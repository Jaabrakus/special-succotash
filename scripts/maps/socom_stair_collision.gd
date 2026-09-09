class_name SocomStairCollision
extends RefCounted

## Map-owned collision only. The character keeps ordinary locomotion.
const GROUP := &"walkable_stairs"
const MODES := ["stair_ramp", "stair_ramp_positive_z", "stair_ramp_positive_x", "stair_ramp_negative_x"]

static func points(bounds: AABB, mode: String = "stair_ramp", scale_value := Vector3.ONE) -> PackedVector3Array:
	var result := PackedVector3Array()
	for x in 2:
		for z in 2:
			var bottom := bounds.position + Vector3(bounds.size.x * x, 0, bounds.size.z * z)
			result.append(bottom * scale_value)
			var high := z == 0
			if mode == "stair_ramp_positive_z": high = z == 1
			elif mode == "stair_ramp_positive_x": high = x == 1
			elif mode == "stair_ramp_negative_x": high = x == 0
			if high: result.append((bottom + Vector3.UP * bounds.size.y) * scale_value)
	return result

static func is_stair(collider: Object) -> bool:
	var node := collider as Node
	while node != null:
		if node.is_in_group(GROUP): return true
		node = node.get_parent()
	return false
