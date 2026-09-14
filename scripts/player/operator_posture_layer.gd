class_name SocomOperatorPostureLayer
extends RefCounted

## Distributes camera-authoritative aim over the anatomical upper-body chain.
## Bone-only presentation; it never changes the authoritative body's transform.

const ProceduralPoseProfile := preload(
	"res://scripts/player/operator_procedural_pose_profile.gd"
)

const BONE_CANDIDATES: Dictionary = {
	&"hips": [&"mixamorig_Hips", &"mixamorig:Hips", &"Spinelower", &"Bip01 Pelvis"],
	&"spine": [&"mixamorig_Spine", &"Bip01 Spine"],
	&"spine1": [&"mixamorig_Spine1", &"mixamorig_Spine", &"Bip01 Spine1"],
	&"spine2": [&"mixamorig_Spine2", &"mixamorig_Spine1", &"Bip01 Spine3"],
	&"neck": [&"mixamorig_Neck", &"Bip01 Neck"],
	&"head": [&"mixamorig_Head", &"Bip01 Head"],
	&"left_shoulder": [&"mixamorig_LeftShoulder", &"Bip01 L Clavicle"],
	&"right_shoulder": [&"mixamorig_RightShoulder", &"Bip01 R Clavicle"],
	&"left_upper_arm": [&"mixamorig_LeftArm", &"Bip01 L UpperArm"],
	&"right_upper_arm": [&"mixamorig_RightArm", &"Bip01 R UpperArm"],
	&"left_forearm": [&"mixamorig_LeftForeArm", &"Bip01 L Forearm"],
	&"right_forearm": [&"mixamorig_RightForeArm", &"Bip01 R Forearm"],
	&"left_hand": [&"mixamorig_LeftHand", &"Bip01 L Hand"],
	&"right_hand": [&"mixamorig_RightHand", &"Bip01 R Hand"],
	&"left_upper_leg": [&"mixamorig_LeftUpLeg", &"Bip01 L Thigh"],
	&"right_upper_leg": [&"mixamorig_RightUpLeg", &"Bip01 R Thigh"],
	&"left_lower_leg": [&"mixamorig_LeftLeg", &"Bip01 L Calf"],
	&"right_lower_leg": [&"mixamorig_RightLeg", &"Bip01 R Calf"],
	&"left_foot": [&"mixamorig_LeftFoot", &"mixamorig:LeftFoot", &"Foot.L", &"Bip01 L Foot"],
	&"right_foot": [&"mixamorig_RightFoot", &"mixamorig:RightFoot", &"Foot.R", &"Bip01 R Foot"],
	&"left_toe": [&"mixamorig_LeftToeBase", &"mixamorig:LeftToeBase", &"ToeBase.L", &"Bip01 L Toe0"],
	&"right_toe": [&"mixamorig_RightToeBase", &"mixamorig:RightToeBase", &"ToeBase.R", &"Bip01 R Toe0"],
}

const TORSO_YAW_WEIGHTS: Dictionary = {
	&"spine": 0.18,
	&"spine1": 0.32,
	&"spine2": 0.50,
}

const TORSO_PITCH_WEIGHTS: Dictionary = {
	&"spine": 0.18,
	&"spine1": 0.32,
	&"spine2": 0.50,
}

const HEAD_RESIDUAL_WEIGHTS: Dictionary = {
	&"neck": 0.45,
	&"head": 0.55,
}

const SQUARE_IDLE_REFERENCE_BONES: Array[StringName] = [
	&"neck", &"head",
]

var skeleton: Skeleton3D
var movement_head_profile: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://config/basic_movement_head.json"))
var last_movement_head_roll_deg: float = 0.0
var bone_indices: Dictionary = {}
var last_applied_yaw: float = 0.0
var last_applied_pitch: float = 0.0
var last_angular_error_deg: float = 0.0
var neutral_hip_rotation := Quaternion.IDENTITY
var neutral_hip_rotations: Dictionary = {}
var last_lower_body_yaw_deg: float = 0.0
var last_lower_body_pitch_deg: float = 0.0
var last_lower_body_roll_deg: float = 0.0
var last_prone_axis_input_error_deg: float = 0.0
var last_prone_axis_residual_error_deg: float = 0.0
var last_prone_axis_correction_deg: float = 0.0
var last_peek_amount: float = 0.0
var authored_peek_clips: Dictionary = {}
var authored_peek_family: StringName = &"TWO_HAND_RIFLE"
var peek_travel_weight: float = 0.0
var last_authored_peek_source := ""
var preserve_authored_body := false
var source_pose_only := false
var look_pitch_profile: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://config/look_pitch_presentation.json"))
var smoothed_look_pitch := 0.0
const AimSpinePitch := preload("res://scripts/player/operator_aim_spine_pitch.gd")
var aim_spine_pitch := AimSpinePitch.new()

func source_spine_pitch_enabled() -> bool:
	return aim_spine_pitch.enabled(look_pitch_profile.get("spine_aim", {}))

func apply_source_spine_pitch(pitch: float, posture_name: StringName, allowed: bool, aim_world: Vector3, delta: float) -> void:
	aim_spine_pitch.apply(self, look_pitch_profile.get("spine_aim", {}), pitch, posture_name, allowed, aim_world, delta)

func advance_look_pitch(target: float, allowed: bool, delta: float) -> float:
	if source_pose_only or not allowed:
		smoothed_look_pitch = 0.0
		return 0.0
	var response := maxf(float(look_pitch_profile.get("response", 12.0)), 0.0)
	smoothed_look_pitch = lerpf(smoothed_look_pitch, target, 1.0 - exp(-response * maxf(delta, 0.0)))
	return smoothed_look_pitch

func torso_pitch_weight(posture_name: StringName, ready_weight: float) -> float:
	var relaxed := 0.0
	if bool(look_pitch_profile.get("enabled", false)) and posture_name in [&"STANDING", &"CROUCHED"]:
		relaxed = clampf(float(look_pitch_profile.get("relaxed_torso_weight", 0.4)), 0.0, 0.6)
	return maxf(clampf(ready_weight, 0.0, 1.0), relaxed)
var legacy_pistol_frame_weight := 0.0
var legacy_pistol_reference_hips := Quaternion.IDENTITY

var preserve_grounded_lean_legs := false
var standing_lean_full_body := false
var lean_blend_seconds := 0.18
var visual_peek_amount := 0.0
var standing_lean_weight := 0.0

func advance_lean(target: float, stationary_standing: bool, delta: float) -> float:
	var step := maxf(delta, 0.0) / lean_blend_seconds
	visual_peek_amount = move_toward(visual_peek_amount, clampf(target, -1.0, 1.0), step)
	standing_lean_weight = move_toward(standing_lean_weight, float(stationary_standing), step)
	return visual_peek_amount

func configure_authored_peek(profile: Dictionary) -> void:
	preserve_grounded_lean_legs = bool(profile.get("preserve_grounded_legs", false))
	standing_lean_full_body = bool(profile.get("standing_full_body", false))
	lean_blend_seconds = clampf(float(profile.get("blend_seconds", 0.18)), 0.08, 0.4)
	authored_peek_clips.clear()
	if not bool(profile.get("enabled", false)):
		return
	for family: String in profile.get("families", {}):
		var postures: Dictionary = profile.families[family]
		for posture: String in postures:
			for side: String in ["left", "right"]:
				var path := str(postures[posture].get(side, ""))
				if not path.begins_with("res://assets/animations/seal_reference/"):
					continue
				var clip := load(path) as Animation
				if clip != null:
					# A held pose samples the final key, never the catalog loop back
					# to neutral. Duplicate so Studio's source remains unchanged.
					clip = clip.duplicate(true) as Animation
					clip.loop_mode = Animation.LOOP_NONE
					# Decoded transition streams include a terminal closure sample
					# identical to frame zero. A held lean ends at the preceding key.
					for track in clip.get_track_count():
						if clip.track_get_type(track) != Animation.TYPE_ROTATION_3D or not "Spine" in str(clip.track_get_path(track)):
							continue
						var count := clip.track_get_key_count(track)
						if count > 2:
							var first: Quaternion = clip.track_get_key_value(track, 0)
							var last: Quaternion = clip.track_get_key_value(track, count - 1)
							var previous: Quaternion = clip.track_get_key_value(track, count - 2)
							if first.angle_to(last) < 0.001 and first.angle_to(previous) > 0.01:
								clip.length = clip.track_get_key_time(track, count - 2)
								break
					authored_peek_clips[family + "/" + posture + "/" + side] = clip

