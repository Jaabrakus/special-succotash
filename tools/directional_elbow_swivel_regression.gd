extends SceneTree

## Narrow geometry/guard proof. Rendered AK/M4 approval remains a separate gate.
const Pose := preload("res://scripts/player/operator_weapon_pose_solver.gd")
const Posture := preload("res://scripts/player/operator_posture_layer.gd")
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var pose := Pose.new()
	root.add_child(pose)
	_check_guards(pose)
	_check_endpoints(pose)
	_check_frame_lifetime(pose)
	pose.queue_free()
	await process_frame
	print("DIRECTIONAL_ELBOW_SWIVEL ", "PASS" if failures.is_empty() else "FAIL", " ", failures)
	quit(0 if failures.is_empty() else 1)

func _angle(pose: Node3D, stance: StringName, state: StringName, moving: bool, x: float, action: StringName = &"", ready: float = 0.0) -> float:
	return rad_to_deg(pose._elbow_presentation_angle(stance, state, ready, action, moving, x))

func _check_guards(pose: Node3D) -> void:
	pose.fire_recoil.age = 1.0
	_expect(is_zero_approx(_angle(pose, &"STANDING", &"LOCOMOTION", true, -1.0)), "default profile adds no carry flare")
	pose.configure_dynamic_hold({"strafe_carry": {"left_elbow_flare_degrees": 12.0}})
	for posture: StringName in [&"STANDING", &"CROUCHED"]:
		_expect(is_equal_approx(_angle(pose, posture, &"LOCOMOTION", true, -1.0), 12.0), "%s left strafe opts into saved angle without readiness" % posture)
		_expect(is_equal_approx(_angle(pose, posture, &"LOCOMOTION", true, -0.5), 6.0), "%s partial left strafe scales existing blend" % posture)
		for x: float in [0.0, 0.5, 1.0]:
			_expect(is_zero_approx(_angle(pose, posture, &"LOCOMOTION", true, x)), "%s zero/right coordinate adds no carry" % posture)
		_expect(is_zero_approx(_angle(pose, posture, &"LOCOMOTION", false, -1.0)), "%s stationary adds no carry" % posture)
		for action: StringName in [&"reload", &"grenade_toss", &"dive_roll"]:
			_expect(is_zero_approx(_angle(pose, posture, &"LOCOMOTION", true, -1.0, action, 1.0)), "%s action %s keeps its authored arm" % [posture, action])
		for state: StringName in [&"AIRBORNE", &"LANDING", &"DIVING", &"ROLLING"]:
			_expect(is_zero_approx(_angle(pose, posture, state, true, -1.0)), "%s mobility %s adds no carry" % [posture, state])
	_expect(is_zero_approx(_angle(pose, &"PRONE", &"LOCOMOTION", true, -1.0)), "prone never receives carry")
	_expect(is_zero_approx(_angle(pose, &"STANDING", &"LOCOMOTION", true, NAN)), "nonfinite coordinate adds no carry")
	pose.fire_recoil.age = pose.fire_recoil.attack
	_expect(is_equal_approx(_angle(pose, &"STANDING", &"LOCOMOTION", true, -1.0, &"", 1.0), 12.0 + pose.fire_recoil.flare), "carry and accepted recoil form one angle")
	_expect(is_equal_approx(_angle(pose, &"PRONE", &"LOCOMOTION", true, -1.0, &"", 1.0), rad_to_deg(pose.fire_recoil.offset(&"PRONE"))), "existing prone recoil is preserved")
	pose.configure_dynamic_hold({"strafe_carry": {"left_elbow_flare_degrees": 99.0}})
	_expect(is_equal_approx(_angle(pose, &"STANDING", &"LOCOMOTION", true, -1.0, &"", 1.0), 20.0), "combined carry and recoil clamp at twenty degrees")
	pose.configure_dynamic_hold({})
	pose.fire_recoil.age = 1.0
	_expect(is_zero_approx(pose.strafe_left_elbow_flare_degrees), "weapon switch clears opt-in")
	pose.configure_dynamic_hold({"strafe_carry": "invalid"})
	_expect(is_zero_approx(pose.strafe_left_elbow_flare_degrees), "invalid section retains zero default")

