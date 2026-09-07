extends "res://tools/build_jump_peak_slide.gd"
## Offline full-body side dives. Reuses canonical native bone sampling only.
var combo_profile: Dictionary

func _run() -> void:
	combo_profile = JSON.parse_string(FileAccess.get_file_as_string("res://config/jump_direction_combos.json"))
	var profile := Profile.new()
	profile.load_project_map()
	profile.clip_paths[&"goalkeeper_source"] = "res://assets/animations/mixamo/Goalkeeper Diving Save.fbx"
	profile.clip_paths[&"source_get_up"] = "res://assets/animations/mixamo/Rifle Prone To Kneel.fbx"
	for clip in [&"jump_dive_left", &"jump_dive_right", &"jump_slide_crouch", &"jump_back_crouch", &"jump_slide_prone"]:
		profile.clip_paths.erase(clip)
	for clip in combo_profile.crouch_clips.values():
		profile.clip_paths.erase(StringName(clip))
	var holder := Node3D.new()
	root.add_child(holder)
	var runtime := Assets.new()
	runtime.build(holder, profile, 62.0, Vector3(-0.02, 0.08, 0.05), Vector3(-90, 180, 0))
	rig = runtime.skeleton
	source = runtime.animation_player.get_animation(&"goalkeeper_source")
	upper = runtime.animation_player.get_animation(&"aim_idle")
	var start := _pose(upper, 0.0)
	var rifle := _pose(upper, 0.0)
	var crouch := _pose(runtime.animation_player.get_animation(&"aim_idle_crouch"), 0.0)
	var prone := _pose(runtime.animation_player.get_animation(&"idle_prone"), 0.0)
	var grounded_source: Animation = runtime.animation_player.get_animation(&"death_right")
	var get_up: Animation = runtime.animation_player.get_animation(&"source_get_up")
	var kneel_to_prone: Animation = runtime.animation_player.get_animation(&"crouch_to_prone")
	var hips := rig.find_bone("mixamorig_Hips")
	for side in ["left", "right"]:
		var grounded := _pose(grounded_source, 2.64)
		# This source falls left when struck from the right.
		if side == "right":
			grounded = _mirror_goal_pose(grounded)
		var output := Animation.new()
		output.length = 1.65
		output.resource_name = "Jump Dive " + side.capitalize()
		output.set_meta("authoring_tool", "res://tools/build_jump_direction_dives.gd")
		output.set_meta("source_clip", "res://assets/animations/mixamo/Goalkeeper Diving Save.fbx")
		output.set_meta("rest_source", "res://assets/animations/mixamo/Pro Rifle Pack/death from right.fbx")
		output.set_meta("recovery_source", "res://assets/animations/mixamo/Rifle Prone To Kneel.fbx")
		var tracks: Array[int] = []
		for bone in rig.get_bone_count():
			for type in [Animation.TYPE_ROTATION_3D, Animation.TYPE_POSITION_3D]:
				var track := output.add_track(type)
				output.track_set_path(track, NodePath(".:" + rig.get_bone_name(bone)))
				tracks.append(track)
		for frame in 51:
			var time := minf(frame / 30.0, output.length)
			var source_time := lerpf(0.45, 1.94, minf(time / 1.05, 1.0)) if time <= 1.05 else lerpf(1.94, source.length, (time - 1.05) / 0.60)
			var pose := _pose(source, source_time)
			if side == "left":
				pose = _mirror_goal_pose(pose)
			if time <= 1.05:
				for bone in rig.get_bone_count():
					pose[bone] = pose[bone].interpolate_with(grounded[bone], smoothstep(0.45, 1.0, time))
			else:
				var recovery := _pose(get_up, get_up.length * smoothstep(1.12, 1.52, time))
				for bone in rig.get_bone_count():
					pose[bone] = grounded[bone].interpolate_with(recovery[bone], smoothstep(1.05, 1.25, time))
			_fit_rifle_torso_frame(pose, rifle, true)
			var weight := smoothstep(0.0, 0.15, time) * (1.0 - smoothstep(1.50, 1.65, time))
			for bone in rig.get_bone_count():
				pose[bone] = start[bone].interpolate_with(pose[bone], weight)
			_ground(pose, hips)
			var globals := _globals(pose)
			var lowest := 0.0
			for bone in rig.get_bone_count():
				lowest = minf(lowest, globals[bone].origin.y - 0.075 / 62.0)
			pose[hips].origin.y -= lowest
			for bone in rig.get_bone_count():
				output.rotation_track_insert_key(tracks[bone * 2], time, pose[bone].basis.get_rotation_quaternion().normalized())
				output.position_track_insert_key(tracks[bone * 2 + 1], time, pose[bone].origin)
		var path: String = "res://assets/animations/authored/jump_dive_" + side + ".tres"
		var result := ResourceSaver.save(output, path)
		if result != OK:
			push_error("Dive save failed: " + error_string(result))
			quit(1)
			return
		print("JUMP_DIRECTION_DIVE_BUILD OK ", path)
		if not _save_crouch_entry(output, "crouch_dive_" + side, crouch):
			return
	for entry in [[&"jump_peak_slide_candidate", "jump_slide_crouch"], [&"backward_dive_pose_candidate", "jump_back_crouch"], [&"jump_peak_slide_candidate", "jump_slide_prone"]]:
		var base: Animation = runtime.animation_player.get_animation(entry[0])
		var output := base.duplicate(true) as Animation
		output.resource_name = String(entry[1])
		output.set_meta("authoring_tool", "res://tools/build_jump_direction_dives.gd")
		var is_prone: bool = entry[1] == "jump_slide_prone"
		output.set_meta("exit_posture", "PRONE" if is_prone else "CROUCHED")
		var end_pose: Array[Transform3D] = prone if is_prone else crouch
		var held := _pose(base, 1.05)
		if entry[1] == "jump_back_crouch":
			# Keep the source legs but bake the same forward rifle torso frame.
			for frame in 51:
				var time := minf(frame / 30.0, output.length)
				var pose := _pose(base, time)
				_fit_rifle_torso_frame(pose, rifle, false)
				var weight := smoothstep(0.0, 0.20, time) * (1.0 - smoothstep(1.05, output.length, time))
				var original := _pose(base, time)
				for bone in rig.get_bone_count():
					pose[bone] = original[bone].interpolate_with(pose[bone], weight)
				for track in output.get_track_count():
					var bone := rig.find_bone(String(output.track_get_path(track).get_subname(0)))
					var value = pose[bone].basis.get_rotation_quaternion().normalized() if output.track_get_type(track) == Animation.TYPE_ROTATION_3D else pose[bone].origin
					output.track_insert_key(track, time, value)
			held = _pose(output, 1.05)
		for track in output.get_track_count():
			var bone := rig.find_bone(String(output.track_get_path(track).get_subname(0)))
			for key in output.track_get_key_count(track):
				var time := output.track_get_key_time(track, key)
				if time < 1.05:
					continue
				var pose: Transform3D = held[bone].interpolate_with(end_pose[bone], smoothstep(1.05, output.length, time))
				if is_prone:
					var authored := _pose(kneel_to_prone, kneel_to_prone.length * smoothstep(1.05, output.length, time))
					pose = held[bone].interpolate_with(authored[bone], smoothstep(1.05, 1.22, time))
				output.track_set_key_value(track, key, pose.basis.get_rotation_quaternion().normalized() if output.track_get_type(track) == Animation.TYPE_ROTATION_3D else pose.origin)
		var path: String = "res://assets/animations/authored/" + String(entry[1]) + ".tres"
		var result := ResourceSaver.save(output, path)
		if result != OK:
			push_error("Crouch exit save failed: " + error_string(result))
			quit(1)
			return
		print("JUMP_DIRECTION_CROUCH_BUILD OK ", path)
		if entry[1] == "jump_back_crouch" and not _save_crouch_entry(output, "crouch_dive_back", crouch):
			return
	holder.queue_free()
	await process_frame
	quit()

