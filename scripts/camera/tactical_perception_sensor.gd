class_name SocomTacticalPerceptionSensor
extends Node3D

## Non-rendering perception probe that shares the visible camera frustum.
## It never draws a second view and never authorizes damage or enemy knowledge.

const TARGET_GROUP := &"tactical_perception_target"

var view_camera: Camera3D
var observer: Node3D
var observer_team_id: int = -1
var allow_friendly_through_walls: bool = false
var scan_interval_seconds: float = 0.10
var _scan_remaining: float = 0.0
var _contacts: Array[Dictionary] = []


func configure(source_camera: Camera3D, source_observer: Node3D) -> void:
	view_camera = source_camera
	observer = source_observer
	observer_team_id = _team_id(observer)


func _physics_process(delta: float) -> void:
	_scan_remaining -= maxf(delta, 0.0)
	if _scan_remaining > 0.0:
		return
	_scan_remaining = scan_interval_seconds
	_contacts = scan_candidates(get_tree().get_nodes_in_group(TARGET_GROUP))


func scan_candidates(candidates: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if view_camera == null or observer == null or not is_inside_tree():
		return result
	for candidate_value in candidates:
		if not candidate_value is Node3D:
			continue
		var candidate := candidate_value as Node3D
		if candidate == observer or not candidate.is_inside_tree():
			continue
		var point := _perception_point(candidate)
		if not view_camera.is_position_in_frustum(point):
			continue
		var target_team := _team_id(candidate)
		var relationship := &"UNKNOWN"
		if observer_team_id >= 0 and target_team >= 0:
			relationship = &"FRIENDLY" if target_team == observer_team_id else &"ENEMY"
		var line_of_sight := _has_line_of_sight(candidate, point)
		# Raw enemy silhouettes through walls are intentionally forbidden. A
		# future server-approved spotted event can become a separate input.
		if not line_of_sight and not (
			relationship == &"FRIENDLY" and allow_friendly_through_walls
		):
			continue
		result.append({
			"node": candidate,
			"relationship": relationship,
			"line_of_sight": line_of_sight,
			"screen_position": view_camera.unproject_position(point),
			"distance_m": view_camera.global_position.distance_to(point),
		})
	return result


func get_contacts() -> Array[Dictionary]:
	return _contacts.duplicate(true)


func _has_line_of_sight(candidate: Node3D, point: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(view_camera.global_position, point)
	query.collide_with_areas = false
	if observer is CollisionObject3D:
		query.exclude = [(observer as CollisionObject3D).get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return true
	var collider: Variant = hit.get("collider")
	if not collider is Node:
		return false
	var current := collider as Node
	while current != null:
		if current == candidate:
			return true
		current = current.get_parent()
	return false


func _perception_point(candidate: Node3D) -> Vector3:
	var anchor := candidate.get_node_or_null("HeadMarker") as Node3D
	if anchor != null:
		return anchor.global_position
	return candidate.global_position + Vector3.UP * 1.35


func _team_id(node: Node) -> int:
	if node == null:
		return -1
	if node.has_meta("team_id"):
		return int(node.get_meta("team_id"))
	for property in node.get_property_list():
		if StringName(property.get("name", &"")) == &"team_id":
			return int(node.get("team_id"))
	return -1
