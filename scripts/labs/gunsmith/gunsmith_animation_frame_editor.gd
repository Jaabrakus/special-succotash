class_name GunsmithAnimationFrameEditor
extends RefCounted

## Stores additive Gunsmith pose keys without modifying imported animation data.

const DEFAULT_FPS := 30.0

var active := false
var playing := false
var slot_name := ""
var clip_name: StringName = &""
var time_seconds := 0.0
var duration_seconds := 0.0
var fps := DEFAULT_FPS
var pose_keys: Dictionary = {}


func load_data(raw_data: Variant) -> void:
	pose_keys = raw_data.duplicate(true) if raw_data is Dictionary else {}


func save_data() -> Dictionary:
	return pose_keys.duplicate(true)


func begin(new_slot: String, new_clip: StringName, duration: float) -> void:
	active = true
	playing = false
	slot_name = new_slot
	clip_name = new_clip
	duration_seconds = maxf(duration, 0.0)
	time_seconds = 0.0


func stop() -> void:
	active = false
	playing = false
	slot_name = ""
	clip_name = &""
	time_seconds = 0.0
	duration_seconds = 0.0


func set_time(value: float) -> void:
	time_seconds = clampf(value, 0.0, duration_seconds)


func step_frames(frame_delta: int) -> void:
	set_time(time_seconds + float(frame_delta) / maxf(fps, 1.0))


func frame_index() -> int:
	return maxi(0, int(round(time_seconds * fps)))


func frame_count() -> int:
	return maxi(1, int(round(duration_seconds * fps)))


func clip_key() -> String:
	return String(clip_name)


func store_current_pose(pose_data: Dictionary) -> void:
	if not active or clip_name == &"":
		return
	var clip_keys: Dictionary = pose_keys.get(clip_key(), {}).duplicate(true)
	clip_keys[str(frame_index())] = pose_data.duplicate(true)
	pose_keys[clip_key()] = clip_keys


func current_pose() -> Dictionary:
	if not active or clip_name == &"":
		return {}
	var clip_keys: Dictionary = pose_keys.get(clip_key(), {})
	var raw_pose: Variant = clip_keys.get(str(frame_index()), {})
	return raw_pose.duplicate(true) if raw_pose is Dictionary else {}


func saved_frame_indices() -> Array[int]:
	var result: Array[int] = []
	var clip_keys: Variant = pose_keys.get(clip_key(), {})
	if clip_keys is Dictionary:
		for raw_frame in (clip_keys as Dictionary).keys():
			result.append(int(raw_frame))
	result.sort()
	return result


func sampled_pose() -> Dictionary:
	var exact := current_pose()
	if not exact.is_empty():
		return exact
	var frames := saved_frame_indices()
	if frames.is_empty():
		return {}
	var current := frame_index()
	var previous := -1
	var following := -1
	for frame in frames:
		if frame < current:
			previous = frame
		elif frame > current:
			following = frame
			break
	var clip_keys: Dictionary = pose_keys.get(clip_key(), {})
	# Hold the closest authored correction through either open end of the clip.
	# A later key creates a blend and can return the correction to neutral.
	if previous < 0:
		var first_pose: Variant = clip_keys.get(str(frames.front()), {})
		return first_pose.duplicate(true) if first_pose is Dictionary else {}
	if following < 0:
		var last_pose: Variant = clip_keys.get(str(frames.back()), {})
		return last_pose.duplicate(true) if last_pose is Dictionary else {}
	var first: Dictionary = clip_keys.get(str(previous), {})
	var second: Dictionary = clip_keys.get(str(following), {})
	var weight := float(current - previous) / float(following - previous)
	return _blend_pose(first, second, weight)


func _blend_pose(first: Dictionary, second: Dictionary, weight: float) -> Dictionary:
	var result := first.duplicate(true)
	for field in [
		"right_elbow_pole",
		"left_elbow_pole",
		"right_hand_target",
		"left_hand_target",
		"weapon_hand_position_correction",
		"weapon_hand_rotation_correction_deg",
	]:
		result[field] = _blend_vector_map(first.get(field, {}), second.get(field, {}), weight)
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


func has_current_pose() -> bool:
	return not current_pose().is_empty()
