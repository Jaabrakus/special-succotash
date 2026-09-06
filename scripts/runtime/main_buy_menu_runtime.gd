class_name SocomMainBuyMenuRuntime
extends Node

## Training-range driver for the two-slot equipment picker. Eligible firearms
## are available with no cash, window, or carry-weight enforcement.
## B opens the menu while the operator stands in the equipment zone at the
## range spawn; everywhere else B keeps toggling fire mode. The menu itself
## is a dumb view — this runtime owns input gating and performs the equip
## through the weapon controller's authorized pickup path.

const BuyMenuScript := preload("res://scripts/ui/socom_buy_menu.gd")
const Validator := preload("res://scripts/economy/socom_purchase_validator.gd")

const WEAPON_CONFIG_DIRECTORY := "res://config/weapons/"
const EQUIPMENT_ZONE_RADIUS := 8.0

var host
var buy_menu
var _layer: CanvasLayer
var _loadout: Dictionary = {"primary": "", "secondary": ""}
var _zone_center: Vector3 = Vector3.ZERO
var _zone_captured: bool = false
var _orbit_input_before_menu: bool = true
var _mouse_was_captured: bool = true


static func config_path_for(weapon_id: String) -> String:
	return WEAPON_CONFIG_DIRECTORY + weapon_id.to_lower().strip_edges() + ".json"


func configure(host_root) -> void:
	host = host_root
	_layer = CanvasLayer.new()
	_layer.layer = 150
	_layer.name = "BuyMenuLayer"
	add_child(_layer)
	buy_menu = BuyMenuScript.new()
	buy_menu.name = "BuyMenu"
	buy_menu.economy_enabled = false
	buy_menu.allow_training_prototypes = true
	_layer.add_child(buy_menu)
	buy_menu.purchase_requested.connect(_handle_purchase)
	buy_menu.close_requested.connect(close_menu)
	if host.player != null:
		_zone_center = host.player.global_position
		_zone_captured = true


func is_open() -> bool:
	return buy_menu != null and buy_menu.is_open()


## The free-issue menu owns B only in public Training Mode and only inside the
## equipment zone. Shared warm-up owns its own B context; live multiplayer
## keeps B for fire mode and does not allow equipment selection.
func handle_unhandled_input(event: InputEvent) -> bool:
	if buy_menu == null or host == null or not bool(host.get("public_training_mode")):
		return false
	if is_open():
		if (
			event.is_action_pressed(&"training_buy_menu")
			and not event.is_action_pressed(&"ui_cancel")
		):
			close_menu()
			return true
		return buy_menu.handle_unhandled_input(event)
	if event.is_action_pressed(&"training_buy_menu") and _player_in_zone():
		open_menu()
		return true
	return false


func open_menu() -> void:
	if buy_menu == null or is_open():
		return
	_mouse_was_captured = Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	if host.weapon_controller != null:
		host.weapon_controller.set_input_enabled(false)
	if host.camera_rig != null:
		_orbit_input_before_menu = host.camera_rig.orbit_input_enabled
		host.camera_rig.orbit_input_enabled = false
	_refresh_menu_state()
	buy_menu.open_menu()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func close_menu() -> void:
	if buy_menu == null or not is_open():
		return
	buy_menu.close_menu()
	if host.weapon_controller != null:
		host.weapon_controller.set_input_enabled(true)
	if host.camera_rig != null:
		host.camera_rig.orbit_input_enabled = _orbit_input_before_menu
	Input.mouse_mode = (
		Input.MOUSE_MODE_CAPTURED if _mouse_was_captured else Input.MOUSE_MODE_VISIBLE
	)


func _player_in_zone() -> bool:
	if not _zone_captured or host.player == null:
		return false
	return host.player.global_position.distance_to(_zone_center) <= EQUIPMENT_ZONE_RADIUS


func _refresh_menu_state() -> void:
	if buy_menu == null:
		return
	if host.weapon_controller != null:
		_loadout = host.weapon_controller.carried_loadout.duplicate()
	buy_menu.update_state(0, _loadout, 0.0, true)


func _handle_purchase(weapon_id: String) -> void:
	_refresh_menu_state()
	var context := {
		"cash": 0,
		"loadout": _loadout,
		"phase_open": true,
		"economy_enabled": false,
		"allow_training_prototypes": true,
	}
	var verdict: Dictionary = Validator.validate(weapon_id, context)
	if not bool(verdict.get("ok", false)):
		push_warning("Armory rejected selection of %s: %s" % [weapon_id, verdict.get("reason", "")])
		_refresh_menu_state()
		return
	var equipped := false
	if host.weapon_controller != null:
		equipped = host.weapon_controller.apply_authorized_weapon_pickup(
			config_path_for(weapon_id)
		)
	if not equipped:
		push_warning("Armory selection failed to equip %s" % weapon_id)
	_refresh_menu_state()
	if is_open() and equipped:
		close_menu()
