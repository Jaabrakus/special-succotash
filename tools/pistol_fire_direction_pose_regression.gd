extends SceneTree

## Input-tagged canonical proof for the two-hand pistol firing frame. It measures
## rendered skeleton/socket geometry directly; cached debug zeros are not proof.

const WEAPON_PATHS: Array[String] = [
	"res://config/weapons/226.json",
	"res://config/weapons/9mm_pistol.json",
	"res://config/weapons/de__50.json",
	"res://config/weapons/mark_23.json",
	"res://config/weapons/mark_23sd.json",
	"res://config/weapons/m9.json",
	"res://config/weapons/model_18.json",
	"res://config/weapons/f57.json",
]
const DIRECTION_CASES: Array[Dictionary] = [
	{"label": "IDLE", "direction": Vector2.ZERO, "speed": 0.0},
	# Canonical visual input is (local_velocity.x, -local_velocity.z): forward
	# therefore has positive Y. Retain backward cases under their actual labels.
	{"label": "WA", "direction": Vector2(-0.70710678, 0.70710678), "speed": 1.0},
	{"label": "WD", "direction": Vector2(0.70710678, 0.70710678), "speed": 1.0},
	{"label": "SA", "direction": Vector2(-0.70710678, -0.70710678), "speed": 1.0},
	{"label": "SD", "direction": Vector2(0.70710678, -0.70710678), "speed": 1.0},
]
const POSTURE_CASES: Array[Dictionary] = [
	{"index": 0, "name": &"STANDING", "height": 1.48},
	{"index": 1, "name": &"CROUCHED", "height": 1.20},
]
const MAX_BORE_ERROR_DEG := 1.0
const MAX_SHOULDER_SQUARE_ERROR_DEG := 10.0
const MAX_SHOULDER_LEVEL_ERROR_CM := 4.0
const MAX_AXIAL_ROLL_DEG := 6.0
const MAX_HAND_ERROR_M := 0.01
const MAX_CENTERLINE_OFFSET_RATIO := 0.20
const MAX_LEFT_CROSS_RATIO := 0.10
const MIN_ELBOW_ANGLE_DEG := 38.0
const MAX_ELBOW_ANGLE_DEG := 155.0
const TRANSITION_SAMPLE_FRAMES: Array[int] = [1, 2, 4, 8, 12, 18]
const AIM_YAW_RAD := deg_to_rad(18.0)
const AIM_PITCH_RAD := deg_to_rad(8.0)

var failures: Array[String] = []
var checked_cases := 0
var candidate_loader: RefCounted
var test_aim_ready := false


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_verify_directional_contract()
	var packed := load("res://main.tscn") as PackedScene
	_expect(packed != null, "canonical res://main.tscn loads")
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
		player != null and controller != null and mannequin != null and driver != null,
		"canonical movement, weapon, mannequin, and animation owners are ready"
	)
	if player == null or controller == null or mannequin == null or driver == null:
		scene.queue_free()
		_finish()
		return
	player.set_physics_process(false)
	if "--no-recoil" in OS.get_cmdline_user_args():
		driver.weapon_pose_solver.fire_recoil.flare = 0.0
	mannequin.set_process(false)
	var weapon_paths := WEAPON_PATHS
	var posture_cases := POSTURE_CASES
	var direction_cases := DIRECTION_CASES
	var user_args := OS.get_cmdline_user_args()
	test_aim_ready = "--aim-ready" in user_args
	for arg: String in user_args:
		if arg.begins_with("--candidate="):
			candidate_loader = load("res://tools/pistol_candidate_loader.gd").new()
			if not candidate_loader.load_candidate(arg.trim_prefix("--candidate=")):
				_expect(false, "candidate GLB loads")
				_finish()
				return
	if "--mark23-only" in user_args:
		weapon_paths = ["res://config/weapons/mark_23.json"]
	if "--standing-idle-only" in user_args:
		posture_cases = [POSTURE_CASES[0]]
		direction_cases = [DIRECTION_CASES[0]]
	elif "--crouched-wa-only" in user_args:
		posture_cases = [POSTURE_CASES[1]]
		direction_cases = [DIRECTION_CASES[1]]
	for weapon_path in weapon_paths:
		_expect(
			bool(controller.call("apply_authorized_weapon_pickup", weapon_path)),
			"%s equips through the canonical authorized handoff" % weapon_path.get_file()
		)
		await _frames(20)
		if candidate_loader != null:
			var installation: Dictionary = candidate_loader.install(driver, "--distinct-low-ready" in user_args)
			print("PISTOL_DIRECTION_CANDIDATE ", JSON.stringify(installation))
			_expect(bool(installation.get("ok", false)), "candidate preserves native rest")
		for posture_case in posture_cases:
			var posture_name := StringName(posture_case["name"])
			_expect(
				bool(player.call("_try_set_posture", int(posture_case["index"]))),
				"%s enters %s" % [weapon_path.get_file(), posture_name]
			)
			await _frames(12)
			for direction_case in direction_cases:
				await _check_case(
					weapon_path.get_file().get_basename(),
					posture_name,
					float(posture_case["height"]),
					direction_case,
					player,
					controller,
					mannequin,
					driver
				)
	scene.queue_free()
	await process_frame
	if candidate_loader != null:
		candidate_loader.dispose()
	_finish()


