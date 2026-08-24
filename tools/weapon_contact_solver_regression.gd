extends SceneTree

const CONTACT_SOLVER := preload(
	"res://scripts/player/operator_weapon_contact_solver.gd"
)

var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var packed := load(
		"res://assets/characters/ps1_gas_mask_soldier/trooper_rigged.fbx"
	) as PackedScene
	_expect(packed != null, "canonical operator rig loads")
	if packed == null:
		_finish()
		return
	var operator := packed.instantiate()
	root.add_child(operator)
	await process_frame
	var skeleton := _find_skeleton(operator)
	_expect(skeleton != null, "canonical operator exposes a skeleton")
	if skeleton == null:
		operator.queue_free()
		_finish()
		return

	var left_hand := skeleton.find_bone("mixamorig_LeftHand")
	var right_hand := skeleton.find_bone("mixamorig_RightHand")
	var left_anchor := CONTACT_SOLVER.calculate_palm_anchor(
		skeleton, "Left", left_hand
	)
	var right_anchor := CONTACT_SOLVER.calculate_palm_anchor(
		skeleton, "Right", right_hand
	)
	print("WEAPON_CONTACT_METRIC left_anchor=", left_anchor, " right_anchor=", right_anchor)
	_expect(left_anchor.length() > 0.0001, "left palm center derives from finger roots")
	_expect(right_anchor.length() > 0.0001, "right palm center derives from finger roots")

	var desired_contact := Transform3D(
		Basis.from_euler(Vector3(-0.35, 0.20, 1.10), EULER_ORDER_YXZ),
		Vector3(0.35, 1.25, -0.55)
	)
	var left_wrist := CONTACT_SOLVER.wrist_target_for_contact(
		skeleton,
		desired_contact,
		left_anchor
	)
	var reconstructed_contact := (
		left_wrist.origin +
		left_wrist.basis * CONTACT_SOLVER.scaled_palm_anchor(
			skeleton,
			left_anchor
		)
	)
	_expect(
		reconstructed_contact.distance_to(desired_contact.origin) <= 0.00001,
		"contact-to-wrist conversion preserves the visible palm contact"
	)

	var left_shoulder := skeleton.find_bone("mixamorig_LeftArm")
	var right_shoulder := skeleton.find_bone("mixamorig_RightArm")
	var hips := skeleton.find_bone("mixamorig_Hips")
	var left_shoulder_world := _bone_world(skeleton, left_shoulder)
	var right_shoulder_world := _bone_world(skeleton, right_shoulder)
	var hips_world := _bone_world(skeleton, hips)
	var shoulder_midpoint := left_shoulder_world.lerp(right_shoulder_world, 0.5)
	var anatomical_up := (shoulder_midpoint - hips_world).normalized()
	var pole := CONTACT_SOLVER.support_elbow_pole(
		skeleton,
		left_shoulder,
		right_shoulder,
		hips,
		left_wrist.origin,
		104.75
	)
	var arm_midpoint := left_shoulder_world.lerp(left_wrist.origin, 0.5)
	_expect(
		(pole - arm_midpoint).dot(anatomical_up) < -0.02,
		"support elbow pole drops anatomically instead of using import forward as up"
	)

	for consumer_path in [
		"res://scripts/labs/gun_calibration_lab.gd",
		"res://scripts/labs/animation_studio_arm_ik_preview.gd",
		"res://scripts/player/operator_weapon_pose_solver.gd",
	]:
		var source := FileAccess.get_file_as_string(consumer_path)
		_expect(
			"operator_weapon_contact_solver.gd" in source,
			"%s consumes the shared contact solver" % consumer_path.get_file()
		)

	operator.queue_free()
	_finish()


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for child in node.get_children():
		var found := _find_skeleton(child)
		if found != null:
			return found
	return null


func _bone_world(skeleton: Skeleton3D, bone_index: int) -> Vector3:
	if bone_index < 0:
		return skeleton.global_position
	return (
		skeleton.global_transform
		* skeleton.get_bone_global_pose(bone_index)
	).origin


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("WEAPON_CONTACT_CHECK PASS ", label)
	else:
		failures.append(label)
		push_error("WEAPON_CONTACT_CHECK FAIL %s" % label)


func _finish() -> void:
	if failures.is_empty():
		print("WEAPON_CONTACT_SOLVER_REGRESSION PASS")
		quit(0)
	else:
		print("WEAPON_CONTACT_SOLVER_REGRESSION FAIL ", failures)
		quit(1)