func _apply_authored_peek(posture: StringName, amount: float) -> bool:
	last_authored_peek_source = ""
	var side := "left" if amount < 0.0 else "right"
	var key := str(authored_peek_family) + "/" + str(posture) + "/" + side
	var clip: Animation = authored_peek_clips.get(key)
	if clip == null or skeleton == null:
		return false
	if source_pose_only:
		return _apply_source_only_peek_clip(clip, amount)
	# The held SEAL pose includes arms and shoulders, not a procedural lean
	# approximation. Weapon contact runs afterward against these authored arms.
	var maximum_angle := 0.0
	var upper_hip_frame := Quaternion.IDENTITY
	var grounded := preserve_grounded_lean_legs and posture in [&"STANDING", &"CROUCHED"]
	var lower_weight := standing_lean_weight if standing_lean_full_body and posture == &"STANDING" else 0.0
	var support_before := _lean_support_height() if grounded and lower_weight > 0.0 else INF
	for track in clip.get_track_count():
		if clip.track_get_type(track) != Animation.TYPE_ROTATION_3D:
			continue
		var bone := str(clip.track_get_path(track)).get_slice(":", 1)
		var index := skeleton.find_bone(bone)
		if index < 0:
			continue
		var initial := clip.rotation_track_interpolate(track, 0.0)
		# Blend to the held pose once. Scrubbing the entry take backward and also
		# weighting it during fire recovery creates an unrelated intermediate pose.
		var sample := clip.rotation_track_interpolate(track, clip.length if grounded else absf(amount) * clip.length)
		var blend_weight := clampf(absf(amount), 0.0, 1.0)
		if bone.ends_with("Hips") or "Leg" in bone or "Foot" in bone or "Toe" in bone:
			if grounded:
				if bone.ends_with("Hips"):
					var gait_hips := skeleton.get_bone_pose_rotation(index)
					var lean_hips := gait_hips.slerp(sample, blend_weight * lower_weight).normalized()
					upper_hip_frame = (lean_hips.inverse() * gait_hips.slerp(sample, blend_weight)).normalized()
					skeleton.set_bone_pose_rotation(index, lean_hips)
				elif lower_weight > 0.0:
					skeleton.set_bone_pose_rotation(index, skeleton.get_bone_pose_rotation(index).slerp(sample, blend_weight * lower_weight).normalized())
				continue
			# Walking/crawling legs remain driven by canonical locomotion, not a
			# held full-body lean endpoint. Stationary poses remain unchanged.
			blend_weight *= 1.0 - clampf(peek_travel_weight, 0.0, 1.0)
		var delta := (initial.inverse() * sample).normalized()
		maximum_angle = maxf(maximum_angle, rad_to_deg(Quaternion.IDENTITY.angle_to(delta)))
		skeleton.set_bone_pose_rotation(index, skeleton.get_bone_pose_rotation(index).slerp(
			sample, blend_weight
		).normalized())
	if grounded:
		var spine := skeleton.find_bone("mixamorig_Spine")
		var hips := skeleton.find_bone("mixamorig_Hips")
		if spine >= 0 and skeleton.get_bone_parent(spine) == hips:
			skeleton.set_bone_pose_rotation(spine, (upper_hip_frame * skeleton.get_bone_pose_rotation(spine)).normalized())
		if hips >= 0 and is_finite(support_before):
			var support_after := _lean_support_height()
			if is_finite(support_after):
				# Source rotations require their matching support height. Adjust only
				# visual pelvis translation, never the CharacterBody or gait clock.
				var hip_pose := skeleton.get_bone_global_pose(hips)
				hip_pose.origin.y += support_before - support_after
				skeleton.set_bone_global_pose(hips, hip_pose)
	last_peek_roll_deg = maximum_angle
	last_authored_peek_source = str(clip.get_meta("source_name", ""))
	return true


func _apply_source_only_peek_clip(clip: Animation, amount: float) -> bool:
	# Authored endpoint blend only: no hip leveling, spine compensation, knee
	# shaping, or synthetic fallback lean. Moving legs retain their gait source.
	var weight := clampf(absf(amount), 0.0, 1.0)
	for track in clip.get_track_count():
		var bone := str(clip.track_get_path(track)).get_slice(":", 1)
		var index := skeleton.find_bone(bone)
		if index < 0: continue
		var blend := weight
		if bone.ends_with("Hips") or "Leg" in bone or "Foot" in bone or "Toe" in bone:
			blend *= 1.0 - clampf(peek_travel_weight, 0.0, 1.0)
		match clip.track_get_type(track):
			Animation.TYPE_ROTATION_3D:
				var sample := clip.rotation_track_interpolate(track, clip.length)
				skeleton.set_bone_pose_rotation(index, skeleton.get_bone_pose_rotation(index).slerp(sample, blend).normalized())
			Animation.TYPE_POSITION_3D:
				skeleton.set_bone_pose_position(index, skeleton.get_bone_pose_position(index).lerp(clip.position_track_interpolate(track, clip.length), blend))
	last_authored_peek_source = str(clip.get_meta("source_name", ""))
	last_peek_roll_deg = 0.0
	return true

func _lean_support_height() -> float:
	var left := skeleton.find_bone("mixamorig_LeftFoot")
	var right := skeleton.find_bone("mixamorig_RightFoot")
	if left < 0 or right < 0:
		return INF
	return minf(skeleton.get_bone_global_pose(left).origin.y, skeleton.get_bone_global_pose(right).origin.y)
var last_peek_roll_deg: float = 0.0
var last_chest_square_correction_deg: float = 0.0
var last_shoulder_square_error_deg: float = 0.0
var last_shoulder_level_error_cm: float = 0.0
var last_shoulder_square_weight: float = 0.0
var last_directional_shoulder_target_deg: float = 0.0
var last_directional_shoulder_error_deg: float = 0.0
var last_default_hip_roll_input_deg: float = 0.0
var last_default_hip_roll_trim_deg: float = 0.0
var last_default_hip_roll_output_deg: float = 0.0
var procedural_profile := ProceduralPoseProfile.new()
var animation_frame_rotation_overrides: Dictionary = {}
var head_look_base_rotations: Dictionary = {}
var head_look_applied_rotations: Dictionary = {}
var last_square_idle_reference_bone_count: int = 0
var authored_stationary_hip_references: Dictionary = {}

const HEAD_LOOK_REUSE_EPSILON_RAD := 0.002


func bind(target_skeleton: Skeleton3D, neutral_pose_hip_rotation := Quaternion.IDENTITY) -> void:
	aim_spine_pitch.retire(skeleton)
	aim_spine_pitch.smoothed_pitch = 0.0
	skeleton = target_skeleton
	neutral_hip_rotation = neutral_pose_hip_rotation.normalized()
	neutral_hip_rotations = {
		&"STANDING": neutral_hip_rotation,
	}
	bone_indices.clear()
	authored_stationary_hip_references.clear()
	head_look_base_rotations.clear()
	head_look_applied_rotations.clear()
	if skeleton == null:
		return
	for logical_name: StringName in BONE_CANDIDATES:
		bone_indices[logical_name] = _first_bone(BONE_CANDIDATES[logical_name])
	procedural_profile.load_project_profile()


func set_neutral_hip_rotation(
	posture_name: StringName,
	neutral_pose_hip_rotation: Quaternion
) -> void:
	neutral_hip_rotations[posture_name] = neutral_pose_hip_rotation.normalized()


func set_procedural_rotation_degrees(
	posture_name: StringName,
	bone_name: StringName,
	rotation_degrees: Vector3
) -> void:
	procedural_profile.set_rotation_degrees(
		posture_name,
		bone_name,
		rotation_degrees
	)


func get_procedural_rotation_degrees(
	posture_name: StringName,
	bone_name: StringName
) -> Vector3:
	return procedural_profile.get_rotation_degrees(posture_name, bone_name)


func get_procedural_axis_limits_degrees(bone_name: StringName) -> Vector3:
	return procedural_profile.get_axis_limits_degrees(bone_name)


