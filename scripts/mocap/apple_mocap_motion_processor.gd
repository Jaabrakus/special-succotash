class_name SocomAppleMocapMotionProcessor
extends RefCounted

## Converts Apple Vision landmark frames into deterministic, reviewable motion.
## This service owns no UI and never changes gameplay movement or shot state.

const JOINTS := [
	"human_root_3D",
	"human_spine_3D",
	"human_center_shoulder_3D",
	"human_center_head_3D",
	"human_top_head_3D",
	"human_left_shoulder_3D",
	"human_left_elbow_3D",
	"human_left_wrist_3D",
	"human_right_shoulder_3D",
	"human_right_elbow_3D",
	"human_right_wrist_3D",
	"human_left_hip_3D",
	"human_left_knee_3D",
	"human_left_ankle_3D",
	"human_right_hip_3D",
	"human_right_knee_3D",
	"human_right_ankle_3D",
]

const BONE_SEGMENTS := {
	"mixamorig_Spine": ["human_root_3D", "human_spine_3D"],
	"mixamorig_Spine1": ["human_spine_3D", "human_center_shoulder_3D"],
	"mixamorig_Neck": ["human_center_shoulder_3D", "human_center_head_3D"],
	"mixamorig_Head": ["human_center_head_3D", "human_top_head_3D"],
	"mixamorig_LeftArm": ["human_left_shoulder_3D", "human_left_elbow_3D"],
	"mixamorig_LeftForeArm": ["human_left_elbow_3D", "human_left_wrist_3D"],
	"mixamorig_RightArm": ["human_right_shoulder_3D", "human_right_elbow_3D"],
	"mixamorig_RightForeArm": ["human_right_elbow_3D", "human_right_wrist_3D"],
	"mixamorig_LeftUpLeg": ["human_left_hip_3D", "human_left_knee_3D"],
	"mixamorig_LeftLeg": ["human_left_knee_3D", "human_left_ankle_3D"],
	"mixamorig_RightUpLeg": ["human_right_hip_3D", "human_right_knee_3D"],
	"mixamorig_RightLeg": ["human_right_knee_3D", "human_right_ankle_3D"],
}


func process(raw_document: Dictionary, options: Dictionary = {}) -> Dictionary:
	var fps := clampf(float(raw_document.get("fps", 30.0)), 1.0, 60.0)
	var raw_frames: Array = raw_document.get("frames", [])
	if raw_frames.is_empty():
		return {"ok": false, "errors": ["The Apple motion document has no frames."]}
	var maximum_gap := maxi(int(options.get("maximum_repair_gap_frames", roundi(fps * 0.35))), 1)
	var smoothing_passes := clampi(int(options.get("smoothing_passes", 2)), 0, 6)
	var target_height := clampf(float(options.get("target_height_m", 1.80)), 1.20, 2.30)
	var frames := _read_frames(raw_frames, fps)
	var repair_count := _repair_missing_samples(frames, maximum_gap)
	_smooth_samples(frames, smoothing_passes)
	var scale_factor := _normalize_scale_and_axes(frames, raw_frames, target_height)
	var ground_y := _ground_height(frames)
	_align_ground(frames, ground_y)
	var contacts := _detect_foot_contacts(frames, fps)
	_apply_foot_locks(frames, contacts)
	var root_motion := _convert_to_in_place(frames)
	var reference_directions := _reference_bone_directions(frames)
	var output_frames: Array[Dictionary] = []
	for index in range(frames.size()):
		var frame: Dictionary = frames[index]
		var joints_output := {}
		for joint_name in JOINTS:
			var position: Variant = frame["joints"].get(joint_name, null)
			if position is Vector3:
				joints_output[joint_name] = {
					"position": _vector_data(position),
					"confidence": float(frame["confidence"].get(joint_name, 0.0)),
				}
		var frame_contacts: Dictionary = contacts[index]
		output_frames.append({
			"frame": int(frame.get("frame", index)),
			"time": float(frame.get("time", float(index) / fps)),
			"detected": bool(frame.get("detected", false)),
			"repaired": bool(frame.get("repaired", false)),
			"joints": joints_output,
			"root_motion": _vector_data(root_motion[index]),
			"contacts": frame_contacts.duplicate(true),
			"bone_directions": _bone_direction_data(frame["joints"]),
			"bone_rotations": _bone_rotation_data(frame["joints"], reference_directions),
		})
	return {
		"ok": true,
		"schema": "socom_apple_body_motion_processed_v1",
		"source_schema": str(raw_document.get("schema", "")),
		"source_video": str(raw_document.get("source_video", "")),
		"fps": fps,
		"duration": float(raw_document.get("duration", float(frames.size() - 1) / fps)),
		"frame_count": frames.size(),
		"joint_count": JOINTS.size(),
		"repaired_samples": repair_count,
		"scale_factor": scale_factor,
		"ground_y_before_alignment": ground_y,
		"in_place": true,
		"coordinate_space": "Godot operator-local meters; Y up; forward is -Z",
		"frames": output_frames,
		"motion_features": _motion_features(root_motion, contacts, fps),
		"errors": [],
	}


