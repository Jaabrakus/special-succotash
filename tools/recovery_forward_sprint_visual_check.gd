extends SceneTree

const SIDE_CAPTURE := "/private/tmp/socom-recovery-forward-sprint-side.png"
const REAR_CAPTURE := "/private/tmp/socom-recovery-forward-sprint-rear.png"

var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1440, 900)
	var packed := load("res://main.tscn") as PackedScene
	_expect(packed != null, "canonical main scene loads")
	if packed == null:
		_finish()
		return
	var scene := packed.instantiate() as Node3D
	root.add_child(scene)
	await _process_steps(60)
	var player := scene.get_node_or_null("Player") as CharacterBody3D
	var mannequin := player.get_node_or_null("Mannequin") if player != null else null
	var driver := mannequin.get_node_or_null("ProductionAnimation") if mannequin != null else null
	_expect(player != null and driver != null, "canonical player animation driver exists")
	if player == null or driver == null:
		_finish()
		return
	if driver.has_method("clear_fire_ready_aim"):
		driver.call("clear_fire_ready_aim")
	Input.action_press(&"move_forward")
	for _frame in range(42):
		await physics_frame
	Input.action_release(&"move_forward")
	_hide_canvas_layers(scene)
	var boom_visualizer := scene.find_child("CameraBoomVisualizer", true, false) as Node3D
	if boom_visualizer != null:
		boom_visualizer.visible = false
	if mannequin.has_method("set_proxy_visuals_visible"):
		mannequin.call("set_proxy_visuals_visible", false)
	var existing_camera := root.get_viewport().get_camera_3d()
	if existing_camera != null:
		existing_camera.current = false
	var review_camera := Camera3D.new()
	review_camera.name = "RecoverySprintReviewCamera"
	review_camera.fov = 38.0
	review_camera.current = true
	review_camera.set_cull_mask_value(20, false)
	scene.add_child(review_camera)
	var target := player.global_position + Vector3.UP * 1.05
	review_camera.global_position = player.global_position + Vector3(3.15, 1.42, 0.05)
	review_camera.look_at(target, Vector3.UP)
	await _process_steps(4)
	_expect(await _capture(SIDE_CAPTURE), "side sprint capture saves")
	review_camera.global_position = player.global_position + Vector3(1.65, 1.48, 2.75)
	review_camera.look_at(target, Vector3.UP)
	await _process_steps(4)
	_expect(await _capture(REAR_CAPTURE), "rear sprint capture saves")
	var debug: Dictionary = driver.call("get_animation_debug_state")
	print("RECOVERY_FORWARD_SPRINT_STATE %s" % JSON.stringify({
		"clip": debug.get("current_clip", &""),
		"locomotion": debug.get("locomotion", {}),
		"weapon_pose": debug.get("weapon_pose", {}),
	}))
	_finish()


func _hide_canvas_layers(node: Node) -> void:
	if node is CanvasLayer:
		(node as CanvasLayer).visible = false
	for child in node.get_children():
		_hide_canvas_layers(child)


func _capture(path: String) -> bool:
	RenderingServer.force_draw()
	await process_frame
	var image := root.get_texture().get_image()
	return image != null and not image.is_empty() and image.save_png(path) == OK


func _process_steps(count: int) -> void:
	for _frame in range(count):
		await process_frame


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("RECOVERY_FORWARD_SPRINT_CHECK PASS %s" % label)
		return
	failures.append(label)
	push_error("RECOVERY_FORWARD_SPRINT_CHECK FAIL %s" % label)


func _finish() -> void:
	if failures.is_empty():
		print("RECOVERY_FORWARD_SPRINT_CHECK PASS")
		quit(0)
	else:
		print("RECOVERY_FORWARD_SPRINT_CHECK FAIL %s" % [failures])
		quit(1)
