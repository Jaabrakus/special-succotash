extends "res://tools/rifle_reference_visual_probe.gd"

const CLIP := &"jump_peak_slide_candidate"
const OUT := "res://art_source/jump_peak_slide"
const Workshop := preload("res://scripts/labs/animation_workshop_repository.gd")

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	output_prefix = ProjectSettings.globalize_path(OUT + "/right_knee_canonical_review")
	root.size = Vector2i(960, 640)
	scene = (load("res://main.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(scene)
	await _frames(60)
	player = scene.get_node("Player") as CharacterBody3D
	driver = player.get_node("Mannequin/ProductionAnimation")
	controller = scene.get_node("WeaponController")
	_install_fixture()
	await _frames(60)
	player.global_position = Vector3(500, 0.02, 500)
	player.velocity = Vector3.ZERO
	await _frames(20)
	var animation_player := driver.get("animation_player") as AnimationPlayer
	if not animation_player.has_animation(CLIP):
		failures.append("Canonical runtime did not load the saved candidate")
		_finish()
		return
	var skeleton := driver.get("skeleton") as Skeleton3D
	if skeleton.get_bone_count() != 65:
		failures.append("Original 65-bone rig changed")
	var source_path := String(driver.get("clip_paths").get(&"jump_forward_action", ""))
	if source_path != "res://assets/animations/mixamo/Shooter Pack/jump forward.fbx":
		failures.append("Normal forward jump assignment changed")
	if String(driver.get("clip_paths").get(&"dive_roll", "")) != "res://assets/animations/mixamo/Running Dive Roll.fbx":
		failures.append("Normal dive assignment changed")
	var animation := animation_player.get_animation(CLIP)
	if not animation_player.has_animation(&"backward_dive_pose_candidate"):
		failures.append("Preserved backward-dive pose is missing from canonical library")
	var authored := Workshop.new().scan_authored("res://assets/animations/authored")
	if not authored.values().has("res://assets/animations/authored/jump_peak_slide_candidate.tres"):
		failures.append("Animation Studio cannot discover the saved candidate")
	if not authored.values().has("res://assets/animations/authored/backward_dive_pose_candidate.tres"):
		failures.append("Animation Studio cannot discover preserved backward-dive pose")
	# Check every authored held sample, not just one lucky playback frame.
	var saved := load("res://assets/animations/authored/jump_peak_slide_candidate.tres") as Animation
	var pose: Array[Transform3D] = []
	for bone in skeleton.get_bone_count():
		pose.append(skeleton.get_bone_rest(bone))
	for sample in range(9, 32):
		var time := float(sample) / 30.0
		for track in saved.get_track_count():
			var bone := skeleton.find_bone(saved.track_get_path(track).get_subname(0))
			if saved.track_get_type(track) == Animation.TYPE_POSITION_3D:
				pose[bone].origin = saved.position_track_interpolate(track, time)
			elif saved.track_get_type(track) == Animation.TYPE_ROTATION_3D:
				pose[bone].basis = Basis(saved.rotation_track_interpolate(track, time))
		var globals: Array[Transform3D] = []
		for bone in skeleton.get_bone_count():
			var parent := skeleton.get_bone_parent(bone)
			globals.append(globals[parent] * pose[bone] if parent >= 0 else pose[bone])
		var knee := globals[skeleton.find_bone("mixamorig_RightLeg")].origin * 62.0
		var left_foot := globals[skeleton.find_bone("mixamorig_LeftFoot")].origin * 62.0
		if knee.y < 0.04 or knee.y > 0.13:
			failures.append("Held right knee not grounded at %.3fs: %.3fm" % [time, knee.y])
		if left_foot.z < knee.z + 0.20:
			failures.append("Left foot is not ahead of grounded right knee")
	for track in animation.get_track_count():
		var path := animation.track_get_path(track)
		if path.get_subname_count() != 1 or skeleton.find_bone(path.get_subname(0)) < 0:
			failures.append("Candidate contains a non-skeleton track")
		for key in animation.track_get_key_count(track):
			if animation.track_get_type(track) == Animation.TYPE_ROTATION_3D:
				var value: Quaternion = animation.track_get_key_value(track, key)
				if not value.is_finite() or absf(value.length() - 1.0) > 0.001:
					failures.append("Invalid candidate quaternion")
			elif String(path).ends_with(":mixamorig_Hips"):
				var position: Vector3 = animation.track_get_key_value(track, key)
				if absf(position.x) + absf(position.z) > 0.00001:
					failures.append("Candidate contains horizontal root travel")
	var origin := player.global_position
	var standing_head := _height(skeleton, &"mixamorig_Head")
	if not bool(driver.call("play_action", CLIP, 0.05)):
		failures.append("Canonical action playback refused candidate")
	await _frames(30)
	var low_head := _height(skeleton, &"mixamorig_Head")
	var right_knee_height := _height(skeleton, &"mixamorig_RightLeg")
	if right_knee_height < 0.02 or right_knee_height > 0.13:
		failures.append("Canonical right knee not grounded: %.3fm" % right_knee_height)
	if StringName(driver.get("current_clip")) != CLIP:
		failures.append("Canonical graph is not playing the candidate")
	if low_head > standing_head - 0.20:
		failures.append("Canonical candidate did not lower the character")
	await _frames(90)
	if player.global_position.distance_to(origin) > 0.03:
		failures.append("Animation moved the authoritative stationary player")
	if StringName(driver.get("requested_action")) != &"":
		failures.append("Candidate action did not release")
	samples.append({"standing_head_m": standing_head, "held_head_m": low_head, "right_knee_m": right_knee_height, "body_drift_m": player.global_position.distance_to(origin)})
	print("SLIDE_CANONICAL height_before=", standing_head, " height_low=", low_head, " right_knee=", right_knee_height, " body_drift=", player.global_position.distance_to(origin))
	if capture:
		for index in 16:
			var marker := MeshInstance3D.new()
			var mesh := BoxMesh.new()
			mesh.size = Vector3(20, 0.01, 0.04)
			marker.mesh = mesh
			marker.position = Vector3(500, 0.005, 495 - index * 1.0)
			scene.add_child(marker)
		var caption := Label.new()
		caption.position = Vector2(28, 24)
		caption.text = "RIGHT-KNEE SLIDE / POSE TEST\nExisting movement underneath — controls unchanged"
		caption.add_theme_font_size_override("font_size", 22)
		root.add_child(caption)
		Input.action_press(&"move_forward")
		await _frames(20)
		driver.call("play_action", CLIP, 0.05)
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT + "/right_knee_frames"))
		for frame in 66:
			await process_frame
			var focus := player.global_position + Vector3.UP * 0.85
			camera.global_position = focus + player.global_basis * Vector3(3.7, 0.7, 2.0)
			camera.look_at(focus)
			camera.current = true
			await RenderingServer.frame_post_draw
			var shot := root.get_texture().get_image()
			shot.resize(960, 600, Image.INTERPOLATE_LANCZOS)
			shot.save_png(OUT + "/right_knee_frames/%03d.png" % frame)
		Input.action_release(&"move_forward")
		caption.queue_free()
	print("JUMP_PEAK_SLIDE_REGRESSION ", "PASS" if failures.is_empty() else "FAIL", " ", failures)
	_finish()
