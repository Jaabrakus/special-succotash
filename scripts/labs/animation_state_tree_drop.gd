extends Tree

signal clip_dropped_on_state(entry: Dictionary, slot_name: String)


func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	if not (
		data is Dictionary
		and str((data as Dictionary).get("kind", "")) == "operator_animation_clip"
	):
		return false
	var item := get_item_at_position(at_position)
	return item != null and not str(item.get_metadata(0)).is_empty()


func _drop_data(at_position: Vector2, data: Variant) -> void:
	if not _can_drop_data(at_position, data):
		return
	var item := get_item_at_position(at_position)
	var entry: Dictionary = ((data as Dictionary).get("entry", {}) as Dictionary).duplicate(true)
	clip_dropped_on_state.emit(entry, str(item.get_metadata(0)))
