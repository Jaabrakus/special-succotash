class_name SocomLoadoutCardHUD
extends Control

## Authentic SOCOM 2 Tactical Weapon & Loadout HUD Card
## Screen-facing status beside the local player's torso; never writes player state.
## Displays:
## - Active weapon / equipment name & slot type
## - High-visibility magazine and reserve ammunition counter
## - Interactive Fire Mode selector pips (AUTO / BURST / SEMI) with [B] hint
## - Tactical grenade inventory badges (Frag, Flash, Smoke)

const CARD_WIDTH := 340.0
const CARD_HEIGHT := 145.0

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
const Attention := preload("res://scripts/ui/contextual_hud_attention.gd")
var attention = Attention.new()
var _weapon_signature: Array = []
var _grenade_signature: Array = []
var _health_initialized := false
var _inventory_known := false
var _follow_player: Node3D
var _follow_collider: CollisionShape3D
var _follow_driver: Node
var _follow_skeleton: Skeleton3D
var _torso_bone_index := -1
var _floating_initialized := false
var _anchor_valid := true
var _actions_offset := Vector2(420.0, 0.0)
var _actions_position := Vector2.ZERO

func ammo_warning() -> String:
	if _weapon_signature.is_empty() or rounds_in_magazine > 0:
		return ""
	return "NO AMMO" if reserve_rounds <= 0 else "EMPTY — RELOAD"

func grenade_is_selected(kind: String) -> bool:
	return _inventory_known and active_grenade_name.to_lower() == kind.to_lower()

func grenade_tint(kind: String) -> Color:
	var selected := grenade_is_selected(kind)
	var tint := Color.from_string(String(attention.profile.get("selected_grenade_color", "#48aaff")), Color.DODGER_BLUE) if selected else Color("92999e")
	tint.a = attention.alpha("throwable", selected and is_grenade_active)
	if selected:
		tint.a = maxf(tint.a, float(attention.profile.get("selected_grenade_idle_alpha", 0.55)))
	elif int(grenade_inventory.get(kind, 0)) <= 0:
		tint.a *= 0.35
	return tint

func bind_player(target: Node3D) -> void:
	if target == _follow_player:
		return
	_follow_player = target
	_follow_collider = target.get_node_or_null("CollisionShape3D") as CollisionShape3D if is_instance_valid(target) else null
	_follow_driver = null
	_follow_skeleton = null
	_torso_bone_index = -1
	_floating_initialized = false

func _animated_torso_anchor(fallback: Vector3) -> Vector3:
	if not bool(attention.profile.get("follow_animated_torso", false)):
		return fallback
	if not is_instance_valid(_follow_driver):
		_follow_driver = _follow_player.get_node_or_null("Mannequin/ProductionAnimation")
	if not is_instance_valid(_follow_driver):
		return fallback
	var skeleton := _follow_driver.get("skeleton") as Skeleton3D
	if not is_instance_valid(skeleton):
		return fallback
	if skeleton != _follow_skeleton:
		_follow_skeleton = skeleton
		_torso_bone_index = skeleton.find_bone(String(attention.profile.get("torso_bone", "mixamorig_Spine2")))
	if _torso_bone_index < 0:
		return fallback
	# Read-only: a bone global pose is skeleton-local, not world space.
	return skeleton.global_transform * skeleton.get_bone_global_pose(_torso_bone_index).origin

