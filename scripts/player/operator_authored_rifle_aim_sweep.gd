class_name SocomOperatorAuthoredRifleAimSweep
extends RefCounted

## Adapts AGLS's authored rifle aim sweep to SOCOM's camera-owned aim intent.
## It applies pose deltas only; it never owns gameplay aim, either hand, or the
## weapon node. The mounted weapon continues to follow the animated helper bone.

const AIM_BONES: Array[StringName] = [
	&"mixamorig_Spine", &"mixamorig_Spine1", &"mixamorig_Spine2",
	&"mixamorig_Neck", &"mixamorig_Head",
	&"mixamorig_LeftShoulder", &"mixamorig_LeftArm",
	&"mixamorig_LeftForeArm", &"mixamorig_LeftHand",
	&"mixamorig_RightShoulder", &"mixamorig_RightArm",
	&"mixamorig_RightForeArm", &"mixamorig_RightHand",
	&"ik_hand_gun",
]

var skeleton: Skeleton3D
var enabled: bool = false
var center_pitch_degrees: float = -2.0
var source_min_pitch_degrees: float = -90.0
var source_max_pitch_degrees: float = 90.0
var invert_source_pitch: bool = true
var animations: Dictionary = {}
var track_maps: Dictionary = {}
var last_posture: StringName = &""
var last_clip: StringName = &""
var last_sample_time: float = 0.0
var last_source_pitch_degrees: float = 0.0
var last_weight: float = 0.0
var last_bone_count: int = 0


func configure(
	target_skeleton: Skeleton3D,
	animation_library: AnimationLibrary,
	raw_profile: Variant
) -> void:
	skeleton = target_skeleton
	animations.clear()
	track_maps.clear()
	var profile: Dictionary = (
		(raw_profile as Dictionary).duplicate(true)
		if raw_profile is Dictionary
		else {}
	)
	enabled = bool(profile.get("enabled", false))
	center_pitch_degrees = float(profile.get("center_pitch_degrees", -2.0))
	source_min_pitch_degrees = float(profile.get("source_min_pitch_degrees", -90.0))
	source_max_pitch_degrees = float(profile.get("source_max_pitch_degrees", 90.0))
	invert_source_pitch = bool(profile.get("invert_source_pitch", true))
	if not enabled or skeleton == null or animation_library == null:
		return
	var slots: Dictionary = profile.get("posture_clips", {})
	for posture_name in [&"STANDING", &"CROUCHED", &"PRONE"]:
		var clip_name := StringName(slots.get(String(posture_name), ""))
		if clip_name == &"" or not animation_library.has_animation(clip_name):
			continue
		var animation := animation_library.get_animation(clip_name)
		animations[posture_name] = animation
		track_maps[posture_name] = _build_track_map(animation)
		animation.set_meta("socom_aim_sweep_clip", clip_name)


func is_available(posture_name: StringName) -> bool:
	return enabled and animations.has(posture_name)


func apply(
	aim_yaw: float,
	aim_pitch: float,
	posture_name: StringName,
	weight: float
) -> bool:
	last_posture = posture_name
	last_weight = clampf(weight, 0.0, 1.0)
	last_bone_count = 0
	var helper_index := skeleton.find_bone(&"ik_hand_gun") if skeleton != null else -1
	if skeleton == null or not is_available(posture_name) or last_weight <= 0.0001:
		last_clip = &""
		return false
	var animation: Animation = animations[posture_name]
	var posture_tracks: Dictionary = track_maps.get(posture_name, {})
	last_clip = StringName(animation.get_meta("socom_aim_sweep_clip", &""))
	var source_pitch := clampf(
		rad_to_deg(aim_pitch) - center_pitch_degrees,
		source_min_pitch_degrees,
		source_max_pitch_degrees
	)
	last_source_pitch_degrees = source_pitch
	var normalized := inverse_lerp(
		source_min_pitch_degrees,
		source_max_pitch_degrees,
		source_pitch
	)
	if invert_source_pitch:
		normalized = 1.0 - normalized
	last_sample_time = clampf(normalized, 0.0, 1.0) * animation.length
	var center_time := animation.length * 0.5
	for raw_bone_name in posture_tracks:
		var bone_name := StringName(raw_bone_name)
		var bone_index := skeleton.find_bone(bone_name)
		if bone_index < 0:
			continue
		var channels: Dictionary = posture_tracks[bone_name]
		var position_track := int(channels.get("position", -1))
		if position_track >= 0:
			var center_position: Vector3 = animation.position_track_interpolate(
				position_track, center_time
			)
			var sampled_position: Vector3 = animation.position_track_interpolate(
				position_track, last_sample_time
			)
			var target_position := skeleton.get_bone_pose_position(bone_index) + (
				sampled_position - center_position
			) * last_weight
			skeleton.set_bone_pose_position(bone_index, target_position)
		var rotation_track := int(channels.get("rotation", -1))
		if rotation_track >= 0:
			var center_rotation: Quaternion = animation.rotation_track_interpolate(
				rotation_track, center_time
			).normalized()
			var sampled_rotation: Quaternion = animation.rotation_track_interpolate(
				rotation_track, last_sample_time
			).normalized()
			var delta_rotation := center_rotation.inverse() * sampled_rotation
			var current_rotation := skeleton.get_bone_pose_rotation(bone_index).normalized()
			var target_rotation := current_rotation * delta_rotation
			skeleton.set_bone_pose_rotation(
				bone_index,
				current_rotation.slerp(target_rotation.normalized(), last_weight)
			)
		last_bone_count += 1
	skeleton.force_update_all_bone_transforms()
	if helper_index >= 0 and absf(aim_yaw) > 0.00001:
		# ik_hand_gun is a root-space Unreal helper, not a child of the spine.
		# Rotate its evaluated global pose in skeleton space so it follows the same
		# camera yaw inherited by the authored arms without moving either hand.
		var helper_pose := skeleton.get_bone_global_pose(helper_index)
		var yaw_basis := Basis(Quaternion(Vector3.UP, aim_yaw))
		var yawed_pose := Transform3D(
			yaw_basis * helper_pose.basis,
			yaw_basis * helper_pose.origin
		)
		skeleton.set_bone_global_pose(
			helper_index,
			helper_pose.interpolate_with(yawed_pose, last_weight)
		)
		skeleton.force_update_all_bone_transforms()
	return last_bone_count > 0


func get_debug_state() -> Dictionary:
	return {
		"enabled": enabled,
		"available_postures": animations.keys(),
		"posture": last_posture,
		"clip": last_clip,
		"sample_time": last_sample_time,
		"source_pitch_degrees": last_source_pitch_degrees,
		"weight": last_weight,
		"bone_count": last_bone_count,
		"hands_are_animation_owned": true,
	}


func _build_track_map(animation: Animation) -> Dictionary:
	var result: Dictionary = {}
	for track_index in range(animation.get_track_count()):
		var path_text := String(animation.track_get_path(track_index))
		if ":" not in path_text:
			continue
		var bone_name := StringName(path_text.rsplit(":", false, 1)[-1])
		if bone_name not in AIM_BONES:
			continue
		var channels: Dictionary = result.get(bone_name, {})
		match animation.track_get_type(track_index):
			Animation.TYPE_POSITION_3D:
				channels["position"] = track_index
			Animation.TYPE_ROTATION_3D:
				channels["rotation"] = track_index
			_:
				continue
		result[bone_name] = channels
	return result
