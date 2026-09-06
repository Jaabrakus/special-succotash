extends RefCounted

# Synchronous equipment policy; state stays on the existing grenade runtime.
const SWITCH_HOLD_THRESHOLD := 0.25
const ACTIVE_RIFLE_READY_REFRESH_SECONDS := 0.35
const EQUIPMENT_SLOT_IDS: Array[StringName] = [
	&"primary", &"secondary", &"frag", &"flash", &"smoke", &"mission",
]

static func equip_or_cycle(runtime: Node) -> bool:
	var start_index: int = runtime.selected_type if not runtime.equipped else runtime.selected_type + 1
	for offset in 3:
		var candidate := (start_index + offset) % 3
		var key: String = ["frag", "flash", "smoke"][candidate]
		if int(runtime.inventory.get(key, 0)) <= 0:
			continue
		if not runtime.equipped:
			_capture_rifle_ready_state(runtime)
		runtime.selected_type = candidate
		runtime.equipped = true
		runtime.active_rifle_ready_latched = false
		runtime._update_held_grenade_visual()
		runtime._set_held_grenade_visible(true)
		# The grenade loadout owns the hands until the player returns to the rifle.
		# Do not reveal the hand-mounted rifle between throws; that transform still
		# contains the completed throw pose and makes the rifle float above the hand.
		runtime._set_rifle_visible(false)
		runtime._set_weapon_input(false)
		runtime._update_status()
		return true
	return_to_rifle(runtime)
	return false


static func equip_last_grenade(runtime: Node) -> bool:
	if equip_grenade_type(runtime, runtime.selected_type):
		return true
	for candidate in 3:
		if equip_grenade_type(runtime, candidate):
			return true
	return_to_rifle(runtime)
	return false


static func equip_grenade_type(runtime: Node, type_index: int) -> bool:
	var candidate := clampi(type_index, 0, 2)
	var key: String = ["frag", "flash", "smoke"][candidate]
	if int(runtime.inventory.get(key, 0)) <= 0:
		return false
	if not runtime.equipped:
		_capture_rifle_ready_state(runtime)
	runtime.selected_type = candidate
	runtime.equipped = true
	runtime.active_rifle_ready_latched = false
	runtime._update_held_grenade_visual()
	runtime._set_held_grenade_visible(true)
	runtime._set_rifle_visible(false)
	runtime._set_weapon_input(false)
	runtime._update_status()
	return true


static func return_to_rifle(runtime: Node, cancel_pending_throw: bool = true) -> void:
	_close_equipment_wheel_visual(runtime)
	if cancel_pending_throw:
		runtime.throw_generation += 1
		runtime.throw_in_progress = false
		runtime.throw_released = false
		runtime.throw_succeeded = false
		runtime._set_movement_locked(false)
		runtime._cancel_operator_action()
	runtime.equipped = false
	runtime.active_rifle_ready_latched = runtime.rifle_ready_before_grenade
	runtime.aim_active = false
	runtime.hold_seconds = 0.0
	runtime.pending_launch_state.clear()
	runtime._set_held_grenade_visible(false)
	if runtime.arc_preview != null:
		runtime.arc_preview.visible = false
	if runtime.charge_panel != null:
		runtime.charge_panel.visible = false
	runtime._set_weapon_input(true)
	runtime._set_rifle_visible(true)
	_restore_captured_rifle_ready_state(runtime)
	runtime._update_status()


static func equip_primary_quick(runtime: Node) -> bool:
	return equip_firearm_slot(runtime, "primary")


static func equip_firearm_slot(runtime: Node, slot: String) -> bool:
	if runtime.throw_in_progress:
		return false
	if runtime.weapon_controller == null or not runtime.weapon_controller.equip_carried_slot(slot):
		return false
	return_to_rifle(runtime)
	return true


static func open_equipment_wheel(runtime: Node) -> bool:
	if runtime.aim_active or runtime.throw_in_progress or runtime.equipment_wheel == null:
		return false
	runtime.wheel_selected_index = runtime.selected_type + 2 if runtime.equipped else 0
	if not _equipment_slot_enabled(runtime, runtime.wheel_selected_index):
		runtime.wheel_selected_index = _next_enabled_equipment_slot(runtime, runtime.wheel_selected_index, 1)
	runtime.equipment_wheel_open = true
	runtime._set_weapon_input(false)
	if runtime.camera_rig != null:
		runtime.camera_rig.orbit_input_enabled = false
	runtime.equipment_wheel.call(
		"show_wheel",
		_equipment_wheel_entries(runtime),
		runtime.wheel_selected_index
	)
	return true


