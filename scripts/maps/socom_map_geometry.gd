extends RefCounted

const MapDocument := preload("res://scripts/maps/socom_map_document.gd")
const Materials := preload("res://scripts/maps/socom_map_surface_materials.gd")

static func _add_visual_box(parent: Node3D, name_value: String, size: Vector3, position: Vector3, rotation: Vector3, source: Dictionary) -> void:
	var visual := MeshInstance3D.new()
	visual.name = name_value
	var mesh := BoxMesh.new()
	mesh.size = size
	visual.mesh = mesh
	visual.position = position
	visual.rotation_degrees = rotation
	visual.material_override = Materials._material_for_object(source)
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	parent.add_child(visual)


static func _add_compound_box(parent: Node3D, part_name: String, size: Vector3, position: Vector3, object: Dictionary) -> void:
	var body := StaticBody3D.new()
	body.name = part_name
	body.position = position
	_set_object_meta(body, object)
	_add_box_parts(body, size, object)
	parent.add_child(body)


static func _add_box_parts(body: StaticBody3D, size: Vector3, object: Dictionary) -> void:
	var visual := MeshInstance3D.new()
	visual.name = "Visual"
	var mesh := BoxMesh.new()
	mesh.size = size
	visual.mesh = mesh
	visual.material_override = Materials._material_for_object(object)
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
	var properties: Dictionary = object.get("properties", {})
	if properties.get("source_material") is String:
		node.set_meta("source_material", properties.source_material)
