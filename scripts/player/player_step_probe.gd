class_name SocomPlayerStepProbe
extends RefCounted

## Stateless shape queries only. CharacterBody applies any accepted lift.
static var profile: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://config/step_assist.json"))

static func lift(body: CharacterBody3D, horizontal_motion: Vector3) -> float:
	if horizontal_motion.length_squared() < 0.000001: return 0.0
	var hit := KinematicCollision3D.new()
	var origin := body.global_transform
	if not body.test_move(origin, horizontal_motion, hit): return 0.0
	if not _solid(hit.get_collider()) or hit.get_normal().y >= cos(body.floor_max_angle): return 0.0
	var maximum := float(profile.maximum_step_up_m)
	var contact := hit.get_position() + horizontal_motion.normalized() * 0.02
	var ray := PhysicsRayQueryParameters3D.create(Vector3(contact.x, origin.origin.y + maximum + 0.01, contact.z), Vector3(contact.x, origin.origin.y + 0.001, contact.z), body.collision_mask, [body.get_rid()])
	var top := body.get_world_3d().direct_space_state.intersect_ray(ray)
	if top.is_empty() or not _solid(top.collider) or Vector3(top.normal).y < cos(body.floor_max_angle): return 0.0
	var amount := Vector3(top.position).y - origin.origin.y + maxf(body.safe_margin * 2.0, 0.003)
	if amount < float(profile.minimum_lift_m) or amount > maximum: return 0.0
	if body.test_move(origin, Vector3.UP * amount): return 0.0
	# Recheck the actual rise and horizontal sweep, not only maximum headroom.
	var final := origin
	final.origin.y += amount
	if body.test_move(final, horizontal_motion): return 0.0
	return amount

static func _solid(collider: Object) -> bool:
	return collider is StaticBody3D and not collider is AnimatableBody3D

static func edge_snap_distance(body: CharacterBody3D) -> float:
	var maximum := float(profile.maximum_step_down_m)
	var hit := KinematicCollision3D.new()
	if not body.test_move(body.global_transform, Vector3.DOWN * maximum, hit): return -1.0
	if not _solid(hit.get_collider()) or hit.get_normal().y <= 0.05: return -1.0
	# A round capsule can touch a sharp tread corner with a non-floor normal.
	# Verify the actual flat top just inside that corner before preserving contact.
	var point := hit.get_position() - hit.get_normal().slide(Vector3.UP).normalized() * 0.02
	var ray := PhysicsRayQueryParameters3D.create(point + Vector3.UP * 0.03, point - Vector3.UP * 0.03, body.collision_mask, [body.get_rid()])
	var top := body.get_world_3d().direct_space_state.intersect_ray(ray)
	if top.is_empty() or not _solid(top.collider) or Vector3(top.normal).y < cos(body.floor_max_angle): return -1.0
	return clampf(-hit.get_travel().y, 0.0, maximum)
