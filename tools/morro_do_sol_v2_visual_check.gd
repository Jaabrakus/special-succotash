extends SceneTree

const MAP_PATH := "res://config/maps/morro_do_sol_v2_2v2.json"
const OVERVIEW_PATH := "/private/tmp/morro_do_sol_v2_overview.png"
const APPROACH_PATH := "/private/tmp/morro_do_sol_v2_alpha_approach.png"
const SKYLINE_PATH := "/private/tmp/morro_do_sol_v2_skyline.png"
const COAST_PATH := "/private/tmp/morro_do_sol_v2_coast.png"
const ALPHA_ROUTE_PATH := "/private/tmp/morro_do_sol_v2_alpha_roof_route.png"
const BRAVO_ROUTE_PATH := "/private/tmp/morro_do_sol_v2_bravo_roof_route.png"
const WORKSHOP_WINDOW_PATH := "/private/tmp/morro_do_sol_v2_workshop_window.png"
const MapDocument := preload("res://scripts/maps/socom_map_document.gd")
const MapRuntime := preload("res://scripts/maps/socom_map_runtime.gd")
const MapAmbience := preload("res://scripts/maps/socom_map_ambience_engine.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var document := MapDocument.load_path(MAP_PATH)
	if document.is_empty():
		push_error("Could not load %s" % MAP_PATH)
		quit(1)
		return
	var stage := Node3D.new()
	stage.name = "MorroDoSolV2VisualProof"
	root.add_child(stage)
	MapAmbience.build_into(stage, document)
	MapRuntime.build_into(stage, document, true)
	var camera := Camera3D.new()
	camera.name = "ProofCamera"
	camera.fov = 58.0
	camera.near = 0.1
	camera.far = 220.0
	camera.current = true
	stage.add_child(camera)

	camera.position = Vector3(0.0, 42.0, 45.0)
	camera.look_at_from_position(camera.position, Vector3(0.0, 1.8, -1.0), Vector3.UP)
	var capture_ok := await _settle_and_capture(OVERVIEW_PATH)

	camera.position = Vector3(0.0, 3.2, 15.8)
	camera.look_at_from_position(camera.position, Vector3(0.0, 3.8, -7.0), Vector3.UP)
	capture_ok = await _settle_and_capture(APPROACH_PATH) and capture_ok

	camera.position = Vector3(-8.5, 3.7, 8.5)
	camera.look_at_from_position(camera.position, Vector3(0.0, 5.7, -11.5), Vector3.UP)
	capture_ok = await _settle_and_capture(SKYLINE_PATH) and capture_ok

	camera.position = Vector3(-7.0, 4.0, 5.5)
	camera.look_at_from_position(camera.position, Vector3(-8.6, 5.1, -4.0), Vector3.UP)
	capture_ok = await _settle_and_capture(ALPHA_ROUTE_PATH) and capture_ok

	camera.position = Vector3(7.0, 4.0, 5.5)
	camera.look_at_from_position(camera.position, Vector3(8.6, 5.0, -4.0), Vector3.UP)
	capture_ok = await _settle_and_capture(BRAVO_ROUTE_PATH) and capture_ok

	camera.position = Vector3(14.0, 5.0, -14.0)
	camera.look_at_from_position(camera.position, Vector3(14.0, 4.2, -8.5), Vector3.UP)
	capture_ok = await _settle_and_capture(WORKSHOP_WINDOW_PATH) and capture_ok

	camera.position = Vector3(0.0, 6.2, 12.0)
	camera.look_at_from_position(camera.position, Vector3(0.0, 8.0, 98.0), Vector3.UP)
	capture_ok = await _settle_and_capture(COAST_PATH) and capture_ok
	print("MORRO_DO_SOL_V2_VISUAL_CHECK overview=%s approach=%s skyline=%s alpha_route=%s bravo_route=%s workshop_window=%s coast=%s" % [OVERVIEW_PATH, APPROACH_PATH, SKYLINE_PATH, ALPHA_ROUTE_PATH, BRAVO_ROUTE_PATH, WORKSHOP_WINDOW_PATH, COAST_PATH])
	quit(0 if capture_ok else 1)


func _settle_and_capture(path: String) -> bool:
	for _frame in 14:
		await process_frame
	var viewport_texture := root.get_texture()
	if viewport_texture == null:
		push_error("No viewport texture available for %s" % path)
		return false
	var image := viewport_texture.get_image()
	# Label3D may allocate its font atlas during the first real renderer frame.
	# Retry a genuinely black warm-up capture instead of saving false evidence.
	if image != null and not image.is_empty() and _average_luminance(image) <= 0.01:
		for _frame in 36:
			await process_frame
		image = viewport_texture.get_image()
	if image == null or image.is_empty():
		push_error("No rendered image available for %s" % path)
		return false
	if _average_luminance(image) <= 0.01:
		push_error("Renderer returned a black proof image for %s" % path)
		return false
	var error := image.save_png(path)
	if error != OK:
		push_error("Could not save %s: %s" % [path, error_string(error)])
		return false
	return true


func _average_luminance(image: Image) -> float:
	var size := image.get_size()
	if size.x <= 0 or size.y <= 0:
		return 0.0
	var luminance := 0.0
	var sample_count := 0
	for y_index in 5:
		for x_index in 9:
			var x := clampi(int((float(x_index) + 0.5) / 9.0 * float(size.x)), 0, size.x - 1)
			var y := clampi(int((float(y_index) + 0.5) / 5.0 * float(size.y)), 0, size.y - 1)
			luminance += image.get_pixel(x, y).get_luminance()
			sample_count += 1
	return luminance / float(maxi(sample_count, 1))
