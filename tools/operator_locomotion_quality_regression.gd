extends SceneTree

## Runtime likeness guard. Values are measured from the rendered 65-bone rig,
## not inferred from selected clip names.

var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var packed := load("res://main.tscn") as PackedScene
	_expect(packed != null, "quality scene loads")
	if packed == null:
		_finish()
		return
	var scene := packed.instantiate()
	root.add_child(scene)
	for _frame in range(30):
		await physics_frame
	var player := scene.get_node_or_null("Player") as CharacterBody3D
	var driver = player.get_node_or_null("Mannequin/ProductionAnimation") if player else null
	_expect(player != null and driver != null, "runtime player and operator exist")
	if player == null or driver == null:
		_finish()
		return
	driver.animation_profile.transitions["enabled"] = false
	await _measure_foot_slip(player, driver)
	await _measure_contact_phase_continuity(player, driver)
	await _measure_direction_pop(player, driver)
	await _measure_torso_error(driver)
	await _measure_body_stack_stability(driver)
	_finish()


func _measure_foot_slip(player: CharacterBody3D, driver) -> void:
	Input.action_press(&"move_forward", 0.4)
	for _frame in range(24):
		await physics_frame
	var left: int = driver.skeleton.find_bone("mixamorig_LeftFoot")
	var right: int = driver.skeleton.find_bone("mixamorig_RightFoot")
	var left_samples: Array[Vector3] = []
	var right_samples: Array[Vector3] = []
	for _frame in range(60):
		await physics_frame
		left_samples.append(_bone_world_position(driver, left))
		right_samples.append(_bone_world_position(driver, right))
	Input.action_release(&"move_forward")
	var slips := _contact_slips(left_samples)
	slips.append_array(_contact_slips(right_samples))
	slips.sort()
	var mean_cm := 0.0
	for slip in slips:
		mean_cm += slip * 100.0
	mean_cm /= maxf(slips.size(), 1)
	var p95_cm := 0.0
	if not slips.is_empty():
		p95_cm = slips[int(floor((slips.size() - 1) * 0.95))] * 100.0
	print("LOCOMOTION_METRIC foot_slip_mean_cm_per_frame=%.3f p95=%.3f samples=%d" % [mean_cm, p95_cm, slips.size()])
	_expect(mean_cm <= 4.6, "mean planted-foot slip stays inside the tightened budget")
	_expect(p95_cm <= 5.6, "p95 planted-foot slip stays inside the tightened budget")


func _measure_contact_phase_continuity(player: CharacterBody3D, driver) -> void:
	var left: int = driver.skeleton.find_bone("mixamorig_LeftFoot")
	var right: int = driver.skeleton.find_bone("mixamorig_RightFoot")
	Input.action_press(&"move_forward", 1.0)
	for _frame in range(36):
		await physics_frame
	var minimum_left_y := INF
	var minimum_right_y := INF
	for _frame in range(75):
		await physics_frame
		minimum_left_y = minf(minimum_left_y, _bone_world_position(driver, left).y)
		minimum_right_y = minf(minimum_right_y, _bone_world_position(driver, right).y)
	var planted_left := true
	for _frame in range(120):
		await physics_frame
		var left_position := _bone_world_position(driver, left)
		var right_position := _bone_world_position(driver, right)
		if left_position.y <= minimum_left_y + 0.012:
			planted_left = true
			break
		if right_position.y <= minimum_right_y + 0.012:
			planted_left = false
			break
	var before_phase: float = driver.locomotion_graph.shared_phase
	var left_before := _bone_world_position(driver, left)
	var right_before := _bone_world_position(driver, right)
	var player_before := player.global_position
	var planted_before := (left_before if planted_left else right_before) - player_before
	Input.action_release(&"move_forward")
	Input.action_press(&"move_right", 1.0)
	await physics_frame
	var after_phase: float = driver.locomotion_graph.shared_phase
	# Authoritative movement changes world position immediately by roughly one
	# full-speed physics step. Remove that intended CharacterBody translation so
	# this metric measures animation/contact discontinuity rather than player travel.
	var planted_after := (
		_bone_world_position(driver, left if planted_left else right)
		- player.global_position
	)
	Input.action_release(&"move_right")
	var phase_step := fposmod(after_phase - before_phase, 1.0)
	var contact_step_cm := Vector2(
		planted_after.x - planted_before.x,
		planted_after.z - planted_before.z
	).length() * 100.0
	print(
		"LOCOMOTION_METRIC direction_change_phase_step=%.4f planted_contact_step_cm=%.3f" % [
			phase_step, contact_step_cm
		]
	)
	_expect(
		phase_step > 0.001 and phase_step < 0.08,
		"direction change advances the locomotion playhead instead of resetting it"
	)
	_expect(
		contact_step_cm <= 6.0,
		"direction change preserves the measured planted-foot contact"
	)
	player.velocity = Vector3.ZERO
	await physics_frame


