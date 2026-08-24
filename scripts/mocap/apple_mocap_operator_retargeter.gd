class_name SocomAppleMocapOperatorRetargeter
extends RefCounted

## Builds a review animation for the 65-bone operator. Apple landmarks are
## aligned once to the operator body frame, then solved through the target
## hierarchy. The result is visual-only and never owns gameplay movement.

const SKELETON_CONTRACT := preload("res://scripts/player/operator_skeleton_contract.gd")

const TRACK_BONES := [
	"mixamorig_Hips",
	"mixamorig_Spine",
	"mixamorig_Spine1",
	"mixamorig_Neck",
	"mixamorig_Head",
	"mixamorig_LeftArm",
	"mixamorig_LeftForeArm",
	"mixamorig_RightArm",
	"mixamorig_RightForeArm",
	"mixamorig_LeftUpLeg",
	"mixamorig_LeftLeg",
	"mixamorig_RightUpLeg",
	"mixamorig_RightLeg",
]

const SEGMENT_SOLVES := {
	"mixamorig_Spine": ["human_root_3D", "human_spine_3D", "mixamorig_Spine1"],
	"mixamorig_Spine1": ["human_spine_3D", "human_center_shoulder_3D", "mixamorig_Spine2"],
	"mixamorig_Neck": ["human_center_shoulder_3D", "human_center_head_3D", "mixamorig_Head"],
	"mixamorig_Head": ["human_center_head_3D", "human_top_head_3D", "mixamorig_HeadTop_End"],
	"mixamorig_LeftArm": ["human_left_shoulder_3D", "human_left_elbow_3D", "mixamorig_LeftForeArm"],
	"mixamorig_LeftForeArm": ["human_left_elbow_3D", "human_left_wrist_3D", "mixamorig_LeftHand"],
	"mixamorig_RightArm": ["human_right_shoulder_3D", "human_right_elbow_3D", "mixamorig_RightForeArm"],
	"mixamorig_RightForeArm": ["human_right_elbow_3D", "human_right_wrist_3D", "mixamorig_RightHand"],
	"mixamorig_LeftUpLeg": ["human_left_hip_3D", "human_left_knee_3D", "mixamorig_LeftLeg"],
	"mixamorig_LeftLeg": ["human_left_knee_3D", "human_left_ankle_3D", "mixamorig_LeftFoot"],
	"mixamorig_RightUpLeg": ["human_right_hip_3D", "human_right_knee_3D", "mixamorig_RightLeg"],
	"mixamorig_RightLeg": ["human_right_knee_3D", "human_right_ankle_3D", "mixamorig_RightFoot"],
}

const MAX_ROTATION_DEGREES := {
	"mixamorig_Hips": 65.0,
	"mixamorig_Spine": 38.0,
	"mixamorig_Spine1": 38.0,
	"mixamorig_Neck": 42.0,
	"mixamorig_Head": 48.0,
	"mixamorig_LeftArm": 115.0,
	"mixamorig_LeftForeArm": 145.0,
	"mixamorig_RightArm": 115.0,
	"mixamorig_RightForeArm": 145.0,
	"mixamorig_LeftUpLeg": 100.0,
	"mixamorig_LeftLeg": 145.0,
	"mixamorig_RightUpLeg": 100.0,
	"mixamorig_RightLeg": 145.0,
}

const TEMPORAL_BLEND := 0.72
const LOWER_BODY_BONES := [
	"mixamorig_Hips",
	"mixamorig_LeftUpLeg",
	"mixamorig_LeftLeg",
	"mixamorig_RightUpLeg",
	"mixamorig_RightLeg",
]


