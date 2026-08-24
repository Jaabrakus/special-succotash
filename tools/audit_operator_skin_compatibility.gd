extends SceneTree

## Read-only comparison of the canonical PS1 operator and a candidate skin.

const PS1_PATH := "res://assets/characters/ps1_gas_mask_soldier/trooper_rigged.fbx"
const URBAN_PATH := "res://counter-strike-urban/source/Counter Strike Urban.fbx"

const PS1_BONES := {
	"hips": "mixamorig_Hips",
	"head": "mixamorig_Head",
	"left_shoulder": "mixamorig_LeftArm",
	"left_hand": "mixamorig_LeftHand",
	"right_shoulder": "mixamorig_RightArm",
	"right_hand": "mixamorig_RightHand",
	"left_foot": "mixamorig_LeftFoot",
	"right_foot": "mixamorig_RightFoot",
}

const URBAN_BONES := {
	"hips": "Bip01 Pelvis",
	"head": "Bip01 Head",
	"left_shoulder": "Bip01 L UpperArm",
	"left_hand": "Bip01 L Hand",
	"right_shoulder": "Bip01 R UpperArm",
	"right_hand": "Bip01 R Hand",
	"left_foot": "Bip01 L Foot",
	"right_foot": "Bip01 R Foot",
}


func _initialize() -> void:
	_compare(PS1_PATH, PS1_BONES, "PS1")
	_compare(URBAN_PATH, URBAN_BONES, "URBAN")
	quit(0)


func _compare(path: String, bone_names: Dictionary, label: String) -> void:
	var scene := load(path) as PackedScene
	if scene == null:
		push_error("SKIN_COMPAT missing %s" % path)
		return
	var instance := scene.instantiate()
	root.add_child(instance)
	var skeleton := _find_skeleton(instance)
	if skeleton == null:
		push_error("SKIN_COMPAT %s has no skeleton" % label)
		instance.queue_free()
		return
	print("SKIN_COMPAT %s root_scale=%s skeleton_transform=%s" % [
		label,
		str(instance.scale),
		str(skeleton.transform),
	])
	var hips_position := _rest_origin(skeleton, String(bone_names["hips"]))
	var head_position := _rest_origin(skeleton, String(bone_names["head"]))
	var height := maxf(hips_position.distance_to(head_position), 0.000001)
	print("SKIN_SIZE %s hips_to_head=%.6f skeleton_scale=%.6f" % [
		label,
		height,
		skeleton.basis.get_scale().length() / sqrt(3.0),
	])
	for logical_name in bone_names:
		var bone_name := String(bone_names[logical_name])
		var index := skeleton.find_bone(bone_name)
		if index < 0:
			print("SKIN_BONE %s %s MISSING" % [label, logical_name])
			continue
		var rest := skeleton.get_bone_global_rest(index)
		print("SKIN_BONE %s %s index=%d normalized_origin=%s rotation=%s" % [
			label,
			logical_name,
			index,
			str((rest.origin - hips_position) / height),
			str(rest.basis.get_rotation_quaternion().normalized()),
		])
	instance.queue_free()


func _rest_origin(skeleton: Skeleton3D, bone_name: String) -> Vector3:
	var index := skeleton.find_bone(bone_name)
	return skeleton.get_bone_global_rest(index).origin if index >= 0 else Vector3.ZERO


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for child in node.get_children():
		var found := _find_skeleton(child)
		if found != null:
			return found
	return null
