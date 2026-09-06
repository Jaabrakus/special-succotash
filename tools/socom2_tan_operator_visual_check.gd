extends SceneTree

## Display-backed proof of the exact model instantiated by operator_player.tscn.
## Bounds-based framing avoids assumptions from older character imports.

const PLAYER_SCENE := "res://scenes/player/operator_player.tscn"
const REAR_CAPTURE := "/private/tmp/socom2-tan-operator-canonical-rear.png"
const SIDE_CAPTURE := "/private/tmp/socom2-tan-operator-canonical-side.png"

var failures: Array[String] = []
var camera: Camera3D


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1100, 1100)
	var packed := load(PLAYER_SCENE) as PackedScene
	_expect(packed != null, "canonical operator player loads")
	if packed == null:
		_finish()
		return
	var player := packed.instantiate() as CharacterBody3D
	player.process_mode = Node.PROCESS_MODE_DISABLED
	root.add_child(player)
	_install_stage()
	for _frame in range(12):
		await process_frame
	var model := player.get_node_or_null("Mannequin/ProductionAnimation/TrooperModel") as Node3D
	_expect(model != null, "canonical player contains TrooperModel")
	_expect(model != null and model.find_child("RearArmorAndWebbing", true, false) is MeshInstance3D, "canonical player contains reviewed rear gear")
	if model == null:
		_finish()
		return
	var bounds := _skinned_character_bounds(model)
	_expect(bounds.size.length() > 0.1, "canonical rendered bounds are non-empty")
	var target := bounds.get_center()
	var half_height := maxf(bounds.size.y * 0.5, 0.5)
	var distance := maxf(half_height / tan(deg_to_rad(camera.fov * 0.5)) * 1.25, 2.8)
	target.y += 0.08
	await _capture_view(REAR_CAPTURE, target + Vector3(0.0, 0.04, 1.0).normalized() * distance, target)
	await _capture_view(SIDE_CAPTURE, target + Vector3(1.0, 0.04, 0.08).normalized() * distance, target)
	_finish()


func _install_stage() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("26313a")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("aab7bf")
	environment.ambient_light_energy = 0.62
	var world := WorldEnvironment.new()
	world.environment = environment
	root.add_child(world)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-48.0, -32.0, 0.0)
	key.light_color = Color("ffe0b2")
	key.light_energy = 1.05
	key.shadow_enabled = true
	root.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-24.0, 142.0, 0.0)
	fill.light_color = Color("96b9d8")
	fill.light_energy = 0.32
	root.add_child(fill)
	var floor := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(12.0, 12.0)
	floor.mesh = plane
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color("4b565d")
	floor_material.roughness = 0.96
	floor.material_override = floor_material
	root.add_child(floor)
	camera = Camera3D.new()
	camera.fov = 39.0
	camera.current = true
	root.add_child(camera)


func _capture_view(path: String, position: Vector3, target: Vector3) -> void:
	camera.global_position = position
	camera.look_at(target, Vector3.UP)
	for _frame in range(4):
		await process_frame
	RenderingServer.force_draw()
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	_expect(image != null and not image.is_empty(), "%s is readable" % path)
	if image != null and not image.is_empty():
		_expect(image.save_png(path) == OK, "%s saves" % path)


func _skinned_character_bounds(node: Node) -> AABB:
	var points: Array[Vector3] = []
	_collect_skinned_character_points(node, points)
	if points.is_empty():
		return AABB()
	var result := AABB(points[0], Vector3.ZERO)
	for point in points:
		result = result.expand(point)
	return result


func _collect_skinned_character_points(node: Node, points: Array[Vector3]) -> void:
	if node is MeshInstance3D:
		var mesh := node as MeshInstance3D
		var is_character_mesh := (
			String(mesh.name).begins_with("BaseBody")
			or String(mesh.name).begins_with("Headgear")
			or String(mesh.name).begins_with("RearArmorAndWebbing")
			or String(mesh.name).begins_with("BeltKitAndHipPouch")
		)
		var skeleton := mesh.get_node_or_null(mesh.skeleton) as Skeleton3D
		if is_character_mesh and mesh.skin != null and skeleton != null:
			for surface in mesh.mesh.get_surface_count():
				var arrays := mesh.mesh.surface_get_arrays(surface)
				var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
				var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
				var stride: int = weights.size() / vertices.size()
				for vertex in vertices.size():
					var point := Vector3.ZERO
					for slot in stride:
						var offset := vertex * stride + slot
						if weights[offset] <= 0.000001:
							continue
						var bind := bones[offset]
						var bone := skeleton.find_bone(mesh.skin.get_bind_name(bind))
						if bone < 0:
							bone = mesh.skin.get_bind_bone(bind)
						point += (
							skeleton.global_transform
							* skeleton.get_bone_global_pose(bone)
							* mesh.skin.get_bind_pose(bind)
							* vertices[vertex]
						) * weights[offset]
					points.append(point)
	for child in node.get_children():
		_collect_skinned_character_points(child, points)


func _expect(condition: bool, message: String) -> void:
	if condition:
		print("SOCOM2_TAN_VISUAL PASS ", message)
	else:
		failures.append(message)
		push_error("SOCOM2_TAN_VISUAL FAIL " + message)


func _finish() -> void:
	print("SOCOM2_TAN_OPERATOR_VISUAL_CHECK %s" % ("PASS" if failures.is_empty() else "FAIL"))
	quit(0 if failures.is_empty() else 1)
