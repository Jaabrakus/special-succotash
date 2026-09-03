class_name SocomAglsSkeletonDebugVisual
extends MultiMeshInstance3D

## One-draw-call runtime visualization for the native AGLS skeleton.
## This has no collision and never participates in gameplay authority.

const HELPER_TOKENS: Array[String] = [
	"ik_", "twist", "attach",
]

var skeleton: Skeleton3D
var segment_bones: Array[int] = []


func bind(target_skeleton: Skeleton3D) -> bool:
	skeleton = target_skeleton
	segment_bones.clear()
	if skeleton == null:
		return false
	for bone_index in skeleton.get_bone_count():
		var parent_index := skeleton.get_bone_parent(bone_index)
		if parent_index < 0 or _is_helper(skeleton.get_bone_name(bone_index)):
			continue
		segment_bones.append(bone_index)
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.08, 0.82, 1.0, 1.0)
	material.emission_enabled = true
	material.emission = Color(0.02, 0.28, 0.40)
	material.roughness = 0.38
	box.material = material
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = box
	multimesh.instance_count = segment_bones.size()
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	process_priority = 110
	_update_segments()
	return not segment_bones.is_empty()


func _process(_delta: float) -> void:
	_update_segments()


func _update_segments() -> void:
	if skeleton == null or multimesh == null:
		return
	skeleton.force_update_all_bone_transforms()
	for segment_index in segment_bones.size():
		var bone_index := segment_bones[segment_index]
		var parent_index := skeleton.get_bone_parent(bone_index)
		var start := skeleton.get_bone_global_pose(parent_index).origin
		var finish := skeleton.get_bone_global_pose(bone_index).origin
		var offset := finish - start
		var length := offset.length()
		if length <= 0.0001:
			multimesh.set_instance_transform(
				segment_index,
				Transform3D(Basis.IDENTITY.scaled(Vector3.ZERO), start)
			)
			continue
		var rotation := Quaternion(Vector3.UP, offset / length)
		var thickness := clampf(length * 0.13, 0.018, 0.042)
		var basis := (
			Basis(rotation)
			* Basis.from_scale(Vector3(thickness, length, thickness))
		)
		multimesh.set_instance_transform(
			segment_index,
			Transform3D(basis, start + offset * 0.5)
		)


func _is_helper(bone_name: String) -> bool:
	var folded := bone_name.to_lower()
	for token in HELPER_TOKENS:
		if token in folded:
			return true
	return false
