extends SceneTree

## Focused diagnostic for the production Auto-Rig Pro visual weapon handoff.
## This does not inspect or mutate the authoritative shot result; it measures
## only the rendered barrel ray against the camera-owned convergence point.

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
	await _steps(45)
	var player := scene.get_node_or_null("Player") as CharacterBody3D
	var rig := scene.get_node_or_null("IndependentCameraRig")
	var weapon := scene.get_node_or_null("WeaponController")
	_expect(player != null and rig != null and weapon != null, "live weapon path is wired")
	if player == null or rig == null or weapon == null:
		_finish()
		return
	player.velocity = Vector3.RIGHT * float(player.get("move_speed"))
	weapon.call("_physics_process", 1.0 / 60.0)
	var shot: Dictionary = weapon.call("request_fire")
	_expect(bool(shot.get("fired", false)), "accepted shot starts native visual handoff")
	var mannequin := player.get_node("Mannequin")
	var driver = mannequin.get_node_or_null("ProductionAnimation")
	_expect(driver != null, "production animation driver exists")
	if driver == null:
		_finish()
		return
	weapon.call("_set_presentation_trigger_held", true)
	mannequin.call("_sync_production_animation", player)
	driver.call("_process", 1.0 / 60.0)
	weapon.call("_set_presentation_trigger_held", false)
	mannequin.call("_sync_production_animation", player)
	for frame in range(25):
		driver.call("_process", 1.0 / 60.0)
		var muzzle: Vector3 = mannequin.call("get_active_muzzle_position")
		var barrel: Vector3 = mannequin.call("get_active_barrel_direction")
		var target := Vector3(rig.get("weapon_aim_point"))
		var target_direction := muzzle.direction_to(target)
		var pose: Dictionary = driver.call("get_animation_debug_state").get(
			"weapon_pose", {}
		)
		print("ARP_WEAPON_ALIGNMENT frame=%d error_deg=%.6f weight=%.6f desired=%.6f muzzle=%s barrel=%s target=%s pose_error_deg=%.6f owner=%s line=%s rail=%s" % [
			frame,
			rad_to_deg(barrel.angle_to(target_direction)),
			float(pose.get("weight", 0.0)),
			float(pose.get("desired_weight", 0.0)),
			muzzle,
			barrel,
			target,
			float(pose.get("weapon_aim_error_deg", INF)),
			String(pose.get("weapon_owner", "")),
			str(pose.get("gun_placement_line_active", false)),
			str(pose.get("rail_to_blue_line_event_active", false)),
		])
	var final_muzzle: Vector3 = mannequin.call("get_active_muzzle_position")
	var final_barrel: Vector3 = mannequin.call("get_active_barrel_direction")
	var final_target := Vector3(rig.get("weapon_aim_point"))
	_expect(
		rad_to_deg(final_barrel.angle_to(final_muzzle.direction_to(final_target))) <= 0.10,
		"native rendered barrel converges to the camera-owned sight point"
	)
	_finish()


func _steps(count: int) -> void:
	for _step in range(count):
		await process_frame


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("OPERATOR_NATIVE_RIG_WEAPON_ALIGNMENT_CHECK PASS %s" % label)
		return
	failures.append(label)
	push_error("OPERATOR_NATIVE_RIG_WEAPON_ALIGNMENT_CHECK FAIL %s" % label)


func _finish() -> void:
	if failures.is_empty():
		print("OPERATOR_NATIVE_RIG_WEAPON_ALIGNMENT_REGRESSION PASS")
		quit(0)
	else:
		print("OPERATOR_NATIVE_RIG_WEAPON_ALIGNMENT_REGRESSION FAIL %s" % [failures])
		quit(1)
