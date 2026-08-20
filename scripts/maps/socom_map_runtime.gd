class_name SocomMapRuntime
extends RefCounted

const MapDocument := preload("res://scripts/maps/socom_map_document.gd")


static func build_into(parent: Node3D, document: Dictionary, editor_preview: bool = false) -> Node3D:
	var normalized := MapDocument.normalize(document)
	if normalized.is_empty():
		return null
	var root := Node3D.new()
	root.name = "AuthoredMap"
	root.set_meta("map_name", normalized.get("name", "Map"))
	root.set_meta("gameplay", (normalized.get("gameplay", {}) as Dictionary).duplicate(true))
	parent.add_child(root)
	for object: Dictionary in normalized.get("objects", []):
		var map_node := build_object(object, editor_preview)
		if map_node != null:
			root.add_child(map_node)
	return root


static func build_object(object: Dictionary, editor_preview: bool = false) -> Node3D:
	var type_name := StringName(object.get("type", "wall"))
	if type_name == &"player_spawn":
		return _build_spawn(object, editor_preview)
	if type_name == &"point_light":
		return _build_point_light(object, editor_preview)
	if type_name == &"ambience_zone":
		return _build_ambience_zone(object, editor_preview)
	if type_name in MapDocument.SOCOM_OBJECTIVE_TYPES:
		return _build_objective_marker(object, editor_preview)
	if type_name == &"curved_wall":
		return _build_curved_wall(object)
	if type_name == &"jagged_wall":
		return _build_jagged_wall(object)
	if type_name == &"ramp":
		return _build_wedge_ramp(object)
	if type_name in [&"training_dummy", &"moving_training_dummy"]:
		return _build_training_marker(object, editor_preview)
	var body := StaticBody3D.new()
	body.name = String(object.get("name", type_name)).validate_node_name()
	body.set_meta("map_object_id", String(object.get("id", "")))
	body.set_meta("map_object_type", type_name)
	body.position = MapDocument.data_to_vector(object.get("position", {}))
	body.rotation_degrees = MapDocument.data_to_vector(object.get("rotation_degrees", {}))
	var size := MapDocument.data_to_vector(object.get("size", {}), Vector3.ONE)
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "Visual"
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh_instance.mesh = mesh
	mesh_instance.material_override = _material_for_object(object)
	body.add_child(mesh_instance)
	var collision := CollisionShape3D.new()
	collision.name = "CollisionShape3D"
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	return body


static func _build_spawn(object: Dictionary, editor_preview: bool) -> Node3D:
	var marker := StaticBody3D.new()
	marker.name = "PlayerSpawn"
	marker.set_meta("map_object_id", String(object.get("id", "")))
	marker.set_meta("map_object_type", &"player_spawn")
	marker.position = MapDocument.data_to_vector(object.get("position", {}))
	marker.rotation_degrees = MapDocument.data_to_vector(object.get("rotation_degrees", {}))
	if not editor_preview:
		return marker
	var visual := MeshInstance3D.new()
	visual.name = "Visual"
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.38
	capsule.height = 1.8
	visual.mesh = capsule
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.25, 1.0, 0.62, 0.55)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	visual.material_override = material
	visual.position.y = 0.9
	marker.add_child(visual)
	var collision := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.38
	shape.height = 1.8
	collision.shape = shape
	collision.position.y = 0.9
	marker.add_child(collision)
	return marker


static func _build_point_light(object: Dictionary, editor_preview: bool) -> Node3D:
	var marker := StaticBody3D.new()
	marker.name = String(object.get("name", "Practical Light")).validate_node_name()
	marker.position = MapDocument.data_to_vector(object.get("position", {}))
	marker.set_meta("map_object_id", String(object.get("id", "")))
	marker.set_meta("map_object_type", &"point_light")
	var properties: Dictionary = object.get("properties", {})
	var light := OmniLight3D.new()
	light.name = "Light"
	light.light_color = MapDocument.data_to_color(object.get("color", {}), Color("ffd59b"))
	light.light_energy = float(properties.get("energy", 4.0))
	light.omni_range = float(properties.get("range", 8.0))
	light.shadow_enabled = bool(properties.get("shadow_enabled", true))
	marker.add_child(light)
	if editor_preview:
		_add_translucent_box(marker, Vector3(0.3, 0.3, 0.3), light.light_color, 0.85)
		var collision := CollisionShape3D.new()
		var shape := SphereShape3D.new()
		shape.radius = 0.3
		collision.shape = shape
		marker.add_child(collision)
	return marker


static func _build_ambience_zone(object: Dictionary, editor_preview: bool) -> Node3D:
	var area := Area3D.new()
	area.name = String(object.get("name", "Ambience Zone")).validate_node_name()
	area.position = MapDocument.data_to_vector(object.get("position", {}))
	area.rotation_degrees = MapDocument.data_to_vector(object.get("rotation_degrees", {}))
	area.set_meta("map_object_id", String(object.get("id", "")))
	area.set_meta("map_object_type", &"ambience_zone")
	var properties: Dictionary = object.get("properties", {})
	for key: String in properties:
		area.set_meta(key, properties[key])
	var size := MapDocument.data_to_vector(object.get("size", {}), Vector3(6.0, 3.0, 6.0))
	var collision := CollisionShape3D.new()
	collision.name = "CollisionShape3D"
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	area.add_child(collision)
	if editor_preview:
		_add_translucent_box(area, size, MapDocument.data_to_color(object.get("color", {}), Color("8b6be8")), 0.16)
	return area