func _verify_directional_contract() -> void:
	var raw := _read_dictionary("res://config/operator_animation_map.json")
	var aliases: Dictionary = raw.get("clip_aliases", {})
	var yaw: Dictionary = raw.get("pose_yaw_offsets_degrees", {})
	for gait in ["walk", "run"]:
		for side in ["left", "right"]:
			var target := "pistol_%s_forward_%s" % [gait, side]
			var source := "pistol_%s_forward" % gait
			_expect(
				String(aliases.get(target, "")) == source,
				"%s reuses centered %s legs" % [target, source]
			)
			var expected_sign := 1.0 if side == "left" else -1.0
			var offset := float(yaw.get(target, 0.0))
			_expect(
				signf(offset) == expected_sign and absf(offset) <= 25.0,
				"%s uses bounded signed hip yaw" % target
			)


func _check_case(
	weapon_id: String,
	posture_name: StringName,
	aim_height: float,
	direction_case: Dictionary,
	player: CharacterBody3D,
	controller: Node,
	mannequin: Node,
	driver: Node
) -> void:
	checked_cases += 1
	if driver.has_method("clear_fire_ready_aim"):
		driver.call("clear_fire_ready_aim")
	var direction: Vector2 = direction_case["direction"]
	var speed := float(direction_case["speed"])
	var world_direction := _world_aim_direction(player, AIM_YAW_RAD, AIM_PITCH_RAD)
	var aim_target := player.global_position + Vector3.UP * aim_height + world_direction * 25.0
	driver.call(
		"set_visual_inputs",
		direction, posture_name, AIM_YAW_RAD, AIM_PITCH_RAD, 1.0 if test_aim_ready else 0.0, false, 0.0,
		speed, &"LOCOMOTION", 0.0, &"FULL", speed * 5.45,
		aim_target, direction, speed, &"ACCELERATING", 0.0
	)
	await _frames(24)
	await _await_ballistics_ready(controller)
	var root_before := player.global_transform
	var shot: Dictionary = controller.call("request_fire")
	var label := "%s %s %s" % [weapon_id, posture_name, direction_case["label"]]
	_expect(bool(shot.get("fired", false)), "%s shot is accepted" % label)
	if not bool(shot.get("fired", false)):
		return
	var previous_sample_frame := 0
	for sample_frame in TRANSITION_SAMPLE_FRAMES:
		await _frames(sample_frame - previous_sample_frame)
		previous_sample_frame = sample_frame
		_check_transition_sample(label, sample_frame, driver, mannequin, aim_target)
	var debug: Dictionary = driver.call("get_animation_debug_state")
	var latch: Dictionary = debug.get("fire_upper_body_latch", {})
	var pose: Dictionary = debug.get("weapon_pose", {})
	var geometry := _measure_geometry(driver, mannequin, aim_target)
	print(
		(
			"PISTOL_FIRE_DIRECTION_METRIC weapon=%s posture=%s input=%s "
			+ "bore_error_deg=%.3f axial_roll_deg=%.3f shoulder_error_deg=%.3f shoulder_level_cm=%.3f "
			+ "reported_bore_error_deg=%.3f wrist_correction_deg=%.3f ready_weight=%.3f "
			+ "trigger_error_m=%.4f support_error_m=%.4f"
		) % [
			weapon_id,
			String(posture_name),
			String(direction_case["label"]),
			float(geometry["bore_error_deg"]),
			float(geometry["axial_roll_deg"]),
			float(geometry["shoulder_error_deg"]),
			float(geometry["shoulder_level_cm"]),
			float(pose.get("weapon_aim_error_deg", INF)),
			float(pose.get("wrist_correction_deg", INF)),
			float(debug.get("weapon_ready_weight", -1.0)),
			float(pose.get("trigger_hand_error_m", INF)),
			float(pose.get("support_hand_error_m", INF)),
		]
	)
	_expect(
		StringName(latch.get("owner_state", &"")) == &"FIRE_RECOVERY"
		and bool(debug.get("presentation_fire_selected", false))
		and StringName(debug.get("active_fire_clip", &"invalid")) == &"",
		"%s keeps the 1.2-second recovery and no fire OneShot" % label
	)
	_expect(
		bool(pose.get("animation_owned_aim_alignment_enabled", false))
		and bool(pose.get("animation_owned_aim_alignment_active", false))
		and bool(pose.get("pistol_trigger_centerline_ik_active", false))
		and bool(pose.get("weapon_solver_owned", false))
		and not bool(pose.get("weapon_parent_is_animation_mount", true))
		and not bool(pose.get("right_hand_ik_running", true)),
		"%s uses the sole pistol aim anchor and bounded one-shot trigger-palm modifier" % label
	)
	_expect(
		float(geometry["bore_error_deg"]) <= MAX_BORE_ERROR_DEG,
		"%s rendered bore follows reticle yaw and pitch within %.1f degree"
		% [label, MAX_BORE_ERROR_DEG]
	)
	_expect(
		absf(float(geometry["axial_roll_deg"])) <= MAX_AXIAL_ROLL_DEG,
		"%s pistol remains upright within %.1f degrees"
		% [label, MAX_AXIAL_ROLL_DEG]
	)
	_expect(
		float(geometry["shoulder_error_deg"]) <= MAX_SHOULDER_SQUARE_ERROR_DEG,
		"%s shoulder bar remains square to reticle" % label
	)
	_expect(
		float(geometry["shoulder_level_cm"]) <= MAX_SHOULDER_LEVEL_ERROR_CM,
		"%s shoulders remain vertically human" % label
	)
	_expect(
		float(pose.get("trigger_hand_error_m", INF)) <= MAX_HAND_ERROR_M
		and float(pose.get("support_hand_error_m", INF)) <= MAX_HAND_ERROR_M,
		"%s keeps both hand contacts within 1 cm" % label
	)
	_expect(
		player.global_transform.is_equal_approx(root_before),
		"%s presentation does not write CharacterBody3D" % label
	)


