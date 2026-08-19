class_name TacticalGrenadeBase
extends RigidBody3D

const FoleyEngine := preload("res://scripts/audio/tactical_foley_engine.gd")

signal fuse_started(duration: float)
signal detonated(position: Vector3)
signal bounced(speed: float, position: Vector3)

@export var fuse_seconds := 3.0
@export var bounce_restitution := 0.38
@export var mass_kg := 0.40
@export var arm_on_ready := true

var armed := false
var detonated_once := false
var fuse_remaining := 0.0
var authority_peer_id := 1
var _previous_linear_velocity := Vector3.ZERO
var foley: TacticalFoleyEngine
var _sparks: GPUParticles3D


func _ready() -> void:
	mass = mass_kg
	physics_material_override = PhysicsMaterial.new()
	physics_material_override.bounce = bounce_restitution
	physics_material_override.friction = 0.62
	contact_monitor = true
	max_contacts_reported = 4
	body_entered.connect(_on_body_entered)
	_build_default_body()
	foley = FoleyEngine.new()
	foley.name = "GrenadeFoley"
	add_child(foley)
	_build_fuse_sparks()
	if arm_on_ready:
		arm()


func _physics_process(delta: float) -> void:
	_previous_linear_velocity = linear_velocity
	if not armed or detonated_once or not _is_simulation_authority():
		return
	fuse_remaining -= delta
	if fuse_remaining <= 0.0:
		detonate()


func arm(duration := -1.0) -> void:
	armed = true
	fuse_remaining = fuse_seconds if duration < 0.0 else duration
	fuse_started.emit(fuse_remaining)


func launch(velocity: Vector3, spin := Vector3(8.0, 3.0, 5.0)) -> void:
	linear_velocity = velocity
	angular_velocity = spin
	sleeping = false


func detonate() -> void:
	if detonated_once:
		return
	detonated_once = true
	detonated.emit(global_position)
	_on_detonated()


func _on_detonated() -> void:
	queue_free()


func _is_simulation_authority() -> bool:
	return not multiplayer.has_multiplayer_peer() or multiplayer.is_server()


func _on_body_entered(_body: Node) -> void:
	var speed := _previous_linear_velocity.length()
	if speed > 1.2:
		bounced.emit(speed, global_position)
		foley.play_cue(&"foot_metal", global_position, -8.0, randf_range(0.82, 1.12))


func _build_default_body() -> void:
	if get_child_count() > 0:
		return
	var collision := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = 0.075
	collision.shape = shape
	add_child(collision)
	var mesh_instance := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.075
	mesh.height = 0.15
	mesh_instance.mesh = mesh
	add_child(mesh_instance)


func _build_fuse_sparks() -> void:
	_sparks = GPUParticles3D.new()
	_sparks.amount = 18
	_sparks.lifetime = 0.35
	_sparks.visibility_aabb = AABB(Vector3(-1, -1, -1), Vector3(2, 2, 2))
	var process := ParticleProcessMaterial.new()
	process.direction = Vector3.UP
	process.spread = 55.0
	process.initial_velocity_min = 0.4
	process.initial_velocity_max = 1.4
	process.gravity = Vector3(0, -4.0, 0)
	_sparks.process_material = process
	var mesh := SphereMesh.new()
	mesh.radius = 0.008
	mesh.height = 0.016
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(1.0, 0.48, 0.08)
	material.emission_enabled = true
	material.emission = Color(1.0, 0.20, 0.02)
	mesh.material = material
	_sparks.draw_pass_1 = mesh
	add_child(_sparks)