func _fit_rifle_torso_frame(pose: Array[Transform3D], rifle: Array[Transform3D], bank_with_body: bool) -> void:
	var spine := rig.find_bone("mixamorig_Spine")
	var hips := rig.find_bone("mixamorig_Hips")
	var original_globals := _globals(pose)
	var rifle_globals := _globals(rifle)
	# Preserve the authored pelvis/legs. Only remove their inherited chest pitch
	# and yaw; retain a bounded side bank so this is not an upright torso on a roll.
	var pelvis_up := original_globals[hips].basis.y.normalized()
	var roll := clampf(atan2(-pelvis_up.x, pelvis_up.y), -deg_to_rad(float(combo_profile.side_torso_roll_degrees)), deg_to_rad(float(combo_profile.side_torso_roll_degrees))) if bank_with_body else 0.0
	# Native rig faces +Z (model faces -Z): +Z bank leans to character-right.
	roll += deg_to_rad(float(combo_profile.torso_right_lean_degrees))
	for bone in rig.get_bone_count():
		if _is_upper(bone, spine):
			pose[bone] = rifle[bone]
	var desired := Basis(Vector3.BACK, roll) * rifle_globals[spine].basis
	pose[spine].basis = original_globals[rig.get_bone_parent(spine)].basis.inverse() * desired

