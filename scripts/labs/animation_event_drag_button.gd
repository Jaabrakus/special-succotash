class_name SocomAnimationEventDragButton
extends Button

var animation_event: String = ""


func _get_drag_data(_position: Vector2) -> Variant:
	if animation_event.is_empty():
		return null
	var preview := Label.new()
	preview.text = "  %s  " % animation_event.replace("_", " ").capitalize()
	preview.add_theme_color_override("font_color", Color(1.0, 0.82, 0.32))
	set_drag_preview(preview)
	return {
		"kind": "operator_animation_event",
		"event": animation_event,
	}
