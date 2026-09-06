extends "res://tools/bake_pistol_compressed_idle.gd"

## Asset-only repair of the captured weapon-root correction. Read the previously
## saved poses; NEVER recapture the live graph, which may now select these files.
## The authored wrist must make the immutable calibrated mount point forward.

func _run() -> void:
	var scene := (load("res://main.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(scene)
	await _frames(60)
	var player := scene.get_node("Player") as CharacterBody3D
	var controller := scene.get_node("WeaponController")
	var mannequin := player.get_node("Mannequin")
	var driver := mannequin.get("production_animation") as Node
	player.set_physics_process(false)
	mannequin.set_process(false)
	_expect(bool(controller.call("apply_authorized_weapon_pickup", MARK_23_PATH)), "canonical Mark 23 mount for saved-asset alignment")
	await _frames(30)
	driver.set_process(false)
	(driver.get("animation_tree") as AnimationTree).active = false
	var camera: Camera3D
	if DisplayServer.get_name() != "headless":
		_hide_canvas_layers(scene)
		camera = Camera3D.new()
		camera.fov = 36.0
		scene.add_child(camera)
		camera.current = true
	var report: Dictionary = {"method": "saved native animation + unchanged canonical raw palm mount", "assets": {}}
	for stance in ["standing", "crouched"]:
		for kind in ["pistol_recovery_reference_", "pistol_compressed_idle_"]:
			var name: String = kind + stance
			report["assets"][name] = await _align_asset(player, driver, camera, name)
	var file := FileAccess.open(OUTPUT + "/wrist_alignment_report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t") + "\n")
	file.close()
	scene.queue_free()
	await process_frame
	if failures.is_empty():
		print("PISTOL_COMPRESSED_WRIST_ALIGNMENT PASS " + JSON.stringify(report))
		quit(0)
	else:
		print("PISTOL_COMPRESSED_WRIST_ALIGNMENT FAIL " + JSON.stringify(failures))
		quit(1)

func _align_asset(player: CharacterBody3D, driver: Node, camera: Camera3D, name: String) -> Dictionary:
	var path := OUTPUT + "/" + name + ".tres"
	var raw_path := OUTPUT + "/captured_raw/" + name + ".tres"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT + "/captured_raw"))
	# Preserve immutable capture inputs on first use. Every subsequent alignment
	# rebuild starts from those references, so the correction cannot accumulate.
	if not FileAccess.file_exists(raw_path):
		_expect(DirAccess.copy_absolute(ProjectSettings.globalize_path(path), ProjectSettings.globalize_path(raw_path)) == OK, name + " preserves raw capture")
	var animation := ResourceLoader.load(raw_path, "Animation", ResourceLoader.CACHE_MODE_IGNORE) as Animation
	var skeleton := driver.get("skeleton") as Skeleton3D
	var solver := driver.get("weapon_pose_solver") as Node
	var weapon := solver.get("weapon_node") as Node3D
	skeleton.clear_bones_global_pose_override()
	skeleton.reset_bone_poses()
	_sample_animation(animation, skeleton)
	var original := _snapshot(skeleton)
	var original_locals := _locals(skeleton, original)
	solver.call("_set_weapon_solver_owned", true)
	solver.call("_weapon_transform_on_trigger_hand", solver.call("_right_hand_grip_world_transform"), true)
	var before := _sample(skeleton, solver)
	var forward := _world_aim_direction(player, 0.0, 0.0)
	var muzzle := solver.get("muzzle_socket") as Marker3D
	var barrel := solver.get("barrel_base_socket") as Marker3D
	var optic := solver.get("optic_socket") as Marker3D
	var bore := barrel.global_position.direction_to(muzzle.global_position)
	var optic_up := (optic.global_position - barrel.global_position).normalized()
	var correction: Quaternion = solver.call("_aim_frame_alignment_delta", bore, forward, optic_up, Vector3.UP)
	var right := skeleton.find_bone("mixamorig_RightHand")
	var right_world := skeleton.global_transform * original[right]
	var corrected_right_basis := (Basis(correction) * right_world.basis.orthonormalized()).orthonormalized()
	_solve_contact(skeleton, solver, "right", Transform3D(corrected_right_basis, before["right_palm"]), original)
	solver.call("_weapon_transform_on_trigger_hand", solver.call("_right_hand_grip_world_transform"), true)
	# Source left-wrist orientation already followed the final physical support
	# socket. Keep that basis and close only its tiny socket-position residual.
	var left := skeleton.find_bone("mixamorig_LeftHand")
	var left_world := skeleton.global_transform * original[left]
	var support := solver.get("support_socket") as Marker3D
	_solve_contact(skeleton, solver, "left", Transform3D(left_world.basis.orthonormalized(), support.global_position), original)
	var solved := _snapshot(skeleton)
	var solved_locals := _locals(skeleton, solved)
	var output := animation.duplicate() as Animation
	for bone in ["mixamorig_RightArm", "mixamorig_RightForeArm", "mixamorig_RightHand", "mixamorig_LeftArm", "mixamorig_LeftForeArm", "mixamorig_LeftHand"]:
		var index := skeleton.find_bone(bone)
		var track := output.find_track(NodePath(".:" + bone), Animation.TYPE_ROTATION_3D)
		_expect(track >= 0, bone + " original rotation track exists")
		for key in range(output.track_get_key_count(track) - 1, -1, -1):
			output.track_remove_key(track, key)
		output.track_insert_key(track, 0.0, solved_locals[index].basis.orthonormalized().get_rotation_quaternion())
	var shoulder_error := 0.0
	for bone in ["mixamorig_Spine", "mixamorig_Spine1", "mixamorig_Spine2", "mixamorig_Neck", "mixamorig_Head", "mixamorig_RightShoulder", "mixamorig_LeftShoulder"]:
		var index := skeleton.find_bone(bone)
		shoulder_error = maxf(shoulder_error, rad_to_deg(original_locals[index].basis.orthonormalized().get_rotation_quaternion().angle_to(solved_locals[index].basis.orthonormalized().get_rotation_quaternion())))
	_expect(shoulder_error <= 0.05, name + " original chest/head/shoulders preserved")
	_expect(ResourceSaver.save(output, path) == OK, name + " wrist aligned resource saved")
	# Reload the actual saved resource and evaluate without ANY animation/IK/aim
	# modifiers. This is the raw calibrated mount proof missing from the capture.
	skeleton.clear_bones_global_pose_override()
	skeleton.reset_bone_poses()
	_sample_animation(ResourceLoader.load(path, "Animation", ResourceLoader.CACHE_MODE_IGNORE) as Animation, skeleton)
	solver.call("_weapon_transform_on_trigger_hand", solver.call("_right_hand_grip_world_transform"), true)
	var after := _sample(skeleton, solver)
	var geometry := _measure_pistol_geometry(driver, muzzle.global_position + forward * 25.0)
	var palm_shift := Vector3(before["right_palm"]).distance_to(after["right_palm"])
	_expect(float(geometry["bore_error_deg"]) <= 0.2 and absf(float(geometry["axial_roll_deg"])) <= 0.2, name + " saved raw mount bore forward/upright")
	_expect(float(after["trigger_error_m"]) <= 0.002 and float(after["support_error_m"]) <= 0.002, name + " saved raw mount contacts")
	_expect(palm_shift <= 0.002, name + " trigger palm position preserved")
	if camera != null:
		_aim_review_camera(camera, driver, player)
		await _capture(OUTPUT + "/" + name + "_mounted.png")
	return {"wrist_correction_deg": rad_to_deg(correction.get_angle()), "protected_bone_delta_deg": shoulder_error, "raw_bore_error_deg": geometry["bore_error_deg"], "raw_roll_deg": geometry["axial_roll_deg"], "trigger_error_m": after["trigger_error_m"], "support_error_m": after["support_error_m"], "trigger_palm_shift_m": palm_shift}

