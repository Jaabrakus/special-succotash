extends "res://tools/pistol_fire_recovery_visual_check.gd"

## Authoring-only bake: capture the canonical accepted recovery, retract both
## hands together, and save native upper-body tracks over the untouched stance.
## Never selects a profile, changes source clips, or changes a runtime owner.
const OUTPUT := "res://assets/animations/authored/pistol_compressed"
const RETRACTION_M := 0.14
const SocketIK := preload("res://scripts/player/operator_weapon_socket_ik.gd")

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
	_expect(bool(controller.call("apply_authorized_weapon_pickup", MARK_23_PATH)), "canonical Mark 23 equips for native capture")
	await _frames(30)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	var report: Dictionary = {"source": "canonical main.tscn accepted FIRE_RECOVERY", "retraction_m": RETRACTION_M, "stances": {}}
	var camera: Camera3D
	if DisplayServer.get_name() != "headless":
		_hide_canvas_layers(scene)
		camera = Camera3D.new()
		camera.fov = 36.0
		scene.add_child(camera)
		camera.current = true
	for posture_index in [0, 1]:
		report["stances"]["standing" if posture_index == 0 else "crouched"] = await _bake_stance(player, controller, driver, camera, posture_index)
	var file := FileAccess.open(OUTPUT + "/report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t") + "\n")
	file.close()
	scene.queue_free()
	await process_frame
	if failures.is_empty():
		print("PISTOL_COMPRESSED_IDLE_BAKE PASS " + JSON.stringify(report))
		quit(0)
	else:
		print("PISTOL_COMPRESSED_IDLE_BAKE FAIL " + JSON.stringify(failures))
		quit(1)

