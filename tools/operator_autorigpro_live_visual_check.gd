extends SceneTree

const CAPTURE_PATH := "/private/tmp/socom-autorigpro-live-weapon.png"
const SIDE_CAPTURE_PATH := "/private/tmp/socom-autorigpro-live-weapon-side.png"
const PLACEMENT_CAPTURE_PATH := "/private/tmp/socom-autorigpro-placement-candidate-side.png"
const MOVEMENT_FIRE_CAPTURE_PREFIX := "/private/tmp/socom-autorigpro-movement-fire"
const UNIFIED_FIRE_CAPTURE_PREFIX := "/private/tmp/socom-autorigpro-unified-fire"
const CROUCH_FIRE_CAPTURE_PREFIX := "/private/tmp/socom-autorigpro-crouch-fire"

var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1440, 900)
	var packed := load("res://main.tscn") as PackedScene
	_expect(packed != null, "main scene loads")
	if packed == null:
		_finish()
		return
	var scene := packed.instantiate() as Node3D
	root.add_child(scene)
	await _steps(60)
	var player := scene.get_node_or_null("Player") as CharacterBody3D
	var mannequin := player.get_node_or_null("Mannequin") if player != null else null
	var driver := mannequin.get_node_or_null("ProductionAnimation") if mannequin != null else null
	var weapon := driver.get("weapon_node") as Node3D if driver != null else null
	var mesh_root := weapon.find_child("WeaponMesh", true, false) as Node3D if weapon != null else null
	_expect(player != null and driver != null, "live Auto-Rig Pro operator exists")
	_expect(weapon != null and mesh_root != null, "canonical weapon root owns a real mesh child")
	_expect(_count_meshes(mesh_root) > 0, "AssaultRifle_1 contributes rendered mesh geometry")
	for socket_name in [
		"Socket_RightHand", "Socket_LeftHand", "Socket_BarrelBase", "Socket_Muzzle",
		"Socket_Buttstock", "Socket_Optic", "Socket_Ejection",
	]:
		_expect(
			weapon != null and weapon.find_child(socket_name, true, false) is Marker3D,
			"canonical weapon exposes %s" % socket_name
		)
	if player == null or driver == null or weapon == null or mesh_root == null:
		_finish()
		return
	var weapon_controller := scene.get_node_or_null("WeaponController")
	if weapon_controller != null:
		weapon_controller.call("request_fire")
	await _steps(12)
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
	review_camera.name = "AutoRigProLiveReviewCamera"
	review_camera.fov = 42.0
	review_camera.current = true
	review_camera.set_cull_mask_value(20, false)
	scene.add_child(review_camera)
	var review_target := player.global_position + Vector3.UP * 1.34
	review_camera.global_position = player.global_position + Vector3(1.30, 1.58, 2.30)
	review_camera.look_at(review_target, Vector3.UP)
	await _steps(3)
	if DisplayServer.get_name() == "headless":
		push_error("OPERATOR_AUTORIGPRO_LIVE_VISUAL_CHECK requires a display-backed run")
		quit(1)
		return
	_expect(await _capture(CAPTURE_PATH), "clean rear review capture saves")
	review_camera.global_position = player.global_position + Vector3(2.55, 1.48, 0.10)
	review_camera.look_at(review_target, Vector3.UP)
	await _steps(3)
	_expect(await _capture(SIDE_CAPTURE_PATH), "clean side review capture saves")
	if OS.get_cmdline_user_args().has("--capture-placement-candidate"):
		var solver = driver.get("weapon_pose_solver")
		if solver != null:
			solver.set("right_hand_owns_ready_weapon", false)
			solver.set("animation_drives_ready_hands", false)
			solver.set("gun_placement_line_active", true)
			await _steps(24)
			var pose: Dictionary = driver.call("get_animation_debug_state").get(
				"weapon_pose", {}
			)
			print("OPERATOR_AUTORIGPRO_PLACEMENT_CANDIDATE trigger_error=%.4f support_error=%.4f aim_error_deg=%.4f right_elbow=%.2f left_elbow=%.2f" % [
				float(pose.get("trigger_hand_error_m", INF)),
				float(pose.get("support_hand_error_m", INF)),
				float(pose.get("weapon_aim_error_deg", INF)),
				float(pose.get("right_elbow_angle_deg", 0.0)),
				float(pose.get("left_elbow_angle_deg", 0.0)),
			])
			_expect(
				await _capture(PLACEMENT_CAPTURE_PATH),
				"shoulder-placement candidate side capture saves"
			)
	if OS.get_cmdline_user_args().has("--capture-movement-fire"):
		await _capture_movement_fire(
			scene, player, driver, weapon, review_camera, false
		)
	if OS.get_cmdline_user_args().has("--capture-unified-fire-candidate"):
		await _capture_movement_fire(
			scene, player, driver, weapon, review_camera, true
		)
	if OS.get_cmdline_user_args().has("--capture-crouch-fire"):
		await _capture_crouch_fire(
			scene, player, driver, weapon, review_camera
		)
	_finish()