func _read_frames(raw_frames: Array, fps: float) -> Array[Dictionary]:
	var frames: Array[Dictionary] = []
	for index in range(raw_frames.size()):
		var raw: Dictionary = raw_frames[index] if raw_frames[index] is Dictionary else {}
		var positions := {}
		var confidences := {}
		var raw_joints: Dictionary = raw.get("joints", {})
		for joint_name in JOINTS:
			var raw_joint: Variant = raw_joints.get(joint_name, null)
			if not raw_joint is Dictionary:
				continue
			var model: Variant = (raw_joint as Dictionary).get("model", null)
			if not model is Dictionary:
				continue
			positions[joint_name] = _vector_from_data(model)
			confidences[joint_name] = clampf(float((raw_joint as Dictionary).get("confidence", 1.0)), 0.0, 1.0)
		frames.append({
			"frame": int(raw.get("frame", index)),
			"time": float(raw.get("time", float(index) / fps)),
			"detected": bool(raw.get("detected", false)),
			"repaired": false,
			"joints": positions,
			"confidence": confidences,
		})
	return frames


func _repair_missing_samples(frames: Array[Dictionary], maximum_gap: int) -> int:
	var repaired := 0
	for joint_name in JOINTS:
		for frame_index in range(frames.size()):
			if frames[frame_index]["joints"].has(joint_name):
				continue
			var previous := _nearest_sample(frames, joint_name, frame_index, -1, maximum_gap)
			var following := _nearest_sample(frames, joint_name, frame_index, 1, maximum_gap)
			var value: Variant = null
			var confidence := 0.0
			if previous["found"] and following["found"]:
				var span := float(following["index"] - previous["index"])
				var weight := float(frame_index - previous["index"]) / maxf(span, 1.0)
				value = (previous["value"] as Vector3).lerp(following["value"], weight)
				confidence = minf(float(previous["confidence"]), float(following["confidence"])) * 0.75
			elif previous["found"]:
				value = previous["value"]
				confidence = float(previous["confidence"]) * 0.50
			elif following["found"]:
				value = following["value"]
				confidence = float(following["confidence"]) * 0.50
			if value is Vector3:
				frames[frame_index]["joints"][joint_name] = value
				frames[frame_index]["confidence"][joint_name] = confidence
				frames[frame_index]["repaired"] = true
				repaired += 1
	return repaired


func _nearest_sample(
	frames: Array[Dictionary], joint_name: String, start: int, direction: int, limit: int
) -> Dictionary:
	for distance in range(1, limit + 1):
		var index := start + distance * direction
		if index < 0 or index >= frames.size():
			break
		if frames[index]["joints"].has(joint_name):
			return {
				"found": true,
				"index": index,
				"value": frames[index]["joints"][joint_name],
				"confidence": frames[index]["confidence"].get(joint_name, 1.0),
			}
	return {"found": false, "index": -1, "value": Vector3.ZERO, "confidence": 0.0}