func get_eye_sight_reference_degrees(posture_name: StringName) -> Vector2:
	return procedural_profile.get_eye_sight_reference_degrees(posture_name)


func set_eye_sight_reference_degrees(
	posture_name: StringName,
	reference_degrees: Vector2
) -> void:
	procedural_profile.set_eye_sight_reference_degrees(
		posture_name,
		reference_degrees
	)


func get_eye_sight_origin_offset_meters(posture_name: StringName) -> Vector3:
	return procedural_profile.get_eye_sight_origin_offset_meters(posture_name)


func set_eye_sight_origin_offset_meters(
	posture_name: StringName,
	offset_meters: Vector3
) -> void:
	procedural_profile.set_eye_sight_origin_offset_meters(
		posture_name,
		offset_meters
	)


func save_procedural_profile() -> bool:
	return procedural_profile.save_project_profile()


func reload_procedural_profile() -> bool:
	return procedural_profile.load_project_profile()


func set_animation_frame_rotation_overrides(raw_rotations: Variant) -> void:
	animation_frame_rotation_overrides = (
		(raw_rotations as Dictionary).duplicate(true)
		if raw_rotations is Dictionary
		else {}
	)


func apply(
	aim_yaw: float,
	aim_pitch: float,
	ready_weight: float,
	obstruction_amount: float,
	recoil_pitch: float,
	chest_yaw_limit: float,
	chest_pitch_limit: float,
	head_yaw_limit: float,
	head_pitch_limit: float,
	lower_body_separation_weight: float = 0.0,
	gait_roll_retention: float = 0.18,
	prone_axis_weight: float = 0.0,
	prone_axis_max_correction: float = deg_to_rad(90.0),
	prone_axis_target_pitch: float = 0.0,
	posture_name: StringName = &"STANDING",
	peek_amount: float = 0.0,
	world_aim_target: Vector3 = Vector3.ZERO,
	neutral_hip_roll_trim_deg: float = 1.20,
	force_square_shoulders: bool = false,
	force_square_hips: bool = false,
	force_square_idle_reference: bool = false,
	clean_recovery_weight: float = 0.0,
	allow_clean_recovery_shoulder_square: bool = false,
	authored_posture_weight: float = 0.0,
	strafe_hip_yaw_retention: float = 0.0,
	strafe_left_square_weight: float = 0.0,
	strafe_right_shoulder_yaw: float = 0.0,
	strafe_directional_activation: float = 1.0,
	rifle_movement_isolation_weight: float = 0.0,
	standing_idle_pelvis_weight: float = 0.0
) -> void:
	if skeleton == null:
		return
	if source_pose_only:
		# Stop only this owner's cached additive head contribution, if the tree
		# has not supplied a fresh pose yet. Never reset the complete skeleton.
		clear_head_look_additive()
		last_applied_yaw = 0.0
		last_applied_pitch = 0.0
		last_angular_error_deg = 0.0
		last_lower_body_yaw_deg = 0.0
		last_lower_body_pitch_deg = 0.0
		last_lower_body_roll_deg = 0.0
		last_prone_axis_correction_deg = 0.0
		last_default_hip_roll_trim_deg = 0.0
		last_shoulder_square_weight = 0.0
		last_chest_square_correction_deg = 0.0
		last_directional_shoulder_target_deg = 0.0
		last_directional_shoulder_error_deg = 0.0
		last_square_idle_reference_bone_count = 0
		_apply_full_body_peek(posture_name, peek_amount)
		return
	var post_layer_weight := 1.0 - clampf(clean_recovery_weight, 0.0, 1.0)
	# Native stationary pistol poses already contain these two corrections.
	# Fade only their duplicate procedural contribution with the actual source
	# blend; retain the normal pass for legacy moving clips and other weapons.
	var unbaked_posture_weight := 1.0 - clampf(authored_posture_weight, 0.0, 1.0)
	# Reference clips already author the pelvis/chest relationship. Legacy
	# cleanup for unrelated takes must not flatten that source pose.
	if preserve_authored_body:
		post_layer_weight = 0.0
		neutral_hip_roll_trim_deg = 0.0
		force_square_hips = false
		prone_axis_weight = 0.0
		standing_idle_pelvis_weight = 0.0
		force_square_idle_reference = false
		lower_body_separation_weight = 0.0
		strafe_hip_yaw_retention = 0.0
		strafe_left_square_weight = 0.0
		strafe_right_shoulder_yaw = 0.0
		rifle_movement_isolation_weight = 0.0
	# A masked legacy torso expects its own pelvis frame. Counter the source
	# pelvis only at the spine; never rotate the SEAL hips or moving legs.
	if legacy_pistol_frame_weight > 0.001:
		var hips: int = bone_indices.get(&"hips", -1)
		var spine: int = bone_indices.get(&"spine", -1)
		if hips >= 0 and spine >= 0:
			var correction := skeleton.get_bone_pose_rotation(hips).inverse() * legacy_pistol_reference_hips
			skeleton.set_bone_pose_rotation(spine, Quaternion.IDENTITY.slerp(correction, legacy_pistol_frame_weight) * skeleton.get_bone_pose_rotation(spine))
	_apply_default_hip_leveling(
		posture_name,
		neutral_hip_roll_trim_deg,
		force_square_hips,
		post_layer_weight
	)
	_apply_prone_axis_alignment(
		prone_axis_weight,
		prone_axis_max_correction,
		prone_axis_target_pitch
	)
	_apply_procedural_profile(posture_name, post_layer_weight)
	if posture_name == &"STANDING":
		_apply_standing_idle_pelvis_square(standing_idle_pelvis_weight)
	_apply_square_idle_reference(force_square_idle_reference, post_layer_weight)
	var torso_yaw := clampf(aim_yaw, -chest_yaw_limit, chest_yaw_limit)
	var torso_pitch := clampf(aim_pitch, -chest_pitch_limit, chest_pitch_limit)
	var head_yaw := clampf(aim_yaw, -head_yaw_limit, head_yaw_limit)
	var head_pitch := clampf(aim_pitch, -head_pitch_limit, head_pitch_limit)
	var normalized_ready := clampf(ready_weight, 0.0, 1.0)
	# A clean recovery suppresses persistent tuning/hip cleanup, but it must not
	# suppress the bounded reticle-facing torso or the squared firing frame. Those
	# are presentation consequences of the same accepted-shot ready weight.
	var firing_frame_weight := maxf(post_layer_weight, normalized_ready)
	# Close-cover obstruction is a firing-safety result, not an animation input.
	# Keeping it out of posture prevents the blue-line/cover detector from raising
	# or lowering the operator's torso and arms.
	var obstruction_scale := 1.0
	# The authored idle/sprint clips own the complete relaxed body. Only the
	# fire/ready command may rotate the head, spine, and shoulders toward aim.
	var torso_ready_scale := normalized_ready * obstruction_scale
	var head_ready_scale := normalized_ready * obstruction_scale

	last_applied_yaw = 0.0
	last_applied_pitch = 0.0
	# A forward-facing idle pelvis no longer needs the old yawed aim_idle hip
	# reference restored at Spine when a shot raises readiness. Fade that same
	# correction out, rather than counter-twisting the chest against the waist.
	var hip_separation := lower_body_separation_weight * (1.0 - clampf(standing_idle_pelvis_weight, 0.0, 1.0))
	var neutral_carry_hip_correction := Quaternion.IDENTITY
	if strafe_hip_yaw_retention > 0.0:
		neutral_carry_hip_correction = _upper_body_hip_correction(
			posture_name, hip_separation, gait_roll_retention,
			authored_posture_weight, 0.0, rifle_movement_isolation_weight
		)
	var hip_correction := _upper_body_hip_correction(
		posture_name,
		hip_separation,
		gait_roll_retention,
		authored_posture_weight,
		strafe_hip_yaw_retention,
		rifle_movement_isolation_weight
	)
	var head_carry_counter := Quaternion.IDENTITY
	if strafe_hip_yaw_retention > 0.0:
		head_carry_counter = _hip_retention_head_counter_rotation(
			neutral_carry_hip_correction, hip_correction
		)
	var articulated_rifle_hip := rifle_movement_isolation_weight > 0.001
	for bone_name: StringName in TORSO_YAW_WEIGHTS:
		var yaw_amount := torso_yaw * float(TORSO_YAW_WEIGHTS[bone_name]) * torso_ready_scale
		var pitch_amount := torso_pitch * float(TORSO_PITCH_WEIGHTS[bone_name]) * torso_pitch_weight(posture_name, normalized_ready)
		if bone_name == &"spine2":
			pitch_amount += recoil_pitch
		_apply_bone_additive(
			bone_name,
			yaw_amount,
			pitch_amount,
			hip_correction if bone_name == &"spine" and not articulated_rifle_hip else Quaternion.IDENTITY
		)
		last_applied_yaw += yaw_amount
		last_applied_pitch += pitch_amount
	if articulated_rifle_hip:
		_apply_articulated_hip_correction(hip_correction, rifle_movement_isolation_weight)
	var directional_square_active := (
		(strafe_left_square_weight > 0.001 or strafe_right_shoulder_yaw > 0.001)
		and posture_name in [&"STANDING", &"CROUCHED"]
	)
	last_directional_shoulder_target_deg = 0.0
	last_directional_shoulder_error_deg = 0.0
	if directional_square_active:
		var chest_index := int(bone_indices.get(&"spine2", -1))
		if chest_index >= 0:
			var before := skeleton.get_bone_global_pose(chest_index).basis.orthonormalized().get_rotation_quaternion().normalized()
			var right_yaw := clampf(strafe_right_shoulder_yaw, 0.0, PI * 0.5)
			last_shoulder_square_weight = maxf(
				clampf(strafe_left_square_weight, 0.0, 1.0),
				clampf(sin(right_yaw) * 4.0, 0.0, 1.0)
			) * clampf(strafe_directional_activation, 0.0, 1.0)
			_apply_square_shoulders(
				world_aim_target, last_shoulder_square_weight, true, right_yaw, 90.0
			)
			last_directional_shoulder_target_deg = rad_to_deg(right_yaw)
			last_directional_shoulder_error_deg = last_shoulder_square_error_deg
			var after := skeleton.get_bone_global_pose(chest_index).basis.orthonormalized().get_rotation_quaternion().normalized()
			head_carry_counter = (head_carry_counter * before * after.inverse()).normalized()
	var residual_head_yaw := head_yaw - last_applied_yaw
	var residual_head_pitch := head_pitch - last_applied_pitch
	_apply_head_additive(
		residual_head_yaw, residual_head_pitch, head_ready_scale, head_carry_counter
	)

	# Arms inherit the complete reticle-facing spine transform. Shoulders only
	# receive the small recoil impulse so they do not overshoot the aim direction.
	var shoulder_pitch := recoil_pitch * 0.22 * firing_frame_weight
	_apply_bone_additive(&"left_shoulder", 0.0, shoulder_pitch)
	_apply_bone_additive(&"right_shoulder", 0.0, shoulder_pitch)
	_apply_full_body_peek(posture_name, peek_amount)
	# Rifle clean recovery already contains its accepted shoulder shape. The
	# imported pistol ready clips do not: direct rendered measurements show a
	# rolled/arched shoulder bar. Let that family reuse this single chest-frame
	# writer without re-enabling persistent hip/procedural corrections.
	var clean_square_weight := (
		1.0 if allow_clean_recovery_shoulder_square else post_layer_weight
	)
	var procedural_square_weight := firing_frame_weight * clean_square_weight * unbaked_posture_weight
	if directional_square_active:
		# This branch already squared the visible shoulder bar and included that
		# exact chest delta in the single head pass. Do not square it a second time.
		pass
	elif not preserve_authored_body and last_authored_peek_source.is_empty() and procedural_square_weight > 0.001 and (force_square_shoulders or normalized_ready >= 0.50):
		last_shoulder_square_weight = procedural_square_weight
		_apply_square_shoulders(
			world_aim_target, procedural_square_weight,
			allow_clean_recovery_shoulder_square
		)
	else:
		last_shoulder_square_weight = 0.0
		last_shoulder_square_error_deg = 0.0
		last_shoulder_level_error_cm = 0.0
		last_chest_square_correction_deg = 0.0
	last_angular_error_deg = rad_to_deg(absf(aim_yaw - last_applied_yaw))