func _check_transition_sample(
	label: String,
	sample_frame: int,
	driver: Node,
	mannequin: Node,
	aim_target: Vector3
) -> void:
	var debug: Dictionary = driver.call("get_animation_debug_state")
	var pose: Dictionary = debug.get("weapon_pose", {})
	var geometry := _measure_geometry(driver, mannequin, aim_target)
	var sample_label := "%s transition frame %d" % [label, sample_frame]
	print(
		(
			"PISTOL_FIRE_TRANSITION_METRIC case=%s frame=%d "
			+ "bore_error_deg=%.3f axial_roll_deg=%.3f "
			+ "trigger_error_m=%.4f support_error_m=%.4f right_hand_ik=%s "
			+ "shoulder_width_m=%.4f trigger_lateral_m=%.4f barrel_lateral_m=%.4f "
			+ "centerline_ratio=%.3f left_cross_ratio=%.3f "
			+ "right_hand_lateral_m=%.4f right_palm_lateral_m=%.4f "
			+ "right_elbow_deg=%.2f left_elbow_deg=%.2f centerline_solve=%s"
		) % [
			label,
			sample_frame,
			float(geometry["bore_error_deg"]),
			float(geometry["axial_roll_deg"]),
			float(pose.get("trigger_hand_error_m", INF)),
			float(pose.get("support_hand_error_m", INF)),
			str(bool(pose.get("right_hand_ik_running", true))),
			float(geometry["shoulder_width_m"]),
			float(geometry["trigger_lateral_m"]),
			float(geometry["barrel_lateral_m"]),
			float(geometry["centerline_offset_ratio"]),
			float(geometry["left_cross_ratio"]),
			float(geometry["right_hand_lateral_m"]),
			float(geometry["right_palm_lateral_m"]),
			float(pose.get("right_elbow_angle_deg", -1.0)),
			float(pose.get("left_elbow_angle_deg", -1.0)),
			str(bool(pose.get("pistol_trigger_centerline_ik_active", false))),
		]
	)
	_expect(
		bool(pose.get("animation_owned_aim_alignment_active", false))
		and bool(pose.get("pistol_trigger_centerline_ik_active", false))
		and bool(pose.get("weapon_solver_owned", false))
		and not bool(pose.get("right_hand_ik_running", true)),
		"%s uses one weapon-root correction and a bounded one-shot trigger-palm modifier" % sample_label
	)
	_expect(
		float(geometry["bore_error_deg"]) <= MAX_BORE_ERROR_DEG
		and absf(float(geometry["axial_roll_deg"])) <= MAX_AXIAL_ROLL_DEG,
		"%s keeps the corrected physical bore on the reticle and upright" % sample_label
	)
	_expect(
		float(pose.get("trigger_hand_error_m", INF)) <= MAX_HAND_ERROR_M
		and float(pose.get("support_hand_error_m", INF)) <= MAX_HAND_ERROR_M,
		"%s keeps both contacts after the final weapon-root correction" % sample_label
	)
	_expect(
		float(geometry["centerline_offset_ratio"]) <= MAX_CENTERLINE_OFFSET_RATIO
		and float(geometry["left_cross_ratio"]) <= MAX_LEFT_CROSS_RATIO,
		(
			"%s keeps trigger grip and barrel within %.0f%% of shoulder width of "
			+ "the aim plane and limits left crossing to %.0f%%"
		) % [
			sample_label,
			MAX_CENTERLINE_OFFSET_RATIO * 100.0,
			MAX_LEFT_CROSS_RATIO * 100.0,
		]
	)
	_expect(
		float(pose.get("right_elbow_angle_deg", -1.0)) >= MIN_ELBOW_ANGLE_DEG
		and float(pose.get("right_elbow_angle_deg", INF)) <= MAX_ELBOW_ANGLE_DEG
		and float(pose.get("left_elbow_angle_deg", -1.0)) >= MIN_ELBOW_ANGLE_DEG
		and float(pose.get("left_elbow_angle_deg", INF)) <= MAX_ELBOW_ANGLE_DEG,
		"%s keeps both elbows inside the human guardrail" % sample_label
	)


