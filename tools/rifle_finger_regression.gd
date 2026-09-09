extends SceneTree

const Grip = preload("res://scripts/player/operator_weapon_grip_contact.gd")
const Driver = preload("res://scripts/player/operator_animation_driver.gd")
const Weapons = preload("res://scripts/weapons/weapon_rig_contract.gd")
var failures: Array[String] = []

func _initialize() -> void:
	ProjectSettings.set_setting("socom/playtest/use_active_bundle", false)
	_run.call_deferred()

func _run() -> void:
	var driver := Driver.new()
	root.add_child(driver)
	await process_frame
	check(driver.notify_weapon_equipped(Weapons.load_config("res://config/weapons/ak-47.json")), "canonical rifle equips")
	driver.set_process(false)
	var s: Skeleton3D = driver.skeleton
	var grip := Grip.new()
	grip.bind(s, driver.weapon_node)
	grip.source_rifle_grip = true
	s.clear_bones_global_pose_override()
	s.reset_bone_poses()
	var before := poses(s)
	var weapon_before: Transform3D = driver.weapon_node.global_transform
	grip.apply(&"READY_SOLVER", &"IK_TO_WEAPON", true)
	var after := poses(s)
	check(grip.applied_bone_count == 30, "both five-finger hands shaped")
	for i in s.get_bone_count():
		if "Hand" not in s.get_bone_name(i) or s.get_bone_name(i).ends_with("Hand"):
			check(before[i].is_equal_approx(after[i]), "nonfinger bone unchanged: " + s.get_bone_name(i))
	for side in ["Right", "Left"]:
		var middle := s.find_bone("mixamorig_" + side + "HandMiddle2")
		var index := s.find_bone("mixamorig_" + side + "HandIndex2")
		var middle_angle := flex(s, middle)
		check(middle_angle > 0.35 and middle_angle < 1.5, side + " finger flexes toward palm, not away")
		if side == "Right":
			check(flex(s, index) < middle_angle * 0.65, "trigger index stays less curled")
	for repeat in 60:
		grip.apply(&"READY_SOLVER", &"IK_TO_WEAPON", true)
	var repeated := poses(s)
	for i in s.get_bone_count():
		check(after[i].is_equal_approx(repeated[i]), "no accumulation: " + s.get_bone_name(i))
	check(weapon_before.is_equal_approx(driver.weapon_node.global_transform), "finger pass never moves weapon")
	# Runtime's weapon owner clears overrides before each animation frame.
	s.clear_bones_global_pose_override()
	grip.apply(&"RELOAD_ACTION", &"ANIMATION_FREE", true)
	check(grip.applied_right and not grip.applied_left and grip.applied_bone_count == 15, "reload support hand released")
	s.clear_bones_global_pose_override()
	grip.apply(&"GRENADE_ACTION", &"ANIMATION_FREE", true)
	check(grip.applied_bone_count == 0, "grenade animation retains all fingers")
	grip.apply(&"READY_SOLVER", &"IK_TO_WEAPON", false)
	check(grip.applied_bone_count == 0, "hidden weapon does not grip")
	s.clear_bones_global_pose_override()
	driver.weapon_node.set_meta("support_hand_pose", {"finger_curl": 0.0, "thumb_wrap": 0.0})
	grip.apply(&"READY_SOLVER", &"IK_TO_WEAPON", true)
	check(absf(flex(s, s.find_bone("mixamorig_RightHandMiddle2"))) < 0.001, "saved zero curl is honored")
	driver.queue_free()
	await process_frame
	print("RIFLE_FINGER ", "PASS" if failures.is_empty() else "FAIL", " ", failures)
	quit(0 if failures.is_empty() else 1)

func poses(s: Skeleton3D) -> Array[Transform3D]:
	s.force_update_all_bone_transforms()
	var result: Array[Transform3D] = []
	for i in s.get_bone_count():
		result.append(s.get_bone_global_pose(i))
	return result

func flex(s: Skeleton3D, index: int) -> float:
	var parent := s.get_bone_parent(index)
	var local := s.get_bone_global_pose(parent).affine_inverse() * s.get_bone_global_pose(index)
	var delta := s.get_bone_rest(index).basis.inverse() * local.basis
	return delta.get_euler().x

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