func apply_movement_head_level(active: bool, right_dive: bool = false) -> void:
	last_movement_head_roll_deg = 0.0
	if source_pose_only or (not active and not right_dive) or not bool(movement_head_profile.enabled) or skeleton == null:
		return
	var index := int(bone_indices.get(&"head", -1))
	if index < 0:
		return
	var head := skeleton.get_bone_global_pose(index).basis.orthonormalized()
	var deformation := skeleton.global_basis.orthonormalized() * head * skeleton.get_bone_global_rest(index).basis.orthonormalized().inverse()
	var forward := (deformation * Vector3.FORWARD).normalized()
	var up := (deformation * Vector3.UP).normalized()
	var level_up := Vector3.UP - forward * forward.dot(Vector3.UP)
	if level_up.length_squared() < 0.01:
		return # No stable horizon when looking almost vertically.
	var limit := deg_to_rad(float(movement_head_profile.right_dive_maximum_roll_degrees if right_dive else movement_head_profile.maximum_roll_correction_degrees))
	var correction := clampf(up.signed_angle_to(level_up.normalized(), forward), -limit, limit)
	var axis := skeleton.global_basis.orthonormalized().inverse() * forward
	var desired := Basis(axis.normalized(), correction) * head
	var neck := int(bone_indices.get(&"neck", -1))
	if right_dive and neck >= 0:
		# Share the larger side-rest counter-bank across neck and head.
		var neck_parent := skeleton.get_bone_parent(neck)
		var neck_parent_basis := skeleton.get_bone_global_pose(neck_parent).basis.orthonormalized() if neck_parent >= 0 else Basis.IDENTITY
		var neck_desired := Basis(axis.normalized(), correction * 0.45) * skeleton.get_bone_global_pose(neck).basis.orthonormalized()
		var neck_applied := (neck_parent_basis.inverse() * neck_desired).get_rotation_quaternion().normalized()
		skeleton.set_bone_pose_rotation(neck, neck_applied)
		if head_look_applied_rotations.has(neck):
			head_look_applied_rotations[neck] = neck_applied
	var parent := skeleton.get_bone_parent(index)
	var parent_basis := skeleton.get_bone_global_pose(parent).basis.orthonormalized() if parent >= 0 else Basis.IDENTITY
	var applied := (parent_basis.inverse() * desired).get_rotation_quaternion().normalized()
	skeleton.set_bone_pose_rotation(index, applied)
	# Keep the existing frozen-pose cache aware of this final head-only result.
	if head_look_applied_rotations.has(index):
		head_look_applied_rotations[index] = applied
	last_movement_head_roll_deg = rad_to_deg(correction)


func apply_head_look_at(
	world_target: Vector3,
	weight: float = 1.0,
	yaw_limit: float = deg_to_rad(56.0),
	pitch_limit: float = deg_to_rad(34.0)
) -> Vector2:
	if source_pose_only or skeleton == null or world_target == Vector3.ZERO:
		return Vector2.ZERO
	var head_index := int(bone_indices.get(&"head", -1))
	var head_origin := (
		(skeleton.global_transform * skeleton.get_bone_global_pose(head_index)).origin
		if head_index >= 0
		else skeleton.global_position
	)
	var direction := (world_target - head_origin).normalized()
	if direction.length_squared() < 0.50:
		return Vector2.ZERO
	var body_basis := skeleton.global_basis.orthonormalized()
	var body_forward := (-body_basis.z).normalized()
	var body_right := body_basis.x.normalized()
	var body_up := body_basis.y.normalized()
	var flat_direction := (direction - body_up * direction.dot(body_up)).normalized()
	var yaw := 0.0
	if flat_direction.length_squared() > 0.50:
		yaw = atan2(flat_direction.dot(body_right), flat_direction.dot(body_forward))
	var pitch := asin(clampf(direction.dot(body_up), -1.0, 1.0))
	yaw = clampf(yaw, -yaw_limit, yaw_limit)
	pitch = clampf(pitch, -pitch_limit, pitch_limit)
	_apply_head_additive(yaw, pitch, clampf(weight, 0.0, 1.0))
	return Vector2(yaw, pitch)


