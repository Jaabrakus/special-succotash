class_name SocomImportedMapAssetBuilder
extends RefCounted

## Construction only: imported GLB visuals, bounds and requested static collision.
## MapRuntime keeps document dispatch and collision/camera policies. AssetLibrary
## keeps file loading. This component never edits maps or player state.
const MapDocument := preload("res://scripts/maps/socom_map_document.gd")
const MapAssetLibrary := preload("res://scripts/maps/socom_map_asset_library.gd")
const StairCollision := preload("res://scripts/maps/socom_stair_collision.gd")
const Materials := preload("res://scripts/maps/socom_map_surface_materials.gd")


static func build(object: Dictionary, editor_preview: bool) -> Node3D:
	var body := StaticBody3D.new()
	body.name = String(object.get("name", "Imported Community Asset")).validate_node_name()
	body.position = MapDocument.data_to_vector(object.get("position", {}))
	body.rotation_degrees = MapDocument.data_to_vector(object.get("rotation_degrees", {}))
	body.set_meta("map_object_id", String(object.get("id", "")))
	body.set_meta("map_object_type", StringName(object.get("type", "")))
	var size := MapDocument.data_to_vector(object.get("size", {}), Vector3.ONE)
	var properties: Dictionary = object.get("properties", {})
	var asset_path := String(properties.get("asset_path", ""))
	var load_result := MapAssetLibrary.instantiate_asset(asset_path)
	if not bool(load_result.get("ok", false)):
		if editor_preview:
			_add_missing_asset_placeholder(body, size, String(load_result.get("message", "Missing GLB")))
		return body
	var content := load_result.get("scene") as Node3D
	content.name = "ImportedContent"
	body.add_child(content)
	var original_bounds := _combined_mesh_bounds(content)
	content.scale = size
	Materials.apply_imported_yard_finish(content, properties)
	var collision_mode := String(properties.get("collision_mode", "box"))
	if collision_mode in StairCollision.MODES:
		body.add_to_group(StairCollision.GROUP)
		# Discard embedded solid colliders for this explicit collision replacement.
		# Keep meshes/materials intact. Do not silently convert arbitrary assets.
		for found: Node in content.find_children("*", "CollisionShape3D", true, false):
			(found as CollisionShape3D).disabled = true
		var collision := CollisionShape3D.new()
		collision.name = "StairTraversalCollision"
		var shape := ConvexPolygonShape3D.new()
		shape.points = StairCollision.points(original_bounds, collision_mode, size)
		collision.shape = shape
		body.add_child(collision)
	elif editor_preview or collision_mode == "box":
		var collision := CollisionShape3D.new()
		collision.name = "EditorSelectionCollision" if editor_preview else "CollisionShape3D"
		var shape := BoxShape3D.new()
		var scaled_bounds_size := Vector3(
			maxf(original_bounds.size.x * absf(size.x), 0.1),
			maxf(original_bounds.size.y * absf(size.y), 0.1),
			maxf(original_bounds.size.z * absf(size.z), 0.1)
		)
		shape.size = scaled_bounds_size
		collision.shape = shape
		collision.position = Vector3(
			(original_bounds.position.x + original_bounds.size.x * 0.5) * size.x,
			(original_bounds.position.y + original_bounds.size.y * 0.5) * size.y,
			(original_bounds.position.z + original_bounds.size.z * 0.5) * size.z
		)
		body.add_child(collision)
	elif collision_mode == "detailed_mesh":
		for found: Node in content.find_children("*", "MeshInstance3D", true, false):
			var mesh_instance := found as MeshInstance3D
			if mesh_instance.mesh != null:
				mesh_instance.create_trimesh_collision()
	# Explicit saved uniform-collider material only. No texture/name inference.
	if properties.get("source_material") is String:
		body.set_meta("source_material", properties.source_material)
		for collider: Node in content.find_children("*", "StaticBody3D", true, false):
			collider.set_meta("source_material", properties.source_material)
	return body


static func _combined_mesh_bounds(content: Node3D) -> AABB:
	var combined := AABB(Vector3.ZERO, Vector3.ONE)
	var has_bounds := false
	for found: Node in content.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := found as MeshInstance3D
		if mesh_instance.mesh == null:
			continue
		var source := mesh_instance.get_aabb()
		var relative_transform := _node_transform_relative_to(mesh_instance, content)
		for corner_index in 8:
			var corner := source.position + Vector3(
				source.size.x if (corner_index & 1) != 0 else 0.0,
				source.size.y if (corner_index & 2) != 0 else 0.0,
				source.size.z if (corner_index & 4) != 0 else 0.0
			)
			var point := relative_transform * corner
			if not has_bounds:
				combined = AABB(point, Vector3.ZERO)
				has_bounds = true
			else:
				combined = combined.expand(point)
	return combined if has_bounds else AABB(Vector3.ZERO, Vector3.ONE)


static func _node_transform_relative_to(node: Node3D, root: Node3D) -> Transform3D:
	var result := node.transform
	var parent := node.get_parent()
	while parent != null and parent != root:
		if parent is Node3D:
			result = (parent as Node3D).transform * result
		parent = parent.get_parent()
	return result


static func _add_missing_asset_placeholder(body: StaticBody3D, size: Vector3, message: String) -> void:
	var visual := MeshInstance3D.new()
	visual.name = "MissingAssetVisual"
	var mesh := BoxMesh.new()
	mesh.size = size
	visual.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.9, 0.12, 0.55, 0.78)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	visual.material_override = material
	body.add_child(visual)
	var collision := CollisionShape3D.new()
	collision.name = "EditorSelectionCollision"
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	var label := Label3D.new()
	label.name = "MissingAssetLabel"
	label.text = message
	label.position.y = maxf(size.y * 0.65, 0.8)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 28
	label.modulate = Color("ff77bd")
	body.add_child(label)
