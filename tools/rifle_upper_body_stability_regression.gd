extends SceneTree

## Focused proof for AK_M4_UPPER_BODY_STABILITY_DIAGNOSIS.md.
const Posture := preload("res://scripts/player/operator_posture_layer.gd")
const Driver := preload("res://scripts/player/operator_animation_driver_runtime.gd")
const Graph := preload("res://scripts/player/operator_locomotion_blend_tree.gd")
var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var skeleton := Skeleton3D.new()
	root.add_child(skeleton)
	skeleton.transform = Transform3D(Basis.from_euler(Vector3(0.1, 0.47, -0.08)).scaled(Vector3.ONE * 1.6), Vector3(3, 2, -5))
	_add_bone(skeleton, "mixamorig_Hips", -1, Vector3(0, 1, 0))
	_add_bone(skeleton, "mixamorig_Spine", 0, Vector3(0, 0.2, 0))
	_add_bone(skeleton, "mixamorig_Head", 1, Vector3(0, 0.4, 0))
	_add_bone(skeleton, "mixamorig_LeftUpLeg", 0, Vector3(-0.1, -0.2, 0))
	skeleton.set_bone_pose_rotation(0, Quaternion.from_euler(Vector3(0.11, 0.6, -0.09)))
	var owner := Posture.new()
	owner.bind(skeleton)
	var hip_min := INF
	var hip_max := -INF
	var head_min := INF
	var head_max := -INF
	for frame in 80:
		skeleton.set_bone_pose_position(0, Vector3(0, 1 + sin(float(frame) * TAU / 80.0) * 0.03, 0))
		skeleton.set_bone_pose_rotation(1, Quaternion.IDENTITY)
		var hip_before := skeleton.get_bone_global_pose(0)
		var leg_before := skeleton.get_bone_global_pose(3)
		owner.apply(0.0, 0.0, 0.0, 0.0, 0.0, 1.0, 1.0, 1.0, 1.0,
			1.0, 0.0, 0.0, PI * 0.5, 0.0, &"STANDING", 0.0, Vector3.ZERO,
			0.0, false, false, false, 1.0, false, 0.0, 0.0, 0.0, 0.0, 1.0, 1.0)
		_expect(skeleton.get_bone_global_pose(0).is_equal_approx(hip_before), "rotation isolation leaves hip unchanged")
		_expect(skeleton.get_bone_global_pose(3).is_equal_approx(leg_before), "rotation isolation leaves leg unchanged")
		_expect(skeleton.get_bone_pose_position(1).is_equal_approx(Vector3(0, 0.2, 0)), "no Spine position suppression remains")
		hip_min = minf(hip_min, _world(skeleton, 0).y)
		hip_max = maxf(hip_max, _world(skeleton, 0).y)
		head_min = minf(head_min, _world(skeleton, 2).y)
		head_max = maxf(head_max, _world(skeleton, 2).y)
	_expect(hip_max - hip_min > 0.08, "source hip bob remains present")
	_expect(head_max - head_min > 0.08, "natural hip-driven head bob remains present")
	_expect(absf((head_max - head_min) - (hip_max - hip_min)) < 0.00001, "head retains the full source vertical cycle")
	_check_rotation_basis(skeleton)
	_check_driver_scope()
	skeleton.queue_free()
	await process_frame
	print("RIFLE_UPPER_BODY_STABILITY ", "PASS" if failures.is_empty() else "FAIL", " natural_hip_range_m=", hip_max - hip_min, " natural_head_range_m=", head_max - head_min, " ", failures)
	quit(0 if failures.is_empty() else 1)