func _hip_retention_head_counter_rotation(reference: Quaternion, actual: Quaternion) -> Quaternion:
	var spine_index := int(bone_indices.get(&"spine", -1))
	if spine_index < 0:
		return Quaternion.IDENTITY
	var parent_index := skeleton.get_bone_parent(spine_index)
	var parent_rotation := Quaternion.IDENTITY
	if parent_index >= 0:
		parent_rotation = skeleton.get_bone_global_pose(parent_index).basis.orthonormalized().get_rotation_quaternion().normalized()
	# Both corrections are already expressed in Spine's local-pose frame. They
	# are left-multiplied onto that pose, so only its evaluated parent converts
	# their difference into skeleton space; rest must not be counted twice.
	return (parent_rotation * reference * actual.inverse() * parent_rotation.inverse()).normalized()


func _apply_articulated_hip_correction(local_correction: Quaternion, weight: float) -> void:
	var spine_index := int(bone_indices.get(&"spine", -1))
	if spine_index < 0:
		return
	var parent_index := skeleton.get_bone_parent(spine_index)
	var parent_rotation := Quaternion.IDENTITY
	if parent_index >= 0:
		parent_rotation = skeleton.get_bone_global_pose(parent_index).basis.orthonormalized().get_rotation_quaternion().normalized()
	var global_correction := (parent_rotation * local_correction * parent_rotation.inverse()).normalized()
	var scope := clampf(weight, 0.0, 1.0)
	var parts: Dictionary = {}
	for logical_name: StringName in TORSO_YAW_WEIGHTS:
		var index := int(bone_indices.get(logical_name, -1))
		if index < 0:
			continue
		var fraction := float(TORSO_YAW_WEIGHTS[logical_name]) * scope
		if logical_name == &"spine":
			fraction += 1.0 - scope
		parts[index] = float(parts.get(index, 0.0)) + fraction
	var sum := 0.0
	for fraction: float in parts.values():
		sum += fraction
	if sum <= 0.001:
		return
	# Fixed skeleton-space powers share one axis and sum to the original Q.
	# Only the articulation changes; final chest rotation remains Q * original.
	for index: int in parts:
		_apply_skeleton_space_rotation(index, Quaternion.IDENTITY.slerp(
			global_correction, float(parts[index]) / sum
		).normalized())


func _apply_head_additive(
	yaw: float, pitch: float, weight: float,
	skeleton_space_counter: Quaternion = Quaternion.IDENTITY
) -> void:
	var counter_weight_sum := 0.0
	if not skeleton_space_counter.is_equal_approx(Quaternion.IDENTITY):
		for bone_name: StringName in HEAD_RESIDUAL_WEIGHTS:
			if int(bone_indices.get(bone_name, -1)) >= 0:
				counter_weight_sum += float(HEAD_RESIDUAL_WEIGHTS[bone_name])
	for bone_name: StringName in HEAD_RESIDUAL_WEIGHTS:
		var index := int(bone_indices.get(bone_name, -1))
		if index < 0:
			continue
		var current := skeleton.get_bone_pose_rotation(index).normalized()
		var base := current
		# AnimationPlayer may leave an unchanged/paused frame in place. In that
		# case current is our own previous result, not a fresh authored pose.
		# Reuse its recorded base instead of multiplying head look forever.
		if (
			head_look_applied_rotations.has(index)
			and current.angle_to(
				head_look_applied_rotations[index] as Quaternion
			) <= HEAD_LOOK_REUSE_EPSILON_RAD
		):
			base = head_look_base_rotations.get(index, current) as Quaternion
		var bone_weight := float(HEAD_RESIDUAL_WEIGHTS[bone_name]) * weight
		var additive := (
			Quaternion(Vector3.UP, yaw * bone_weight)
			* Quaternion(Vector3.RIGHT, pitch * bone_weight)
		).normalized()
		var applied := (base * additive).normalized()
		if counter_weight_sum > 0.0:
			# Counter only the extra carry turn, even with readiness zero. Split
			# it over the existing neck/head chain, not one extreme neck twist.
			var counter_part := Quaternion.IDENTITY.slerp(
				skeleton_space_counter,
				float(HEAD_RESIDUAL_WEIGHTS[bone_name]) / counter_weight_sum
			).normalized()
			var parent_index := skeleton.get_bone_parent(index)
			var parent_rotation := Quaternion.IDENTITY
			if parent_index >= 0:
				parent_rotation = skeleton.get_bone_global_pose(parent_index).basis.orthonormalized().get_rotation_quaternion().normalized()
			var local_counter := (parent_rotation.inverse() * counter_part * parent_rotation).normalized()
			applied = (local_counter * applied).normalized()
		skeleton.set_bone_pose_rotation(index, applied)
		head_look_base_rotations[index] = base
		head_look_applied_rotations[index] = applied


func clear_head_look_additive() -> void:
	if skeleton != null:
		for raw_index in head_look_applied_rotations.keys():
			var index := int(raw_index)
			var current := skeleton.get_bone_pose_rotation(index).normalized()
			var applied := head_look_applied_rotations[index] as Quaternion
			if current.angle_to(applied) <= HEAD_LOOK_REUSE_EPSILON_RAD:
				skeleton.set_bone_pose_rotation(
					index,
					head_look_base_rotations.get(index, current) as Quaternion
				)
	head_look_base_rotations.clear()
	head_look_applied_rotations.clear()


func get_debug_state() -> Dictionary:
	return {
		"chain_bones": bone_indices.duplicate(),
		"applied_yaw_rad": last_applied_yaw,
		"applied_pitch_rad": last_applied_pitch,
		"torso_to_aim_error_deg": last_angular_error_deg,
		"lower_body_inherited_yaw_deg": last_lower_body_yaw_deg,
		"lower_body_inherited_pitch_deg": last_lower_body_pitch_deg,
		"lower_body_retained_roll_deg": last_lower_body_roll_deg,
		"prone_axis_input_error_deg": last_prone_axis_input_error_deg,
		"prone_axis_correction_deg": last_prone_axis_correction_deg,
		"prone_axis_residual_error_deg": last_prone_axis_residual_error_deg,
		"peek_amount": last_peek_amount,
		"peek_roll_deg": last_peek_roll_deg,
		"authored_peek_source": last_authored_peek_source,
		"preserve_authored_body": preserve_authored_body,
		"source_pose_only": source_pose_only,
		"chest_square_correction_deg": last_chest_square_correction_deg,
		"shoulder_square_error_deg": last_shoulder_square_error_deg,
		"shoulder_level_error_cm": last_shoulder_level_error_cm,
		"shoulder_square_weight": last_shoulder_square_weight,
		"directional_shoulder_target_deg": last_directional_shoulder_target_deg,
		"directional_shoulder_error_deg": last_directional_shoulder_error_deg,
		"default_hip_roll_input_deg": last_default_hip_roll_input_deg,
		"default_hip_roll_trim_deg": last_default_hip_roll_trim_deg,
		"default_hip_roll_output_deg": last_default_hip_roll_output_deg,
		"square_idle_reference_bone_count": last_square_idle_reference_bone_count,
		"animation_frame_rotation_override_count": animation_frame_rotation_overrides.size(),
	}


func _apply_square_idle_reference(enabled: bool, weight: float = 1.0) -> void:
	last_square_idle_reference_bone_count = 0
	var normalized_weight := clampf(weight, 0.0, 1.0)
	if not enabled or normalized_weight <= 0.001:
		return
	# Square describes the shoulder and pelvis frames, not the direction of each
	# limb bone. Keep every authored leg rotation so knees and feet cannot swing
	# upward when entering idle. Only the head uses this neutral reference.
	for logical_name: StringName in SQUARE_IDLE_REFERENCE_BONES:
		var bone_index := int(bone_indices.get(logical_name, -1))
		if bone_index < 0:
			continue
		var current := skeleton.get_bone_pose_rotation(bone_index).normalized()
		skeleton.set_bone_pose_rotation(
			bone_index,
			current.slerp(Quaternion.IDENTITY, normalized_weight).normalized()
		)
		last_square_idle_reference_bone_count += 1


