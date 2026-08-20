class_name GunsmithGizmoController
extends RefCounted

const HAND_GIZMO_ARROW_LENGTH := 0.12
const HAND_GIZMO_RING_RADIUS := 0.09
const WEAPON_GIZMO_ARROW_LENGTH := 0.10
const WEAPON_GIZMO_RING_RADIUS := 0.075
const GIZMO_CENTER_RADIUS := 0.018
const GIZMO_PICK_DISTANCE_PX := 28.0


static func create_marker(color: Color, marker_name: String, radius: float = 0.016) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = marker_name
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	sphere.radial_segments = 16
	sphere.rings = 8
	mi.mesh = sphere

	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 0.6
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test = true
	mi.material_override = mat
	return mi


static func create_selection_box(color: Color, box_name: String, size_m: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = box_name
	var box := BoxMesh.new()
	box.size = Vector3.ONE * size_m
	mi.mesh = box

	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 0.85
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test = true
	mi.material_override = mat
	return mi


static func create_axis_arrow(color: Color, axis_dir: Vector3, arrow_name: String, length: float) -> Node3D:
	var root := Node3D.new()
	root.name = arrow_name

	var shaft := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.003
	cyl.bottom_radius = 0.003
	cyl.height = length
	shaft.mesh = cyl

	var tip := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.010
	cone.height = 0.025
	tip.mesh = cone

	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 0.75
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test = true
	shaft.material_override = mat
	tip.material_override = mat

	root.add_child(shaft)
	root.add_child(tip)

	if axis_dir == Vector3.RIGHT:
		root.rotation_degrees = Vector3(0, 0, -90)
	elif axis_dir == Vector3.BACK:
		root.rotation_degrees = Vector3(90, 0, 0)
	elif axis_dir == Vector3.FORWARD:
		root.rotation_degrees = Vector3(-90, 0, 0)

	shaft.position = Vector3(0, length * 0.5, 0)
	tip.position = Vector3(0, length + 0.0125, 0)
	return root


static func create_rotation_ring(color: Color, normal_axis: Vector3, radius: float, ring_name: String) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = ring_name
	var torus := TorusMesh.new()
	torus.inner_radius = radius - 0.003
	torus.outer_radius = radius + 0.003
	torus.rings = 32
	torus.ring_segments = 8
	mi.mesh = torus

	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 0.65
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test = true
	mi.material_override = mat

	if normal_axis == Vector3.RIGHT:
		mi.rotation_degrees = Vector3(0, 0, 90)
	elif normal_axis == Vector3.BACK or normal_axis == Vector3.FORWARD:
		mi.rotation_degrees = Vector3(90, 0, 0)
	return mi
