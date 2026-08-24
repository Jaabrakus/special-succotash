class_name SocomMainGrenadeRuntime
extends Node

const ScreenEffects := preload("res://scripts/tactical/tactical_screen_effects.gd")
const GrenadeThrower := preload("res://scripts/tactical/tactical_grenade_thrower.gd")
const SmokeGrenade := preload("res://scripts/tactical/smoke_grenade.gd")
const Flashbang := preload("res://scripts/tactical/flashbang_grenade.gd")
const FragGrenade := preload("res://scripts/tactical/frag_grenade.gd")
const Trajectory := preload("res://scripts/runtime/main_grenade_trajectory.gd")
const GrenadeProfile := preload("res://scripts/tactical/tactical_grenade_profile.gd")
const GRENADE_VISUAL_SCENES: Array[PackedScene] = [
	preload("res://assets/models/grenades/frag_west_cc0.glb"),
	preload("res://assets/models/grenades/flashbang_west_cc0.glb"),
	preload("res://assets/models/grenades/smoke_west_cc0.glb"),
]

const SWITCH_HOLD_THRESHOLD := 0.25
const HELD_GRENADE_VISUAL_SCALE := 0.55
const ACTIVE_RIFLE_READY_REFRESH_SECONDS := 0.35
const EQUIPMENT_SLOT_IDS: Array[StringName] = [
	&"primary", &"secondary", &"frag", &"flash", &"smoke", &"mission",
]

var host
var trajectory: SocomMainGrenadeTrajectory
var held_grenade_attachment: BoneAttachment3D
var held_grenade_mesh: Node3D
var pending_launch_state: Dictionary = {}
var wheel_selected_index := 0
var active_rifle_ready_latched := false

var player:
	get: return host.get("player")
var camera_rig:
	get: return host.get("camera_rig")
var weapon_controller:
	get: return host.get("weapon_controller")
var thrower:
	get: return host.get("tactical_grenade_thrower")
	set(value): host.set("tactical_grenade_thrower", value)
var arc_preview:
	get: return host.get("grenade_arc_preview")
	set(value): host.set("grenade_arc_preview", value)
var selected_type: int:
	get: return int(host.get("selected_grenade_type"))
	set(value): host.set("selected_grenade_type", value)
var equipped: bool:
	get: return bool(host.get("grenade_equipped"))
	set(value): host.set("grenade_equipped", value)
var aim_active: bool:
	get: return bool(host.get("grenade_aim_active"))
	set(value): host.set("grenade_aim_active", value)
var hold_seconds: float:
	get: return float(host.get("grenade_hold_seconds"))
	set(value): host.set("grenade_hold_seconds", value)
var underhand: bool:
	get: return bool(host.get("grenade_underhand"))
	set(value): host.set("grenade_underhand", value)
var throw_in_progress: bool:
	get: return bool(host.get("grenade_throw_in_progress"))
	set(value): host.set("grenade_throw_in_progress", value)
var throw_generation: int:
	get: return int(host.get("grenade_throw_generation"))
	set(value): host.set("grenade_throw_generation", value)
var throw_released: bool:
	get: return bool(host.get("grenade_throw_released"))
	set(value): host.set("grenade_throw_released", value)
var throw_succeeded: bool:
	get: return bool(host.get("grenade_throw_succeeded"))
	set(value): host.set("grenade_throw_succeeded", value)
var switch_hold_seconds: float:
	get: return float(host.get("grenade_switch_hold_seconds"))
	set(value): host.set("grenade_switch_hold_seconds", value)
var switch_hold_triggered: bool:
	get: return bool(host.get("grenade_switch_hold_triggered"))
	set(value): host.set("grenade_switch_hold_triggered", value)
var inventory: Dictionary:
	get: return host.get("grenade_inventory") as Dictionary
var charge_panel: PanelContainer:
	get: return host.get("grenade_charge_panel") as PanelContainer
var charge_bar: ProgressBar:
	get: return host.get("grenade_charge_bar") as ProgressBar
var charge_label: Label:
	get: return host.get("grenade_charge_label") as Label
var equipment_wheel: Control:
	get: return host.get("equipment_wheel") as Control