func _apply_standing_idle_pelvis_square(weight: float) -> void:
	var amount := clampf(weight, 0.0, 1.0)
	if amount <= 0.001:
		return
	var hips := int(bone_indices.get(&"hips", -1))
	var left := int(bone_indices.get(&"left_upper_leg", -1))
	var right := int(bone_indices.get(&"right_upper_leg", -1))
	if min(hips, left, right) < 0:
		return
	var bar := skeleton.get_bone_global_pose(right).origin - skeleton.get_bone_global_pose(left).origin
	bar.y = 0.0
	if bar.length_squared() <= 0.000001:
		return
	var rest_bar := skeleton.get_bone_global_rest(right).origin - skeleton.get_bone_global_rest(left).origin
	var desired := Vector3.RIGHT if rest_bar.x >= 0.0 else Vector3.LEFT
	var yaw := bar.normalized().signed_angle_to(desired, Vector3.UP)
	# Rotate only the existing visual hips owner about its own origin. Preserve
	# authored pitch, roll and every bone translation; the ordinary torso/weapon
	# pass below evaluates this current pose, rather than a stale previous frame.
	_apply_skeleton_space_rotation(hips, Quaternion(Vector3.UP, yaw * amount))


func _apply_default_hip_leveling(
	posture_name: StringName,
	maximum_trim_deg: float,
	force_square: bool = false,
	weight: float = 1.0
) -> void:
	last_default_hip_roll_input_deg = 0.0
	last_default_hip_roll_trim_deg = 0.0
	last_default_hip_roll_output_deg = 0.0
	if posture_name != &"STANDING":
		return
	var normalized_weight := clampf(weight, 0.0, 1.0)
	if normalized_weight <= 0.001:
		return
	var hips_index := int(bone_indices.get(&"hips", -1))
	if hips_index < 0:
		return
	var current_rotation := skeleton.get_bone_pose_rotation(hips_index).normalized()
	var current_roll := current_rotation.get_euler().z
	last_default_hip_roll_input_deg = rad_to_deg(current_roll)
	last_default_hip_roll_output_deg = last_default_hip_roll_input_deg
	# A zero trim means authored locomotion owns the hips. Report that real pose
	# instead of erasing it from diagnostics; no correction is applied here.
	if maximum_trim_deg <= 0.0 and not force_square:
		return
	if absf(current_roll) <= 0.0001:
		return
	if force_square:
		var e := current_rotation.get_euler()
		var target_euler := Vector3(e.x, e.y, 0.0)
		var target_rot := Quaternion.from_euler(target_euler).normalized()
		var new_rot := current_rotation.slerp(target_rot, normalized_weight).normalized()
		skeleton.set_bone_pose_rotation(hips_index, new_rot)
		last_default_hip_roll_trim_deg = rad_to_deg(e.z) * normalized_weight
		last_default_hip_roll_output_deg = rad_to_deg(
			skeleton.get_bone_pose_rotation(hips_index).get_euler().z
		)
	else:
		var trim := minf(absf(current_roll) * 0.80, deg_to_rad(maximum_trim_deg))
		trim *= -signf(current_roll)
		trim *= normalized_weight
		skeleton.set_bone_pose_rotation(
			hips_index,
			(current_rotation * Quaternion(Vector3.BACK, trim)).normalized()
		)
		last_default_hip_roll_trim_deg = rad_to_deg(trim)
		last_default_hip_roll_output_deg = rad_to_deg(
			skeleton.get_bone_pose_rotation(hips_index).get_euler().z
		)


func _apply_square_shoulders(
	world_aim_target: Vector3,
	weight: float = 1.0,
	align_visible_shoulder_ends: bool = false,
	rightward_yaw: float = 0.0,
	maximum_correction_degrees: float = 55.0
) -> void:
	var normalized_weight := clampf(weight, 0.0, 1.0)
	if normalized_weight <= 0.001:
		return
	var left_shoulder := int(bone_indices.get(&"left_shoulder", -1))
	var right_shoulder := int(bone_indices.get(&"right_shoulder", -1))
	var left_arm := int(bone_indices.get(&"left_upper_arm", -1))
	var right_arm := int(bone_indices.get(&"right_upper_arm", -1))
	if min(left_shoulder, right_shoulder, left_arm, right_arm) < 0:
		last_shoulder_square_error_deg = 0.0
		last_shoulder_level_error_cm = 0.0
		return

	skeleton.force_update_all_bone_transforms()
	var left_arm_pose := skeleton.get_bone_global_pose(left_arm)
	var right_arm_pose := skeleton.get_bone_global_pose(right_arm)
	var shoulder_center_local := (left_arm_pose.origin + right_arm_pose.origin) * 0.5
	var shoulder_center_world := skeleton.global_transform * shoulder_center_local
	var aim_forward_world := world_aim_target - shoulder_center_world
	if aim_forward_world.length_squared() <= 0.01:
		aim_forward_world = -skeleton.global_basis.z
	aim_forward_world.y = 0.0
	if aim_forward_world.length_squared() <= 0.0001:
		return
	aim_forward_world = aim_forward_world.normalized()
	var desired_right_world := aim_forward_world.cross(Vector3.UP).normalized()
	if rightward_yaw > 0.0:
		# A bar alone has a 180-degree ambiguity. Establish the anatomical right
		# direction against this rig's neutral shoulder line before turning it;
		# never choose whichever of the two sideways facings is nearest afterward.
		var rest_right_world := skeleton.global_basis * (
			skeleton.get_bone_global_rest(right_arm).origin
			- skeleton.get_bone_global_rest(left_arm).origin
		)
		if desired_right_world.dot(rest_right_world) < 0.0:
			desired_right_world = -desired_right_world
		desired_right_world = desired_right_world.rotated(Vector3.UP, -rightward_yaw)
	var desired_right_local := (
		skeleton.global_basis.inverse() * desired_right_world
	).normalized()
	# Pistol square posture is measured at the visible upper-arm origins. The
	# inner clavicle roots can be level while the authored clavicles slope, so
	# aligning that different segment leaves the visible shoulder bar tilted.
	# Rotate the same single chest owner; never rotate individual clavicles.
	_apply_square_chest(
		left_arm if align_visible_shoulder_ends else left_shoulder,
		right_arm if align_visible_shoulder_ends else right_shoulder,
		desired_right_local, normalized_weight, maximum_correction_degrees,
		rightward_yaw > 0.0
	)
	skeleton.force_update_all_bone_transforms()
	left_arm_pose = skeleton.get_bone_global_pose(left_arm)
	right_arm_pose = skeleton.get_bone_global_pose(right_arm)
	var current_right_local := (right_arm_pose.origin - left_arm_pose.origin).normalized()
	if desired_right_local.dot(current_right_local) < 0.0:
		desired_right_local = -desired_right_local
	# Spine2 turns the complete clavicle frame toward the reticle. Do not rotate
	# either clavicle independently: doing so may mathematically level the shoulder
	# points while twisting a rifle arm nearly 180 degrees away from its authored
	# hand contact.
	var left_world := skeleton.global_transform * left_arm_pose.origin
	var right_world := skeleton.global_transform * right_arm_pose.origin
	var actual_right_world := right_world - left_world
	last_shoulder_level_error_cm = absf(actual_right_world.y) * 100.0
	actual_right_world.y = 0.0
	if actual_right_world.length_squared() <= 0.0001:
		last_shoulder_square_error_deg = 0.0
		return
	actual_right_world = actual_right_world.normalized()
	if rightward_yaw <= 0.0 and actual_right_world.dot(desired_right_world) < 0.0:
		actual_right_world = -actual_right_world
	last_shoulder_square_error_deg = rad_to_deg(
		acos(clampf(actual_right_world.dot(desired_right_world), -1.0, 1.0))
	)


