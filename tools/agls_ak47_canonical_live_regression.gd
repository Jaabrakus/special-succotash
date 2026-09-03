extends SceneTree

## Canonical AK-47 equipment and action proof. Run with:
## -- --weapon-rig-config=res://config/weapons/ak-47.json
## A display-backed run also saves the ready and two reload review frames below.

const CONFIG_PATH := "res://config/weapons/ak-47.json"
const MODEL_PATH := "res://assets/external/agls_intake/imported/weapons/ak47/ak47.glb"
const RELOAD_PATH := (
	"res://assets/external/agls_intake/imported/weapon_reload/"
	+ "ALSP2_Reloading_Rifle_AK47.scn"
)
const STANDING_CAPTURE_PATH := "/private/tmp/socom-agls-ak47-live-reload-standing.png"
const CROUCHED_CAPTURE_PATH := "/private/tmp/socom-agls-ak47-live-reload-crouched.png"
const READY_CAPTURE_PATH := "/private/tmp/socom-agls-ak47-live-ready.png"

var failures: Array[String] = []
var review_camera: Camera3D


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
	await _physics_steps(80)
	var player := scene.get_node_or_null("Player") as CharacterBody3D
	var controller := scene.get_node_or_null("WeaponController")
	var coordinator := scene.get_node_or_null("WeaponReloadCoordinator")
	var mannequin := player.get_node_or_null("Mannequin") if player != null else null
	var driver := mannequin.get_node_or_null("ProductionAnimation") if mannequin != null else null
	_expect(
		player != null and controller != null and coordinator != null and driver != null,
		"canonical player, weapon authority, reload coordinator, and animation consumer are live"
	)
	if player == null or controller == null or coordinator == null or driver == null:
		_finish()
		return
	var weapon := driver.get("weapon_node") as Node3D
	var mesh_root := weapon.find_child("WeaponMesh", true, false) as Node3D if weapon != null else null
	var weapon_skeleton := _find_skeleton(mesh_root) if mesh_root != null else null
	_expect(
		weapon != null
		and String(weapon.get_meta("weapon_id", "")) == "ak-47"
		and String(weapon.get_meta("rig_config", "")) == CONFIG_PATH,
		"canonical equipment runtime consumes the AK-47 saved contract"
	)
	_expect(
		mesh_root != null and weapon_skeleton != null
		and weapon_skeleton.find_bone("body") >= 0
		and weapon_skeleton.find_bone("muzzle") >= 0,
		"rendered weapon is the exported skeletal AGLS AK-47"
	)
	if weapon != null:
		for socket_name in [
			"Socket_RightHand", "Socket_LeftHand", "Socket_BarrelBase",
			"Socket_Muzzle", "Socket_Buttstock", "Socket_Optic", "Socket_Ejection",
		]:
			_expect(
				weapon.find_child(socket_name, true, false) is Marker3D,
				"live AK-47 exposes %s" % socket_name
			)
	var rendered_span := _rendered_mesh_span(mesh_root)
	print("AGLS_AK47_LIVE_MODEL span_m=%.6f" % rendered_span)
	_expect(
		rendered_span >= 0.95 and rendered_span <= 1.05,
		"live AGLS AK-47 remains human rifle scale"
	)
	var clip_paths: Dictionary = driver.get("clip_paths")
	_expect(
		String(clip_paths.get(&"reload_ak47", "")) == RELOAD_PATH
		and bool(driver.call("has_clip", &"reload_ak47")),
		"canonical animation library loads the verified AK-47 reload"
	)
	var handling: Dictionary = driver.get("equipped_weapon_handling_profile")
	var slots: Dictionary = handling.get("animation_slots", {})
	_expect(
		String(slots.get("fire_standing", "")) == "combat_fire"
		and String(slots.get("fire_crouched", "")) == "crouch_fire"
		and String(slots.get("idle_standing", "")) == "aim_idle"
		and is_equal_approx(
			float((handling.get("ready_aim", {}) as Dictionary).get("fire_hold_seconds", 0.0)),
			1.2
		),
		"live AK-47 keeps shared fire poses and the 1.2 second recovery"
	)
	_setup_review_camera(scene, player, mannequin)
	await _process_steps(12)
	await _check_ready_contacts(driver)
	await _capture_ready_review(driver, player)
	_check_live_bore_alignment(driver, weapon, weapon_skeleton)
	await _exercise_reload(
		player, controller, coordinator, driver, 0, &"STANDING",
		&"reload_ak47", STANDING_CAPTURE_PATH
	)
	await _exercise_reload(
		player, controller, coordinator, driver, 1, &"CROUCHED",
		&"reload_ak47", CROUCHED_CAPTURE_PATH
	)
	player.call("_try_set_posture", 2)
	await _physics_steps(18)
	_expect(
		StringName(driver.call("resolve_semantic_action", &"reload")) == &"prone_reload",
		"prone keeps its authored prone reload instead of the unproven standing AK take"
	)
	_finish()


