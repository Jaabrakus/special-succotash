class_name SocomDemolitionBombVisual
extends Node3D

## Shared presentation for the server-owned demolition objective. This scene
## follows replicated bomb state. It never decides pickup, plant, defuse, fuse,
## damage, or round results.

const STATE_AVAILABLE := &"AVAILABLE"
const STATE_CARRIED := &"CARRIED"
const STATE_PLANTED := &"PLANTED"
const STATE_DEFUSING := &"DEFUSING"

var bomb_state: StringName = STATE_AVAILABLE
var state_label: Label3D
var status_light_material: StandardMaterial3D
var pulse_age := 0.0


func _ready() -> void:
	_build_satchel()
	set_bomb_state(STATE_AVAILABLE)


func _process(delta: float) -> void:
	pulse_age += delta
	if status_light_material == null:
		return
	var pulse := 0.55 + sin(pulse_age * (13.0 if bomb_state == STATE_PLANTED else 8.0)) * 0.45
	if bomb_state in [STATE_PLANTED, STATE_DEFUSING]:
		status_light_material.emission_energy_multiplier = lerpf(1.5, 5.0, pulse)
	else:
		status_light_material.emission_energy_multiplier = 1.2


func set_bomb_state(value: StringName, defuse_progress: float = 0.0) -> void:
	bomb_state = value
	if state_label == null or status_light_material == null:
		return
	match bomb_state:
		STATE_CARRIED:
			state_label.text = "BOMB"
			state_label.modulate = Color("f4d34f")
			status_light_material.albedo_color = Color("f4d34f")
			status_light_material.emission = Color("f4d34f")
		STATE_PLANTED:
			state_label.text = "ARMED"
			state_label.modulate = Color("ff5548")
			status_light_material.albedo_color = Color("ff5548")
			status_light_material.emission = Color("ff5548")
		STATE_DEFUSING:
			state_label.text = "DEFUSE %d%%" % int(round(clampf(defuse_progress, 0.0, 1.0) * 100.0))
			state_label.modulate = Color("52c7ff")
			status_light_material.albedo_color = Color("52c7ff")
			status_light_material.emission = Color("52c7ff")
		_:
			state_label.text = "BOMB"
			state_label.modulate = Color("f4d34f")
			status_light_material.albedo_color = Color("f4d34f")
			status_light_material.emission = Color("f4d34f")


func _build_satchel() -> void:
	_add_box("Satchel", Vector3(0.48, 0.18, 0.34), Vector3(0.0, 0.13, 0.0), Color("263229"), 0.92, 0.05)
	_add_box("ControlPanel", Vector3(0.28, 0.045, 0.20), Vector3(0.0, 0.245, 0.0), Color("1b1f22"), 0.68, 0.28)
	_add_box("LeftStrap", Vector3(0.055, 0.035, 0.38), Vector3(-0.15, 0.225, 0.0), Color("756443"), 0.82, 0.0)
	_add_box("RightStrap", Vector3(0.055, 0.035, 0.38), Vector3(0.15, 0.225, 0.0), Color("756443"), 0.82, 0.0)
	_add_box("Screen", Vector3(0.14, 0.018, 0.07), Vector3(0.0, 0.273, -0.025), Color("14252a"), 0.35, 0.15)

	var status_light := MeshInstance3D.new()
	status_light.name = "StatusLight"
	var light_mesh := SphereMesh.new()
	light_mesh.radius = 0.025
	light_mesh.height = 0.05
	status_light.mesh = light_mesh
	status_light.position = Vector3(0.085, 0.292, -0.025)
	status_light_material = StandardMaterial3D.new()
	status_light_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	status_light_material.emission_enabled = true
	status_light.material_override = status_light_material
	add_child(status_light)

	var antenna := MeshInstance3D.new()
	antenna.name = "Antenna"
	var antenna_mesh := CylinderMesh.new()
	antenna_mesh.top_radius = 0.009
	antenna_mesh.bottom_radius = 0.012
	antenna_mesh.height = 0.24
	antenna.mesh = antenna_mesh
	antenna.position = Vector3(0.19, 0.32, 0.08)
	antenna.rotation_degrees.z = -12.0
	var antenna_material := StandardMaterial3D.new()
	antenna_material.albedo_color = Color("202326")
	antenna_material.metallic = 0.35
	antenna_material.roughness = 0.55
	antenna.material_override = antenna_material
	add_child(antenna)

	state_label = Label3D.new()
	state_label.name = "BombStateLabel"
	state_label.text = "BOMB"
	state_label.position = Vector3(0.0, 0.58, 0.0)
	state_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	state_label.font_size = 22
	state_label.outline_size = 5
	state_label.no_depth_test = true
	add_child(state_label)


func _add_box(
	part_name: String,
	size: Vector3,
	position: Vector3,
	color: Color,
	roughness: float,
	metallic: float
) -> void:
	var part := MeshInstance3D.new()
	part.name = part_name
	var mesh := BoxMesh.new()
	mesh.size = size
	part.mesh = mesh
	part.position = position
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.metallic = metallic
	part.material_override = material
	add_child(part)
