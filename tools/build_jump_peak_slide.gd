extends SceneTree

const Assets := preload("res://scripts/player/operator_asset_runtime.gd")
const Profile := preload("res://scripts/player/operator_animation_profile.gd")
const RECIPE := "res://config/jump_peak_slide_recipe.json"
var rig: Skeleton3D
var source: Animation
var upper: Animation
var recipe: Dictionary

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	recipe = JSON.parse_string(FileAccess.get_file_as_string(RECIPE))
	var profile := Profile.new()
	profile.load_project_map()
	# Build from canonical sources, never from a previous authored candidate.
	profile.clip_paths.erase(&"jump_peak_slide_candidate")
	profile.clip_paths.erase(&"backward_dive_pose_candidate")
	var holder := Node3D.new()
	root.add_child(holder)
	var runtime := Assets.new()
	runtime.build(holder, profile, 62.0, Vector3(-0.02, 0.08, 0.05), Vector3(-90, 180, 0))
	rig = runtime.skeleton
	source = runtime.animation_player.get_animation(StringName(recipe.source_clip))
	upper = runtime.animation_player.get_animation(StringName(recipe.upper_body_clip))
	var output := Animation.new()
	output.length = float(recipe.duration_seconds)
	output.resource_name = "Jump Peak Slide - Candidate"
	output.set_meta("source_recipe", RECIPE)
	output.set_meta("source_clip", String(recipe.source_clip))
	output.set_meta("animation_only", true)
	var rotation_tracks: Array[int] = []
	var position_tracks: Array[int] = []
	for bone in rig.get_bone_count():
		var path := NodePath(".:" + rig.get_bone_name(bone))
		var rotation_track := output.add_track(Animation.TYPE_ROTATION_3D)
		output.track_set_path(rotation_track, path)
		rotation_tracks.append(rotation_track)
		var position_track := output.add_track(Animation.TYPE_POSITION_3D)
		output.track_set_path(position_track, path)
		position_tracks.append(position_track)
	var hips := rig.find_bone("mixamorig_Hips")
	var spine := rig.find_bone("mixamorig_Spine")
	var start := _pose(source, 0.0)
	var upper_pose := _pose(upper, 0.0)
	var frames := int(ceil(output.length * float(recipe.sample_fps)))
	for frame in frames + 1:
		var time := minf(float(frame) / float(recipe.sample_fps), output.length)
		var weight := smoothstep(0.0, float(recipe.enter_seconds), time)
		weight *= 1.0 - smoothstep(float(recipe.hold_end_seconds), output.length, time)
		var drift := clampf((time - float(recipe.enter_seconds)) / (float(recipe.hold_end_seconds) - float(recipe.enter_seconds)), 0.0, 1.0)
		var pose := _pose(source, float(recipe.peak_seconds) + drift * float(recipe.peak_drift_seconds))
		# Preserve the existing rifle upper-body pose; source jump supplies the legs.
		for bone in rig.get_bone_count():
			if _is_upper(bone, spine):
				pose[bone] = upper_pose[bone]
		var hip_rotation := Quaternion(Vector3.RIGHT, deg_to_rad(float(recipe.pelvis_lean_degrees))) * pose[hips].basis.get_rotation_quaternion()
		pose[hips].basis = Basis(hip_rotation)
		# One authored spine correction compensates pelvis pitch, not runtime IK.
		pose[spine].basis = Basis(hip_rotation.inverse() * Quaternion(Vector3.RIGHT, deg_to_rad(float(recipe.torso_lean_degrees))) * upper_pose[hips].basis.get_rotation_quaternion()) * upper_pose[spine].basis
		pose[hips].origin = Vector3(0, float(recipe.slide_hip_height_m) / 62.0, 0)
		# Solve right knee contact first, then the forward left leg at that hip height.
		# These are offline keys, not a new runtime IK or movement owner.
		_fit_kneeling_right_leg(pose, start)
		_fit_slide_leg(pose, "Left", float(recipe.left_foot_forward_m), start)
		if frame == 15:
			var contacts := _globals(pose)
			for bone_name in ["Hips", "RightUpLeg", "RightLeg", "RightFoot", "RightToeBase", "LeftLeg", "LeftFoot", "LeftToeBase"]:
				print("CONTACT_BEFORE_GROUND ", bone_name, " ", contacts[rig.find_bone("mixamorig_" + bone_name)].origin * 62.0)
		for bone in rig.get_bone_count():
			pose[bone] = start[bone].interpolate_with(pose[bone], weight)
		_ground(pose, hips)
		for bone in rig.get_bone_count():
			output.rotation_track_insert_key(rotation_tracks[bone], time, pose[bone].basis.get_rotation_quaternion().normalized())
			output.position_track_insert_key(position_tracks[bone], time, pose[bone].origin)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(String(recipe.output).get_base_dir()))
	var result := ResourceSaver.save(output, String(recipe.output))
	print("JUMP_PEAK_SLIDE_BUILD ", error_string(result), " frames=", frames + 1, " output=", recipe.output)
	holder.queue_free()
	await process_frame
	quit(0 if result == OK else 1)

