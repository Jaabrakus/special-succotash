extends SceneTree

const LAB_SCRIPT := preload("res://scripts/labs/operator_animation_lab.gd")
const GIZMO_SCRIPT := preload("res://scripts/labs/transform_gizmo_3d.gd")
const WEAPON_PREVIEW := preload("res://scripts/labs/weapon_rig_preview_loader.gd")

var failures: Array[String] = []


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var gizmo: SocomTransformGizmo3D = GIZMO_SCRIPT.new()
	root.add_child(gizmo)
	await process_frame
	for handle_name in ["move_x", "move_y", "move_z", "rot_x", "rot_y", "rot_z"]:
		_expect(gizmo.has_node(handle_name), "transform gizmo exposes %s" % handle_name)

	var lab = LAB_SCRIPT.new()
	var skeleton := Skeleton3D.new()
	for bone_name in ["mixamorig_Hips", "mixamorig_RightArm", "mixamorig_RightForeArm", "mixamorig_RightHand"]:
		skeleton.add_bone(bone_name)
	skeleton.set_bone_parent(1, 0)
	skeleton.set_bone_parent(2, 1)
	skeleton.set_bone_parent(3, 2)
	lab.skeleton = skeleton
	lab.active_dragged_bone = "mixamorig_RightHand"
	lab.call("_begin_anatomical_drag", lab.active_dragged_bone)
	lab.call("_drag_selected_translation_axis", &"x", Vector2(90.0, 0.0))
	_expect(
		(lab.bone_pos_offsets.get("mixamorig_RightHand", Vector3.ZERO) as Vector3).is_zero_approx(),
		"limb translation arrows preserve hand-to-arm bone length"
	)
	var driven_rotation: Vector3 = lab.bone_rot_offsets.get("mixamorig_RightForeArm", Vector3.ZERO)
	_expect(not driven_rotation.is_zero_approx(), "limb arrow drives its anatomical parent chain")
	var limits: Vector3 = lab.call("_human_rotation_limits", "mixamorig_RightForeArm")
	_expect(
		absf(driven_rotation.x) <= limits.x
		and absf(driven_rotation.y) <= limits.y
		and absf(driven_rotation.z) <= limits.z,
		"anatomical arrow motion remains inside human joint limits"
	)

	var config_path: String = WEAPON_PREVIEW.resolve_config_path("ak-47")
	var config: Dictionary = WEAPON_PREVIEW.load_config(config_path)
	_expect(not config.is_empty(), "Animation Studio resolves a saved Gunsmith weapon profile")
	var attachment := BoneAttachment3D.new()
	root.add_child(attachment)
	var attached: Dictionary = WEAPON_PREVIEW.attach_to_hand(
		config,
		attachment,
		Vector3(-0.02, 0.08, 0.05),
		Vector3(-90.0, 180.0, 0.0)
	)
	_expect(
		attached.has("weapon_root")
		and attached.has("right_hand")
		and attached.has("left_hand")
		and attached.has("muzzle")
		and attached.has("ejection")
		and attached.has("optic"),
		"Studio imports the Gunsmith model and complete socket contract"
	)

	gizmo.queue_free()
	attachment.queue_free()
	skeleton.free()
	lab.free()
	await process_frame
	if failures.is_empty():
		print("POSE_GIZMO_WEAPON_CONTRACT_REGRESSION PASS")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("POSE_GIZMO_WEAPON_CONTRACT_REGRESSION FAIL ", failures)
		quit(1)


func _expect(condition: bool, description: String) -> void:
	if condition:
		print("POSE_GIZMO_CHECK PASS ", description)
	else:
		failures.append(description)
		push_error("POSE_GIZMO_CHECK FAIL %s" % description)