func _check_endpoints(pose: Node3D) -> void:
	var skeleton := Skeleton3D.new()
	pose.add_child(skeleton)
	pose.skeleton = skeleton
	# Explicit two-segment test chains use skeleton-global poses. Different
	# parent/world transforms make accidental world-space operations detectable.
	pose.position = Vector3(3.0, 2.0, -4.0)
	pose.rotation = Vector3(0.1, 0.5, -0.2)
	skeleton.scale = Vector3.ONE * 1.4
	_add_bone(skeleton, "mixamorig_RightArm", -1, Vector3(0.2, 1.4, 0.0))
	_add_bone(skeleton, "mixamorig_RightForeArm", 0, Vector3(0.1, -0.16, -0.17))
	_add_bone(skeleton, "mixamorig_RightHand", 1, Vector3(-0.05, 0.02, -0.25))
	_add_bone(skeleton, "mixamorig_LeftArm", -1, Vector3(-0.2, 1.4, 0.0))
	_add_bone(skeleton, "mixamorig_LeftForeArm", 3, Vector3(0.05, -0.18, -0.15))
	_add_bone(skeleton, "mixamorig_LeftHand", 4, Vector3(0.25, 0.03, -0.3))
	for index in skeleton.get_bone_count():
		pose.bone_indices[StringName(skeleton.get_bone_name(index))] = index
	var weapon := Node3D.new()
	pose.add_child(weapon)
	weapon.position = Vector3(0.3, 1.3, -0.2)
	pose.weapon_node = weapon
	var capped_elbow := Vector3.ZERO
	for degrees: float in [0.0, 12.0, 20.0, 500.0]:
		skeleton.clear_bones_global_pose_override()
		skeleton.force_update_all_bone_transforms()
		var shoulder := skeleton.get_bone_global_pose(0)
		var elbow := skeleton.get_bone_global_pose(1)
		var wrist := skeleton.get_bone_global_pose(2)
		var support := skeleton.get_bone_global_pose(5)
		var root_before := weapon.global_transform
		var upper_length := shoulder.origin.distance_to(elbow.origin)
		var fore_length := elbow.origin.distance_to(wrist.origin)
		pose.fire_recoil.apply_elbow_angle(pose, deg_to_rad(degrees))
		var after := skeleton.get_bone_global_pose(1)
		_expect(shoulder.origin.is_equal_approx(skeleton.get_bone_global_pose(0).origin), "%.0f degree fixed shoulder endpoint" % degrees)
		_expect(wrist.is_equal_approx(skeleton.get_bone_global_pose(2)), "%.0f degree fixed wrist transform" % degrees)
		_expect(support.is_equal_approx(skeleton.get_bone_global_pose(5)), "%.0f degree fixed support-hand transform" % degrees)
		_expect(root_before.is_equal_approx(weapon.global_transform), "%.0f degree unchanged weapon root" % degrees)
		_expect(is_equal_approx(upper_length, shoulder.origin.distance_to(after.origin)) and is_equal_approx(fore_length, wrist.origin.distance_to(after.origin)), "%.0f degree bone lengths unchanged" % degrees)
		var shift := elbow.origin.distance_to(after.origin)
		_expect(shift > 0.001 if degrees > 0.0 else is_zero_approx(shift), "%.0f degree expected elbow movement" % degrees)
		if degrees == 20.0:
			capped_elbow = after.origin
		elif degrees > 20.0:
			_expect(capped_elbow.is_equal_approx(after.origin), "angle utility independently caps external callers")
		print("DIRECTIONAL_ELBOW_METRIC degrees=", degrees, " elbow_shift_skeleton_units=", shift)
	# Old two-argument API must produce the same pose as its original envelope.
	skeleton.clear_bones_global_pose_override()
	pose.fire_recoil.age = pose.fire_recoil.attack
	pose.fire_recoil.apply_elbow(pose, &"STANDING")
	var legacy := skeleton.get_bone_global_pose(1)
	skeleton.clear_bones_global_pose_override()
	pose.fire_recoil.apply_elbow_angle(pose, pose.fire_recoil.offset(&"STANDING"))
	_expect(legacy.is_equal_approx(skeleton.get_bone_global_pose(1)), "legacy recoil API remains compatible")

