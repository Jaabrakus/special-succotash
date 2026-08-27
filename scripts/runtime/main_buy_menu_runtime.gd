class_name SocomMainBuyMenuRuntime
extends Node

## Training-range driver for the buy menu. Free-issue sandbox: every catalog
## firearm is available with no cash, window, or carry-weight enforcement.
## P opens the menu anywhere in the Training Range. The menu itself
## is a dumb view — this runtime owns input gating and performs the equip
## through the weapon controller's authorized pickup path.

const BuyMenuScript := preload("res://scripts/ui/socom_buy_menu.gd")
const Validator := preload("res://scripts/economy/socom_purchase_validator.gd")

const WEAPON_CONFIG_DIRECTORY := "res://config/weapons/"
var host
var buy_menu
var _layer: CanvasLayer
var _loadout: Dictionary = {"primary": "", "secondary": ""}
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
	_layer.add_child(buy_menu)
	buy_menu.purchase_requested.connect(_handle_purchase)
	buy_menu.close_requested.connect(close_menu)


func is_open() -> bool:
	return buy_menu != null and buy_menu.is_open()


## Returns true when the event was consumed. Called first from the gameplay
## HUD's unhandled-input chain so the menu receives P before other overlays.
func handle_unhandled_input(event: InputEvent) -> bool:
	if buy_menu == null:
		return false
	if is_open():
		if event.is_action_pressed(&"open_buy_menu") and not event.is_action_pressed(&"ui_cancel"):
			close_menu()
			return true
		return buy_menu.handle_unhandled_input(event)
	if event.is_action_pressed(&"open_buy_menu"):
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


func _refresh_menu_state() -> void:
	if buy_menu == null:
		return
	buy_menu.update_state(0, _loadout, 0.0, true)


func _handle_purchase(weapon_id: String) -> void:
	var context := {
		"cash": 0,
		"loadout": _loadout,
		"phase_open": true,
		"economy_enabled": false,
	}
	var verdict: Dictionary = Validator.validate(weapon_id, context)
	if not bool(verdict.get("ok", false)):
		push_warning("Buy menu rejected free issue of %s: %s" % [weapon_id, verdict.get("reason", "")])
		_refresh_menu_state()
		return
	var applied: Dictionary = Validator.apply_purchase(
		weapon_id, _loadout, 0, false
	)
	_loadout = applied.get("loadout", _loadout)
	var equipped := false
	if host.weapon_controller != null:
		equipped = host.weapon_controller.apply_authorized_weapon_pickup(
			config_path_for(weapon_id)
		)
	if not equipped:
		push_warning("Buy menu free issue failed to equip %s" % weapon_id)
	_refresh_menu_state()
	if is_open() and equipped:
		close_menu()