var equipment_wheel_open: bool:
	get: return bool(host.get("equipment_wheel_open"))
	set(value): host.set("equipment_wheel_open", value)


func configure(main_host: Node) -> void:
	host = main_host
	trajectory = Trajectory.new()
	trajectory.configure(host)


func build() -> void:
	var effects := ScreenEffects.new()
	effects.name = "TacticalScreenEffects"
	host.add_child(effects)
	host.set("tactical_screen_effects", effects)
	effects.bind_camera(camera_rig.camera)
	thrower = GrenadeThrower.new()
	thrower.name = "TacticalGrenadeThrower"
	host.add_child(thrower)
	arc_preview = trajectory.create_preview()
	_build_held_grenade_visual()


func _process(_delta: float) -> void:
	_maintain_active_rifle_ready_presentation()
	if (
		not throw_in_progress
		or throw_released
		or pending_launch_state.is_empty()
		or arc_preview == null
	):
		return
	var hand_origin := release_origin()
	if hand_origin.is_finite():
		pending_launch_state["origin"] = hand_origin
	trajectory.draw_launch_state(arc_preview, pending_launch_state, player)


func begin_aim() -> void:
	if thrower == null or camera_rig == null or not equipped or throw_in_progress or selected_count() <= 0:
		return
	aim_active = true
	pending_launch_state.clear()
	hold_seconds = 0.0
	underhand = Input.is_key_pressed(KEY_SHIFT)
	_set_held_grenade_visible(true)
	_set_weapon_input(false)
	if arc_preview != null:
		arc_preview.visible = true
	if charge_panel != null:
		charge_panel.visible = true
	refresh_aim_preview()


func update_aim(delta: float) -> void:
	if not aim_active:
		return
	hold_seconds = minf(
		hold_seconds + maxf(delta, 0.0),
		float(thrower.get("maximum_hold_seconds"))
	)
	underhand = Input.is_key_pressed(KEY_SHIFT)
	refresh_aim_preview()
	if hold_seconds >= float(thrower.get("maximum_hold_seconds")):
		release_aim()


func release_aim() -> void:
	if not aim_active:
		return
	var charge := float(thrower.call("charge_for_hold", hold_seconds))
	var release_underhand := underhand
	var release_hold_seconds := hold_seconds
	var launch_state := trajectory.build_launch_state(
		thrower,
		release_hold_seconds,
		release_underhand
	)
	aim_active = false
	pending_launch_state = launch_state
	if arc_preview != null:
		arc_preview.visible = true
	if charge_panel != null:
		charge_panel.visible = false
	throw_in_progress = true
	throw_released = false
	throw_succeeded = false
	throw_generation += 1
	var generation := throw_generation
	var driver := _play_throw_animation(
		release_underhand,
		_animation_speed_for_charge(charge)
	)
	_set_movement_locked(true)
	if driver == null:
		release_at_animation_cue(
			&"", generation, release_underhand, charge, release_hold_seconds, launch_state
		)
		complete_throw(&"", generation)
		return
	driver.action_release_cue.connect(
		release_at_animation_cue.bind(
			generation, release_underhand, charge, release_hold_seconds, launch_state
		),
		CONNECT_ONE_SHOT
	)
	driver.action_recovery_cue.connect(
		begin_throw_recovery.bind(generation),
		CONNECT_ONE_SHOT
	)
	driver.action_completed.connect(complete_throw.bind(generation), CONNECT_ONE_SHOT)


func release_at_animation_cue(
	_clip_name: StringName,
	generation: int,
	release_underhand: bool,
	charge: float,
	release_hold_seconds: float,
	launch_state: Dictionary
) -> void:
	if not throw_in_progress or generation != throw_generation or not equipped or throw_released:
		return
	var hand_origin := release_origin()
	if hand_origin.is_finite():
		launch_state["origin"] = hand_origin
		pending_launch_state["origin"] = hand_origin
	trajectory.draw_launch_state(arc_preview, launch_state, player)
	throw_released = true
	throw_succeeded = throw_selected(
		release_underhand,
		charge,
		release_hold_seconds,
		launch_state
	)
	if arc_preview != null:
		arc_preview.visible = false
	pending_launch_state.clear()
	_set_held_grenade_visible(not throw_succeeded and equipped)