static func cycle_equipment_wheel(runtime: Node, step: int) -> bool:
	if not runtime.equipment_wheel_open or step == 0:
		return false
	runtime.wheel_selected_index = _next_enabled_equipment_slot(runtime, 
		runtime.wheel_selected_index,
		1 if step > 0 else -1
	)
	runtime.equipment_wheel.call(
		"update_wheel",
		_equipment_wheel_entries(runtime),
		runtime.wheel_selected_index
	)
	return true


static func confirm_equipment_wheel(runtime: Node) -> bool:
	if not runtime.equipment_wheel_open:
		return false
	var selected_id := StringName(&"primary")
	if runtime.equipment_wheel != null and runtime.equipment_wheel.get("selected_index") != null:
		var entries_var: Variant = runtime.equipment_wheel.get("entries")
		if entries_var is Array:
			var entries: Array = entries_var as Array
			var s_idx: int = int(runtime.equipment_wheel.get("selected_index"))
			if s_idx >= 0 and s_idx < entries.size():
				selected_id = StringName(entries[s_idx].get("id", &"primary"))
	else:
		selected_id = EQUIPMENT_SLOT_IDS[clampi(runtime.wheel_selected_index, 0, EQUIPMENT_SLOT_IDS.size() - 1)]
	_close_equipment_wheel_visual(runtime)
	if selected_id in [&"primary", &"secondary"]:
		return equip_firearm_slot(runtime, String(selected_id))
	var grenade_index := [StringName(&"frag"), &"flash", &"smoke"].find(selected_id)
	if grenade_index >= 0:
		return equip_grenade_type(runtime, grenade_index)
	_restore_input_for_current_equipment(runtime)
	return false


static func cancel_equipment_wheel(runtime: Node) -> bool:
	if not runtime.equipment_wheel_open:
		return false
	_close_equipment_wheel_visual(runtime)
	_restore_input_for_current_equipment(runtime)
	return true


static func equipment_wheel_selection_id(runtime: Node) -> StringName:
	return EQUIPMENT_SLOT_IDS[clampi(runtime.wheel_selected_index, 0, EQUIPMENT_SLOT_IDS.size() - 1)]


static func handle_unhandled_input(runtime: Node, event: InputEvent) -> bool:
	if not runtime.equipment_wheel_open:
		return false
	if event.is_action_pressed("ui_cancel"):
		return cancel_equipment_wheel(runtime)
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			return cycle_equipment_wheel(runtime, 1)
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			return cycle_equipment_wheel(runtime, -1)
		if event.button_index == MOUSE_BUTTON_RIGHT:
			return cancel_equipment_wheel(runtime)
	return false


static func update_switch_input(runtime: Node, delta: float) -> void:
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED or OS.get_cmdline_user_args().has("--automated-test"):
		return
	update_switch_state(runtime, 
		delta,
		Input.is_action_pressed("equip_grenade"),
		Input.is_action_just_pressed("equip_grenade"),
		Input.is_action_just_released("equip_grenade")
	)


static func update_switch_state(runtime: Node, 
	delta: float,
	pressed: bool,
	just_pressed: bool,
	just_released: bool
) -> void:
	if just_pressed:
		runtime.switch_hold_seconds = 0.0
		runtime.switch_hold_triggered = false
	if pressed and not runtime.switch_hold_triggered:
		runtime.switch_hold_seconds += maxf(delta, 0.0)
		if runtime.switch_hold_seconds >= SWITCH_HOLD_THRESHOLD:
			runtime.switch_hold_triggered = open_equipment_wheel(runtime)
	if just_released:
		if runtime.equipment_wheel_open:
			confirm_equipment_wheel(runtime)
		elif not runtime.switch_hold_triggered:
			equip_last_grenade(runtime)
		runtime.switch_hold_seconds = 0.0
		runtime.switch_hold_triggered = false


