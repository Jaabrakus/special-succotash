extends SceneTree

## Display-backed review of every real pistol, assault-rifle, and SMG profile.
##
## The proof enters res://main.tscn and equips each saved profile through the
## same authorized handoff used by gameplay. It does not write runtime state or
## weapon configuration. Four side-review frames are saved for every weapon,
## plus rear shoulder frames for selected geometry representatives.

const OUTPUT_DIR := "/private/tmp/socom-firearm-family-visual-proof"
const VIEW_SIZE := Vector2i(960, 600)
const CELL_SIZE := Vector2i(480, 300)
const MAX_SHOULDER_YAW_DEG := 6.0
const MIN_SHOULDER_SPAN_M := 0.40
const MAX_SHOULDER_SPAN_M := 0.50
const MAX_ABS_PISTOL_ROLL_DEG := 12.0
const STATES := [
	"standing_ready",
	"standing_recovery",
	"crouched_ready",
	"crouched_recovery",
]
const REAR_CASES := [
	"mark_23",
	"de__50",
	"ak-47",
	"m4a1",
	"bullpup_1",
	"hk5",
]
const CASES := [
	# Pistols: every catalog profile and all six modular pistol meshes.
	{"id": "226", "group": "pistols"},
	{"id": "9mm_pistol", "group": "pistols"},
	{"id": "de__50", "group": "pistols"},
	{"id": "f57", "group": "pistols"},
	{"id": "m9", "group": "pistols"},
	{"id": "mark_23", "group": "pistols"},
	{"id": "mark_23sd", "group": "pistols"},
	{"id": "model_18", "group": "pistols"},
	# Assault-rifle catalog: includes authored, modular, bullpup, shotgun,
	# sniper, and SMG-shaped records classified by the gameplay catalog.
	{"id": "552", "group": "rifles"},
	{"id": "ak-47", "group": "rifles"},
	{"id": "aks-74", "group": "rifles"},
	{"id": "assaultrifle_1", "group": "rifles"},
	{"id": "assaultrifle_2", "group": "rifles"},
	{"id": "assaultrifle_3", "group": "rifles"},
	{"id": "assaultrifle_4", "group": "rifles"},
	{"id": "bullpup_1", "group": "rifles"},
	{"id": "m14", "group": "rifles"},
	{"id": "m16a2", "group": "rifles"},
	{"id": "m16a2-m203", "group": "rifles"},
	{"id": "m40a1", "group": "rifles"},
	{"id": "m4a1", "group": "rifles"},
	{"id": "m4a1-m203", "group": "rifles"},
	{"id": "m4a1_sd", "group": "rifles"},
	{"id": "shotgun_1", "group": "rifles"},
	{"id": "sniperrifle_1", "group": "rifles"},
	{"id": "submachinegun_1", "group": "rifles"},
	# Dedicated submachine-gun catalog profiles and all four SMG meshes.
	{"id": "9mm_sub", "group": "smgs"},
	{"id": "f90", "group": "smgs"},
	{"id": "hk5", "group": "smgs"},
	{"id": "hk5sd", "group": "smgs"},
]

var failures: Array[String] = []
var thumbnails: Dictionary = {}
var rear_thumbnails: Dictionary = {}
var metric_rows: Array[Dictionary] = []
var review_camera: Camera3D
var proof_label: Label


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("FIREARM_FAMILY_VISUAL_PROOF requires a display-backed run")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(OUTPUT_DIR)
	root.size = VIEW_SIZE
	var packed := load("res://main.tscn") as PackedScene
	_expect(packed != null, "canonical main scene loads")
	if packed == null:
		_finish()
		return
	var scene := packed.instantiate() as Node3D
	root.add_child(scene)
	await _steps(70)
	var player := scene.get_node_or_null("Player") as CharacterBody3D
	var controller := scene.get_node_or_null("WeaponController")
	var mannequin := player.get_node_or_null("Mannequin") if player != null else null
	var driver = mannequin.get("production_animation") if mannequin != null else null
	_expect(
		player != null and controller != null and mannequin != null and driver != null,
		"canonical player, equipment handoff, and presentation consumer are live"
	)
	if player == null or controller == null or mannequin == null or driver == null:
		scene.queue_free()
		_finish()
		return
	_setup_review_scene(scene, player, mannequin)
	player.set_physics_process(false)
	mannequin.set_process(false)
	for case_value in CASES:
		var weapon_case := case_value as Dictionary
		await _capture_weapon_case(
			scene,
			player,
			controller,
			driver,
			weapon_case
		)
	_write_contact_sheets()
	_write_manifest()
	scene.queue_free()
	await process_frame
	_finish()