func complete_throw(_clip_name: StringName, generation: int) -> void:
	if not throw_in_progress or generation != throw_generation:
		return
	throw_in_progress = false
	pending_launch_state.clear()
	_set_movement_locked(false)
	if throw_succeeded and selected_count() <= 0:
		equip_or_cycle()
	elif equipped:
		_set_weapon_input(false)
		_update_held_grenade_visual()
		_set_held_grenade_visible(selected_count() > 0)
	_update_status()


func begin_throw_recovery(_clip_name: StringName, generation: int) -> void:
	if not throw_in_progress or generation != throw_generation:
		return
	# The animation driver starts its locomotion crossfade at this cue. Keep the
	# authoritative body stationary until the action completes so the operator
	# cannot translate while the throw pose is still fading out. complete_throw()
	# restores input after the base locomotion route has regained visual control.


func cancel_for_jump() -> void:
	if not equipped and not throw_in_progress:
		return
	throw_generation += 1
	throw_in_progress = false
	throw_released = false
	throw_succeeded = false
	pending_launch_state.clear()
	_set_held_grenade_visible(false)
	_set_movement_locked(false)
	var mannequin := player.get_node_or_null("Mannequin") as Node if player != null else null
	if mannequin != null and mannequin.has_method("cancel_operator_grenade_action"):
		mannequin.call("cancel_operator_grenade_action")
	return_to_rifle(false)


func refresh_aim_preview() -> void:
	trajectory.refresh(
		arc_preview,
		thrower,
		hold_seconds,
		underhand,
		type_name(),
		selected_count(),
		charge_bar,
		charge_label
	)


func type_name() -> String:
	return ["FRAG", "FLASH", "SMOKE"][clampi(selected_type, 0, 2)]


func inventory_key() -> String:
	return ["frag", "flash", "smoke"][clampi(selected_type, 0, 2)]


func selected_count() -> int:
	return int(inventory.get(inventory_key(), 0))


func arc_origin() -> Vector3:
	return trajectory.arc_origin()


func release_origin() -> Vector3:
	return trajectory.release_origin()


func bone_world_position(bone_name: StringName) -> Vector3:
	return trajectory.bone_world_position(bone_name)


func equip_or_cycle() -> bool:
	var start_index := selected_type if not equipped else selected_type + 1
	for offset in 3:
		var candidate := (start_index + offset) % 3
		var key: String = ["frag", "flash", "smoke"][candidate]
		if int(inventory.get(key, 0)) <= 0:
			continue
		selected_type = candidate
		equipped = true
		active_rifle_ready_latched = false
		_update_held_grenade_visual()
		_set_held_grenade_visible(true)
		# The grenade loadout owns the hands until the player returns to the rifle.
		# Do not reveal the hand-mounted rifle between throws; that transform still
		# contains the completed throw pose and makes the rifle float above the hand.
		_set_rifle_visible(false)
		_set_weapon_input(false)
		_update_status()
		return true
	equipped = false
	active_rifle_ready_latched = true
	_set_held_grenade_visible(false)
	_cancel_operator_action()
	_set_rifle_visible(true)
	_set_weapon_input(true)
	_update_status()
	return false


func equip_last_grenade() -> bool:
	if equip_grenade_type(selected_type):
		return true
	for candidate in 3:
		if equip_grenade_type(candidate):
			return true
	return_to_rifle()
	return false


func equip_grenade_type(type_index: int) -> bool:
	var candidate := clampi(type_index, 0, 2)
	var key: String = ["frag", "flash", "smoke"][candidate]
	if int(inventory.get(key, 0)) <= 0:
		return false
	selected_type = candidate
	equipped = true
	active_rifle_ready_latched = false
	_update_held_grenade_visual()
	_set_held_grenade_visible(true)
	_set_rifle_visible(false)
	_set_weapon_input(false)
	_update_status()
	return true