func _measure_geometry(driver: Node, mannequin: Node, aim_target: Vector3) -> Dictionary:
	var skeleton := driver.get("skeleton") as Skeleton3D
	var muzzle := mannequin.call("get_active_muzzle_marker") as Marker3D
	var barrel_base := mannequin.call("get_active_barrel_base_marker") as Marker3D
	var solver = driver.get("weapon_pose_solver")
	var optic := solver.get("optic_socket") as Marker3D if solver != null else null
	var trigger := solver.get("trigger_socket") as Marker3D if solver != null else null
	if (
		skeleton == null
		or muzzle == null
		or barrel_base == null
		or optic == null
		or trigger == null
	):
		return {
			"bore_error_deg": INF,
			"axial_roll_deg": INF,
			"shoulder_error_deg": INF,
			"shoulder_level_cm": INF,
			"shoulder_width_m": 0.0,
			"trigger_lateral_m": INF,
			"barrel_lateral_m": INF,
			"centerline_offset_ratio": INF,
			"left_cross_ratio": INF,
		}
	var bore := (muzzle.global_position - barrel_base.global_position).normalized()
	var expected := muzzle.global_position.direction_to(aim_target)
	var actual_up := optic.global_position - barrel_base.global_position
	actual_up -= bore * actual_up.dot(bore)
	var expected_up := skeleton.global_basis.y.normalized()
	expected_up -= bore * expected_up.dot(bore)
	var axial_roll := INF
	if actual_up.length_squared() >= 0.0000000001 and expected_up.length_squared() >= 0.0000000001:
		actual_up = actual_up.normalized()
		expected_up = expected_up.normalized()
		axial_roll = rad_to_deg(atan2(
			bore.dot(expected_up.cross(actual_up)),
			expected_up.dot(actual_up)
		))
	var left_index := skeleton.find_bone(&"mixamorig_LeftArm")
	var right_index := skeleton.find_bone(&"mixamorig_RightArm")
	var left := skeleton.global_transform * skeleton.get_bone_global_pose(left_index).origin
	var right := skeleton.global_transform * skeleton.get_bone_global_pose(right_index).origin
	var shoulder_bar := right - left
	var shoulder_width_m := shoulder_bar.length()
	var shoulder_center := (left + right) * 0.5
	var shoulder_level_cm := absf(shoulder_bar.y) * 100.0
	shoulder_bar.y = 0.0
	var aim_flat := Vector3(expected.x, 0.0, expected.z).normalized()
	var desired_right := aim_flat.cross(Vector3.UP).normalized()
	var square_error := INF
	if shoulder_bar.length_squared() > 0.000001 and desired_right.length_squared() > 0.5:
		square_error = rad_to_deg(acos(clampf(
			absf(shoulder_bar.normalized().dot(desired_right)), -1.0, 1.0
		)))
	var trigger_lateral_m := (trigger.global_position - shoulder_center).dot(desired_right)
	var barrel_lateral_m := (barrel_base.global_position - shoulder_center).dot(desired_right)
	var right_hand_index := skeleton.find_bone(&"mixamorig_RightHand")
	var right_hand_position := (
		skeleton.global_transform * skeleton.get_bone_global_pose(right_hand_index).origin
	)
	var right_palm_anchor: Vector3 = solver.get("right_palm_anchor_local")
	var right_palm_position := skeleton.global_transform * (
		skeleton.get_bone_global_pose(right_hand_index) * right_palm_anchor
	)
	var right_hand_lateral_m := (right_hand_position - shoulder_center).dot(desired_right)
	var right_palm_lateral_m := (right_palm_position - shoulder_center).dot(desired_right)
	var safe_shoulder_width := maxf(shoulder_width_m, 0.001)
	var centerline_offset_ratio := maxf(
		absf(trigger_lateral_m), absf(barrel_lateral_m)
	) / safe_shoulder_width
	var left_cross_ratio := maxf(
		maxf(-trigger_lateral_m, -barrel_lateral_m), 0.0
	) / safe_shoulder_width
	return {
		"bore_error_deg": rad_to_deg(bore.angle_to(expected)),
		"axial_roll_deg": axial_roll,
		"shoulder_error_deg": square_error,
		"shoulder_level_cm": shoulder_level_cm,
		"shoulder_width_m": shoulder_width_m,
		"trigger_lateral_m": trigger_lateral_m,
		"barrel_lateral_m": barrel_lateral_m,
		"centerline_offset_ratio": centerline_offset_ratio,
		"left_cross_ratio": left_cross_ratio,
		"right_hand_lateral_m": right_hand_lateral_m,
		"right_palm_lateral_m": right_palm_lateral_m,
	}


