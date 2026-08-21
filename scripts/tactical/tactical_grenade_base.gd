class_name TacticalGrenadeBase
extends RigidBody3D

const FoleyEngine := preload("res://scripts/audio/tactical_foley_engine.gd")
const GrenadeProfile := preload("res://scripts/tactical/tactical_grenade_profile.gd")

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
var foley: Node
var _sparks: GPUParticles3D
var _impact_cooldown := 0.0
var profile_override: Dictionary = {}
var active_profile: Dictionary = {}


func _ready() -> void:
	active_profile = (
		GrenadeProfile.normalize(profile_override)
		if not profile_override.is_empty()
		else GrenadeProfile.load_profile()
	)
	_apply_common_profile(active_profile)
	_apply_type_profile(active_profile)
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


func configure_profile(raw_profile: Dictionary) -> void:
	profile_override = GrenadeProfile.normalize(raw_profile)
	if is_node_ready():
		active_profile = profile_override.duplicate(true)
		_apply_common_profile(active_profile)
		_apply_type_profile(active_profile)
		mass = mass_kg
		if physics_material_override != null:
			physics_material_override.bounce = bounce_restitution


func _apply_common_profile(profile: Dictionary) -> void:
	var common: Dictionary = profile.get("common", {})
	fuse_seconds = float(common.get("fuse_seconds", fuse_seconds))
	bounce_restitution = float(common.get("bounce_restitution", bounce_restitution))
	mass_kg = float(common.get("mass_kg", mass_kg))


func _apply_type_profile(_profile: Dictionary) -> void:
	pass


func _physics_process(delta: float) -> void:
	_previous_linear_velocity = linear_velocity
	_impact_cooldown = maxf(0.0, _impact_cooldown - delta)
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


func _on_body_entered(body: Node) -> void:
	var speed := _previous_linear_velocity.length()
	if speed <= 1.2 or _impact_cooldown > 0.0:
		return
	_impact_cooldown = 0.055
	bounced.emit(speed, global_position)
	var surface: StringName = foley.play_surface_event(
		&"grenade_impact", global_position, clampf(speed / 8.0, 0.15, 1.25), body
	)
	if _is_simulation_authority():
		call_deferred("_apply_surface_response", surface)


func _apply_surface_response(surface: StringName) -> void:
	if foley == null:
		return
	var response: Dictionary = foley.surface_physics(surface)
	linear_velocity *= clampf(float(response.get("energy_retention", 0.72)), 0.05, 1.0)
	angular_velocity *= clampf(float(response.get("angular_retention", 0.76)), 0.05, 1.0)


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
