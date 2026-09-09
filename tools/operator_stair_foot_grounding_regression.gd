extends SceneTree

const EXPECTED_WRITTEN_BONES: Array[StringName] = [
	&"mixamorig_LeftUpLeg", &"mixamorig_LeftLeg", &"mixamorig_LeftFoot",
	&"mixamorig_RightUpLeg", &"mixamorig_RightLeg", &"mixamorig_RightFoot",
]

var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var physics_ticks_before := Engine.physics_ticks_per_second
	var packed := load("res://main.tscn") as PackedScene
	_expect(packed != null, "canonical main scene loads")
	if packed == null:
		_finish()
		return
	var scene := packed.instantiate() as Node3D
	root.add_child(scene)
	for _frame in range(30):
		await physics_frame
	var player := scene.get_node_or_null("Player") as CharacterBody3D
	var driver := (
		player.get_node_or_null("Mannequin/ProductionAnimation")
		if player != null else null
	)
	var foot_lock = driver.foot_contact_lock if driver != null else null
	_expect(player != null and driver != null and foot_lock != null, "live foot-grounding owner exists")
	if player == null or driver == null or foot_lock == null:
		_finish()
		return

	var skeleton := driver.skeleton as Skeleton3D
	var skeleton_priority_before := skeleton.process_priority
	var callback_mode_before := skeleton.modifier_callback_mode_process
	_expect(
		foot_lock.left_ground_ray is RayCast3D
		and foot_lock.right_ground_ray is RayCast3D,
		"owner creates exactly two RayCast3D foot probes"
	)
	_expect(
		foot_lock.get_child_count() == 2,
		"foot owner has no self-running IK helper nodes"
	)
	_expect(
		foot_lock.grounding_modifier is SocomOperatorFootGroundingModifier,
		"one leg-only SkeletonModifier3D consumes both contacts"
	)
	_expect(
		skeleton.get_node_or_null("LeftFootContactIK") == null
		and skeleton.get_node_or_null("RightFootContactIK") == null,
		"deprecated SkeletonIK3D foot solvers are absent"
	)

	foot_lock.set_collision_mask_for_test(2)
	foot_lock.set_invariance_probe_enabled(true)
	var left_foot_index := skeleton.find_bone(&"mixamorig_LeftFoot")
	var right_foot_index := skeleton.find_bone(&"mixamorig_RightFoot")
	var left_foot_world := (
		skeleton.global_transform * skeleton.get_bone_global_pose(left_foot_index)
	).origin
	var step_height := 0.18
	var step := _make_step(
		Vector3(left_foot_world.x, player.global_position.y, left_foot_world.z),
		step_height
	)
	scene.add_child(step)
	await physics_frame

	driver.set_visual_inputs(
		Vector2.ZERO, &"STANDING", 0.0, 0.0, 0.0, false, 0.0,
		0.0, &"STANDING", 0.0, &"WALK", 0.0
	)
	for _frame in range(18):
		await process_frame
	var grounded: Dictionary = foot_lock.get_debug_state()
	var modifier: Dictionary = grounded.get("modifier", {})
	_expect(int(grounded.get("ray_count", 0)) == 2, "grounding performs two probes only")
	_expect(bool(grounded.get("left_ray_hit", false)), "left probe detects the isolated stair tread")
	_expect(
		float(grounded.get("left_offset_m", 0.0)) >= step_height - 0.025,
		"left target reaches the 18 cm stair height"
	)
	_expect(bool(grounded.get("active", false)), "standing grounding activates on a valid tread")
	_expect(int(modifier.get("process_count", 0)) > 0, "leg-only modifier processes rendered poses")
	_expect(
		float(modifier.get("left_error_m", INF)) <= 0.035,
		"left boot reaches within 3.5 cm of the resolved stair contact"
	)
	_expect(
		Array(modifier.get("written_bones", [])) == EXPECTED_WRITTEN_BONES,
		"modifier declares only the six leg bones"
	)
	_expect(
		float(modifier.get("protected_translation_delta_m", INF)) <= 0.000001,
		"grounding does not translate hips, spine, shoulders, arms, or hands"
	)
	_expect(
		float(modifier.get("protected_rotation_delta_deg", INF)) <= 0.001,
		"grounding does not rotate hips, spine, shoulders, arms, or hands"
	)
	_expect(
		float(grounded.get("body_translation_delta_m", INF)) <= 0.000001
		and float(grounded.get("body_velocity_delta_mps", INF)) <= 0.000001,
		"grounding never writes CharacterBody transform or velocity"
	)
	_expect(
		skeleton.process_priority == skeleton_priority_before
		and skeleton.modifier_callback_mode_process == callback_mode_before,
		"grounding does not change shared skeleton timing"
	)
	_expect(
		Engine.physics_ticks_per_second == physics_ticks_before,
		"grounding does not change global physics timing"
	)

	var right_foot_world := (
		skeleton.global_transform * skeleton.get_bone_global_pose(right_foot_index)
	).origin
	step.global_position = Vector3(
		right_foot_world.x,
		player.global_position.y + step_height * 0.5,
		right_foot_world.z
	)
	await physics_frame
	for _frame in range(18):
		await process_frame
	var right_grounded: Dictionary = foot_lock.get_debug_state()
	var right_modifier: Dictionary = right_grounded.get("modifier", {})
	_expect(
		bool(right_grounded.get("right_ray_hit", false)),
		"right probe detects the isolated stair tread"
	)
	_expect(
		float(right_grounded.get("right_offset_m", 0.0)) >= step_height - 0.025,
		"right target reaches the 18 cm stair height"
	)
	_expect(
		float(right_modifier.get("right_error_m", INF)) <= 0.035,
		"right boot reaches within 3.5 cm of the resolved stair contact"
	)

	var mannequin := player.get_node_or_null("Mannequin")
	if mannequin != null:
		mannequin.set_process(false)
	driver.set_visual_inputs(
		Vector2.ZERO, &"STANDING", 0.0, 0.0, 1.0, true, 0.0,
		0.0, &"STANDING", 0.0, &"WALK", 0.0
	)
	for _frame in range(3):
		await process_frame
	var fire_state: Dictionary = foot_lock.get_debug_state()
	_expect(
		bool(fire_state.get("protected_pose_active", false))
		and not bool(fire_state.get("active", true)),
		"fire and fire recovery disable foot grounding immediately"
	)
	driver.set_visual_inputs(
		Vector2.ZERO, &"CROUCHED", 0.0, 0.0, 0.0, false, 0.0,
		0.0, &"CROUCHED", 0.0, &"WALK", 0.0
	)
	# Recovery deliberately protects the authored fire pose. Wait for the real
	# owner to release that protection before testing unrelated crouch contact;
	# a fixed eight render frames is shorter than the accepted fire hold.
	for _frame in range(600):
		await process_frame
		if not bool(foot_lock.get_debug_state().get("protected_pose_active", true)):
			break
	_expect(not bool(foot_lock.get_debug_state().get("protected_pose_active", true)), "fire recovery releases grounding protection")
	var crouched_left_world := (
		skeleton.global_transform * skeleton.get_bone_global_pose(left_foot_index)
	).origin
	step.global_position = Vector3(
		crouched_left_world.x,
		player.global_position.y + step_height * 0.5,
		crouched_left_world.z
	)
	await physics_frame
	for _frame in range(16):
		await process_frame
	var crouch_state: Dictionary = foot_lock.get_debug_state()
	print("OPERATOR_STAIR_CROUCH_STATE ", JSON.stringify(crouch_state))
	_expect(
		bool(crouch_state.get("active", false))
		and bool(crouch_state.get("left_ray_hit", false)),
		"crouched grounding uses the same bounded stair-contact path"
	)

	foot_lock.apply(
		Vector2.ZERO, 0.0, &"CROUCHED", &"CROUCHED", &"reload", 1.0 / 60.0, false
	)
	var reload_state: Dictionary = foot_lock.get_debug_state()
	_expect(
		bool(reload_state.get("protected_pose_active", false))
		and not bool(reload_state.get("active", true)),
		"reload disables foot grounding immediately"
	)

	print("OPERATOR_STAIR_GROUNDING_STATE %s" % JSON.stringify(grounded))
	_finish()


func _make_step(base: Vector3, height: float) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "GroundingRegressionStep"
	body.collision_layer = 2
	body.collision_mask = 0
	body.position = base + Vector3.UP * (height * 0.5)
	var shape_node := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.24, height, 0.24)
	shape_node.shape = shape
	body.add_child(shape_node)
	return body


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("OPERATOR_STAIR_GROUNDING_CHECK PASS %s" % label)
		return
	failures.append(label)
	push_error("OPERATOR_STAIR_GROUNDING_CHECK FAIL %s" % label)


func _finish() -> void:
	if failures.is_empty():
		print("OPERATOR_STAIR_FOOT_GROUNDING_REGRESSION PASS")
		quit(0)
	else:
		print("OPERATOR_STAIR_FOOT_GROUNDING_REGRESSION FAIL %s" % [failures])
		quit(1)
