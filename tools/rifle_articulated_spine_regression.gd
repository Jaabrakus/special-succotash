extends SceneTree

## Mathematical proof for the scoped articulated hip-counter translation.
## Same final chest/head rotation; existing three spine weights; no translations
## or hips/leg writes. Native waist/armor and physical palms remain separate gates.
const Posture := preload("res://scripts/player/operator_posture_layer.gd")
var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var skeleton := Skeleton3D.new()
	root.add_child(skeleton)
	skeleton.transform = Transform3D(Basis.from_euler(Vector3(0.15, 0.7, -0.1)).scaled(Vector3(1.3, 1.7, 0.9)), Vector3(3, 2, -4))
	var names: Array[String] = ["mixamorig_Hips", "mixamorig_Spine", "mixamorig_Spine1", "mixamorig_Spine2", "mixamorig_Neck", "mixamorig_Head", "mixamorig_LeftUpLeg"]
	for index in names.size():
		skeleton.add_bone(names[index])
		skeleton.set_bone_parent(index, index - 1 if index < 6 else 0)
		var position := Vector3(0.01 * index, 0.15, -0.015 * index) if index > 0 else Vector3(0, 1, 0)
		if index == 6:
			position = Vector3(-0.1, -0.3, 0.01)
		skeleton.set_bone_rest(index, Transform3D(Basis.from_euler(Vector3(0.03 * index, -0.02 * index, 0.01 * index)), position))
		skeleton.reset_bone_pose(index)
	var owner := Posture.new()
	owner.bind(skeleton)
	var random := RandomNumberGenerator.new()
	random.seed = 141
	var maximum_chest_error := 0.0
	var maximum_head_error := 0.0
	for sample in 12:
		var source: Array[Quaternion] = []
		for index in names.size():
			# These evaluated bases include nonidentity rest and local aim terms.
			var q := skeleton.get_bone_rest(index).basis.get_rotation_quaternion().normalized()
			q = q * Quaternion.from_euler(Vector3(random.randf_range(-0.15, 0.15), random.randf_range(-0.7, 0.7), random.randf_range(-0.12, 0.12)))
			source.append(q.normalized())
		var counter := Quaternion.from_euler(Vector3(0.12, deg_to_rad(-95.0 + sample * 17.0), -0.07)).normalized()
		_reset(skeleton, source)
		skeleton.set_bone_pose_rotation(1, counter * source[1])
		var expected_chest := skeleton.get_bone_global_pose(3).basis.orthonormalized().get_rotation_quaternion().normalized()
		var expected_head := skeleton.get_bone_global_pose(5).basis.orthonormalized().get_rotation_quaternion().normalized()
		for weight: float in [0.0, 0.25, 0.5, 0.75, 1.0]:
			_reset(skeleton, source)
			var hips_before := skeleton.get_bone_global_pose(0)
			var leg_before := skeleton.get_bone_global_pose(6)
			owner._apply_articulated_hip_correction(counter, weight)
			var chest_error := rad_to_deg(expected_chest.angle_to(skeleton.get_bone_global_pose(3).basis.orthonormalized().get_rotation_quaternion().normalized()))
			var head_error := rad_to_deg(expected_head.angle_to(skeleton.get_bone_global_pose(5).basis.orthonormalized().get_rotation_quaternion().normalized()))
			maximum_chest_error = maxf(maximum_chest_error, chest_error)
			maximum_head_error = maxf(maximum_head_error, head_error)
			_expect(chest_error < 0.06 and head_error < 0.06, "same net chest and head rotations across mixed poses/fades")
			_expect(hips_before.is_equal_approx(skeleton.get_bone_global_pose(0)) and leg_before.is_equal_approx(skeleton.get_bone_global_pose(6)), "hip and leg transforms unchanged")
			for index in names.size():
				_expect(skeleton.get_bone_pose_position(index).is_equal_approx(skeleton.get_bone_rest(index).origin), "no bone position writes")
			if weight == 0.0:
				_expect(rad_to_deg(skeleton.get_bone_pose_rotation(1).angle_to(counter * source[1])) < 0.06, "zero distribution is original Spine-only correction")
			if weight == 1.0:
				var first_joint := source[1].angle_to(skeleton.get_bone_pose_rotation(1))
				_expect(first_joint < counter.get_angle() * 0.25, "first waist joint takes only bounded share of counter")
	skeleton.queue_free()
	await process_frame
	print("RIFLE_ARTICULATED_SPINE ", "PASS" if failures.is_empty() else "FAIL", " cases=60 max_chest_error_deg=", maximum_chest_error, " max_head_error_deg=", maximum_head_error, " ", failures)
	quit(0 if failures.is_empty() else 1)


func _reset(skeleton: Skeleton3D, source: Array[Quaternion]) -> void:
	for index in source.size():
		skeleton.set_bone_pose_rotation(index, source[index])


func _expect(ok: bool, label: String) -> void:
	if not ok and not failures.has(label):
		failures.append(label)