func _update_floating_position(delta: float) -> void:
	if not bool(attention.profile.get("floating_enabled", false)):
		return
	var camera := get_viewport().get_camera_3d()
	_anchor_valid = is_instance_valid(_follow_player) and is_instance_valid(camera)
	if not _anchor_valid:
		return
	# Collision height follows stance without inheriting animation sway or bone jitter.
	var height := 1.85
	if is_instance_valid(_follow_collider) and _follow_collider.shape is CapsuleShape3D:
		height = _follow_collider.shape.height
	var torso := _follow_player.global_position + Vector3.UP * height * 0.8
	var posture := String(_follow_player.call("get_posture_name")) if _follow_player.has_method("get_posture_name") else "STANDING"
	var heights: Dictionary = attention.profile.get("stance_anchor_heights", {})
	# Read canonical stance, not a replicated collider that may still be standing.
	torso.y = _follow_player.global_position.y + float(heights.get(posture, height * 0.8))
	var stance_offsets: Dictionary = attention.profile.get("stance_offset_y", {})
	var offset_y := float(stance_offsets.get(posture, attention.profile.floating_offset_y))
	torso = _animated_torso_anchor(torso)
	if bool(attention.profile.get("follow_animated_torso", false)) and is_instance_valid(_follow_skeleton) and _torso_bone_index >= 0:
		# Use actual torso height during actions, not their eventual exit stance.
		var torso_height := torso.y - _follow_player.global_position.y
		var low := float(heights.get("PRONE", 0.38))
		var middle := float(heights.get("CROUCHED", 0.88))
		var high := float(heights.get("STANDING", 1.48))
		if torso_height < middle:
			offset_y = lerpf(float(stance_offsets.get("PRONE", -45.0)), float(stance_offsets.get("CROUCHED", -110.0)), clampf(inverse_lerp(low, middle, torso_height), 0.0, 1.0))
		else:
			offset_y = lerpf(float(stance_offsets.get("CROUCHED", -110.0)), float(stance_offsets.get("STANDING", -170.0)), clampf(inverse_lerp(middle, high, torso_height), 0.0, 1.0))
	_anchor_valid = not camera.is_position_behind(torso)
	if not _anchor_valid:
		return
	set_anchors_preset(PRESET_TOP_LEFT)
	scale = Vector2.ONE * float(attention.profile.get("floating_scale", 0.7))
	var desired := camera.unproject_position(torso) + Vector2(
		float(attention.profile.floating_offset_x), offset_y)
	var bounds := get_viewport_rect().size - size * scale - Vector2.ONE * 12.0
	desired = desired.clamp(Vector2.ONE * 12.0, bounds.max(Vector2.ONE * 12.0))
	position = position.lerp(desired, 1.0 - exp(-float(attention.profile.floating_follow_speed) * delta)) if _floating_initialized else desired
	var actions_desired := camera.unproject_position(torso) + Vector2(
		float(attention.profile.get("actions_offset_x", 130.0)), offset_y)
	actions_desired = actions_desired.clamp(Vector2.ONE * 12.0, bounds.max(Vector2.ONE * 12.0))
	_actions_position = _actions_position.lerp(actions_desired, 1.0 - exp(-float(attention.profile.floating_follow_speed) * delta)) if _floating_initialized else actions_desired
	_actions_offset = (_actions_position - position) / scale
	_floating_initialized = true

func _process(delta: float) -> void:
	attention.advance(delta)
	_update_floating_position(delta)
	queue_redraw()


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
	configured_burst_size: int = 3,
	magazine_capacity: int = 0
) -> void:
	var signature := [display_name, slot_name, magazine, reserve, fire_mode]
	if signature != _weapon_signature:
		attention.reveal("weapon")
		_weapon_signature = signature
	max_magazine = magazine_capacity
	weapon_display_name = display_name.to_upper()
	active_slot_label = slot_name.to_upper()
	rounds_in_magazine = magazine
	reserve_rounds = reserve
	current_fire_mode = fire_mode.to_lower()
	if not available_modes.is_empty():
		available_fire_modes = available_modes
	burst_size = clampi(configured_burst_size, 2, 3)
	queue_redraw()


