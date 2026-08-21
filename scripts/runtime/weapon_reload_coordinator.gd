class_name SocomWeaponReloadCoordinator
extends Node

## Couples the visual reload take to the gameplay ammo commit. The playable
## scene asks for a reload; this coordinator owns completion and cancellation.

signal pending_changed(pending: bool)

var player: Node
var weapon_controller: Node
var pending: bool = false
var generation: int = 0


func configure(player_node: Node, controller: Node) -> void:
	player = player_node
	weapon_controller = controller


func request_reload() -> bool:
	if player == null or pending:
		return false
	var mannequin := player.get_node_or_null("Mannequin")
	var driver: Node = mannequin.get("production_animation") as Node if mannequin != null else null
	var played := (
		mannequin != null
		and driver != null
		and mannequin.has_method("play_operator_semantic_action_timed")
		and bool(mannequin.call(
			"play_operator_semantic_action_timed",
			&"reload",
			float(driver.call("weapon_reload_duration_seconds")),
			0.12
		))
	)
	if not played:
		return false
	_set_pending(true)
	generation += 1
	var request_generation := generation
	driver.action_completed.connect(
		_on_animation_completed.bind(request_generation),
		CONNECT_ONE_SHOT
	)
	driver.action_cancelled.connect(
		_on_animation_cancelled.bind(request_generation),
		CONNECT_ONE_SHOT
	)
	return true


func _on_animation_completed(clip_name: StringName, request_generation: int) -> void:
	if request_generation != generation or "reload" not in String(clip_name).to_lower():
		return
	_set_pending(false)
	if weapon_controller != null and weapon_controller.has_method("request_reload"):
		weapon_controller.call("request_reload")


func _on_animation_cancelled(clip_name: StringName, request_generation: int) -> void:
	if request_generation == generation and "reload" in String(clip_name).to_lower():
		_set_pending(false)


func _set_pending(value: bool) -> void:
	if pending == value:
		return
	pending = value
	pending_changed.emit(pending)
