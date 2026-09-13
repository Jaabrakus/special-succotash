extends SceneTree

const Grip := preload("res://scripts/player/operator_weapon_grip_contact.gd")
const CANONICAL := "res://assets/characters/ps1_dual_source_rig/ps1_dual_source_rig.scn"
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var selection: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://config/operator_character.json"))
	var selected := String(selection.get("scene", CANONICAL)) if bool(selection.get("enabled", false)) else CANONICAL
	var paths: Array[String] = [selected]
	if selected != CANONICAL:
		paths.append(CANONICAL)
	for path in paths:
		_check_model(path)
	print("SOURCE_PISTOL_FINGER ", JSON.stringify({"result":"PASS" if failures.is_empty() else "FAIL", "models":paths, "failures":failures}))
	quit(0 if failures.is_empty() else 1)

func _check_model(path: String) -> void:
	var scene := load(path) as PackedScene
	if not _expect(scene != null, path + " loads"):
		return
	var model := scene.instantiate() as Node3D
	root.add_child(model)
	model.scale = Vector3.ONE * 62.0
	var skeletons := model.find_children("*", "Skeleton3D", true, false)
	if not _expect(skeletons.size() == 1, path + " has unique skeleton"):
		model.free()
		return
	var skeleton := skeletons[0] as Skeleton3D
	var weapon := Node3D.new()
	root.add_child(weapon)
	weapon.position = Vector3(0.2, 1.0, 0.4)
	weapon.rotation = Vector3(0.1, 0.2, -0.4)
	weapon.set_meta("support_hand_pose", {"finger_curl":0.82, "thumb_wrap":0.72})
	var grip := Grip.new()
	grip.bind(skeleton, weapon)
	skeleton.reset_bone_poses()
	# Non-neutral wrist/arm input proves the helper does not impose a hold pose.
	for name in ["mixamorig_RightHand", "mixamorig_LeftHand", "mixamorig_RightForeArm", "mixamorig_LeftArm"]:
		var bone := skeleton.find_bone(name)
		if bone >= 0:
			skeleton.set_bone_pose_rotation(bone, (skeleton.get_bone_pose_rotation(bone) * Quaternion(Vector3.UP, 0.19)).normalized())
	var before := _poses(skeleton)
	var weapon_before := weapon.global_transform
	grip.apply_source_pistol(true, false)
	var right_only := _poses(skeleton)
	_expect(grip.applied_bone_count == 15 and grip.applied_right and not grip.applied_left, path + " right-only 15 finger bones")
	_expect(grip.snapshot().source_pistol_grip, path + " diagnostics identify source pistol")
	_forbid_nonfinger_changes(skeleton, before, right_only, false, path)
	var middle := skeleton.find_bone("mixamorig_RightHandMiddle2")
	var index := skeleton.find_bone("mixamorig_RightHandIndex2")
	_expect(_flex(skeleton, middle) > 0.35 and _flex(skeleton, middle) < 1.5, path + " right flex positive")
	_expect(_flex(skeleton, index) < _flex(skeleton, middle) * 0.65, path + " trigger index less curled")
	for repeat in 60:
		grip.apply_source_pistol(true, false)
	_compare(right_only, _poses(skeleton), path + " no accumulated finger pose")
	_expect(weapon_before.is_equal_approx(weapon.global_transform), path + " weapon transform untouched")
	grip.apply_source_pistol(true, true)
	var both := _poses(skeleton)
	_expect(grip.applied_bone_count == 30 and grip.applied_left, path + " explicitly requested support closure")
	_forbid_nonfinger_changes(skeleton, before, both, true, path)
	_expect(_flex(skeleton, skeleton.find_bone("mixamorig_LeftHandMiddle2")) > 0.35, path + " left flex positive")
	grip.apply_source_pistol(true, false)
	_compare(right_only, _poses(skeleton), path + " support closure released")
	grip.apply_source_pistol(false, true)
	_expect(grip.applied_bone_count == 0 and not grip.applied_right and not grip.applied_left and not grip.snapshot().source_pistol_grip, path + " hidden or stowed applies no grip")
	_compare(before, _poses(skeleton), path + " hidden releases owned finger overrides")
	weapon.set_meta("support_hand_pose", {"finger_curl":0.0, "thumb_wrap":0.0})
	grip.apply_source_pistol(true, false)
	_expect(_flex(skeleton, middle) > 0.35, path + " zero saved controls use pistol defaults")
	grip.apply_source_pistol(false, false)
	_compare(before, _poses(skeleton), path + " repeat release preserves source pose")
	weapon.free()
	model.free()

func _poses(skeleton: Skeleton3D) -> Array[Transform3D]:
	skeleton.force_update_all_bone_transforms()
	var result: Array[Transform3D] = []
	for bone in skeleton.get_bone_count():
		result.append(skeleton.get_bone_global_pose(bone))
	return result

func _forbid_nonfinger_changes(skeleton: Skeleton3D, before: Array[Transform3D], after: Array[Transform3D], left_allowed: bool, label: String) -> void:
	for bone in skeleton.get_bone_count():
		var name := String(skeleton.get_bone_name(bone))
		var allowed := (name.begins_with("mixamorig_RightHand") or (left_allowed and name.begins_with("mixamorig_LeftHand"))) and not name.ends_with("Hand")
		if not allowed:
			_expect(before[bone].is_equal_approx(after[bone]), label + " protected bone " + name)

func _flex(skeleton: Skeleton3D, bone: int) -> float:
	if not _expect(bone >= 0, "expected finger exists"):
		return 0.0
	var parent := skeleton.get_bone_parent(bone)
	var local := skeleton.get_bone_global_pose(parent).affine_inverse() * skeleton.get_bone_global_pose(bone)
	return (skeleton.get_bone_rest(bone).basis.inverse() * local.basis).get_euler().x

func _compare(expected: Array[Transform3D], actual: Array[Transform3D], label: String) -> void:
	for bone in expected.size():
		_expect(expected[bone].is_equal_approx(actual[bone]), label + " bone " + str(bone))

func _expect(ok: bool, message: String) -> bool:
	if not ok:
		failures.append(message)
	return ok
