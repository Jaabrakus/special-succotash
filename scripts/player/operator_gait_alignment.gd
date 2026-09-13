extends RefCounted

## Library-time correction only. AnimationTree remains the pose writer;
## CharacterBody remains the movement writer. Source assets are never edited.
static func align_support(clip: Animation, rig: Skeleton3D, support_height: float) -> void:
	var hips := clip.find_track(NodePath(".:mixamorig_Hips"), Animation.TYPE_POSITION_3D)
	var left := rig.find_bone("mixamorig_LeftFoot")
	var right := rig.find_bone("mixamorig_RightFoot")
	if hips < 0 or mini(left, right) < 0 or clip.loop_mode != Animation.LOOP_LINEAR:
		return
	var rotations := {}
	var positions := {}
	for track in clip.get_track_count():
		var bone := rig.find_bone(str(clip.track_get_path(track)).get_slice(":", 1))
		if bone < 0: continue
		if clip.track_get_type(track) == Animation.TYPE_ROTATION_3D: rotations[bone] = track
		if clip.track_get_type(track) == Animation.TYPE_POSITION_3D: positions[bone] = track
	var corrected: Array[Vector3] = []
	# Calculate all samples before changing the hip track: otherwise interpolation
	# would read partly corrected data and accumulate an offset within the bake.
	for key in clip.track_get_key_count(hips):
		var time := clip.track_get_key_time(hips, key)
		var poses := {}
		var left_pose := _bone_pose(left, time, clip, rig, rotations, positions, poses)
		var right_pose := _bone_pose(right, time, clip, rig, rotations, positions, poses)
		var value: Vector3 = clip.track_get_key_value(hips, key)
		value.y += support_height - minf(left_pose.origin.y, right_pose.origin.y)
		corrected.append(value)
	for key in corrected.size(): clip.track_set_key_value(hips, key, corrected[key])
	clip.set_meta("grounded_gait_aligned", true)

static func _bone_pose(index: int, time: float, clip: Animation, rig: Skeleton3D,
		rotations: Dictionary, positions: Dictionary, poses: Dictionary) -> Transform3D:
	if poses.has(index): return poses[index]
	var pose := rig.get_bone_rest(index)
	if rotations.has(index): pose.basis = Basis(clip.rotation_track_interpolate(rotations[index], time))
	if positions.has(index): pose.origin = clip.position_track_interpolate(positions[index], time)
	var parent := rig.get_bone_parent(index)
	if parent >= 0: pose = _bone_pose(parent, time, clip, rig, rotations, positions, poses) * pose
	poses[index] = pose
	return pose

static func balance_run_support(clip: Animation, maximum_correction: float) -> void:
	var hips := clip.find_track(NodePath(".:mixamorig_Hips"), Animation.TYPE_POSITION_3D)
	if hips < 0 or clip.loop_mode != Animation.LOOP_LINEAR or clip.length <= 0.0: return
	var corrected: Array[Vector3] = []
	# Read the entire original curve first. The opposite stance occurs half a
	# stride later; average only hip height, retaining both authored leg chains.
	for key in clip.track_get_key_count(hips):
		var t := fposmod(clip.track_get_key_time(hips, key), clip.length)
		var own := clip.position_track_interpolate(hips, t)
		var opposite := clip.position_track_interpolate(hips, fposmod(t + clip.length * 0.5, clip.length))
		var value: Vector3 = clip.track_get_key_value(hips, key)
		value.y += clampf((opposite.y - own.y) * 0.5, -maximum_correction, maximum_correction)
		corrected.append(value)
	for key in corrected.size(): clip.track_set_key_value(hips, key, corrected[key])
	clip.set_meta("forward_run_hip_balanced", true)


static func limit_run_bounce(clip: Animation, rig: Skeleton3D, maximum_travel: float) -> void:
	var hips := clip.find_track(NodePath(".:mixamorig_Hips"), Animation.TYPE_POSITION_3D)
	if maximum_travel <= 0.0 or hips < 0 or clip.loop_mode != Animation.LOOP_LINEAR: return
	var minimum := INF
	var maximum := -INF
	for key in clip.track_get_key_count(hips):
		var p: Vector3 = clip.track_get_key_value(hips, key)
		minimum = minf(minimum, p.y)
		maximum = maxf(maximum, p.y)
	if maximum - minimum <= maximum_travel: return
	var source := clip.duplicate(true) as Animation
	# Transient bake rig, never the live character's pose. The runtime graph
	# remains the only base-pose writer after this resource preparation finishes.
	var working := Skeleton3D.new()
	for bone in rig.get_bone_count():
		working.add_bone(rig.get_bone_name(bone))
		working.set_bone_parent(bone, rig.get_bone_parent(bone))
		working.set_bone_rest(bone, rig.get_bone_rest(bone))
	rig.add_child(working)
	var solver := preload("res://scripts/player/operator_foot_grounding_modifier.gd").new()
	solver.bind(working, {"maximum_joint_delta_deg": 75.0})
	var rotations := {}
	var positions := {}
	for track in source.get_track_count():
		var bone := working.find_bone(str(source.track_get_path(track)).get_slice(":", 1))
		if bone < 0: continue
		if source.track_get_type(track) == Animation.TYPE_ROTATION_3D: rotations[bone] = track
		if source.track_get_type(track) == Animation.TYPE_POSITION_3D: positions[bone] = track
	var leg_keys := {}
	for name in solver.written_bone_names(): leg_keys[name] = []
	var hip_bone := working.find_bone("mixamorig_Hips")
	var max_error := 0.0
	for key in clip.track_get_key_count(hips):
		var time := clip.track_get_key_time(hips, key)
		for bone in working.get_bone_count():
			var rest := working.get_bone_rest(bone)
			working.set_bone_pose_position(bone, source.position_track_interpolate(positions[bone], time) if positions.has(bone) else rest.origin)
			working.set_bone_pose_rotation(bone, source.rotation_track_interpolate(rotations[bone], time) if rotations.has(bone) else rest.basis.get_rotation_quaternion())
		working.force_update_all_bone_transforms()
		var left := working.to_global(working.get_bone_global_pose(working.find_bone(solver.LEFT_FOOT)).origin)
		var right := working.to_global(working.get_bone_global_pose(working.find_bone(solver.RIGHT_FOOT)).origin)
		var p: Vector3 = source.track_get_key_value(hips, key)
		p.y = minimum + (p.y - minimum) * maximum_travel / (maximum - minimum)
		working.set_bone_pose_position(hip_bone, p)
		working.force_update_all_bone_transforms()
		max_error = maxf(max_error, solver._solve_chain(working, solver.LEFT_UPPER, solver.LEFT_KNEE, solver.LEFT_FOOT, left, 1.0))
		max_error = maxf(max_error, solver._solve_chain(working, solver.RIGHT_UPPER, solver.RIGHT_KNEE, solver.RIGHT_FOOT, right, 1.0))
		clip.track_set_key_value(hips, key, p)
		for name in leg_keys:
			leg_keys[name].append([time, working.get_bone_pose_rotation(working.find_bone(name))])
	for name in leg_keys:
		var track := clip.find_track(NodePath(".:" + str(name)), Animation.TYPE_ROTATION_3D)
		if track < 0: continue
		for key in range(clip.track_get_key_count(track)-1, -1, -1): clip.track_remove_key(track, key)
		for entry in leg_keys[name]: clip.rotation_track_insert_key(track, entry[0], entry[1])
	clip.set_meta("run_bounce_fit_error_m", max_error)
	working.free()
	solver.free()