func _capture_movement_fire(
	scene: Node3D,
	player: CharacterBody3D,
	driver: Node,
	weapon: Node3D,
	review_camera: Camera3D,
	unified_candidate: bool
) -> void:
	var weapon_controller := scene.get_node_or_null("WeaponController")
	_expect(weapon_controller != null, "movement-fire weapon controller exists")
	if weapon_controller == null:
		return
	if driver.has_method("clear_fire_ready_aim"):
		driver.call("clear_fire_ready_aim")
	for _frame in range(30):
		await physics_frame
	Input.action_release(&"move_forward")
	player.set_physics_process(false)
	var mannequin := player.get_node_or_null("Mannequin")
	if mannequin != null:
		mannequin.set_process(false)
	driver.call(
		"set_visual_inputs",
		Vector2(0.0, 1.0), &"STANDING", 0.0, 0.0, 0.0, false, 0.0,
		1.0, &"LOCOMOTION", 0.0, &"FULL", 5.45,
		player.global_position + Vector3(0.0, 1.35, -25.0),
		Vector2(0.0, 1.0), 1.0, &"SUSTAINED", 0.0
	)
	var capture_prefix := MOVEMENT_FIRE_CAPTURE_PREFIX
	if unified_candidate:
		capture_prefix = UNIFIED_FIRE_CAPTURE_PREFIX
		var handling_profile: Dictionary = driver.get(
			"equipped_weapon_handling_profile"
		)
		handling_profile["standing_fire_uses_aim_idle"] = false
		driver.set("equipped_weapon_handling_profile", handling_profile)
		var solver = driver.get("weapon_pose_solver")
		if solver != null:
			solver.set("right_hand_owns_ready_weapon", false)
			solver.set("animation_drives_ready_hands", false)
			solver.set("gun_placement_line_active", true)
	for _frame in range(24):
		await process_frame
	var pre_shot_target := _operator_review_target(driver, player)
	review_camera.global_position = pre_shot_target + Vector3(2.80, 0.10, 0.10)
	review_camera.look_at(pre_shot_target, Vector3.UP)
	_expect(
		await _capture("%s-pre.png" % capture_prefix),
		"movement-fire pre-shot forward-run capture saves"
	)
	var shot: Dictionary = weapon_controller.call("request_fire")
	_expect(bool(shot.get("fired", false)), "movement-fire diagnostic shot is accepted")
	var lowest_relative_weapon_y := INF
	var lowest_frame := -1
	var capture_frames := [0, 4, 12, 24, 72, 96]
	for frame in range(105):
		await process_frame
		var snapshot: Dictionary = driver.call("get_animation_debug_state")
		var pose: Dictionary = snapshot.get("weapon_pose", {})
		var relative_weapon_y := weapon.global_position.y - player.global_position.y
		if relative_weapon_y < lowest_relative_weapon_y:
			lowest_relative_weapon_y = relative_weapon_y
			lowest_frame = frame
		print(
			"OPERATOR_AUTORIGPRO_MOVEMENT_FIRE_METRIC",
			" frame=", frame,
			" owner=", String(pose.get("weapon_owner", &"")),
			" fire_clip=", String(snapshot.get("active_fire_clip", &"")),
			" ready_weight=", snappedf(float(pose.get("weight", 0.0)), 0.0001),
			" upper_blend=", snappedf(
				float(snapshot.get("upper_body_ready_blend", 0.0)), 0.0001
			),
			" weapon_relative_y=", snappedf(relative_weapon_y, 0.0001),
			" trigger_error=", snappedf(
				float(pose.get("trigger_hand_error_m", INF)), 0.0001
			),
			" support_error=", snappedf(
				float(pose.get("support_hand_error_m", INF)), 0.0001
			)
		)
		if frame in capture_frames:
			var target := _operator_review_target(driver, player)
			review_camera.global_position = target + Vector3(2.80, 0.10, 0.10)
			review_camera.look_at(target, Vector3.UP)
			_expect(
				await _capture("%s-%02d.png" % [capture_prefix, frame]),
				"movement-fire frame %d capture saves" % frame
			)
	print(
		"OPERATOR_AUTORIGPRO_MOVEMENT_FIRE_SUMMARY "
		+ "lowest_frame=%d lowest_weapon_relative_y=%.4f"
		% [lowest_frame, lowest_relative_weapon_y]
	)


