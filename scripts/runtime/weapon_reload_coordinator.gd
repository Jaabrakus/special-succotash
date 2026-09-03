class_name SocomWeaponReloadCoordinator
extends Node

const AutoReloadPolicy := preload("res://scripts/weapons/weapon_auto_reload_policy.gd")

## Couples the visual reload take to the gameplay ammo commit. The playable
## scene asks for a reload; this coordinator owns completion and cancellation.

signal pending_changed(pending: bool)
signal reload_ammo_committed(request_generation: int)

var player: Node
var weapon_controller: Node
var pending: bool = false
var generation: int = 0
var animation_driver: Node
var completion_callback: Callable
var cancellation_callback: Callable
var commit_callback: Callable
var ammo_commit_attempted: bool = false
var ammo_committed: bool = false
var auto_reload_waiting_for_safe_state: bool = false


func _ready() -> void:
	set_physics_process(false)


func configure(player_node: Node, controller: Node) -> void:
	_disconnect_driver_signals()
	if weapon_controller != null and weapon_controller.has_method("set_reload_locked"):
		weapon_controller.call("set_reload_locked", false)
	if player != null and player.has_signal("mobility_action_started"):
		var previous_mobility_callback := Callable(self, "_on_mobility_action_started")
		if player.is_connected("mobility_action_started", previous_mobility_callback):
			player.disconnect("mobility_action_started", previous_mobility_callback)
	if player != null and player.has_signal("mobility_action_requested"):
		var previous_request_callback := Callable(self, "_on_mobility_action_requested")
		if player.is_connected("mobility_action_requested", previous_request_callback):
			player.disconnect("mobility_action_requested", previous_request_callback)
	if weapon_controller != null and weapon_controller.has_signal("ammo_changed"):
		var previous_callback := Callable(self, "_on_ammo_changed")
		if weapon_controller.is_connected("ammo_changed", previous_callback):
			weapon_controller.disconnect("ammo_changed", previous_callback)
	player = player_node
	weapon_controller = controller
	if weapon_controller != null and weapon_controller.has_method("set_reload_locked"):
		weapon_controller.call("set_reload_locked", false)
	if player != null and player.has_signal("mobility_action_started"):
		player.connect(
			"mobility_action_started",
			Callable(self, "_on_mobility_action_started")
		)
	if player != null and player.has_signal("mobility_action_requested"):
		player.connect(
			"mobility_action_requested",
			Callable(self, "_on_mobility_action_requested")
		)
	if player != null:
		player.set_meta("reload_action_pending", false)
	_set_auto_reload_waiting(false)
	if weapon_controller != null and weapon_controller.has_signal("ammo_changed"):
		weapon_controller.connect("ammo_changed", Callable(self, "_on_ammo_changed"))


func _on_ammo_changed(rounds_in_magazine: int, reserve_rounds: int) -> void:
	if AutoReloadPolicy.should_start(rounds_in_magazine, reserve_rounds, pending):
		call_deferred("_request_auto_reload")
	elif rounds_in_magazine > 0 or reserve_rounds <= 0:
		_set_auto_reload_waiting(false)


func _request_auto_reload() -> void:
	if weapon_controller == null or pending or not weapon_controller.has_method("get_ammo_snapshot"):
		_set_auto_reload_waiting(false)
		return
	var ammo: Dictionary = weapon_controller.call("get_ammo_snapshot")
	if not AutoReloadPolicy.should_start(
		int(ammo.get("rounds_in_magazine", 0)),
		int(ammo.get("reserve_ammo", 0)),
		pending
	):
		_set_auto_reload_waiting(false)
		return
	if not _player_allows_reload_start():
		_set_auto_reload_waiting(true)
		return
	_set_auto_reload_waiting(false)
	request_reload()


func _physics_process(_delta: float) -> void:
	if not auto_reload_waiting_for_safe_state or not _player_allows_reload_start():
		return
	_set_auto_reload_waiting(false)
	call_deferred("_request_auto_reload")


func _on_mobility_action_started(state_name: StringName) -> void:
	# Reload is an upper-body timeline. Movement never cancels it.
	pass


func _on_mobility_action_requested(state_name: StringName) -> void:
	# Reload is an upper-body timeline. Movement never cancels it.
	pass


func request_reload() -> bool:
	if player == null or pending or not _player_allows_reload_start():
		return false
	if player.has_method("play_socom_action") and player.get_node_or_null("Mannequin") == null:
		var played := bool(player.call("play_socom_action", &"reload"))
		if not played:
			return false
		_set_pending(true)
		generation += 1
		var request_generation := generation
		_begin_reload_transaction()
		var fallback_duration := 2.2
		get_tree().create_timer(fallback_duration * 0.76).timeout.connect(func():
			_commit_reload_ammo(request_generation)
		)
		get_tree().create_timer(2.2).timeout.connect(func():
			if pending and generation == request_generation:
				_commit_reload_ammo(request_generation)
				_set_pending(false)
		)
		return true
	var mannequin := player.get_node_or_null("Mannequin")
	var driver: Node = mannequin.get("production_animation") as Node if mannequin != null else null
	var plan: Dictionary = {}
	if driver != null and driver.has_method("present_event"):
		plan = driver.call(
			"present_event",
			&"RELOAD_STARTED",
			{
				"target_duration_seconds": float(
					driver.call("weapon_reload_duration_seconds")
				),
			}
		)
	var played := bool(plan.get("applied", false))
	if not played:
		return false
	_set_pending(true)
	generation += 1
	var request_generation := generation
	_begin_reload_transaction()
	_disconnect_driver_signals()
	animation_driver = driver
	completion_callback = _on_animation_completed.bind(request_generation)
	cancellation_callback = _on_animation_cancelled.bind(request_generation)
	driver.action_completed.connect(completion_callback, CONNECT_ONE_SHOT)
	driver.action_cancelled.connect(cancellation_callback, CONNECT_ONE_SHOT)
	if driver.has_signal("reload_commit_cue"):
		commit_callback = _on_reload_commit_cue.bind(request_generation)
		driver.connect("reload_commit_cue", commit_callback, CONNECT_ONE_SHOT)
	return true


