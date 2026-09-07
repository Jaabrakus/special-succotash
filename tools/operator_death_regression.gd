extends "res://tools/rifle_reference_visual_probe.gd"

const NetworkScene := preload("res://scenes/player/network_operator.tscn")
const Encoder := preload("res://scripts/network/socom_snapshot_encoder.gd")

func _run() -> void:
	output_prefix = "/private/tmp/operator_death_regression"
	scene = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	await _frames(60)
	player = scene.get_node("Player")
	driver = player.get_node("Mannequin/ProductionAnimation")
	controller = scene.get_node("WeaponController")
	_install_fixture()
	player.global_position = Vector3(500, 0.02, 500)
	player.set_local_input_enabled(false)
	await _frames(20)
	player.apply_damage(10.0)
	await _frames(3)
	_check(not driver.death_presentation_active, "Nonlethal damage does not play death")
	player.apply_damage(500.0)
	await _frames(8)
	_check(driver.death_presentation_active and driver.current_clip == &"death_right", "Zero health selects actual death animation")
	_check(player.get_node("Mannequin").visible, "Local corpse remains visible")
	_check(controller.request_fire().get("reason") == "DEAD", "Dead local player cannot fire")
	var origin := player.global_position
	player.request_jump()
	await _frames(10)
	_check(player.global_position.distance_to(origin) < 0.01, "Dead input cannot move player")
	if capture:
		await _capture_death()
	await _frames(235)
	var elapsed: float = driver.death_elapsed
	var skeleton: Skeleton3D = driver.skeleton
	var hips := skeleton.find_bone("mixamorig_Hips")
	var final_pose := skeleton.get_bone_pose_rotation(hips)
	await _frames(20)
	_check(is_equal_approx(elapsed, driver.death_elapsed), "Death playhead holds at final frame")
	_check(final_pose.angle_to(skeleton.get_bone_pose_rotation(hips)) < 0.01, "Final corpse pose is stable")
	var head := skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone("mixamorig_Head")).origin
	_check(head.y - player.global_position.y < 0.8, "Death visibly lowers body to floor")
	player.set_current_health(player.max_health)
	await _frames(20)
	_check(not driver.death_presentation_active and driver.current_clip != &"death_right", "Health restore releases death pose")
	for stance in [player.MotionState.CROUCHED, player.MotionState.PRONE]:
		player._try_set_posture(stance)
		await _frames(25)
		player.apply_damage(500.0)
		await _frames(10)
		var expected: StringName = &"death_kneel_back" if stance == player.MotionState.CROUCHED else &"death_right"
		_check(driver.current_clip == expected and driver.locomotion_graph.current_state == expected, "Stance death reaches full-body graph state %s" % expected)
		await _frames(235)
		var stance_head := skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone("mixamorig_Head")).origin
		_check(stance_head.y - player.global_position.y < 0.8, "Stance death finishes on floor %s" % expected)
		var held_pose := skeleton.get_bone_pose_rotation(hips)
		await _frames(20)
		_check(held_pose.angle_to(skeleton.get_bone_pose_rotation(hips)) < 0.01, "Stance death remains still %s" % expected)
		player.set_current_health(player.max_health)
		await _frames(20)
	var server := NetworkScene.instantiate() as SocomNetworkOperator
	scene.add_child(server)
	server.global_position = Vector3(510, 0.02, 500)
	server.set_local_input_enabled(false)
	var proxy := NetworkScene.instantiate() as SocomNetworkOperator
	scene.add_child(proxy)
	proxy.set_replica_mode(true)
	await _frames(20)
	var result := server.take_explosion_damage(500.0, server.global_position, 42)
	_check(result.get("eliminated", false) and not server.alive, "Server lethal damage owns elimination")
	for index in 20:
		var snapshot: Dictionary = Encoder.capture({2: server}, [2])[2]
		proxy.push_network_snapshot(snapshot.position, snapshot.yaw, snapshot.velocity, snapshot.posture, snapshot.health, snapshot.alive, float(index), snapshot.presentation)
		proxy.update_proxy_interpolation(float(index) + 0.2)
		await _frames(3)
	var proxy_driver = proxy.get_node("Mannequin/ProductionAnimation")
	_check(proxy.mannequin.visible and proxy_driver.death_presentation_active, "Dead network proxy shows corpse animation")
	_check(proxy_driver.death_elapsed > 0.5, "Repeated dead snapshots do not restart death")
	_check(server.collision_layer == 0, "Corpse keeps existing disabled collision")
	_check(server.hurtbox_rig != null and not server.hurtbox_rig.enabled, "Dead authoritative hurtboxes are disabled")
	server.respawn_at(Vector3(510, 0.02, 500))
	await _frames(12)
	_check(server.alive and server.mannequin.visible and not server.get_node("Mannequin/ProductionAnimation").death_presentation_active, "Respawn restores living presentation")
	server.deactivate_for_round()
	_check(not server.mannequin.visible, "Benched operator remains hidden")
	server.queue_free()
	proxy.queue_free()
	print("OPERATOR_DEATH_REGRESSION ", "PASS" if failures.is_empty() else "FAIL", " ", failures)
	_finish()

func _capture_death() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	root.size = Vector2i(960, 640)
	var folder := "res://art_source/operator_death"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	for frame in 120:
		await _frames(2)
		var focus := player.global_position + Vector3.UP * 0.8
		camera.global_position = focus + Vector3(3.5, 1.1, 3.2)
		camera.look_at(focus)
		camera.current = true
		RenderingServer.force_draw()
		var shot := root.get_texture().get_image()
		shot.resize(800, 500, Image.INTERPOLATE_LANCZOS)
		shot.save_png(folder + "/%03d.png" % frame)

func _check(value: bool, message: String) -> void:
	if not value and message not in failures:
		failures.append(message)
