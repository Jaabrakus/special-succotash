extends SceneTree

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	var label := "after" if "--after" in OS.get_cmdline_user_args() else "before"
	var document_path := "res://config/maps/current_map.json" if label == "after" else "/private/tmp/relic-yard-map-before.json"
	var document: Dictionary = load("res://scripts/maps/socom_map_document.gd").load_path(document_path)
	assert(not document.is_empty())
	if "--live" not in OS.get_cmdline_user_args():
		ProjectSettings.set_setting("socom/session/selected_map_document", document)
	root.set_disable_input(true)
	ProjectSettings.set_setting("socom/session/public_training", true)
	ProjectSettings.set_setting("socom/playtest/use_active_bundle", false)
	change_scene_to_file("res://main.tscn")
	await scene_changed
	# Freeze only this test actor so typing in the desktop app cannot poll as
	# WASD during the before/after capture. Runtime scripts remain unchanged.
	var actor := current_scene.get_node("Player") as CharacterBody3D
	actor.set_physics_process(false)
	actor.position = Vector3(0, 0.1, 25)
	actor.velocity = Vector3.ZERO
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	root.size = Vector2i(1280, 720)
	for frame in 120:
		await process_frame
	var camera := root.get_camera_3d()
	print("RELIC_CAMERA ", camera.global_transform)
	if label == "after":
		var found_finish := false
		for object: Dictionary in current_scene.active_map_document.objects:
			if object.id == "relic_001":
				found_finish = bool(object.properties.get("yard_weathering", false))
		assert(found_finish, "canonical main must load the saved finish, not a stale selection")
	await _capture(label + "-player")
	# Inspection-only camera in the real main scene, never saved to gameplay.
	var inspection := Camera3D.new()
	current_scene.add_child(inspection)
	inspection.fov = 65.0
	inspection.position = Vector3(15, 8, 26)
	inspection.look_at(Vector3(-2, 0.5, 13))
	inspection.make_current()
	for frame in 45:
		await process_frame
	await _capture(label + "-yard")
	var intervals: Array[float] = []
	var last := Time.get_ticks_usec()
	for frame in 180:
		await process_frame
		var now := Time.get_ticks_usec()
		intervals.append(float(now - last) / 1000.0)
		last = now
	intervals.sort()
	print("RELIC_FRAME_TIME %s median_ms=%.3f p95_ms=%.3f draw_calls=%d primitives=%d" % [label, intervals[90], intervals[171], Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)])
	# Inspect source material flags before choosing the smallest safe adjustment.
	for node: Node in current_scene.get_node("AuthoredMap").get_children():
		if String(node.get_meta("map_object_id", "")) not in ["relic_015", "relic_016", "relic_027"]:
			continue
		for mesh: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
			for surface in mesh.mesh.get_surface_count():
				var mat := mesh.get_active_material(surface) as BaseMaterial3D
				if mat:
					if label == "after":
						assert(mat.texture_filter == BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC)
					print("RELIC_MATERIAL ", node.get_meta("map_object_id"), " ", mat.resource_name, " shading=", mat.shading_mode, " filter=", mat.texture_filter, " roughness=", mat.roughness, " metallic=", mat.metallic)
	print("RELIC_YARD_VISUAL_CHECK PASS ", label)
	quit()

func _capture(label: String) -> void:
	await RenderingServer.frame_post_draw
	var result := root.get_texture().get_image().save_png("/private/tmp/relic-yard-" + label + ".png")
	assert(result == OK)