func _capture_weapon_case(
	scene: Node3D,
	player: CharacterBody3D,
	controller: Node,
	driver: Node,
	weapon_case: Dictionary
) -> void:
	var weapon_id := String(weapon_case.get("id", ""))
	var group := String(weapon_case.get("group", ""))
	var config_path := "res://config/weapons/%s.json" % weapon_id
	var equipped := bool(controller.call("apply_authorized_weapon_pickup", config_path))
	_expect(equipped, "%s equips through the canonical authorized handoff" % weapon_id)
	if not equipped:
		return
	await _steps(18)
	for posture_case in [
		{"index": 0, "name": &"STANDING", "label": "standing", "height": 1.48},
		{"index": 1, "name": &"CROUCHED", "label": "crouched", "height": 1.20},
	]:
		if driver.has_method("clear_fire_ready_aim"):
			driver.call("clear_fire_ready_aim")
		_expect(
			bool(player.call("_try_set_posture", int(posture_case.get("index", 0)))),
			"%s enters %s" % [weapon_id, posture_case.get("name", &"")]
		)
		_set_visual_pose(player, driver, posture_case, 1.0)
		await _steps(22)
		var ready_state := "%s_ready" % String(posture_case.get("label", ""))
		await _capture_state(
			player, driver, weapon_id, group, ready_state, false
		)
		await _await_ballistics_ready(controller)
		var shot: Dictionary = controller.call("request_fire")
		_expect(
			bool(shot.get("fired", false)),
			"%s %s shot is accepted"
			% [weapon_id, posture_case.get("name", &"")]
		)
		await _steps(12)
		var recovery_state := "%s_recovery" % String(
			posture_case.get("label", "")
		)
		await _capture_state(
			player, driver, weapon_id, group, recovery_state, false
		)
		if weapon_id in REAR_CASES:
			await _capture_state(
				player, driver, weapon_id, group, recovery_state, true
			)
		_set_visual_pose(player, driver, posture_case, 0.0)
		if driver.has_method("clear_fire_ready_aim"):
			driver.call("clear_fire_ready_aim")
		await _steps(4)


func _set_visual_pose(
	player: CharacterBody3D,
	driver: Node,
	posture_case: Dictionary,
	ready_weight: float
) -> void:
	var aim_target := (
		player.global_position
		+ Vector3.UP * float(posture_case.get("height", 1.48))
		+ Vector3.FORWARD * 25.0
	)
	driver.call(
		"set_visual_inputs",
		Vector2.ZERO,
		StringName(posture_case.get("name", &"STANDING")),
		0.0,
		0.0,
		ready_weight,
		false,
		0.0,
		0.0,
		&"LOCOMOTION",
		0.0,
		&"WALK",
		0.0,
		aim_target,
		Vector2.ZERO,
		0.0,
		&"IDLE",
		0.0
	)


