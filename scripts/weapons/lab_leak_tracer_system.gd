class_name LabLeakTracerSystem
extends Node3D

## Project Lab Leak: Zero-Allocation High-Performance Tracer & VFX System
## Pre-allocates all visual meshes, particle emitters, and tracers once at startup
## to guarantee 144+ FPS with ZERO garbage collection or physics node lag during full-auto fire.

const POOL_SIZE := 48
const SHELL_POOL_SIZE := 24
const BLOOD_PARTICLE_POOL_SIZE := 8
const BLOOD_MARK_POOL_SIZE := 32

static var _is_initialized := false
static var _tracer_pool: Array[MeshInstance3D] = []
static var _tracer_index: int = 0
static var _spark_emitter: CPUParticles3D
static var _muzzle_flash_light: OmniLight3D
static var _muzzle_flash_star: MeshInstance3D
static var _trajectory_debug_enabled := false
static var _shell_pool: Array[MeshInstance3D] = []
static var _shell_tweens: Array[Tween] = []
static var _shell_index: int = 0
static var _blood_emitters: Array[CPUParticles3D] = []
static var _blood_emitter_index: int = 0
static var _blood_marks: Array[MeshInstance3D] = []
static var _blood_mark_tweens: Array[Tween] = []
static var _blood_mark_index: int = 0

static func initialize(parent: Node) -> void:
	if _is_initialized and _spark_emitter and is_instance_valid(_spark_emitter):
		return
	_tracer_pool.clear()
	_tracer_index = 0
	_shell_pool.clear()
	_shell_tweens.clear()
	_shell_index = 0
	_blood_emitters.clear()
	_blood_emitter_index = 0
	_blood_marks.clear()
	_blood_mark_tweens.clear()
	_blood_mark_index = 0

	# 1. Pre-allocate 16 Reusable Tracer Mesh Instances
	for i in range(POOL_SIZE):
		var mi := MeshInstance3D.new()
		mi.name = "PooledTracer_%d" % i
		var im := ImmediateMesh.new()
		mi.mesh = im

		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color(1.0, 0.88, 0.35)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mi.material_override = mat
		mi.visible = false
		parent.add_child(mi)
		_tracer_pool.append(mi)

	# Reusable presentation-only casings. Shot authority remains hitscan and no
	# physics body is created per shot, so this is safe for sustained 8v8 fire.
	for i in range(SHELL_POOL_SIZE):
		var shell := MeshInstance3D.new()
		shell.name = "PooledShell_%d" % i
		var shell_mesh := CylinderMesh.new()
		shell_mesh.top_radius = 0.008
		shell_mesh.bottom_radius = 0.008
		shell_mesh.height = 0.032
		shell.mesh = shell_mesh
		var shell_material := StandardMaterial3D.new()
		shell_material.albedo_color = Color(0.72, 0.51, 0.20)
		shell_material.metallic = 0.75
		shell_material.roughness = 0.35
		shell.material_override = shell_material
		shell.visible = false
		parent.add_child(shell)
		_shell_pool.append(shell)
		_shell_tweens.append(null)

	# 2. Pre-allocate Single Reusable Impact Spark Emitter
	_spark_emitter = CPUParticles3D.new()
	_spark_emitter.name = "PooledSparkEmitter"
	_spark_emitter.emitting = false
	_spark_emitter.one_shot = true
	_spark_emitter.explosiveness = 1.0
	_spark_emitter.lifetime = 0.18
	var presentation := tree_root_presentation(parent)
	_spark_emitter.amount = (
		int(presentation.call("scaled_effect_count", 6, 2))
		if presentation != null
		else 6
	)
	_spark_emitter.spread = 55.0
	_spark_emitter.initial_velocity_min = 4.0
	_spark_emitter.initial_velocity_max = 7.0
	_spark_emitter.gravity = Vector3(0, -12.0, 0)

	var s_mat := StandardMaterial3D.new()
	s_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	s_mat.albedo_color = Color(1.0, 0.95, 0.5)
	_spark_emitter.material_override = s_mat

	var s_mesh := SphereMesh.new()
	s_mesh.radius = 0.015
	s_mesh.height = 0.03
	_spark_emitter.mesh = s_mesh
	parent.add_child(_spark_emitter)

	# Character-hit presentation is pooled separately from world sparks. It is
	# triggered only after authoritative damage accepts the hit.
	for i in range(BLOOD_PARTICLE_POOL_SIZE):
		var blood := CPUParticles3D.new()
		blood.name = "PooledBloodEmitter_%d" % i
		blood.emitting = false
		blood.one_shot = true
		blood.explosiveness = 1.0
		blood.lifetime = 0.24
		blood.amount = 9
		blood.spread = 42.0
		blood.initial_velocity_min = 1.4
		blood.initial_velocity_max = 3.8
		blood.gravity = Vector3(0.0, -7.5, 0.0)
		var blood_material := StandardMaterial3D.new()
		blood_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		blood_material.albedo_color = Color(0.52, 0.015, 0.02, 0.92)
		blood.material_override = blood_material
		var droplet := SphereMesh.new()
		droplet.radius = 0.012
		droplet.height = 0.024
		blood.mesh = droplet
		parent.add_child(blood)
		_blood_emitters.append(blood)

	for i in range(BLOOD_MARK_POOL_SIZE):
		var mark := MeshInstance3D.new()
		mark.name = "PooledBloodEntry_%d" % i
		var disk := CylinderMesh.new()
		disk.top_radius = 0.022
		disk.bottom_radius = 0.022
		disk.height = 0.003
		disk.radial_segments = 12
		mark.mesh = disk
		var mark_material := StandardMaterial3D.new()
		mark_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mark_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mark_material.albedo_color = Color(0.34, 0.005, 0.01, 0.94)
		mark.material_override = mark_material
		mark.visible = false
		parent.add_child(mark)
		_blood_marks.append(mark)
		_blood_mark_tweens.append(null)

	# 3. Pre-allocate Muzzle Flash Point Light & Star
	_muzzle_flash_light = OmniLight3D.new()
	_muzzle_flash_light.name = "PooledMuzzleLight"
	_muzzle_flash_light.light_color = Color(1.0, 0.82, 0.35)
	_muzzle_flash_light.light_energy = 0.0
	_muzzle_flash_light.omni_range = 6.0
	_muzzle_flash_light.visible = (
		bool(presentation.call("effect_lights_enabled"))
		if presentation != null
		else true
	)
	parent.add_child(_muzzle_flash_light)

	_is_initialized = true


