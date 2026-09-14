extends "res://tools/source_camera_reference_projection.gd"
## Offline same-phase observer; never changes project assets or game state.

const JOINTS := {"hips": "Hips", "head": "Head", "lcalf": "LeftLeg", "rcalf": "RightLeg",
	"lfoot": "LeftFoot", "rfoot": "RightFoot", "ltoe": "LeftToeBase", "rtoe": "RightToeBase"}

func _run() -> void:
	var output := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): output = arg.trim_prefix("--out=")
	if not output.begins_with("/private/tmp/") or output.contains("..") or FileAccess.file_exists(output):
		push_error("Fresh --out=/private/tmp/...json required")
		quit(1)
		return
	source_nodes = _json(SOURCE + "seal-skeleton.json").nodes
	_measure_current_rest(_globals({}, 0))
	var original := _json(SOURCE + "motion/seal_prone_crawl.json")
	var current: Animation = current_asset_runtime.animation_library.get_animation(&"prone_forward").duplicate()
	_check(current.get_meta("source_sha256", "") == FileAccess.get_sha256(SOURCE + "motion/seal_prone_crawl.json"), "crawl source provenance")
	current.loop_mode = Animation.LOOP_NONE
	current_asset_runtime.profile.clip_paths[&"prone_backward"] = "res://assets/animations/mixamo/Moving Backward In Prone Position.fbx"
	current_asset_runtime.animation_player.remove_animation_library("")
	current_asset_runtime._build_animation_library()
	var previous: Animation = current_asset_runtime.animation_library.get_animation(&"prone_backward").duplicate()
	previous.loop_mode = Animation.LOOP_NONE
	var units: float = current_skeleton.get_meta("iso_proportions").metres_per_source_unit / 62.0
	var rows := []
	var max_hip_delta := 0.0
	for index in int(original.samples):
		var phase := float(index) / float(original.frames)
		var source := _globals(original, index)
		var raw_xz: Vector3 = source.skel_root.origin
		raw_xz.y = 0.0
		var source_points := {}
		for joint: String in JOINTS: source_points[joint] = _vec((source[joint].origin - raw_xz) * METRES)
		var corrected := current.duplicate() as Animation
		var track := corrected.find_track(NodePath(".:mixamorig_Hips"), Animation.TYPE_POSITION_3D)
		var corrected_pos := corrected.position_track_interpolate(track, phase * corrected.length)
		corrected_pos.y = float(source.hips.origin.y) * units
		# Observer-only exact key at this phase. This does not mutate a shared clip.
		corrected.position_track_insert_key(track, phase * corrected.length, corrected_pos)
		var before := _sample_clip(current, phase)
		var after := _sample_clip(corrected, phase)
		var prior := _sample_clip(previous, phase)
		var delta := float(before.hips[1]) - float(source_points.hips[1])
		max_hip_delta = maxf(max_hip_delta, absf(delta))
		rows.append({"phase": phase, "original": source_points, "current": before, "source_height_candidate": after,
			"previous_mixamo_backward": prior, "hip_y_current_minus_source_m": delta})
	report["prone_same_phase"] = rows
	report["maximum_current_hip_height_error_m"] = max_hip_delta
	report["original_source_sha256"] = FileAccess.get_sha256(SOURCE + "motion/seal_prone_crawl.json")
	report["scope"] = "Offline exact same-phase source FK versus built poses and old Mixamo. No live layers; candidate only changes sampled pelvis Y. Not visual acceptance."
	current_model.free()
	_finish(output)


func _sample_clip(animation: Animation, phase: float) -> Dictionary:
	current_skeleton.reset_bone_poses()
	var time := phase * animation.length
	for track in animation.get_track_count():
		var path := animation.track_get_path(track)
		if path.get_subname_count() != 1: continue
		var bone := current_skeleton.find_bone(path.get_subname(0))
		if bone < 0: continue
		match animation.track_get_type(track):
			Animation.TYPE_POSITION_3D: current_skeleton.set_bone_pose_position(bone, animation.position_track_interpolate(track, time))
			Animation.TYPE_ROTATION_3D: current_skeleton.set_bone_pose_rotation(bone, animation.rotation_track_interpolate(track, time))
			Animation.TYPE_SCALE_3D: current_skeleton.set_bone_pose_scale(bone, animation.scale_track_interpolate(track, time))
	current_skeleton.force_update_all_bone_transforms()
	var points := {}
	for joint: String in JOINTS:
		var bone := current_skeleton.find_bone("mixamorig_" + JOINTS[joint])
		_check(bone >= 0, "joint exists " + joint)
		points[joint] = _vec(current_skeleton.global_transform * current_skeleton.get_bone_global_pose(bone).origin)
	return points