func _world_aim_direction(player: CharacterBody3D, yaw: float, pitch: float) -> Vector3:
	var yaw_basis := Basis(Vector3.UP, player.global_rotation.y + yaw)
	var forward := yaw_basis * Vector3.FORWARD
	var right := yaw_basis * Vector3.RIGHT
	return (Basis(right, pitch) * forward).normalized()


func _await_ballistics_ready(controller: Node) -> void:
	var ballistics = controller.get("ballistics")
	if ballistics == null:
		return
	for _frame in 240:
		if float(ballistics.get("fire_cooldown")) <= 0.0:
			return
		await process_frame
		await physics_frame


func _read_dictionary(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(file.get_as_text()) if file != null else null
	return parsed as Dictionary if parsed is Dictionary else {}


func _frames(count: int) -> void:
	for _frame in count:
		await process_frame
		await physics_frame


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("PISTOL_FIRE_DIRECTION_CHECK PASS %s" % label)
		return
	failures.append(label)
	push_error("PISTOL_FIRE_DIRECTION_CHECK FAIL %s" % label)


func _finish() -> void:
	if failures.is_empty():
		print("PISTOL_FIRE_DIRECTION_POSE_REGRESSION PASS cases=%d" % checked_cases)
		quit(0)
		return
	print("PISTOL_FIRE_DIRECTION_POSE_REGRESSION FAIL %s" % [failures])
	quit(1)