func _apply_square_chest(
	left_shoulder_index: int,
	right_shoulder_index: int,
	desired_right: Vector3,
	weight: float = 1.0,
	maximum_correction_degrees: float = 55.0,
	directed_target: bool = false
) -> void:
	var chest_index := int(bone_indices.get(&"spine2", -1))
	if chest_index < 0:
		last_chest_square_correction_deg = 0.0
		return
	var left_root := skeleton.get_bone_global_pose(left_shoulder_index).origin
	var right_root := skeleton.get_bone_global_pose(right_shoulder_index).origin
	var current_right := right_root - left_root
	if current_right.length_squared() <= 0.000001 or desired_right.length_squared() <= 0.000001:
		last_chest_square_correction_deg = 0.0
		return
	current_right = current_right.normalized()
	desired_right = desired_right.normalized()
	if not directed_target and current_right.dot(desired_right) < 0.0:
		desired_right = -desired_right
	var chest_correction := Quaternion(current_right, desired_right).normalized()
	var correction_angle := (
		minf(chest_correction.get_angle(), deg_to_rad(clampf(maximum_correction_degrees, 0.0, 90.0)))
		* clampf(weight, 0.0, 1.0)
	)
	if correction_angle <= 0.00001:
		last_chest_square_correction_deg = 0.0
		return
	var correction_axis := chest_correction.get_axis().normalized()
	chest_correction = Quaternion(correction_axis, correction_angle).normalized()
	last_chest_square_correction_deg = rad_to_deg(correction_angle)
	_apply_skeleton_space_rotation(chest_index, chest_correction)


func _apply_skeleton_space_rotation(bone_index: int, correction: Quaternion) -> void:
	var bone_global_rotation := (
		skeleton.get_bone_global_pose(bone_index).basis.get_rotation_quaternion().normalized()
	)
	var local_correction := (
		bone_global_rotation.inverse() * correction * bone_global_rotation
	).normalized()
	var base_rotation := skeleton.get_bone_pose_rotation(bone_index)
	skeleton.set_bone_pose_rotation(
		bone_index,
		(base_rotation * local_correction).normalized()
	)


func _square_one_shoulder(
	shoulder_index: int,
	arm_index: int,
	target_arm: Vector3,
	weight: float = 1.0
) -> void:
	var shoulder_pose := skeleton.get_bone_global_pose(shoulder_index)
	var arm_pose := skeleton.get_bone_global_pose(arm_index)
	var current_direction := arm_pose.origin - shoulder_pose.origin
	var desired_direction := target_arm - shoulder_pose.origin
	if current_direction.length_squared() <= 0.000001 or desired_direction.length_squared() <= 0.000001:
		return
	current_direction = current_direction.normalized()
	desired_direction = desired_direction.normalized()
	var skeleton_space_correction := Quaternion(current_direction, desired_direction).normalized()
	skeleton_space_correction = Quaternion.IDENTITY.slerp(
		skeleton_space_correction,
		clampf(weight, 0.0, 1.0)
	).normalized()
	var shoulder_global_rotation := shoulder_pose.basis.get_rotation_quaternion().normalized()
	var local_correction := (
		shoulder_global_rotation.inverse()
		* skeleton_space_correction
		* shoulder_global_rotation
	).normalized()
	var base_rotation := skeleton.get_bone_pose_rotation(shoulder_index)
	skeleton.set_bone_pose_rotation(
		shoulder_index,
		(base_rotation * local_correction).normalized()
	)


func _apply_full_body_peek(posture_name: StringName, amount: float) -> void:
	# SOCOM's peek is a planted reach, not a camera roll or one-joint waist bend.
	# The imported trooper faces 180 degrees opposite the authoritative player,
	# so its local roll sign must be inverted: Q remains gameplay-left and E
	# remains gameplay-right in world space.
	var signed_amount := clampf(amount, -1.0, 1.0)
	last_peek_amount = signed_amount
	if absf(signed_amount) <= 0.0001:
		last_peek_roll_deg = 0.0
		last_authored_peek_source = ""
		return
	if _apply_authored_peek(posture_name, signed_amount):
		return
	if source_pose_only:
		last_peek_roll_deg = 0.0
		return # Missing source take is not permission to synthesize a lean.
	var pose_amount := -signed_amount
	var hip_roll_deg := 5.0
	var spine_roll_deg := 13.0
	var head_counter_deg := 2.0
	var thigh_open_deg := 7.0
	var shin_counter_deg := 5.0
	if posture_name == &"CROUCHED":
		hip_roll_deg = 6.0
		spine_roll_deg = 11.0
		head_counter_deg = 2.5
		thigh_open_deg = 8.0
		shin_counter_deg = 7.0
	elif posture_name == &"PRONE":
		hip_roll_deg = 1.5
		spine_roll_deg = 9.0
		head_counter_deg = 3.0
		thigh_open_deg = 0.0
		shin_counter_deg = 0.0

	_apply_bone_roll(&"hips", deg_to_rad(hip_roll_deg) * pose_amount)
	_apply_bone_roll(&"spine", deg_to_rad(spine_roll_deg * 0.28) * pose_amount)
	_apply_bone_roll(&"spine1", deg_to_rad(spine_roll_deg * 0.34) * pose_amount)
	_apply_bone_roll(&"spine2", deg_to_rad(spine_roll_deg * 0.38) * pose_amount)
	_apply_bone_roll(&"neck", deg_to_rad(-head_counter_deg * 0.45) * pose_amount)
	_apply_bone_roll(&"head", deg_to_rad(-head_counter_deg * 0.55) * pose_amount)

	if thigh_open_deg > 0.0:
		var exposed_thigh := &"right_upper_leg" if signed_amount > 0.0 else &"left_upper_leg"
		var exposed_shin := &"right_lower_leg" if signed_amount > 0.0 else &"left_lower_leg"
		var support_thigh := &"left_upper_leg" if signed_amount > 0.0 else &"right_upper_leg"
		_apply_bone_roll(exposed_thigh, deg_to_rad(thigh_open_deg) * pose_amount)
		_apply_bone_roll(exposed_shin, deg_to_rad(-shin_counter_deg) * pose_amount)
		_apply_bone_roll(support_thigh, deg_to_rad(-2.0) * pose_amount)
	last_peek_roll_deg = (hip_roll_deg + spine_roll_deg - head_counter_deg) * absf(signed_amount)


func _apply_bone_roll(bone_name: StringName, roll: float) -> void:
	var index := int(bone_indices.get(bone_name, -1))
	if index < 0:
		return
	var base_rotation := skeleton.get_bone_pose_rotation(index)
	skeleton.set_bone_pose_rotation(
		index,
		base_rotation * Quaternion(Vector3.FORWARD, roll)
	)


func _apply_prone_axis_alignment(
	weight: float,
	maximum_correction: float,
	target_pitch: float
) -> void:
	var hips_index := int(bone_indices.get(&"hips", -1))
	var spine_index := int(bone_indices.get(&"spine", -1))
	var head_index := int(bone_indices.get(&"head", -1))
	if hips_index < 0 or spine_index < 0 or head_index < 0 or weight <= 0.001:
		last_prone_axis_input_error_deg = 0.0
		last_prone_axis_correction_deg = 0.0
		last_prone_axis_residual_error_deg = 0.0
		return

	skeleton.force_update_all_bone_transforms()
	var hip_pose := skeleton.get_bone_global_pose(hips_index)
	var head_pose := skeleton.get_bone_global_pose(head_index)
	var current_axis := head_pose.origin - hip_pose.origin
	if current_axis.length_squared() <= 0.000001:
		return
	current_axis = current_axis.normalized()
	var desired_axis := Vector3(
		0.0,
		sin(target_pitch),
		cos(target_pitch)
	).normalized()
	var input_error := current_axis.angle_to(desired_axis)
	last_prone_axis_input_error_deg = rad_to_deg(input_error)
	var correction_fraction := (
		minf(1.0, maxf(maximum_correction, 0.0) / input_error)
		if input_error > 0.00001
		else 0.0
	)
	correction_fraction *= clampf(weight, 0.0, 1.0)
	last_prone_axis_correction_deg = rad_to_deg(input_error * correction_fraction)
	if correction_fraction <= 0.00001:
		last_prone_axis_residual_error_deg = last_prone_axis_input_error_deg
		return

	var full_correction := Quaternion(current_axis, desired_axis)
	var correction := Quaternion.IDENTITY.slerp(full_correction, correction_fraction)
	# Straighten only the upper-body branch. Rotating the hips also rotates both
	# leg chains and was lifting prone knees/feet roughly half a metre off the
	# ground. The pelvis remains the measured anchor while Spine carries the
	# correction toward the head.
	_apply_global_bone_correction(spine_index, correction)
	skeleton.force_update_all_bone_transforms()
	var corrected_axis := (
		skeleton.get_bone_global_pose(head_index).origin
		- skeleton.get_bone_global_pose(hips_index).origin
	)
	# Rotating around Spine instead of Hips changes the lever arm slightly. Ease
	# the residual correction in over the last part of the prone blend so landing
	# from a dive cannot leave a briefly crooked torso or create a one-frame snap.
	# The pelvis and both leg chains remain untouched throughout.
	if corrected_axis.length_squared() > 0.000001:
		var residual_error := corrected_axis.normalized().angle_to(desired_axis)
		var settle_weight := smoothstep(0.85, 0.98, clampf(weight, 0.0, 1.0))
		if residual_error > deg_to_rad(0.10) and settle_weight > 0.0001:
			_apply_global_bone_correction(
				spine_index,
				Quaternion.IDENTITY.slerp(
					Quaternion(corrected_axis.normalized(), desired_axis),
					settle_weight
				)
			)
			skeleton.force_update_all_bone_transforms()
			corrected_axis = (
				skeleton.get_bone_global_pose(head_index).origin
				- skeleton.get_bone_global_pose(hips_index).origin
			)
	last_prone_axis_residual_error_deg = (
		rad_to_deg(corrected_axis.normalized().angle_to(desired_axis))
		if corrected_axis.length_squared() > 0.000001
		else 0.0
	)


