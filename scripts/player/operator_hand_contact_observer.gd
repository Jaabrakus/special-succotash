@tool
class_name SocomOperatorHandContactObserver
extends SkeletonModifier3D

## Read-only modifier-time proof for a hand contact.
##
## Godot restores SkeletonModifier3D results after rendering. A normal process-frame
## bone query can therefore report the base animation instead of the rendered IK
## pose. Place this observer after the final hand modifier to measure the pose that
## the renderer actually receives without changing any bone.

var target: Node3D
var hand_bone := -1
var process_count := 0
var last_hand_world := Vector3.ZERO
var last_target_world := Vector3.ZERO
var last_contact_error_m := INF


func bind(target_skeleton: Skeleton3D, bone_name: StringName, contact_target: Node3D) -> void:
	target = contact_target
	hand_bone = target_skeleton.find_bone(bone_name) if target_skeleton != null else -1


func _process_modification() -> void:
	process_count += 1
	var target_skeleton := get_skeleton()
	if target_skeleton == null or hand_bone < 0 or target == null:
		return
	last_hand_world = (
		target_skeleton.global_transform
		* target_skeleton.get_bone_global_pose(hand_bone)
	).origin
	last_target_world = target.global_position
	last_contact_error_m = last_hand_world.distance_to(last_target_world)
