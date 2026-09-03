extends SceneTree

const MARK_23_PATH := "res://config/weapons/mark_23.json"
const CAPTURE_PREFIX := "/private/tmp/socom-mark23-fire-recovery"

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
	await _frames(60)
	var player := scene.get_node_or_null("Player") as CharacterBody3D
	var controller := scene.get_node_or_null("WeaponController")
	var mannequin := player.get_node_or_null("Mannequin") if player != null else null
	var driver = mannequin.get("production_animation") if mannequin != null else null
	_expect(
		player != null and controller != null and driver != null,
		"canonical player, weapon, and presentation owners are ready"
	)
	if player == null or controller == null or driver == null:
		scene.queue_free()
		_finish()
		return
	_expect(
		bool(controller.call("apply_authorized_weapon_pickup", MARK_23_PATH)),
		"Mark 23 equips through the canonical authorized handoff"
	)
	await _frames(30)
	_hide_canvas_layers(scene)
	var debug_visualizer := scene.find_child("CameraBoomVisualizer", true, false) as Node3D
	if debug_visualizer != null:
		debug_visualizer.visible = false
	if mannequin.has_method("set_proxy_visuals_visible"):
		mannequin.call("set_proxy_visuals_visible", false)
	var existing_camera := root.get_viewport().get_camera_3d()
	if existing_camera != null:
		existing_camera.current = false
	var review_camera := Camera3D.new()
	review_camera.name = "PistolFireRecoveryReviewCamera"
	review_camera.fov = 38.0
	review_camera.current = true
	review_camera.set_cull_mask_value(20, false)
	scene.add_child(review_camera)
	player.set_physics_process(false)
	mannequin.set_process(false)
	if DisplayServer.get_name() == "headless":
		push_error("PISTOL_FIRE_RECOVERY_VISUAL_CHECK requires a display-backed run")
		quit(1)
		return
	await _capture_posture(
		scene, player, controller, driver, review_camera,
		0, &"STANDING", &"pistol_idle"
	)
	await _capture_posture(
		scene, player, controller, driver, review_camera,
		1, &"CROUCHED", &"pistol_idle_kneeling"
	)
	scene.queue_free()
	await process_frame
	_finish()


