extends SceneTree

const TargetDummyScript := preload("res://scripts/combat/lab_leak_target_dummy.gd")
const AnatomicalHitResolver := preload("res://scripts/combat/socom_anatomical_hit_resolver.gd")

var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var world_root := Node3D.new()
	root.add_child(world_root)
	var dummy := TargetDummyScript.new()
	dummy.name = "FrontDistributionTarget"
	world_root.add_child(dummy)
	await process_frame
	await physics_frame

	var rig: Node3D = dummy.get_hurtbox_rig()
	_expect(rig != null, "animated hurtbox rig exists")
	if rig == null:
		_finish()
		return
	_print_hurtbox_layout(rig)

	var counts: Dictionary = {}
	var central_counts: Dictionary = {}
	var hit_count := 0
	var central_hit_count := 0
	var printed_limb_samples := 0
	for y_index in range(19):
		var y := 0.20 + float(y_index) * 0.09
		for x_index in range(15):
			var x := -0.49 + float(x_index) * 0.07
			var hit := AnatomicalHitResolver.trace(
				world_root.get_world_3d().direct_space_state,
				Vector3(x, y, 3.0),
				Vector3(x, y, -3.0),
				[]
			)
			var region := StringName(hit.get("hit_region", &"MISS"))
			counts[region] = int(counts.get(region, 0)) + 1
			if region != &"MISS":
				hit_count += 1
			# The standing dummy's authored chest spans roughly 1.30-1.72 m.
			# Keep the audit on that band so valid thigh hits are never counted as
			# chest-classification failures.
			if absf(x) <= 0.28 and y >= 1.28 and y <= 1.72:
				central_counts[region] = int(central_counts.get(region, 0)) + 1
				if region != &"MISS":
					central_hit_count += 1
				if _is_limb(region) and printed_limb_samples < 8:
					print(
						"HURTBOX_FRONT_LIMB_SAMPLE x=%.2f y=%.2f resolved=%s raw=%s"
						% [x, y, String(region), str(_raw_regions(
							world_root.get_world_3d().direct_space_state,
							Vector3(x, y, 3.0),
							Vector3(x, y, -3.0)
						))]
					)
					printed_limb_samples += 1

	var central_limb_hits := 0
	for raw_region in central_counts:
		if _is_limb(StringName(raw_region)):
			central_limb_hits += int(central_counts[raw_region])
	var central_limb_ratio := (
		float(central_limb_hits) / float(central_hit_count)
		if central_hit_count > 0
		else 0.0
	)
	print(
		"HURTBOX_FRONT_DISTRIBUTION total=%s central=%s central_limb_ratio=%.3f"
		% [str(counts), str(central_counts), central_limb_ratio]
	)
	_expect(hit_count > 0, "front grid intersects the animated target")
	_expect(central_hit_count > 0, "central chest grid intersects damage anatomy")
	_expect(
		central_limb_ratio <= 0.20,
		"central chest shots do not classify predominantly as limb damage"
	)
	_audit_side_chest(world_root)

	dummy.queue_free()
	await process_frame
	_finish()


func _audit_side_chest(world_root: Node3D) -> void:
	var counts: Dictionary = {}
	var hit_count := 0
	var limb_count := 0
	var printed_samples := 0
	for y_index in 6:
		var y := 1.28 + float(y_index) * 0.08
		for z_index in 9:
			var z := -0.28 + float(z_index) * 0.07
			var origin := Vector3(3.0, y, z)
			var finish := Vector3(-3.0, y, z)
			var hit := AnatomicalHitResolver.trace(
				world_root.get_world_3d().direct_space_state,
				origin,
				finish,
				[]
			)
			var region := StringName(hit.get("hit_region", &"MISS"))
			counts[region] = int(counts.get(region, 0)) + 1
			if region != &"MISS":
				hit_count += 1
			if _is_limb(region):
				limb_count += 1
				if printed_samples < 8:
					print(
						"HURTBOX_SIDE_LIMB_SAMPLE z=%.2f y=%.2f resolved=%s raw=%s"
						% [z, y, String(region), str(_raw_regions(
							world_root.get_world_3d().direct_space_state,
							origin,
							finish
						))]
					)
					printed_samples += 1
	var ratio := float(limb_count) / float(hit_count) if hit_count > 0 else 0.0
	print("HURTBOX_SIDE_DISTRIBUTION counts=%s limb_ratio=%.3f" % [str(counts), ratio])
	_expect(
		ratio <= 0.20,
		"side chest shots crossing an arm resolve to the operator core"
	)


func _is_limb(region: StringName) -> bool:
	var text := String(region)
	return (
		"ARM" in text
		or "LEG" in text
		or "THIGH" in text
		or "CALF" in text
		or "FOOT" in text
	)


func _raw_regions(
	space_state: PhysicsDirectSpaceState3D,
	origin: Vector3,
	finish: Vector3
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var excluded: Array[RID] = []
	for _index in 16:
		var query := PhysicsRayQueryParameters3D.create(origin, finish)
		query.exclude = excluded
		query.collision_mask = 1 | (1 << 2)
		query.collide_with_areas = true
		var hit := space_state.intersect_ray(query)
		if hit.is_empty():
			break
		var collider: Object = hit.get("collider")
		if collider == null or not collider.has_method("get_hit_region"):
			break
		result.append({
			"region": StringName(collider.call("get_hit_region")),
			"distance": origin.distance_to(Vector3(hit.get("position", origin))),
		})
		if collider is CollisionObject3D:
			excluded.append((collider as CollisionObject3D).get_rid())
		else:
			break
	return result


func _print_hurtbox_layout(rig: Node3D) -> void:
	for area: Area3D in rig.get_hurtbox_areas():
		var shape_node: CollisionShape3D = null
		for child in area.get_children():
			if child is CollisionShape3D:
				shape_node = child as CollisionShape3D
				break
		if shape_node == null or shape_node.shape == null:
			continue
		var dimensions := "unknown"
		if shape_node.shape is CapsuleShape3D:
			var capsule := shape_node.shape as CapsuleShape3D
			dimensions = "capsule r=%.3f h=%.3f" % [capsule.radius, capsule.height]
		elif shape_node.shape is SphereShape3D:
			dimensions = "sphere r=%.3f" % (shape_node.shape as SphereShape3D).radius
		elif shape_node.shape is BoxShape3D:
			dimensions = "box size=%s" % str((shape_node.shape as BoxShape3D).size)
		print(
			"HURTBOX_FRONT_AREA region=%s pos=%s y_axis=%s %s"
			% [
				String(area.get_hit_region()),
				str(area.global_position),
				str(area.global_basis.y),
				dimensions,
			]
		)


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("HURTBOX_FRONT_CHECK PASS ", label)
	else:
		failures.append(label)
		push_error("HURTBOX_FRONT_CHECK FAIL %s" % label)


func _finish() -> void:
	if failures.is_empty():
		print("HURTBOX_FRONT_DISTRIBUTION_REGRESSION PASS")
		quit(0)
	else:
		print("HURTBOX_FRONT_DISTRIBUTION_REGRESSION FAIL ", failures)
		quit(1)
