class_name AudioAnimationEventProfile
extends RefCounted

const DEFAULT_PATH := "res://config/audio_animation_events.json"

var animations: Dictionary = {}


func load_from_file(path := DEFAULT_PATH) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var file := FileAccess.open(path, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(file.get_as_text()) if file else null
	if not (parsed is Dictionary):
		return false
	var raw_animations: Variant = (parsed as Dictionary).get("animations", {})
	if not (raw_animations is Dictionary):
		return false
	animations = (raw_animations as Dictionary).duplicate(true)
	return true


func save_to_file(path := DEFAULT_PATH) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify({"schema_version": 1, "animations": animations}, "  "))
	return true


func events_for(animation_name: StringName) -> Array:
	var events: Variant = animations.get(String(animation_name), [])
	return (events as Array).duplicate(true) if events is Array else []


func set_events(animation_name: StringName, events: Array) -> void:
	animations[String(animation_name)] = events.duplicate(true)


func add_event(animation_name: StringName, event: Dictionary) -> void:
	var events := events_for(animation_name)
	events.append(_sanitize_event(event))
	set_events(animation_name, events)


func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	for animation_name in animations:
		if not animations[animation_name] is Array:
			errors.append("%s must contain an event array" % animation_name)
			continue
		for event in animations[animation_name]:
			if not event is Dictionary:
				errors.append("%s contains a non-object event" % animation_name)
				continue
			if float(event.get("time", -1.0)) < 0.0:
				errors.append("%s contains a negative event time" % animation_name)
			if String(event.get("cue", "")).is_empty() and String(event.get("event", "")).is_empty():
				errors.append("%s contains an event without a cue or surface event" % animation_name)
	return errors


func _sanitize_event(event: Dictionary) -> Dictionary:
	return {
		"time": maxf(0.0, float(event.get("time", 0.0))),
		"cue": String(event.get("cue", "foot_concrete")),
		"event": String(event.get("event", "")),
		"surface": String(event.get("surface", "")),
		"intensity": clampf(float(event.get("intensity", 0.75)), 0.05, 1.5),
		"bone": String(event.get("bone", "mixamorig_Hips")),
		"volume_db": clampf(float(event.get("volume_db", 0.0)), -36.0, 12.0),
		"pitch_min": clampf(float(event.get("pitch_min", 0.96)), 0.5, 2.0),
		"pitch_max": clampf(float(event.get("pitch_max", 1.04)), 0.5, 2.0),
	}
