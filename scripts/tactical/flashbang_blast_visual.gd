class_name TacticalFlashbangBlastVisual
extends Node3D

var blast_radius := 18.0
var age := 0.0
var lifetime_seconds := 1.35
var bright_particles: GPUParticles3D
var smoke_particles: GPUParticles3D
var smoke_radius_shell: MeshInstance3D
var smoke_shell_material: StandardMaterial3D
var flash_light: OmniLight3D


func configure(radius: float) -> void:
	blast_radius = maxf(radius, 0.5)


func _ready() -> void:
	add_to_group("flashbang_blast_visuals")
	_build_bright_burst()
	_build_smoke_burst()
	_build_radius_shell()
	_build_flash_light()


func _process(delta: float) -> void:
	age += maxf(delta, 0.0)
	var progress := clampf(age / lifetime_seconds, 0.0, 1.0)
	var expansion := smoothstep(0.0, 1.0, minf(progress / 0.72, 1.0))
	if smoke_radius_shell != null:
		smoke_radius_shell.scale = Vector3.ONE * lerpf(0.06, blast_radius, expansion)
		var shell_alpha := (
			0.15 * smoothstep(0.0, 0.12, progress) * (1.0 - smoothstep(0.48, 1.0, progress))
		)
		smoke_shell_material.albedo_color.a = shell_alpha
	if flash_light != null:
		flash_light.light_energy = 12.0 * (1.0 - smoothstep(0.0, 0.22, progress))
	if progress >= 1.0:
		queue_free()


func _build_bright_burst() -> void:
	bright_particles = GPUParticles3D.new()
	bright_particles.name = "FlashFragmentBurst"
	bright_particles.one_shot = true
	bright_particles.amount = 128
	bright_particles.lifetime = 0.72
	bright_particles.explosiveness = 1.0
	bright_particles.randomness = 0.38
	bright_particles.visibility_aabb = AABB(
		Vector3.ONE * -blast_radius,
		Vector3.ONE * blast_radius * 2.0
	)
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = 0.12
	process.direction = Vector3.UP
	process.spread = 180.0
	process.initial_velocity_min = blast_radius * 0.36
	process.initial_velocity_max = blast_radius * 0.72
	process.gravity = Vector3(0.0, -5.5, 0.0)
	process.scale_min = 0.018
	process.scale_max = 0.055
	bright_particles.process_material = process
	var spark_mesh := SphereMesh.new()
	spark_mesh.radius = 0.035
	spark_mesh.height = 0.07
	var spark_material := StandardMaterial3D.new()
	spark_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	spark_material.albedo_color = Color(1.0, 0.92, 0.68, 1.0)
	spark_material.emission_enabled = true
	spark_material.emission = Color(1.0, 0.82, 0.42)
	spark_material.emission_energy_multiplier = 5.0
	spark_mesh.material = spark_material
	bright_particles.draw_pass_1 = spark_mesh
	add_child(bright_particles)
	bright_particles.emitting = true


func _build_smoke_burst() -> void:
	smoke_particles = GPUParticles3D.new()
	smoke_particles.name = "FlashSmokeRadiusBurst"
	smoke_particles.one_shot = true
	smoke_particles.amount = 180
	smoke_particles.lifetime = 1.10
	smoke_particles.explosiveness = 0.96
	smoke_particles.randomness = 0.56
	smoke_particles.visibility_aabb = AABB(
		Vector3.ONE * -blast_radius * 1.15,
		Vector3.ONE * blast_radius * 2.30
	)
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = 0.18
	process.direction = Vector3.UP
	process.spread = 180.0
	process.initial_velocity_min = blast_radius * 0.62
	process.initial_velocity_max = blast_radius * 1.02
	process.gravity = Vector3(0.0, 0.35, 0.0)
	process.damping_min = 1.8
	process.damping_max = 3.2
	process.scale_min = 0.55
	process.scale_max = 1.35
	var color_gradient := Gradient.new()
	color_gradient.offsets = PackedFloat32Array([0.0, 0.18, 0.68, 1.0])
	color_gradient.colors = PackedColorArray([
		Color(0.92, 0.92, 0.88, 0.82),
		Color(0.76, 0.78, 0.75, 0.64),
		Color(0.58, 0.61, 0.60, 0.26),
		Color(0.50, 0.52, 0.52, 0.0),
	])
	var color_ramp := GradientTexture1D.new()
	color_ramp.gradient = color_gradient
	process.color_ramp = color_ramp
	smoke_particles.process_material = process
	var puff := QuadMesh.new()
	puff.size = Vector2(1.35, 1.35)
	var puff_material := StandardMaterial3D.new()
	puff_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	puff_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	puff_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	puff_material.albedo_color = Color(0.74, 0.76, 0.73, 0.72)
	var alpha_gradient := Gradient.new()
	alpha_gradient.offsets = PackedFloat32Array([0.0, 0.48, 0.82, 1.0])
	alpha_gradient.colors = PackedColorArray([
		Color(1.0, 1.0, 1.0, 0.96),
		Color(1.0, 1.0, 1.0, 0.72),
		Color(1.0, 1.0, 1.0, 0.18),
		Color(1.0, 1.0, 1.0, 0.0),
	])
	var puff_texture := GradientTexture2D.new()
	puff_texture.width = 64
	puff_texture.height = 64
	puff_texture.fill = GradientTexture2D.FILL_RADIAL
	puff_texture.fill_from = Vector2(0.5, 0.5)
	puff_texture.fill_to = Vector2(1.0, 0.5)
	puff_texture.gradient = alpha_gradient
	puff_material.albedo_texture = puff_texture
	puff.material = puff_material
	smoke_particles.draw_pass_1 = puff
	add_child(smoke_particles)
	smoke_particles.emitting = true


func _build_radius_shell() -> void:
	smoke_radius_shell = MeshInstance3D.new()
	smoke_radius_shell.name = "FlashSmokeBlastRadius"
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 32
	sphere.rings = 16
	smoke_shell_material = StandardMaterial3D.new()
	smoke_shell_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smoke_shell_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smoke_shell_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	smoke_shell_material.albedo_color = Color(0.74, 0.78, 0.76, 0.0)
	sphere.material = smoke_shell_material
	smoke_radius_shell.mesh = sphere
	smoke_radius_shell.scale = Vector3.ONE * 0.06
	add_child(smoke_radius_shell)


func _build_flash_light() -> void:
	flash_light = OmniLight3D.new()
	flash_light.name = "FlashDetonationLight"
	flash_light.light_color = Color(1.0, 0.93, 0.78)
	flash_light.light_energy = 12.0
	flash_light.omni_range = minf(blast_radius, 24.0)
	add_child(flash_light)