func _save_crouch_entry(base: Animation, clip_name: String, crouch: Array[Transform3D]) -> bool:
	var output := base.duplicate(true) as Animation
	output.resource_name = clip_name
	output.set_meta("entry_posture", "CROUCHED")
	var end := float(combo_profile.crouch_entry_seconds)
	for track in output.get_track_count():
		var bone := rig.find_bone(String(output.track_get_path(track).get_subname(0)))
		for key in output.track_get_key_count(track):
			var time := output.track_get_key_time(track, key)
			if time >= end:
				break
			var source_pose := _pose(base, time)
			var pose := crouch[bone].interpolate_with(source_pose[bone], smoothstep(0.0, end, time))
			output.track_set_key_value(track, key, pose.basis.get_rotation_quaternion().normalized() if output.track_get_type(track) == Animation.TYPE_ROTATION_3D else pose.origin)
	var path := "res://assets/animations/authored/" + clip_name + ".tres"
	var result := ResourceSaver.save(output, path)
	if result != OK:
		push_error("Crouch entry save failed: " + error_string(result))
		quit(1)
		return false
	print("CROUCH_DIVE_ENTRY_BUILD OK ", path)
	return true

func _mirror_goal_pose(pose: Array[Transform3D]) -> Array[Transform3D]:
	var rests: Array[Transform3D] = []
	for bone in rig.get_bone_count(): rests.append(rig.get_bone_rest(bone))
	var rest_globals := _globals(rests)
	var globals := _globals(pose)
	var reflected: Array[Transform3D] = []
	var flip := Basis.from_scale(Vector3(-1, 1, 1))
	for bone in rig.get_bone_count():
		var name := rig.get_bone_name(bone)
		var other := name.replace("Left", "Right") if "Left" in name else name.replace("Right", "Left")
		var partner := rig.find_bone(other)
		var deformation := globals[partner] * rest_globals[partner].affine_inverse()
		reflected.append(Transform3D(flip * deformation.basis * flip, flip * deformation.origin) * rest_globals[bone])
	var result: Array[Transform3D] = []
	for bone in rig.get_bone_count():
		var parent := rig.get_bone_parent(bone)
		result.append(reflected[parent].affine_inverse() * reflected[bone] if parent >= 0 else reflected[bone])
	return result
