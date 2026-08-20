class_name SocomOperatorAnimationFramePoseRuntime
extends RefCounted

## Reads additive frame keys saved by Gunsmith. Imported animations remain
## unchanged; this layer only returns the visual correction for the current
## rendered frame.

const DEFAULT_FPS := 30.0

var fps: float = DEFAULT_FPS
var pose_keys: Dictionary = {}
var last_clip_key := ""
var last_frame: int = -1
var last_pose_active := false


func configure(raw_keys: Variant) -> void:
	pose_keys = raw_keys.duplicate(true) if raw_keys is Dictionary else {}
	last_clip_key = ""
	last_frame = -1
	last_pose_active = false


func sample(clip_candidates: Array, time_seconds: float) -> Dictionary:
	last_clip_key = _resolve_clip_key(clip_candidates)
	last_frame = maxi(0, int(round(maxf(time_seconds, 0.0) * fps)))
	last_pose_active = false
	if last_clip_key.is_empty():
		return {}
	var clip_frames: Variant = pose_keys.get(last_clip_key, {})
	if not clip_frames is Dictionary:
		return {}
	var frames := _sorted_frames(clip_frames)
	if frames.is_empty():
		return {}
	var exact: Variant = (clip_frames as Dictionary).get(str(last_frame), {})
	if exact is Dictionary and not (exact as Dictionary).is_empty():
		last_pose_active = true
		return (exact as Dictionary).duplicate(true)
	var previous := -1
	var following := -1
	for frame in frames:
		if frame < last_frame:
			previous = frame
		elif frame > last_frame:
			following = frame
			break
	# Match the Gunsmith curve contract: endpoint keys hold to the clip bounds.
	# Designers can add a later neutral key when a correction must recover.
	if previous < 0:
		var first_pose: Variant = (clip_frames as Dictionary).get(str(frames.front()), {})
		if first_pose is Dictionary:
			last_pose_active = true
			return (first_pose as Dictionary).duplicate(true)
		return {}
	if following < 0:
		var last_pose: Variant = (clip_frames as Dictionary).get(str(frames.back()), {})
		if last_pose is Dictionary:
			last_pose_active = true
			return (last_pose as Dictionary).duplicate(true)
		return {}
	var first: Dictionary = (clip_frames as Dictionary).get(str(previous), {})
	var second: Dictionary = (clip_frames as Dictionary).get(str(following), {})
	var weight := float(last_frame - previous) / float(following - previous)
	last_pose_active = true
	return _blend_pose(first, second, weight)


func key_count() -> int:
	var total := 0
	for raw_clip in pose_keys.values():
		if raw_clip is Dictionary:
			total += (raw_clip as Dictionary).size()
	return total


func get_debug_state() -> Dictionary:
	return {
		"saved_key_count": key_count(),
		"resolved_clip_key": last_clip_key,
		"sampled_frame": last_frame,
		"pose_active": last_pose_active,
	}


func _resolve_clip_key(candidates: Array) -> String:
	for raw_candidate in candidates:
		var candidate := String(raw_candidate)
		if pose_keys.has(candidate):
			return candidate
		var file_name := candidate.get_file()
		if pose_keys.has(file_name):
			return file_name
		var base_name := file_name.get_basename()
		if pose_keys.has(base_name):
			return base_name
	return ""


func _sorted_frames(raw_frames: Variant) -> Array[int]:
	var result: Array[int] = []
	if raw_frames is Dictionary:
		for raw_frame in (raw_frames as Dictionary).keys():
			result.append(int(raw_frame))
	result.sort()
	return result


func _blend_pose(first: Dictionary, second: Dictionary, weight: float) -> Dictionary:
	var result := first.duplicate(true)
	for field in [
		"right_elbow_pole", "left_elbow_pole",
		"right_hand_target", "left_hand_target",
	]:
		if first.has(field) and second.has(field):
			result[field] = _blend_vector_map(first[field], second[field], weight)
	var first_rotations: Dictionary = first.get("joint_rotations", {})
	var second_rotations: Dictionary = second.get("joint_rotations", {})
	var rotations: Dictionary = {}
	for joint_name in first_rotations.keys():
		if second_rotations.has(joint_name):
			rotations[joint_name] = _blend_vector_map(
				first_rotations[joint_name],
				second_rotations[joint_name],
				weight
			)
	result["joint_rotations"] = rotations
	return result


func _blend_vector_map(first: Variant, second: Variant, weight: float) -> Dictionary:
	if not first is Dictionary or not second is Dictionary:
		return first.duplicate(true) if first is Dictionary else {}
	return {
		"x": lerpf(float(first.get("x", 0.0)), float(second.get("x", 0.0)), weight),
		"y": lerpf(float(first.get("y", 0.0)), float(second.get("y", 0.0)), weight),
		"z": lerpf(float(first.get("z", 0.0)), float(second.get("z", 0.0)), weight),
	}