func _pose(animation: Animation, time: float) -> Array[Transform3D]:
	var result: Array[Transform3D] = []
	for bone in rig.get_bone_count():
		result.append(rig.get_bone_rest(bone))
	for track in animation.get_track_count():
		var path := animation.track_get_path(track)
		if path.get_subname_count() == 0:
			continue
		var bone := rig.find_bone(path.get_subname(path.get_subname_count() - 1))
		if bone < 0:
			continue
		match animation.track_get_type(track):
			Animation.TYPE_POSITION_3D:
				result[bone].origin = animation.position_track_interpolate(track, time)
			Animation.TYPE_ROTATION_3D:
				result[bone].basis = Basis(animation.rotation_track_interpolate(track, time))
	return result

func _is_upper(bone: int, spine: int) -> bool:
	while bone >= 0:
		if bone == spine:
			return true
		bone = rig.get_bone_parent(bone)
	return false

func _ground(pose: Array[Transform3D], hips: int) -> void:
	var globals := _globals(pose)
	var lowest := INF
	for name in ["mixamorig_LeftFoot", "mixamorig_LeftToeBase", "mixamorig_RightFoot", "mixamorig_RightToeBase", "mixamorig_LeftLeg", "mixamorig_RightLeg"]:
		var bone := rig.find_bone(name)
		lowest = minf(lowest, globals[bone].origin.y - 0.055 / 62.0)
	lowest = minf(lowest, globals[hips].origin.y - 0.14 / 62.0)
	pose[hips].origin = Vector3(0.0, pose[hips].origin.y - lowest, 0.0)

func _globals(pose: Array[Transform3D]) -> Array[Transform3D]:
	var globals: Array[Transform3D] = []
	for bone in rig.get_bone_count():
		var parent := rig.get_bone_parent(bone)
		globals.append(globals[parent] * pose[bone] if parent >= 0 else pose[bone])
	return globals

