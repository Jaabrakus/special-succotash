extends Control

signal state_selected(slot_name: String)
signal clip_dropped_on_state(entry: Dictionary, slot_name: String)
signal candidate_selected(entry: Dictionary)

const GROUP_ORDER := [
	"STANDING LOCOMOTION",
	"CROUCH",
	"PRONE",
	"MOBILITY",
	"COMBAT",
	"TRANSITIONS",
]
const NODE_HEIGHT := 42.0
const NODE_GAP := 7.0
const GROUP_GAP := 18.0

var state_slots: Dictionary = {}
var selected_slot: String = ""
var node_rects: Dictionary = {}
var group_rects: Dictionary = {}
var candidate_entries: Array[Dictionary] = []
var candidate_rects: Dictionary = {}
var candidate_group_rect := Rect2()
var hovered_slot: String = ""
var drag_active: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size.x = 390.0


func set_state_data(slots: Dictionary, selected: String, candidates: Array = []) -> void:
	state_slots = slots.duplicate(true)
	selected_slot = selected
	candidate_entries.clear()
	for raw_candidate in candidates:
		if raw_candidate is Dictionary:
			candidate_entries.append((raw_candidate as Dictionary).duplicate(true))
	_rebuild_layout()
	queue_redraw()


func _rebuild_layout() -> void:
	node_rects.clear()
	group_rects.clear()
	candidate_rects.clear()
	candidate_group_rect = Rect2()
	var grouped: Dictionary = {}
	for group_name in GROUP_ORDER:
		grouped[group_name] = []
	var slot_names: Array = state_slots.keys()
	slot_names.sort()
	for raw_slot in slot_names:
		var slot_name := str(raw_slot)
		grouped[_group_for_slot(slot_name)].append(slot_name)

	var y := 80.0
	if not candidate_entries.is_empty():
		var candidate_top := y
		for index in range(candidate_entries.size()):
			candidate_rects[index] = Rect2(158.0, y, 222.0, NODE_HEIGHT)
			y += NODE_HEIGHT + NODE_GAP
		candidate_group_rect = Rect2(14.0, candidate_top, 122.0, maxf(NODE_HEIGHT, y - NODE_GAP - candidate_top))
		y += GROUP_GAP
	for group_name in GROUP_ORDER:
		var slots: Array = grouped[group_name]
		if slots.is_empty():
			continue
		var group_top := y
		for slot_name in slots:
			node_rects[slot_name] = Rect2(158.0, y, 222.0, NODE_HEIGHT)
			y += NODE_HEIGHT + NODE_GAP
		var group_bottom := y - NODE_GAP
		group_rects[group_name] = Rect2(14.0, group_top, 122.0, maxf(NODE_HEIGHT, group_bottom - group_top))
		y += GROUP_GAP
	custom_minimum_size.y = y + 20.0
	size.y = custom_minimum_size.y


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.035, 0.05, 0.065, 0.96), true)
	var font := ThemeDB.fallback_font
	var root_rect := Rect2(96.0, 14.0, 205.0, 42.0)
	_draw_card(root_rect, "OPERATOR ANIMATION", "approved runtime routes", Color(0.13, 0.58, 0.43), font)
	if drag_active:
		var drag_banner := Rect2(14.0, 60.0, 366.0, 20.0)
		draw_rect(drag_banner, Color(0.03, 0.16, 0.20, 0.98), true)
		draw_rect(drag_banner, Color(0.2, 0.9, 1.0), false, 2.0)
		draw_string(font, drag_banner.position + Vector2(8.0, 14.0), "VALID TARGETS GLOW CYAN — RELEASE ON A STATE CARD", HORIZONTAL_ALIGNMENT_CENTER, drag_banner.size.x - 16.0, 10, Color(0.55, 0.95, 1.0))
	var spine_x := 28.0
	if not group_rects.is_empty():
		var last_group: Rect2 = group_rects.values()[-1]
		draw_line(Vector2(spine_x, root_rect.end.y), Vector2(spine_x, last_group.get_center().y), Color(0.2, 0.75, 0.9, 0.7), 2.0)
	draw_line(Vector2(root_rect.get_center().x, root_rect.end.y), Vector2(spine_x, root_rect.end.y), Color(0.2, 0.75, 0.9, 0.7), 2.0)
	if not candidate_group_rect.size.is_zero_approx():
		var candidate_center := Vector2(candidate_group_rect.position.x, candidate_group_rect.get_center().y)
		draw_line(Vector2(spine_x, candidate_center.y), candidate_center, Color(0.72, 0.38, 1.0, 0.8), 2.0)
		var candidate_header := Rect2(candidate_group_rect.position.x, candidate_group_rect.get_center().y - 18.0, candidate_group_rect.size.x, 36.0)
		draw_rect(candidate_header, Color(0.18, 0.08, 0.24), true)
		draw_rect(candidate_header, Color(0.72, 0.38, 1.0), false, 1.5)
		draw_string(font, candidate_header.position + Vector2(7.0, 22.0), "HIGHLIGHTED", HORIZONTAL_ALIGNMENT_LEFT, candidate_header.size.x - 12.0, 10, Color(0.9, 0.75, 1.0))
		for index in range(candidate_entries.size()):
			var entry: Dictionary = candidate_entries[index]
			var candidate_rect: Rect2 = candidate_rects[index]
			draw_line(candidate_header.end - Vector2(0.0, candidate_header.size.y * 0.5), Vector2(candidate_rect.position.x, candidate_rect.get_center().y), Color(0.72, 0.38, 1.0, 0.6), 1.5)
			var suggestion := str(entry.get("suggested_slot", ""))
			var subtitle := "proposal — choose state" if suggestion.is_empty() else "suggest → %s" % suggestion
			_draw_card(candidate_rect, str(entry.get("display", "Animation clip")), subtitle, Color(0.72, 0.38, 1.0), font)
			if not suggestion.is_empty() and node_rects.has(suggestion):
				var target_rect: Rect2 = node_rects[suggestion]
				draw_dashed_line(candidate_rect.end - Vector2(candidate_rect.size.x * 0.5, 0.0), Vector2(target_rect.get_center().x, target_rect.position.y), Color(0.72, 0.38, 1.0, 0.38), 1.0, 6.0)

	for group_name in GROUP_ORDER:
		if not group_rects.has(group_name):
			continue
		var group_rect: Rect2 = group_rects[group_name]
		var group_center := Vector2(group_rect.position.x, group_rect.get_center().y)
		draw_line(Vector2(spine_x, group_center.y), group_center, Color(0.2, 0.75, 0.9, 0.7), 2.0)
		var header_rect := Rect2(group_rect.position.x, group_rect.get_center().y - 18.0, group_rect.size.x, 36.0)
		draw_rect(header_rect, Color(0.08, 0.18, 0.23), true)
		draw_rect(header_rect, Color(0.2, 0.75, 0.9), false, 1.5)
		draw_string(font, header_rect.position + Vector2(7.0, 22.0), group_name, HORIZONTAL_ALIGNMENT_LEFT, header_rect.size.x - 12.0, 10, Color(0.72, 0.93, 1.0))

		for slot_name in node_rects.keys():
			if _group_for_slot(str(slot_name)) != group_name:
				continue
			var node_rect: Rect2 = node_rects[slot_name]
			draw_line(header_rect.end - Vector2(0.0, header_rect.size.y * 0.5), Vector2(node_rect.position.x, node_rect.get_center().y), Color(0.2, 0.75, 0.9, 0.5), 1.5)
			var accent := Color(0.35, 0.88, 1.0) if drag_active else Color(0.2, 0.75, 0.9)
			if str(slot_name) == selected_slot and not drag_active:
				accent = Color(0.2, 1.0, 0.6)
			if str(slot_name) == hovered_slot:
				accent = Color(1.0, 0.82, 0.2)
			var clip_path := str(state_slots.get(slot_name, ""))
			var clip_name := "UNASSIGNED" if clip_path.is_empty() else clip_path.get_file()
			_draw_card(node_rect, str(slot_name), clip_name, accent, font)


