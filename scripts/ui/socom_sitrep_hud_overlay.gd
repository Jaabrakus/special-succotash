class_name SocomSitrepHudOverlay
extends Control

## Authentic SOCOM 2 SITREP Radio Transcript Feed
## Ported from reCOM (zUI, zSpeech)

const MAX_MESSAGES := 4
const MESSAGE_LIFETIME := 4.5

var messages: Array[Dictionary] = []
var _vbox: VBoxContainer


func _ready() -> void:
	custom_minimum_size = Vector2(340, 160)
	mouse_filter = MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	offset_left = 22.0
	offset_top = 58.0
	offset_right = 380.0
	offset_bottom = 220.0

	_vbox = VBoxContainer.new()
	_vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_vbox.add_theme_constant_override("separation", 6)
	_vbox.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(_vbox)


func _process(delta: float) -> void:
	var needs_rebuild := false
	for i in range(messages.size() - 1, -1, -1):
		messages[i]["time_remaining"] -= delta
		if messages[i]["time_remaining"] <= 0.0:
			messages.remove_at(i)
			needs_rebuild = true
	if needs_rebuild:
		_refresh_ui()


func add_sitrep_message(callsign: String, text: String, color: Color = Color("9df2cd")) -> void:
	if messages.size() >= MAX_MESSAGES:
		messages.pop_front()
	messages.append({
		"callsign": callsign,
		"text": text,
		"color": color,
		"time_remaining": MESSAGE_LIFETIME,
	})
	_refresh_ui()


func _refresh_ui() -> void:
	if _vbox == null:
		return
	for child in _vbox.get_children():
		child.queue_free()

	for msg in messages:
		var lbl := Label.new()
		lbl.text = "📻 [%s]: %s" % [msg.get("callsign", "OPERATOR"), msg.get("text", "")]
		lbl.add_theme_font_size_override("font_size", 13)
		var base_col: Color = msg.get("color", Color("9df2cd"))
		var alpha: float = clampf(float(msg.get("time_remaining", 1.0)) / 0.8, 0.0, 1.0)
		base_col.a = alpha
		lbl.add_theme_color_override("font_color", base_col)
		_vbox.add_child(lbl)
