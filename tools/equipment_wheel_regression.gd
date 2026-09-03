extends SceneTree

const MAIN_SCENE := preload("res://main.tscn")

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var main := MAIN_SCENE.instantiate()
	root.add_child(main)
	for _frame in 12:
		await process_frame
	var runtime: Node = main.get("grenade_runtime") as Node
	var wheel: Control = main.get("equipment_wheel") as Control
	var weapon_controller: Node = main.get("weapon_controller") as Node
	var camera_rig: Node = main.get("camera_rig") as Node
	var mannequin: Node = main.get("player").get_node_or_null("Mannequin") as Node
	var driver: Node = mannequin.get("production_animation") as Node if mannequin != null else null
	var rifle: Node3D = driver.get("weapon_node") as Node3D if driver != null else null
	if driver != null:
		driver.set("_fire_ready_hold_remaining", 0.0)
	var yaw_before := float(camera_rig.get("yaw"))
	var inventory_before := (main.get("grenade_inventory") as Dictionary).duplicate(true)

	_expect(_action_has_key(&"equip_primary", KEY_1), "1 quick-selects the primary weapon")
	_expect(_action_has_key(&"equip_grenade", KEY_G), "G owns tap and hold equipment selection")
	_expect(wheel != null and not wheel.visible, "the equipment wheel starts hidden")

	_expect(bool(runtime.call("open_equipment_wheel")), "holding G opens the equipment wheel")
	_expect(
		bool(main.get("equipment_wheel_open"))
		and wheel.visible
		and StringName(runtime.call("equipment_wheel_selection_id")) == &"primary"
		and not bool(weapon_controller.get("input_enabled")),
		"the wheel opens on the active rifle without allowing a shot"
	)

	var wheel_down := InputEventMouseButton.new()
	wheel_down.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel_down.pressed = true
	_expect(bool(runtime.call("handle_unhandled_input", wheel_down)), "scroll is consumed while G is held")
	_expect(
		StringName(runtime.call("equipment_wheel_selection_id")) == &"frag",
		"scroll skips the unavailable secondary slot"
	)
	_expect(bool(runtime.call("cycle_equipment_wheel", 1)), "a second scroll advances the wheel")
	_expect(
		StringName(runtime.call("equipment_wheel_selection_id")) == &"flash",
		"the next available grenade is highlighted"
	)
	_expect(bool(runtime.call("confirm_equipment_wheel")), "releasing G confirms the highlighted item")
	_expect(
		bool(main.get("grenade_equipped"))
		and int(main.get("selected_grenade_type")) == 1
		and not wheel.visible,
		"wheel confirmation equips Flash and closes the overlay"
	)

	_expect(bool(runtime.call("equip_last_grenade")), "tap G re-equips the last-used grenade")
	_expect(
		int(main.get("selected_grenade_type")) == 1,
		"repeated tap G does not cycle away from the last-used grenade"
	)

	_expect(bool(runtime.call("open_equipment_wheel")), "the wheel reopens from a grenade")
	var right_click := InputEventMouseButton.new()
	right_click.button_index = MOUSE_BUTTON_RIGHT
	right_click.pressed = true
	_expect(bool(runtime.call("handle_unhandled_input", right_click)), "right mouse cancels the wheel")
	_expect(
		bool(main.get("grenade_equipped"))
		and int(main.get("selected_grenade_type")) == 1
		and not wheel.visible,
		"cancel preserves the previously equipped grenade"
	)

	_expect(bool(runtime.call("open_equipment_wheel")), "the wheel opens for rifle selection")
	while StringName(runtime.call("equipment_wheel_selection_id")) != &"primary":
		runtime.call("cycle_equipment_wheel", -1)
	_expect(bool(runtime.call("confirm_equipment_wheel")), "the primary slot confirms")
	_expect(
		not bool(main.get("grenade_equipped"))
		and bool(weapon_controller.get("input_enabled"))
		and rifle != null
		and rifle.visible,
		"primary confirmation restores the rendered rifle and weapon input"
	)
	for _frame in 90:
		await process_frame
	var camera: Camera3D = camera_rig.get("camera") as Camera3D
	var rifle_screen := camera.unproject_position(rifle.global_position)
	var viewport_size := main.get_viewport().get_visible_rect().size
	_expect(
		rifle.visible
		and not camera.is_position_behind(rifle.global_position)
		and rifle_screen.x >= 0.0
		and rifle_screen.x <= viewport_size.x
		and rifle_screen.y >= 0.0
		and rifle_screen.y <= viewport_size.y,
		"the restored rifle remains inside the playable viewport after settling"
	)
	_expect(
		not bool(runtime.get("active_rifle_ready_latched"))
		and driver != null
		and float(driver.get("_fire_ready_hold_remaining")) <= 0.001,
		"grenade return restores relaxed rifle state instead of forcing Aim Idle"
	)
	_expect(
		(main.get("grenade_inventory") as Dictionary) == inventory_before,
		"equipment selection never consumes a grenade"
	)
	_expect(
		is_equal_approx(float(camera_rig.get("yaw")), yaw_before),
		"equipment selection does not modify camera yaw"
	)

	runtime.call("update_switch_state", 0.26, true, true, false)
	_expect(
		bool(main.get("equipment_wheel_open")),
		"holding G past the threshold opens the wheel"
	)
	runtime.call("cycle_equipment_wheel", 1)
	runtime.call("update_switch_state", 0.0, false, false, true)
	_expect(
		not bool(main.get("equipment_wheel_open"))
		and bool(main.get("grenade_equipped"))
		and int(main.get("selected_grenade_type")) == 0,
		"releasing G equips the highlighted Frag"
	)
	runtime.call("return_to_rifle")
	runtime.call("update_switch_state", 0.05, true, true, false)
	runtime.call("update_switch_state", 0.0, false, false, true)
	_expect(
		bool(main.get("grenade_equipped"))
		and int(main.get("selected_grenade_type")) == 0
		and not bool(main.get("equipment_wheel_open")),
		"a quick G tap equips the last grenade without opening the wheel"
	)
	main.set("grenade_throw_in_progress", true)
	_expect(
		not bool(main.call("_return_to_primary_weapon"))
		and bool(main.get("grenade_equipped")),
		"primary quick-select cannot cancel a committed grenade throw"
	)
	main.set("grenade_throw_in_progress", false)
	_expect(
		bool(main.call("_return_to_primary_weapon"))
		and rifle != null
		and rifle.visible,
		"primary quick-select restores the rendered rifle after grenade use"
	)
	main.queue_free()
	await process_frame
	if failures.is_empty():
		print("EQUIPMENT_WHEEL_REGRESSION PASS")
		quit(0)
		return
	for failure in failures:
		push_error("EQUIPMENT_WHEEL_REGRESSION: %s" % failure)
	quit(1)


func _action_has_key(action: StringName, keycode: Key) -> bool:
	if not InputMap.has_action(action):
		return false
	for event in InputMap.action_get_events(action):
		if event is InputEventKey and event.physical_keycode == keycode:
			return true
	return false


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("EQUIPMENT_WHEEL_CHECK PASS ", label)
	else:
		failures.append(label)
