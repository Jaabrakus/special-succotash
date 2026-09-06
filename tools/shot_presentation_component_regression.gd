extends SceneTree

const Presentation := preload("res://scripts/network/socom_shot_presentation.gd")
const Tracers := preload("res://scripts/weapons/lab_leak_tracer_system.gd")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(640, 360)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var camera := Camera3D.new()
	viewport.add_child(camera)
	camera.position = Vector3(0, 1, 6)
	camera.look_at(Vector3.ZERO)
	var presentation := Presentation.new()
	viewport.add_child(presentation)
	await process_frame
	# Persist only in this test; first-frame shader compilation can outlast a flash.
	Tracers.set_trajectory_debug_enabled(true)
	presentation.present_shot(Vector3(-2, 0, 0), Vector3(2, 0, 0), false, "MISS",
		{"ballistics": {"muzzle_velocity_mps": 1.0}}, [])
	for frame in 3:
		await process_frame
		await RenderingServer.frame_post_draw
	var picture := viewport.get_texture().get_image()
	var yellow_pixels := 0
	for y in picture.get_height():
		for x in picture.get_width():
			var pixel := picture.get_pixel(x, y)
			if pixel.r > 0.5 and pixel.g > 0.4 and pixel.b < pixel.g * 0.7:
				yellow_pixels += 1
	var error := picture.save_png("/private/tmp/socom-shot-component.png")
	Tracers.set_trajectory_debug_enabled(false)
	var passed := yellow_pixels > 0 and error == OK
	print("SHOT_PRESENTATION_COMPONENT_REGRESSION ", "PASS" if passed else "FAIL", " tracer_pixels=", yellow_pixels)
	quit(0 if passed else 1)
