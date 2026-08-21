class_name TacticalFragBlastVisual
extends Node3D

var blast_radius := 7.0
var age := 0.0
var lifetime_seconds := 1.0
var smoke_particle_amount := 220
var smoke_opacity := 0.24
var spark_particles: GPUParticles3D
var smoke_particles: GPUParticles3D
var smoke_radius_shell: MeshInstance3D
var smoke_shell_material: StandardMaterial3D
var blast_light: OmniLight3D


func configure(
	radius: float,
	duration: float = 1.0,
	particle_amount: int = 220,
	opacity: float = 0.24
) -> void:
	blast_radius = maxf(radius, 0.5)
	lifetime_seconds = clampf(duration, 0.25, 1.50)
	smoke_particle_amount = clampi(particle_amount, 24, 500)
	smoke_opacity = clampf(opacity, 0.04, 0.55)


func _ready() -> void:
	add_to_group("frag_blast_visuals")
	_build_spark_burst()
	_build_smoke_burst()
	_build_radius_shell()
	_build_blast_light()


func _process(delta: float) -> void:
	age += maxf(delta, 0.0)
	var progress := clampf(age / lifetime_seconds, 0.0, 1.0)
	# Reach the authoritative damage radius quickly, hold for one readable
	# instant, then disappear. This is a visual meter only; it never decides hits.
	var expansion := smoothstep(0.0, 1.0, minf(progress / 0.46, 1.0))
	if smoke_radius_shell != null:
		smoke_radius_shell.scale = Vector3.ONE * lerpf(0.05, blast_radius, expansion)
		var shell_alpha := (
			smoke_opacity
			* smoothstep(0.0, 0.07, progress)
			* (1.0 - smoothstep(0.48, 0.94, progress))
		)
		smoke_shell_material.albedo_color.a = shell_alpha
	if blast_light != null:
		blast_light.light_energy = 15.0 * (1.0 - smoothstep(0.0, 0.24, progress))
	if progress >= 1.0:
		queue_free()


func _build_spark_burst() -> void:
	spark_particles = GPUParticles3D.new()
	spark_particles.name = "FragSparkBurst"
	spark_particles.one_shot = true
	spark_particles.amount = clampi(int(round(smoke_particle_amount * 0.68)), 24, 320)
	spark_particles.lifetime = lifetime_seconds * 0.70
	spark_particles.explosiveness = 1.0
	spark_particles.randomness = 0.42
	spark_particles.visibility_aabb = AABB(
		Vector3.ONE * -blast_radius,
		Vector3.ONE * blast_radius * 2.0
	)
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = 0.10
	process.direction = Vector3.UP
	process.spread = 180.0
	var safe_spark_speed := (blast_radius - 0.15) / maxf(spark_particles.lifetime, 0.01)
	process.initial_velocity_min = safe_spark_speed * 0.42
	process.initial_velocity_max = safe_spark_speed * 0.88
	process.gravity = Vector3(0.0, -7.5, 0.0)
	process.scale_min = 0.025
	process.scale_max = 0.075
	spark_particles.process_material = process
	var fragment_mesh := SphereMesh.new()
	fragment_mesh.radius = 0.030
	fragment_mesh.height = 0.060
	var fragment_material := StandardMaterial3D.new()
	fragment_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fragment_material.albedo_color = Color(1.0, 0.62, 0.16, 1.0)
	fragment_material.emission_enabled = true
	fragment_material.emission = Color(1.0, 0.28, 0.035)
	fragment_material.emission_energy_multiplier = 6.0
	fragment_mesh.material = fragment_material
	spark_particles.draw_pass_1 = fragment_mesh
	add_child(spark_particles)
	spark_particles.emitting = true


func _build_smoke_burst() -> void:
	smoke_particles = GPUParticles3D.new()
	smoke_particles.name = "FragSmokeRadiusBurst"
	smoke_particles.one_shot = true
	smoke_particles.amount = smoke_particle_amount
	smoke_particles.lifetime = lifetime_seconds * 0.88
	smoke_particles.explosiveness = 1.0
	smoke_particles.randomness = 0.50
	smoke_particles.visibility_aabb = AABB(
		Vector3.ONE * -blast_radius,
		Vector3.ONE * blast_radius * 2.0
	)
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = 0.14
	process.direction = Vector3.UP
	process.spread = 180.0
	# Even with no damping, a puff cannot travel beyond the damage radius.
	# Damping then pulls the visible cloud slightly inside that hard boundary.
	var safe_smoke_speed := (blast_radius - 0.72) / maxf(smoke_particles.lifetime, 0.01)
	process.initial_velocity_min = safe_smoke_speed * 0.48
	process.initial_velocity_max = safe_smoke_speed * 0.92
	process.gravity = Vector3(0.0, 0.18, 0.0)
	process.damping_min = 3.5
	process.damping_max = 6.0
	process.scale_min = 0.42
	process.scale_max = 1.10
	var color_gradient := Gradient.new()
	color_gradient.offsets = PackedFloat32Array([0.0, 0.15, 0.64, 1.0])
	color_gradient.colors = PackedColorArray([
		Color(0.96, 0.72, 0.42, 0.84),
		Color(0.54, 0.48, 0.40, 0.68),
		Color(0.30, 0.32, 0.32, 0.30),
		Color(0.24, 0.25, 0.25, 0.0),
	])
	var color_ramp := GradientTexture1D.new()
	color_ramp.gradient = color_gradient
	process.color_ramp = color_ramp
	smoke_particles.process_material = process
	var puff := QuadMesh.new()
	puff.size = Vector2(1.30, 1.30)
	var puff_material := StandardMaterial3D.new()
	puff_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	puff_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	puff_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	puff_material.albedo_color = Color(0.55, 0.52, 0.48, minf(0.88, smoke_opacity * 3.25))
	var alpha_gradient := Gradient.new()
	alpha_gradient.offsets = PackedFloat32Array([0.0, 0.42, 0.80, 1.0])
	alpha_gradient.colors = PackedColorArray([
		Color(1.0, 1.0, 1.0, 0.96),
		Color(1.0, 1.0, 1.0, 0.72),
		Color(1.0, 1.0, 1.0, 0.16),
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
	smoke_radius_shell.name = "FragSmokeBlastRadius"
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 32
	sphere.rings = 16
	smoke_shell_material = StandardMaterial3D.new()
	smoke_shell_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smoke_shell_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smoke_shell_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	smoke_shell_material.albedo_color = Color(0.43, 0.40, 0.35, 0.0)
	sphere.material = smoke_shell_material
	smoke_radius_shell.mesh = sphere
	smoke_radius_shell.scale = Vector3.ONE * 0.05
	add_child(smoke_radius_shell)


func _build_blast_light() -> void:
	blast_light = OmniLight3D.new()
	blast_light.name = "FragDetonationLight"
	blast_light.light_color = Color(1.0, 0.42, 0.10)
	blast_light.light_energy = 15.0
	blast_light.omni_range = blast_radius
	add_child(blast_light)
