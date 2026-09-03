extends SceneTree

const MAP_PATH := "res://config/maps/painterly_coastal_village_2v2.json"
const OVERVIEW_PATH := "/private/tmp/morro_do_sol_overview.png"
const ATTACK_PATH := "/private/tmp/morro_do_sol_attack_route.png"
const COAST_PATH := "/private/tmp/morro_do_sol_distant_coast.png"
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
	stage.name = "MorroDoSolVisualProof"
	root.add_child(stage)
	MapAmbience.build_into(stage, document)
	MapRuntime.build_into(stage, document, true)
	var camera := Camera3D.new()
	camera.name = "ProofCamera"
	camera.fov = 56.0
	camera.near = 0.1
	camera.far = 180.0
	camera.current = true
	stage.add_child(camera)

	camera.position = Vector3(31.0, 28.0, 33.0)
	camera.look_at_from_position(camera.position, Vector3(0.0, 1.3, 0.0), Vector3.UP)
	var capture_ok := await _settle_and_capture(OVERVIEW_PATH)

	camera.position = Vector3(0.0, 3.4, 16.2)
	camera.look_at_from_position(camera.position, Vector3(0.0, 1.6, -3.0), Vector3.UP)
	capture_ok = await _settle_and_capture(ATTACK_PATH) and capture_ok

	camera.position = Vector3(0.0, 6.2, 11.5)
	camera.look_at_from_position(camera.position, Vector3(0.0, 5.0, 95.0), Vector3.UP)
	capture_ok = await _settle_and_capture(COAST_PATH) and capture_ok
	print("PAINTERLY_VILLAGE_VISUAL_CHECK overview=%s attack=%s coast=%s" % [OVERVIEW_PATH, ATTACK_PATH, COAST_PATH])
	quit(0 if capture_ok else 1)


func _settle_and_capture(path: String) -> bool:
	for _frame in 12:
		await process_frame
	var viewport_texture := root.get_texture()
	if viewport_texture == null:
		push_error("No viewport texture available for %s" % path)
		return false
	var image := viewport_texture.get_image()
	if image == null or image.is_empty():
		push_error("No rendered image available for %s" % path)
		return false
	var error := image.save_png(path)
	if error != OK:
		push_error("Could not save %s: %s" % [path, error_string(error)])
		return false
	return true
