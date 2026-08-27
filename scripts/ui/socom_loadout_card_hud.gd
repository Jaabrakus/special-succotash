class_name SocomLoadoutCardHUD
extends Control

## Authentic SOCOM 2 Tactical Weapon & Loadout HUD Card
## Positioned in the bottom-right corner of the player viewport.
## Displays:
## - Active weapon / equipment name & slot type
## - High-visibility magazine and reserve ammunition counter
## - Interactive Fire Mode selector pips (AUTO / BURST / SEMI) with [B] hint
## - Tactical grenade inventory badges (Frag, Flash, Smoke)

const CARD_WIDTH := 280.0
const CARD_HEIGHT := 115.0

var weapon_display_name: String = "M16A2"
var active_slot_label: String = "PRIMARY"
var rounds_in_magazine: int = 30
var reserve_rounds: int = 120
var max_magazine: int = 30
var current_fire_mode: String = "auto"
var available_fire_modes: Array[String] = ["auto", "burst", "semi"]
var burst_size: int = 3

var is_grenade_active: bool = false
var grenade_inventory: Dictionary = {"frag": 2, "flash": 1, "smoke": 1}
var active_grenade_name: String = "FRAG"

var health_current: float = 100.0
var health_max: float = 100.0


func _ready() -> void:
	custom_minimum_size = Vector2(CARD_WIDTH, CARD_HEIGHT)
	mouse_filter = MOUSE_FILTER_IGNORE
	set_anchors_preset(PRESET_BOTTOM_RIGHT)
	offset_left = -CARD_WIDTH - 24.0
	offset_top = -CARD_HEIGHT - 24.0
	offset_right = -24.0
	offset_bottom = -24.0
	visible = true


func update_weapon_state(
	display_name: String,
	slot_name: String,
	magazine: int,
	reserve: int,
	fire_mode: String = "auto",
	available_modes: Array[String] = [],
	configured_burst_size: int = 3
) -> void:
	weapon_display_name = display_name.to_upper()
	active_slot_label = slot_name.to_upper()
	rounds_in_magazine = magazine
	reserve_rounds = reserve
	current_fire_mode = fire_mode.to_lower()
	if not available_modes.is_empty():
		available_fire_modes = available_modes
	burst_size = clampi(configured_burst_size, 2, 3)
	is_grenade_active = false
	queue_redraw()


func update_grenade_state(
	inventory: Dictionary,
	selected_name: String,
	grenade_equipped: bool
) -> void:
	grenade_inventory = inventory.duplicate(true)
	active_grenade_name = selected_name.to_upper()
	is_grenade_active = grenade_equipped
	if is_grenade_active:
		active_slot_label = "GRENADE"
		weapon_display_name = active_grenade_name
	queue_redraw()


func update_health(current: float, maximum: float) -> void:
	health_current = current
	health_max = maximum
	queue_redraw()


func _draw() -> void:
	if not visible:
		return

	var rect := Rect2(Vector2.ZERO, size)
	var font := ThemeDB.fallback_font

	# --- Background & Tactical Frame ---
	draw_rect(rect, Color(0.015, 0.022, 0.028, 0.88))
	draw_rect(rect, Color(0.25, 0.35, 0.38, 0.70), false, 1.5)

	# Subtle top header bar
	var header_rect := Rect2(0.0, 0.0, rect.size.x, 26.0)
	draw_rect(header_rect, Color(0.03, 0.05, 0.07, 0.94))
	draw_line(Vector2(0.0, 26.0), Vector2(rect.size.x, 26.0), Color("c8a66b"), 1.5)

	# Slot badge (PRIMARY / GRENADE)
	var slot_color := Color("f2cf6a") if is_grenade_active else Color("9df2cd")
	draw_string(font, Vector2(10.0, 18.0), active_slot_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, slot_color)

	# Fire Mode Indicator in top right of header
	if not is_grenade_active:
		var mode_label := ""
		match current_fire_mode:
			"auto":
				mode_label = "●●● AUTO"
			"burst":
				mode_label = "●●○ %d-BURST" % burst_size
			"semi":
				mode_label = "●○○ SEMI"
			_:
				mode_label = current_fire_mode.to_upper()

		var mode_text := "%s [B]" % mode_label
		draw_string(font, Vector2(rect.size.x - 110.0, 18.0), mode_text, HORIZONTAL_ALIGNMENT_RIGHT, 100.0, 11, Color("e3d3b3"))

	# --- Active Weapon / Equipment Name ---
	var name_color := Color("ffffff")
	draw_string(font, Vector2(12.0, 52.0), weapon_display_name, HORIZONTAL_ALIGNMENT_LEFT, 170.0, 18, name_color)

	# --- Ammunition Counter ---
	if not is_grenade_active:
		var mag_color := Color("a9f4c0")
		if rounds_in_magazine <= 5:
			mag_color = Color("ff6b6b") # Low ammo alert
		elif rounds_in_magazine <= 10:
			mag_color = Color("f2cf6a") # Caution

		var mag_str := "%d" % rounds_in_magazine
		var res_str := "/ %d" % reserve_rounds
		draw_string(font, Vector2(rect.size.x - 90.0, 55.0), mag_str, HORIZONTAL_ALIGNMENT_RIGHT, 40.0, 24, mag_color)
		draw_string(font, Vector2(rect.size.x - 46.0, 53.0), res_str, HORIZONTAL_ALIGNMENT_LEFT, 45.0, 14, Color("8fa09b"))
	else:
		var count_str := "x%d" % int(grenade_inventory.get(active_grenade_name.to_lower(), 0))
		draw_string(font, Vector2(rect.size.x - 70.0, 55.0), count_str, HORIZONTAL_ALIGNMENT_RIGHT, 60.0, 22, Color("f2cf6a"))

	# --- Grenade Inventory Bar at bottom ---
	var bottom_y := rect.size.y - 10.0
	draw_line(Vector2(8.0, rect.size.y - 24.0), Vector2(rect.size.x - 8.0, rect.size.y - 24.0), Color(0.20, 0.28, 0.32, 0.50), 1.0)

	var frag_cnt: int = int(grenade_inventory.get("frag", 0))
	var flash_cnt: int = int(grenade_inventory.get("flash", 0))
	var smoke_cnt: int = int(grenade_inventory.get("smoke", 0))

	var frag_col := Color("9df2cd") if frag_cnt > 0 else Color("535d5a")
	var flash_col := Color("9df2cd") if flash_cnt > 0 else Color("535d5a")
	var smoke_col := Color("9df2cd") if smoke_cnt > 0 else Color("535d5a")

	draw_string(font, Vector2(12.0, bottom_y), "FRAG %d" % frag_cnt, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, frag_col)
	draw_string(font, Vector2(85.0, bottom_y), "FLASH %d" % flash_cnt, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, flash_col)
	draw_string(font, Vector2(165.0, bottom_y), "SMOKE %d" % smoke_cnt, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, smoke_col)
	draw_string(font, Vector2(rect.size.x - 48.0, bottom_y), "[G]", HORIZONTAL_ALIGNMENT_RIGHT, 40.0, 10, Color("c8a66b"))
