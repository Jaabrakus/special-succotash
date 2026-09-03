extends SceneTree

const RIG_SCENE := "res://scenes/player/canonical_socom_operator_rig.tscn"
const EXPECTED_LIMITS := [0.9424778, 0.5026548, 0.5654867, 0.2513274]

var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var packed := load(RIG_SCENE) as PackedScene
	_expect(packed != null, "authored operator rig scene loads")
	if packed == null:
		_finish()
		return
	var rig := packed.instantiate() as Node3D
	root.add_child(rig)
	await process_frame

	var visual := rig.get_node_or_null("VisualModel") as Node3D
	var graph := rig.get_node_or_null("IKControlGraph") as Node3D
	var skeleton := rig.get_node_or_null("VisualModel/Skeleton3D") as Skeleton3D
	_expect(visual != null, "scene exposes editable VisualModel wrapper")
	_expect(graph != null, "scene exposes editable IKControlGraph")
	_expect(skeleton != null, "scene exposes the rendered Skeleton3D")
	if visual != null:
		_expect(is_equal_approx(visual.scale.x, 62.0), "only VisualModel carries legacy 62x scale")
	if graph != null:
		_expect(graph.scale.is_equal_approx(Vector3.ONE), "IK controls remain metre-space")
	if skeleton == null:
		rig.queue_free()
		_finish()
		return
	_expect(skeleton.get_bone_count() == 65, "authored Skeleton3D has canonical 65 bones")

	var ordered_names: Array[String] = []
	for child in skeleton.get_children():
		if child is SkeletonModifier3D:
			ordered_names.append(String(child.name))
	var required_order := [
		"SpineCCDIK3D",
		"TargetPivotArmAimModifier",
		"WeaponHandAttachmentModifier",
		"LHTwoBoneIK3D",
		"LHCopyTransformModifier3D2",
		"LeftHandContactObserver",
	]
	_expect(ordered_names.slice(0, required_order.size()) == required_order, "saved modifier order matches pose dependency order")

	var ccd := skeleton.get_node_or_null("SpineCCDIK3D") as CCDIK3D
	_expect(ccd != null, "saved hierarchy contains CCDIK3D")
	if ccd != null:
		_expect(int(ccd.get("settings/0/joint_count")) == 5, "CCDIK3D exposes five spine joints")
		for joint_index in range(EXPECTED_LIMITS.size()):
			var limitation := ccd.get(
				"settings/0/joints/%d/limitation" % joint_index
			) as JointLimitationCone3D
			_expect(limitation != null, "CCDIK joint %d has a cone limitation" % joint_index)
			if limitation != null:
				_expect(
					is_equal_approx(limitation.angle, EXPECTED_LIMITS[joint_index]),
					"CCDIK joint %d preserves authored cone angle" % joint_index
				)
		var spine_target := ccd.get_node_or_null(
			ccd.get("settings/0/target_node") as NodePath
		)
		_expect(spine_target == graph.get_node_or_null("TargetPivot/SpineTargetWeaponAim"), "CCDIK target resolves to the shared TargetPivot graph")

	var support_ik := skeleton.get_node_or_null("LHTwoBoneIK3D") as TwoBoneIK3D
	_expect(support_ik != null, "saved hierarchy contains support-arm TwoBoneIK3D")
	if support_ik != null:
		var support_target := support_ik.get_node_or_null(
			support_ik.get("settings/0/target_node") as NodePath
		)
		var pole_target := support_ik.get_node_or_null(
			support_ik.get("settings/0/pole_node") as NodePath
		)
		_expect(support_target == graph.get_node_or_null("TargetPivot/LHWeaponContactTarget"), "support IK target resolves to weapon contact")
		_expect(pole_target == graph.get_node_or_null("LHPoleAnchor/LHPoleTarget"), "support IK pole resolves to editable elbow control")

	rig.queue_free()
	_finish()


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("AUTHORED_RIG PASS ", label)
	else:
		failures.append(label)
		push_error("AUTHORED_RIG FAIL %s" % label)


func _finish() -> void:
	if failures.is_empty():
		print("AUTHORED_OPERATOR_RIG_SCENE_REGRESSION PASS")
		quit(0)
	else:
		print("AUTHORED_OPERATOR_RIG_SCENE_REGRESSION FAIL %s" % [failures])
		quit(1)
