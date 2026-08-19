class_name TacticalSmokeCloud
extends Node3D

const FoleyEngine := preload("res://scripts/audio/tactical_foley_engine.gd")

enum Stage { SPROUT, DENSE_BLOOM, DISSIPATE }

@export var sprout_seconds := 1.8
@export var dense_seconds := 12.0
@export var dissipate_seconds := 5.0
@export var maximum_radius := 4.8

var stage := Stage.SPROUT
var age := 0.0
var current_radius := 0.10
var current_density := 0.0
var _particles: GPUParticles3D
var _foley: TacticalFoleyEngine


func _ready() -> void:
	_build_particles()
	_foley = FoleyEngine.new()
	add_child(_foley)
	_foley.play_cue(&"smoke_hiss", global_position, -5.0, 0.92)
	var manager := get_node_or_null("/root/TacticalOcclusionManager")
	if manager != null:
		manager.call("register_cloud", self)


func _exit_tree() -> void:
	var manager := get_node_or_null("/root/TacticalOcclusionManager")
	if manager != null:
		manager.call("unregister_cloud", self)


func _process(delta: float) -> void:
	age += delta
	if age < sprout_seconds:
		stage = Stage.SPROUT
		var t := age / sprout_seconds
		current_radius = lerpf(0.10, maximum_radius * 0.72, ease(t, 0.55))
		current_density = lerpf(0.0, 0.82, t)
	elif age < sprout_seconds + dense_seconds:
		stage = Stage.DENSE_BLOOM
		var t := (age - sprout_seconds) / dense_seconds
		current_radius = lerpf(maximum_radius * 0.72, maximum_radius, minf(1.0, t * 2.0))
		current_density = lerpf(0.82, 1.0, minf(1.0, t * 0.25))
	else:
		stage = Stage.DISSIPATE
		var t := (age - sprout_seconds - dense_seconds) / dissipate_seconds
		current_radius = lerpf(maximum_radius, maximum_radius * 1.22, t)
		current_density = lerpf(1.0, 0.0, t)
		if t >= 1.0:
			queue_free()
	if _particles != null:
		_particles.amount_ratio = clampf(current_density, 0.05, 1.0)
		_particles.scale = Vector3.ONE * current_radius / maximum_radius


func _build_particles() -> void:
	_particles = GPUParticles3D.new()
	_particles.amount = 180
	_particles.lifetime = 4.5
	_particles.randomness = 0.72
	_particles.visibility_aabb = AABB(Vector3(-7, -2, -7), Vector3(14, 8, 14))
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = 2.8
	process.initial_velocity_min = 0.08
	process.initial_velocity_max = 0.45
	process.gravity = Vector3(0.0, 0.10, 0.0)
	process.scale_min = 1.8
	process.scale_max = 3.8
	_particles.process_material = process
	var quad := QuadMesh.new()
	quad.size = Vector2(1.7, 1.7)
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.46, 0.49, 0.45, 0.20)
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	quad.material = material
	_particles.draw_pass_1 = quad
	add_child(_particles)
