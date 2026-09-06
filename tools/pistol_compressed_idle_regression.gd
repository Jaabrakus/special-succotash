extends "res://tools/pistol_recovery_exit_regression.gd"

## Canonical acceptance proof: same forward, two-hand pistol shape, compressed
## toward the chest in idle; extend on accepted shot, hold 1.2 s, then retract.
## No candidate injection or alternate runtime: saved Mark 23 is equipped by the
## normal authorized handoff. Bone global poses are explicitly converted from
## skeleton space to world space before comparison with physical weapon sockets.

const COMPRESSED_CAPTURE_PREFIX := "/private/tmp/socom-pistol-compressed"
const MAX_CONTACT_ERROR_M := 0.01
const MAX_CHEST_LATERAL_M := 0.08
const MIN_COMPRESSION_M := 0.05
const MAX_UPPER_BODY_STEP_M := 0.02
const MAX_UPPER_BODY_STEP_DEG := 5.0

var capture_enabled: bool = false
var review_camera: Camera3D
var active_scene: Node3D


func _run() -> void:
	Engine.max_fps = 60
	capture_enabled = "--capture" in OS.get_cmdline_user_args()
	if capture_enabled and DisplayServer.get_name() == "headless":
		_expect(false, "--capture needs a display-backed run")
		_finish()
		return
	active_scene = (load("res://main.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(active_scene)
	await _frames(60)
	var player := active_scene.get_node("Player") as CharacterBody3D
	var controller := active_scene.get_node("WeaponController")
	var mannequin := player.get_node("Mannequin")
	var driver := mannequin.get("production_animation") as Node
	_expect(bool(controller.call("apply_authorized_weapon_pickup", MARK_23_PATH)), "canonical Mark 23 equips")
	await _frames(30)
	player.set_physics_process(false)
	mannequin.set_process(false)
	if capture_enabled:
		_hide_canvas_layers(active_scene)
		var debug_visualizer := active_scene.find_child("CameraBoomVisualizer", true, false) as Node3D
		if debug_visualizer != null:
			debug_visualizer.visible = false
		if mannequin.has_method("set_proxy_visuals_visible"):
			mannequin.call("set_proxy_visuals_visible", false)
		review_camera = Camera3D.new()
		review_camera.fov = 38.0
		review_camera.set_cull_mask_value(20, false)
		active_scene.add_child(review_camera)
		review_camera.make_current()
	for posture_index in [0, 1]:
		for offset in [Vector2.ZERO, Vector2(AIM_YAW_RAD, AIM_PITCH_RAD)]:
			await _check_compressed_cycle(player, controller, driver, posture_index, offset)
		await _check_reload_owner(player, controller, driver, posture_index)
	active_scene.queue_free()
	await process_frame
	_finish()


func _check_compressed_cycle(player: CharacterBody3D, controller: Node, driver: Node, posture_index: int, aim: Vector2) -> void:
	var posture := &"STANDING" if posture_index == 0 else &"CROUCHED"
	var label := "%s_yaw%d_pitch%d" % [posture, roundi(rad_to_deg(aim.x)), roundi(rad_to_deg(aim.y))]
	driver.call("clear_fire_ready_aim")
	_expect(bool(player.call("_try_set_posture", posture_index)), "%s canonical posture" % label)
	var target := player.global_position + Vector3.UP * (1.48 if posture_index == 0 else 1.20) + _world_aim_direction(player, aim.x, aim.y) * 25.0
	driver.call("set_visual_inputs", Vector2.ZERO, posture, aim.x, aim.y, 0.0, false, 0.0,
		0.0, &"LOCOMOTION", 0.0, &"WALK", 0.0, target, Vector2.ZERO, 0.0, &"IDLE", 0.0)
	await _frames(48)
	await _await_ballistics_ready(controller)
	var profile: Dictionary = driver.get("equipped_weapon_handling_profile")
	var slots: Dictionary = profile.get("animation_slots", {})
	var suffix := "standing" if posture_index == 0 else "crouched"
	var idle_clip := StringName(slots.get("idle_" + suffix, ""))
	var ready_clip := StringName(slots.get("ready_" + suffix, ""))
	_expect(not idle_clip.is_empty() and not ready_clip.is_empty() and idle_clip != ready_clip,
		"%s saved idle and ready slots are distinct" % label)
	var idle := _compressed_sample(driver)
	_report_sample(label, "idle", idle)
	_expect_contacts(idle, "%s idle" % label)
	_expect(absf(float(idle["chest_lateral_m"])) <= MAX_CHEST_LATERAL_M,
		"%s idle hands centered within 8 cm of chest midline" % label)
	_expect(float(idle["bore_up_deg"]) <= 25.0 and float(idle["bore_forward_deg"]) <= 30.0,
		"%s idle muzzle points forward, not up beside the face" % label)
	_expect(StringName(driver.call("_select_visual_clip")) == idle_clip and float(driver.get("weapon_ready_weight")) <= 0.0,
		"%s is genuinely idle before firing" % label)
	if aim == Vector2.ZERO:
		await _capture_pair(driver, player, label, "idle")
	# PNG encoding is synchronous. Sample the actual stable frame after capture
	# settling, not the older pose from before the image-write stall.
	idle = _compressed_sample(driver)
	var graph := driver.get("locomotion_graph") as RefCounted
	var fire_count := int(graph.get("fire_trigger_count"))
	var shot: Dictionary = controller.call("request_fire")
	_expect(bool(shot.get("fired", false)), "%s canonical shot accepted" % label)
	var latch: Dictionary = (driver.call("get_animation_debug_state") as Dictionary).get("fire_upper_body_latch", {})
	_expect(is_equal_approx(float(latch.get("grace_duration_seconds", -1.0)), 1.2)
		and is_equal_approx(float(latch.get("grace_remaining_seconds", -1.0)), 1.2),
		"%s accepted shot starts unchanged 1.2 second hold" % label)
	await _frames(1)
	var first := _compressed_sample(driver)
	_report_sample(label, "first_fire_frame", first)
	_expect_contacts(first, "%s first rendered shot" % label)
	var first_geometry := _measure_pistol_geometry(driver, target)
	_expect(float(first_geometry["bore_error_deg"]) <= 1.0 and absf(float(first_geometry["axial_roll_deg"])) <= 6.0,
		"%s first rendered shot bore follows reticle upright" % label)
	var upper_steps := _upper_body_steps(idle, first)
	var ready := first
	var max_entry_contact := maxf(float(first["trigger_error_m"]), float(first["support_error_m"]))
	var max_entry_bore := float(first_geometry["bore_error_deg"])
	var max_entry_roll := absf(float(first_geometry["axial_roll_deg"]))
	for entry_frame in range(2, 9):
		await _frames(1)
		var entry_sample := _compressed_sample(driver)
		var steps := _upper_body_steps(ready, entry_sample)
		upper_steps["distance_m"] = maxf(float(upper_steps["distance_m"]), float(steps["distance_m"]))
		upper_steps["angle_deg"] = maxf(float(upper_steps["angle_deg"]), float(steps["angle_deg"]))
		max_entry_contact = maxf(max_entry_contact, maxf(float(entry_sample["trigger_error_m"]), float(entry_sample["support_error_m"])))
		var entry_geometry := _measure_pistol_geometry(driver, target)
		max_entry_bore = maxf(max_entry_bore, float(entry_geometry["bore_error_deg"]))
		max_entry_roll = maxf(max_entry_roll, absf(float(entry_geometry["axial_roll_deg"])))
		_report_sample(label, "entry_frame_%d" % entry_frame, entry_sample)
		ready = entry_sample
	_expect(max_entry_contact <= MAX_CONTACT_ERROR_M, "%s palms stay attached on every entry frame 1-8" % label)
	_expect(max_entry_bore <= 1.0 and max_entry_roll <= 6.0,
		"%s every entry frame 1-8 keeps reticle aim and upright bore" % label)
	_report_sample(label, "ready", ready)
	_expect_contacts(ready, "%s ready" % label)
	_expect(float(ready["chest_distance_m"]) - float(idle["chest_distance_m"]) >= MIN_COMPRESSION_M,
		"%s idle hands are at least 5 cm closer to chest than ready" % label)
	# Idle is chest-forward, not a second camera-aim owner. An offset reticle
	# legitimately changes ready bore direction by the requested yaw/pitch.
	if aim == Vector2.ZERO:
		_expect(rad_to_deg(Vector3(idle["bore"]).angle_to(Vector3(ready["bore"]))) <= 15.0,
			"%s neutral idle and ready retain the same forward muzzle orientation" % label)
	var ready_geometry := _measure_pistol_geometry(driver, target)
	_expect(float(ready_geometry["bore_error_deg"]) <= 1.0 and absf(float(ready_geometry["axial_roll_deg"])) <= 6.0,
		"%s ready bore independently follows camera reticle upright" % label)
	_expect(StringName(driver.call("_select_visual_clip")) == ready_clip,
		"%s accepted shot selects shared ready slot" % label)
	if aim == Vector2.ZERO:
		await _capture_pair(driver, player, label, "ready")
	var previous := _compressed_sample(driver)
	var previous_weight := float(driver.get("weapon_ready_weight"))
	var max_exit_contact := 0.0
	var terminal_palm_step := 0.0
	var settled_frames := 0
	var observed_recovery := false
	for _frame in range(240):
		await _frames(1)
		var current := _compressed_sample(driver)
		var debug: Dictionary = driver.call("get_animation_debug_state")
		var current_latch: Dictionary = debug.get("fire_upper_body_latch", {})
		var weight := float(debug.get("weapon_ready_weight", 0.0))
		observed_recovery = observed_recovery or String(current_latch.get("owner_state", "")) == "FIRE_RECOVERY"
		var steps := _upper_body_steps(previous, current)
		upper_steps["distance_m"] = maxf(float(upper_steps["distance_m"]), float(steps["distance_m"]))
		upper_steps["angle_deg"] = maxf(float(upper_steps["angle_deg"]), float(steps["angle_deg"]))
		max_exit_contact = maxf(max_exit_contact, maxf(float(current["trigger_error_m"]), float(current["support_error_m"])))
		if previous_weight <= TERMINAL_READY_WEIGHT:
			terminal_palm_step = maxf(terminal_palm_step, maxf(Vector3(previous["right_palm"]).distance_to(current["right_palm"]), Vector3(previous["left_palm"]).distance_to(current["left_palm"])))
		settled_frames = settled_frames + 1 if weight <= 0.0 else 0
		previous = current
		previous_weight = weight
		if settled_frames >= 5:
			break
	_report_sample(label, "returned_idle", previous)
	print("PISTOL_COMPRESSED_IDLE_CONTINUITY %s upper_step_m=%.6f upper_step_deg=%.3f entry_contact_m=%.6f exit_contact_m=%.6f terminal_palm_step_m=%.6f" % [label, upper_steps["distance_m"], upper_steps["angle_deg"], max_entry_contact, max_exit_contact, terminal_palm_step])
	_expect(observed_recovery and settled_frames >= 5 and StringName(driver.call("_select_visual_clip")) == idle_clip,
		"%s full hold completes and returns to idle" % label)
	_expect(max_exit_contact <= MAX_CONTACT_ERROR_M, "%s palms remain attached throughout recovery exit" % label)
	_expect(terminal_palm_step <= MAX_TERMINAL_PALM_STEP_M, "%s terminal idle handoff has no palm pop" % label)
	_expect(float(upper_steps["distance_m"]) <= MAX_UPPER_BODY_STEP_M and float(upper_steps["angle_deg"]) <= MAX_UPPER_BODY_STEP_DEG,
		"%s head and shoulder motion is continuous across entry and exit" % label)
	_expect(Vector3(previous["right_palm_chest"]).distance_to(idle["right_palm_chest"]) <= 0.025
		and Vector3(previous["left_palm_chest"]).distance_to(idle["left_palm_chest"]) <= 0.025,
		"%s returns to original compressed idle hand positions" % label)
	_expect(int(graph.get("fire_trigger_count")) == fire_count and String(graph.get("active_fire_clip")).is_empty(),
		"%s never launches a fire OneShot" % label)
	_expect_same_dimensions(idle, previous, label)
	if aim == Vector2.ZERO:
		await _capture_pair(driver, player, label, "returned_idle")


func _check_reload_owner(player: CharacterBody3D, controller: Node, driver: Node, posture_index: int) -> void:
	var label := "STANDING" if posture_index == 0 else "CROUCHED"
	var coordinator := active_scene.get_node("WeaponReloadCoordinator")
	_expect(bool(coordinator.call("request_reload")), "%s reload remains accepted by existing coordinator" % label)
	await _frames(12)
	var debug: Dictionary = driver.call("get_animation_debug_state")
	var pose: Dictionary = debug.get("weapon_pose", {})
	print("PISTOL_COMPRESSED_IDLE_RELOAD %s pending=%s action=%s weapon_owner=%s" % [label, coordinator.get("pending"), driver.get("requested_action"), pose.get("weapon_owner", "")])
	_expect(bool(coordinator.get("pending")) and "reload" in String(driver.get("requested_action")).to_lower()
		and String(pose.get("weapon_owner", "")) == "RELOAD_RIGHT_HAND",
		"%s reload owns the pose instead of compressed idle" % label)
	for _frame in range(420):
		if not bool(coordinator.get("pending")):
			break
		await _frames(1)
	await _frames(48)
	_expect(not bool(coordinator.get("pending")), "%s reload completes normally" % label)
	_expect_contacts(_compressed_sample(driver), "%s post-reload idle" % label)
	var ammo: Dictionary = controller.call("get_ammo_snapshot")
	_expect(int(ammo.get("rounds_in_magazine", 0)) > 0, "%s reload keeps gameplay ammo commit" % label)


func _compressed_sample(driver: Node) -> Dictionary:
	var sample := _exit_sample(driver)
	var skeleton := driver.get("skeleton") as Skeleton3D
	for name in ["LeftShoulder", "RightShoulder", "Head", "Spine2", "Neck"]:
		sample[name] = skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone("mixamorig_" + name))
	var chest: Vector3 = (sample["Spine2"] as Transform3D).origin
	var right := ((sample["RightShoulder"] as Transform3D).origin - (sample["LeftShoulder"] as Transform3D).origin).normalized()
	var up := ((sample["Neck"] as Transform3D).origin - chest).normalized()
	var forward := up.cross(right).normalized()
	for side in ["right", "left"]:
		var relative: Vector3 = Vector3(sample[side + "_palm"]) - chest
		sample[side + "_palm_chest"] = Vector3(relative.dot(right), relative.dot(up), relative.dot(forward))
	var palms := (Vector3(sample["right_palm"]) + Vector3(sample["left_palm"])) * 0.5
	var solver := driver.get("weapon_pose_solver") as Node
	var barrel := (solver.get("barrel_base_socket") as Marker3D).global_position
	var bore := barrel.direction_to(sample["muzzle"])
	sample["bore"] = bore
	sample["chest_lateral_m"] = (palms - chest).dot(right)
	sample["chest_distance_m"] = palms.distance_to(chest)
	sample["bore_up_deg"] = rad_to_deg(asin(clampf(bore.dot(Vector3.UP), -1.0, 1.0)))
	sample["bore_forward_deg"] = rad_to_deg(bore.angle_to(forward))
	return sample


func _upper_body_steps(previous: Dictionary, current: Dictionary) -> Dictionary:
	var distance := 0.0
	var angle := 0.0
	for name in ["LeftShoulder", "RightShoulder", "Head", "Spine2"]:
		var a: Transform3D = previous[name]
		var b: Transform3D = current[name]
		distance = maxf(distance, a.origin.distance_to(b.origin))
		angle = maxf(angle, rad_to_deg(a.basis.orthonormalized().get_rotation_quaternion().angle_to(b.basis.orthonormalized().get_rotation_quaternion())))
	return {"distance_m": distance, "angle_deg": angle}


func _expect_contacts(sample: Dictionary, label: String) -> void:
	_expect(float(sample["trigger_error_m"]) <= MAX_CONTACT_ERROR_M and float(sample["support_error_m"]) <= MAX_CONTACT_ERROR_M,
		"%s physical palms match gun contacts within 1 cm" % label)


func _report_sample(label: String, phase: String, sample: Dictionary) -> void:
	print("PISTOL_COMPRESSED_IDLE_METRIC %s phase=%s chest_lateral_m=%.5f chest_distance_m=%.5f bore_up_deg=%.3f bore_forward_deg=%.3f trigger_m=%.6f support_m=%.6f" % [label, phase, sample["chest_lateral_m"], sample["chest_distance_m"], sample["bore_up_deg"], sample["bore_forward_deg"], sample["trigger_error_m"], sample["support_error_m"]])


func _capture_pair(driver: Node, player: CharacterBody3D, label: String, phase: String) -> void:
	if not capture_enabled:
		return
	_aim_review_camera(review_camera, driver, player)
	_expect(await _capture("%s-%s-%s-side.png" % [COMPRESSED_CAPTURE_PREFIX, label.to_lower(), phase]), "saves %s %s side" % [label, phase])
	_aim_rear_camera(review_camera, driver, player)
	_expect(await _capture("%s-%s-%s-rear.png" % [COMPRESSED_CAPTURE_PREFIX, label.to_lower(), phase]), "saves %s %s rear" % [label, phase])
	# File encoding must not become the next measured animation delta. Drain
	# ordinary presented frames before a shot or another measured transition.
	await _frames(4)


func _capture(path: String) -> bool:
	# The previous helper force-drew and read back before the next frame was
	# presented, producing a stale camera view. Own only the review camera at
	# pre-draw, after gameplay camera updates, then read that completed draw.
	await process_frame
	await RenderingServer.frame_pre_draw
	review_camera.make_current()
	await RenderingServer.frame_post_draw
	var rendered := root.get_texture().get_image()
	return rendered != null and not rendered.is_empty() and rendered.save_png(path) == OK


func _frames(count: int) -> void:
	for _frame in count:
		await process_frame
		if DisplayServer.get_name() == "headless":
			# process_frame alone is before Node._process. SceneTreeTimer runs
			# after every node, so this measures the completed presentation frame.
			# https://docs.godotengine.org/en/latest/classes/class_scenetree.html#class-scenetree-method-create-timer
			await create_timer(0.0).timeout
		else:
			await RenderingServer.frame_post_draw


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("PISTOL_COMPRESSED_IDLE_CHECK PASS %s" % label)
	else:
		failures.append(label)
		push_error("PISTOL_COMPRESSED_IDLE_CHECK FAIL %s" % label)


func _finish() -> void:
	if failures.is_empty():
		print("PISTOL_COMPRESSED_IDLE_REGRESSION PASS cases=4 reloads=2")
		quit(0)
	else:
		print("PISTOL_COMPRESSED_IDLE_REGRESSION FAIL %s" % [failures])
		quit(1)