func _check_ready_contacts(driver: Node) -> void:
	await _physics_steps(40)
	var debug: Dictionary = driver.call("get_animation_debug_state")
	var pose: Dictionary = debug.get("weapon_pose", {})
	print("AGLS_AK47_LIVE_READY trigger_error_m=%.6f support_error_m=%.6f" % [
		float(pose.get("trigger_hand_error_m", INF)),
		float(pose.get("support_hand_error_m", INF)),
	])
	_expect(
		float(pose.get("trigger_hand_error_m", INF)) <= 0.04,
		"AK-47 trigger hand reaches the measured grip"
	)


func _check_live_bore_alignment(
	driver: Node,
	weapon: Node3D,
	weapon_skeleton: Skeleton3D
) -> void:
	if weapon == null or weapon_skeleton == null:
		return
	var barrel := weapon.find_child("Socket_BarrelBase", true, false) as Marker3D
	var muzzle := weapon.find_child("Socket_Muzzle", true, false) as Marker3D
	var stock := weapon.find_child("Socket_Buttstock", true, false) as Marker3D
	if barrel == null or muzzle == null or stock == null:
		return
	var debug: Dictionary = driver.call("get_animation_debug_state")
	var pose: Dictionary = debug.get("weapon_pose", {})
	var aim_direction: Vector3 = pose.get("aim_direction", Vector3.ZERO)
	var bore_direction := barrel.global_position.direction_to(muzzle.global_position)
	var pivot := weapon.find_child("CalibratedWeaponPivot", true, false) as Node3D
	var local_aim := (
		pivot.global_basis.inverse() * aim_direction
		if pivot != null
		else Vector3.ZERO
	)
	print("AGLS_AK47_LIVE_BORE direction=%s aim=%s local_aim=%s pivot_rotation=%s dot=%.6f" % [
		bore_direction, aim_direction, local_aim,
		pivot.global_rotation_degrees if pivot != null else Vector3.ZERO,
		bore_direction.dot(aim_direction),
	])
	_expect(
		bore_direction.dot(aim_direction) >= 0.98,
		"physical AK-47 barrel points at the canonical reticle aim"
	)
	_expect(
		stock.global_position.direction_to(barrel.global_position).dot(bore_direction)
			>= 0.85,
		"AK-47 buttstock, receiver, and muzzle remain in physical order"
	)
	var model_body := (
		weapon_skeleton.global_transform
		* weapon_skeleton.get_bone_global_pose(weapon_skeleton.find_bone("body"))
	).origin
	var model_muzzle := (
		weapon_skeleton.global_transform
		* weapon_skeleton.get_bone_global_pose(weapon_skeleton.find_bone("muzzle"))
	).origin
	_expect(
		model_body.distance_to(barrel.global_position) <= 0.001
		and model_muzzle.distance_to(muzzle.global_position) <= 0.001,
		"rendered AK-47 body and muzzle bones coincide with gameplay sockets"
	)
	_expect(
		float(pose.get("support_hand_error_m", INF)) <= 0.03,
		"AK-47 support hand reaches the measured handguard"
	)


func _capture_ready_review(driver: Node, player: CharacterBody3D) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var target := _operator_review_target(driver, player)
	review_camera.global_position = target + Vector3(2.6, 0.15, -0.8)
	review_camera.look_at(target, Vector3.UP)
	await _process_steps(3)
	_expect(await _capture(READY_CAPTURE_PATH), "ready contact review capture saves")