func _smooth_samples(frames: Array[Dictionary], passes: int) -> void:
	for _pass in range(passes):
		var next_values: Array[Dictionary] = []
		for frame in frames:
			next_values.append((frame["joints"] as Dictionary).duplicate())
		for index in range(1, frames.size() - 1):
			for joint_name in JOINTS:
				if not (
					frames[index - 1]["joints"].has(joint_name)
					and frames[index]["joints"].has(joint_name)
					and frames[index + 1]["joints"].has(joint_name)
				):
					continue
				var previous: Vector3 = frames[index - 1]["joints"][joint_name]
				var current: Vector3 = frames[index]["joints"][joint_name]
				var following: Vector3 = frames[index + 1]["joints"][joint_name]
				next_values[index][joint_name] = previous * 0.25 + current * 0.50 + following * 0.25
		for index in range(frames.size()):
			frames[index]["joints"] = next_values[index]


func _normalize_scale_and_axes(
	frames: Array[Dictionary], raw_frames: Array, target_height: float
) -> float:
	var heights: Array[float] = []
	for raw in raw_frames:
		if raw is Dictionary:
			var height := float((raw as Dictionary).get("body_height", 0.0))
			if height > 0.50:
				heights.append(height)
	var measured_height := _median(heights)
	if measured_height <= 0.50:
		var estimated: Array[float] = []
		for frame in frames:
			var joints: Dictionary = frame["joints"]
			if joints.has("human_top_head_3D") and joints.has("human_left_ankle_3D") and joints.has("human_right_ankle_3D"):
				var ankles := (Vector3(joints["human_left_ankle_3D"]) + Vector3(joints["human_right_ankle_3D"])) * 0.5
				estimated.append(Vector3(joints["human_top_head_3D"]).distance_to(ankles))
		measured_height = _median(estimated)
	var scale_factor := target_height / measured_height if measured_height > 0.50 else 1.0
	for frame in frames:
		for joint_name in frame["joints"].keys():
			var apple: Vector3 = frame["joints"][joint_name]
			frame["joints"][joint_name] = Vector3(apple.x, apple.y, -apple.z) * scale_factor
	return scale_factor


func _ground_height(frames: Array[Dictionary]) -> float:
	var samples: Array[float] = []
	for frame in frames:
		for ankle in ["human_left_ankle_3D", "human_right_ankle_3D"]:
			if frame["joints"].has(ankle):
				samples.append(Vector3(frame["joints"][ankle]).y)
	if samples.is_empty():
		return 0.0
	samples.sort()
	return samples[mini(int(floor(samples.size() * 0.08)), samples.size() - 1)]


func _align_ground(frames: Array[Dictionary], ground_y: float) -> void:
	for frame in frames:
		for joint_name in frame["joints"].keys():
			var position: Vector3 = frame["joints"][joint_name]
			position.y -= ground_y
			frame["joints"][joint_name] = position


func _detect_foot_contacts(frames: Array[Dictionary], fps: float) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	for index in range(frames.size()):
		var contacts := {}
		for side in ["left", "right"]:
			var ankle := "human_%s_ankle_3D" % side
			var position: Variant = frames[index]["joints"].get(ankle, null)
			var speed := INF
			if position is Vector3 and index > 0 and frames[index - 1]["joints"].has(ankle):
				speed = (position as Vector3).distance_to(frames[index - 1]["joints"][ankle]) * fps
			var previous_contact := bool(output[index - 1].get("%s_foot" % side, false)) if index > 0 else false
			var height_limit := 0.12 if previous_contact else 0.085
			var speed_limit := 0.34 if previous_contact else 0.22
			contacts["%s_foot" % side] = (
				position is Vector3
				and (position as Vector3).y <= height_limit
				and speed <= speed_limit
			)
			contacts["%s_speed_mps" % side] = speed if speed < INF else 0.0
		output.append(contacts)
	return output