func return_to_rifle(cancel_pending_throw: bool = true) -> void:
	_close_equipment_wheel_visual()
	if cancel_pending_throw:
		throw_generation += 1
		throw_in_progress = false
		throw_released = false
		throw_succeeded = false
		_set_movement_locked(false)
		_cancel_operator_action()
	equipped = false
	active_rifle_ready_latched = true
	aim_active = false
	hold_seconds = 0.0
	pending_launch_state.clear()
	_set_held_grenade_visible(false)
	if arc_preview != null:
		arc_preview.visible = false
	if charge_panel != null:
		charge_panel.visible = false
	_set_weapon_input(true)
	_set_rifle_visible(true)
	_raise_active_rifle_immediately()
	_update_status()


func equip_primary_quick() -> bool:
	if throw_in_progress:
		return false
	return_to_rifle()
	return true


func open_equipment_wheel() -> bool:
	if aim_active or throw_in_progress or equipment_wheel == null:
		return false
	wheel_selected_index = selected_type + 2 if equipped else 0
	if not _equipment_slot_enabled(wheel_selected_index):
		wheel_selected_index = _next_enabled_equipment_slot(wheel_selected_index, 1)
	equipment_wheel_open = true
	_set_weapon_input(false)
	equipment_wheel.call(
		"show_wheel",
		_equipment_wheel_entries(),
		wheel_selected_index
	)
	return true


func cycle_equipment_wheel(step: int) -> bool:
	if not equipment_wheel_open or step == 0:
		return false
	wheel_selected_index = _next_enabled_equipment_slot(
		wheel_selected_index,
		1 if step > 0 else -1
	)
	equipment_wheel.call(
		"update_wheel",
		_equipment_wheel_entries(),
		wheel_selected_index
	)
	return true


func confirm_equipment_wheel() -> bool:
	if not equipment_wheel_open:
		return false
	var selected_id := EQUIPMENT_SLOT_IDS[wheel_selected_index]
	_close_equipment_wheel_visual()
	if selected_id == &"primary":
		return_to_rifle()
		return true
	var grenade_index := [StringName(&"frag"), &"flash", &"smoke"].find(selected_id)
	if grenade_index >= 0:
		return equip_grenade_type(grenade_index)
	_restore_input_for_current_equipment()
	return false


func cancel_equipment_wheel() -> bool:
	if not equipment_wheel_open:
		return false
	_close_equipment_wheel_visual()
	_restore_input_for_current_equipment()
	return true


func equipment_wheel_selection_id() -> StringName:
	return EQUIPMENT_SLOT_IDS[clampi(wheel_selected_index, 0, EQUIPMENT_SLOT_IDS.size() - 1)]


func handle_unhandled_input(event: InputEvent) -> bool:
	if not equipment_wheel_open:
		return false
	if event.is_action_pressed("ui_cancel"):
		return cancel_equipment_wheel()
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			return cycle_equipment_wheel(1)
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			return cycle_equipment_wheel(-1)
		if event.button_index == MOUSE_BUTTON_RIGHT:
			return cancel_equipment_wheel()
	return false


func update_switch_input(delta: float) -> void:
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED or OS.get_cmdline_user_args().has("--automated-test"):
		return
	update_switch_state(
		delta,
		Input.is_action_pressed("equip_grenade"),
		Input.is_action_just_pressed("equip_grenade"),
		Input.is_action_just_released("equip_grenade")
	)


func update_switch_state(
	delta: float,
	pressed: bool,
	just_pressed: bool,
	just_released: bool
) -> void:
	if just_pressed:
		switch_hold_seconds = 0.0
		switch_hold_triggered = false
	if pressed and not switch_hold_triggered:
		switch_hold_seconds += maxf(delta, 0.0)
		if switch_hold_seconds >= SWITCH_HOLD_THRESHOLD:
			switch_hold_triggered = open_equipment_wheel()
	if just_released:
		if equipment_wheel_open:
			confirm_equipment_wheel()
		elif not switch_hold_triggered:
			equip_last_grenade()
		switch_hold_seconds = 0.0
		switch_hold_triggered = false