static func _equipment_wheel_entries(runtime: Node) -> Array[Dictionary]:
	var rifle_name := "RIFLE"
	var pistol_name := "EMPTY"
	if runtime.weapon_controller != null:
		rifle_name = String(runtime.weapon_controller.carried_loadout.get("primary", "")).to_upper()
		pistol_name = String(runtime.weapon_controller.carried_loadout.get("secondary", "")).to_upper()
	return [
		{"id": &"primary", "label": rifle_name if not rifle_name.is_empty() else "EMPTY", "detail": "PRIMARY", "enabled": not rifle_name.is_empty()},
		{"id": &"secondary", "label": pistol_name if not pistol_name.is_empty() else "EMPTY", "detail": "PISTOL", "enabled": not pistol_name.is_empty()},
		{"id": &"frag", "label": "FRAG  x%d" % int(runtime.inventory.get("frag", 0)), "detail": "GRENADE", "enabled": int(runtime.inventory.get("frag", 0)) > 0},
		{"id": &"flash", "label": "FLASH  x%d" % int(runtime.inventory.get("flash", 0)), "detail": "GRENADE", "enabled": int(runtime.inventory.get("flash", 0)) > 0},
		{"id": &"smoke", "label": "SMOKE  x%d" % int(runtime.inventory.get("smoke", 0)), "detail": "GRENADE", "enabled": int(runtime.inventory.get("smoke", 0)) > 0},
		{"id": &"mission", "label": "AUTO", "detail": "MISSION", "enabled": false},
	]


static func _equipment_slot_enabled(runtime: Node, slot_index: int) -> bool:
	var entries := _equipment_wheel_entries(runtime)
	return bool(entries[clampi(slot_index, 0, entries.size() - 1)].get("enabled", false))


static func _next_enabled_equipment_slot(runtime: Node, from_index: int, direction: int) -> int:
	var index := from_index
	for _offset in EQUIPMENT_SLOT_IDS.size():
		index = wrapi(index + direction, 0, EQUIPMENT_SLOT_IDS.size())
		if _equipment_slot_enabled(runtime, index):
			return index
	return from_index


static func _close_equipment_wheel_visual(runtime: Node) -> void:
	runtime.equipment_wheel_open = false
	if runtime.camera_rig != null:
		runtime.camera_rig.orbit_input_enabled = true
	if runtime.equipment_wheel != null:
		runtime.equipment_wheel.call("hide_wheel")


static func _restore_input_for_current_equipment(runtime: Node) -> void:
	runtime._set_weapon_input(not runtime.equipped)
	runtime._set_rifle_visible(not runtime.equipped)
	runtime._set_held_grenade_visible(runtime.equipped and runtime.selected_count() > 0)


static func _capture_rifle_ready_state(runtime: Node) -> void:
	var driver: Node = runtime._operator_animation_driver()
	runtime.rifle_ready_before_grenade = (
		runtime.active_rifle_ready_latched
		or (
			driver != null
			and float(driver.get("_fire_ready_hold_remaining")) > 0.001
		)
	)


static func _restore_captured_rifle_ready_state(runtime: Node) -> void:
	runtime.active_rifle_ready_latched = runtime.rifle_ready_before_grenade
	var driver: Node = runtime._operator_animation_driver()
	if runtime.rifle_ready_before_grenade:
		_raise_active_rifle_immediately(runtime)
	elif driver != null:
		driver.set("_fire_ready_hold_remaining", 0.0)


static func _maintain_active_rifle_ready_presentation(runtime: Node) -> void:
	if not runtime.active_rifle_ready_latched or runtime.equipped or runtime.equipment_wheel_open or runtime.throw_in_progress:
		return
	var driver: Node = runtime._operator_animation_driver()
	if driver == null:
		return
	driver.set(
		"_fire_ready_hold_remaining",
		maxf(
			float(driver.get("_fire_ready_hold_remaining")),
			ACTIVE_RIFLE_READY_REFRESH_SECONDS
		)
	)


static func _raise_active_rifle_immediately(runtime: Node) -> void:
	var driver: Node = runtime._operator_animation_driver()
	if driver != null and driver.has_method("_trigger_fire_ready_aim"):
		driver.call("_trigger_fire_ready_aim")