func _capture_state(
	player: CharacterBody3D,
	driver: Node,
	weapon_id: String,
	group: String,
	state_name: String,
	rear_view: bool
) -> void:
	var debug: Dictionary = driver.call("get_animation_debug_state")
	var pose: Dictionary = debug.get("weapon_pose", {})
	var trigger_error := float(pose.get("trigger_hand_error_m", INF))
	var support_error := float(pose.get("support_hand_error_m", INF))
	var aim_error := float(pose.get("weapon_aim_error_deg", INF))
	var latch: Dictionary = debug.get("fire_upper_body_latch", {})
	var is_recovery := state_name.ends_with("_recovery")
	var rig_id := String((driver.get("equipped_weapon_config") as Dictionary).get(
		"_visual_rig_id",
		"authored"
	))
	var anatomy := _body_metrics(driver.get("skeleton") as Skeleton3D)
	var weapon_roll := _weapon_roll_metrics(driver)
	var shoulder_yaw := float(anatomy.get("shoulder_yaw_deg", INF))
	var shoulder_span := float(anatomy.get("shoulder_span_m", INF))
	var operator_roll := float(weapon_roll.get("operator_deg", INF))
	proof_label.text = (
		"%s | %s | %s\nrig: %s\ntrigger %.1f mm | support %.1f mm | aim %.2f deg | roll %+.1f deg"
		% [
			weapon_id,
			group,
			state_name.replace("_", " ").to_upper(),
			rig_id,
			trigger_error * 1000.0,
			support_error * 1000.0,
			aim_error,
			operator_roll,
		]
	)
	_expect(
		trigger_error <= 0.01,
		"%s %s trigger-hand contact is within 1 cm" % [weapon_id, state_name]
	)
	_expect(
		support_error <= 0.01,
		"%s %s support-hand contact is within 1 cm" % [weapon_id, state_name]
	)
	_expect(
		aim_error <= 1.0,
		"%s %s bore remains within 1 degree of aim" % [weapon_id, state_name]
	)
	_expect(
		shoulder_yaw <= MAX_SHOULDER_YAW_DEG,
		"%s %s shoulder line stays within %.1f degrees of square"
		% [weapon_id, state_name, MAX_SHOULDER_YAW_DEG]
	)
	_expect(
		shoulder_span >= MIN_SHOULDER_SPAN_M
		and shoulder_span <= MAX_SHOULDER_SPAN_M,
		"%s %s shoulder span stays inside the operator anatomy envelope"
		% [weapon_id, state_name]
	)
	if group == "pistols":
		_expect(
			absf(operator_roll) <= MAX_ABS_PISTOL_ROLL_DEG,
			"%s %s pistol is not sideways (|roll| <= %.1f degrees)"
			% [weapon_id, state_name, MAX_ABS_PISTOL_ROLL_DEG]
		)
	if is_recovery:
		_expect(
			StringName(latch.get("owner_state", &"")) == &"FIRE_RECOVERY"
			and bool(debug.get("presentation_fire_selected", false))
			and String(debug.get("active_fire_clip", "")).is_empty(),
			"%s %s is the canonical recovery without a fire OneShot"
			% [weapon_id, state_name]
		)
	_aim_camera(player, driver, rear_view)
	await _steps(3)
	var view_suffix := "rear" if rear_view else "side"
	var path := "%s/%s-%s-%s.png" % [
		OUTPUT_DIR,
		weapon_id,
		state_name,
		view_suffix,
	]
	var image := await _capture(path)
	_expect(image != null, "%s %s %s frame saves" % [weapon_id, state_name, view_suffix])
	if image != null:
		var thumbnail := image.duplicate()
		thumbnail.resize(CELL_SIZE.x, CELL_SIZE.y, Image.INTERPOLATE_LANCZOS)
		thumbnail.convert(Image.FORMAT_RGBA8)
		var key := "%s|%s" % [weapon_id, state_name]
		if rear_view:
			rear_thumbnails[key] = thumbnail
		else:
			thumbnails[key] = thumbnail
	if not rear_view:
		metric_rows.append({
			"weapon_id": weapon_id,
			"group": group,
			"state": state_name,
			"rig_id": rig_id,
			"trigger_error_m": trigger_error,
			"support_error_m": support_error,
			"aim_error_deg": aim_error,
			"recovery_owner": String(latch.get("owner_state", "")),
			"logical_clip": String(debug.get("logical_clip", "")),
			"source_take": String(debug.get("source_take", "")),
			"equipped_weapon_family": String(
				debug.get("equipped_weapon_family", "")
			),
			"clean_ready_pose_weight": float(
				debug.get("clean_ready_pose_weight", 0.0)
			),
			"weapon_owner": String(pose.get("weapon_owner", "")),
			"right_hand_owns_ready_weapon": bool(
				pose.get("right_hand_owns_ready_weapon", false)
			),
			"animation_drives_ready_hands": bool(
				pose.get("animation_drives_ready_hands", false)
			),
			"gun_placement_line_active": bool(
				pose.get("gun_placement_line_active", false)
			),
			"shoulder_span_m": shoulder_span,
			"shoulder_level_m": float(anatomy.get("shoulder_level_m", INF)),
			"shoulder_yaw_deg": shoulder_yaw,
			"weapon_roll_operator_deg": operator_roll,
			"weapon_roll_world_deg": float(weapon_roll.get("world_deg", INF)),
			"weapon_roll_solver_error_deg": float(
				pose.get("gun_placement_roll_error_deg", INF)
			),
		})
		print(
			"FIREARM_FAMILY_VISUAL_METRIC %s"
			% JSON.stringify(metric_rows.back())
		)


