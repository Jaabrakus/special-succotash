class_name SocomWeaponReloadCoordinator
extends Node

const AutoReloadPolicy := preload("res://scripts/weapons/weapon_auto_reload_policy.gd")

## Couples the visual reload take to the gameplay ammo commit. The playable
## scene asks for a reload; this coordinator owns completion and cancellation.

signal pending_changed(pending: bool)

var player: Node
var weapon_controller: Node
var pending: bool = false
var generation: int = 0
var animation_driver: Node
var completion_callback: Callable
var cancellation_callback: Callable
var auto_reload_waiting_for_safe_state: bool = false


func _ready() -> void:
	set_physics_process(false)


func configure(player_node: Node, controller: Node) -> void:
	if weapon_controller != null and weapon_controller.has_signal("ammo_changed"):
		var previous_callback := Callable(self, "_on_ammo_changed")
		if weapon_controller.is_connected("ammo_changed", previous_callback):
			weapon_controller.disconnect("ammo_changed", previous_callback)
	player = player_node
	weapon_controller = controller
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
	if not _player_allows_reload():
		_set_auto_reload_waiting(true)
		return
	_set_auto_reload_waiting(false)
	request_reload()


func _physics_process(_delta: float) -> void:
	if not auto_reload_waiting_for_safe_state or not _player_allows_reload():
		return
	_set_auto_reload_waiting(false)
	call_deferred("_request_auto_reload")


func request_reload() -> bool:
	if player == null or pending or not _player_allows_reload():
		return false
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
	_disconnect_driver_signals()
	animation_driver = driver
	completion_callback = _on_animation_completed.bind(request_generation)
	cancellation_callback = _on_animation_cancelled.bind(request_generation)
	driver.action_completed.connect(completion_callback, CONNECT_ONE_SHOT)
	driver.action_cancelled.connect(cancellation_callback, CONNECT_ONE_SHOT)
	return true


func _player_allows_reload() -> bool:
	var movement_state := &""
	if player.has_method("get_motion_state_name"):
		movement_state = StringName(player.call("get_motion_state_name"))
	if movement_state in [&"AIRBORNE", &"LANDING", &"DIVING", &"ROLLING"]:
		return false
	if player is CharacterBody3D and not (player as CharacterBody3D).is_on_floor():
		return false
	return true


func _set_auto_reload_waiting(value: bool) -> void:
	auto_reload_waiting_for_safe_state = value
	set_physics_process(value)


func _on_animation_completed(clip_name: StringName, request_generation: int) -> void:
	if request_generation != generation or "reload" not in String(clip_name).to_lower():
		return
	_disconnect_driver_signals()
	_set_pending(false)
	if weapon_controller != null and weapon_controller.has_method("request_reload"):
		weapon_controller.call("request_reload")


func _on_animation_cancelled(clip_name: StringName, request_generation: int) -> void:
	if request_generation == generation and "reload" in String(clip_name).to_lower():
		_disconnect_driver_signals()
		_set_pending(false)
		# An empty magazine still needs its approved automatic reload after an
		# airborne or mobility interruption. Retry now; unsafe movement states
		# queue the request until the operator is grounded.
		call_deferred("_request_auto_reload")


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
	animation_driver = null
	completion_callback = Callable()
	cancellation_callback = Callable()


func _set_pending(value: bool) -> void:
	if pending == value:
		return
	pending = value
	pending_changed.emit(pending)