func _solve_contact(skeleton: Skeleton3D, solver: Node, side: String, target: Transform3D, original: Array[Transform3D]) -> void:
	var prefix := "mixamorig_" + ("Right" if side == "right" else "Left")
	var hand := skeleton.find_bone(prefix + "Hand")
	var elbow := skeleton.find_bone(prefix + "ForeArm")
	var upper := skeleton.find_bone(prefix + "Arm")
	var wrist_world := skeleton.global_transform * original[hand].origin
	var elbow_world := skeleton.global_transform * original[elbow].origin
	var upper_world := skeleton.global_transform * original[upper].origin
	var natural_pole := (elbow_world - upper_world.lerp(wrist_world, 0.5)).normalized()
	var target_marker := Marker3D.new()
	var pole := Marker3D.new()
	skeleton.add_child(target_marker)
	skeleton.add_child(pole)
	target_marker.global_transform = target
	pole.global_position = elbow_world + natural_pole * 0.4
	var ik := SocketIK.create(skeleton, "WristMountAuthoring" + side, prefix + "Arm", prefix + "Hand")
	ik.override_tip_basis = true
	SocketIK.solve(skeleton, {StringName(prefix + "Hand"): hand}, ik, target_marker, pole, StringName(prefix + "Hand"), solver.get(side + "_palm_anchor_local"), true, 1.0, 8)
	ik.queue_free()
	target_marker.queue_free()
	pole.queue_free()

func _sample_animation(animation: Animation, skeleton: Skeleton3D) -> void:
	for track in animation.get_track_count():
		var bone := String(animation.track_get_path(track)).get_slice(":", 1)
		var index := skeleton.find_bone(bone)
		if index < 0:
			continue
		match animation.track_get_type(track):
			Animation.TYPE_ROTATION_3D:
				skeleton.set_bone_pose_rotation(index, animation.rotation_track_interpolate(track, 0.0))
			Animation.TYPE_POSITION_3D:
				skeleton.set_bone_pose_position(index, animation.position_track_interpolate(track, 0.0))
			Animation.TYPE_SCALE_3D:
				skeleton.set_bone_pose_scale(index, animation.scale_track_interpolate(track, 0.0))
	skeleton.force_update_all_bone_transforms()