func _setup_review_scene(
	scene: Node3D,
	player: CharacterBody3D,
	mannequin: Node
) -> void:
	_hide_canvas_layers(scene)
	var debug_visualizer := scene.find_child(
		"CameraBoomVisualizer", true, false
	) as Node3D
	if debug_visualizer != null:
		debug_visualizer.visible = false
	if mannequin.has_method("set_proxy_visuals_visible"):
		mannequin.call("set_proxy_visuals_visible", false)
	var existing_camera := root.get_viewport().get_camera_3d()
	if existing_camera != null:
		existing_camera.current = false
	review_camera = Camera3D.new()
	review_camera.name = "FirearmFamilyVisualProofCamera"
	review_camera.fov = 38.0
	review_camera.near = 0.05
	review_camera.current = true
	review_camera.set_cull_mask_value(20, false)
	scene.add_child(review_camera)
	var world_environment := scene.find_child(
		"WorldEnvironment", true, false
	) as WorldEnvironment
	if world_environment != null and world_environment.environment != null:
		world_environment.environment = world_environment.environment.duplicate(true)
		world_environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		world_environment.environment.ambient_light_color = Color(0.85, 0.90, 1.0)
		world_environment.environment.ambient_light_energy = 1.45
	var key := DirectionalLight3D.new()
	key.name = "VisualProofKey"
	key.rotation_degrees = Vector3(-38.0, -55.0, 0.0)
	key.light_color = Color(1.0, 0.92, 0.82)
	key.light_energy = 2.4
	scene.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.name = "VisualProofFill"
	fill.rotation_degrees = Vector3(-20.0, 135.0, 0.0)
	fill.light_color = Color(0.62, 0.78, 1.0)
	fill.light_energy = 1.8
	scene.add_child(fill)
	var overlay := CanvasLayer.new()
	overlay.name = "FirearmFamilyVisualProofOverlay"
	overlay.layer = 100
	scene.add_child(overlay)
	proof_label = Label.new()
	proof_label.position = Vector2(18.0, 16.0)
	proof_label.add_theme_font_size_override("font_size", 25)
	proof_label.add_theme_color_override("font_color", Color.WHITE)
	proof_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.95))
	proof_label.add_theme_constant_override("outline_size", 7)
	overlay.add_child(proof_label)
	_aim_camera(player, mannequin.get("production_animation"), false)


func _aim_camera(
	player: CharacterBody3D,
	driver: Node,
	rear_view: bool
) -> void:
	var target := _operator_review_target(driver, player)
	if rear_view:
		review_camera.global_position = target + Vector3(0.0, 0.10, 2.75)
	else:
		# Review from the front quarter: the former rear-quarter angle hid the
		# weapon behind the torso and could not visually expose a sideways roll.
		review_camera.global_position = target + Vector3(2.55, 0.10, -1.65)
	review_camera.look_at(target, Vector3.UP)