func _exercise_reload(
	player: CharacterBody3D,
	controller: Node,
	coordinator: Node,
	driver: Node,
	posture_index: int,
	posture_name: StringName,
	expected_clip: StringName,
	capture_path: String
) -> void:
	_expect(bool(player.call("_try_set_posture", posture_index)), "%s posture is available" % posture_name)
	await _physics_steps(24)
	var shot: Dictionary = controller.call("request_fire")
	_expect(bool(shot.get("fired", false)), "%s test shot is accepted" % posture_name)
	await _physics_steps(2)
	var fire_debug: Dictionary = driver.call("get_animation_debug_state")
	var fire_latch: Dictionary = fire_debug.get("fire_upper_body_latch", {})
	_expect(
		StringName(fire_latch.get("owner_state", &"")) == &"FIRE_RECOVERY"
		and bool(fire_latch.get("selected", false))
		and StringName(fire_debug.get("active_fire_clip", &"invalid")) == &"",
		"%s shot uses FIRE_RECOVERY without a second fire one-shot" % posture_name
	)
	await _physics_steps(16)
	_expect(bool(coordinator.call("request_reload")), "%s real reload input is accepted" % posture_name)
	await _physics_steps(2)
	var debug: Dictionary = driver.call("get_animation_debug_state")
	var presentation: Dictionary = debug.get("last_event_presentation", {})
	_expect(
		StringName(driver.get("requested_action")) == expected_clip
		and StringName(presentation.get("state", "")) == expected_clip
		and StringName(presentation.get("family_route_state", "")) == &"reload",
		"%s coordinator resolves the AK-specific reload through the canonical consumer" % posture_name
	)
	_expect(
		int(debug.get(
			"crouched_reload_trigger_count"
				if posture_name == &"CROUCHED"
				else "standing_reload_trigger_count",
			0
		)) > 0,
		"%s reload fires the posture-preserving upper-body layer" % posture_name
	)
	var hand_indices := [
		(driver.get("skeleton") as Skeleton3D).find_bone("mixamorig_LeftHand"),
		(driver.get("skeleton") as Skeleton3D).find_bone("mixamorig_RightHand"),
	]
	var skeleton := driver.get("skeleton") as Skeleton3D
	var skeleton_world := skeleton.global_transform
	var initial_hands := [
		(skeleton_world * skeleton.get_bone_global_pose(hand_indices[0])).origin,
		(skeleton_world * skeleton.get_bone_global_pose(hand_indices[1])).origin,
	]
	var maximum_hand_motion := 0.0
	for _frame in range(44):
		await physics_frame
		maximum_hand_motion = maxf(
			maximum_hand_motion,
			maxf(
				initial_hands[0].distance_to(
					(skeleton.global_transform * skeleton.get_bone_global_pose(
						hand_indices[0]
					)).origin
				),
				initial_hands[1].distance_to(
					(skeleton.global_transform * skeleton.get_bone_global_pose(
						hand_indices[1]
					)).origin
				)
			)
		)
	var metrics := _live_body_metrics(skeleton)
	print("AGLS_AK47_LIVE_RELOAD posture=%s motion=%.6f metrics=%s presentation=%s" % [
		posture_name, maximum_hand_motion, JSON.stringify(metrics), JSON.stringify(presentation),
	])
	_expect(maximum_hand_motion >= 0.001, "%s AK reload visibly animates both arm chains" % posture_name)
	_expect(
		bool(metrics.get("finite", false))
		and float(metrics.get("shoulder_span_m", 0.0)) >= 0.35
		and float(metrics.get("shoulder_span_m", 0.0)) <= 0.50
		and float(metrics.get("hand_span_m", 0.0)) >= 0.10
		and float(metrics.get("hand_span_m", 0.0)) <= 0.90
		and float(metrics.get("shoulder_level_m", INF)) <= 0.22
		and float(metrics.get("shoulder_yaw_degrees", INF)) <= 70.0,
		"%s layered AK reload remains anatomically human" % posture_name
	)
	if DisplayServer.get_name() != "headless":
		var target := _operator_review_target(driver, player)
		review_camera.global_position = target + Vector3(2.8, 0.10, 0.10)
		review_camera.look_at(target, Vector3.UP)
		await _process_steps(3)
		_expect(await _capture(capture_path), "%s live review capture saves" % posture_name)
	var wait_frames := 0
	while bool(coordinator.get("pending")) and wait_frames < 180:
		await physics_frame
		wait_frames += 1
	_expect(not bool(coordinator.get("pending")), "%s reload completes its canonical timeline" % posture_name)


func _setup_review_camera(scene: Node3D, player: CharacterBody3D, mannequin: Node) -> void:
	_hide_canvas_layers(scene)
	var boom_visualizer := scene.find_child("CameraBoomVisualizer", true, false) as Node3D
	if boom_visualizer != null:
		boom_visualizer.visible = false
	if mannequin != null and mannequin.has_method("set_proxy_visuals_visible"):
		mannequin.call("set_proxy_visuals_visible", false)
	var existing := root.get_viewport().get_camera_3d()
	if existing != null:
		existing.current = false
	review_camera = Camera3D.new()
	review_camera.name = "AK47CanonicalReloadReviewCamera"
	review_camera.fov = 38.0
	review_camera.current = true
	review_camera.set_cull_mask_value(20, false)
	scene.add_child(review_camera)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-42.0, -30.0, 0.0)
	key.light_energy = 1.8
	scene.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-18.0, 145.0, 0.0)
	fill.light_color = Color(0.55, 0.72, 1.0)
	fill.light_energy = 0.9
	scene.add_child(fill)


