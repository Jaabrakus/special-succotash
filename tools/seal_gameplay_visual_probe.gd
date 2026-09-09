extends SceneTree

## Asset-only diagnostic before activation. No saved gameplay data is changed.
const TARGET := "res://assets/characters/ps1_dual_source_rig/ps1_dual_source_rig.scn"
const RETARGET = preload("res://scripts/labs/animation_retarget_service.gd")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("SEAL_VISUAL requires a render-backed process")
		quit(1)
		return
	root.size = Vector2i(800, 800)
	var world := Node3D.new()
	root.add_child(world)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.15, 0.17, 0.2)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.7
	world.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-40, -30, 0)
	light.light_energy = 1.5
	world.add_child(light)
	var model := (load(TARGET) as PackedScene).instantiate() as Node3D
	model.scale = Vector3.ONE * 62.0
	model.rotation.y = PI
	world.add_child(model)
	var skeleton: Skeleton3D = RETARGET.new()._find_skeleton(model)
	var player := AnimationPlayer.new()
	skeleton.add_child(player)
	player.root_node = NodePath("..")
	var library := AnimationLibrary.new()
	player.add_animation_library("seal", library)
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.position = Vector3(2.8, 1.8, 3.6)
	camera.look_at(Vector3(0, 0.9, 0))
	camera.fov = 36.0
	camera.current = true
	var label := Label.new()
	label.position = Vector2(20, 20)
	label.add_theme_font_size_override("font_size", 24)
	root.add_child(label)
	for clip_name: String in ["seal_stand", "seal_p_stand", "seal_crouch", "seal_prone", "seal_run", "seal_tossgrenade", "seal_stand2llean"]:
		var clip := load("res://assets/animations/seal_reference/" + clip_name + ".tres") as Animation
		library.add_animation(clip_name, clip)
		player.play("seal/" + clip_name)
		player.seek(clip.length * 0.5, true)
		player.pause()
		label.text = clip_name + " | source-only retarget, no weapon/IK"
		for frame in 3:
			await process_frame
		await RenderingServer.frame_post_draw
		var image := root.get_texture().get_image()
		var path := "/private/tmp/seal-visual-" + clip_name + ".png"
		if image == null or image.is_empty() or image.save_png(path) != OK:
			push_error("SEAL_VISUAL capture failed: " + clip_name)
			quit(1)
			return
		print("SEAL_VISUAL ", path)
	world.free()
	quit()
