class_name SocomBuyMenu
extends Control

## Pre-round buy menu over the reCOM weapon catalog. Dumb view only: it
## renders pushed state, emits purchase/close requests, and never equips
## weapons or mutates economy state itself. The host driver owns input
## gating and routes validated purchases to the weapon controller or the
## server authority.

signal purchase_requested(weapon_id: String)
signal close_requested

const Economy := preload("res://scripts/economy/socom_economy_rules.gd")
const Validator := preload("res://scripts/economy/socom_purchase_validator.gd")

const PALETTE_TITLE := Color("8bc5ae")
const PALETTE_GOLD := Color("f2cf6a")
const PALETTE_BRASS := Color("c8a66b")
const PALETTE_TEXT := Color("aeb9c9")
const PALETTE_DIM := Color("7f8b9c")
const PALETTE_READY := Color("70f59b")
const PALETTE_DENY := Color("ff7d76")
const PALETTE_PANEL := Color(0.015, 0.022, 0.028, 0.92)

var economy_enabled := true
var phase_open := true

var _overlay: Control
var _category_buttons: Dictionary = {}
var _row_container: VBoxContainer
var _detail_title: Label
var _detail_body: RichTextLabel
var _subtitle_label: Label
var _cash_label: Label
var _weight_label: Label
var _countdown_label: Label
var _status_label: Label

var _cash: int = 0
var _loadout: Dictionary = {"primary": "", "secondary": ""}
var _window_seconds_remaining: float = 0.0
var _selected_category: String = ""
var _selected_weapon_id: String = ""
var _category_order: Array = []
var _weapons_by_category: Dictionary = {}


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_build_ui()


func is_open() -> bool:
	return visible


## Pushed by the driver whenever menu-relevant state changes.
func update_state(
	cash: int,
	loadout: Dictionary,
	window_seconds_remaining: float,
	phase_is_open: bool
) -> void:
	_cash = cash
	_loadout = loadout
	_window_seconds_remaining = window_seconds_remaining
	phase_open = phase_is_open
	_refresh_footer()
	_refresh_rows()


func open_menu() -> void:
	visible = true
	_select_category(_selected_category if _category_buttons.has(_selected_category) else _category_order[0])


func close_menu() -> void:
	visible = false


func handle_unhandled_input(event: InputEvent) -> bool:
	if not visible:
		return false
	if event.is_action_pressed("ui_cancel"):
		close_requested.emit()
		return true
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		close_requested.emit()
		return true
	if event.is_action_pressed("ui_left") or event.is_action_pressed("ui_up"):
		_move_selection(-1)
		return true
	if event.is_action_pressed("ui_right") or event.is_action_pressed("ui_down"):
		_move_selection(1)
		return true
	if event.is_action_pressed("ui_accept"):
		_submit_selected()
		return true
	return false


func _build_ui() -> void:
	_overlay = Control.new()
	_overlay.name = "BuyMenuOverlay"
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_overlay)

	var dim := ColorRect.new()
	dim.color = Color(0.025, 0.035, 0.05, 0.82)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(980.0, 620.0)
	center.add_child(panel)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, 26)
	panel.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	margin.add_child(column)

	var title := Label.new()
	title.text = "ARMORY"
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", PALETTE_TITLE)
	column.add_child(title)

	var subtitle := Label.new()
	subtitle.name = "BuyMenuSubtitle"
	subtitle.add_theme_font_size_override("font_size", 13)
	subtitle.add_theme_color_override("font_color", PALETTE_DIM)
	column.add_child(subtitle)
	_subtitle_label = subtitle

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 18)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(body)

	body.add_child(_build_category_column())
	body.add_child(_build_list_column())
	body.add_child(_build_detail_column())

	column.add_child(HSeparator.new())
	column.add_child(_build_footer())


func _build_category_column() -> Control:
	var column := VBoxContainer.new()
	column.custom_minimum_size.x = 190.0
	column.add_theme_constant_override("separation", 6)

	var header := Label.new()
	header.text = "CATEGORY"
	header.add_theme_font_size_override("font_size", 12)
	header.add_theme_color_override("font_color", PALETTE_DIM)
	column.add_child(header)

	_category_order = Economy.firearm_categories()
	for category: Variant in _category_order:
		var button := Button.new()
		button.text = String(category).to_upper()
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.custom_minimum_size.y = 44.0
		button.add_theme_font_size_override("font_size", 14)
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(_select_category.bind(String(category)))
		_category_buttons[String(category)] = button
		column.add_child(button)
	return column


func _build_list_column() -> Control:
	var column := VBoxContainer.new()
	column.custom_minimum_size.x = 420.0
	column.add_theme_constant_override("separation", 6)

	var header := Label.new()
	header.text = "WEAPON"
	header.add_theme_font_size_override("font_size", 12)
	header.add_theme_color_override("font_color", PALETTE_DIM)
	column.add_child(header)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)

	_row_container = VBoxContainer.new()
	_row_container.add_theme_constant_override("separation", 4)
	_row_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_row_container)
	return column