func _operator_review_target(driver: Node, player: CharacterBody3D) -> Vector3:
	var skeleton := driver.get("skeleton") as Skeleton3D
	if skeleton == null:
		return player.global_position + Vector3.UP * 1.20
	var chest_index := skeleton.find_bone(&"mixamorig_Spine2")
	if chest_index < 0:
		return player.global_position + Vector3.UP * 1.20
	return (
		skeleton.global_transform
		* skeleton.get_bone_global_pose(chest_index)
	).origin


func _body_metrics(skeleton: Skeleton3D) -> Dictionary:
	if skeleton == null:
		return {}
	var left_index := skeleton.find_bone(&"mixamorig_LeftArm")
	var right_index := skeleton.find_bone(&"mixamorig_RightArm")
	var chest_index := skeleton.find_bone(&"mixamorig_Spine2")
	if left_index < 0 or right_index < 0 or chest_index < 0:
		return {}
	var world := skeleton.global_transform
	var left := (world * skeleton.get_bone_global_pose(left_index)).origin
	var right := (world * skeleton.get_bone_global_pose(right_index)).origin
	var chest_world := world * skeleton.get_bone_global_pose(chest_index)
	var local_line := (
		chest_world.affine_inverse() * left
		- chest_world.affine_inverse() * right
	)
	return {
		"shoulder_span_m": left.distance_to(right),
		"shoulder_level_m": absf(left.y - right.y),
		"shoulder_yaw_deg": absf(rad_to_deg(atan2(
			absf(local_line.z),
			maxf(absf(local_line.x), 0.000001)
		))),
	}


func _weapon_roll_metrics(driver: Node) -> Dictionary:
	var solver = driver.get("weapon_pose_solver")
	var skeleton := driver.get("skeleton") as Skeleton3D
	if solver == null or skeleton == null:
		return {}
	var muzzle := solver.get("muzzle_socket") as Marker3D
	var barrel_base := solver.get("barrel_base_socket") as Marker3D
	var optic := solver.get("optic_socket") as Marker3D
	if muzzle == null or barrel_base == null or optic == null:
		return {}
	var direction := (muzzle.global_position - barrel_base.global_position).normalized()
	var actual_up := optic.global_position - barrel_base.global_position
	actual_up -= direction * actual_up.dot(direction)
	if direction.length_squared() < 0.50 or actual_up.length_squared() < 0.000001:
		return {}
	actual_up = actual_up.normalized()
	return {
		"operator_deg": _signed_roll_degrees(
			direction,
			actual_up,
			skeleton.global_basis.y.normalized()
		),
		"world_deg": _signed_roll_degrees(direction, actual_up, Vector3.UP),
	}


func _signed_roll_degrees(
	direction: Vector3,
	actual_up: Vector3,
	reference_up: Vector3
) -> float:
	var projected_reference := reference_up - direction * reference_up.dot(direction)
	if projected_reference.length_squared() < 0.000001:
		return 0.0
	projected_reference = projected_reference.normalized()
	return rad_to_deg(atan2(
		direction.dot(projected_reference.cross(actual_up)),
		projected_reference.dot(actual_up)
	))


