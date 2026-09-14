class_name SourceFirearmTrace
extends RefCounted

## Pure source-only query adapter. Existing weapon/server callers own damage.
## See docs/SOURCE_FIREARM_TRACE_ADAPTER.md for geometry and ordering limits.
const QUERY_RANGE_SCALE := 1.1
const MAX_QUERIES := 128 # Adapter performance guard, not a recovered source cap.
const MAX_RECEIVER_NODES := 512


static func trace(
	space: PhysicsDirectSpaceState3D, origin: Vector3, direction: Vector3,
	maxrange: float, piercing: float, exclude: Array[RID], materials: Dictionary
) -> Array[Dictionary]:
	var impacts: Array[Dictionary] = []
	if space == null or not origin.is_finite() or not direction.is_finite():
		return impacts
	if not is_finite(maxrange) or maxrange <= 0.0 or not is_finite(piercing) or piercing < 0.0:
		return impacts
	var length_squared := direction.length_squared()
	if not is_finite(length_squared) or length_squared <= 0.000000000001:
		return impacts
	var forward := direction.normalized()
	var range_limit := _f32(maxrange)
	var endpoint := origin + forward * (range_limit * QUERY_RANGE_SCALE)
	if not endpoint.is_finite() or not is_finite(_f32(range_limit * range_limit)):
		return impacts
	var local_exclude: Array[RID] = exclude.duplicate()
	var hit_receivers: Dictionary = {}
	var previous_distance_squared := 0.0
	for query_index in MAX_QUERIES:
		var query := PhysicsRayQueryParameters3D.create(origin, endpoint)
		query.collide_with_areas = true
		query.collide_with_bodies = true
		query.hit_from_inside = true
		query.exclude = local_exclude
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			break
		var position: Vector3 = hit.get("position", Vector3(INF, INF, INF))
		var normal: Vector3 = hit.get("normal", Vector3(INF, INF, INF))
		if not position.is_finite() or not normal.is_finite():
			break
		var collider := hit.get("collider") as Node
		var rid: RID = hit.get("rid", RID())
		if not is_instance_valid(collider) or not rid.is_valid() or local_exclude.has(rid):
			break
		local_exclude.append(rid)
		# Movement capsules are not anatomy. Keep the first actual hurtbox;
		# do not reintroduce the legacy arm-to-core arbitration here.
		if collider is PhysicsBody3D and collider.has_method("take_bullet_damage_region") and not collider.has_method("get_hit_region"):
			continue
		var offset := position - origin
		var distance_squared := offset.length_squared()
		# Original candidate ordering: strictly farther and strictly inside R².
		if not is_finite(distance_squared) or offset.dot(forward) <= 0.0:
			break
		if distance_squared <= previous_distance_squared or distance_squared >= _f32(range_limit * range_limit):
			break
		previous_distance_squared = distance_squared
		var receiver := _anatomical_receiver(collider)
		if receiver != null and hit_receivers.has(receiver.get_instance_id()):
			continue
		var material := material_for(collider, receiver, materials)
		var coefficient: float = material.coefficient
		if coefficient == 1.0:
			continue # Original P=1 bypasses the ordinary impact handler.
		var range_after := reduced_range(range_limit, piercing, coefficient)
		var continues := distance_squared <= _f32(range_after * range_after)
		var stop_reason := "" if continues else "MATERIAL_RANGE"
		if receiver != null:
			hit_receivers[receiver.get_instance_id()] = true
			if not _exclude_receiver_colliders(receiver, local_exclude):
				continues = false
				stop_reason = "RECEIVER_SCAN_LIMIT"
		if query_index == MAX_QUERIES - 1 and continues:
			continues = false
			stop_reason = "QUERY_LIMIT"
		impacts.append({
			"entry_pos": position, "exit_pos": position, "normal": normal,
			"collider": collider, "rid": rid, "receiver": receiver,
			"is_target": receiver != null, "is_wallbang": not impacts.is_empty(),
			"source_material": material.name, "coefficient": coefficient,
			"range_limit": range_limit, "range_after": range_after,
			"distance_squared": distance_squared, "continues": continues,
			"trace_stop_reason": stop_reason,
		})
		range_limit = range_after
		if not continues:
			break
	return impacts


static func material_for(collider: Node, receiver: Node, materials: Dictionary) -> Dictionary:
	var name := "PERSON" if receiver != null else "UNKNOWN"
	if receiver == null and collider != null and collider.has_meta("source_material"):
		var tag: Variant = collider.get_meta("source_material")
		if tag is String or tag is StringName:
			name = String(tag).strip_edges().to_upper()
	if name == "UNKNOWN" or not materials.has(name):
		return {"name": "UNKNOWN", "coefficient": 0.0}
	var value: Variant = materials[name]
	if not (value is float or value is int):
		return {"name": "UNKNOWN", "coefficient": 0.0}
	var coefficient := float(value)
	if not is_finite(coefficient) or coefficient < 0.0 or coefficient > 1.0:
		return {"name": "UNKNOWN", "coefficient": 0.0}
	return {"name": name, "coefficient": _f32(coefficient)}


static func reduced_range(range_limit: float, piercing: float, coefficient: float) -> float:
	if not is_finite(range_limit) or range_limit <= 0.0 or not is_finite(piercing) or piercing < 0.0:
		return 0.0
	if not is_finite(coefficient) or coefficient < 0.0 or coefficient > 1.0:
		return 0.0
	var original := _f32(range_limit)
	var factor := _f32(_f32(0.1) * _f32(piercing))
	var candidate := _f32(_f32(original + _f32(original * factor)) * _f32(coefficient))
	if not is_finite(candidate):
		return 0.0
	return candidate if candidate < original else original


static func _anatomical_receiver(collider: Node) -> Node:
	if collider == null or not collider.has_method("get_damage_receiver"):
		return null
	var anatomical := collider.has_method("get_hit_region")
	if collider.has_method("is_anatomical_hurtbox"):
		anatomical = bool(collider.call("is_anatomical_hurtbox"))
	if not anatomical:
		return null
	var receiver: Variant = collider.call("get_damage_receiver")
	return receiver as Node if receiver is Node and is_instance_valid(receiver) else null


static func _exclude_receiver_colliders(receiver: Node, excludes: Array[RID]) -> bool:
	var pending: Array[Node] = [receiver]
	var visited := 0
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		visited += 1
		if visited > MAX_RECEIVER_NODES:
			return false
		if node is CollisionObject3D and (node == receiver or _anatomical_receiver(node) == receiver):
			var rid := (node as CollisionObject3D).get_rid()
			if not excludes.has(rid):
				excludes.append(rid)
		for child: Node in node.get_children():
			pending.append(child)
	return true


static func _f32(value: float) -> float:
	return PackedFloat32Array([value])[0]
