class_name SocomOperatorIKContract
extends Node3D

## Stable target interface for the future support-hand and two-foot solvers.
## Targets exist now so animation, weapon and terrain systems can integrate
## without reaching into the animation driver's internals.

var support_hand_target: Marker3D
var left_foot_target: Marker3D
var right_foot_target: Marker3D
var skeleton: Skeleton3D


func bind(target_skeleton: Skeleton3D, weapon_parent: Node3D) -> void:
	skeleton = target_skeleton
	support_hand_target = Marker3D.new()
	support_hand_target.name = "SupportHandIKTarget"
	if weapon_parent != null:
		weapon_parent.add_child(support_hand_target)
		support_hand_target.position = Vector3(-0.18, 0.02, -0.42)
	else:
		add_child(support_hand_target)

	left_foot_target = Marker3D.new()
	left_foot_target.name = "LeftFootIKTarget"
	add_child(left_foot_target)
	right_foot_target = Marker3D.new()
	right_foot_target.name = "RightFootIKTarget"
	add_child(right_foot_target)


func get_debug_state() -> Dictionary:
	return {
		"contract_ready": skeleton != null,
		"support_hand_chain_ready": _has_bones([
			&"mixamorig_LeftArm", &"mixamorig_LeftForeArm", &"mixamorig_LeftHand",
		]),
		"left_foot_chain_ready": _has_bones([
			&"mixamorig_LeftUpLeg", &"mixamorig_LeftLeg", &"mixamorig_LeftFoot",
		]),
		"right_foot_chain_ready": _has_bones([
			&"mixamorig_RightUpLeg", &"mixamorig_RightLeg", &"mixamorig_RightFoot",
		]),
	}


func _has_bones(names: Array[StringName]) -> bool:
	if skeleton == null:
		return false
	for bone_name in names:
		if skeleton.find_bone(bone_name) < 0:
			return false
	return true
