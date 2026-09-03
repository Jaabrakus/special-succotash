extends SceneTree

const CAPTURE_PATH := "/private/tmp/socom-agls-live-skeleton.png"


func _initialize() -> void:
	_capture.call_deferred()


func _capture() -> void:
	root.size = Vector2i(1280, 800)
	var packed := load("res://main.tscn") as PackedScene
	if packed == null:
		push_error("AGLS skeleton visual check could not load main.tscn")
		quit(1)
		return
	var scene := packed.instantiate() as Node3D
	root.add_child(scene)
	await _frames(60)
	var player := scene.get_node_or_null("Player") as CharacterBody3D
	if player == null:
		push_error("AGLS skeleton visual check could not find Player")
		quit(1)
		return
	_hide_canvas(scene)
	var camera := Camera3D.new()
	camera.name = "AglsSkeletonReviewCamera"
	scene.add_child(camera)
	camera.global_position = player.global_position + Vector3(3.4, 2.15, 4.6)
	camera.look_at(player.global_position + Vector3(0.0, 1.0, 0.0), Vector3.UP)
	camera.fov = 42.0
	camera.current = true
	await _frames(12)
	var image := root.get_texture().get_image()
	if image == null or image.is_empty() or image.save_png(CAPTURE_PATH) != OK:
		push_error("AGLS skeleton visual capture failed")
		quit(1)
		return
	print("AGLS_LIVE_SKELETON_VISUAL_CHECK PASS %s" % CAPTURE_PATH)
	quit(0)


func _hide_canvas(node: Node) -> void:
	if node is CanvasItem:
		(node as CanvasItem).visible = false
	for child in node.get_children():
		_hide_canvas(child)


func _frames(count: int) -> void:
	for _frame in count:
		await process_frame
