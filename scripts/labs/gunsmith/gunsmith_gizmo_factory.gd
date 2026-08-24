class_name GunsmithGizmoFactory
extends RefCounted

## Stateless mesh factory for Gunsmith authoring controls.


static func create_axis_arrow(
	color: Color,
	axis_direction: Vector3,
	arrow_name: String,
	length: float = 0.26
) -> Node3D:
	var root := Node3D.new()
	root.name = arrow_name
	var shaft := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.008
	cylinder.bottom_radius = 0.008
	cylinder.height = length
	shaft.mesh = cylinder
	var head := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.020
	cone.height = 0.050
	head.mesh = cone
	var material := _unshaded_material(color, 110)
	shaft.material_override = material
	head.material_override = material
	shaft.position = Vector3(0, length * 0.5, 0)
	head.position = Vector3(0, length + 0.025, 0)
	root.add_child(shaft)
	root.add_child(head)
	if axis_direction.is_equal_approx(Vector3.RIGHT):
		root.rotation_degrees = Vector3(0, 0, -90)
	elif axis_direction.is_equal_approx(Vector3.BACK):
		root.rotation_degrees = Vector3(90, 0, 0)
	elif axis_direction.is_equal_approx(Vector3.FORWARD):
		root.rotation_degrees = Vector3(-90, 0, 0)
	return root


static func create_rotation_ring(
	color: Color,
	normal_axis: Vector3,
	radius: float,
	ring_name: String
) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = ring_name
	var torus := TorusMesh.new()
	torus.inner_radius = radius - 0.012
	torus.outer_radius = radius + 0.012
	torus.rings = 48
	torus.ring_segments = 16
	instance.mesh = torus
	instance.material_override = _unshaded_material(color, 110)
	if normal_axis.is_equal_approx(Vector3.RIGHT):
		instance.rotation_degrees = Vector3(0, 0, 90)
	elif normal_axis.is_equal_approx(Vector3.FORWARD) or normal_axis.is_equal_approx(Vector3.BACK):
		instance.rotation_degrees = Vector3(90, 0, 0)
	return instance


static func create_marker(
	color: Color,
	marker_name: String,
	radius: float = 0.055
) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = marker_name
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	instance.mesh = sphere
	instance.material_override = _unshaded_material(color, 100)
	return instance


static func create_selection_box(
	color: Color,
	marker_name: String,
	size: float = 0.065
) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = marker_name
	var box := BoxMesh.new()
	box.size = Vector3.ONE * size
	instance.mesh = box
	instance.material_override = _unshaded_material(color, 100)
	return instance


static func _unshaded_material(color: Color, priority: int) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.render_priority = priority
	material.no_depth_test = true
	return material
