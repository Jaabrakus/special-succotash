extends SceneTree

const LAB_SCENE := preload("res://gun_calibration_lab_2.tscn")
const CAPTURE_PATH := "/private/tmp/socom-guns-lab-2.png"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1440, 900)
	var lab := LAB_SCENE.instantiate() as GunsLab2
	root.add_child(lab)
	for _frame in range(24):
		await process_frame
	if DisplayServer.get_name() == "headless":
		push_error("GUNS_LAB_2_VISUAL_CHECK requires a display-backed run")
		quit(1)
		return
	RenderingServer.force_draw()
	await process_frame
	var image := root.get_texture().get_image()
	if image == null or image.is_empty():
		push_error("GUNS_LAB_2_VISUAL_CHECK could not read the rendered frame")
		quit(1)
		return
	var error := image.save_png(CAPTURE_PATH)
	if error != OK:
		push_error("GUNS_LAB_2_VISUAL_CHECK could not save %s: %s" % [CAPTURE_PATH, error])
		quit(1)
		return
	print("GUNS_LAB_2_VISUAL_CHECK PASS %s" % CAPTURE_PATH)
	quit(0)