static func tree_root_presentation(parent: Node) -> Node:
	if parent == null or parent.get_tree() == null:
		return null
	return parent.get_tree().root.get_node_or_null("PresentationSettings")

static func spawn_muzzle_flash(tree: SceneTree, muzzle_pos: Vector3) -> void:
	if not _is_initialized or not _muzzle_flash_light:
		initialize(tree.current_scene)

	if _muzzle_flash_light and is_instance_valid(_muzzle_flash_light):
		_muzzle_flash_light.global_position = muzzle_pos
		_muzzle_flash_light.light_energy = 4.5
		var t := _muzzle_flash_light.create_tween()
		t.tween_property(_muzzle_flash_light, "light_energy", 0.0, 0.04)

static func spawn_tracer(
	tree: SceneTree,
	start_pos: Vector3,
	end_pos: Vector3,
	color: Color = Color(1.0, 0.88, 0.35),
	muzzle_velocity_mps: float = 715.0
) -> void:
	if not _is_initialized or _tracer_pool.is_empty():
		initialize(tree.current_scene)

	var tracer: MeshInstance3D = _tracer_pool[_tracer_index]
	_tracer_index = (_tracer_index + 1) % POOL_SIZE

	var im := tracer.mesh as ImmediateMesh
	if im:
		im.clear_surfaces()
		im.surface_begin(Mesh.PRIMITIVE_LINES)
		im.surface_add_vertex(start_pos)
		im.surface_add_vertex(end_pos)
		im.surface_end()

	var mat := tracer.material_override as StandardMaterial3D
	if mat:
		mat.albedo_color = color

	tracer.visible = true

	# Study lines persist until F6 clears them. Normal gameplay tracers retain
	# their brief flash so debug behavior never leaks into the presentation mode.
	if not _trajectory_debug_enabled:
		var t := tracer.create_tween()
		# Hit detection remains immediate and server-authoritative. Velocity from
		# Gunsmith controls only how long the presentation streak takes to cross
		# the measured distance, capped so long-range fire stays readable.
		var visual_travel_seconds := clampf(
			start_pos.distance_to(end_pos) / maxf(muzzle_velocity_mps, 1.0),
			0.025,
			0.12
		)
		t.tween_interval(visual_travel_seconds)
		t.tween_property(mat, "albedo_color:a", 0.0, 0.035)
		t.tween_callback(func(): if tracer and is_instance_valid(tracer): tracer.visible = false)

