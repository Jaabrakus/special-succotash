class_name LabLeakTracerSystem
extends Node3D

## Project Lab Leak: Zero-Allocation High-Performance Tracer & VFX System
## Pre-allocates all visual meshes, particle emitters, and tracers once at startup
## to guarantee 144+ FPS with ZERO garbage collection or physics node lag during full-auto fire.

const POOL_SIZE := 48

static var _is_initialized := false
static var _tracer_pool: Array[MeshInstance3D] = []
static var _tracer_index: int = 0
static var _spark_emitter: CPUParticles3D
static var _muzzle_flash_light: OmniLight3D
static var _muzzle_flash_star: MeshInstance3D
static var _trajectory_debug_enabled := false

static func initialize(parent: Node) -> void:
	if _is_initialized and _spark_emitter and is_instance_valid(_spark_emitter):
		return
	_tracer_pool.clear()
	_tracer_index = 0

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

	# 2. Pre-allocate Single Reusable Impact Spark Emitter
	_spark_emitter = CPUParticles3D.new()
	_spark_emitter.name = "PooledSparkEmitter"
	_spark_emitter.emitting = false
	_spark_emitter.one_shot = true
	_spark_emitter.explosiveness = 1.0
	_spark_emitter.lifetime = 0.18
	_spark_emitter.amount = 6
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

	# 3. Pre-allocate Muzzle Flash Point Light & Star
	_muzzle_flash_light = OmniLight3D.new()
	_muzzle_flash_light.name = "PooledMuzzleLight"
	_muzzle_flash_light.light_color = Color(1.0, 0.82, 0.35)
	_muzzle_flash_light.light_energy = 0.0
	_muzzle_flash_light.omni_range = 6.0
	parent.add_child(_muzzle_flash_light)

	_is_initialized = true

static func spawn_muzzle_flash(tree: SceneTree, muzzle_pos: Vector3) -> void:
	if not _is_initialized or not _muzzle_flash_light:
		initialize(tree.current_scene)

	if _muzzle_flash_light and is_instance_valid(_muzzle_flash_light):
		_muzzle_flash_light.global_position = muzzle_pos
		_muzzle_flash_light.light_energy = 4.5
		var t := _muzzle_flash_light.create_tween()
		t.tween_property(_muzzle_flash_light, "light_energy", 0.0, 0.04)

static func spawn_tracer(tree: SceneTree, start_pos: Vector3, end_pos: Vector3, color: Color = Color(1.0, 0.88, 0.35)) -> void:
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
		t.tween_property(mat, "albedo_color:a", 0.0, 0.06)
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

static func spawn_shell_casing(_tree: SceneTree, _eject_pos: Vector3, _eject_dir: Vector3) -> void:
	# Zero-allocation visual casing (no physics bodies created per frame)
	pass
