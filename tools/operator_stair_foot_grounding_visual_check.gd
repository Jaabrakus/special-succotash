extends SceneTree

const STANDING_CAPTURE_PATH := "/private/tmp/socom-safe-stair-foot-grounding-standing.png"
const CROUCHED_CAPTURE_PATH := "/private/tmp/socom-safe-stair-foot-grounding-crouched.png"

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
	for _frame in range(30):
		await physics_frame
	var player := scene.get_node_or_null("Player") as CharacterBody3D
	var driver := (
		player.get_node_or_null("Mannequin/ProductionAnimation")
		if player != null else null
	)
	var foot_lock = driver.foot_contact_lock if driver != null else null
	_expect(player != null and driver != null and foot_lock != null, "live grounding owner exists")
	if player == null or driver == null or foot_lock == null:
		_finish()
		return
	# The proof drives the production animation owner directly. Stop the
	# mannequin input bridge from replacing the requested posture next frame.
	var mannequin := player.get_node_or_null("Mannequin")
	if mannequin != null:
		mannequin.set_process(false)
	foot_lock.set_collision_mask_for_test(2)
	var skeleton := driver.skeleton as Skeleton3D
	var left_index := skeleton.find_bone(&"mixamorig_LeftFoot")
	var left_world := (
		skeleton.global_transform * skeleton.get_bone_global_pose(left_index)
	).origin
	var step := _make_visible_step(
		Vector3(left_world.x, player.global_position.y, left_world.z), 0.18
	)
	scene.add_child(step)
	driver.set_visual_inputs(
		Vector2.ZERO, &"STANDING", 0.0, 0.0, 0.0, false, 0.0,
		0.0, &"STANDING", 0.0, &"WALK", 0.0
	)
	for _frame in range(24):
		await process_frame
	_hide_canvas_layers(scene)
	var existing_camera := root.get_viewport().get_camera_3d()
	if existing_camera != null:
		existing_camera.current = false
	var review_camera := Camera3D.new()
	review_camera.name = "SafeFootGroundingReviewCamera"
	review_camera.fov = 34.0
	review_camera.current = true
	scene.add_child(review_camera)
	review_camera.global_position = player.global_position + Vector3(4.2, 1.55, 3.4)
	review_camera.look_at(player.global_position + Vector3.UP * 0.95, Vector3.UP)
	for _frame in range(4):
		await process_frame
	_expect(
		await _capture(STANDING_CAPTURE_PATH),
		"rendered standing stair-contact capture saves"
	)
	driver.set_visual_inputs(
		Vector2.ZERO, &"CROUCHED", 0.0, 0.0, 0.0, false, 0.0,
		0.0, &"CROUCHED", 0.0, &"WALK", 0.0
	)
	for _frame in range(8):
		await process_frame
	var crouched_left_world := (
		skeleton.global_transform * skeleton.get_bone_global_pose(left_index)
	).origin
	step.global_position = Vector3(
		crouched_left_world.x,
		player.global_position.y + 0.09,
		crouched_left_world.z
	)
	await physics_frame
	for _frame in range(20):
		await process_frame
	_expect(
		await _capture(CROUCHED_CAPTURE_PATH),
		"rendered crouched stair-contact capture saves"
	)
	print("OPERATOR_STAIR_GROUNDING_VISUAL_STATE %s" % JSON.stringify(
		foot_lock.get_debug_state()
	))
	_finish()


func _make_visible_step(base: Vector3, height: float) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "SafeGroundingReviewStep"
	body.collision_layer = 2
	body.collision_mask = 0
	body.position = base + Vector3.UP * (height * 0.5)
	var shape_node := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.28, height, 0.32)
	shape_node.shape = shape
	body.add_child(shape_node)
	var mesh_node := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = shape.size
	mesh_node.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.26, 0.30, 0.34, 1.0)
	material.roughness = 0.86
	mesh_node.material_override = material
	body.add_child(mesh_node)
	return body


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


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("OPERATOR_STAIR_GROUNDING_VISUAL_CHECK PASS %s" % label)
		return
	failures.append(label)
	push_error("OPERATOR_STAIR_GROUNDING_VISUAL_CHECK FAIL %s" % label)


func _finish() -> void:
	if failures.is_empty():
		print(
			"OPERATOR_STAIR_FOOT_GROUNDING_VISUAL_CHECK PASS %s %s"
			% [STANDING_CAPTURE_PATH, CROUCHED_CAPTURE_PATH]
		)
		quit(0)
	else:
		print("OPERATOR_STAIR_FOOT_GROUNDING_VISUAL_CHECK FAIL %s" % [failures])
		quit(1)