static func set_trajectory_debug_enabled(enabled: bool) -> void:
	_trajectory_debug_enabled = enabled
	if not enabled:
		for tracer in _tracer_pool:
			if tracer and is_instance_valid(tracer):
				tracer.visible = false

static func is_trajectory_debug_enabled() -> bool:
	return _trajectory_debug_enabled

static func spawn_trajectory_reference(
	tree: SceneTree,
	start_pos: Vector3,
	end_pos: Vector3,
	color: Color
) -> void:
	if not _trajectory_debug_enabled:
		return
	spawn_tracer(tree, start_pos, end_pos, color)

static func spawn_impact_effect(tree: SceneTree, hit_pos: Vector3, hit_normal: Vector3) -> void:
	if not _is_initialized or not _spark_emitter or not is_instance_valid(_spark_emitter):
		initialize(tree.current_scene)

	_spark_emitter.global_position = hit_pos
	_spark_emitter.direction = hit_normal + Vector3(0, 0.4, 0)
	_spark_emitter.restart()


static func spawn_body_hit_effect(
	tree: SceneTree,
	hit_pos: Vector3,
	hit_normal: Vector3,
	is_headshot: bool = false
) -> void:
	if not _is_initialized or _blood_emitters.is_empty() or _blood_marks.is_empty():
		initialize(tree.current_scene)
	var normal := hit_normal.normalized()
	if normal.length_squared() < 0.50:
		normal = Vector3.UP

	var blood := _blood_emitters[_blood_emitter_index]
	_blood_emitter_index = (_blood_emitter_index + 1) % BLOOD_PARTICLE_POOL_SIZE
	blood.global_position = hit_pos + normal * 0.012
	blood.direction = (normal + Vector3.UP * 0.16).normalized()
	blood.amount = 14 if is_headshot else 9
	blood.restart()

	var index := _blood_mark_index
	_blood_mark_index = (_blood_mark_index + 1) % BLOOD_MARK_POOL_SIZE
	var old_tween := _blood_mark_tweens[index]
	if old_tween != null and old_tween.is_valid():
		old_tween.kill()
	var mark := _blood_marks[index]
	var material := mark.material_override as StandardMaterial3D
	mark.global_position = hit_pos + normal * 0.006
	mark.quaternion = Quaternion(Vector3.UP, normal)
	mark.scale = Vector3.ONE * (1.30 if is_headshot else 1.0)
	if material != null:
		material.albedo_color = Color(0.42, 0.006, 0.012, 0.94)
	mark.visible = true
	var tween := mark.create_tween()
	_blood_mark_tweens[index] = tween
	tween.tween_interval(1.15)
	if material != null:
		tween.tween_property(material, "albedo_color:a", 0.0, 0.35)
	tween.tween_callback(func(): if mark and is_instance_valid(mark): mark.visible = false)

static func spawn_shell_casing(tree: SceneTree, eject_pos: Vector3, eject_dir: Vector3) -> void:
	if not _is_initialized or _shell_pool.is_empty():
		initialize(tree.current_scene)
	var index := _shell_index
	_shell_index = (_shell_index + 1) % SHELL_POOL_SIZE
	var old_tween := _shell_tweens[index]
	if old_tween != null and old_tween.is_valid():
		old_tween.kill()
	var shell := _shell_pool[index]
	var direction := eject_dir.normalized()
	if direction.length_squared() < 0.99:
		direction = Vector3.RIGHT
	shell.global_position = eject_pos
	shell.global_rotation = Vector3.ZERO
	shell.visible = true
	var flight_time := 0.34
	var destination := eject_pos + direction * 0.48 + Vector3.DOWN * 0.24
	var tween := shell.create_tween()
	_shell_tweens[index] = tween
	tween.set_parallel(true)
	tween.tween_property(shell, "global_position", destination, flight_time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(shell, "rotation_degrees", Vector3(420.0, 690.0, 260.0), flight_time)
	tween.set_parallel(false)
	tween.tween_callback(func(): if shell and is_instance_valid(shell): shell.visible = false)
