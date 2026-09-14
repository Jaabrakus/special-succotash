extends "res://tools/rifle_reference_visual_probe.gd"
## Read-only renderer of saved arsenal assets and representative canonical holds.
const Catalog := preload("res://scripts/weapons/socom_weapon_catalog.gd")
const Contract := preload("res://scripts/weapons/weapon_rig_contract.gd")

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		failures.append("Native display required for visual proof")
		_finish()
		return
	output_prefix = "/private/tmp/source-arsenal-visual"
	capture = true
	root.set_disable_input(true)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	root.size = Vector2i(1600, 1800)
	await _sheet()
	root.size = Vector2i(1280, 800)
	ProjectSettings.set_setting("socom/session/public_training", true)
	scene = (load("res://main.tscn") as PackedScene).instantiate() as Node3D
	scene.get_node("IndependentCameraRig").capture_mouse_on_ready = false
	root.add_child(scene)
	current_scene = scene
	player = scene.get_node("Player")
	player.set_local_input_enabled(false)
	await _frames(45)
	controller = scene.get_node("WeaponController")
	controller.set_input_enabled(false)
	driver = player.get_node("Mannequin/ProductionAnimation")
	_install_fixture()
	for id in ["s2_m4a1", "s2_mark_23", "s2_hk5", "s2_870", "s2_m40a1", "s2_f2000", "s2_m60e3"]:
		weapon_id = id
		if not controller.apply_authorized_weapon_pickup("res://config/weapons/" + id + ".json"):
			failures.append("Equip refused " + id)
			continue
		for stance in [0, 1]:
			player.call("_try_set_posture", stance)
			await _frames(90)
			await _sample(id + "_" + str(stance) + "_idle")
			if _request_shot():
				await _frames(12)
				await _sample(id + "_" + str(stance) + "_fire")
	print("SOURCE_ARSENAL_VISUAL_PROOF ", "PASS" if failures.is_empty() else "FAIL", " captures=", samples.size() * 2)
	_finish()

func _sheet() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.08, 0.10, 0.12)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color.WHITE
	env.environment.ambient_light_energy = 0.9
	stage.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-30, -25, 0)
	sun.light_energy = 1.2
	stage.add_child(sun)
	var ids := Catalog.source_arsenal_ids()
	for index in ids.size():
		var config := Contract.load_config("res://config/weapons/" + ids[index] + ".json")
		var node := (load(config.model_fbx) as PackedScene).instantiate() as Node3D
		node.rotation_degrees.y = 85
		node.position = Vector3((index % 4) * 2.05 - 3.4, 5.1 - (index / 4) * 1.0, 0)
		stage.add_child(node)
		var label := Label3D.new()
		label.text = String(config.display_name).trim_prefix("SOCOM II · ")
		label.font_size = 32
		label.pixel_size = 0.004
		label.no_depth_test = true
		label.position = node.position + Vector3(0.20, -0.30, 0.25)
		stage.add_child(label)
	var view := Camera3D.new()
	view.projection = Camera3D.PROJECTION_ORTHOGONAL
	view.size = 11.7
	view.position = Vector3(0, 0, 15)
	stage.add_child(view)
	view.make_current()
	await _frames(6)
	await RenderingServer.frame_post_draw
	var error := root.get_texture().get_image().save_png(output_prefix + "-sheet.png")
	if error != OK: failures.append("Contact sheet could not be saved")
	stage.queue_free()
	await process_frame