func _draw_card(rect: Rect2, title: String, subtitle: String, accent: Color, font: Font) -> void:
	draw_rect(rect, Color(0.075, 0.095, 0.12), true)
	draw_rect(rect, accent, false, 2.0)
	draw_circle(Vector2(rect.position.x, rect.get_center().y), 4.0, accent)
	draw_string(font, rect.position + Vector2(10.0, 17.0), _fit_text(title, 29), HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 18.0, 12, Color.WHITE)
	draw_string(font, rect.position + Vector2(10.0, 33.0), _fit_text(subtitle, 31), HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 18.0, 10, Color(0.63, 0.71, 0.79))


func _fit_text(value: String, limit: int) -> String:
	return value if value.length() <= limit else value.left(limit - 1) + "…"


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var slot := _slot_at(event.position)
		if slot != hovered_slot:
			hovered_slot = slot
			tooltip_text = _tooltip_for_slot(slot)
			queue_redraw()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var slot := _slot_at(event.position)
		if not slot.is_empty():
			selected_slot = slot
			state_selected.emit(slot)
			queue_redraw()
		else:
			var candidate_index := _candidate_at(event.position)
			if candidate_index >= 0:
				candidate_selected.emit(candidate_entries[candidate_index].duplicate(true))


func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	var valid_payload := (
		data is Dictionary
		and str((data as Dictionary).get("kind", "")) == "operator_animation_clip"
	)
	var slot := _slot_at(at_position) if valid_payload else ""
	drag_active = valid_payload
	if hovered_slot != slot:
		hovered_slot = slot
		queue_redraw()
	return not slot.is_empty()