func _build_detail_column() -> Control:
	var column := VBoxContainer.new()
	column.custom_minimum_size.x = 260.0
	column.add_theme_constant_override("separation", 8)

	var header := Label.new()
	header.text = "DETAIL"
	header.add_theme_font_size_override("font_size", 12)
	header.add_theme_color_override("font_color", PALETTE_DIM)
	column.add_child(header)

	_detail_title = Label.new()
	_detail_title.add_theme_font_size_override("font_size", 18)
	_detail_title.add_theme_color_override("font_color", PALETTE_GOLD)
	_detail_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_detail_title)

	_detail_body = RichTextLabel.new()
	_detail_body.bbcode_enabled = true
	_detail_body.fit_content = true
	_detail_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_detail_body.add_theme_font_size_override("normal_font_size", 13)
	_detail_body.add_theme_color_override("default_color", PALETTE_TEXT)
	column.add_child(_detail_body)

	_status_label = Label.new()
	_status_label.add_theme_font_size_override("font_size", 13)
	_status_label.add_theme_color_override("font_color", PALETTE_BRASS)
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_status_label)

	var confirm := Button.new()
	confirm.text = "CONFIRM PURCHASE"
	confirm.custom_minimum_size.y = 48.0
	confirm.add_theme_font_size_override("font_size", 16)
	confirm.pressed.connect(_submit_selected)
	column.add_child(confirm)

	var cancel := Button.new()
	cancel.text = "CLOSE  [ESC]"
	cancel.custom_minimum_size.y = 40.0
	cancel.add_theme_font_size_override("font_size", 14)
	cancel.pressed.connect(func(): close_requested.emit())
	column.add_child(cancel)
	return column


func _build_footer() -> Control:
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 32)

	_cash_label = Label.new()
	_cash_label.add_theme_font_size_override("font_size", 16)
	_cash_label.add_theme_color_override("font_color", PALETTE_GOLD)
	footer.add_child(_cash_label)

	_weight_label = Label.new()
	_weight_label.add_theme_font_size_override("font_size", 16)
	_weight_label.add_theme_color_override("font_color", PALETTE_TEXT)
	footer.add_child(_weight_label)

	_countdown_label = Label.new()
	_countdown_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_countdown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_countdown_label.add_theme_font_size_override("font_size", 16)
	_countdown_label.add_theme_color_override("font_color", PALETTE_READY)
	footer.add_child(_countdown_label)
	return footer


func _select_category(category: String) -> void:
	_selected_category = category
	for raw_category: Variant in _category_buttons:
		var button: Button = _category_buttons[raw_category]
		var selected := String(raw_category) == category
		button.add_theme_color_override(
			"font_color",
			PALETTE_GOLD if selected else PALETTE_TEXT
		)
	_refresh_rows()


func _refresh_rows() -> void:
	if _row_container == null or _selected_category.is_empty():
		return
	for child in _row_container.get_children():
		child.queue_free()

	var records: Array = Economy.weapons_for_category(_selected_category)
	_weapons_by_category[_selected_category] = records
	var index := 0
	var first_weapon_id := ""
	for raw_record: Variant in records:
		var record := raw_record as Dictionary
		var weapon_id := String(record.get("weapon_id", ""))
		if index == 0:
			first_weapon_id = weapon_id
		var row := _build_weapon_row(record)
		_row_container.add_child(row)
		index += 1
	if _selected_weapon_id.is_empty() or not _category_has_weapon(_selected_category, _selected_weapon_id):
		_selected_weapon_id = first_weapon_id
	_refresh_detail()


func _category_has_weapon(category: String, weapon_id: String) -> bool:
	for raw_record: Variant in _weapons_by_category.get(category, []):
		if String((raw_record as Dictionary).get("weapon_id", "")) == weapon_id:
			return true
	return false


func _build_weapon_row(record: Dictionary) -> Control:
	var weapon_id := String(record.get("weapon_id", ""))
	var verdict := Validator.validate(weapon_id, _validation_context())
	var slot := String(verdict.get("slot", ""))

	var button := Button.new()
	button.text = _row_label(record, verdict)
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.custom_minimum_size.y = 42.0
	button.add_theme_font_size_override("font_size", 14)
	button.focus_mode = Control.FOCUS_NONE
	button.disabled = not bool(verdict.get("ok", false))
	button.pressed.connect(func():
		_selected_weapon_id = weapon_id
		_refresh_detail()
		_submit(weapon_id)
	)
	if weapon_id == _selected_weapon_id:
		button.add_theme_color_override("font_color", PALETTE_GOLD)
	# The row press both selects and purchases (CS-style buy click). Selection
	# alone happens through keyboard navigation into the detail panel.
	return button