func _bake_stance(player: CharacterBody3D, controller: Node, driver: Node, camera: Camera3D, posture_index: int) -> Dictionary:
	var stance := "standing" if posture_index == 0 else "crouched"
	var posture := &"STANDING" if posture_index == 0 else &"CROUCHED"
	var tree := driver.get("animation_tree") as AnimationTree
	var skeleton := driver.get("skeleton") as Skeleton3D
	var solver := driver.get("weapon_pose_solver") as Node
	var weapon := solver.get("weapon_node") as Node3D
	driver.set_process(true)
	tree.active = true
	driver.call("clear_fire_ready_aim")
	_expect(bool(player.call("_try_set_posture", posture_index)), "canonical " + stance)
	var forward := _world_aim_direction(player, 0.0, 0.0)
	var target := player.global_position + Vector3.UP * (1.48 if posture_index == 0 else 1.20) + forward * 25.0
	driver.call("set_visual_inputs", Vector2.ZERO, posture, 0.0, 0.0, 0.0, false, 0.0, 0.0, &"LOCOMOTION", 0.0, &"WALK", 0.0, target, Vector2.ZERO, 0.0, &"IDLE", 0.0)
	await _frames(40)
	await _await_ballistics_ready(controller)
	var shot: Dictionary = controller.call("request_fire")
	_expect(bool(shot.get("fired", false)), stance + " accepted shot")
	await create_timer(0.25).timeout
	await _frames(2)
	# Use the physical muzzle height, not a guessed posture-camera height. This
	# removes parallax pitch from the neutral authoring frame without moving aim.
	target = (solver.get("muzzle_socket") as Marker3D).global_position + forward * 25.0
	driver.call("set_visual_inputs", Vector2.ZERO, posture, 0.0, 0.0, 0.0, false, 0.0, 0.0, &"LOCOMOTION", 0.0, &"WALK", 0.0, target, Vector2.ZERO, 0.0, &"IDLE", 0.0)
	await _frames(8)
	var source := _sample(skeleton, solver)
	var geometry := _measure_pistol_geometry(driver, target)
	print("PISTOL_COMPRESSED_SOURCE " + stance + " " + JSON.stringify({"trigger_m": source["trigger_error_m"], "support_m": source["support_error_m"], "bore": geometry}))
	_expect(float(source["trigger_error_m"]) <= 0.01 and float(source["support_error_m"]) <= 0.01, stance + " source hand contacts")
	_expect(float(geometry["bore_error_deg"]) <= 1.0, stance + " source bore follows target")
	# Freeze only this isolated authoring scene. Copy effective global poses first:
	# Skeleton3D globals are skeleton-space and include the accepted IK overrides.
	driver.set_process(false)
	tree.active = false
	var original := _snapshot(skeleton)
	var local_poses := _locals(skeleton, original)
	skeleton.clear_bones_global_pose_override()
	for index in skeleton.get_bone_count():
		skeleton.set_bone_pose(index, local_poses[index])
	skeleton.force_update_all_bone_transforms()
	if camera != null:
		_aim_review_camera(camera, driver, player)
		await _capture(OUTPUT + "/" + stance + "_source.png")
	var retract := -forward * RETRACTION_M
	for side in ["right", "left"]:
		var prefix := "mixamorig_Right" if side == "right" else "mixamorig_Left"
		var hand := skeleton.find_bone(prefix + "Hand")
		var elbow := skeleton.find_bone(prefix + "ForeArm")
		var palm: Vector3 = source[side + "_palm"]
		var hand_world := skeleton.global_transform * original[hand]
		var target_marker := Marker3D.new()
		var pole := Marker3D.new()
		skeleton.add_child(target_marker)
		skeleton.add_child(pole)
		target_marker.global_transform = Transform3D(hand_world.basis.orthonormalized(), palm + retract)
		var elbow_world := skeleton.global_transform * original[elbow].origin
		pole.global_position = elbow_world + Vector3.DOWN * 0.25 + player.global_basis.x * (0.10 if side == "right" else -0.10)
		var ik := SocketIK.create(skeleton, "Authoring" + side, prefix + "Arm", prefix + "Hand")
		ik.override_tip_basis = true
		SocketIK.solve(skeleton, {StringName(prefix + "Hand"): hand}, ik, target_marker, pole, StringName(prefix + "Hand"), solver.get(side + "_palm_anchor_local"), true, 1.0, 8)
		ik.queue_free()
		target_marker.queue_free()
		pole.queue_free()
	var compressed := _snapshot(skeleton)
	var compressed_locals := _locals(skeleton, compressed)
	var library := driver.get("dynamic_anim_lib") as AnimationLibrary
	var base_name := &"pistol_idle" if posture_index == 0 else &"pistol_idle_kneeling"
	var base := library.get_animation(base_name)
	var ready := _compose_pose(base, skeleton, local_poses)
	ready.resource_name = "pistol_recovery_reference_" + stance
	ready.loop_mode = Animation.LOOP_LINEAR
	_expect(ResourceSaver.save(ready, OUTPUT + "/" + ready.resource_name + ".tres") == OK, stance + " accepted recovery reference saved")
	var animation := base.duplicate() as Animation
	var count := 0
	for index in skeleton.get_bone_count():
		var bone := skeleton.get_bone_name(index)
		if not _upper(bone):
			continue
		var track_path := NodePath(".:" + bone)
		var track := animation.find_track(track_path, Animation.TYPE_ROTATION_3D)
		if track < 0:
			track = animation.add_track(Animation.TYPE_ROTATION_3D)
			animation.track_set_path(track, track_path)
		for key in range(animation.track_get_key_count(track) - 1, -1, -1):
			animation.track_remove_key(track, key)
		animation.track_insert_key(track, 0.0, compressed_locals[index].basis.orthonormalized().get_rotation_quaternion())
		count += 1
	animation.resource_name = "pistol_compressed_idle_" + stance
	animation.loop_mode = Animation.LOOP_LINEAR
	_expect(ResourceSaver.save(animation, OUTPUT + "/" + animation.resource_name + ".tres") == OK, stance + " native authored animation saved")
	# The same rigid weapon follows the same unchanged palm basis and identical
	# displacement. This does not change scale, sockets, or either saved grip.
	weapon.global_position += retract
	var after := _sample(skeleton, solver)
	var max_palm_error := 0.0
	var max_wrist_angle := 0.0
	for side in ["right", "left"]:
		max_palm_error = maxf(max_palm_error, Vector3(after[side + "_palm"]).distance_to(Vector3(source[side + "_palm"]) + retract))
		var index := skeleton.find_bone("mixamorig_" + ("Right" if side == "right" else "Left") + "Hand")
		max_wrist_angle = maxf(max_wrist_angle, rad_to_deg(original[index].basis.orthonormalized().get_rotation_quaternion().angle_to(compressed[index].basis.orthonormalized().get_rotation_quaternion())))
	_expect(max_palm_error <= 0.002, stance + " both palms retract together")
	_expect(max_wrist_angle <= 0.1, stance + " wrist orientations preserved")
	_expect(float(after["trigger_error_m"]) <= 0.01 and float(after["support_error_m"]) <= 0.01, stance + " compressed contacts")
	var lower_unchanged := true
	for track in base.get_track_count():
		var bone := String(base.track_get_path(track)).get_slice(":", 1)
		if _upper(bone):
			continue
		var other := animation.find_track(base.track_get_path(track), base.track_get_type(track))
		if other < 0 or base.track_get_key_count(track) != animation.track_get_key_count(other):
			lower_unchanged = false
			continue
		for key in base.track_get_key_count(track):
			lower_unchanged = lower_unchanged and base.track_get_key_value(track, key) == animation.track_get_key_value(other, key) and base.track_get_key_time(track, key) == animation.track_get_key_time(other, key)
	_expect(lower_unchanged, stance + " original lower-body tracks unchanged")
	if camera != null:
		# Persist the sampled one-shot result before the next rendered frame.
		skeleton.clear_bones_global_pose_override()
		for index in skeleton.get_bone_count():
			skeleton.set_bone_pose(index, compressed_locals[index])
		skeleton.force_update_all_bone_transforms()
		_aim_review_camera(camera, driver, player)
		await _capture(OUTPUT + "/" + stance + "_compressed.png")
	return {"source_clip": base_name, "native_bones": skeleton.get_bone_count(), "upper_rotation_tracks": count, "source_bore_error_deg": geometry["bore_error_deg"], "palm_retraction_error_m": max_palm_error, "wrist_rotation_delta_deg": max_wrist_angle, "trigger_error_m": after["trigger_error_m"], "support_error_m": after["support_error_m"], "lower_body_tracks_unchanged": lower_unchanged}

