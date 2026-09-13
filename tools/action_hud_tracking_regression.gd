extends "res://tools/jump_direction_combo_regression.gd"

var hud: Control

func _run() -> void:
	ProjectSettings.set_setting("socom/session/public_training", true)
	scene = load("res://main.tscn").instantiate()
	root.add_child(scene)
	await _frames(45)
	player = scene.get_node("Player")
	driver = player.get_node("Mannequin/ProductionAnimation")
	controller = scene.get_node("WeaponController")
	controller.set_input_enabled(false)
	hud = scene.gameplay_hud.loadout_card_hud
	_install_fixture()
	player.set_physics_process(false)
	player.set_local_input_enabled(false)
	player.automatic_vault_enabled = false
	await _reset_player()
	var neutral: Vector3 = hud._animated_torso_anchor(Vector3.ZERO) - player.global_position
	for side in [-1.0, 1.0]:
		for frame in 50:
			await physics_frame
			var command := Command.new()
			command.peek_axis = side
			player.queue_movement_command(command)
			player._physics_process(1.0 / 60.0)
			await process_frame
			if frame in [10, 30, 49]: await _sample_hud("lean_%s_%d" % [side, frame])
		var leaned: Vector3 = hud._animated_torso_anchor(Vector3.ZERO) - player.global_position
		_check(leaned.distance_to(neutral) > 0.04, "Lean moves the read-only torso anchor")
	for bit in [1, 2, 4, 8]:
		player.lean_latch.reset()
		player.peek_amount = 0.0
		await _reset_player()
		await _sequence(bit)
		_check(player.mobility_combo_kind == Intent.DIRECTIONS[bit], "Canonical mobility input selected %s; got %s" % [Intent.DIRECTIONS[bit], player.mobility_combo_kind])
		for frame in 70:
			await _tick()
			if frame in [10, 30, 60]: await _sample_hud("%s_%d" % [Intent.DIRECTIONS[bit], frame])
		for frame in 70:
			await _tick(1)
			if frame in [10, 40, 69]: await _sample_hud("recover_%d_%d" % [bit, frame])
	print("ACTION_HUD_TRACKING ", "PASS" if failures.is_empty() else "FAIL", " ", failures)
	scene.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

func _hide_canvas(_node: Node) -> void:
	# Unlike the inherited weapon-only fixture, this test must show the HUD.
	pass

func _sample_hud(label: String) -> void:
	var skeleton: Skeleton3D = driver.skeleton
	var bone := skeleton.find_bone("mixamorig_Spine2")
	var pose := skeleton.get_bone_global_pose(bone)
	var actor_transform := player.global_transform
	var view: Camera3D = root.get_camera_3d()
	var camera_transform := view.global_transform
	var target: Vector3 = hud._animated_torso_anchor(Vector3.ZERO)
	_check(target.distance_to(skeleton.global_transform * pose.origin) < 0.00001, "HUD reads animated torso " + label)
	hud._update_floating_position(1.0 / 60.0)
	_check(hud.rotation == 0 and hud._anchor_valid, "HUD remains upright and visible " + label)
	_check(hud.is_visible_in_tree(), "HUD is actually drawn " + label)
	_check(hud.position.x >= 12 and hud.position.y >= 12, "HUD inside viewport " + label)
	_check(player.global_transform == actor_transform and view.global_transform == camera_transform and skeleton.get_bone_global_pose(bone) == pose, "HUD does not write protected transforms " + label)
	if capture and label in ["lean_-1.0_49", "lean_1.0_49", "slide_30", "left_60", "right_30", "back_30"]:
		for channel in ["health", "weapon", "throwable"]: hud.attention.reveal(channel)
		hud.queue_redraw()
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/private/tmp/hud-action-%s.png" % label)