func build_animation(
	processed: Dictionary,
	skeleton: Skeleton3D,
	skeleton_path: NodePath = NodePath("."),
	options: Dictionary = {}
) -> Animation:
	if not bool(processed.get("ok", false)) or skeleton == null:
		return null
	SKELETON_CONTRACT.ensure_65_bones(skeleton)
	var frames: Array = processed.get("frames", [])
	if frames.is_empty():
		return null
	var source_reference := _source_reference_basis(frames)
	var target_reference := _target_reference_basis(skeleton)
	if not bool(source_reference.get("valid", false)) or not bool(target_reference.get("valid", false)):
		return null
	var source_to_target := (
		(target_reference["basis"] as Basis)
		* (source_reference["basis"] as Basis).inverse()
	).orthonormalized()
	var fps := clampf(float(processed.get("fps", 30.0)), 1.0, 60.0)
	var animation := Animation.new()
	animation.length = maxf(
		float(processed.get("duration", float(frames.size() - 1) / fps)),
		float(frames.size() - 1) / fps
	)
	animation.loop_mode = Animation.LOOP_NONE
	var include_lower_body := bool(options.get("include_lower_body", true))
	var tracks := _create_rotation_tracks(animation, skeleton, skeleton_path, include_lower_body)
	var original_poses := _capture_pose_rotations(skeleton)
	var previous := {}
	for frame_index in range(frames.size()):
		var frame: Dictionary = frames[frame_index] if frames[frame_index] is Dictionary else {}
		var time := clampf(float(frame.get("time", float(frame_index) / fps)), 0.0, animation.length)
		_reset_solve_pose(skeleton)
		var solved := _solve_frame(
			frame,
			skeleton,
			source_to_target,
			target_reference["basis"] as Basis,
			previous,
			include_lower_body
		)
		for bone_name in tracks:
			var rotation: Quaternion = solved.get(bone_name, previous.get(bone_name, Quaternion.IDENTITY))
			skeleton.set_bone_pose_rotation(skeleton.find_bone(bone_name), rotation)
			animation.rotation_track_insert_key(int(tracks[bone_name]), time, rotation)
			previous[bone_name] = rotation
	_restore_pose_rotations(skeleton, original_poses)
	animation.set_meta("source", "apple_vision_3d")
	animation.set_meta("processed_schema", str(processed.get("schema", "")))
	animation.set_meta("source_video", str(processed.get("source_video", "")))
	animation.set_meta("in_place", bool(processed.get("in_place", true)))
	animation.set_meta("root_translation", "locked_for_review")
	animation.set_meta("retarget_solver", "operator_rest_space_v2")
	animation.set_meta("body_regions", "full_body" if include_lower_body else "upper_body_only")
	animation.set_meta("motion_features", processed.get("motion_features", []))
	animation.set_meta("review_status", "PENDING")
	return animation


func save_review_animation(
	animation: Animation,
	requested_name: String,
	overwrite_existing: bool = false
) -> Dictionary:
	if animation == null:
		return {"ok": false, "error": "No animation was built."}
	var safe_name := requested_name.to_snake_case().validate_filename()
	if safe_name.is_empty():
		safe_name = "apple_motion_review"
	var directory := "user://apple_mocap/review"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var path := "%s/%s.tres" % [directory, safe_name]
	var suffix := 2
	while not overwrite_existing and FileAccess.file_exists(path):
		path = "%s/%s_%d.tres" % [directory, safe_name, suffix]
		suffix += 1
	animation.resource_name = path.get_file().get_basename()
	var error := ResourceSaver.save(animation, path)
	return {
		"ok": error == OK,
		"path": path if error == OK else "",
		"error": "" if error == OK else error_string(error),
	}


func _solve_frame(
	frame: Dictionary,
	skeleton: Skeleton3D,
	source_to_target: Basis,
	target_reference: Basis,
	previous: Dictionary,
	include_lower_body: bool
) -> Dictionary:
	var solved := {}
	var hips_rotation := Quaternion.IDENTITY
	if include_lower_body:
		var source_body := _frame_body_basis(frame)
		hips_rotation = previous.get("mixamorig_Hips", Quaternion.IDENTITY) as Quaternion
		if bool(source_body.get("valid", false)):
			var desired_body := (source_to_target * (source_body["basis"] as Basis)).orthonormalized()
			var global_delta := (desired_body * target_reference.inverse()).orthonormalized()
			hips_rotation = _global_delta_to_local_pose(skeleton, "mixamorig_Hips", global_delta)
			hips_rotation = _bounded_smoothed_rotation("mixamorig_Hips", hips_rotation, previous)
	_set_solve_rotation(skeleton, "mixamorig_Hips", hips_rotation)
	if include_lower_body:
		solved["mixamorig_Hips"] = hips_rotation
	for bone_name in SEGMENT_SOLVES:
		if not include_lower_body and LOWER_BODY_BONES.has(bone_name):
			continue
		var segment: Array = SEGMENT_SOLVES[bone_name]
		var source_direction: Variant = _frame_direction(frame, str(segment[0]), str(segment[1]))
		var rotation := previous.get(bone_name, Quaternion.IDENTITY) as Quaternion
		if source_direction is Vector3:
			var desired := (source_to_target * (source_direction as Vector3)).normalized()
			var candidate := _solve_segment_pose(skeleton, bone_name, str(segment[2]), desired)
			rotation = _bounded_smoothed_rotation(bone_name, candidate, previous)
		_set_solve_rotation(skeleton, bone_name, rotation)
		solved[bone_name] = rotation
	return solved