func update_grenade_state(
	inventory: Dictionary,
	selected_name: String,
	grenade_equipped: bool
) -> void:
	var signature := [inventory.duplicate(true), selected_name, grenade_equipped]
	if signature != _grenade_signature:
		attention.reveal("throwable")
		_grenade_signature = signature
	_inventory_known = true
	grenade_inventory = inventory.duplicate(true)
	active_grenade_name = selected_name.to_upper()
	is_grenade_active = grenade_equipped
	if is_grenade_active:
		active_slot_label = "GRENADE"
		weapon_display_name = active_grenade_name
	queue_redraw()


func update_health(current: float, maximum: float) -> void:
	if not _health_initialized or not is_equal_approx(current, health_current):
		attention.reveal("health", float(attention.profile.health_hold_seconds))
	_health_initialized = true
	health_current = current
	health_max = maximum
	queue_redraw()


func _draw() -> void:
	if not visible or not _anchor_valid:
		return
	if bool(attention.profile.enabled):
		_draw_contextual()
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


func _draw_contextual() -> void:
	var font := ThemeDB.fallback_font
	var ratio := clampf(health_current / maxf(health_max, 1.0), 0.0, 1.0)
	var critical := ratio <= float(attention.profile.critical_health_ratio)
	var hp_color := Color("ff625a") if critical else Color("a4ed42")
	hp_color.a = attention.alpha("health", critical)
	var center := Vector2(60.0, 64.0)
	for index in 20:
		var angle := deg_to_rad(110.0 + index * 7.0)
		var tint := hp_color
		if float(index) / 20.0 >= ratio:
			tint.a *= 0.18
		draw_arc(center, float(attention.profile.get("health_radius", 50.0)), angle, angle + deg_to_rad(4.5), 4, tint, float(attention.profile.get("health_thickness", 5.0)), true)
	draw_string(font, Vector2(43, 128), "%d HP" % int(health_current), HORIZONTAL_ALIGNMENT_LEFT, -1, int(attention.profile.get("health_font_size", 22)), hp_color)
	# Incoming condition stays left; outgoing weapon/throwable activity stays right.
	draw_set_transform(_actions_offset)
	var warning := ammo_warning()
	var gun_color := Color(0.88, 0.96, 0.97, attention.alpha("weapon", not warning.is_empty()))
	if not warning.is_empty():
		gun_color = Color("ff625a")
	var gun_name := String(_weapon_signature[0]).to_upper() if not _weapon_signature.is_empty() else weapon_display_name
	draw_string(font, Vector2(67, 59), gun_name, HORIZONTAL_ALIGNMENT_LEFT, 205, 17, gun_color)
	var ammo_text := "%d  /  %d RDS" % [rounds_in_magazine, reserve_rounds]
	if max_magazine > 0:
		ammo_text = "%d  |  %d MAGS" % [rounds_in_magazine, reserve_rounds / max_magazine]
		if reserve_rounds % max_magazine != 0:
			ammo_text += " +%d" % (reserve_rounds % max_magazine)
	draw_string(font, Vector2(67, 87), ammo_text, HORIZONTAL_ALIGNMENT_LEFT, 270, int(attention.profile.get("ammo_font_size", 22)), gun_color)
	if not warning.is_empty():
		draw_string(font, Vector2(67, 112), warning, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, gun_color)
	if not _inventory_known:
		draw_set_transform(Vector2.ZERO)
		return # Never invent multiplayer throwable stock.
	for index in 3:
		var kind: String = ["frag", "flash", "smoke"][index]
		var tint := grenade_tint(kind)
		var count := int(grenade_inventory.get(kind, 0))
		var x := 75.0 + index * 50.0
		draw_rect(Rect2(x, 17, 9, 12), tint, false, 1.4)
		draw_line(Vector2(x + 3, 16), Vector2(x + 8, 16), tint, 2)
		draw_string(font, Vector2(x + 13, 29), "%d" % count, HORIZONTAL_ALIGNMENT_LEFT, -1, int(attention.profile.get("grenade_font_size", 18)), tint)
		draw_string(font, Vector2(x - 2, 40), kind.left(2).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 9, tint)
	draw_set_transform(Vector2.ZERO)
