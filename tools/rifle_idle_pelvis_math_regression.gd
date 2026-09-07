extends SceneTree

## Translation: prove only the existing standing-idle pelvis yaw helper. No
## runtime or profile mutation. Keep local positions, vertical origins, lean,
## default poses and unrelated branches. Canonical live guards are a separate
## test; this fixture covers mixed bases/scales, exact fades and settled reuse.
const Posture := preload("res://scripts/player/operator_posture_layer.gd")
const WEIGHTS: Array[float] = [0.0, 0.125, 0.25, 0.5, 0.75, 0.875, 1.0]
var failures: Array[String] = []
var case_count := 0
var maximum_bar_error := 0.0
var maximum_y_error := 0.0
var maximum_fraction_error := 0.0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for side: float in [-1.0, 1.0]:
		var skeleton := _fixture(side)
		root.add_child(skeleton)
		var owner := Posture.new()
		owner.bind(skeleton)
		for sample in 12:
			var scale := [0.62, 1.0, 6.2][sample % 3] as float
			skeleton.transform = Transform3D(Basis(Vector3.UP, 0.19 * sample).scaled(Vector3.ONE * scale), Vector3(3, 2, -4))
			var source := _source(skeleton, sample)
			for weight: float in WEIGHTS:
				_reset(skeleton, source)
				var before := _globals(skeleton)
				var bar := before[3].origin - before[2].origin
				bar.y = 0.0
				var rest_bar := skeleton.get_bone_global_rest(3).origin - skeleton.get_bone_global_rest(2).origin
				var desired := Vector3.RIGHT if rest_bar.x >= 0.0 else Vector3.LEFT
				var yaw := bar.normalized().signed_angle_to(desired, Vector3.UP)
				owner._apply_standing_idle_pelvis_square(weight)
				var after := _globals(skeleton)
				var expected := (Basis(Vector3.UP, yaw * weight) * before[1].basis).orthonormalized().get_rotation_quaternion().normalized()
				var actual := after[1].basis.orthonormalized().get_rotation_quaternion().normalized()
				var fraction_error := rad_to_deg(expected.angle_to(actual))
				maximum_fraction_error = maxf(maximum_fraction_error, fraction_error)
				_expect(fraction_error < 0.06, "fraction uses exact requested yaw without clamp/snapping")
				_expect(after[1].origin.is_equal_approx(before[1].origin), "pelvis origin is unchanged")
				for index in skeleton.get_bone_count():
					_expect(skeleton.get_bone_pose_position(index).is_equal_approx(skeleton.get_bone_rest(index).origin), "all local bone positions remain authored")
					var y_error := absf((skeleton.global_transform * after[index].origin).y - (skeleton.global_transform * before[index].origin).y)
					maximum_y_error = maxf(maximum_y_error, y_error)
					_expect(y_error < 0.0001, "yaw does not suppress or alter vertical bone origins")
					if weight == 0.0:
						_expect(before[index].is_equal_approx(after[index]), "zero weight keeps every bone unchanged")
					if index != 1:
						_expect(rad_to_deg(source[index].angle_to(skeleton.get_bone_pose_rotation(index))) < 0.06, "only local hips rotation is written")
				_expect(before[0].is_equal_approx(after[0]) and before[8].is_equal_approx(after[8]), "parent and unrelated branch remain unchanged")
				if weight == 1.0:
					var final_bar := after[3].origin - after[2].origin
					final_bar.y = 0.0
					var error := absf(rad_to_deg(final_bar.normalized().signed_angle_to(desired, Vector3.UP)))
					maximum_bar_error = maxf(maximum_bar_error, error)
					_expect(error < 0.01, "full weight physically aligns pelvis root bar")
					for repeated in 8:
						owner._apply_standing_idle_pelvis_square(1.0)
					var settled := _globals(skeleton)
					for index in skeleton.get_bone_count():
						_expect(after[index].origin.distance_to(settled[index].origin) < 0.00001, "settled frozen calls preserve all origins")
						_expect(rad_to_deg(after[index].basis.get_rotation_quaternion().normalized().angle_to(settled[index].basis.get_rotation_quaternion().normalized())) < 0.06, "settled frozen calls do not accumulate yaw")
				case_count += 1
		skeleton.queue_free()
		await process_frame
	print("RIFLE_IDLE_PELVIS_MATH ", "PASS" if failures.is_empty() else "FAIL", " cases=", case_count, " max_bar_error_deg=", maximum_bar_error, " max_fraction_error_deg=", maximum_fraction_error, " max_y_error_m=", maximum_y_error, " ", failures)
	quit(0 if failures.is_empty() else 1)


func _fixture(side: float) -> Skeleton3D:
	var skeleton := Skeleton3D.new()
	var names: Array[String] = ["RigRoot", "mixamorig_Hips", "mixamorig_LeftUpLeg", "mixamorig_RightUpLeg", "mixamorig_Spine", "mixamorig_Head", "mixamorig_LeftLeg", "mixamorig_RightLeg", "Unrelated"]
	var parents: Array[int] = [-1, 0, 1, 1, 1, 4, 2, 3, 0]
	var positions: Array[Vector3] = [Vector3.ZERO, Vector3(0.02, 1, -0.03), Vector3(-0.14 * side, -0.05, 0.01), Vector3(0.14 * side, -0.05, 0.01), Vector3(0.02, 0.18, -0.02), Vector3(0, 0.45, 0.04), Vector3(0, -0.4, 0.01), Vector3(0, -0.4, 0.01), Vector3(0.3, 0.1, 0.2)]
	for index in names.size():
		skeleton.add_bone(names[index])
		skeleton.set_bone_parent(index, parents[index])
		skeleton.set_bone_rest(index, Transform3D(Basis.from_euler(Vector3(0.02 * index, -0.03 * index, 0.01 * index)), positions[index]))
		skeleton.reset_bone_pose(index)
	return skeleton


func _source(skeleton: Skeleton3D, sample: int) -> Array[Quaternion]:
	var source: Array[Quaternion] = []
	for index in skeleton.get_bone_count():
		var q := skeleton.get_bone_rest(index).basis.get_rotation_quaternion().normalized()
		if index == 0:
			q = Quaternion.from_euler(Vector3(0.03 * (sample - 5), 0.21 * (sample - 6), -0.02 * (sample - 4)))
		elif index == 1:
			q = Quaternion.from_euler(Vector3(-0.25 + 0.04 * sample, deg_to_rad(-175.0 + 31.0 * sample), 0.2 - 0.035 * sample))
		else:
			q = q * Quaternion.from_euler(Vector3(0.015 * sample, -0.01 * sample, 0.008 * index))
		source.append(q.normalized())
	return source


func _reset(skeleton: Skeleton3D, source: Array[Quaternion]) -> void:
	for index in source.size():
		skeleton.set_bone_pose_rotation(index, source[index])


func _globals(skeleton: Skeleton3D) -> Array[Transform3D]:
	var transforms: Array[Transform3D] = []
	for index in skeleton.get_bone_count():
		transforms.append(skeleton.get_bone_global_pose(index))
	return transforms


func _expect(ok: bool, label: String) -> void:
	if not ok and not failures.has(label):
		failures.append(label)