func _measure_direction_pop(player: CharacterBody3D, driver) -> void:
	Input.action_press(&"move_forward", 1.0)
	for _frame in range(60):
		await physics_frame
	var bones: Array[int] = []
	for bone_name in [
		"mixamorig_Hips", "mixamorig_Spine2",
		"mixamorig_LeftUpLeg", "mixamorig_RightUpLeg",
	]:
		bones.append(driver.skeleton.find_bone(bone_name))
	var previous: Array[Quaternion] = []
	var pops_by_bone: Array[Array] = []
	for bone in bones:
		previous.append(driver.skeleton.get_bone_global_pose(bone).basis.get_rotation_quaternion())
		pops_by_bone.append([])
	Input.action_release(&"move_forward")
	Input.action_press(&"move_right", 1.0)
	var pops: Array[float] = []
	for _frame in range(45):
		await physics_frame
		for index in range(bones.size()):
			var current: Quaternion = driver.skeleton.get_bone_global_pose(bones[index]).basis.get_rotation_quaternion()
			var delta_deg := rad_to_deg(previous[index].angle_to(current))
			pops.append(delta_deg)
			pops_by_bone[index].append(delta_deg)
			previous[index] = current
	Input.action_release(&"move_right")
	pops.sort()
	var p95 := pops[int(floor((pops.size() - 1) * 0.95))] if not pops.is_empty() else 0.0
	var maximum := pops[-1] if not pops.is_empty() else 0.0
	print("LOCOMOTION_METRIC direction_pop_deg_per_frame_p95=%.3f max=%.3f" % [p95, maximum])
	for index in range(pops_by_bone.size()):
		pops_by_bone[index].sort()
		var bone_p95: float = pops_by_bone[index][int(floor((pops_by_bone[index].size() - 1) * 0.95))]
		print(
			"LOCOMOTION_METRIC direction_pop_%s_p95=%.3f" % [
				driver.skeleton.get_bone_name(bones[index]), bone_p95,
			]
		)
	_expect(p95 <= 12.0, "direction blend p95 pose delta stays below 12 degrees per frame")
	_expect(maximum <= 25.0, "direction blend has no one-frame pose snap")
	player.velocity = Vector3.ZERO


func _measure_torso_error(driver) -> void:
	driver.set_visual_inputs(
		Vector2.ZERO, &"STANDING", deg_to_rad(30.0), 0.0,
		1.0, false, 0.0, 0.0, &"STANDING", 0.0, &"WALK", 0.0
	)
	# Ready Aim intentionally eases in so a relaxed rifle run cannot snap into
	# its combat upper-body pose. Measure the settled contract, not frame one of
	# that transition.
	for _frame in range(30):
		await process_frame
	var snapshot: Dictionary = driver.get_animation_debug_state()
	var error := float(snapshot.get("torso_to_aim_error_deg", 180.0))
	print("LOCOMOTION_METRIC torso_to_aim_error_deg=%.3f" % error)
	_expect(error <= 1.0, "reticle-facing torso leaves at most one degree for the arms")


func _measure_body_stack_stability(driver) -> void:
	var hips_index: int = driver.skeleton.find_bone(&"mixamorig_Hips")
	var head_index: int = driver.skeleton.find_bone(&"mixamorig_Head")
	var maximum_lean_deg := 0.0
	for direction in [Vector2.UP, Vector2.RIGHT, Vector2.LEFT]:
		driver.set_visual_inputs(
			direction, &"STANDING", 0.0, 0.0,
			1.0, false, 0.0, 1.0, &"LOCOMOTION", 0.0, &"FULL", 5.45
		)
		for frame_index in range(60):
			await process_frame
			if frame_index < 10:
				continue
			var hips: Vector3 = driver.skeleton.get_bone_global_pose(hips_index).origin
			var head: Vector3 = driver.skeleton.get_bone_global_pose(head_index).origin
			var offset := head - hips
			var lean_deg := rad_to_deg(
				atan2(Vector2(offset.x, offset.z).length(), maxf(offset.y, 0.0001))
			)
			maximum_lean_deg = maxf(maximum_lean_deg, lean_deg)
	print("LOCOMOTION_METRIC body_stack_max_lean_deg=%.3f" % maximum_lean_deg)
	_expect(
		maximum_lean_deg <= 10.5,
		"standing locomotion keeps the rifle torso inside the body-stack lean budget"
	)


func _contact_slips(samples: Array[Vector3]) -> Array[float]:
	var result: Array[float] = []
	if samples.size() < 2:
		return result
	var minimum_y := INF
	for sample in samples:
		minimum_y = minf(minimum_y, sample.y)
	for index in range(1, samples.size()):
		if samples[index].y > minimum_y + 0.025 or samples[index - 1].y > minimum_y + 0.025:
			continue
		var delta := samples[index] - samples[index - 1]
		result.append(Vector2(delta.x, delta.z).length())
	return result


func _bone_world_position(driver, bone_index: int) -> Vector3:
	return driver.skeleton.global_transform * driver.skeleton.get_bone_global_pose(bone_index).origin


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("LOCOMOTION_QUALITY_CHECK PASS ", label)
	else:
		failures.append(label)
		push_error("LOCOMOTION_QUALITY_CHECK FAIL %s" % label)


func _finish() -> void:
	for action in [&"move_forward", &"move_back", &"move_left", &"move_right"]:
		Input.action_release(action)
	if failures.is_empty():
		print("OPERATOR_LOCOMOTION_QUALITY_REGRESSION PASS")
		quit(0)
	else:
		print("OPERATOR_LOCOMOTION_QUALITY_REGRESSION FAIL ", failures)
		quit(1)
