extends SceneTree
const Maps := preload("res://scripts/maps/socom_map_document.gd")
var source_variant := false

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	source_variant = "--source-assets" in OS.get_cmdline_user_args()
	var document := Maps.load_path("user://maps/desert_glory_source_enhanced.json" if source_variant else "user://maps/desert_glory_rebuild.json")
	assert(not document.is_empty(), "Build local map first")
	ProjectSettings.set_setting("socom/session/selected_map_document", document)
	ProjectSettings.set_setting("socom/playtest/use_active_bundle", false)
	ProjectSettings.set_setting("socom/session/public_training", true)
	root.set_disable_input(true)
	change_scene_to_file("res://main.tscn")
	await scene_changed
	assert(current_scene.active_map_document.map_id == ("desert_glory_source_enhanced" if source_variant else "desert_glory_local"))
	var actor := current_scene.get_node("Player") as CharacterBody3D
	actor.set_physics_process(false)
	actor.velocity = Vector3.ZERO
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	root.size = Vector2i(1280,720)
	for frame in 90: await process_frame
	assert(current_scene.find_children("MapFilmGrain", "CanvasLayer", true, false).size() == 1, "One grain owner in canonical game")
	var grain: CanvasLayer = current_scene.find_children("MapFilmGrain", "CanvasLayer", true, false)[0]
	assert(grain.layer == -1)
	assert(is_equal_approx(grain.get_node("GrainOverlay").material.get_shader_parameter("strength"),document.environment.film_grain_strength))
	await _capture("player")
	var inspection := Camera3D.new()
	current_scene.add_child(inspection)
	inspection.fov = 65.0
	inspection.position = Vector3(146,82,248)
	inspection.look_at(Vector3(148,2,168))
	inspection.make_current()
	for frame in 30: await process_frame
	await _capture("overview")
	inspection.position = Vector3(151,5,191)
	inspection.look_at(Vector3(170,5,166))
	for frame in 30: await process_frame
	await _capture("street")
	print("DESERT_GLORY_VISUAL PASS: canonical main, local map, one below-HUD grain layer; primitives=",Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)," draws=",Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	quit()

func _capture(label: String) -> void:
	await RenderingServer.frame_post_draw
	assert(root.get_texture().get_image().save_png(("/private/tmp/desert-glory-source-" if source_variant else "/private/tmp/desert-glory-") + label + ".png") == OK)
