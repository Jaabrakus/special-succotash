extends SceneTree

const Operator := preload("res://scripts/network/socom_network_operator.gd")
const Appearance := preload("res://scripts/player/operator_team_appearance.gd")
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	current_scene = world
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.position = Vector3(0, 1.5, 4.6)
	camera.look_at(Vector3(0, 1.0, 0))
	var light := DirectionalLight3D.new()
	world.add_child(light)
	light.rotation_degrees = Vector3(-40, -20, 0)
	light.light_energy = 1.8
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.13, 0.15, 0.17)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color.WHITE
	env.environment.ambient_light_energy = 0.8
	world.add_child(env)
	var operators: Array[Node] = []
	for team in 2:
		var operator := Operator.new()
		world.add_child(operator)
		operator.position = Vector3(-0.85 if team == 0 else 0.85, 0, 0)
		operator.rotation.y = PI
		operator.set_physics_process(false)
		operator.configure_identity(team + 1, team)
		operator.set_local_input_enabled(false)
		operators.append(operator)
	for frame in 40:
		await process_frame
	for team in 2:
		var operator = operators[team]
		var driver = operator.mannequin.production_animation
		_expect(driver.skeleton.get_bone_count() == 65, "runtime skeleton unchanged")
		var model: Node = driver.get_node("TrooperModel")
		var colored := 0
		for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
			if mesh.mesh == null:
				continue
			for surface in mesh.mesh.get_surface_count():
				var material := mesh.get_surface_override_material(surface) as ShaderMaterial
				if material != null and material.shader == Appearance.CLOTH:
					colored += 1
					_expect(material.get_shader_parameter("team_color") == Appearance.color_for(team), "team cloth color")
		_expect(colored > 0, "body receives team appearance")
		_expect(model.scene_file_path == Appearance.profile().model, "original model selected")
	if OS.get_cmdline_user_args().has("--render"):
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/private/tmp/blue-green-operators.png")
	world.queue_free()
	await process_frame
	print("BLUE_GREEN_OPERATOR_REGRESSION ", "PASS" if failures == 0 else "FAIL")
	quit(0 if failures == 0 else 1)

func _expect(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		push_error("BLUE_GREEN_OPERATOR FAIL " + label)