func _capture_crouch_fire(
	scene: Node3D,
	player: CharacterBody3D,
	driver: Node,
	weapon: Node3D,
	review_camera: Camera3D
) -> void:
	var weapon_controller := scene.get_node_or_null("WeaponController")
	_expect(weapon_controller != null, "crouch-fire weapon controller exists")
	if weapon_controller == null:
		return
	if driver.has_method("clear_fire_ready_aim"):
		driver.call("clear_fire_ready_aim")
	await _steps(45)
	player.set_physics_process(false)
	var mannequin := player.get_node_or_null("Mannequin")
	if mannequin != null:
		mannequin.set_process(false)
	var aim_yaw := deg_to_rad(14.0)
	var aim_pitch := deg_to_rad(-4.0)
	var aim_direction := Vector3(
		sin(aim_yaw) * cos(aim_pitch),
		sin(aim_pitch),
		-cos(aim_yaw) * cos(aim_pitch)
	).normalized()
	var aim_target := player.global_position + Vector3.UP * 1.25 + aim_direction * 25.0
	driver.call(
		"set_visual_inputs",
		Vector2.ZERO, &"CROUCHED", aim_yaw, aim_pitch, 0.0, false, 0.0,
		0.0, &"LOCOMOTION", 0.0, &"WALK", 0.0,
		aim_target, Vector2.ZERO, 0.0, &"IDLE", 0.0
	)
	await _steps(24)
	var pre_snapshot: Dictionary = driver.call("get_animation_debug_state")
	var pre_pose: Dictionary = pre_snapshot.get("weapon_pose", {})
	_expect(
		bool(pre_pose.get("support_hand_grip_locked", false))
		and float(pre_pose.get("support_hand_error_m", INF)) <= 0.01,
		"crouch base keeps the left palm on the foregrip before firing"
	)
	var target := _operator_review_target(driver, player)
	review_camera.global_position = target + Vector3(2.80, 0.10, 0.10)
	review_camera.look_at(target, Vector3.UP)
	_expect(
		await _capture("%s-pre.png" % CROUCH_FIRE_CAPTURE_PREFIX),
		"crouch-fire pre-shot base capture saves"
	)
	var shot: Dictionary = weapon_controller.call("request_fire")
	_expect(bool(shot.get("fired", false)), "crouch-fire diagnostic shot is accepted")
	var maximum_support_error := 0.0
	var maximum_torso_error := 0.0
	var selected_sample_count := 0
	var capture_frames := [0, 4, 12, 24, 48, 72, 96]
	for frame in range(105):
		await process_frame
		var snapshot: Dictionary = driver.call("get_animation_debug_state")
		var pose: Dictionary = snapshot.get("weapon_pose", {})
		var support_error := float(pose.get("support_hand_error_m", INF))
		var torso_error := float(snapshot.get("torso_to_aim_error_deg", INF))
		if frame >= 12 and bool(snapshot.get("presentation_fire_selected", false)):
			selected_sample_count += 1
			maximum_support_error = maxf(maximum_support_error, support_error)
			maximum_torso_error = maxf(maximum_torso_error, torso_error)
		print(
			"OPERATOR_AUTORIGPRO_CROUCH_FIRE_METRIC",
			" frame=", frame,
			" selected=", bool(snapshot.get("presentation_fire_selected", false)),
			" torso_error_deg=", snappedf(torso_error, 0.001),
			" support_error=", snappedf(support_error, 0.0001),
			" weapon_relative_y=", snappedf(
				weapon.global_position.y - player.global_position.y,
				0.0001
			)
		)
		if frame in capture_frames:
			target = _operator_review_target(driver, player)
			review_camera.global_position = target + Vector3(2.80, 0.10, 0.10)
			review_camera.look_at(target, Vector3.UP)
			_expect(
				await _capture("%s-%02d.png" % [CROUCH_FIRE_CAPTURE_PREFIX, frame]),
				"crouch-fire frame %d capture saves" % frame
			)
	_expect(selected_sample_count > 0, "crouch recovery produces settled proof frames")
	_expect(maximum_support_error <= 0.01, "crouch recovery keeps the left palm on the foregrip")
	_expect(maximum_torso_error <= 1.0, "crouch recovery torso follows reticle yaw")
	print(
		"OPERATOR_AUTORIGPRO_CROUCH_FIRE_SUMMARY "
		+ "maximum_support_error=%.4f maximum_torso_error_deg=%.3f"
		% [maximum_support_error, maximum_torso_error]
	)