static func _build_objective_marker(object: Dictionary, editor_preview: bool) -> Node3D:
	var marker := StaticBody3D.new()
	var type_name := StringName(object.get("type", ""))
	marker.name = String(object.get("name", type_name)).validate_node_name()
	marker.position = MapDocument.data_to_vector(object.get("position", {}))
	marker.rotation_degrees = MapDocument.data_to_vector(object.get("rotation_degrees", {}))
	marker.set_meta("map_object_id", String(object.get("id", "")))
	marker.set_meta("map_object_type", type_name)
	marker.set_meta("socom_objective", true)
	if not editor_preview:
		return marker
	var size := MapDocument.data_to_vector(object.get("size", {}), Vector3.ONE)
	_add_translucent_box(marker, size, MapDocument.data_to_color(object.get("color", {})), 0.46)
	var collision := CollisionShape3D.new()
	collision.name = "CollisionShape3D"
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	marker.add_child(collision)
	return marker


static func _build_training_marker(object: Dictionary, editor_preview: bool) -> Node3D:
	var marker := StaticBody3D.new()
	var type_name := StringName(object.get("type", "training_dummy"))
	marker.name = String(object.get("name", type_name)).validate_node_name()
	marker.position = MapDocument.data_to_vector(object.get("position", {}))
	marker.rotation_degrees = MapDocument.data_to_vector(object.get("rotation_degrees", {}))
	_set_object_meta(marker, object)
	marker.set_meta("training_target", true)
	if not editor_preview:
		return marker
	var visual := MeshInstance3D.new()
	visual.name = "Visual"
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.38
	capsule.height = 1.8
	visual.mesh = capsule
	visual.position.y = 0.9
	var material := StandardMaterial3D.new()
	material.albedo_color = MapDocument.data_to_color(object.get("color", {}), Color("f39a55"))
	material.roughness = 0.8
	visual.material_override = material
	marker.add_child(visual)
	var collision := CollisionShape3D.new()
	collision.name = "CollisionShape3D"
	var shape := CapsuleShape3D.new()
	shape.radius = 0.38
	shape.height = 1.8
	collision.shape = shape
	collision.position.y = 0.9
	marker.add_child(collision)
	var label := Label3D.new()
	label.text = "MOVING" if type_name == &"moving_training_dummy" else "STATIC"
	label.position.y = 2.15
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 22
	label.modulate = material.albedo_color
	marker.add_child(label)
	if type_name == &"moving_training_dummy":
		var properties: Dictionary = object.get("properties", {})
		var distance := clampf(float(properties.get("patrol_distance", 6.0)), 0.5, 50.0)
		var path := MeshInstance3D.new()
		path.name = "PatrolPath"
		var path_mesh := BoxMesh.new()
		path_mesh.size = Vector3(distance, 0.035, 0.08)
		path.mesh = path_mesh
		path.position.y = 0.04
		var path_material := StandardMaterial3D.new()
		path_material.albedo_color = Color(0.2, 0.95, 1.0, 0.75)
		path_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		path_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		path.material_override = path_material
		marker.add_child(path)
	return marker


static func _build_wedge_ramp(object: Dictionary) -> Node3D:
	var body := StaticBody3D.new()
	body.name = String(object.get("name", "Ramp")).validate_node_name()
	body.position = MapDocument.data_to_vector(object.get("position", {}))
	body.rotation_degrees = MapDocument.data_to_vector(object.get("rotation_degrees", {}))
	_set_object_meta(body, object)
	var size := MapDocument.data_to_vector(object.get("size", {}), Vector3(3.0, 1.5, 5.0))
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "Visual"
	mesh_instance.mesh = _wedge_mesh(size)
	mesh_instance.material_override = _material_for_object(object)
	body.add_child(mesh_instance)
	var collision := CollisionShape3D.new()
	collision.name = "CollisionShape3D"
	var shape := ConvexPolygonShape3D.new()
	shape.points = _wedge_points(size)
	collision.shape = shape
	body.add_child(collision)
	return body


