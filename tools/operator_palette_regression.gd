extends SceneTree
const Operator := preload("res://scripts/network/socom_network_operator.gd")
const Appearance := preload("res://scripts/player/operator_team_appearance.gd")
const COLORS := ["black", "green", "blue", "white"]
var failures: Array[String] = []
var models: Array[Node] = []
func _initialize() -> void:
	call_deferred("_run")
func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	current_scene = world
	root.size = Vector2i(1280, 720)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("29323d")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color.WHITE
	env.environment.ambient_light_energy = .9
	world.add_child(env)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35, 30, 0)
	light.light_energy = 1.4
	world.add_child(light)
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.position = Vector3(0, 1.6, 6.5)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 4.5
	camera.look_at(Vector3(0, 1, 0))
	camera.current = true
	for index in COLORS.size():
		var color: String = COLORS[index]
		if not Appearance.profile().get("palette", {}).has(color):
			failures.append("palette entry missing: " + color)
		var actor := Operator.new()
		world.add_child(actor)
		actor.position = Vector3((index - 1.5) * 1.8, 0, 0)
		actor.rotation.y = PI
		actor.set_physics_process(false)
		actor.configure_identity(index + 1, index % 2)
		actor.set_local_input_enabled(false)
		var model: Node = actor.mannequin.production_animation.get_node("TrooperModel")
		models.append(model)
		Appearance.apply(model, 0, color)
		if model.scene_file_path != Appearance.profile().model:
			failures.append("original model not selected")
		if actor.mannequin.production_animation.skeleton.get_bone_count() != 65:
			failures.append("runtime bone count changed")
		if not model.find_children("RelicNVG_*", "MeshInstance3D", true, false).is_empty():
			failures.append("rejected model remains")
		var body := model.find_child("armlower", true, false) as MeshInstance3D
		if body == null or not body.visible:
			failures.append("original body hidden")
		else:
			var material := body.get_surface_override_material(0) as ShaderMaterial
			if material == null or material.get_shader_parameter("team_color") != Appearance.palette_color(color):
				failures.append("palette missing: " + color)
		var label := Label3D.new()
		label.text = color.to_upper()
		label.position = actor.position + Vector3(0, 2.4, 0)
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.font_size = 48
		world.add_child(label)
	for frame in 40:
		await process_frame
	# Network identity deliberately owns team colors after deferred setup. Apply
	# the four preview overrides only after initialization, then check final state.
	for index in models.size():
		var color: String = COLORS[index]
		Appearance.apply(models[index], 0, color)
		var body := models[index].find_child("armlower", true, false) as MeshInstance3D
		var material := body.get_surface_override_material(0) as ShaderMaterial
		if material.get_shader_parameter("team_color") != Appearance.palette_color(color):
			failures.append("final palette mismatch: " + color)
		if material.get_shader_parameter("cloth_brightness") != (4.0 if color == "white" else 1.0):
			failures.append("cloth brightness mismatch: " + color)
	# Team identity must reset the preview-only named color and brightness.
	for team in 2:
		Appearance.apply(models[3], team)
		var body := models[3].find_child("armlower", true, false) as MeshInstance3D
		var material := body.get_surface_override_material(0) as ShaderMaterial
		if material.get_shader_parameter("team_color") != Appearance.color_for(team) or material.get_shader_parameter("cloth_brightness") != 1.0:
			failures.append("team appearance did not reset white")
	Appearance.apply(models[3], 0, "white")
	await process_frame
	if OS.get_cmdline_user_args().has("--render"):
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://art_source/relic_depot_integration/original_character_palette.png")
	print("OPERATOR_PALETTE_REGRESSION ", "PASS" if failures.is_empty() else "FAIL", " ", failures)
	world.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
