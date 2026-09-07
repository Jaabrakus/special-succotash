extends SceneTree
## Render imported staging scenes only, never the canonical gameplay scene.
const BASE := "res://art_source/sketchfab_intake_20260906/"
const TILE := Vector2i(640, 460)
var views: Array[SubViewport] = []
var entries: Array[Dictionary] = []

func _initialize() -> void:
	call_deferred("_run")

func _bounds(node: Node, prior: Transform3D, boxes: Array[AABB]) -> void:
	var current: Transform3D = prior
	if node is Node3D:
		current = prior * (node as Node3D).transform
	if node is MeshInstance3D:
		var instance := node as MeshInstance3D
		var box: AABB = instance.get_aabb()
		if instance.skin != null:
			var posed: ArrayMesh = instance.bake_mesh_from_current_skeleton_pose()
			if posed != null:
				box = posed.get_aabb()
		boxes.append(current * box)
	for child in node.get_children():
		_bounds(child, current, boxes)

func _run() -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(BASE + "inventory.json"))
	for record: Dictionary in manifest.assets:
		if record.status == "held":
			continue
		entries.append(record)
		var viewport := SubViewport.new()
		viewport.size = TILE
		viewport.own_world_3d = true
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(viewport)
		views.append(viewport)
		var world := Node3D.new()
		viewport.add_child(world)
		var packed := load("res://" + str(record.gltf).get_base_dir() + "/imported.scn") as PackedScene
		var asset: Node = packed.instantiate()
		world.add_child(asset)
		await process_frame
		await process_frame
		var boxes: Array[AABB] = []
		_bounds(asset, Transform3D.IDENTITY, boxes)
		var bounds: AABB = boxes[0]
		for box: AABB in boxes:
			bounds = bounds.merge(box)
		var center: Vector3 = bounds.get_center()
		var span: float = maxf(bounds.size.length(), 0.1)
		var camera := Camera3D.new()
		world.add_child(camera)
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera.size = span * 1.03
		camera.near = span * 0.001
		camera.far = span * 10.0
		camera.position = center + Vector3(1.0, 0.65, 1.3).normalized() * span * 2.0
		camera.look_at(center)
		camera.current = true
		var environment := WorldEnvironment.new()
		environment.environment = Environment.new()
		environment.environment.background_mode = Environment.BG_COLOR
		environment.environment.background_color = Color("26313b")
		environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		environment.environment.ambient_light_color = Color.WHITE
		environment.environment.ambient_light_energy = 0.8
		world.add_child(environment)
		var light := DirectionalLight3D.new()
		light.rotation_degrees = Vector3(-45, -25, 0)
		light.light_energy = 1.2
		world.add_child(light)
		var label := Label.new()
		label.text = str(record.id).replace("_", " ")
		label.position = Vector2(14, 12)
		label.add_theme_font_size_override("font_size", 17)
		viewport.add_child(label)
	for frame in 12:
		await process_frame
	await RenderingServer.frame_post_draw
	var sheet := Image.create(TILE.x * 2, TILE.y * 3, false, Image.FORMAT_RGBA8)
	for index in views.size():
		var pixels: Image = views[index].get_texture().get_image()
		if pixels == null or pixels.is_empty():
			push_error("No rendered pixels for " + str(entries[index].id))
			quit(1)
			return
		pixels.convert(Image.FORMAT_RGBA8)
		var destination: String = "res://" + str(entries[index].gltf).get_base_dir() + "/preview.png"
		var err: Error = pixels.save_png(destination)
		if err != OK:
			push_error("Cannot save preview: " + destination)
			quit(1)
			return
		sheet.blit_rect(pixels, Rect2i(Vector2i.ZERO, TILE), Vector2i((index % 2) * TILE.x, (index / 2) * TILE.y))
	var result: Error = sheet.save_png(BASE + "prepared/contact_sheet.png")
	print("Six Godot scene previews saved, result=", result)
	quit(0 if result == OK else 1)
