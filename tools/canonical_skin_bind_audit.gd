extends SceneTree

const RIG_PATH := "res://assets/characters/ps1_gas_mask_soldier/trooper_rigged.fbx"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1280, 900)
	var packed := load(RIG_PATH) as PackedScene
	if packed == null:
		push_error("CANONICAL_SKIN_BIND_AUDIT rig does not load")
		quit(1)
		return
	var rig := packed.instantiate() as Node3D
	rig.scale = Vector3.ONE * 62.0
	rig.rotation.y = PI
	root.add_child(rig)
	_setup_world()
	await process_frame
	_print_tree(rig, "")
	var skeleton := _find_skeleton(rig)
	if skeleton == null:
		push_error("CANONICAL_SKIN_BIND_AUDIT skeleton missing")
		quit(1)
		return
	print("CANONICAL_SKIN skeleton=%s bones=%d transform=%s" % [
		skeleton.get_path(), skeleton.get_bone_count(), skeleton.transform,
	])
	for mesh in _find_meshes(rig):
		print("CANONICAL_SKIN mesh=%s skeleton_path=%s transform=%s aabb=%s skin=%s" % [
			mesh.get_path(), mesh.skeleton, mesh.transform,
			mesh.get_aabb(), "yes" if mesh.skin != null else "no",
		])
		if mesh.skin == null:
			continue
		print("CANONICAL_SKIN binds=%d" % mesh.skin.get_bind_count())
		for bind_index in mini(mesh.skin.get_bind_count(), 12):
			var bind_name := String(mesh.skin.get_bind_name(bind_index))
			var bone_index := skeleton.find_bone(bind_name)
			var rest_global := (
				skeleton.get_bone_global_rest(bone_index)
				if bone_index >= 0 else Transform3D.IDENTITY
			)
			print("CANONICAL_SKIN bind=%d name=%s bone=%d pose=%s rest=%s combined=%s" % [
				bind_index, bind_name, bone_index, mesh.skin.get_bind_pose(bind_index),
				rest_global, rest_global * mesh.skin.get_bind_pose(bind_index),
			])
	for _frame in range(4):
		await process_frame
	RenderingServer.force_draw()
	await process_frame
	var image := root.get_texture().get_image()
	var capture_path := "/private/tmp/socom-canonical-direct-rest.png"
	if image == null or image.is_empty() or image.save_png(capture_path) != OK:
		push_error("CANONICAL_SKIN_BIND_AUDIT capture failed")
		quit(1)
		return
	print("CANONICAL_SKIN_BIND_AUDIT_CAPTURE %s" % capture_path)
	quit(0)


func _setup_world() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("6f8290")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color.WHITE
	environment.ambient_light_energy = 0.75
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	root.add_child(world_environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-40.0, -30.0, 0.0)
	light.light_energy = 1.2
	root.add_child(light)
	var camera := Camera3D.new()
	camera.position = Vector3(2.3, 1.45, -4.2)
	camera.fov = 36.0
	root.add_child(camera)
	camera.look_at(Vector3(0.0, 1.05, 0.0), Vector3.UP)
	camera.current = true


func _print_tree(node: Node, indent: String) -> void:
	print("CANONICAL_SKIN_TREE %s%s <%s>" % [indent, node.name, node.get_class()])
	for child in node.get_children():
		_print_tree(child, indent + "  ")


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for child in node.get_children():
		var found := _find_skeleton(child)
		if found != null:
			return found
	return null


func _find_meshes(node: Node) -> Array[MeshInstance3D]:
	var found: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		found.append(node as MeshInstance3D)
	for child in node.get_children():
		found.append_array(_find_meshes(child))
	return found