func _write_contact_sheets() -> void:
	for group in ["pistols", "rifles", "smgs"]:
		var group_cases: Array[Dictionary] = []
		for case_value in CASES:
			var weapon_case := case_value as Dictionary
			if String(weapon_case.get("group", "")) == group:
				group_cases.append(weapon_case)
		var sheet := Image.create_empty(
			CELL_SIZE.x * STATES.size(),
			CELL_SIZE.y * group_cases.size(),
			false,
			Image.FORMAT_RGBA8
		)
		sheet.fill(Color(0.025, 0.03, 0.04, 1.0))
		for row in group_cases.size():
			var weapon_id := String(group_cases[row].get("id", ""))
			for column in STATES.size():
				var key := "%s|%s" % [weapon_id, STATES[column]]
				var thumbnail := thumbnails.get(key) as Image
				if thumbnail == null:
					continue
				sheet.blit_rect(
					thumbnail,
					Rect2i(Vector2i.ZERO, CELL_SIZE),
					Vector2i(column * CELL_SIZE.x, row * CELL_SIZE.y)
				)
		var path := "%s/%s-contact-sheet.png" % [OUTPUT_DIR, group]
		_expect(
			sheet.save_png(path) == OK,
			"%s contact sheet saves" % group
		)
	var rear_sheet := Image.create_empty(
		CELL_SIZE.x * 2,
		CELL_SIZE.y * REAR_CASES.size(),
		false,
		Image.FORMAT_RGBA8
	)
	rear_sheet.fill(Color(0.025, 0.03, 0.04, 1.0))
	for row in REAR_CASES.size():
		for column in 2:
			var state_name := (
				"standing_recovery" if column == 0 else "crouched_recovery"
			)
			var key := "%s|%s" % [REAR_CASES[row], state_name]
			var thumbnail := rear_thumbnails.get(key) as Image
			if thumbnail == null:
				continue
			rear_sheet.blit_rect(
				thumbnail,
				Rect2i(Vector2i.ZERO, CELL_SIZE),
				Vector2i(column * CELL_SIZE.x, row * CELL_SIZE.y)
			)
	var rear_path := "%s/recovery-shoulders-rear-contact-sheet.png" % OUTPUT_DIR
	_expect(
		rear_sheet.save_png(rear_path) == OK,
		"representative rear shoulder contact sheet saves"
	)


func _write_manifest() -> void:
	var manifest := {
		"canonical_scene": "res://main.tscn",
		"equipment_handoff": "SocomWeaponController.apply_authorized_weapon_pickup",
		"presentation_consumer": "SocomOperatorAnimationDriver",
		"weapon_count": CASES.size(),
		"states_per_weapon": STATES.size(),
		"side_capture_count": thumbnails.size(),
		"rear_capture_count": rear_thumbnails.size(),
		"metrics": metric_rows,
	}
	var path := "%s/manifest.json" % OUTPUT_DIR
	var file := FileAccess.open(path, FileAccess.WRITE)
	_expect(file != null, "visual proof manifest opens for writing")
	if file != null:
		file.store_string(JSON.stringify(manifest, "  "))
		file.close()


func _await_ballistics_ready(controller: Node) -> void:
	var ballistics = controller.get("ballistics")
	for _index in 240:
		if ballistics == null or float(ballistics.get("fire_cooldown")) <= 0.0:
			return
		await process_frame
		await physics_frame


func _hide_canvas_layers(node: Node) -> void:
	if node is CanvasLayer:
		(node as CanvasLayer).visible = false
	for child in node.get_children():
		_hide_canvas_layers(child)


func _capture(path: String) -> Image:
	RenderingServer.force_draw()
	await process_frame
	var image := root.get_texture().get_image()
	if image == null or image.is_empty() or image.save_png(path) != OK:
		return null
	return image


func _steps(count: int) -> void:
	for _index in count:
		await process_frame
		await physics_frame


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("FIREARM_FAMILY_VISUAL_PROOF PASS %s" % label)
		return
	failures.append(label)
	push_error("FIREARM_FAMILY_VISUAL_PROOF FAIL %s" % label)


func _finish() -> void:
	if failures.is_empty():
		print(
			"FIREARM_FAMILY_VISUAL_PROOF PASS weapons=%d states=%d output=%s"
			% [CASES.size(), STATES.size(), OUTPUT_DIR]
		)
		quit(0)
		return
	print("FIREARM_FAMILY_VISUAL_PROOF FAIL %s" % [failures])
	quit(1)
