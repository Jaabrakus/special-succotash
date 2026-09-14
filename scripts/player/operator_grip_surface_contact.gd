extends RefCounted
## Geometry only. NEVER writes a bone, mount, movement or physics transform.
const Profile := preload("res://scripts/player/weapon_grip_surface_profile.gd")
const NODE_PATH := "CalibratedWeaponPivot/GripContactSurface/ForeEnd"
const META := &"grip_surface_profile"

static func attach(pivot: Node3D, weapon: Node3D, config: Dictionary) -> void:
	var id := String(config.get("weapon_id", ""))
	if id.is_empty() or id.validate_filename() != id: return
	var path := "res://config/weapon_grip_surfaces/" + id + ".tres"
	if not ResourceLoader.exists(path): return
	var profile := load(path) as Profile
	if profile == null or not profile.enabled or not profile.is_valid(): return
	if profile.expected_model != String(config.get("model_fbx", "")): return
	if pivot.has_node("GripContactSurface"): return
	var area := Area3D.new()
	area.name = "GripContactSurface"
	# Presentation probes query this shape directly. It must never intercept
	# server rays, detect the owner's body, or produce world collision forces.
	area.collision_layer = 0
	area.collision_mask = 0
	area.monitoring = false
	area.monitorable = false
	area.input_ray_pickable = false
	var collider := CollisionShape3D.new()
	collider.name = "ForeEnd"
	collider.shape = profile.shape.duplicate()
	collider.transform = profile.local_transform
	area.add_child(collider)
	pivot.add_child(area)
	weapon.set_meta(META, profile)

static func limit_curl(sk: Skeleton3D, weapon: Node3D, finger: String, requested: float) -> Dictionary:
	var unchanged := {"curl": requested, "status": "unconfigured"}
	if not is_instance_valid(sk) or not is_instance_valid(weapon): return unchanged
	if not weapon.has_meta(META): return unchanged
	var profile := weapon.get_meta(META, null) as Profile
	var collider := weapon.get_node_or_null(NODE_PATH) as CollisionShape3D
	if profile == null or not profile.enabled or not profile.is_valid() or collider == null: return unchanged
	if collider.disabled: return unchanged
	var shape := collider.shape as CapsuleShape3D
	if shape == null: return unchanged
	var surface_world := collider.global_transform
	if not surface_world.is_finite() or absf(surface_world.basis.determinant()) < .000001: return unchanged
	var to_surface := surface_world.affine_inverse() * sk.global_transform
	if not to_surface.is_finite(): return unchanged
	var bones: Array[int] = []
	var locals: Array[Transform3D] = []
	for segment in [1, 2, 3]:
		var bone := sk.find_bone("mixamorig_LeftHand" + finger + str(segment))
		if bone < 0: return unchanged
		bones.append(bone)
		var local := sk.get_bone_pose(bone)
		local.basis = sk.get_bone_rest(bone).basis.orthonormalized().scaled(local.basis.get_scale())
		locals.append(local)
	if sk.get_bone_parent(bones[1]) != bones[0] or sk.get_bone_parent(bones[2]) != bones[1]: return unchanged
	var parent := sk.get_bone_parent(bones[0])
	if parent < 0: return unchanged
	var start := to_surface * sk.get_bone_global_pose(parent)
	var radius := profile.finger_radius_m
	var gap := func(curl: float) -> float:
		return chain_gap(start, locals, curl, shape.radius, shape.height, radius)
	var result := bounded_curl(requested, gap, profile.sweep_steps, profile.refinement_steps)
	result["candidate_curl"] = result.curl
	result["correction_enabled"] = profile.correction_enabled
	if not profile.correction_enabled: result.curl = requested
	return result

static func bounded_curl(requested: float, gap: Callable, steps: int, refinements: int) -> Dictionary:
	# Sweep from open, not just an endpoint check: a curved path can pass into
	# and out of the gun. Keep the first safe interval and refine its boundary.
	if not is_finite(requested) or requested < 0 or requested > 1 or steps < 1 or refinements < 1:
		return {"curl": requested, "status": "invalid"}
	var initial: float = gap.call(0.0)
	if not is_finite(initial): return {"curl": requested, "status": "invalid"}
	if initial < 0.0:
		# Fingers cannot repair an already embedded palm/knuckle or a bad proxy.
		# Never force the arm or invent a new wrist offset to conceal this.
		return {"curl": requested, "status": "embedded_open_pose", "open_gap_m": initial}
	var lower := 0.0
	for step in range(1, steps + 1):
		var upper := requested * float(step) / float(steps)
		var distance: float = gap.call(upper)
		if not is_finite(distance): return {"curl": requested, "status": "invalid"}
		if distance < 0.0:
			for iteration in refinements:
				var middle := (lower + upper) * .5
				var middle_gap: float = gap.call(middle)
				if not is_finite(middle_gap): return {"curl": requested, "status": "invalid"}
				if middle_gap < 0.0: upper = middle
				else: lower = middle
			return {"curl": lower, "status": "contact_limited", "gap_m": float(gap.call(lower))}
		lower = upper
	return {"curl": requested, "status": "clear", "gap_m": float(gap.call(requested))}

static func chain_gap(start: Transform3D, locals: Array[Transform3D], curl: float,
		radius: float, height: float, finger_radius: float) -> float:
	var points := PackedVector3Array()
	var global := start
	var angles := Vector3(55.0, 75.0, 45.0)
	for segment in 3:
		var local := locals[segment]
		var scale := local.basis.get_scale()
		local.basis = (local.basis.orthonormalized() * Basis(Vector3.RIGHT, deg_to_rad(angles[segment] * curl))).scaled(scale)
		global *= local
		points.append(global.origin)
	# Target rig has no fingertip bone. Extend distal by its rest segment length;
	# this is explicitly a capsule approximation, not a skin collision mesh.
	points.append(global * locals[2].origin)
	return polyline_gap(points, radius, height, finger_radius)

static func polyline_gap(points: PackedVector3Array, radius: float, height: float, finger_radius: float) -> float:
	var minimum := INF
	var half_axis := maxf(0.0, height * .5 - radius)
	for segment in 3:
		var closest := Geometry3D.get_closest_points_between_segments(points[segment], points[segment + 1],
			Vector3(0, -half_axis, 0), Vector3(0, half_axis, 0))
		minimum = minf(minimum, closest[0].distance_to(closest[1]) - radius - finger_radius)
	return minimum
