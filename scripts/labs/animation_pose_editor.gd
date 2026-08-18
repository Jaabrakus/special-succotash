class_name SocomAnimationPoseEditor
extends RefCounted

## Small, non-destructive pose-to-pose editor used by the Animation Studio.
## Imported clips remain untouched. A captured key pose stores the skeleton's
## local transforms at one output frame, and authored playback is baked into a
## separate Animation resource.

var keyframes: Array[Dictionary] = []
var clipboard: Dictionary = {}


func clear() -> void:
	keyframes.clear()
	clipboard.clear()


func capture_pose(skeleton: Skeleton3D, frame: int, contacts: Dictionary = {}) -> int:
	if skeleton == null:
		return -1
	var bones: Dictionary = {}
	for bone_index in range(skeleton.get_bone_count()):
		var bone_name := String(skeleton.get_bone_name(bone_index))
		bones[bone_name] = {
			"position": skeleton.get_bone_pose_position(bone_index),
			"rotation": skeleton.get_bone_pose_rotation(bone_index),
			"scale": skeleton.get_bone_pose_scale(bone_index),
		}
	var keyframe := {
		"frame": maxi(0, frame),
		"bones": bones,
		"contacts": contacts.duplicate(true),
	}
	for index in range(keyframes.size()):
		if int(keyframes[index].get("frame", -1)) == frame:
			keyframes[index] = keyframe
			return index
	keyframes.append(keyframe)
	keyframes.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("frame", 0)) < int(b.get("frame", 0))
	)
	return keyframes.find(keyframe)


func copy_pose(index: int) -> bool:
	if index < 0 or index >= keyframes.size():
		return false
	clipboard = (keyframes[index].get("bones", {}) as Dictionary).duplicate(true)
	return not clipboard.is_empty()


func copy_latest_pose() -> bool:
	return copy_pose(keyframes.size() - 1)


func paste_pose(skeleton: Skeleton3D) -> bool:
	if skeleton == null or clipboard.is_empty():
		return false
	_apply_bones(skeleton, clipboard)
	return true


func apply_keyframe(skeleton: Skeleton3D, index: int) -> bool:
	if skeleton == null or index < 0 or index >= keyframes.size():
		return false
	var bones: Dictionary = keyframes[index].get("bones", {})
	_apply_bones(skeleton, bones)
	return true


func latest_frame() -> int:
	if keyframes.is_empty():
		return -1
	return int(keyframes[-1].get("frame", -1))


func summary() -> String:
	if keyframes.is_empty():
		return "KEY POSES: none yet"
	var frames: PackedStringArray = []
	for keyframe in keyframes:
		frames.append(str(int(keyframe.get("frame", 0))))
	return "KEY POSES: %s" % "  →  ".join(frames)


func build_animation(skeleton_path: NodePath, fps: float = 30.0, smooth: bool = true) -> Animation:
	if keyframes.is_empty():
		return null
	var safe_fps := maxf(fps, 1.0)
	var result := Animation.new()
	result.step = 1.0 / safe_fps
	result.loop_mode = Animation.LOOP_NONE
	result.length = maxf(float(maxi(1, latest_frame())) / safe_fps, result.step)
	var first_bones: Dictionary = keyframes[0].get("bones", {})
	for bone_name in first_bones.keys():
		var position_track := result.add_track(Animation.TYPE_POSITION_3D)
		var rotation_track := result.add_track(Animation.TYPE_ROTATION_3D)
		var scale_track := result.add_track(Animation.TYPE_SCALE_3D)
		var track_path := NodePath("%s:%s" % [str(skeleton_path), str(bone_name)])
		for track in [position_track, rotation_track, scale_track]:
			result.track_set_path(track, track_path)
			result.track_set_interpolation_type(
				track,
				Animation.INTERPOLATION_LINEAR if smooth else Animation.INTERPOLATION_NEAREST
			)
			result.track_set_interpolation_loop_wrap(track, false)
		for keyframe in keyframes:
			var pose_bones: Dictionary = keyframe.get("bones", {})
			if not pose_bones.has(bone_name):
				continue
			var pose: Dictionary = pose_bones[bone_name]
			var time := float(int(keyframe.get("frame", 0))) / safe_fps
			result.track_insert_key(position_track, time, pose.get("position", Vector3.ZERO))
			result.track_insert_key(rotation_track, time, pose.get("rotation", Quaternion.IDENTITY))
			result.track_insert_key(scale_track, time, pose.get("scale", Vector3.ONE))
	return result


func _apply_bones(skeleton: Skeleton3D, bones: Dictionary) -> void:
	for raw_bone_name in bones.keys():
		var bone_name := String(raw_bone_name)
		var bone_index := skeleton.find_bone(bone_name)
		if bone_index < 0:
			continue
		var pose: Dictionary = bones[raw_bone_name]
		skeleton.set_bone_pose_position(bone_index, pose.get("position", Vector3.ZERO))
		skeleton.set_bone_pose_rotation(bone_index, pose.get("rotation", Quaternion.IDENTITY))
		skeleton.set_bone_pose_scale(bone_index, pose.get("scale", Vector3.ONE))
	skeleton.force_update_all_bone_transforms()