func _drop_data(at_position: Vector2, data: Variant) -> void:
	var slot := _slot_at(at_position)
	if slot.is_empty() or not data is Dictionary:
		return
	var entry: Dictionary = ((data as Dictionary).get("entry", {}) as Dictionary).duplicate(true)
	selected_slot = slot
	hovered_slot = ""
	clip_dropped_on_state.emit(entry, slot)
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_BEGIN:
		drag_active = true
		queue_redraw()
	elif what == NOTIFICATION_DRAG_END:
		drag_active = false
		hovered_slot = ""
		queue_redraw()


func _slot_at(point: Vector2) -> String:
	for slot_name in node_rects.keys():
		if (node_rects[slot_name] as Rect2).has_point(point):
			return str(slot_name)
	return ""


func _candidate_at(point: Vector2) -> int:
	for raw_index in candidate_rects.keys():
		if (candidate_rects[raw_index] as Rect2).has_point(point):
			return int(raw_index)
	return -1


func _tooltip_for_slot(slot_name: String) -> String:
	if slot_name.is_empty():
		return "Drag an animation clip onto a connected state card."
	return "%s\n%s" % [slot_name, str(state_slots.get(slot_name, "UNASSIGNED"))]


func _group_for_slot(slot_name: String) -> String:
	if slot_name == "idle_crouch" or slot_name.begins_with("crouch_"):
		return "CROUCH"
	if slot_name == "idle_prone" or slot_name.begins_with("prone_"):
		return "PRONE"
	if slot_name.begins_with("jump_") or slot_name in ["dive_roll", "roll"]:
		return "MOBILITY"
	if slot_name in ["combat_fire", "reload", "aim_idle"]:
		return "COMBAT"
	if (
		slot_name.begins_with("start_")
		or slot_name.begins_with("stop_")
		or slot_name.begins_with("turn_")
		or slot_name == "run_to_stop"
	):
		return "TRANSITIONS"
	return "STANDING LOCOMOTION"
