class_name TacticalSmokeCloud
extends Node3D

const FoleyEngine := preload("res://scripts/audio/tactical_foley_engine.gd")
const GrenadeProfile := preload("res://scripts/tactical/tactical_grenade_profile.gd")

enum Stage { SPROUT, DENSE_BLOOM, DISSIPATE }

@export var sprout_seconds := 1.8
@export var dense_seconds := 12.0
@export var dissipate_seconds := 5.0
@export var maximum_radius := 4.8
@export var particle_amount := 180
@export var particle_lifetime := 4.5
@export var emission_radius := 2.8
@export var puff_size_min := 1.8
@export var puff_size_max := 3.8
@export var visual_opacity := 0.20

var stage := Stage.SPROUT
var age := 0.0
var current_radius := 0.10
var current_density := 0.0
var _particles: GPUParticles3D
var _foley: TacticalFoleyEngine
var profile_override: Dictionary = {}


func _ready() -> void:
	add_to_group("presentation_quality_consumers")
	_apply_profile(
		GrenadeProfile.normalize(profile_override)
		if not profile_override.is_empty()
		else GrenadeProfile.load_profile()
	)
	_build_particles()
	_foley = FoleyEngine.new()
	add_child(_foley)
	_foley.play_cue(&"smoke_hiss", global_position, -5.0, 0.92)
	var manager := get_node_or_null("/root/TacticalOcclusionManager")
	if manager != null:
		manager.call("register_cloud", self)


func apply_graphics_preset() -> void:
	if _particles == null:
		return
	var presentation := get_node_or_null("/root/PresentationSettings")
	if presentation != null:
		_particles.amount = int(
			presentation.call("scaled_effect_count", particle_amount, 56)
		)


func configure_profile(raw_profile: Dictionary) -> void:
	profile_override = GrenadeProfile.normalize(raw_profile)
	if is_node_ready():
		_apply_profile(profile_override)


func _apply_profile(profile: Dictionary) -> void:
	var values: Dictionary = profile.get("smoke", {})
	maximum_radius = float(values.get("maximum_radius", maximum_radius))
	sprout_seconds = float(values.get("sprout_seconds", sprout_seconds))
	dense_seconds = float(values.get("dense_seconds", dense_seconds))
	dissipate_seconds = float(values.get("dissipate_seconds", dissipate_seconds))
	particle_amount = int(values.get("particle_amount", particle_amount))
	particle_lifetime = float(values.get("particle_lifetime", particle_lifetime))
	emission_radius = float(values.get("emission_radius", emission_radius))
	puff_size_min = float(values.get("puff_size_min", puff_size_min))
	puff_size_max = float(values.get("puff_size_max", puff_size_max))
	visual_opacity = float(values.get("visual_opacity", visual_opacity))


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
	var presentation := get_node_or_null("/root/PresentationSettings")
	_particles.amount = (
		int(presentation.call("scaled_effect_count", particle_amount, 56))
		if presentation != null
		else particle_amount
	)
	_particles.lifetime = particle_lifetime
	_particles.randomness = 0.72
	_particles.visibility_aabb = AABB(Vector3(-7, -2, -7), Vector3(14, 8, 14))
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = emission_radius
	process.initial_velocity_min = 0.08
	process.initial_velocity_max = 0.45
	process.gravity = Vector3(0.0, 0.10, 0.0)
	process.scale_min = puff_size_min
	process.scale_max = puff_size_max
	_particles.process_material = process
	var quad := QuadMesh.new()
	quad.size = Vector2(1.7, 1.7)
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.46, 0.49, 0.45, visual_opacity)
	var alpha_gradient := Gradient.new()
	alpha_gradient.offsets = PackedFloat32Array([0.0, 0.42, 0.78, 1.0])
	alpha_gradient.colors = PackedColorArray([
		Color(1.0, 1.0, 1.0, 0.96),
		Color(1.0, 1.0, 1.0, 0.78),
		Color(1.0, 1.0, 1.0, 0.24),
		Color(1.0, 1.0, 1.0, 0.0),
	])
	var soft_puff_texture := GradientTexture2D.new()
	soft_puff_texture.width = 96
	soft_puff_texture.height = 96
	soft_puff_texture.fill = GradientTexture2D.FILL_RADIAL
	soft_puff_texture.fill_from = Vector2(0.5, 0.5)
	soft_puff_texture.fill_to = Vector2(1.0, 0.5)
	soft_puff_texture.gradient = alpha_gradient
	material.albedo_texture = soft_puff_texture
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	quad.material = material
	_particles.draw_pass_1 = quad
	add_child(_particles)
