extends SceneTree

## Verifies the native AGLS locomotion pose can move at full lateral speed while
## the SOCOM camera-owned aim remains immediate through torso, rifle, and muzzle.

const AIM_YAW := deg_to_rad(32.0)
const AIM_PITCH := deg_to_rad(-8.0)
const MAX_ALIGNMENT_ERROR_DEG := 0.25

var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var packed := load("res://main.tscn") as PackedScene
	_expect(packed != null, "main scene loads")
	if packed == null:
		_finish()
		return
	var scene := packed.instantiate()
	root.add_child(scene)
	await _frames(45)
	var player := scene.get_node_or_null("Player") as CharacterBody3D
	var mannequin := player.get_node_or_null("Mannequin") if player != null else null
	var driver := mannequin.get_node_or_null("ProductionAnimation") if mannequin != null else null
	_expect(player != null and mannequin != null and driver != null, "live AGLS operator route exists")
	if player == null or mannequin == null or driver == null:
		_finish()
		return

	mannequin.set_process(false)
	var aim_direction := Vector3(sin(AIM_YAW), -sin(AIM_PITCH), -cos(AIM_YAW)).normalized()
	var aim_target := player.global_position + Vector3.UP * 1.35 + aim_direction * 25.0
	driver.call(
		"set_visual_inputs",
		Vector2.RIGHT,
		&"STANDING",
		AIM_YAW,
		AIM_PITCH,
		1.0,
		false,
		0.0,
		1.0,
		&"LOCOMOTION",
		0.0,
		&"FULL",
		6.25,
		aim_target,
		Vector2.RIGHT,
		1.0,
		&"SUSTAINED",
		0.0
	)
	await _frames(30)
	var debug: Dictionary = driver.call("get_animation_debug_state")
	var pose: Dictionary = debug.get("weapon_pose", {})
	var muzzle: Vector3 = mannequin.call("get_active_muzzle_position")
	var barrel: Vector3 = mannequin.call("get_active_barrel_direction")
	var measured_error := rad_to_deg(barrel.angle_to(muzzle.direction_to(aim_target)))
	print((
		"AGLS_FAST_MOVEMENT_AIM_INFO clip=%s torso_yaw=%.3f target_yaw=%.3f "
		+ "pose_error=%.3f measured_error=%.3f"
	) % [
			String(debug.get("logical_clip", "")),
			rad_to_deg(float(debug.get("applied_yaw_rad", 0.0))),
			rad_to_deg(AIM_YAW),
			float(pose.get("weapon_aim_error_deg", INF)),
			measured_error,
		]
	)
	_expect(bool(debug.get("strict_authored_pose", false)), "native AGLS animation remains the base pose")
	_expect(String(debug.get("logical_clip", "")) == "run_right", "full-speed lateral movement keeps the AGLS run state")
	_expect(
		absf(float(debug.get("applied_yaw_rad", 0.0)) - AIM_YAW) <= deg_to_rad(MAX_ALIGNMENT_ERROR_DEG),
		"camera yaw reaches the torso on the current frame"
	)
	_expect(
		float(pose.get("weapon_aim_error_deg", INF)) <= MAX_ALIGNMENT_ERROR_DEG,
		"weapon solver reports the rifle on the reticle ray"
	)
	_expect(measured_error <= MAX_ALIGNMENT_ERROR_DEG, "rendered muzzle independently points at the reticle target")
	_expect(
		absf(float(debug.get("lower_body_inherited_yaw_deg", 0.0))) <= 0.01,
		"aim correction does not rotate the lower body"
	)
	_finish()


func _frames(count: int) -> void:
	for _frame in range(count):
		await physics_frame


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("AGLS_FAST_MOVEMENT_AIM_CHECK PASS %s" % label)
		return
	failures.append(label)
	push_error("AGLS_FAST_MOVEMENT_AIM_CHECK FAIL %s" % label)


func _finish() -> void:
	if failures.is_empty():
		print("AGLS_FAST_MOVEMENT_AIM_REGRESSION PASS")
		quit(0)
		return
	print("AGLS_FAST_MOVEMENT_AIM_REGRESSION FAIL %s" % [failures])
	quit(1)