func _check_frame_lifetime(pose: Node3D) -> void:
	var skeleton := Skeleton3D.new()
	pose.add_child(skeleton)
	pose.skeleton = skeleton
	_add_bone(skeleton, "mixamorig_Hips", -1, Vector3(0, 1, 0))
	_add_bone(skeleton, "mixamorig_Spine2", 0, Vector3(0, 0.4, 0))
	_add_bone(skeleton, "mixamorig_LeftShoulder", 1, Vector3(-0.08, 0.1, 0))
	_add_bone(skeleton, "mixamorig_LeftArm", 2, Vector3(-0.15, 0, 0))
	_add_bone(skeleton, "mixamorig_RightShoulder", 1, Vector3(0.08, 0.1, 0))
	_add_bone(skeleton, "mixamorig_RightArm", 4, Vector3(0.15, 0, 0))
	_add_bone(skeleton, "mixamorig_RightForeArm", 5, Vector3(0.02, -0.18, -0.18))
	_add_bone(skeleton, "mixamorig_RightHand", 6, Vector3(-0.05, 0.02, -0.25))
	_add_bone(skeleton, "UnrelatedLeg", 0, Vector3(0.1, -0.3, 0))
	pose.bone_indices.clear()
	for index in skeleton.get_bone_count():
		pose.bone_indices[StringName(skeleton.get_bone_name(index))] = index
	var owner := Posture.new()
	owner.bind(skeleton)
	var target := skeleton.global_transform * Vector3(0, 1.5, -20)
	var hip := skeleton.get_bone_global_pose(0)
	var unrelated := skeleton.get_bone_global_pose(8)
	unrelated.origin += Vector3(0, 0.01, 0)
	skeleton.set_bone_global_pose_override(8, unrelated, 1.0, true)
	var weapon_before: Transform3D = pose.weapon_node.global_transform
	pose.fire_recoil.apply_elbow_angle(pose, deg_to_rad(12.0), true)
	var pinned := skeleton.get_bone_global_pose(5).origin
	skeleton.set_bone_pose_rotation(1, Quaternion(Vector3.UP, 0.6))
	skeleton.force_update_all_bone_transforms()
	_expect(pinned.is_equal_approx(skeleton.get_bone_global_pose(5).origin), "repro prior elbow override pins shoulder against fresh chest")
	owner._apply_square_shoulders(target, 1.0, true, 0.0, 90.0)
	var stale_error := owner.last_shoulder_square_error_deg
	_expect(stale_error > 1.0, "repro stale endpoint leaves measurable one-pass square residual")
	pose.begin_posture_frame()
	owner._apply_square_shoulders(target, 1.0, true, 0.0, 90.0)
	_expect(owner.last_shoulder_square_error_deg < 0.06, "retired elbow override allows one-pass physical square")
	_expect(skeleton.get_bone_global_pose(0).is_equal_approx(hip), "retirement never changes hip or bob source")
	_expect(skeleton.get_bone_global_pose(8).is_equal_approx(unrelated), "retirement preserves unrelated owner's override")
	_expect(pose.weapon_node.global_transform.is_equal_approx(weapon_before), "retirement never rewrites weapon or aim")
	var shoulder := skeleton.get_bone_global_pose(5).origin
	var wrist := skeleton.get_bone_global_pose(7)
	pose.fire_recoil.apply_elbow_angle(pose, deg_to_rad(12.0), true)
	_expect(skeleton.get_bone_global_pose(5).origin.is_equal_approx(shoulder) and skeleton.get_bone_global_pose(7).is_equal_approx(wrist), "new final elbow pass still preserves both endpoints")
	print("ELBOW_FRAME_LIFETIME stale_error_deg=", stale_error, " clean_error_deg=", owner.last_shoulder_square_error_deg)
	pose.begin_posture_frame()
	pose.begin_posture_frame()

func _add_bone(skeleton: Skeleton3D, name: String, parent: int, local_position: Vector3) -> void:
	skeleton.add_bone(name)
	var index := skeleton.get_bone_count() - 1
	skeleton.set_bone_parent(index, parent)
	var rest := Transform3D(Basis.IDENTITY, local_position)
	skeleton.set_bone_rest(index, rest)
	skeleton.set_bone_pose(index, rest)

func _expect(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		push_error("DIRECTIONAL_ELBOW_CHECK FAIL " + label)
