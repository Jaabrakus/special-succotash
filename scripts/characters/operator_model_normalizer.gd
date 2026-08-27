class_name SocomOperatorModelNormalizer
extends RefCounted

## Shared visual-space normalization for imported operator rigs. Gameplay
## collision, movement, aim, hurtboxes, and server authority do not use this.

const TARGET_RIG_HEIGHT_M := 1.70
const TARGET_FORWARD := Vector3.BACK
const MIN_RIG_HEIGHT := 0.001


static func measure(model: Node3D, bone_map: Dictionary) -> Dictionary:
	if model == null:
		return {"ok": false, "error": "No model was provided."}
	var skeleton := _largest_skeleton(model)
	if skeleton == null:
		return {"ok": false, "error": "No Skeleton3D was found."}
	var skeleton_transform := _relative_transform(skeleton, model)
	var hips_value: Variant = _bone_point(skeleton, skeleton_transform, bone_map, "hips")
	var head_value: Variant = _bone_point(skeleton, skeleton_transform, bone_map, "head")
	var left_foot_value: Variant = _bone_point(skeleton, skeleton_transform, bone_map, "left_foot")
	var right_foot_value: Variant = _bone_point(skeleton, skeleton_transform, bone_map, "right_foot")
	var left_toe_value: Variant = _bone_point(skeleton, skeleton_transform, bone_map, "left_toe")
	var right_toe_value: Variant = _bone_point(skeleton, skeleton_transform, bone_map, "right_toe")
	if [hips_value, head_value, left_foot_value, right_foot_value, left_toe_value, right_toe_value].any(func(point): return point == null):
		return {"ok": false, "error": "The normalized skeleton landmarks are incomplete."}
	var hips: Vector3 = hips_value
	var head: Vector3 = head_value
	var left_foot: Vector3 = left_foot_value
	var right_foot: Vector3 = right_foot_value
	var left_toe: Vector3 = left_toe_value
	var right_toe: Vector3 = right_toe_value
	var foot_center: Vector3 = (left_foot + right_foot) * 0.5
	var toe_center: Vector3 = (left_toe + right_toe) * 0.5
	var rig_height := absf(head.y - foot_center.y)
	if rig_height < MIN_RIG_HEIGHT:
		return {"ok": false, "error": "Head-to-foot rig height is too small to normalize."}
	var forward := toe_center - foot_center
	forward.y = 0.0
	if forward.length_squared() < MIN_RIG_HEIGHT * MIN_RIG_HEIGHT:
		forward = TARGET_FORWARD
	else:
		forward = forward.normalized()
	var yaw := forward.signed_angle_to(TARGET_FORWARD, Vector3.UP)
	var scale_factor := TARGET_RIG_HEIGHT_M / rig_height
	var normalized_basis := Basis(Vector3.UP, yaw).scaled(Vector3.ONE * scale_factor)
	var source_anchor := Vector3(hips.x, foot_center.y, hips.z)
	var normalized_origin := -(normalized_basis * source_anchor)
	return {
		"ok": true,
		"skeleton_name": String(skeleton.name),
		"source_rig_height": rig_height,
		"target_rig_height": TARGET_RIG_HEIGHT_M,
		"scale_factor": scale_factor,
		"yaw_radians": yaw,
		"yaw_degrees": rad_to_deg(yaw),
		"source_anchor": source_anchor,
		"source_forward": forward,
		"normalized_origin": normalized_origin,
	}


static func apply(model: Node3D, bone_map: Dictionary) -> Dictionary:
	_stop_animation_players(model)
	model.transform = Transform3D.IDENTITY
	var metrics := measure(model, bone_map)
	if not bool(metrics.get("ok", false)):
		return metrics
	var yaw := float(metrics.get("yaw_radians", 0.0))
	var scale_factor := float(metrics.get("scale_factor", 1.0))
	var basis := Basis(Vector3.UP, yaw).scaled(Vector3.ONE * scale_factor)
	model.transform = Transform3D(basis, metrics.get("normalized_origin", Vector3.ZERO))
	return metrics


static func model_bounds(model: Node3D, prefer_skinned := true) -> AABB:
	if model == null:
		return AABB()
	var meshes := _mesh_instances(model)
	var selected: Array[MeshInstance3D] = []
	if prefer_skinned:
		for mesh_instance in meshes:
			if mesh_instance.skin != null:
				selected.append(mesh_instance)
	if selected.is_empty():
		selected = meshes
	var bounds := AABB()
	var has_bounds := false
	for mesh_instance in selected:
		if mesh_instance.mesh == null:
			continue
		var relative_transform := model.transform * _relative_transform(mesh_instance, model)
		var mesh_bounds: AABB = relative_transform * mesh_instance.mesh.get_aabb()
		bounds = bounds.merge(mesh_bounds) if has_bounds else mesh_bounds
		has_bounds = true
	return bounds


static func profile_data(metrics: Dictionary) -> Dictionary:
	if not bool(metrics.get("ok", false)):
		return {}
	var origin: Vector3 = metrics.get("normalized_origin", Vector3.ZERO)
	return {
		"contract": "SOCOM_OPERATOR_SPACE_V1",
		"target_rig_height_m": float(metrics.get("target_rig_height", TARGET_RIG_HEIGHT_M)),
		"source_rig_height": float(metrics.get("source_rig_height", 0.0)),
		"scale": float(metrics.get("scale_factor", 1.0)),
		"rotation_degrees": {
			"x": 0.0,
			"y": float(metrics.get("yaw_degrees", 0.0)),
			"z": 0.0,
		},
		"position": {"x": origin.x, "y": origin.y, "z": origin.z},
		"anchor": "hips_xz_and_average_feet_y",
		"forward": "+Z_FROM_AVERAGE_TOES",
	}


static func _bone_point(
	skeleton: Skeleton3D,
	skeleton_transform: Transform3D,
	bone_map: Dictionary,
	role: String
):
	var bone_name := String(bone_map.get(role, ""))
	var bone_index := skeleton.find_bone(bone_name)
	if bone_index < 0:
		return null
	return skeleton_transform * skeleton.get_bone_global_rest(bone_index).origin


static func _relative_transform(node: Node3D, root: Node3D) -> Transform3D:
	var result := Transform3D.IDENTITY
	var cursor: Node = node
	while cursor != null and cursor != root:
		if cursor is Node3D:
			result = (cursor as Node3D).transform * result
		cursor = cursor.get_parent()
	return result


static func _largest_skeleton(node: Node) -> Skeleton3D:
	var result: Skeleton3D
	if node is Skeleton3D:
		result = node as Skeleton3D
	for child in node.get_children():
		var candidate := _largest_skeleton(child)
		if candidate != null and (result == null or candidate.get_bone_count() > result.get_bone_count()):
			result = candidate
	return result


static func _mesh_instances(node: Node) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		result.append(node as MeshInstance3D)
	for child in node.get_children():
		result.append_array(_mesh_instances(child))
	return result


static func _stop_animation_players(node: Node) -> void:
	if node is AnimationPlayer:
		var player := node as AnimationPlayer
		player.stop()
		player.active = false
	for child in node.get_children():
		_stop_animation_players(child)
