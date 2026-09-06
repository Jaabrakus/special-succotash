extends SceneTree

const KIT_PATH := "res://scenes/props/tactical_courtyard_kit.tscn"
const ASSET_PATH := "res://assets/environment/tactical_courtyard_kit/"
const MODULE_NAMES := ["plaster_wall_3m", "plaster_doorway_3m", "concrete_stairs_6step", "wood_supply_crate_1m", "corrugated_cover_2m"]
var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var imported_mesh_count: int = 0
	for module_name: String in MODULE_NAMES:
		var packed := load(ASSET_PATH + module_name + ".glb") as PackedScene
		_check(packed != null, "GLB imports: " + module_name)
		if packed == null:
			continue
		var instance := packed.instantiate() as Node3D
		root.add_child(instance)
		var meshes := instance.find_children("*", "MeshInstance3D", true, false)
		if instance is MeshInstance3D:
			meshes.append(instance)
		_check(meshes.size() == 1, "one runtime mesh: " + module_name)
		for mesh_node: MeshInstance3D in meshes:
			imported_mesh_count += 1
			_check(mesh_node.mesh != null and mesh_node.mesh.get_surface_count() == 1, "one material surface: " + module_name)
			var material := mesh_node.get_active_material(0) as StandardMaterial3D
			_check(material != null and material.albedo_texture != null, "color atlas imported: " + module_name)
			if material != null:
				_check(material.roughness > 0.9, "matte material: " + module_name)
				_check(material.cull_mode == BaseMaterial3D.CULL_BACK, "backface culling: " + module_name)
			var bounds := mesh_node.global_transform * mesh_node.get_aabb()
			_check(absf(bounds.position.y) < 0.001, "ground anchor: " + module_name)
			_check(bounds.size.y >= 0.99 and bounds.size.y <= 3.01, "meter scale: " + module_name)
		instance.free()
	var prefab := load(KIT_PATH) as PackedScene
	_check(prefab != null, "prefab loads")
	if prefab == null:
		quit(1)
		return
	var kit := prefab.instantiate() as StaticBody3D
	_check(kit != null, "one StaticBody3D owns kit collision")
	root.add_child(kit)
	_check(kit.find_children("*", "PhysicsBody3D", true, false).is_empty(), "no nested collision authorities")
	_check(kit.find_children("*", "CollisionShape3D", true, false).size() == 23, "23 bounded collision shapes")
	await physics_frame
	await physics_frame
	var world := kit.get_world_3d().direct_space_state
	var doorway := PhysicsRayQueryParameters3D.create(Vector3(0, 1, -2), Vector3(0, 1, -4), 1)
	_check(world.intersect_ray(doorway).is_empty(), "doorway is physically open")
	var wall := PhysicsRayQueryParameters3D.create(Vector3(-3, 1, -2), Vector3(-3, 1, -4), 1)
	_check(not world.intersect_ray(wall).is_empty(), "wall is physical cover")
	for step: int in range(6):
		var z: float = -0.7 - step * 0.32
		var ray := PhysicsRayQueryParameters3D.create(Vector3(3, 2, z), Vector3(3, -0.1, z), 1)
		var hit := world.intersect_ray(ray)
		_check(not hit.is_empty(), "stair collision exists: %d" % (step + 1))
		if not hit.is_empty():
			var expected_height: float = (step + 1) * 0.18
			var point: Vector3 = hit["position"]
			_check(absf(point.y - expected_height) < 0.001, "stair %d actual height %.3f m" % [step + 1, point.y])
	if OS.get_cmdline_user_args().has("--render"):
		await _render_prefab(kit)
	print("[COURTYARD ASSETS] %s: %d GLB meshes; doorway, wall and six stair heights checked; CharacterBody traversal not asserted" % ["PASS" if failures == 0 else "FAIL", imported_mesh_count])
	kit.free()
	quit(0 if failures == 0 else 1)


func _render_prefab(kit: Node3D) -> void:
	root.size = Vector2i(1600, 1200)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.14, 0.16, 0.14)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.7, 0.77, 0.85)
	environment.ambient_light_energy = 0.65
	var world := WorldEnvironment.new()
	world.environment = environment
	kit.add_child(world)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-48, -35, 0)
	light.light_color = Color(1, 0.87, 0.69)
	light.light_energy = 1.6
	light.shadow_enabled = true
	kit.add_child(light)
	var camera := Camera3D.new()
	kit.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 11.5
	camera.position = Vector3(11, 11, 15)
	camera.look_at(Vector3(0, 1, -0.35))
	camera.current = true
	for frame: int in range(8):
		await process_frame
	await RenderingServer.frame_post_draw
	var capture := root.get_texture().get_image()
	var path := "res://art_source/tactical_courtyard_kit/godot_import_preview.png"
	_check(capture.save_png(path) == OK, "Godot rendered imported prefab: " + path)


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		push_error("[COURTYARD ASSETS] FAIL: " + label)
	else:
		print("[COURTYARD ASSETS] PASS: " + label)
