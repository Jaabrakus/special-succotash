extends "res://tools/canonical_skin_bind_audit.gd"

## Render the exported asset only. Never changes the canonical player's skin.
func _run() -> void:
	root.size = Vector2i(1100, 1200)
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	var path := "res://assets/characters/ps1_skin_template/ps1_skin_template_example.glb"
	if document.append_from_file(ProjectSettings.globalize_path(path), state) != OK:
		push_error("PS1_SKIN_TEMPLATE_VISUAL sample does not load")
		quit(1)
		return
	var model := document.generate_scene(state) as Node3D
	model.scale = Vector3.ONE * 62.0
	model.rotation.y = PI
	root.add_child(model)
	_setup_world()
	for _frame in range(6):
		await process_frame
	RenderingServer.force_draw()
	await RenderingServer.frame_post_draw
	var capture := root.get_texture().get_image()
	var destination := "res://art_source/ps1_skin_template/godot_import_preview.png"
	if capture == null or capture.is_empty() or capture.save_png(ProjectSettings.globalize_path(destination)) != OK:
		push_error("PS1_SKIN_TEMPLATE_VISUAL capture failed")
		quit(1)
		return
	print("PS1_SKIN_TEMPLATE_VISUAL_CAPTURE_PASS ", destination)
	quit(0)
