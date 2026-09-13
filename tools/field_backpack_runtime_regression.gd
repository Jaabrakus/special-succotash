extends SceneTree

var failures := 0

func _init() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error("FIELD_BACKPACK_RUNTIME FAIL " + message)
	else:
		print("FIELD_BACKPACK_RUNTIME PASS " + message)

func _run() -> void:
	ProjectSettings.set_setting("socom/playtest/use_active_bundle", false)
	ProjectSettings.set_setting("socom/session/selected_map_document", load("res://scripts/maps/socom_map_document.gd").load_path("res://config/maps/current_map.json"))
	ProjectSettings.set_setting("socom/session/public_training", true)
	ProjectSettings.set_setting("socom/session/tournament_mode", false)
	change_scene_to_file("res://main.tscn")
	await scene_changed
	await create_timer(0.2).timeout
	var player: Node3D = current_scene.get_node("Player")
	var pack: Node3D = current_scene.get_node("FieldBackpackPickup")
	check(player.global_position.distance_to(pack.spawn_position()) < 5, "pack is near current-map entry")
	player.set_physics_process(false)
	player.position = pack.spawn_position() + Vector3(0.7, 0.12, 0)
	await physics_frame
	await physics_frame
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if DisplayServer.get_name() == "headless":
		# Dummy display has no captured mouse; test the same command entry there.
		pack.interact()
	else:
		Input.action_press("interact")
		await process_frame
		await process_frame
		Input.action_release("interact")
	check(pack.holder_peer_id == 1 and is_instance_valid(pack.worn), "canonical main Interact command equips pack (%s)" % DisplayServer.get_name())
	if "--visual" in OS.get_cmdline_user_args():
		for i in 15:
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/private/tmp/field-backpack-game.png")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	change_scene_to_file("res://multiplayer_slice.tscn")
	await scene_changed
	await create_timer(0.2).timeout
	var session := current_scene
	check(session.host_match(0) == OK, "canonical multiplayer host starts")
	await create_timer(0.2).timeout
	# Session lifecycle owns actor spawn; use its existing RPC implementation.
	if not session.operators.has(1):
		session.spawn_operator(1, 0, Vector3(0, 0.12, 25))
	session.session_active = true
	player = session.operators[1]
	pack = session.get_node("FieldBackpackPickup")
	player.set_physics_process(false)
	player.position = pack.spawn_position() + Vector3(0.7, 0.12, 0)
	await physics_frame
	await physics_frame
	check(pack.try_pick_up(1, pack.revision, player.respawn_revision), "canonical multiplayer world permits nearby pickup")
	check(is_instance_valid(pack.worn) and not pack.ground.visible, "canonical network operator wears pack")
	session.call("_disconnect_existing_peer")
	await process_frame
	print("FIELD_BACKPACK_RUNTIME_REGRESSION %s failures=%d" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(0 if failures == 0 else 1)
