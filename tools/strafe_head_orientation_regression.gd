extends SceneTree

## Exact world-orientation proof for the existing posture writer.
const Posture := preload("res://scripts/player/operator_posture_layer.gd")
var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var skeleton := Skeleton3D.new()
	root.add_child(skeleton)
	skeleton.transform = Transform3D(Basis.from_euler(Vector3(0.12, 0.47, -0.08)), Vector3(3, 2, -5))
	_add_bone(skeleton, "mixamorig_Hips", -1, Vector3(0, 1, 0), Vector3(0.04, -0.06, 0.03))
	_add_bone(skeleton, "mixamorig_Spine", 0, Vector3(0, 0.2, 0), Vector3(0.17, -0.11, 0.09))
	_add_bone(skeleton, "mixamorig_Spine1", 1, Vector3(0, 0.15, 0), Vector3(-0.04, 0.09, 0.02))
	_add_bone(skeleton, "mixamorig_Spine2", 2, Vector3(0, 0.15, 0), Vector3(0.02, -0.08, 0.03))
	_add_bone(skeleton, "mixamorig_Neck", 3, Vector3(0, 0.15, 0), Vector3(0.11, 0.08, -0.12))
	_add_bone(skeleton, "mixamorig_Head", 4, Vector3(0, 0.12, 0), Vector3(-0.04, 0.06, 0.03))
	_add_bone(skeleton, "mixamorig_RightShoulder", 3, Vector3(0.15, 0.06, 0), Vector3(0, 0.08, 0.04))
	_add_bone(skeleton, "mixamorig_LeftShoulder", 3, Vector3(-0.15, 0.06, 0), Vector3(0, -0.05, -0.03))
	_add_bone(skeleton, "mixamorig_RightArm", 6, Vector3(0.15, 0, 0), Vector3(0, 0, -0.1))
	_add_bone(skeleton, "mixamorig_LeftArm", 7, Vector3(-0.15, 0, 0), Vector3(0, 0, 0.1))
	var source: Array[Quaternion] = []
	for index in skeleton.get_bone_count():
		source.append(skeleton.get_bone_pose_rotation(index))
	source[0] = Quaternion.from_euler(Vector3(0.13, 0.71, -0.06))
	source[3] = source[3] * Quaternion(Vector3.UP, 0.4)
	var cases := 0
	for stance: StringName in [&"STANDING", &"CROUCHED"]:
		for ready: float in [0.0, 0.35, 1.0]:
			for separation: float in [0.0, 0.35, 1.0]:
				var baseline := Posture.new()
				baseline.bind(skeleton)
				_reset(skeleton, source)
				_apply_frame(baseline, stance, ready, separation, 0.0)
				var baseline_head := _world_rotation(skeleton, 5)
				var baseline_shoulder := _world_rotation(skeleton, 6)
				var candidate := Posture.new()
				candidate.bind(skeleton)
				_reset(skeleton, source)
				_apply_frame(candidate, stance, ready, separation, 1.0)
				var head := _world_rotation(skeleton, 5)
				var shoulder := _world_rotation(skeleton, 6)
				var head_error := rad_to_deg(head.angle_to(baseline_head))
				var shoulder_turn := rad_to_deg(shoulder.angle_to(baseline_shoulder))
				var label := "%s ready=%.2f separation=%.2f" % [stance, ready, separation]
				_expect(head_error < 0.06, label + " preserves world head orientation")
				_expect(shoulder_turn > 0.3 if separation > 0.0 else shoulder_turn < 0.06, label + " preserves expected torso turn")
				var first_head := skeleton.get_bone_pose_rotation(5)
				var first_neck := skeleton.get_bone_pose_rotation(4)
				for frame in 12:
					# The graph refreshes the body, while an unkeyed/frozen head can
					# retain this writer's result. Exercise its existing base cache.
					_reset(skeleton, source, true)
					_apply_frame(candidate, stance, ready, separation, 1.0)
				_expect(rad_to_deg(_world_rotation(skeleton, 5).angle_to(head)) < 0.06, label + " frozen head does not accumulate")
				_expect(rad_to_deg(skeleton.get_bone_pose_rotation(5).angle_to(first_head)) < 0.06 and rad_to_deg(skeleton.get_bone_pose_rotation(4).angle_to(first_neck)) < 0.06, label + " neck/head cache is stable")
				candidate.clear_head_look_additive()
				_expect(rad_to_deg(skeleton.get_bone_pose_rotation(4).angle_to(source[4])) < 0.06 and rad_to_deg(skeleton.get_bone_pose_rotation(5).angle_to(source[5])) < 0.06, label + " clear restores authored head")
				print("STRAFE_HEAD_METRIC ", label, " head_error_deg=", head_error, " shoulder_turn_deg=", shoulder_turn)
				cases += 1
	_check_left_square(skeleton, source)
	_check_right_target(skeleton, source)
	_check_exact_scope_head(skeleton, source)
	skeleton.queue_free()
	await process_frame
	print("STRAFE_HEAD_ORIENTATION ", "PASS" if failures.is_empty() else "FAIL", " cases=", cases, " ", failures)
	quit(0 if failures.is_empty() else 1)