func _check_rotation_basis(skeleton: Skeleton3D) -> void:
	var spine_rest := Quaternion.from_euler(Vector3(0.2, -0.1, 0.12))
	skeleton.set_bone_rest(1, Transform3D(Basis(spine_rest), Vector3(0, 0.2, 0)))
	skeleton.set_bone_pose_rotation(0, Quaternion.IDENTITY)
	skeleton.set_bone_pose_rotation(1, spine_rest)
	var expected := skeleton.get_bone_global_pose(2).basis.get_rotation_quaternion().normalized()
	var owner := Posture.new()
	owner.bind(skeleton)
	var max_legacy_error := 0.0
	var max_exact_error := 0.0
	for frame in 40:
		skeleton.set_bone_pose_rotation(0, Quaternion.from_euler(Vector3(0.12, 0.6, sin(float(frame) * TAU / 40.0) * 0.1)))
		var legacy := owner._upper_body_hip_correction(&"STANDING", 1.0, 0.0)
		skeleton.set_bone_pose_rotation(1, legacy * spine_rest)
		max_legacy_error = maxf(max_legacy_error, rad_to_deg(expected.angle_to(skeleton.get_bone_global_pose(2).basis.get_rotation_quaternion().normalized())))
		# Bone pose already includes the rest rotation. Undo the legacy extra
		# conjugation before the same left-multiplied local-pose operation.
		var exact := owner._upper_body_hip_correction(&"STANDING", 1.0, 0.0, 0.0, 0.0, 1.0)
		var expected_exact := (spine_rest * legacy * spine_rest.inverse()).normalized()
		_expect(rad_to_deg(exact.angle_to(expected_exact)) < 0.06, "scoped exact route matches evaluated local-pose correction")
		for fade: float in [0.0, 0.25, 0.5, 0.75, 1.0]:
			var blended := owner._upper_body_hip_correction(&"STANDING", 1.0, 0.0, 0.0, 0.0, fade)
			_expect(rad_to_deg(blended.angle_to(legacy.slerp(exact, fade))) < 0.06, "exact rotation uses continuous existing movement gate")
		skeleton.set_bone_pose_rotation(1, exact * spine_rest)
		max_exact_error = maxf(max_exact_error, rad_to_deg(expected.angle_to(skeleton.get_bone_global_pose(2).basis.get_rotation_quaternion().normalized())))
	_expect(max_legacy_error > 1.0, "nonidentity-rest fixture exposes legacy compensation residual")
	_expect(max_exact_error < 0.06, "evaluated local-pose correction cancels hip rotation exactly")
	print("RIFLE_HIP_BASIS_DIAGNOSTIC legacy_error_deg=", max_legacy_error, " exact_error_deg=", max_exact_error)


func _check_driver_scope() -> void:
	var driver := Driver.new()
	driver.locomotion_graph = Graph.new()
	driver.use_modern_locomotion = true
	driver.locomotion_graph.locomotion_carry_weight = 0.759
	driver.equipped_weapon_handling_profile = {"dynamic_hold": {"strafe_carry": {"right_hip_follow_weight": 1.0, "left_elbow_flare_degrees": 12.0}}}
	for stance: StringName in [&"STANDING", &"CROUCHED"]:
		driver.posture = stance
		for direction: Vector2 in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2(0.7071068, -0.7071068)]:
			driver.locomotion_graph.rendered_direction = direction
			for ready: float in [0.0, 0.5, 1.0]:
				driver._presentation_ready_weight = ready
				_expect(is_equal_approx(driver._left_strafe_shoulder_square_weight(), 1.0), "all scoped moving directions own square baseline")
				var expected: float = asin(maxf(direction.normalized().x, 0.0)) * ready
				_expect(absf(driver._right_strafe_shoulder_yaw() - expected) < 0.0001, "D target follows only existing readiness")
				if ready == 0.0:
					_expect(is_zero_approx(driver._right_strafe_hip_follow()), "relaxed D has no retained hip turn")
	driver.requested_action = &"RELOAD"
	_expect(is_zero_approx(driver._rifle_movement_stability_weight()), "reload excluded")
	driver.requested_action = &""
	for movement: StringName in [&"AIRBORNE", &"LANDING", &"DIVING", &"ROLLING"]:
		driver.movement_state = movement
		_expect(is_zero_approx(driver._rifle_movement_stability_weight()), "mobility excluded")
	driver.movement_state = &"IDLE"
	driver.posture = &"PRONE"
	_expect(is_zero_approx(driver._rifle_movement_stability_weight()), "driver prone excluded")
	driver.posture = &"STANDING"
	driver.equipped_weapon_handling_profile = {}
	_expect(is_zero_approx(driver._rifle_movement_stability_weight()), "other weapons without saved opt-in unchanged")
	driver.free()


func _add_bone(skeleton: Skeleton3D, name: String, parent: int, position: Vector3) -> void:
	var index := skeleton.get_bone_count()
	skeleton.add_bone(name)
	skeleton.set_bone_parent(index, parent)
	skeleton.set_bone_rest(index, Transform3D(Basis.IDENTITY, position))
	skeleton.reset_bone_pose(index)


func _world(skeleton: Skeleton3D, index: int) -> Vector3:
	return skeleton.global_transform * skeleton.get_bone_global_pose(index).origin


func _expect(ok: bool, description: String) -> void:
	if not ok and not failures.has(description):
		failures.append(description)
