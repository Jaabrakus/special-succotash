class_name SocomAnimationCorrectionOverlay
extends RefCounted

## Shared authoring helpers for the per-animation correction tracks consumed by
## gameplay. Animation Studio edits these fields; the imported clip stays intact.

const FramePoseRuntime := preload(
	"res://scripts/player/operator_animation_frame_pose_runtime.gd"
)


static func resolve_clip_key(
	entry: Dictionary,
	state_slots: Dictionary,
	preferred_state: String = ""
) -> String:
	var resource_path := String(entry.get("path", ""))
	if not preferred_state.is_empty() and String(state_slots.get(preferred_state, "")) == resource_path:
		return preferred_state
	var matches: Array[String] = []
	for raw_state in state_slots.keys():
		var state_name := String(raw_state)
		if not resource_path.is_empty() and String(state_slots[raw_state]) == resource_path:
			matches.append(state_name)
	matches.sort()
	if not matches.is_empty():
		return matches[0]
	return String(entry.get("key", entry.get("name", "")))


static func sample(pose_keys: Dictionary, clip_key: String, frame: int) -> Dictionary:
	if clip_key.is_empty():
		return {}
	var runtime = FramePoseRuntime.new()
	runtime.configure(pose_keys)
	return runtime.sample([clip_key], float(maxi(frame, 0)) / 30.0)


static func store_key(
	pose_keys: Dictionary,
	clip_key: String,
	frame: int,
	pose: Dictionary
) -> Dictionary:
	var result := pose_keys.duplicate(true)
	if clip_key.is_empty() or pose.is_empty():
		return result
	var clip_frames: Dictionary = (
		(result.get(clip_key, {}) as Dictionary).duplicate(true)
		if result.get(clip_key, {}) is Dictionary
		else {}
	)
	clip_frames[str(maxi(frame, 0))] = pose.duplicate(true)
	result[clip_key] = clip_frames
	return result


static func delete_key(pose_keys: Dictionary, clip_key: String, frame: int) -> Dictionary:
	var result := pose_keys.duplicate(true)
	var raw_frames: Variant = result.get(clip_key, {})
	if not raw_frames is Dictionary:
		return result
	var frames := (raw_frames as Dictionary).duplicate(true)
	frames.erase(str(maxi(frame, 0)))
	if frames.is_empty():
		result.erase(clip_key)
	else:
		result[clip_key] = frames
	return result


static func joint_name_for_bone(bone_name: String) -> String:
	var lower := bone_name.to_lower()
	if "toe" in lower:
		return "left_toe" if _is_left(lower) else "right_toe"
	if "foot" in lower:
		return "left_foot" if _is_left(lower) else "right_foot"
	if "upleg" in lower or "upperleg" in lower or "legthigh" in lower:
		return "left_upper_leg" if _is_left(lower) else "right_upper_leg"
	if "leglower" in lower or lower.ends_with("leftleg") or lower.ends_with("rightleg"):
		return "left_lower_leg" if _is_left(lower) else "right_lower_leg"
	if "hips" in lower or "spinelower" in lower:
		return "hips"
	if "hand" in lower:
		return "left_hand" if _is_left(lower) else "right_hand"
	if "forearm" in lower or "armlower" in lower:
		return "left_forearm" if _is_left(lower) else "right_forearm"
	if "shoulder" in lower:
		return "left_shoulder" if _is_left(lower) else "right_shoulder"
	if "arm" in lower and not "hand" in lower:
		return "left_upper_arm" if _is_left(lower) else "right_upper_arm"
	if "head" in lower:
		return "head"
	if "neck" in lower:
		return "neck"
	if "spine2" in lower or "spineupper" in lower:
		return "spine2"
	if "spine1" in lower:
		return "spine1"
	if "spine" in lower and not "spinelower" in lower:
		return "spine"
	return ""


static func vector_map(value: Vector3) -> Dictionary:
	return {"x": value.x, "y": value.y, "z": value.z}


static func vector_from(raw: Variant, fallback: Vector3 = Vector3.ZERO) -> Vector3:
	if not raw is Dictionary:
		return fallback
	return Vector3(
		float((raw as Dictionary).get("x", fallback.x)),
		float((raw as Dictionary).get("y", fallback.y)),
		float((raw as Dictionary).get("z", fallback.z))
	)


static func _is_left(lower_bone_name: String) -> bool:
	return "left" in lower_bone_name or ".l" in lower_bone_name
