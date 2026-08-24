class_name SocomCameraPassagePolicy
extends RefCounted

## Camera-only passage contract.
##
## Geometry is a hard blocker by default. A mapper may deliberately add a
## collision object (or one of its parents) to `camera_soft_occluder` to let the
## rendered camera pass/fade it. This does not change player, bullet or server
## collision layers.

const SOFT_OCCLUDER_GROUP := &"camera_soft_occluder"
const SOFT_OCCLUDER_META := &"camera_soft_occluder"
const MAX_SOFT_CONTACTS_PER_CAST := 6


func cast_camera_motion(
	world: World3D,
	shape: Shape3D,
	anchor: Vector3,
	destination: Vector3,
	margin: float,
	initial_exclude: Array[RID]
) -> Dictionary:
	var effective_exclude: Array[RID] = initial_exclude.duplicate()
	var skipped_soft: Array[RID] = []
	var motion := destination - anchor
	if world == null or shape == null or motion.length_squared() <= 0.0000001:
		return {
			"safe_fraction": 1.0,
			"exclude": effective_exclude,
			"soft_occluder_count": 0,
		}
	var space := world.direct_space_state
	for _attempt in range(MAX_SOFT_CONTACTS_PER_CAST + 1):
		var motion_query := PhysicsShapeQueryParameters3D.new()
		motion_query.shape = shape
		motion_query.transform = Transform3D(Basis.IDENTITY, anchor)
		motion_query.motion = motion
		motion_query.margin = margin
		motion_query.exclude = effective_exclude
		motion_query.collide_with_areas = false
		var result: PackedFloat32Array = space.cast_motion(motion_query)
		var safe_fraction := result[0] if result.size() >= 1 else 1.0
		if safe_fraction >= 0.999:
			return {
				"safe_fraction": safe_fraction,
				"exclude": effective_exclude,
				"soft_occluder_count": skipped_soft.size(),
			}

		# Probe the camera volume immediately beyond the reported contact. If the
		# contact is explicitly soft, exclude only that RID and repeat the exact
		# same cast. Any untagged geometry remains a hard boundary.
		var probe_fraction := minf(safe_fraction + 0.0025, 1.0)
		var probe := PhysicsShapeQueryParameters3D.new()
		probe.shape = shape
		probe.transform = Transform3D(
			Basis.IDENTITY,
			anchor + motion * probe_fraction
		)
		probe.margin = margin + 0.01
		probe.exclude = effective_exclude
		probe.collide_with_areas = false
		var overlaps := space.intersect_shape(probe, 16)
		var added_soft := false
		for overlap in overlaps:
			var collider: Variant = overlap.get("collider")
			var collider_rid: RID = overlap.get("rid", RID())
			if not collider is Node or not is_soft_occluder(collider as Node):
				continue
			if not collider_rid.is_valid() or collider_rid in effective_exclude:
				continue
			effective_exclude.append(collider_rid)
			skipped_soft.append(collider_rid)
			added_soft = true
		if not added_soft:
			return {
				"safe_fraction": safe_fraction,
				"exclude": effective_exclude,
				"soft_occluder_count": skipped_soft.size(),
			}
	return {
		"safe_fraction": 0.0,
		"exclude": effective_exclude,
		"soft_occluder_count": skipped_soft.size(),
	}


func is_soft_occluder(node: Node) -> bool:
	var current := node
	while current != null:
		if current.is_in_group(SOFT_OCCLUDER_GROUP):
			return true
		if bool(current.get_meta(SOFT_OCCLUDER_META, false)):
			return true
		current = current.get_parent()
	return false
