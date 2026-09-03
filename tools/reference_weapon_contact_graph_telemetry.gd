extends SceneTree

## Executable code audit of the supplied GODOT 4.6 - NEW IK AIM contact graph.
## This is read-only. It proves which nodes own shoulder, hand, weapon, elbow,
## palm, and spine presentation before SOCOM adopts the graph.

const REFERENCE_SCENE := "res://GODOT 4.6 - NEW IK AIM/Node/Player.tscn"

var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var packed := load(REFERENCE_SCENE) as PackedScene
	_expect(packed != null, "reference Player scene loads")
	if packed == null:
		_finish()
		return
	var player := packed.instantiate()

	var skeleton := player.get_node_or_null("Model/GeneralSkeleton") as Skeleton3D
	_expect(skeleton != null, "reference has one GeneralSkeleton")
	if skeleton == null:
		_finish()
		return

	var shoulder_copy := skeleton.get_node_or_null(
		"WeaponCopyTransformModifier3D"
	) as CopyTransformModifier3D
	var trigger_copy := skeleton.get_node_or_null(
		"WeaponCopyTransformModifier3D2"
	) as CopyTransformModifier3D
	var support_ik := skeleton.get_node_or_null("LHTwoBoneIK3D") as TwoBoneIK3D
	var support_palm_copy := skeleton.get_node_or_null(
		"LHCopyTransformModifier3D2"
	) as CopyTransformModifier3D
	var spine_ik := skeleton.get_node_or_null("SpineCCDIK3D") as CCDIK3D
	var weapon_attachment := skeleton.get_node_or_null(
		"RShoulderBoneAttachment3D2"
	) as BoneAttachment3D
	var gun := skeleton.get_node_or_null(
		"RShoulderBoneAttachment3D2/WeaponHolder/Gun"
	) as Node3D
	var left_contact := skeleton.get_node_or_null(
		"RShoulderBoneAttachment3D2/WeaponHolder/Gun/LHikTarget"
	) as Node3D
	var target_pivot := player.get_node_or_null("TargetPivot") as Node3D
	var left_pole := player.get_node_or_null("BoneAttachment3D/LHPoleTarget") as Node3D

	_expect(
		_copy_targets_bone(shoulder_copy, skeleton, "RightUpperArm")
		and String(shoulder_copy.get_reference_node(0)).ends_with(
			"TargetPivot/RHUpperArmWeaponTarget"
		),
		"right-upper-arm rotation copies the shoulder target"
	)
	_expect(
		_copy_targets_bone(trigger_copy, skeleton, "RightHand")
		and String(trigger_copy.get_reference_node(0)).ends_with(
			"TargetPivot/RHWeaponTarget"
		),
		"right-hand rotation copies the trigger-hand target"
	)
	_expect(
		weapon_attachment != null
		and weapon_attachment.bone_name == "RightHand"
		and gun != null,
		"gun is attached under the animated right hand"
	)
	_expect(
		support_ik != null
		and skeleton.get_bone_name(support_ik.get_root_bone(0)) == "LeftUpperArm"
		and skeleton.get_bone_name(support_ik.get_middle_bone(0)) == "LeftLowerArm"
		and skeleton.get_bone_name(support_ik.get_end_bone(0)) == "LeftHand"
		and String(support_ik.get_target_node(0)).ends_with("Gun/LHikTarget")
		and String(support_ik.get_pole_node(0)).ends_with("LHPoleTarget"),
		"left arm uses TwoBoneIK from weapon contact plus elbow pole"
	)
	_expect(
		_copy_targets_bone_with_flags(
			support_palm_copy,
			skeleton,
			"LeftHand",
			CopyTransformModifier3D.TRANSFORM_FLAG_POSITION
			| CopyTransformModifier3D.TRANSFORM_FLAG_ROTATION
		)
		and String(support_palm_copy.get_reference_node(0)).ends_with(
			"Gun/LHikTarget"
		),
		"left palm copies weapon-contact position and rotation after IK"
	)
	_expect(
		spine_ik != null
		and skeleton.get_bone_name(spine_ik.get_root_bone(0)) == "Spine"
		and skeleton.get_bone_name(spine_ik.get_end_bone(0)) == "Head"
		and String(spine_ik.get_target_node(0)).ends_with(
			"TargetPivot/SpineTargetWeaponAim"
		),
		"spine-to-head chain follows the shared aim target"
	)
	_expect(
		target_pivot != null
		and target_pivot.get_node_or_null("RHUpperArmWeaponTarget") != null
		and target_pivot.get_node_or_null("RHWeaponTarget") != null
		and target_pivot.get_node_or_null("SpineTargetWeaponAim") != null,
		"shoulder, trigger hand, and spine targets share one TargetPivot"
	)
	_expect(left_contact != null and left_pole != null, "weapon contact and elbow pole are editable 3D nodes")

	var camera_script := player.get_node("Camera").get_script() as Script
	var camera_source := camera_script.source_code if camera_script != null else ""
	_expect(
		"target_pivot.rotation_degrees.x" in camera_source
		and "target_pivot.rotation_degrees.y" in camera_source,
		"camera aim rotates the shared TargetPivot at runtime"
	)

	var telemetry := {
		"right_shoulder": _copy_record(shoulder_copy, skeleton),
		"right_hand": _copy_record(trigger_copy, skeleton),
		"weapon_parent_bone": weapon_attachment.bone_name if weapon_attachment != null else "",
		"left_hand": {
			"solver": support_ik.get_class() if support_ik != null else "",
			"root": skeleton.get_bone_name(support_ik.get_root_bone(0)) if support_ik != null else "",
			"middle": skeleton.get_bone_name(support_ik.get_middle_bone(0)) if support_ik != null else "",
			"end": skeleton.get_bone_name(support_ik.get_end_bone(0)) if support_ik != null else "",
			"contact": String(support_ik.get_target_node(0)) if support_ik != null else "",
			"pole": String(support_ik.get_pole_node(0)) if support_ik != null else "",
			"palm_rotation_copy": String(support_palm_copy.get_reference_node(0)) if support_palm_copy != null else "",
		},
		"spine": {
			"solver": spine_ik.get_class() if spine_ik != null else "",
			"target": String(spine_ik.get_target_node(0)) if spine_ik != null else "",
			"joint_count": spine_ik.get_joint_count(0) if spine_ik != null else 0,
		},
		"shared_pivot": String(player.get_path_to(target_pivot)) if target_pivot != null else "",
	}
	print("REFERENCE_CONTACT_GRAPH_TELEMETRY ", JSON.stringify(telemetry))
	player.free()
	_finish()


