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
