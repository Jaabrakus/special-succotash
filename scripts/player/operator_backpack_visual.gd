class_name SocomOperatorBackpackVisual
extends RefCounted

## Original modular field pack assembled from engine-native geometry.
## It is a wearable visual only: no hitbox, gameplay state, or animation ownership.


static func build(config: Dictionary = {}) -> Node3D:
	var root := Node3D.new()
	root.name = "WearableBackpack"
	root.set_meta("socom_wearable", true)
	root.set_meta("wearable_slot", "back")

	var fabric := _material(_color(config.get("fabric_color", {}), Color("303a31")), 0.94)
	var webbing := _material(_color(config.get("webbing_color", {}), Color("202720")), 0.98)
	var hardware := _material(Color("111512"), 0.56, 0.20)

	_add_box(root, "MainPack", Vector3(0.40, 0.50, 0.17), Vector3(0.0, -0.04, 0.0), fabric)
	_add_box(root, "TopFlap", Vector3(0.37, 0.13, 0.20), Vector3(0.0, 0.205, 0.012), fabric)
	_add_box(root, "LowerPouch", Vector3(0.33, 0.15, 0.13), Vector3(0.0, -0.205, 0.035), fabric)
	_add_box(root, "LeftPouch", Vector3(0.105, 0.23, 0.14), Vector3(-0.245, -0.055, 0.018), fabric)
	_add_box(root, "RightPouch", Vector3(0.105, 0.23, 0.14), Vector3(0.245, -0.055, 0.018), fabric)

	# Shoulder straps sit on the body-facing side of the pack.
	_add_box(root, "LeftShoulderStrap", Vector3(0.055, 0.52, 0.025), Vector3(-0.125, 0.0, -0.098), webbing)
	_add_box(root, "RightShoulderStrap", Vector3(0.055, 0.52, 0.025), Vector3(0.125, 0.0, -0.098), webbing)
	_add_box(root, "CenterWebbing", Vector3(0.035, 0.40, 0.022), Vector3(0.0, -0.02, 0.098), webbing)
	_add_box(root, "TopBuckle", Vector3(0.075, 0.052, 0.032), Vector3(0.0, 0.10, 0.112), hardware)
	_add_box(root, "BottomBuckle", Vector3(0.075, 0.052, 0.032), Vector3(0.0, -0.12, 0.112), hardware)
	_add_box(root, "BombControlPanel", Vector3(0.22, 0.13, 0.035), Vector3(0.0, 0.04, 0.112), hardware)
	var status_light := MeshInstance3D.new()
	status_light.name = "BombStatusLight"
	var light_mesh := SphereMesh.new()
	light_mesh.radius = 0.022
	light_mesh.height = 0.044
	status_light.mesh = light_mesh
	status_light.position = Vector3(0.065, 0.065, 0.137)
	var light_material := StandardMaterial3D.new()
	light_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	light_material.albedo_color = Color("f1b84b")
	light_material.emission_enabled = true
	light_material.emission = Color("f1b84b")
	light_material.emission_energy_multiplier = 2.2
	status_light.material_override = light_material
	root.add_child(status_light)

	var bedroll := MeshInstance3D.new()
	bedroll.name = "Bedroll"
	var roll_mesh := CylinderMesh.new()
	roll_mesh.top_radius = 0.082
	roll_mesh.bottom_radius = 0.082
	roll_mesh.height = 0.38
	roll_mesh.radial_segments = 12
	bedroll.mesh = roll_mesh
	bedroll.position = Vector3(0.0, -0.325, 0.005)
	bedroll.rotation_degrees.z = 90.0
	bedroll.material_override = webbing
	root.add_child(bedroll)
	var antenna := MeshInstance3D.new()
	antenna.name = "BombAntenna"
	var antenna_mesh := CylinderMesh.new()
	antenna_mesh.top_radius = 0.008
	antenna_mesh.bottom_radius = 0.011
	antenna_mesh.height = 0.25
	antenna_mesh.radial_segments = 8
	antenna.mesh = antenna_mesh
	antenna.position = Vector3(0.155, 0.31, 0.015)
	antenna.rotation_degrees.z = -10.0
	antenna.material_override = hardware
	root.add_child(antenna)
	return root


static func _add_box(parent: Node3D, part_name: String, size: Vector3, position: Vector3, material: Material) -> void:
	var part := MeshInstance3D.new()
	part.name = part_name
	var mesh := BoxMesh.new()
	mesh.size = size
	part.mesh = mesh
	part.position = position
	part.material_override = material
	parent.add_child(part)


static func _material(color: Color, roughness: float, metallic: float = 0.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.metallic = metallic
	return material


static func _color(value: Variant, fallback: Color) -> Color:
	if value is Dictionary:
		var data := value as Dictionary
		return Color(
			float(data.get("r", fallback.r)),
			float(data.get("g", fallback.g)),
			float(data.get("b", fallback.b)),
			float(data.get("a", fallback.a))
		)
	return fallback