func _fit_slide_leg(pose: Array[Transform3D], side: String, reach_m: float, standing: Array[Transform3D]) -> void:
	var thigh := rig.find_bone("mixamorig_" + side + "UpLeg")
	var knee := rig.find_bone("mixamorig_" + side + "Leg")
	var foot := rig.find_bone("mixamorig_" + side + "Foot")
	var globals := _globals(pose)
	var origin := globals[thigh].origin
	var target := Vector3(origin.x, 0.07 / 62.0, reach_m / 62.0)
	var upper_length := origin.distance_to(globals[knee].origin)
	var lower_length := globals[knee].origin.distance_to(globals[foot].origin)
	var axis := (target - origin).normalized()
	var distance := minf(origin.distance_to(target), (upper_length + lower_length) * 0.98)
	target = origin + axis * distance
	var along := (upper_length * upper_length - lower_length * lower_length + distance * distance) / (2.0 * distance)
	var bend := sqrt(maxf(upper_length * upper_length - along * along, 0.0))
	var pole := (Vector3.UP - axis * Vector3.UP.dot(axis)).normalized()
	var knee_target := origin + axis * along + pole * bend
	var desired := Basis(Quaternion((globals[knee].origin - origin).normalized(), (knee_target - origin).normalized())) * globals[thigh].basis
	pose[thigh].basis = globals[rig.get_bone_parent(thigh)].basis.inverse() * desired
	globals = _globals(pose)
	desired = Basis(Quaternion((globals[foot].origin - globals[knee].origin).normalized(), (target - globals[knee].origin).normalized())) * globals[knee].basis
	pose[knee].basis = globals[thigh].basis.inverse() * desired
	globals = _globals(pose)
	pose[foot].basis = globals[knee].basis.inverse() * _globals(standing)[foot].basis
	var toe := rig.find_bone("mixamorig_" + side + "ToeBase")
	pose[toe].basis = standing[toe].basis
	_level_foot(pose, foot, toe, 1.0)

func _fit_kneeling_right_leg(pose: Array[Transform3D], standing: Array[Transform3D]) -> void:
	var hips := rig.find_bone("mixamorig_Hips")
	var thigh := rig.find_bone("mixamorig_RightUpLeg")
	var knee := rig.find_bone("mixamorig_RightLeg")
	var foot := rig.find_bone("mixamorig_RightFoot")
	var globals := _globals(pose)
	var length := globals[thigh].origin.distance_to(globals[knee].origin)
	var knee_target := Vector3(globals[thigh].origin.x, float(recipe.right_knee_height_m) / 62.0, float(recipe.right_knee_forward_m) / 62.0)
	var forward_offset := knee_target.z - globals[thigh].origin.z
	# Preserve the thigh length: choose pelvis height instead of stretching a bone.
	pose[hips].origin.y += knee_target.y + sqrt(maxf(length * length - forward_offset * forward_offset, 0.0)) - globals[thigh].origin.y
	globals = _globals(pose)
	var desired := Basis(Quaternion((globals[knee].origin - globals[thigh].origin).normalized(), (knee_target - globals[thigh].origin).normalized())) * globals[thigh].basis
	pose[thigh].basis = globals[rig.get_bone_parent(thigh)].basis.inverse() * desired
	globals = _globals(pose)
	# Shin lies behind the grounded knee, with the ankle slightly above it.
	var shin_axis := Vector3(0, 0.07, -1).normalized()
	desired = Basis(Quaternion((globals[foot].origin - globals[knee].origin).normalized(), shin_axis)) * globals[knee].basis
	pose[knee].basis = globals[thigh].basis.inverse() * desired
	globals = _globals(pose)
	pose[foot].basis = globals[knee].basis.inverse() * _globals(standing)[foot].basis
	var toe := rig.find_bone("mixamorig_RightToeBase")
	pose[toe].basis = standing[toe].basis
	_level_foot(pose, foot, toe, 1.0)
	globals = _globals(pose)
	# Plantarflex around the lateral ankle axis, not a 180-degree yaw twist.
	pose[foot].basis = globals[knee].basis.inverse() * Basis(Vector3.RIGHT, PI) * globals[foot].basis

func _level_foot(pose: Array[Transform3D], foot: int, toe: int, forward: float) -> void:
	# Jump-start toes point down; align their actual FK direction to the floor.
	var globals := _globals(pose)
	var toe_axis := (globals[toe].origin - globals[foot].origin).normalized()
	var floor_axis := Vector3(0, -0.04, forward).normalized()
	var desired := Basis(Quaternion(toe_axis, floor_axis)) * globals[foot].basis
	pose[foot].basis = globals[rig.get_bone_parent(foot)].basis.inverse() * desired