func _apply_foot_locks(frames: Array[Dictionary], contacts: Array[Dictionary]) -> void:
	for side in ["left", "right"]:
		var ankle := "human_%s_ankle_3D" % side
		var key := "%s_foot" % side
		var lock := Vector3.ZERO
		var active := false
		for index in range(frames.size()):
			if bool(contacts[index].get(key, false)) and frames[index]["joints"].has(ankle):
				var position: Vector3 = frames[index]["joints"][ankle]
				if not active:
					lock = position
					active = true
				position.x = lock.x
				position.z = lock.z
				position.y = maxf(position.y, 0.0)
				frames[index]["joints"][ankle] = position
			else:
				active = false


func _convert_to_in_place(frames: Array[Dictionary]) -> Array[Vector3]:
	var root_motion: Array[Vector3] = []
	var first_root := Vector3.ZERO
	var has_first := false
	for frame in frames:
		var root_value: Variant = frame["joints"].get("human_root_3D", null)
		if not root_value is Vector3:
			root_motion.append(root_motion[-1] if not root_motion.is_empty() else Vector3.ZERO)
			continue
		var root := root_value as Vector3
		if not has_first:
			first_root = root
			has_first = true
		var motion := Vector3(root.x - first_root.x, 0.0, root.z - first_root.z)
		root_motion.append(motion)
		for joint_name in frame["joints"].keys():
			var position: Vector3 = frame["joints"][joint_name]
			position.x -= root.x
			position.z -= root.z
			frame["joints"][joint_name] = position
	return root_motion


func _reference_bone_directions(frames: Array[Dictionary]) -> Dictionary:
	for frame in frames:
		var directions := _bone_directions(frame["joints"])
		if directions.size() >= BONE_SEGMENTS.size() / 2:
			return directions
	return {}


func _bone_directions(joints: Dictionary) -> Dictionary:
	var output := {}
	for bone_name in BONE_SEGMENTS:
		var segment: Array = BONE_SEGMENTS[bone_name]
		if not (joints.has(segment[0]) and joints.has(segment[1])):
			continue
		var direction := Vector3(joints[segment[1]]) - Vector3(joints[segment[0]])
		if direction.length_squared() > 0.000001:
			output[bone_name] = direction.normalized()
	return output


func _bone_direction_data(joints: Dictionary) -> Dictionary:
	var output := {}
	for bone_name in _bone_directions(joints):
		output[bone_name] = _vector_data(_bone_directions(joints)[bone_name])
	return output


func _bone_rotation_data(joints: Dictionary, reference: Dictionary) -> Dictionary:
	var output := {}
	var directions := _bone_directions(joints)
	for bone_name in directions:
		if not reference.has(bone_name):
			continue
		var rotation := Quaternion(Vector3(reference[bone_name]), Vector3(directions[bone_name])).normalized()
		output[bone_name] = {
			"x": rotation.x,
			"y": rotation.y,
			"z": rotation.z,
			"w": rotation.w,
		}
	return output


func _motion_features(
	root_motion: Array[Vector3], contacts: Array[Dictionary], fps: float
) -> Array[Dictionary]:
	var features: Array[Dictionary] = []
	for index in range(root_motion.size()):
		var velocity := Vector3.ZERO
		if index > 0:
			velocity = (root_motion[index] - root_motion[index - 1]) * fps
		features.append({
			"frame": index,
			"root_velocity": _vector_data(velocity),
			"speed_mps": Vector2(velocity.x, velocity.z).length(),
			"left_foot_contact": bool(contacts[index].get("left_foot", false)),
			"right_foot_contact": bool(contacts[index].get("right_foot", false)),
		})
	return features


func _median(values: Array[float]) -> float:
	if values.is_empty():
		return 0.0
	values.sort()
	var middle := values.size() / 2
	return values[middle] if values.size() % 2 == 1 else (values[middle - 1] + values[middle]) * 0.5


func _vector_from_data(data: Dictionary) -> Vector3:
	return Vector3(float(data.get("x", 0.0)), float(data.get("y", 0.0)), float(data.get("z", 0.0)))


func _vector_data(value: Vector3) -> Dictionary:
	return {"x": value.x, "y": value.y, "z": value.z}
