class_name SocomMainGrenadeRuntime
extends Node

const ScreenEffects := preload("res://scripts/tactical/tactical_screen_effects.gd")
const GrenadeThrower := preload("res://scripts/tactical/tactical_grenade_thrower.gd")
const SmokeGrenade := preload("res://scripts/tactical/smoke_grenade.gd")
const Flashbang := preload("res://scripts/tactical/flashbang_grenade.gd")
const FragGrenade := preload("res://scripts/tactical/frag_grenade.gd")
const Trajectory := preload("res://scripts/runtime/main_grenade_trajectory.gd")

const SHORT_THROW_PLAYBACK_SPEED := 1.85
const SWITCH_HOLD_THRESHOLD := 0.25

var host
var trajectory: SocomMainGrenadeTrajectory

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


func begin_aim() -> void:
	if thrower == null or camera_rig == null or not equipped or throw_in_progress or selected_count() <= 0:
		return
	aim_active = true
	hold_seconds = 0.0
	underhand = Input.is_key_pressed(KEY_SHIFT)
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
	aim_active = false
	if arc_preview != null:
		arc_preview.visible = false
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
			&"", generation, release_underhand, charge, release_hold_seconds
		)
		complete_throw(&"", generation)
		return
	driver.action_release_cue.connect(
		release_at_animation_cue.bind(
			generation, release_underhand, charge, release_hold_seconds
		),
		CONNECT_ONE_SHOT
	)
	driver.action_completed.connect(complete_throw.bind(generation), CONNECT_ONE_SHOT)


func release_at_animation_cue(
	_clip_name: StringName,
	generation: int,
	release_underhand: bool,
	charge: float,
	release_hold_seconds: float
) -> void:
	if not throw_in_progress or generation != throw_generation or not equipped or throw_released:
		return
	throw_released = true
	throw_succeeded = throw_selected(release_underhand, charge, release_hold_seconds)


func complete_throw(_clip_name: StringName, generation: int) -> void:
	if not throw_in_progress or generation != throw_generation:
		return
	throw_in_progress = false
	_set_movement_locked(false)
	if throw_succeeded and selected_count() <= 0:
		equip_or_cycle()
	elif equipped:
		_set_weapon_input(false)
	_update_status()


func cancel_for_jump() -> void:
	if not equipped and not throw_in_progress:
		return
	throw_generation += 1
	throw_in_progress = false
	throw_released = false
	throw_succeeded = false
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
		_set_rifle_visible(true)
		_set_weapon_input(false)
		_update_status()
		return true
	equipped = false
	_cancel_operator_action()
	_set_rifle_visible(true)
	_set_weapon_input(true)
	_update_status()
	return false


func return_to_rifle(cancel_pending_throw: bool = true) -> void:
	if cancel_pending_throw:
		throw_generation += 1
		throw_in_progress = false
		throw_released = false
		throw_succeeded = false
		_set_movement_locked(false)
		_cancel_operator_action()
	equipped = false
	aim_active = false
	hold_seconds = 0.0
	if arc_preview != null:
		arc_preview.visible = false
	if charge_panel != null:
		charge_panel.visible = false
	_set_weapon_input(true)
	_set_rifle_visible(true)
	_update_status()


func update_switch_input(delta: float) -> void:
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED or OS.get_cmdline_user_args().has("--automated-test"):
		return
	if Input.is_action_just_pressed("equip_grenade"):
		switch_hold_seconds = 0.0
		switch_hold_triggered = false
	if Input.is_action_pressed("equip_grenade") and not switch_hold_triggered:
		switch_hold_seconds += maxf(delta, 0.0)
		if switch_hold_seconds >= SWITCH_HOLD_THRESHOLD:
			switch_hold_triggered = true
			return_to_rifle()
	if Input.is_action_just_released("equip_grenade"):
		if not switch_hold_triggered:
			equip_or_cycle()
		switch_hold_seconds = 0.0
		switch_hold_triggered = false


func throw_selected(
	release_underhand: bool,
	charge: float = 1.0,
	release_hold_seconds: float = 0.0
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
	host.add_child(grenade)
	var forward: Vector3 = -camera_rig.camera.global_basis.z
	grenade.global_position = release_origin() + forward * 0.45
	var mode := (
		GrenadeThrower.ThrowMode.UNDERHAND
		if release_underhand
		else GrenadeThrower.ThrowMode.OVERHAND
	)
	grenade.arm(thrower.remaining_fuse(grenade.fuse_seconds, release_hold_seconds))
	grenade.launch(thrower.calculate_launch_velocity(forward, Vector3.UP, mode, charge))
	inventory[key] = maxi(0, int(inventory[key]) - 1)
	_update_status()
	return true


func _animation_speed_for_charge(charge: float) -> float:
	return lerpf(SHORT_THROW_PLAYBACK_SPEED, 1.0, clampf(charge, 0.0, 1.0))


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


func _update_status() -> void:
	host.call("_update_player_status_ui")