func cancel_for_fire() -> bool:
	if (
		not pending
		or weapon_controller == null
		or not weapon_controller.has_method("get_ammo_snapshot")
	):
		return false
	var ammo: Dictionary = weapon_controller.call("get_ammo_snapshot")
	if int(ammo.get("rounds_in_magazine", 0)) <= 0:
		return false
	if animation_driver != null and animation_driver.has_method("cancel_reload_action"):
		var cancelled := bool(animation_driver.call("cancel_reload_action"))
		return cancelled and not pending
	# In the legacy fallback path, advance the generation so its timers cannot
	# commit ammunition after the fire interruption.
	generation += 1
	_disconnect_driver_signals()
	_set_pending(false)
	return true


func _player_allows_reload_continuation() -> bool:
	return true


func _player_allows_reload_start() -> bool:
	if not _player_allows_reload_continuation():
		return false
	var movement_state := &""
	if player.has_method("get_motion_state_name"):
		movement_state = StringName(player.call("get_motion_state_name"))
	if movement_state in [&"AIRBORNE", &"LANDING"]:
		return false
	return not (player is CharacterBody3D) or (player as CharacterBody3D).is_on_floor()


func _set_auto_reload_waiting(value: bool) -> void:
	auto_reload_waiting_for_safe_state = value
	_refresh_physics_process()


func _on_animation_completed(clip_name: StringName, request_generation: int) -> void:
	if request_generation != generation or "reload" not in String(clip_name).to_lower():
		return
	# Older drivers have no magazine-in cue. Completion remains a safe fallback,
	# but a cue-aware driver has already committed exactly once.
	_commit_reload_ammo(request_generation)
	_disconnect_driver_signals()
	_set_pending(false)


func _on_animation_cancelled(clip_name: StringName, request_generation: int) -> void:
	if request_generation == generation and "reload" in String(clip_name).to_lower():
		_disconnect_driver_signals()
		_set_pending(false)
		# Empty-magazine reloads cannot be cancelled by fire. This deferred check
		# remains as a safe fallback for explicit external cancellations.
		call_deferred("_request_auto_reload")


func _on_reload_commit_cue(clip_name: StringName, request_generation: int) -> void:
	if request_generation != generation or "reload" not in String(clip_name).to_lower():
		return
	_commit_reload_ammo(request_generation)


func _begin_reload_transaction() -> void:
	ammo_commit_attempted = false
	ammo_committed = false


func _commit_reload_ammo(request_generation: int) -> bool:
	if (
		request_generation != generation
		or not pending
		or ammo_commit_attempted
	):
		return ammo_committed
	ammo_commit_attempted = true
	if weapon_controller == null or not weapon_controller.has_method("request_reload"):
		return false
	ammo_committed = bool(weapon_controller.call("request_reload"))
	if ammo_committed:
		reload_ammo_committed.emit(request_generation)
	return ammo_committed


func _disconnect_driver_signals() -> void:
	# CONNECT_ONE_SHOT removes only the callback whose signal fired. A completed
	# reload used to leave its cancellation callback behind (and vice versa), so
	# every later reload accumulated another connection and flooded the runtime.
	if animation_driver != null:
		if (
			completion_callback.is_valid()
			and animation_driver.action_completed.is_connected(completion_callback)
		):
			animation_driver.action_completed.disconnect(completion_callback)
		if (
			cancellation_callback.is_valid()
			and animation_driver.action_cancelled.is_connected(cancellation_callback)
		):
			animation_driver.action_cancelled.disconnect(cancellation_callback)
		if (
			commit_callback.is_valid()
			and animation_driver.is_connected("reload_commit_cue", commit_callback)
		):
			animation_driver.disconnect("reload_commit_cue", commit_callback)
	animation_driver = null
	completion_callback = Callable()
	cancellation_callback = Callable()
	commit_callback = Callable()


func _set_pending(value: bool) -> void:
	if pending == value:
		return
	pending = value
	if player != null:
		player.set_meta("reload_action_pending", pending)
	if weapon_controller != null and weapon_controller.has_method("set_reload_locked"):
		weapon_controller.call("set_reload_locked", pending)
	_refresh_physics_process()
	pending_changed.emit(pending)


func _refresh_physics_process() -> void:
	set_physics_process(pending or auto_reload_waiting_for_safe_state)