func _compose_pose(base: Animation, skeleton: Skeleton3D, local_poses: Array[Transform3D]) -> Animation:
	var result := base.duplicate() as Animation
	for index in skeleton.get_bone_count():
		var bone := skeleton.get_bone_name(index)
		if not _upper(bone):
			continue
		var path := NodePath(".:" + bone)
		var track := result.find_track(path, Animation.TYPE_ROTATION_3D)
		if track < 0:
			track = result.add_track(Animation.TYPE_ROTATION_3D)
			result.track_set_path(track, path)
		for key in range(result.track_get_key_count(track) - 1, -1, -1):
			result.track_remove_key(track, key)
		result.track_insert_key(track, 0.0, local_poses[index].basis.orthonormalized().get_rotation_quaternion())
	return result

func _upper(bone: String) -> bool:
	return bone.begins_with("mixamorig_") and not (bone.ends_with("Hips") or bone.ends_with("Root") or "Leg" in bone or "Foot" in bone or "Toe" in bone)

func _snapshot(skeleton: Skeleton3D) -> Array[Transform3D]:
	skeleton.force_update_all_bone_transforms()
	var result: Array[Transform3D] = []
	for index in skeleton.get_bone_count():
		result.append(skeleton.get_bone_global_pose(index))
	return result

func _locals(skeleton: Skeleton3D, globals: Array[Transform3D]) -> Array[Transform3D]:
	var result: Array[Transform3D] = []
	for index in skeleton.get_bone_count():
		var parent := skeleton.get_bone_parent(index)
		result.append(globals[parent].affine_inverse() * globals[index] if parent >= 0 else globals[index])
	return result

func _sample(skeleton: Skeleton3D, solver: Node) -> Dictionary:
	var result: Dictionary = {}
	for side in ["right", "left"]:
		var hand := skeleton.find_bone("mixamorig_" + ("Right" if side == "right" else "Left") + "Hand")
		var palm: Vector3 = solver.get(side + "_palm_anchor_local")
		result[side + "_palm"] = skeleton.global_transform * (skeleton.get_bone_global_pose(hand) * palm)
	result["trigger_error_m"] = Vector3(result["right_palm"]).distance_to((solver.get("trigger_socket") as Marker3D).global_position)
	result["support_error_m"] = Vector3(result["left_palm"]).distance_to((solver.get("support_socket") as Marker3D).global_position)
	return result
