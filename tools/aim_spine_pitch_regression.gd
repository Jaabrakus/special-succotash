extends SceneTree

const Layer := preload("res://scripts/player/operator_posture_layer.gd")
var failures: Array[String] = []
var checks := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var skeleton := Skeleton3D.new()
	root.add_child(skeleton)
	var names := ["mixamorig_Hips", "mixamorig_Spine", "mixamorig_Spine1", "mixamorig_Spine2", "mixamorig_LeftFoot", "mixamorig_RightFoot"]
	for i in names.size():
		skeleton.add_bone(names[i])
		if i > 0: skeleton.set_bone_parent(i, i - 1 if i < 4 else 0)
		skeleton.set_bone_rest(i, Transform3D(Basis.IDENTITY, Vector3(0, 0.2 if i < 4 else -0.5, 0)))
	skeleton.reset_bone_poses()
	# A rotated visual frame catches the previous bone-local-axis assumption.
	skeleton.rotation.y = 0.7
	var layer := Layer.new()
	layer.bind(skeleton)
	var baseline := {}
	for i in names.size(): baseline[i] = skeleton.get_bone_pose_rotation(i)
	var aim := Vector3(0, 1, -10)
	for posture: StringName in [&"STANDING", &"CROUCHED", &"PRONE"]:
		for pitch in [-1.4, 0.0, 1.4]:
			for frame in 90:
				layer.apply_source_spine_pitch(pitch, posture, true, aim, 1.0 / 60.0)
				_check(layer.aim_spine_pitch.last_protected_delta < 0.00001, "hips and feet protected")
			var settings: Dictionary = layer.look_pitch_profile.spine_aim[String(posture).to_lower()]
			var expected := clampf(pitch * float(settings.gain), -deg_to_rad(settings.down_limit_deg), deg_to_rad(settings.up_limit_deg))
			_check(absf(layer.aim_spine_pitch.last_pitch_rad - expected) < .0001, "stance target " + str(posture))
			_check(layer.aim_spine_pitch.last_bone_count == 3, "three unique spine bones")
			for i in [0, 4, 5]: _check(skeleton.get_bone_pose_rotation(i).angle_to(baseline[i]) < .00001, "no protected local change")
			var once := skeleton.get_bone_pose_rotation(3)
			for frame in 90: layer.apply_source_spine_pitch(pitch, posture, true, aim, 1.0 / 60.0)
			_check(once.angle_to(skeleton.get_bone_pose_rotation(3)) < .001, "no accumulation")
			layer.apply_source_spine_pitch(pitch, posture, false, aim, 1.0 / 60.0)
			for i in names.size(): _check(skeleton.get_bone_pose_rotation(i).angle_to(baseline[i]) < .001, "suppression restores base")
	# Fresh graph pose must not be replaced with stale cached values on release.
	layer.apply_source_spine_pitch(.8, &"STANDING", true, aim, 1.0)
	var fresh := Quaternion(Vector3.FORWARD, .2)
	skeleton.set_bone_pose_rotation(2, fresh)
	layer.aim_spine_pitch.retire(skeleton)
	_check(skeleton.get_bone_pose_rotation(2).angle_to(fresh) < .001, "new graph value retains ownership")
	layer.apply_source_spine_pitch(NAN, &"STANDING", true, aim, 1.0)
	_check(layer.aim_spine_pitch.last_bone_count == 0, "invalid input suppressed")
	layer.look_pitch_profile.spine_aim.enabled = false
	layer.apply_source_spine_pitch(.5, &"STANDING", true, aim, 1.0)
	_check(layer.aim_spine_pitch.last_bone_count == 0, "saved disable supported")
	layer.look_pitch_profile.spine_aim.enabled = true
	# A real horizontal base, not only a PRONE label on an upright skeleton.
	skeleton.reset_bone_poses()
	skeleton.rotation = Vector3.ZERO
	skeleton.set_bone_pose_rotation(0, Quaternion(Vector3.RIGHT, -PI / 2.0))
	var prone_tip := skeleton.get_bone_global_pose(3).origin
	for pitch in [-0.5, 0.5]:
		layer.apply_source_spine_pitch(pitch, &"PRONE", true, aim, 1.0)
		var tip_delta := skeleton.get_bone_global_pose(3).origin - prone_tip
		_check(signf(tip_delta.y) == signf(pitch) and absf(tip_delta.y) > .005, "horizontal prone chest raises/lowers with aim")
		_check(layer.aim_spine_pitch.last_protected_delta < .00001, "horizontal prone protected hips/feet")
		layer.apply_source_spine_pitch(pitch, &"PRONE", false, aim, 1.0)
		_check(skeleton.get_bone_global_pose(3).origin.distance_to(prone_tip) < .00001, "horizontal prone source restored")
	print("AIM_SPINE_PITCH ", "PASS" if failures.is_empty() else "FAIL", " checks=", checks)
	skeleton.free()
	quit(0 if failures.is_empty() else 1)


func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)