func _apply_global_bone_correction(bone_index: int, correction: Quaternion) -> void:
	var bone_pose := skeleton.get_bone_global_pose(bone_index)
	var current_global_rotation := bone_pose.basis.get_rotation_quaternion().normalized()
	var desired_global_rotation := (correction * current_global_rotation).normalized()
	var parent_index := skeleton.get_bone_parent(bone_index)
	var parent_rotation := Quaternion.IDENTITY
	if parent_index >= 0:
		parent_rotation = (
			skeleton.get_bone_global_pose(parent_index).basis.get_rotation_quaternion().normalized()
		)
	var rest_rotation := skeleton.get_bone_rest(bone_index).basis.get_rotation_quaternion().normalized()
	var local_basis_rotation := (parent_rotation * rest_rotation).normalized()
	skeleton.set_bone_pose_rotation(
		bone_index,
		(local_basis_rotation.inverse() * desired_global_rotation).normalized()
	)


func _upper_body_hip_correction(
	posture_name: StringName,
	weight: float,
	gait_roll_retention: float,
	authored_posture_weight: float = 0.0,
	strafe_hip_yaw_retention: float = 0.0,
	exact_local_pose_weight: float = 0.0
) -> Quaternion:
	var hips_index := int(bone_indices.get(&"hips", -1))
	var spine_index := int(bone_indices.get(&"spine", -1))
	if hips_index < 0 or spine_index < 0:
		last_lower_body_yaw_deg = 0.0
		last_lower_body_pitch_deg = 0.0
		last_lower_body_roll_deg = 0.0
		return Quaternion.IDENTITY
	var current_hip := skeleton.get_bone_pose_rotation(hips_index).normalized()
	var posture_neutral: Quaternion = neutral_hip_rotations.get(
		posture_name,
		neutral_hip_rotation
	)
	var native_weight := clampf(authored_posture_weight, 0.0, 1.0)
	if native_weight >= 0.999:
		authored_stationary_hip_references[posture_name] = current_hip
	if native_weight > 0.0:
		# The native spine already compensates its own hip frame. Blend that
		# reference with the legacy moving neutral, not the correction's strength:
		# scaling strength would leak moving-hip rotation into the native half.
		var native_hip: Quaternion = authored_stationary_hip_references.get(posture_name, current_hip)
		posture_neutral = posture_neutral.slerp(native_hip, native_weight).normalized()
	var hip_delta := (current_hip.inverse() * posture_neutral).normalized()
	# Cancel pelvis yaw/pitch completely while retaining a restrained fraction of
	# lateral gait roll. This restores tactical weight without allowing the legs
	# to pull the rifle-ready torso off its body axis.
	var hip_delta_euler := hip_delta.get_euler()
	# Right-strafe opt-in retains a little authored pelvis yaw, not its pitch or
	# head bob. The same spine writer continues to own all torso correction.
	var retained_yaw := clampf(strafe_hip_yaw_retention, 0.0, 1.0)
	if retained_yaw > 0.0:
		hip_delta_euler.y *= 1.0 - retained_yaw
		hip_delta = Quaternion.from_euler(hip_delta_euler).normalized()
	var yaw_pitch_correction := (
		Quaternion(Vector3.UP, hip_delta_euler.y)
		* Quaternion(Vector3.RIGHT, hip_delta_euler.x)
	).normalized()
	var roll_cancel_weight := 1.0 - clampf(gait_roll_retention, 0.0, 1.0)
	var hip_upper_body_correction := yaw_pitch_correction.slerp(
		hip_delta,
		roll_cancel_weight
	).normalized()
	var applied := Quaternion.IDENTITY.slerp(
		hip_upper_body_correction,
		clampf(weight, 0.0, 1.0)
	).normalized()
	var applied_euler := applied.get_euler()
	last_lower_body_yaw_deg = rad_to_deg(applied_euler.y)
	last_lower_body_pitch_deg = rad_to_deg(applied_euler.x)
	last_lower_body_roll_deg = rad_to_deg(hip_delta_euler.z) * clampf(gait_roll_retention, 0.0, 1.0)
	# Retain the legacy rest-conjugated route for profiles that have not opted
	# into exact moving-rifle isolation; their authored presentation is unchanged.
	var spine_rest_rotation := skeleton.get_bone_rest(spine_index).basis.get_rotation_quaternion().normalized()
	var legacy := (spine_rest_rotation.inverse() * applied * spine_rest_rotation).normalized()
	# Godot's evaluated pose rotation already includes rest. For the opted-in
	# stable moving rifle frame, H * (H^-1 * N) * Spine cancels the moving parent
	# exactly; conjugating through rest again leaks gait rotation into the head.
	# Preserve the established route elsewhere and fade with the same carry gate.
	return legacy.slerp(applied, clampf(exact_local_pose_weight, 0.0, 1.0)).normalized()


func _apply_bone_additive(
	bone_name: StringName,
	yaw: float,
	pitch: float,
	pre_rotation: Quaternion = Quaternion.IDENTITY
) -> void:
	var index := int(bone_indices.get(bone_name, -1))
	if index < 0:
		return
	var base_rotation := skeleton.get_bone_pose_rotation(index)
	var additive := Quaternion(Vector3.UP, yaw) * Quaternion(Vector3.RIGHT, pitch)
	skeleton.set_bone_pose_rotation(index, pre_rotation * base_rotation * additive)


func _apply_procedural_profile(posture_name: StringName, weight: float = 1.0) -> void:
	var normalized_weight := clampf(weight, 0.0, 1.0)
	if normalized_weight <= 0.001:
		return
	for bone_name: StringName in ProceduralPoseProfile.SUPPORTED_BONES:
		var degrees := procedural_profile.get_rotation_degrees(posture_name, bone_name)
		var frame_value: Variant = animation_frame_rotation_overrides.get(String(bone_name), null)
		if frame_value is Dictionary:
			degrees = Vector3(
				float(frame_value.get("x", degrees.x)),
				float(frame_value.get("y", degrees.y)),
				float(frame_value.get("z", degrees.z))
			)
		if degrees.is_zero_approx():
			continue
		var index := int(bone_indices.get(bone_name, -1))
		if index < 0:
			continue
		var additive := (
			Quaternion(Vector3.UP, deg_to_rad(degrees.y))
			* Quaternion(Vector3.RIGHT, deg_to_rad(degrees.x))
			* Quaternion(Vector3.FORWARD, deg_to_rad(degrees.z))
		).normalized()
		additive = Quaternion.IDENTITY.slerp(additive, normalized_weight).normalized()
		var base_rotation := skeleton.get_bone_pose_rotation(index)
		skeleton.set_bone_pose_rotation(
			index,
			(base_rotation * additive).normalized()
		)


func _first_bone(candidates: Array) -> int:
	for candidate in candidates:
		var index := skeleton.find_bone(StringName(candidate))
		if index >= 0:
			return index
	return -1