func _copy_targets_bone(
	modifier: CopyTransformModifier3D,
	skeleton: Skeleton3D,
	expected_bone: String
) -> bool:
	return (
		modifier != null
		and modifier.get_setting_count() == 1
		and skeleton.get_bone_name(modifier.get_apply_bone(0)) == expected_bone
		and modifier.get_copy_flags(0) == CopyTransformModifier3D.TRANSFORM_FLAG_ROTATION
	)


func _copy_targets_bone_with_flags(
	modifier: CopyTransformModifier3D,
	skeleton: Skeleton3D,
	expected_bone: String,
	expected_flags: int
) -> bool:
	return (
		modifier != null
		and modifier.get_setting_count() == 1
		and skeleton.get_bone_name(modifier.get_apply_bone(0)) == expected_bone
		and modifier.get_copy_flags(0) == expected_flags
	)


func _copy_record(modifier: CopyTransformModifier3D, skeleton: Skeleton3D) -> Dictionary:
	if modifier == null:
		return {}
	return {
		"modifier": modifier.get_class(),
		"bone": skeleton.get_bone_name(modifier.get_apply_bone(0)),
		"target": String(modifier.get_reference_node(0)),
		"copy_flags": modifier.get_copy_flags(0),
	}


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("REFERENCE_CONTACT_GRAPH PASS ", label)
	else:
		failures.append(label)
		push_error("REFERENCE_CONTACT_GRAPH FAIL %s" % label)


func _finish() -> void:
	if failures.is_empty():
		print("REFERENCE_WEAPON_CONTACT_GRAPH_TELEMETRY PASS")
		quit(0)
	else:
		print("REFERENCE_WEAPON_CONTACT_GRAPH_TELEMETRY FAIL ", failures)
		quit(1)