func _equipment_wheel_entries() -> Array[Dictionary]:
	var rifle_name := "RIFLE"
	if weapon_controller != null:
		rifle_name = String(weapon_controller.get("equipped_weapon_display_name")).to_upper()
	return [
		{"id": &"primary", "label": rifle_name, "detail": "PRIMARY", "enabled": true},
		{"id": &"secondary", "label": "EMPTY", "detail": "SECONDARY", "enabled": false},
		{"id": &"frag", "label": "FRAG  x%d" % int(inventory.get("frag", 0)), "detail": "GRENADE", "enabled": int(inventory.get("frag", 0)) > 0},
		{"id": &"flash", "label": "FLASH  x%d" % int(inventory.get("flash", 0)), "detail": "GRENADE", "enabled": int(inventory.get("flash", 0)) > 0},
		{"id": &"smoke", "label": "SMOKE  x%d" % int(inventory.get("smoke", 0)), "detail": "GRENADE", "enabled": int(inventory.get("smoke", 0)) > 0},
		{"id": &"mission", "label": "AUTO", "detail": "MISSION", "enabled": false},
	]


func _equipment_slot_enabled(slot_index: int) -> bool:
	var entries := _equipment_wheel_entries()
	return bool(entries[clampi(slot_index, 0, entries.size() - 1)].get("enabled", false))


func _next_enabled_equipment_slot(from_index: int, direction: int) -> int:
	var index := from_index
	for _offset in EQUIPMENT_SLOT_IDS.size():
		index = wrapi(index + direction, 0, EQUIPMENT_SLOT_IDS.size())
		if _equipment_slot_enabled(index):
			return index
	return from_index


func _close_equipment_wheel_visual() -> void:
	equipment_wheel_open = false
	if equipment_wheel != null:
		equipment_wheel.call("hide_wheel")


func _restore_input_for_current_equipment() -> void:
	_set_weapon_input(not equipped)
	_set_rifle_visible(not equipped)
	_set_held_grenade_visible(equipped and selected_count() > 0)
	if not equipped:
		active_rifle_ready_latched = true
		_raise_active_rifle_immediately()


func _maintain_active_rifle_ready_presentation() -> void:
	if not active_rifle_ready_latched or equipped or equipment_wheel_open or throw_in_progress:
		return
	var driver := _operator_animation_driver()
	if driver == null:
		return
	driver.set(
		"_fire_ready_hold_remaining",
		maxf(
			float(driver.get("_fire_ready_hold_remaining")),
			ACTIVE_RIFLE_READY_REFRESH_SECONDS
		)
	)


func _raise_active_rifle_immediately() -> void:
	var driver := _operator_animation_driver()
	if driver != null and driver.has_method("_trigger_fire_ready_aim"):
		driver.call("_trigger_fire_ready_aim")


func _operator_animation_driver() -> Node:
	var mannequin := player.get_node_or_null("Mannequin") as Node if player != null else null
	return mannequin.get("production_animation") as Node if mannequin != null else null


func throw_selected(
	release_underhand: bool,
	charge: float = 1.0,
	release_hold_seconds: float = 0.0,
	launch_state: Dictionary = {}
) -> bool:
	if thrower == null or camera_rig == null:
		return false
	var key := inventory_key()
	if int(inventory.get(key, 0)) <= 0:
		return false
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return false
	var grenade: RigidBody3D
	if selected_type == 0:
		grenade = FragGrenade.new()
	elif selected_type == 1:
		grenade = Flashbang.new()
	else:
		grenade = SmokeGrenade.new()
	grenade.configure_visual_scene(GRENADE_VISUAL_SCENES[selected_type])
	host.add_child(grenade)
	var resolved_launch := launch_state
	if resolved_launch.is_empty():
		resolved_launch = trajectory.build_launch_state(
			thrower,
			release_hold_seconds,
			release_underhand
		)
	if resolved_launch.is_empty():
		grenade.queue_free()
		return false
	var launch_origin: Vector3 = resolved_launch.get("origin", Vector3.ZERO)
	var launch_velocity: Vector3 = resolved_launch.get("velocity", Vector3.ZERO)
	grenade.global_position = launch_origin
	grenade.set_meta("authoritative_launch_origin", launch_origin)
	grenade.set_meta("authoritative_launch_velocity", launch_velocity)
	grenade.ignore_launch_body_temporarily(player)
	grenade.arm(thrower.remaining_fuse(grenade.fuse_seconds, release_hold_seconds))
	grenade.launch(launch_velocity)
	inventory[key] = maxi(0, int(inventory[key]) - 1)
	_update_status()
	return true


