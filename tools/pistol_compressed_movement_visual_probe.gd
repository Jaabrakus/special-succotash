extends "res://tools/pistol_compressed_idle_regression.gd"

## Read-only canonical transition measurements. Default runs are diagnostic,
## not a pass claim for movement appearance or an alternate runtime solver.
## --fixed-fps 60 --script <this script> -- --enforce [--rapid-reversals]
## enforces only firing boundaries; ordinary locomotion remains diagnostic.
const PROBE_REFERENCE_DELTA := 1.0 / 60.0
const PROBE_MAX_UPPER_STEP_M := 0.035
const PROBE_MAX_UPPER_STEP_DEG := 6.0

var probe_output := "/private/tmp/socom-pistol-forward-movement-continuity"
var custom_output_prefix := ""
var probe_direction := Vector2(0.0, 1.0)
var baseline_profile_path := ""
var enforce_boundaries := false
var rapid_reversals := false
var probe_report: Dictionary = {"phases": []}

func _run() -> void:
	Engine.max_fps = 60
	capture_enabled = "--capture" in OS.get_cmdline_user_args()
	enforce_boundaries = "--enforce" in OS.get_cmdline_user_args()
	rapid_reversals = "--rapid-reversals" in OS.get_cmdline_user_args()
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--baseline-profile="):
			baseline_profile_path = argument.trim_prefix("--baseline-profile=")
		elif argument.begins_with("--output-prefix="):
			custom_output_prefix = argument.trim_prefix("--output-prefix=")
		elif argument == "--backward":
			probe_direction = Vector2(0.0, -1.0)
	probe_output = "/private/tmp/socom-pistol-%s-%s-continuity" % ["backward" if probe_direction.y < 0.0 else "forward", "baseline-profile" if not baseline_profile_path.is_empty() else "candidate"]
	if not custom_output_prefix.is_empty():
		probe_output = custom_output_prefix
	probe_report["movement_direction"] = [probe_direction.x, probe_direction.y]
	probe_report["profile_source"] = baseline_profile_path if not baseline_profile_path.is_empty() else MARK_23_PATH
	probe_report["baseline_scope"] = "driver handling + graph only; solver runtime/config unchanged" if not baseline_profile_path.is_empty() else "canonical saved candidate"
	probe_report["enforcement"] = {
		"enabled": enforce_boundaries,
		"scope": "ready_to_move, moving_recovery_to_stop, optional ready_rapid_reversals only",
		"ordinary_locomotion": "diagnostic only; does not claim ordinary crouch movement is fixed",
		"max_60hz_equivalent_step_m": PROBE_MAX_UPPER_STEP_M,
		"max_60hz_equivalent_step_deg": PROBE_MAX_UPPER_STEP_DEG,
		"max_contact_error_m": MAX_CONTACT_ERROR_M,
		"requires_fixed_fps": 60,
	}
	probe_report["rapid_reversals"] = rapid_reversals
	if capture_enabled and DisplayServer.get_name() == "headless":
		push_error("Movement capture requires a display-backed run")
		quit(1)
		return
	active_scene = (load("res://main.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(active_scene)
	await _frames(60)
	var player := active_scene.get_node("Player") as CharacterBody3D
	var controller := active_scene.get_node("WeaponController")
	var mannequin := player.get_node("Mannequin")
	var driver := mannequin.get("production_animation") as Node
	_expect(bool(controller.call("apply_authorized_weapon_pickup", MARK_23_PATH)), "canonical Mark23 equips")
	await _frames(24)
	if not baseline_profile_path.is_empty():
		var baseline: Variant = JSON.parse_string(FileAccess.get_file_as_string(baseline_profile_path))
		if not baseline is Dictionary or not (baseline as Dictionary).get("handling_profile") is Dictionary:
			push_error("Baseline profile missing handling_profile: " + baseline_profile_path)
			quit(1)
			return
		driver.set("equipped_weapon_handling_profile", ((baseline as Dictionary)["handling_profile"] as Dictionary).duplicate(true))
		driver.call("_build_animation_tree")
		await _frames(24)
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
		review_camera.fov = 36.0
		review_camera.set_cull_mask_value(20, false)
		active_scene.add_child(review_camera)
		review_camera.make_current()
		RenderingServer.frame_pre_draw.connect(_own_probe_camera)
	for posture_index in [0, 1]:
		var posture := &"STANDING" if posture_index == 0 else &"CROUCHED"
		driver.call("clear_fire_ready_aim")
		_expect(bool(player.call("_try_set_posture", posture_index)), String(posture) + " canonical posture")
		var target := player.global_position + Vector3.UP * (1.48 if posture_index == 0 else 1.20) + _world_aim_direction(player, 0.0, 0.0) * 25.0
		_set_probe_movement(driver, posture, target, false)
		await _frames(60)
		if capture_enabled:
			_aim_review_camera(review_camera, driver, player)
			await _frames(3)
		await _probe_phase(driver, posture, target, "idle_to_move", true, 36)
		await _probe_phase(driver, posture, target, "moving_to_stop", false, 60)
		await _frames(48)
		await _await_ballistics_ready(controller)
		var shot: Dictionary = controller.call("request_fire")
		_expect(bool(shot.get("fired", false)), String(posture) + " stationary shot accepted")
		await _frames(12)
		await _probe_phase(driver, posture, target, "ready_to_move", true, 24, true)
		await _probe_phase(driver, posture, target, "moving_recovery_to_stop", false, 72, true)
		await _frames(90)
		if rapid_reversals:
			await _await_ballistics_ready(controller)
			var rapid_shot: Dictionary = controller.call("request_fire")
			_expect(bool(rapid_shot.get("fired", false)), String(posture) + " rapid reversal shot accepted")
			await _frames(12)
			await _probe_phase(driver, posture, target, "ready_rapid_reversals", true, 96, true, true)
			await _frames(90)
	if capture_enabled:
		RenderingServer.frame_pre_draw.disconnect(_own_probe_camera)
	var report_path := probe_output + ("-rendered.json" if capture_enabled else "-headless.json")
	probe_report["result"] = ("PASS_FIRING_BOUNDARIES_ONLY" if failures.is_empty() else "FAIL") if enforce_boundaries else "DIAGNOSTIC_ONLY"
	probe_report["failures"] = failures
	var file := FileAccess.open(report_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(probe_report, "\t") + "\n")
	file.close()
	print("PISTOL_MOVEMENT_CONTINUITY_REPORT " + report_path)
	if enforce_boundaries:
		print("PISTOL_MOVEMENT_CONTINUITY_ENFORCEMENT %s scope=firing_boundaries_only failures=%d" % ["PASS" if failures.is_empty() else "FAIL", failures.size()])
	else:
		print("PISTOL_MOVEMENT_CONTINUITY DIAGNOSTIC_ONLY no_movement_acceptance_claim")
	active_scene.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

func _probe_phase(driver: Node, posture: StringName, target: Vector3, phase: String, moving: bool, frames: int, firing_boundary: bool = false, rapid: bool = false) -> void:
	var previous := _compressed_sample(driver)
	var entries: Array[Dictionary] = []
	var captures: Array[Dictionary] = []
	var largest := {"position_m": 0.0, "angle_deg": 0.0, "position_frame": -1, "position_bone": "", "angle_frame": -1, "angle_bone": ""}
	var largest_60hz := {"position_m": 0.0, "angle_deg": 0.0, "position_frame": -1, "position_bone": "", "angle_frame": -1, "angle_bone": ""}
	var max_contact_m := 0.0
	var max_delta_error := 0.0
	var initial_ready_weight := float(driver.get("weapon_ready_weight"))
	var input_direction := probe_direction if moving else Vector2.ZERO
	_set_probe_movement(driver, posture, target, moving)
	for frame in frames:
		if rapid:
			# Interrupt source crossfades after four frames, including a direct
			# forward/backward reversal. Then observe the entire recovery exit.
			var sequence: Array[Vector2] = [probe_direction, Vector2.ZERO, -probe_direction, probe_direction, Vector2.ZERO, probe_direction, Vector2.ZERO]
			input_direction = sequence[mini(frame / 4, sequence.size() - 1)]
			_set_probe_movement(driver, posture, target, not input_direction.is_zero_approx(), input_direction)
		await _frames(1)
		var current := _compressed_sample(driver)
		var delta_seconds := driver.get_process_delta_time()
		var scale_60hz := PROBE_REFERENCE_DELTA / maxf(delta_seconds, 0.000001)
		max_delta_error = maxf(max_delta_error, absf(delta_seconds - PROBE_REFERENCE_DELTA))
		max_contact_m = maxf(max_contact_m, maxf(float(current["trigger_error_m"]), float(current["support_error_m"])))
		var entry := {
			"frame": frame,
			"delta_seconds": delta_seconds,
			"input_direction": [input_direction.x, input_direction.y],
			"authored_idle_baseline": driver.call("_uses_authored_compressed_idle"),
			"clean_weight": driver.get("_clean_fire_recovery_weight"),
			"ready_weight": driver.get("weapon_ready_weight"),
			"current_clip": driver.get("current_clip"),
			"requested_action": driver.get("requested_action"),
			"graph_state": (driver.get("locomotion_graph") as RefCounted).get("current_state"),
			"bones": {},
			"trigger_error_m": current["trigger_error_m"],
			"support_error_m": current["support_error_m"],
		}
		for bone in ["Head", "LeftShoulder", "RightShoulder", "Spine2"]:
			var a: Transform3D = previous[bone]
			var b: Transform3D = current[bone]
			var step_m := a.origin.distance_to(b.origin)
			var step_deg := rad_to_deg(a.basis.orthonormalized().get_rotation_quaternion().angle_to(b.basis.orthonormalized().get_rotation_quaternion()))
			entry["bones"][bone] = {"step_m": step_m, "step_deg": step_deg, "step_60hz_m": step_m * scale_60hz, "step_60hz_deg": step_deg * scale_60hz, "position": [b.origin.x, b.origin.y, b.origin.z]}
			if step_m > float(largest["position_m"]):
				largest["position_m"] = step_m
				largest["position_frame"] = frame
				largest["position_bone"] = bone
			if step_deg > float(largest["angle_deg"]):
				largest["angle_deg"] = step_deg
				largest["angle_frame"] = frame
				largest["angle_bone"] = bone
			if step_m * scale_60hz > float(largest_60hz["position_m"]):
				largest_60hz["position_m"] = step_m * scale_60hz
				largest_60hz["position_frame"] = frame
				largest_60hz["position_bone"] = bone
			if step_deg * scale_60hz > float(largest_60hz["angle_deg"]):
				largest_60hz["angle_deg"] = step_deg * scale_60hz
				largest_60hz["angle_frame"] = frame
				largest_60hz["angle_bone"] = bone
		entries.append(entry)
		if capture_enabled and frame in [0, 1, 2, 3, 5, 8, 9, 10, 12, 18, 24, 35, 47, 59, 71]:
			captures.append({"frame": frame, "image": root.get_texture().get_image()})
		previous = current
	var result := {"posture": posture, "phase": phase, "max": largest, "max_60hz_equivalent": largest_60hz, "max_contact_error_m": max_contact_m, "max_fixed_delta_error_seconds": max_delta_error, "firing_boundary": firing_boundary, "enforced": enforce_boundaries and firing_boundary, "frames": entries}
	probe_report["phases"].append(result)
	print("PISTOL_MOVEMENT_CONTINUITY " + String(posture) + " " + phase + " " + JSON.stringify(largest) + " max_contact_m=" + str(max_contact_m))
	if enforce_boundaries and firing_boundary:
		var label := String(posture) + " " + phase
		_expect(initial_ready_weight > 0.5, label + " starts during actual accepted-shot recovery")
		_expect(max_delta_error <= 0.00001, label + " measured fixed 60 Hz presentation deltas (run Godot with --fixed-fps 60)")
		_expect(float(largest_60hz["position_m"]) <= PROBE_MAX_UPPER_STEP_M and float(largest_60hz["angle_deg"]) <= PROBE_MAX_UPPER_STEP_DEG,
			label + " upper body stays within 3.5 cm / 6 degrees per 60 Hz-equivalent frame")
		_expect(max_contact_m <= MAX_CONTACT_ERROR_M, label + " both gun contacts stay within 1 cm")
	for capture in captures:
		var path := "%s-%s-%s-f%03d.png" % [probe_output, String(posture).to_lower(), phase, int(capture["frame"])]
		(capture["image"] as Image).save_png(path)
	# Save only after the measured sequence; do not let encoding become a sample.
	if not captures.is_empty():
		await _frames(4)

func _set_probe_movement(driver: Node, posture: StringName, target: Vector3, moving: bool, direction: Vector2 = Vector2.ZERO) -> void:
	var input_direction := (probe_direction if direction.is_zero_approx() else direction) if moving else Vector2.ZERO
	driver.call("set_visual_inputs", input_direction, posture, 0.0, 0.0, 0.0, false, 0.0,
		1.0 if moving else 0.0, &"LOCOMOTION", 0.0, &"WALK", 4.0 if moving else 0.0, target,
		input_direction, 1.0 if moving else 0.0, &"MOVING" if moving else &"IDLE", 0.0)

func _own_probe_camera() -> void:
	if is_instance_valid(review_camera):
		review_camera.make_current()
