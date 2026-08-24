class_name SocomOperatorWeaponPoseGeometry
extends RefCounted

## Stateless stance, obstruction, and ground geometry for the visual weapon.
## This layer does not own camera aim, shots, damage, or character movement.

const STANDING_CHEST_ANCHOR_LOCAL := Vector3(0.0, 1.52, 0.0)
const CROUCHED_CHEST_ANCHOR_LOCAL := Vector3(0.0, 1.12, 0.0)
const PRONE_CHEST_ANCHOR_LOCAL := Vector3(0.0, 0.42, 0.02)


static func vector_from_data(raw: Variant) -> Vector3:
	if raw is Vector3:
		return raw
	if not raw is Dictionary:
		return Vector3.ZERO
	var data := raw as Dictionary
	return Vector3(
		float(data.get("x", 0.0)),
		float(data.get("y", 0.0)),
		float(data.get("z", 0.0))
	)


static func stable_chest_anchor(
	body: Node3D,
	posture: StringName,
	movement_state: StringName
) -> Vector3:
	var local_anchor := STANDING_CHEST_ANCHOR_LOCAL
	if posture == &"CROUCHED":
		local_anchor = CROUCHED_CHEST_ANCHOR_LOCAL
	elif posture == &"PRONE":
		local_anchor = PRONE_CHEST_ANCHOR_LOCAL
	if movement_state == &"DIVING":
		var dive_phase := (
			clampf(float(body.call("get_action_phase")), 0.0, 1.0)
			if body.has_method("get_action_phase")
			else 0.0
		)
		local_anchor = STANDING_CHEST_ANCHOR_LOCAL.lerp(
			PRONE_CHEST_ANCHOR_LOCAL,
			smoothstep(0.0, 0.70, dive_phase)
		)
	elif movement_state == &"ROLLING":
		var roll_phase := (
			clampf(float(body.call("get_action_phase")), 0.0, 1.0)
			if body.has_method("get_action_phase")
			else 0.0
		)
		local_anchor = CROUCHED_CHEST_ANCHOR_LOCAL.lerp(
			Vector3(0.0, 0.66, 0.0),
			sin(roll_phase * PI)
		)
	return body.global_transform * local_anchor


static func floor_clearance(
	body: Node3D,
	point: Vector3,
	probe_up_m: float,
	probe_down_m: float
) -> float:
	if body == null or body.get_world_3d() == null:
		return INF
	var excluded: Array[RID] = []
	if body is CollisionObject3D:
		excluded.append((body as CollisionObject3D).get_rid())
	# A vertical probe can meet a nearby wall before it reaches the supporting
	# floor. Skip steep collision owners and continue. Stopping at the first wall
	# made prone clearance report INF even though the operator was on valid ground.
	for _attempt in range(8):
		var query := PhysicsRayQueryParameters3D.create(
			point + Vector3.UP * probe_up_m,
			point - Vector3.UP * probe_down_m
		)
		query.collide_with_areas = false
		query.exclude = excluded
		var hit := body.get_world_3d().direct_space_state.intersect_ray(query)
		if hit.is_empty():
			return INF
		var normal := Vector3(hit.get("normal", Vector3.UP)).normalized()
		if normal.dot(Vector3.UP) >= 0.45:
			return (point - Vector3(hit.get("position", point))).dot(normal)
		var collider := hit.get("collider") as CollisionObject3D
		if collider == null:
			return INF
		var collider_rid := collider.get_rid()
		if collider_rid in excluded:
			return INF
		excluded.append(collider_rid)
	return INF


static func render_direction(
	aim_direction: Vector3,
	body_forward: Vector3,
	obstruction_hold_active: bool,
	last_clear_direction: Vector3,
	posture: StringName,
	standing_blocked_pitch_deg: float,
	crouched_blocked_pitch_deg: float,
	prone_blocked_pitch_deg: float,
	cover_amount: float
) -> Dictionary:
	var stable_aim := aim_direction.normalized()
	var next_clear_direction := last_clear_direction
	if not obstruction_hold_active and stable_aim.length_squared() > 0.50:
		next_clear_direction = stable_aim
	elif obstruction_hold_active:
		# A close surface can put the camera target behind the muzzle. Hold the last
		# clear direction so the visual rifle cannot reverse by almost 180 degrees.
		stable_aim = (
			last_clear_direction
			if last_clear_direction.length_squared() > 0.50
			else body_forward.normalized()
		)
	var blocked_pitch_deg := standing_blocked_pitch_deg
	if posture == &"CROUCHED":
		blocked_pitch_deg = crouched_blocked_pitch_deg
	elif posture == &"PRONE":
		blocked_pitch_deg = prone_blocked_pitch_deg
	var pitch_axis := stable_aim.cross(Vector3.UP).normalized()
	var low_ready_direction := (
		stable_aim.rotated(pitch_axis, -deg_to_rad(blocked_pitch_deg)).normalized()
		if pitch_axis.length_squared() > 0.50
		else stable_aim
	)
	if low_ready_direction.length_squared() < 0.50:
		low_ready_direction = stable_aim
	return {
		"direction": stable_aim.slerp(low_ready_direction, cover_amount).normalized(),
		"last_clear_direction": next_clear_direction,
	}
