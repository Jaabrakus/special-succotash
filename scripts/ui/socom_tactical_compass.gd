class_name SocomTacticalCompass
extends Control

## Authentic SOCOM 2 Tactical Compass & Objective Navpoint HUD
## Ported from reCOM (zUI, CCompassAnchor, m_mpbomb_anchor)

@export var compass_width: float = 360.0
@export var compass_height: float = 32.0
@export var fov_degrees: float = 120.0 # Field of view visible on the tape
@export var primary_color := Color(0.91, 0.83, 0.31, 0.95) # Authentic SOCOM Yellow/Gold
@export var secondary_color := Color(0.70, 0.82, 0.90, 0.80)
@export var background_color := Color(0.08, 0.12, 0.15, 0.55)
@export var border_color := Color(0.25, 0.35, 0.42, 0.70)

var current_yaw_deg: float = 0.0
var current_player_position: Vector3 = Vector3.ZERO
var anchors: Dictionary = {} # id -> { "label": String, "world_pos": Vector3, "color": Color }

const CARDINALS: Dictionary = {
	0: "N",
	45: "NE",
	90: "E",
	135: "SE",
	180: "S",
	225: "SW",
	270: "W",
	315: "NW",
	360: "N",
}


func _ready() -> void:
	custom_minimum_size = Vector2(compass_width, compass_height)
	mouse_filter = MOUSE_FILTER_IGNORE
	_center_on_screen()
	if not get_viewport().size_changed.is_connected(_center_on_screen):
		get_viewport().size_changed.connect(_center_on_screen)


func _center_on_screen() -> void:
	var vp_size := get_viewport_rect().size
	position = Vector2((vp_size.x - compass_width) * 0.5, 14.0)
	size = Vector2(compass_width, compass_height)


func add_anchor(
	id: StringName,
	label: String,
	world_pos: Vector3,
	color: Color = Color("f4d34f"),
	group: StringName = &"default"
) -> void:
	anchors[id] = {
		"label": label,
		"world_pos": world_pos,
		"color": color,
		"group": group,
	}
	queue_redraw()


func remove_anchor(id: StringName) -> void:
	anchors.erase(id)
	queue_redraw()


func clear_anchor_group(group: StringName) -> void:
	for raw_id: Variant in anchors.keys():
		var anchor: Dictionary = anchors.get(raw_id, {})
		if StringName(anchor.get("group", &"default")) == group:
			anchors.erase(raw_id)
	queue_redraw()


func replace_anchor_group(group: StringName, entries: Array[Dictionary]) -> void:
	clear_anchor_group(group)
	for index in entries.size():
		var entry: Dictionary = entries[index]
		var id := StringName(entry.get("id", "%s_%d" % [group, index]))
		add_anchor(
			id,
			String(entry.get("label", "")),
			Vector3(entry.get("world_pos", Vector3.ZERO)),
			Color(entry.get("color", primary_color)),
			group
		)


func update_compass(camera_yaw_deg: float, player_pos: Vector3) -> void:
	# Normalize yaw to [0, 360)
	current_yaw_deg = fposmod(camera_yaw_deg, 360.0)
	current_player_position = player_pos
	queue_redraw()


func _draw() -> void:
	var half_w := compass_width * 0.5
	var center_x := half_w
	var rect := Rect2(0, 0, compass_width, compass_height)

	# Background and subtle frame
	draw_rect(rect, background_color, true)
	draw_rect(rect, border_color, false, 1.0)

	# Tape clipping bounds
	var px_per_deg := compass_width / fov_degrees
	var min_deg := current_yaw_deg - (fov_degrees * 0.5)
	var max_deg := current_yaw_deg + (fov_degrees * 0.5)

	# Draw degree ticks and cardinal labels
	var start_tick := int(floor(min_deg / 15.0)) * 15
	var end_tick := int(ceil(max_deg / 15.0)) * 15

	var font := ThemeDB.fallback_font
	var font_size := 11

	for tick in range(start_tick, end_tick + 1, 15):
		var normalized_tick := posmod(tick, 360)
		var x := center_x + (tick - current_yaw_deg) * px_per_deg
		if x < 4.0 or x > compass_width - 4.0:
			continue

		var is_cardinal: bool = CARDINALS.has(normalized_tick)
		var tick_len := 10.0 if is_cardinal else 5.0
		var tick_color := primary_color if is_cardinal else secondary_color

		draw_line(Vector2(x, compass_height - tick_len), Vector2(x, compass_height), tick_color, 1.2)

		if is_cardinal:
			var label_str: String = CARDINALS[normalized_tick]
			var str_size := font.get_string_size(label_str, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
			draw_string(font, Vector2(x - str_size.x * 0.5, compass_height - 12.0), label_str, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, primary_color)
		elif normalized_tick % 30 == 0:
			var num_str := "%d" % (normalized_tick / 10)
			var str_size := font.get_string_size(num_str, HORIZONTAL_ALIGNMENT_CENTER, -1, 9)
			draw_string(font, Vector2(x - str_size.x * 0.5, compass_height - 12.0), num_str, HORIZONTAL_ALIGNMENT_CENTER, -1, 9, secondary_color)

	# Draw Objective Anchors (e.g. Bomb Sites, dropped bomb)
	for id in anchors:
		var anchor: Dictionary = anchors[id]
		var world_pos: Vector3 = anchor.get("world_pos", Vector3.ZERO)
		var label: String = anchor.get("label", "")
		var color: Color = anchor.get("color", primary_color)

		var to_target := world_pos - current_player_position
		to_target.y = 0.0
		if to_target.length_squared() < 0.001:
			continue

		# Angle from player to target (in degrees, 0 = North / -Z, 90 = East / +X)
		var target_angle_deg := rad_to_deg(atan2(to_target.x, -to_target.z))
		target_angle_deg = fposmod(target_angle_deg, 360.0)

		# Angle difference relative to camera yaw
		var diff := target_angle_deg - current_yaw_deg
		while diff > 180.0: diff -= 360.0
		while diff < -180.0: diff += 360.0

		var marker_x := center_x + diff * px_per_deg
		marker_x = clampf(marker_x, 10.0, compass_width - 10.0)

		# Draw anchor indicator diamond / pip
		var marker_y := 8.0
		draw_circle(Vector2(marker_x, marker_y), 3.5, color)
		var dist_m := int(current_player_position.distance_to(world_pos))
		var anchor_text := "%s %dm" % [label, dist_m]
		var text_sz := font.get_string_size(anchor_text, HORIZONTAL_ALIGNMENT_CENTER, -1, 9)
		draw_string(font, Vector2(marker_x - text_sz.x * 0.5, marker_y + 12.0), anchor_text, HORIZONTAL_ALIGNMENT_CENTER, -1, 9, color)

	# Center indicator pip (▲)
	draw_line(Vector2(center_x, 0), Vector2(center_x, 8.0), primary_color, 2.0)