func _check_left_square(skeleton: Skeleton3D, source: Array[Quaternion]) -> void:
	var target := Vector3(3, 1, -40)
	for stance: StringName in [&"STANDING", &"CROUCHED"]:
		for ready: float in [0.0, 0.35, 1.0]:
			var baseline := Posture.new()
			baseline.bind(skeleton)
			_reset(skeleton, source)
			_apply_frame(baseline, stance, ready, 1.0, 0.0, 0.0, target)
			var before_head := _world_rotation(skeleton, 5)
			var before_shoulder := _world_rotation(skeleton, 6)
			var before_error := _shoulder_error(skeleton, target)
			var candidate := Posture.new()
			candidate.bind(skeleton)
			_reset(skeleton, source)
			_apply_frame(candidate, stance, ready, 1.0, 0.0, 1.0, target)
			var error := _shoulder_error(skeleton, target)
			var head_error := rad_to_deg(_world_rotation(skeleton, 5).angle_to(before_head))
			var label := "%s left ready=%.2f" % [stance, ready]
			_expect(before_error > 5.0 and error < 0.06, label + " visible shoulder bar squares toward reticle")
			_expect(rad_to_deg(_world_rotation(skeleton, 6).angle_to(before_shoulder)) > 0.3, label + " chest really turns")
			_expect(head_error < 0.06, label + " world head orientation survives chest square")
			for frame in 12:
				_reset(skeleton, source, true)
				_apply_frame(candidate, stance, ready, 1.0, 0.0, 1.0, target)
			_expect(rad_to_deg(_world_rotation(skeleton, 5).angle_to(before_head)) < 0.06, label + " frozen head does not accumulate chest counter")
			print("STRAFE_LEFT_METRIC ", label, " before_error_deg=", before_error, " after_error_deg=", error, " head_error_deg=", head_error)


func _check_right_target(skeleton: Skeleton3D, source: Array[Quaternion]) -> void:
	var target := Vector3(3, 1, -40)
	for degrees: float in [45.0, 90.0]:
		var baseline := Posture.new()
		baseline.bind(skeleton)
		_reset(skeleton, source)
		_apply_frame(baseline, &"STANDING", 1.0, 1.0, 0.0, 0.0, target)
		var before_head := _world_rotation(skeleton, 5)
		var candidate := Posture.new()
		candidate.bind(skeleton)
		_reset(skeleton, source)
		_apply_frame(candidate, &"STANDING", 1.0, 1.0, 0.0, 0.0, target, deg_to_rad(degrees))
		var error := _shoulder_error(skeleton, target, deg_to_rad(degrees))
		var head_error := rad_to_deg(_world_rotation(skeleton, 5).angle_to(before_head))
		# A source requiring more than 90 degrees must stop at the safety cap,
		# not turn the other way and masquerade as a correct unsigned bar.
		_expect(head_error < 0.06, "right %.0f preserves head orientation" % degrees)
		_expect(float(candidate.last_chest_square_correction_deg) <= 90.01, "right %.0f keeps scoped correction bound" % degrees)
		_expect(absf(error - float(candidate.last_directional_shoulder_error_deg)) < 0.1, "right %.0f reports directed physical error, not unsigned axis" % degrees)
		print("STRAFE_RIGHT_METRIC target_deg=", degrees, " directed_error_deg=", error, " head_error_deg=", head_error, " applied_deg=", candidate.last_chest_square_correction_deg)
	# A right-turning pelvis is a negative local-Y rotation on this fixture.
	# Retain that authored baseline before targeting the chest; it should reduce
	# the spinal correction while the combined head counter still removes both.
	var right_source := source.duplicate()
	right_source[0] = Quaternion.from_euler(Vector3(0.13, -1.4, -0.06))
	for retained: float in [0.75, 1.0]:
		var baseline := Posture.new()
		baseline.bind(skeleton)
		_reset(skeleton, right_source)
		_apply_frame(baseline, &"STANDING", 1.0, 1.0, 0.0, 0.0, target)
		var before_head := _world_rotation(skeleton, 5)
		var candidate := Posture.new()
		candidate.bind(skeleton)
		_reset(skeleton, right_source)
		_apply_frame(candidate, &"STANDING", 1.0, 1.0, retained, 0.0, target, PI * 0.5)
		var error := _shoulder_error(skeleton, target, PI * 0.5)
		var head_error := rad_to_deg(_world_rotation(skeleton, 5).angle_to(before_head))
		_expect(error < 0.1, "right-hip baseline reaches directed90 target")
		_expect(head_error < 0.06, "composed hip/chest counter preserves head")
		print("STRAFE_RIGHT_BASELINE_METRIC retention=", retained, " directed_error_deg=", error, " head_error_deg=", head_error, " applied_deg=", candidate.last_chest_square_correction_deg)


