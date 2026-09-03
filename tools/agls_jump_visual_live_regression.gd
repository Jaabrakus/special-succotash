extends SceneTree

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
	var driver := (
		player.get_node_or_null("Mannequin/ProductionAnimation")
		if player != null
		else null
	)
	_expect(player != null and driver != null, "live AGLS jump route exists")
	if player == null or driver == null:
		_finish()
		return
	var clip_paths: Dictionary = driver.get("clip_paths")
	_expect(
		String(clip_paths.get(&"jump_up_standing", "")).contains("Start_Stand"),
		"stationary takeoff has a dedicated AGLS clip"
	)
	_expect(
		String(clip_paths.get(&"jump_down_moving", "")).contains("Land_Run"),
		"moving ground contact has a dedicated AGLS clip"
	)

	var start_y := player.global_position.y
	var skeleton := driver.get("skeleton") as Skeleton3D
	var hips_index := skeleton.find_bone(&"mixamorig_Hips") if skeleton != null else -1
	if hips_index < 0 and skeleton != null:
		hips_index = skeleton.find_bone(&"pelvis")
	var resting_hips_y := (
		skeleton.get_bone_global_pose(hips_index).origin.y
		if skeleton != null and hips_index >= 0
		else 0.0
	)
	Input.action_press(&"jump")
	await physics_frame
	Input.action_release(&"jump")
	await _steps(2)
	_expect(player.call("get_motion_state_name") == &"AIRBORNE", "stationary jump enters airborne state")
	_expect(
		StringName(driver.get("current_clip")) == &"jump_up_standing",
		"stationary jump uses standing takeoff rather than run takeoff"
	)
	var jump_debug: Dictionary = driver.call("get_animation_debug_state")
	_expect(
		is_equal_approx(float(jump_debug.get("rifle_carry_weight", 0.0)), 1.0),
		"normal jump retains the authored rifle arms"
	)
	var apex := start_y
	var minimum_hips_y := resting_hips_y
	var maximum_hips_y := resting_hips_y
	var saw_fall_loop := false
	var saw_landing := false
	for _frame in range(150):
		await physics_frame
		apex = maxf(apex, player.global_position.y)
		if skeleton != null and hips_index >= 0:
			var hips_y := skeleton.get_bone_global_pose(hips_index).origin.y
			minimum_hips_y = minf(minimum_hips_y, hips_y)
			maximum_hips_y = maxf(maximum_hips_y, hips_y)
		var state := StringName(player.call("get_motion_state_name"))
		var clip := StringName(driver.get("current_clip"))
		if state == &"AIRBORNE" and float(player.velocity.y) < -1.0:
			saw_fall_loop = saw_fall_loop or clip == &"jump_loop"
		if state == &"LANDING":
			saw_landing = saw_landing or clip == &"jump_down"
		if state == &"LOCOMOTION" and player.is_on_floor():
			break
	_expect(saw_fall_loop, "falling stays in the AGLS airborne loop")
	_expect(saw_landing, "landing take begins only on ground contact")
	var rise := apex - start_y
	print(
		"AGLS_JUMP_VISUAL_INFO capsule_rise=%.4f hips_rest=%.4f hips_min=%.4f hips_max=%.4f"
		% [rise, resting_hips_y, minimum_hips_y, maximum_hips_y]
	)
	_expect(
		maximum_hips_y - minimum_hips_y <= 0.35,
		"jump animation cannot add unbounded pelvis height"
	)
	_expect(rise >= 0.35 and rise <= 0.80, "jump remains a bounded tactical hop")
	_finish()


func _steps(count: int) -> void:
	for _step in range(count):
		await physics_frame


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("AGLS_JUMP_VISUAL_CHECK PASS %s" % label)
		return
	failures.append(label)
	push_error("AGLS_JUMP_VISUAL_CHECK FAIL %s" % label)


func _finish() -> void:
	Input.action_release(&"jump")
	if failures.is_empty():
		print("AGLS_JUMP_VISUAL_LIVE_REGRESSION PASS")
		quit(0)
		return
	print("AGLS_JUMP_VISUAL_LIVE_REGRESSION FAIL %s" % [failures])
	quit(1)