func _operator_review_target(driver: Node, player: CharacterBody3D) -> Vector3:
	var skeleton := driver.get("skeleton") as Skeleton3D
	if skeleton == null:
		return player.global_position + Vector3.UP * 1.15
	var chest_index := skeleton.find_bone(&"mixamorig_Spine2")
	if chest_index < 0:
		return player.global_position + Vector3.UP * 1.15
	return (
		skeleton.global_transform
		* skeleton.get_bone_global_pose(chest_index)
	).origin


func _hide_canvas_layers(node: Node) -> void:
	if node is CanvasLayer:
		(node as CanvasLayer).visible = false
	for child in node.get_children():
		_hide_canvas_layers(child)


func _count_meshes(node: Node) -> int:
	var count := 1 if node is MeshInstance3D and (node as MeshInstance3D).mesh != null else 0
	for child in node.get_children():
		count += _count_meshes(child)
	return count


func _capture(path: String) -> bool:
	RenderingServer.force_draw()
	await process_frame
	var image := root.get_texture().get_image()
	return image != null and not image.is_empty() and image.save_png(path) == OK


func _steps(count: int) -> void:
	for _frame in range(count):
		await process_frame


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("OPERATOR_AUTORIGPRO_LIVE_VISUAL_CHECK PASS %s" % label)
		return
	failures.append(label)
	push_error("OPERATOR_AUTORIGPRO_LIVE_VISUAL_CHECK FAIL %s" % label)


func _finish() -> void:
	if failures.is_empty():
		print("OPERATOR_AUTORIGPRO_LIVE_VISUAL_CHECK PASS %s" % CAPTURE_PATH)
		quit(0)
	else:
		print("OPERATOR_AUTORIGPRO_LIVE_VISUAL_CHECK FAIL %s" % [failures])
		quit(1)
