class_name SocomAnatomicalHitResolver
extends RefCounted

## Resolves overlapping animated hurtboxes without changing their geometry.
## Environment still wins at the nearest depth. Arms are treated as thin,
## penetrable anatomy when the same ray continues into that operator's core;
## an arm outside the body silhouette remains a real limb hit.

const WORLD_AND_DAMAGE_MASK: int = 1 | (1 << 2)
const JOINT_OVERLAP_DEPTH_M := 0.14
const ARM_TO_CORE_PENETRATION_M := 0.62
const MAX_OVERLAP_HITS := 16


static func trace(
	space_state: PhysicsDirectSpaceState3D,
	origin: Vector3,
	finish: Vector3,
	exclude: Array[RID]
) -> Dictionary:
	var direction := (finish - origin).normalized()
	if direction.length_squared() < 0.99:
		return {}
	var working_exclude := exclude.duplicate()
	var candidates: Array[Dictionary] = []
	var first_receiver: Node = null

	for _index in MAX_OVERLAP_HITS:
		var query := PhysicsRayQueryParameters3D.create(origin, finish)
		query.exclude = working_exclude
		query.collision_mask = WORLD_AND_DAMAGE_MASK
		query.collide_with_areas = true
		var hit := space_state.intersect_ray(query)
		if hit.is_empty():
			break
		var collider: Object = hit.get("collider")
		# CharacterBody collision owns movement and must stay solid to players,
		# but its broad capsule is not damage anatomy. Continue through a damage
		# receiver's movement body so the animated HEAD/TORSO/LIMB areas decide
		# the hit region. Ordinary world bodies still stop the ray immediately.
		if (
			collider is CollisionObject3D
			and collider.has_method("take_bullet_damage_region")
			and not collider.has_method("get_hit_region")
		):
			working_exclude.append((collider as CollisionObject3D).get_rid())
			continue
		if collider == null or not collider.has_method("get_hit_region"):
			if candidates.is_empty():
				return hit
			break
		var receiver: Node = null
		if collider.has_method("get_damage_receiver"):
			receiver = collider.call("get_damage_receiver") as Node
		if candidates.is_empty():
			first_receiver = receiver
		elif receiver != first_receiver:
			break
		var candidate := hit.duplicate()
		candidate["hit_region"] = StringName(collider.call("get_hit_region"))
		candidate["damage_receiver"] = receiver
		candidate["distance"] = origin.distance_to(hit.position)
		candidates.append(candidate)
		if collider is CollisionObject3D:
			working_exclude.append((collider as CollisionObject3D).get_rid())
		else:
			break

	return choose_hit(candidates)


static func choose_hit(candidates: Array[Dictionary]) -> Dictionary:
	if candidates.is_empty():
		return {}
	var nearest := candidates[0]
	var nearest_distance := float(nearest.get("distance", 0.0))
	var nearest_region := StringName(nearest.get("hit_region", &""))
	if not _is_limb(nearest_region):
		return nearest
	var core_depth_limit := (
		ARM_TO_CORE_PENETRATION_M
		if _is_arm(nearest_region)
		else JOINT_OVERLAP_DEPTH_M
	)

	for candidate in candidates:
		var region := StringName(candidate.get("hit_region", &""))
		var depth := float(candidate.get("distance", nearest_distance)) - nearest_distance
		if depth > core_depth_limit:
			break
		if region in [&"TORSO", &"PELVIS"]:
			var resolved := candidate.duplicate()
			resolved["anatomical_override"] = true
			resolved["occluding_region"] = nearest_region
			resolved["overlap_depth_m"] = maxf(0.0, depth)
			return resolved
	return nearest


static func _is_arm(region: StringName) -> bool:
	return "ARM" in String(region)


static func _is_limb(region: StringName) -> bool:
	var text := String(region)
	return (
		"ARM" in text
		or "LEG" in text
		or "THIGH" in text
		or "CALF" in text
		or "FOOT" in text
	)