func _solve_segment_pose(
	skeleton: Skeleton3D,
	bone_name: String,
	child_name: String,
	desired_direction: Vector3
) -> Quaternion:
	var bone_index := skeleton.find_bone(bone_name)
	var child_index := skeleton.find_bone(child_name)
	if bone_index < 0 or child_index < 0 or desired_direction.length_squared() <= 0.000001:
		return Quaternion.IDENTITY
	var current_global := skeleton.get_bone_global_pose(bone_index).basis.orthonormalized()
	var child_local := skeleton.get_bone_rest(child_index).origin
	if child_local.length_squared() <= 0.000001:
		return Quaternion.IDENTITY
	var current_direction := (current_global * child_local).normalized()
	var global_delta := Basis(Quaternion(current_direction, desired_direction.normalized()))
	return (
		current_global.inverse() * global_delta * current_global
	).orthonormalized().get_rotation_quaternion().normalized()


func _global_delta_to_local_pose(
	skeleton: Skeleton3D,
	bone_name: String,
	global_delta: Basis
) -> Quaternion:
	var bone_index := skeleton.find_bone(bone_name)
	if bone_index < 0:
		return Quaternion.IDENTITY
	var current_global := skeleton.get_bone_global_pose(bone_index).basis.orthonormalized()
	return (
		current_global.inverse() * global_delta * current_global
	).orthonormalized().get_rotation_quaternion().normalized()


func _bounded_smoothed_rotation(
	bone_name: String,
	candidate: Quaternion,
	previous: Dictionary
) -> Quaternion:
	var bounded := _clamp_rotation(candidate, float(MAX_ROTATION_DEGREES.get(bone_name, 90.0)))
	if previous.has(bone_name):
		bounded = (previous[bone_name] as Quaternion).slerp(bounded, TEMPORAL_BLEND).normalized()
	return bounded


func _clamp_rotation(rotation: Quaternion, maximum_degrees: float) -> Quaternion:
	var normalized := rotation.normalized()
	if normalized.w < 0.0:
		normalized = Quaternion(-normalized.x, -normalized.y, -normalized.z, -normalized.w)
	var angle := normalized.get_angle()
	var maximum := deg_to_rad(maximum_degrees)
	if angle <= maximum or angle <= 0.000001:
		return normalized
	return Quaternion.IDENTITY.slerp(normalized, maximum / angle).normalized()


func _source_reference_basis(frames: Array) -> Dictionary:
	for raw_frame in frames:
		if raw_frame is Dictionary:
			var body := _frame_body_basis(raw_frame)
			if bool(body.get("valid", false)):
				return body
	return {"valid": false, "basis": Basis.IDENTITY}


func _frame_body_basis(frame: Dictionary) -> Dictionary:
	var required := [
		"human_root_3D",
		"human_center_shoulder_3D",
		"human_left_shoulder_3D",
		"human_right_shoulder_3D",
		"human_left_hip_3D",
		"human_right_hip_3D",
	]
	var points := {}
	for joint_name in required:
		var point: Variant = _frame_joint(frame, joint_name)
		if not point is Vector3:
			return {"valid": false, "basis": Basis.IDENTITY}
		points[joint_name] = point
	return _body_basis(
		points["human_left_hip_3D"],
		points["human_right_hip_3D"],
		points["human_left_shoulder_3D"],
		points["human_right_shoulder_3D"],
		points["human_root_3D"],
		points["human_center_shoulder_3D"]
	)


func _target_reference_basis(skeleton: Skeleton3D) -> Dictionary:
	var names := [
		"mixamorig_LeftUpLeg",
		"mixamorig_RightUpLeg",
		"mixamorig_LeftArm",
		"mixamorig_RightArm",
		"mixamorig_Hips",
		"mixamorig_Spine2",
	]
	var points := {}
	for bone_name in names:
		var index := skeleton.find_bone(bone_name)
		if index < 0:
			return {"valid": false, "basis": Basis.IDENTITY}
		points[bone_name] = _bone_global_rest(skeleton, index).origin
	return _body_basis(
		points["mixamorig_LeftUpLeg"],
		points["mixamorig_RightUpLeg"],
		points["mixamorig_LeftArm"],
		points["mixamorig_RightArm"],
		points["mixamorig_Hips"],
		points["mixamorig_Spine2"]
	)