func _live_body_metrics(skeleton: Skeleton3D) -> Dictionary:
	var left_index := skeleton.find_bone("mixamorig_LeftArm")
	var right_index := skeleton.find_bone("mixamorig_RightArm")
	var left_hand_index := skeleton.find_bone("mixamorig_LeftHand")
	var right_hand_index := skeleton.find_bone("mixamorig_RightHand")
	var chest_index := skeleton.find_bone("mixamorig_Spine2")
	if (
		left_index < 0 or right_index < 0
		or left_hand_index < 0 or right_hand_index < 0 or chest_index < 0
	):
		return {"finite": false}
	var world := skeleton.global_transform
	var left := (world * skeleton.get_bone_global_pose(left_index)).origin
	var right := (world * skeleton.get_bone_global_pose(right_index)).origin
	var left_hand := (world * skeleton.get_bone_global_pose(left_hand_index)).origin
	var right_hand := (world * skeleton.get_bone_global_pose(right_hand_index)).origin
	var chest_world := world * skeleton.get_bone_global_pose(chest_index)
	var shoulder_line := (
		chest_world.affine_inverse() * left
		- chest_world.affine_inverse() * right
	)
	return {
		"finite": left.is_finite() and right.is_finite()
			and left_hand.is_finite() and right_hand.is_finite(),
		"shoulder_span_m": left.distance_to(right),
		"shoulder_level_m": absf(left.y - right.y),
		"shoulder_yaw_degrees": absf(rad_to_deg(atan2(
			absf(shoulder_line.z), maxf(absf(shoulder_line.x), 0.000001)
		))),
		"hand_span_m": left_hand.distance_to(right_hand),
	}


func _operator_review_target(driver: Node, player: CharacterBody3D) -> Vector3:
	var skeleton := driver.get("skeleton") as Skeleton3D
	if skeleton == null:
		return player.global_position + Vector3.UP * 1.15
	var chest_index := skeleton.find_bone("mixamorig_Spine2")
	if chest_index < 0:
		return player.global_position + Vector3.UP * 1.15
	return (
		skeleton.global_transform * skeleton.get_bone_global_pose(chest_index)
	).origin


func _rendered_mesh_span(node: Node3D) -> float:
	if node == null:
		return 0.0
	var points: Array[Vector3] = []
	_collect_mesh_points(node, points)
	if points.is_empty():
		return 0.0
	var bounds := AABB(points[0], Vector3.ZERO)
	for point in points:
		bounds = bounds.expand(point)
	return maxf(bounds.size.x, maxf(bounds.size.y, bounds.size.z))


func _collect_mesh_points(node: Node, points: Array[Vector3]) -> void:
	if node is MeshInstance3D:
		var mesh_node := node as MeshInstance3D
		var bounds := mesh_node.get_aabb()
		for x in [0.0, 1.0]:
			for y in [0.0, 1.0]:
				for z in [0.0, 1.0]:
					points.append(
						mesh_node.global_transform
						* (bounds.position + bounds.size * Vector3(x, y, z))
					)
	for child in node.get_children():
		_collect_mesh_points(child, points)


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for child in node.get_children():
		var found := _find_skeleton(child)
		if found != null:
			return found
	return null


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


func _physics_steps(count: int) -> void:
	for _frame in range(count):
		await physics_frame


func _process_steps(count: int) -> void:
	for _frame in range(count):
		await process_frame


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("AGLS_AK47_LIVE_CHECK PASS %s" % label)
		return
	failures.append(label)
	push_error("AGLS_AK47_LIVE_CHECK FAIL %s" % label)


func _finish() -> void:
	if failures.is_empty():
		print("AGLS_AK47_CANONICAL_LIVE_REGRESSION PASS ready=%s standing=%s crouched=%s" % [
			READY_CAPTURE_PATH, STANDING_CAPTURE_PATH, CROUCHED_CAPTURE_PATH,
		])
		quit(0)
	else:
		print("AGLS_AK47_CANONICAL_LIVE_REGRESSION FAIL %s" % [failures])
		quit(1)