func _capture_posture(
	scene: Node3D,
	player: CharacterBody3D,
	controller: Node,
	driver: Node,
	review_camera: Camera3D,
	posture_index: int,
	posture_name: StringName,
	expected_state: StringName
) -> void:
	if driver.has_method("clear_fire_ready_aim"):
		driver.call("clear_fire_ready_aim")
	_expect(
		bool(player.call("_try_set_posture", posture_index)),
		"player enters %s for visual proof" % posture_name
	)
	var aim_target := player.global_position + Vector3.UP * (
		1.20 if posture_name == &"CROUCHED" else 1.48
	) + Vector3.FORWARD * 25.0
	driver.call(
		"set_visual_inputs",
		Vector2.ZERO, posture_name, 0.0, 0.0, 0.0, false, 0.0,
		0.0, &"LOCOMOTION", 0.0, &"WALK", 0.0,
		aim_target, Vector2.ZERO, 0.0, &"IDLE", 0.0
	)
	await _frames(30)
	_aim_review_camera(review_camera, driver, player)
	var label := String(posture_name).to_lower()
	_expect(
		await _capture("%s-%s-before.png" % [CAPTURE_PREFIX, label]),
		"%s pre-shot frame saves" % posture_name
	)
	await _await_ballistics_ready(controller)
	var before: Dictionary = driver.call("get_animation_debug_state")
	var trigger_count_before := int(before.get("fire_trigger_count", 0))
	var shot: Dictionary = controller.call("request_fire")
	_expect(bool(shot.get("fired", false)), "%s shot is accepted" % posture_name)
	await _frames(8)
	var during: Dictionary = driver.call("get_animation_debug_state")
	var event: Dictionary = during.get("last_event_presentation", {})
	var latch: Dictionary = during.get("fire_upper_body_latch", {})
	var pose: Dictionary = during.get("weapon_pose", {})
	_expect(
		StringName(event.get("state", "")) == expected_state
		and String(latch.get("owner_state", "")) == "FIRE_RECOVERY"
		and bool(during.get("presentation_fire_selected", false))
		and String(during.get("active_fire_clip", "")).is_empty()
		and int(during.get("fire_trigger_count", 0)) == trigger_count_before,
		"%s recovery holds %s without a fire OneShot"
		% [posture_name, expected_state]
	)
	print(
		(
			"PISTOL_FIRE_RECOVERY_VISUAL_METRIC posture=%s trigger_error_m=%.4f "
			+ "support_error_m=%.4f torso_error_deg=%.3f recovery_remaining=%.3f"
		) % [
			String(posture_name),
			float(pose.get("trigger_hand_error_m", INF)),
			float(pose.get("support_hand_error_m", INF)),
			float(during.get("torso_to_aim_error_deg", INF)),
			float(latch.get("grace_remaining_seconds", 0.0)),
		]
	)
	_aim_review_camera(review_camera, driver, player)
	_expect(
		await _capture("%s-%s-recovery.png" % [CAPTURE_PREFIX, label]),
		"%s recovery frame saves" % posture_name
	)
	_aim_rear_camera(review_camera, driver, player)
	_expect(
		await _capture("%s-%s-recovery-rear.png" % [CAPTURE_PREFIX, label]),
		"%s rear shoulder recovery frame saves" % posture_name
	)
	# Render FPS is not gameplay time (the display-backed proof can exceed 60
	# FPS), so wait on real SceneTree time instead of assuming 72 frames = 1.2 s.
	await create_timer(1.30).timeout
	await _frames(3)
	var after: Dictionary = driver.call("get_animation_debug_state")
	_expect(
		not bool(after.get("presentation_fire_selected", true)),
		"%s recovery returns to authored base" % posture_name
	)
	_aim_review_camera(review_camera, driver, player)
	_expect(
		await _capture("%s-%s-after.png" % [CAPTURE_PREFIX, label]),
		"%s post-recovery frame saves" % posture_name
	)


func _await_ballistics_ready(controller: Node) -> void:
	var ballistics = controller.get("ballistics")
	if ballistics == null:
		return
	for _frame in 240:
		if float(ballistics.get("fire_cooldown")) <= 0.0:
			return
		await process_frame
		await physics_frame


func _aim_review_camera(
	camera: Camera3D,
	driver: Node,
	player: CharacterBody3D
) -> void:
	var target := player.global_position + Vector3.UP * 1.15
	var skeleton := driver.get("skeleton") as Skeleton3D
	if skeleton != null:
		var chest_index := skeleton.find_bone(&"mixamorig_Spine2")
		if chest_index >= 0:
			target = (
				skeleton.global_transform
				* skeleton.get_bone_global_pose(chest_index)
			).origin
	camera.global_position = target + Vector3(2.65, 0.16, 1.65)
	camera.look_at(target, Vector3.UP)


func _aim_rear_camera(
	camera: Camera3D,
	driver: Node,
	player: CharacterBody3D
) -> void:
	var target := player.global_position + Vector3.UP * 1.15
	var skeleton := driver.get("skeleton") as Skeleton3D
	if skeleton != null:
		var chest_index := skeleton.find_bone(&"mixamorig_Spine2")
		if chest_index >= 0:
			target = (
				skeleton.global_transform
				* skeleton.get_bone_global_pose(chest_index)
			).origin
	camera.global_position = target + Vector3(0.0, 0.12, 2.85)
	camera.look_at(target, Vector3.UP)


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


func _frames(count: int) -> void:
	for _frame in count:
		await process_frame


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("PISTOL_FIRE_RECOVERY_VISUAL_CHECK PASS %s" % label)
		return
	failures.append(label)
	push_error("PISTOL_FIRE_RECOVERY_VISUAL_CHECK FAIL %s" % label)


func _finish() -> void:
	if failures.is_empty():
		print("PISTOL_FIRE_RECOVERY_VISUAL_CHECK PASS %s" % CAPTURE_PREFIX)
		quit(0)
		return
	print("PISTOL_FIRE_RECOVERY_VISUAL_CHECK FAIL ", failures)
	quit(1)