func _body_basis(
	left_hip: Vector3,
	right_hip: Vector3,
	left_shoulder: Vector3,
	right_shoulder: Vector3,
	root: Vector3,
	shoulder_center: Vector3
) -> Dictionary:
	var hip_right := right_hip - left_hip
	var shoulder_right := right_shoulder - left_shoulder
	var up := shoulder_center - root
	if hip_right.length_squared() <= 0.000001 or shoulder_right.length_squared() <= 0.000001 or up.length_squared() <= 0.000001:
		return {"valid": false, "basis": Basis.IDENTITY}
	var right := (hip_right.normalized() + shoulder_right.normalized()).normalized()
	var vertical := up.normalized()
	right = (right - vertical * right.dot(vertical)).normalized()
	if right.length_squared() <= 0.000001:
		return {"valid": false, "basis": Basis.IDENTITY}
	var backward := right.cross(vertical).normalized()
	if backward.length_squared() <= 0.000001:
		return {"valid": false, "basis": Basis.IDENTITY}
	right = vertical.cross(backward).normalized()
	return {"valid": true, "basis": Basis(right, vertical, backward).orthonormalized()}


func _frame_direction(frame: Dictionary, start_name: String, end_name: String) -> Variant:
	var start: Variant = _frame_joint(frame, start_name)
	var end: Variant = _frame_joint(frame, end_name)
	if not start is Vector3 or not end is Vector3:
		return null
	var direction := (end as Vector3) - (start as Vector3)
	return direction.normalized() if direction.length_squared() > 0.000001 else null


func _frame_joint(frame: Dictionary, joint_name: String) -> Variant:
	var joints: Dictionary = frame.get("joints", {})
	var sample: Variant = joints.get(joint_name, null)
	if not sample is Dictionary:
		return null
	var position: Variant = (sample as Dictionary).get("position", null)
	if not position is Dictionary:
		return null
	return Vector3(
		float((position as Dictionary).get("x", 0.0)),
		float((position as Dictionary).get("y", 0.0)),
		float((position as Dictionary).get("z", 0.0))
	)


func _create_rotation_tracks(
	animation: Animation,
	skeleton: Skeleton3D,
	skeleton_path: NodePath,
	include_lower_body: bool
) -> Dictionary:
	var tracks := {}
	for bone_name in TRACK_BONES:
		if not include_lower_body and LOWER_BODY_BONES.has(bone_name):
			continue
		if skeleton.find_bone(bone_name) < 0:
			continue
		var track := animation.add_track(Animation.TYPE_ROTATION_3D)
		animation.track_set_path(track, NodePath("%s:%s" % [str(skeleton_path), bone_name]))
		animation.track_set_interpolation_type(track, Animation.INTERPOLATION_LINEAR)
		tracks[bone_name] = track
	return tracks


func _capture_pose_rotations(skeleton: Skeleton3D) -> Dictionary:
	var poses := {}
	for bone_name in TRACK_BONES:
		var index := skeleton.find_bone(bone_name)
		if index >= 0:
			poses[bone_name] = skeleton.get_bone_pose_rotation(index)
	return poses


func _reset_solve_pose(skeleton: Skeleton3D) -> void:
	for bone_name in TRACK_BONES:
		_set_solve_rotation(skeleton, bone_name, Quaternion.IDENTITY)


func _restore_pose_rotations(skeleton: Skeleton3D, poses: Dictionary) -> void:
	for bone_name in poses:
		_set_solve_rotation(skeleton, bone_name, poses[bone_name])


func _set_solve_rotation(skeleton: Skeleton3D, bone_name: String, rotation: Quaternion) -> void:
	var index := skeleton.find_bone(bone_name)
	if index >= 0:
		skeleton.set_bone_pose_rotation(index, rotation.normalized())


func _bone_global_rest(skeleton: Skeleton3D, bone_index: int) -> Transform3D:
	var chain: Array[Transform3D] = []
	var current := bone_index
	while current >= 0:
		chain.push_front(skeleton.get_bone_rest(current))
		current = skeleton.get_bone_parent(current)
	var result := Transform3D.IDENTITY
	for local_rest in chain:
		result *= local_rest
	return result