func _shoulder_error(skeleton: Skeleton3D, target: Vector3, right_yaw: float = 0.0) -> float:
	var left := skeleton.global_transform * skeleton.get_bone_global_pose(9).origin
	var right := skeleton.global_transform * skeleton.get_bone_global_pose(8).origin
	var facing := target - (left + right) * 0.5
	facing.y = 0.0
	var desired_right := facing.normalized().cross(Vector3.UP).normalized()
	if right_yaw > 0.0:
		var reference := skeleton.global_basis * (skeleton.get_bone_global_rest(8).origin - skeleton.get_bone_global_rest(9).origin)
		if reference.dot(desired_right) < 0.0:
			desired_right = -desired_right
		desired_right = desired_right.rotated(Vector3.UP, -right_yaw)
	var shoulder_right := (right - left).normalized()
	if right_yaw > 0.0:
		shoulder_right.y = 0.0
		return rad_to_deg(acos(clampf(shoulder_right.normalized().dot(desired_right), -1.0, 1.0)))
	return rad_to_deg(acos(clampf(absf(shoulder_right.dot(desired_right)), 0.0, 1.0)))


func _check_exact_scope_head(skeleton: Skeleton3D, source: Array[Quaternion]) -> void:
	var right_source := source.duplicate()
	right_source[0] = Quaternion.from_euler(Vector3(0.13, -1.4, -0.06))
	for stance: StringName in [&"STANDING", &"CROUCHED"]:
		for ready: float in [0.0, 0.5, 1.0]:
			for scope: float in [0.25, 0.5, 1.0]:
				var baseline := Posture.new()
				baseline.bind(skeleton)
				_reset(skeleton, right_source)
				_apply_frame(baseline, stance, ready, 1.0, 0.0, 0.0, Vector3.ZERO, 0.0, scope)
				var expected := _world_rotation(skeleton, 5)
				var candidate := Posture.new()
				candidate.bind(skeleton)
				_reset(skeleton, right_source)
				_apply_frame(candidate, stance, ready, 1.0, ready, 1.0, Vector3(3, 1, -40), PI * 0.5 * ready, scope)
				var error := rad_to_deg(expected.angle_to(_world_rotation(skeleton, 5)))
				_expect(error < 0.06, "exact scoped hip/chest compensation preserves world head")
				for frozen in 8:
					_reset(skeleton, right_source, true)
					_apply_frame(candidate, stance, ready, 1.0, ready, 1.0, Vector3(3, 1, -40), PI * 0.5 * ready, scope)
				_expect(rad_to_deg(expected.angle_to(_world_rotation(skeleton, 5))) < 0.06, "exact scoped frozen head remains stable")
				print("STRAFE_EXACT_HEAD_METRIC ", stance, " ready=", ready, " scope=", scope, " error_deg=", error)


func _apply_frame(layer: RefCounted, stance: StringName, ready: float, separation: float, retained: float, left_square: float = 0.0, target: Vector3 = Vector3.ZERO, right_yaw: float = 0.0, exact_scope: float = 0.0) -> void:
	layer.apply(0.23, -0.14, ready, 0.0, 0.0, 1.0, 1.0, 1.0, 1.0,
		separation, 0.18, 0.0, deg_to_rad(90.0), 0.0, stance,
		0.0, target, 0.0, false, false, false, 1.0, false, 0.0, retained, left_square, right_yaw, 1.0, exact_scope)


func _reset(skeleton: Skeleton3D, source: Array[Quaternion], keep_head: bool = false) -> void:
	for index in source.size():
		if keep_head and index in [4, 5]:
			continue
		skeleton.set_bone_pose_rotation(index, source[index])
	skeleton.force_update_all_bone_transforms()


func _world_rotation(skeleton: Skeleton3D, index: int) -> Quaternion:
	return (skeleton.global_basis * skeleton.get_bone_global_pose(index).basis).orthonormalized().get_rotation_quaternion().normalized()


func _add_bone(skeleton: Skeleton3D, name: String, parent: int, offset: Vector3, angles: Vector3) -> void:
	skeleton.add_bone(name)
	var index := skeleton.get_bone_count() - 1
	skeleton.set_bone_parent(index, parent)
	var rest := Transform3D(Basis.from_euler(angles), offset)
	skeleton.set_bone_rest(index, rest)
	skeleton.set_bone_pose(index, rest)


func _expect(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		push_error("STRAFE_HEAD_CHECK FAIL " + label)
