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
	for _frame in range(30):
		await physics_frame
	var player := scene.get_node_or_null("Player") as CharacterBody3D
	var driver := scene.get_node_or_null("Player/Mannequin/ProductionAnimation")
	_expect(player != null and driver != null, "production prone rig exists")
	if player == null or driver == null:
		_finish()
		return

	player.global_position = Vector3(0.0, 0.05, 6.0)
	player.velocity = Vector3.ZERO
	if OS.get_cmdline_user_args().has("--baseline-prone"):
		driver.set("prone_axis_max_correction_deg", 0.0)
	player.call("_try_set_posture", 2)
	Input.action_press(&"move_forward")
	for _frame in range(75):
		await physics_frame
	Input.action_release(&"move_forward")
	for _frame in range(4):
		await physics_frame

	var skeleton: Skeleton3D = driver.get("skeleton")
	_expect(skeleton != null, "production skeleton exists")
	if skeleton != null:
		var samples: Dictionary = {}
		for bone_name in [
			"mixamorig_Hips", "mixamorig_LeftUpLeg", "mixamorig_LeftLeg",
			"mixamorig_LeftFoot", "mixamorig_LeftToeBase", "mixamorig_RightUpLeg",
			"mixamorig_RightLeg", "mixamorig_RightFoot", "mixamorig_RightToeBase",
			"mixamorig_Head",
		]:
			var bone_index := skeleton.find_bone(bone_name)
			if bone_index >= 0:
				samples[bone_name] = (
					skeleton.global_transform
					* skeleton.get_bone_global_pose(bone_index).origin
				)
		# Measure the actual collision surface under the operator. Authored maps may
		# place the floor above world Y=0, so absolute bone heights made this check
		# map-offset dependent even when contact was unchanged.
		var floor_y := 0.0
		var ground_query := PhysicsRayQueryParameters3D.create(
			player.global_position + Vector3.UP * 2.0,
			player.global_position + Vector3.DOWN * 3.0
		)
		ground_query.exclude = [player.get_rid()]
		var ground_hit: Dictionary = player.get_world_3d().direct_space_state.intersect_ray(ground_query)
		if not ground_hit.is_empty():
			floor_y = float((ground_hit.get("position", Vector3.ZERO) as Vector3).y)
		var left_foot_height := float((samples.get("mixamorig_LeftFoot", Vector3.UP * 99.0) as Vector3).y - floor_y)
		var right_foot_height := float((samples.get("mixamorig_RightFoot", Vector3.UP * 99.0) as Vector3).y - floor_y)
		var left_knee_height := float((samples.get("mixamorig_LeftLeg", Vector3.UP * 99.0) as Vector3).y - floor_y)
		var right_knee_height := float((samples.get("mixamorig_RightLeg", Vector3.UP * 99.0) as Vector3).y - floor_y)
		print(
			"PRONE_GROUND_METRIC floor_y=%.4f left_foot_m=%.4f right_foot_m=%.4f left_knee_m=%.4f right_knee_m=%.4f"
			% [floor_y, left_foot_height, right_foot_height, left_knee_height, right_knee_height]
		)
		var debug: Dictionary = driver.call("get_animation_debug_state")
		var axis_error := absf(float(debug.get("prone_axis_residual_error_deg", 999.0)))
		print(
			"PRONE_GROUND_METRIC axis_error_deg=%.4f"
			% axis_error
		)
		_expect(
			minf(left_foot_height, right_foot_height) <= 0.18
			and maxf(left_foot_height, right_foot_height) <= 0.32,
			"forward-prone crawl keeps one planted foot while bounding the moving foot"
		)
		_expect(
			minf(left_knee_height, right_knee_height) <= 0.05
			and maxf(left_knee_height, right_knee_height) <= 0.16
			and minf(left_knee_height, right_knee_height) >= -0.08,
			"forward-prone crawl keeps one support knee grounded and the moving knee bounded"
		)
		_expect(
			axis_error <= 1.0,
			"grounded prone pelvis, spine, and head remain stacked for W travel"
		)

	scene.queue_free()
	await process_frame
	_finish()


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("PRONE_GROUND_CHECK PASS ", label)
	else:
		failures.append(label)
		push_error("PRONE_GROUND_CHECK FAIL %s" % label)


func _finish() -> void:
	Input.action_release(&"move_forward")
	if failures.is_empty():
		print("PRONE_GROUNDING_REGRESSION PASS")
		quit(0)
	else:
		print("PRONE_GROUNDING_REGRESSION FAIL ", failures)
		quit(1)