static func _build_curved_wall(object: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = String(object.get("name", "Curved Wall")).validate_node_name()
	root.position = MapDocument.data_to_vector(object.get("position", {}))
	root.rotation_degrees = MapDocument.data_to_vector(object.get("rotation_degrees", {}))
	_set_object_meta(root, object)
	var size := MapDocument.data_to_vector(object.get("size", {}), Vector3(5.0, 3.0, 0.35))
	var properties: Dictionary = object.get("properties", {})
	var radius := maxf(float(properties.get("radius", 4.0)), 0.5)
	var arc_degrees := clampf(float(properties.get("arc_degrees", 90.0)), 5.0, 330.0)
	var segments := clampi(int(properties.get("segments", 8)), 2, 48)
	var step_radians := deg_to_rad(arc_degrees / float(segments))
	var chord := maxf(2.0 * radius * sin(step_radians * 0.5), 0.1)
	for index in segments:
		var angle_degrees := -arc_degrees * 0.5 + (float(index) + 0.5) * arc_degrees / float(segments)
		var angle := deg_to_rad(angle_degrees)
		var segment := StaticBody3D.new()
		segment.name = "CurveSegment%02d" % index
		segment.position = Vector3(sin(angle) * radius, 0.0, cos(angle) * radius - radius)
		segment.rotation_degrees.y = angle_degrees
		_set_object_meta(segment, object)
		_add_box_parts(segment, Vector3(chord, size.y, size.z), object)
		root.add_child(segment)
	return root


static func _build_jagged_wall(object: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = String(object.get("name", "Broken Wall")).validate_node_name()
	root.position = MapDocument.data_to_vector(object.get("position", {}))
	root.rotation_degrees = MapDocument.data_to_vector(object.get("rotation_degrees", {}))
	_set_object_meta(root, object)
	var size := MapDocument.data_to_vector(object.get("size", {}), Vector3(5.0, 2.6, 0.45))
	var properties: Dictionary = object.get("properties", {})
	var pieces := clampi(int(properties.get("pieces", 6)), 2, 24)
	var variance := clampf(float(properties.get("height_variance", 0.8)), 0.0, size.y * 0.8)
	var edge_rotation := clampf(float(properties.get("edge_rotation", 5.0)), 0.0, 25.0)
	var piece_width := size.x / float(pieces)
	var seed_value: int = absi(String(object.get("id", "wall")).hash()) % 997
	for index in pieces:
		var noise := sin(float(seed_value + index * 37) * 0.731)
		var piece_height := maxf(0.25, size.y - absf(noise) * variance)
		var piece := StaticBody3D.new()
		piece.name = "BrokenPiece%02d" % index
		piece.position = Vector3(-size.x * 0.5 + piece_width * (float(index) + 0.5), -size.y * 0.5 + piece_height * 0.5, 0.0)
		piece.rotation_degrees.z = noise * edge_rotation
		_set_object_meta(piece, object)
		_add_box_parts(piece, Vector3(piece_width * 1.04, piece_height, size.z), object)
		root.add_child(piece)
	return root


static func _add_box_parts(body: StaticBody3D, size: Vector3, object: Dictionary) -> void:
	var visual := MeshInstance3D.new()
	visual.name = "Visual"
	var mesh := BoxMesh.new()
	mesh.size = size
	visual.mesh = mesh
	visual.material_override = _material_for_object(object)
	body.add_child(visual)
	var collision := CollisionShape3D.new()
	collision.name = "CollisionShape3D"
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)


static func _set_object_meta(node: Node, object: Dictionary) -> void:
	node.set_meta("map_object_id", String(object.get("id", "")))
	node.set_meta("map_object_type", StringName(object.get("type", "")))


static func _material_for_object(object: Dictionary) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = MapDocument.data_to_color(object.get("color", {}), Color("626973"))
	var properties: Dictionary = object.get("properties", {})
	material.roughness = clampf(float(properties.get("roughness", 0.9)), 0.0, 1.0)
	material.metallic = clampf(float(properties.get("metallic", 0.0)), 0.0, 1.0)
	var texture_path := String(properties.get("texture_path", ""))
	if not texture_path.is_empty() and ResourceLoader.exists(texture_path):
		var texture := load(texture_path) as Texture2D
		if texture != null:
			material.albedo_texture = texture
			var uv_scale := maxf(float(properties.get("uv_scale", 1.0)), 0.01)
			material.uv1_scale = Vector3(uv_scale, uv_scale, uv_scale)
	return material


static func _wedge_points(size: Vector3) -> PackedVector3Array:
	var hx := size.x * 0.5
	var hy := size.y * 0.5
	var hz := size.z * 0.5
	return PackedVector3Array([
		Vector3(-hx, -hy, -hz), Vector3(hx, -hy, -hz), Vector3(-hx, hy, -hz), Vector3(hx, hy, -hz),
		Vector3(-hx, -hy, hz), Vector3(hx, -hy, hz),
	])


static func _wedge_mesh(size: Vector3) -> ArrayMesh:
	var points := _wedge_points(size)
	var triangles := [
		0, 1, 3, 0, 3, 2,
		4, 5, 1, 4, 1, 0,
		2, 3, 5, 2, 5, 4,
		0, 2, 4,
		1, 5, 3,
	]
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for point_index: int in triangles:
		surface.set_uv(Vector2(points[point_index].x, points[point_index].z))
		surface.add_vertex(points[point_index])
	surface.generate_normals()
	return surface.commit()


static func _add_translucent_box(parent: Node3D, size: Vector3, color: Color, alpha: float) -> void:
	var visual := MeshInstance3D.new()
	visual.name = "Visual"
	var mesh := BoxMesh.new()
	mesh.size = size
	visual.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(color.r, color.g, color.b, alpha)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	visual.material_override = material
	parent.add_child(visual)
