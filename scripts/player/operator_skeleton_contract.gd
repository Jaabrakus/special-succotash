class_name SocomOperatorSkeletonContract
extends RefCounted

## Canonical 65-bone expansion shared by runtime animation and authoring tools.

const EXPECTED_BONE_COUNT := 65


static func ensure_65_bones(skeleton: Skeleton3D) -> void:
	if skeleton == null:
		return
	for side in ["Left", "Right"]:
		var hand_index := skeleton.find_bone("mixamorig_%sHand" % side)
		if hand_index < 0:
			continue
		for finger in ["Middle", "Ring", "Pinky"]:
			var parent_index := hand_index
			for segment in range(1, 5):
				var bone_name := "mixamorig_%sHand%s%d" % [side, finger, segment]
				var bone_index := skeleton.find_bone(bone_name)
				if bone_index < 0:
					bone_index = skeleton.add_bone(bone_name)
					var reference := skeleton.find_bone(
						"mixamorig_%sHandIndex%d" % [side, segment]
					)
					if reference >= 0:
						skeleton.set_bone_rest(bone_index, skeleton.get_bone_rest(reference))
				skeleton.set_bone_parent(bone_index, parent_index)
				parent_index = bone_index


static func is_complete(skeleton: Skeleton3D) -> bool:
	return skeleton != null and skeleton.get_bone_count() == EXPECTED_BONE_COUNT
