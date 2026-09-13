extends SceneTree

const TrainingScene := preload("res://main.tscn")
const MapDocument := preload("res://scripts/maps/socom_map_document.gd")

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	MapDocument.library_directory_override = "/private/tmp/socom_public_training_maps_%s" % Time.get_ticks_usec()
	ProjectSettings.set_setting("socom/session/public_training", true)
	ProjectSettings.set_setting("socom/session/selected_map_document", MapDocument.new_document("Public Training Regression"))
	var training := TrainingScene.instantiate()
	root.add_child(training)
	var initial_player_position: Vector3 = training.get_node("Player").global_position
	for _frame in 6:
		await process_frame
	await physics_frame

	_expect(bool(training.get("public_training_mode")), "public Training Range mode is active")
	_expect(training.find_child("PublicTrainingRangeTitle", true, false) != null, "Training Range has player-facing identity")
	_expect(training.find_child("TrainingRangeMainMenuButton", true, false) is Button, "Training Range can return to the player menu")
	var hud_toggle_btn := training.find_child("TrainingRangeToggleHudButton", true, false) as Button
	_expect(hud_toggle_btn != null, "Training Range has toggle HUD button")
	_expect(hud_toggle_btn != null and hud_toggle_btn.text == "HIDE HUD", "HUD button shows HIDE HUD when HUD is visible")
	var status_hud := training.find_child("SocomLoadoutCardHUD", true, false) as Control
	var reticle := training.find_child("SocomDynamicReticle", true, false) as Control
	var gameplay_hud = training.get("gameplay_hud")
	_expect(gameplay_hud != null, "Training Range has gameplay HUD node")
	if gameplay_hud != null and hud_toggle_btn != null:
		var menu_btn := training.find_child("TrainingRangeMainMenuButton", true, false) as Button
		hud_toggle_btn.emit_signal("pressed")
		await process_frame
		_expect(hud_toggle_btn.text == "SHOW HUD", "HUD toggle button changes text to SHOW HUD")
		_expect(hud_toggle_btn != null and not hud_toggle_btn.visible, "HUD toggle button is hidden when HUD toggled off")
		_expect(menu_btn != null and not menu_btn.visible, "Main menu button is hidden when HUD toggled off")
		_expect(status_hud != null and not status_hud.visible, "Player status HUD is hidden when HUD toggled off")
		_expect(reticle != null and not reticle.visible, "Reticle is hidden when HUD toggled off")
		hud_toggle_btn.emit_signal("pressed")
		await process_frame
		_expect(hud_toggle_btn.text == "HIDE HUD", "HUD toggle button changes text back to HIDE HUD")
		_expect(hud_toggle_btn != null and hud_toggle_btn.visible, "HUD toggle button restored when HUD toggled on")
		_expect(menu_btn != null and menu_btn.visible, "Main menu button restored when HUD toggled on")
		_expect(status_hud != null and status_hud.visible, "Player status HUD restored when HUD toggled on")
		_expect(reticle != null and reticle.visible, "Reticle restored when HUD toggled on")

		var key_event := InputEventKey.new()
		key_event.pressed = true
		key_event.keycode = KEY_H
		gameplay_hud._unhandled_input(key_event)
		await process_frame
		_expect(not gameplay_hud.hud_mechanics_visible, "H key input toggles HUD mechanics off")
		_expect(status_hud != null and not status_hud.visible, "H key hides status HUD")
		_expect(reticle != null and not reticle.visible, "H key hides reticle")
		gameplay_hud._unhandled_input(key_event)
		await process_frame
		_expect(gameplay_hud.hud_mechanics_visible, "H key input toggles HUD mechanics back on")
		_expect(status_hud != null and status_hud.visible, "H key restores status HUD")
		_expect(reticle != null and reticle.visible, "H key restores reticle")
	_expect(status_hud != null, "Training Range keeps health, weapon ammo, and grenade inventory")
	_expect(status_hud != null and status_hud.is_visible_in_tree(), "Training Range HUD is visible during play")
	_expect(reticle != null, "Training Range keeps the gameplay reticle")
	_expect(reticle != null and reticle.is_visible_in_tree(), "Training Range reticle is visible during play")
	_expect(reticle != null and reticle.size.x > 0.0 and reticle.size.y > 0.0, "Training Range reticle covers the gameplay viewport")
	_expect(reticle != null and reticle.get_authoritative_center() != Vector2.ZERO, "Training Range reticle receives the live camera aim point")
	_expect(training.find_child("SocomControlsGuide", true, false) != null, "Training Range keeps player key-bind settings")
	_expect(training.get("weapon_controller") != null, "Training Range uses the canonical weapon controller")
	_expect(training.get("tactical_grenade_thrower") != null, "Training Range uses the canonical grenade system")
	_expect(InputMap.has_action(&"training_buy_menu"), "Training Range registers its context-owned buy action")
	var training_buy_bindings := InputMap.action_get_events(&"training_buy_menu")
	var training_buy_uses_b := false
	for event: InputEvent in training_buy_bindings:
		if event is InputEventKey and int((event as InputEventKey).physical_keycode) == KEY_B:
			training_buy_uses_b = true
			break
	_expect(
		training_buy_uses_b,
		"Training Range binds its free-loadout menu to B"
	)
	var buy_runtime = training.get("buy_menu_runtime")
	_expect(buy_runtime != null, "Training Range creates one free-loadout menu owner")
	if buy_runtime != null:
		var buy_event := InputEventAction.new()
		buy_event.action = &"training_buy_menu"
		buy_event.pressed = true
		_expect(
			bool(buy_runtime.handle_unhandled_input(buy_event)),
			"B is consumed by the Training Range equipment zone"
		)
		await process_frame
		_expect(bool(buy_runtime.is_open()), "B opens the Training Range free-loadout menu")
		_expect(
			bool(buy_runtime.handle_unhandled_input(buy_event)),
			"a second B press is consumed by the open Training Range menu"
		)
		await process_frame
		_expect(not bool(buy_runtime.is_open()), "a second B press closes the Training Range menu")
		buy_runtime.open_menu()
		buy_runtime.buy_menu.call("_submit", "mark_23")
		await process_frame
		_expect(
			String(training.get("weapon_controller").get("equipped_weapon_id")) == "mark_23",
			"a Training menu selection equips through the canonical weapon controller"
		)
	_expect((training.get("target_dummies") as Array).size() >= 3, "Training Range supplies shootable respawning dummies")
	var bomb_visuals: Array = training.get("training_bomb_visuals")
	_expect(not bomb_visuals.is_empty(), "Training Range exposes the authored demolition bomb")
	if not bomb_visuals.is_empty():
		var player := training.get_node_or_null("Player") as CharacterBody3D
		var bomb := bomb_visuals[0] as Node3D
		player.global_position = bomb.global_position
		Input.action_press(&"interact")
		await process_frame
		Input.action_release(&"interact")
		await process_frame
		_expect(bool(training.get("training_bomb_carried")), "F acquires the bomb in Training Range")
		_expect(not bomb.visible, "acquired Training Range bomb leaves the ground")
		var backpack := training.find_child("WearableBackpack", true, false) as Node3D
		_expect(backpack != null and backpack.visible, "acquired bomb appears as the operator backpack")
		var sites: Array = training.get("training_bomb_site_positions")
		_expect(not sites.is_empty(), "Training Range exposes authored demolition plant sites")
		if not sites.is_empty():
			player.global_position = Vector3(sites[0])
			training.set(
				"training_bomb_plant_progress",
				float(training.get("training_bomb_plant_seconds")) - 0.01
			)
			Input.action_press(&"interact")
			training.call("_update_training_bomb_pickup", 0.02)
			Input.action_release(&"interact")
			_expect(bool(training.get("training_bomb_planted")), "holding F plants the carried bomb")
			_expect(bomb.visible, "planted bomb appears at the authored target")
			_expect(backpack != null and not backpack.visible, "planting removes the bomb backpack")
	_expect(not bool(training.get("debug_hud_visible")), "public Training Range forces the debug HUD off")
	_expect(training.find_child("OperatorBodyStackOverlay", true, false) == null, "public Training Range does not create bone or hitbox overlays")
	_expect(training.find_child("CameraSpectatorPanel", true, false) == null, "public Training Range does not create the camera workbench")
	_expect(training.find_child("CameraTuningPanel", true, false) == null, "public Training Range does not create camera tuning")
	_expect(training.find_child("AnimationStudioPanel", true, false) == null, "public Training Range does not create Animation Studio")
	_expect(training.find_child("OperatorPoseTuner", true, false) == null, "public Training Range does not create the pose editor")

	if "--render" in OS.get_cmdline_user_args():
		training.get_node("Player").global_position = initial_player_position
		for frame in 90:
			await process_frame
		for channel in ["weapon", "health", "throwable"]:
			status_hud.attention.reveal(channel)
		await process_frame
		await RenderingServer.frame_post_draw
		_expect(status_hud._anchor_valid, "Floating HUD has a visible canonical torso anchor")
		root.get_texture().get_image().save_png("/private/tmp/contextual-hud-canonical.png")
	training.queue_free()
	await process_frame
	if failures.is_empty():
		print("PUBLIC_TRAINING_RANGE_REGRESSION PASS")
		quit(0)
		return
	for failure in failures:
		push_error("PUBLIC_TRAINING_RANGE_REGRESSION: %s" % failure)
	quit(1)


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("PUBLIC_TRAINING_CHECK PASS ", label)
	else:
		failures.append(label)