func _row_label(record: Dictionary, verdict: Dictionary) -> String:
	var weapon_id := String(record.get("weapon_id", ""))
	var name := String(record.get("display_name", weapon_id))
	var price := Economy.price_for(weapon_id)
	var weight := Economy.carry_weight_for(weapon_id)
	var slot_tag := "SIDEARM" if String(verdict.get("slot", "")) == "secondary" else "PRIMARY"
	if not economy_enabled:
		return "%s   [%s]" % [name, slot_tag]
	return "%s   %s  •  W%d  •  $%d" % [name, slot_tag, weight, price]


func _refresh_detail() -> void:
	if _detail_title == null or _selected_weapon_id.is_empty():
		return
	var record := Economy.weapon_record(_selected_weapon_id)
	if record.is_empty():
		return
	_detail_title.text = String(record.get("display_name", _selected_weapon_id))

	var ballistics: Dictionary = record.get("ballistics", {})
	var ammo: Dictionary = record.get("ammo_spec", {})
	var lines: Array[String] = []
	lines.append("[color=#c8a66b]CATEGORY[/color]  %s" % String(record.get("category", "")))
	lines.append(
		"[color=#c8a66b]FIRE MODE[/color]  %s" % " / ".join(
			(record.get("fire_modes", []) as Array).map(func(mode): return String(mode).to_upper())
		)
	)
	lines.append("[color=#c8a66b]DAMAGE[/color]  %d   [color=#c8a66b]RPM[/color]  %d" % [
		int(ballistics.get("damage", 0)),
		int(ballistics.get("fire_rate_rpm", 0)),
	])
	lines.append(
		"[color=#c8a66b]MAGAZINE[/color]  %d   [color=#c8a66b]RESERVE[/color]  %d" % [
			int(ballistics.get("magazine_capacity", 0)),
			int(ballistics.get("reserve_ammo", 0)),
		]
	)
	lines.append("[color=#c8a66b]RANGE[/color]  %d m" % int(ballistics.get("effective_range_m", 0)))
	if not ammo.is_empty():
		lines.append(
			"[color=#c8a66b]AMMO[/color]  %s" % String(ammo.get("type", ""))
		)
	lines.append("[color=#c8a66b]ENCUMBRANCE (SOCOM)[/color]  %d" % int(record.get("encumbrance", 0)))
	if bool(ballistics.get("is_silenced", false)):
		lines.append("[color=#70f59b]SUPPRESSED[/color]")
	_detail_body.clear()
	for line in lines:
		_detail_body.append_text(line + "\n")

	var verdict := Validator.validate(_selected_weapon_id, _validation_context())
	if bool(verdict.get("ok", false)):
		_status_label.add_theme_color_override("font_color", PALETTE_READY)
		_status_label.text = (
			"READY TO ISSUE"
			if not economy_enabled
			else "PURCHASE  •  $%d" % int(verdict.get("cost", 0))
		)
	else:
		_status_label.add_theme_color_override("font_color", PALETTE_DENY)
		_status_label.text = String(verdict.get("reason", "UNAVAILABLE"))


func _refresh_footer() -> void:
	if _cash_label == null:
		return
	if _subtitle_label != null:
		_subtitle_label.text = (
			"FREE ISSUE  •  TRAINING SANDBOX"
			if not economy_enabled
			else "Buy window open  •  purchases are validated by the server"
		)
	if economy_enabled:
		_cash_label.text = "CASH  $%d" % _cash
		_weight_label.text = "CARRY  %d / %d" % [
			Validator.loadout_carry_weight(_loadout),
			Economy.carry_weight_cap(),
		]
		var seconds := ceili(_window_seconds_remaining)
		_countdown_label.text = "BUY TIME  %ds" % maxi(0, seconds)
	else:
		_cash_label.text = ""
		_weight_label.text = "ALL WEAPONS AVAILABLE"
		_countdown_label.text = ""


func _validation_context() -> Dictionary:
	return {
		"cash": _cash,
		"loadout": _loadout,
		"phase_open": phase_open,
		"economy_enabled": economy_enabled,
	}


func _move_selection(step: int) -> void:
	var records: Array = _weapons_by_category.get(_selected_category, [])
	if records.is_empty():
		return
	var index := 0
	for i: int in records.size():
		if String((records[i] as Dictionary).get("weapon_id", "")) == _selected_weapon_id:
			index = i
			break
	var next_index := wrapi(index + step, 0, records.size())
	_selected_weapon_id = String((records[next_index] as Dictionary).get("weapon_id", ""))
	_refresh_detail()


func _submit_selected() -> void:
	if not _selected_weapon_id.is_empty():
		_submit(_selected_weapon_id)


func _submit(weapon_id: String) -> void:
	purchase_requested.emit(weapon_id)