func _animation_speed_for_charge(charge: float) -> float:
	var throw_profile: Dictionary = GrenadeProfile.load_profile().get("throw", {})
	return lerpf(
		float(throw_profile.get("quick_throw_playback_speed", 2.05)),
		float(throw_profile.get("full_throw_playback_speed", 1.15)),
		clampf(charge, 0.0, 1.0)
	)


func _play_throw_animation(is_underhand: bool, playback_speed: float) -> Node:
	if player == null:
		return null
	var mannequin := player.get_node_or_null("Mannequin") as Node
	var played := (
		mannequin != null
		and mannequin.has_method("play_operator_semantic_action")
		and bool(mannequin.call(
			"play_operator_semantic_action",
			&"grenade_quick" if is_underhand else &"grenade_full",
			0.10,
			playback_speed
		))
	)
	return mannequin.get("production_animation") as Node if played else null


func _set_movement_locked(locked: bool) -> void:
	if player == null:
		return
	if player.has_method("set_local_input_enabled"):
		player.call("set_local_input_enabled", not locked)
	if locked and player is CharacterBody3D:
		player.velocity.x = 0.0
		player.velocity.z = 0.0


func _cancel_operator_action() -> void:
	var mannequin := player.get_node_or_null("Mannequin") as Node if player != null else null
	if mannequin != null and mannequin.has_method("cancel_operator_grenade_action"):
		mannequin.call("cancel_operator_grenade_action")


func _set_rifle_visible(enabled: bool) -> void:
	if player == null:
		return
	var mannequin := player.get_node_or_null("Mannequin") as Node
	if mannequin != null and mannequin.has_method("set_operator_weapon_visible"):
		mannequin.call("set_operator_weapon_visible", enabled)


func _set_weapon_input(enabled: bool) -> void:
	if weapon_controller != null and weapon_controller.has_method("set_input_enabled"):
		weapon_controller.call("set_input_enabled", enabled)


func _build_held_grenade_visual() -> void:
	if player == null:
		return
	var mannequin := player.get_node_or_null("Mannequin") as Node
	var driver: Node = mannequin.get("production_animation") as Node if mannequin != null else null
	var skeleton: Skeleton3D = driver.get("skeleton") as Skeleton3D if driver != null else null
	if skeleton == null:
		return
	held_grenade_attachment = BoneAttachment3D.new()
	held_grenade_attachment.name = "HeldGrenadeAttachment"
	held_grenade_attachment.bone_name = "mixamorig_RightHand"
	skeleton.add_child(held_grenade_attachment)
	# The imported operator skeleton carries a 64x bone scale. BoneAttachment3D
	# rewrites its own transform from the bone every frame, so its child must
	# cancel that scale while retaining the hand's animated position and rotation.
	var inherited_scale := held_grenade_attachment.global_basis.get_scale()
	var inverse_bone_scale := Vector3(
		1.0 / maxf(inherited_scale.x, 0.001),
		1.0 / maxf(inherited_scale.y, 0.001),
		1.0 / maxf(inherited_scale.z, 0.001)
	)
	held_grenade_mesh = Node3D.new()
	held_grenade_mesh.name = "HeldGrenadeVisual"
	held_grenade_mesh.scale = inverse_bone_scale
	held_grenade_mesh.position = Vector3(0.0, 0.012, -0.006) * inverse_bone_scale
	held_grenade_attachment.add_child(held_grenade_mesh)
	_update_held_grenade_visual()
	_set_held_grenade_visible(false)


func _update_held_grenade_visual() -> void:
	if held_grenade_mesh == null:
		return
	for child in held_grenade_mesh.get_children():
		child.queue_free()
	var visual := GRENADE_VISUAL_SCENES[selected_type].instantiate() as Node3D
	if visual == null:
		return
	visual.name = "TypeVisual"
	visual.scale = Vector3.ONE * HELD_GRENADE_VISUAL_SCALE
	held_grenade_mesh.add_child(visual)


func _set_held_grenade_visible(enabled: bool) -> void:
	if held_grenade_mesh != null:
		held_grenade_mesh.visible = enabled


func _update_status() -> void:
	host.call("_update_player_status_ui")
