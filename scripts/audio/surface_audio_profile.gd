class_name SurfaceAudioProfile
extends RefCounted

const DEFAULT_PATH := "res://config/surface_audio_profiles.json"

var surfaces: Dictionary = {}


func load_from_file(path := DEFAULT_PATH) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var file := FileAccess.open(path, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(file.get_as_text()) if file else null
	if not (parsed is Dictionary):
		return false
	var raw_surfaces: Variant = (parsed as Dictionary).get("surfaces", {})
	if not (raw_surfaces is Dictionary):
		return false
	surfaces = (raw_surfaces as Dictionary).duplicate(true)
	return not surfaces.is_empty()


func surface_for_name(source_name: String) -> StringName:
	var text := source_name.to_lower().strip_edges()
	if text.is_empty():
		return &"default"
	for surface_name in surfaces:
		if text == String(surface_name).to_lower():
			return StringName(surface_name)
		var data: Variant = surfaces[surface_name]
		if not (data is Dictionary):
			continue
		for alias in data.get("aliases", []):
			if text.contains(String(alias).to_lower()):
				return StringName(surface_name)
	return &"default"


func surface_for_collider(collider: Node) -> StringName:
	if collider == null:
		return &"default"
	for key in [&"surface_audio", &"surface_type", &"footstep_surface", &"material_type"]:
		if collider.has_meta(key):
			return surface_for_name(String(collider.get_meta(key)))
	var candidates := PackedStringArray([collider.name])
	for child in collider.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := child as MeshInstance3D
		candidates.append(mesh_instance.name)
		if mesh_instance.mesh != null:
			candidates.append(mesh_instance.mesh.resource_name)
			for index in mesh_instance.mesh.get_surface_count():
				var material := mesh_instance.get_active_material(index)
				if material != null:
					candidates.append(material.resource_name)
	for candidate in candidates:
		var surface := surface_for_name(candidate)
		if surface != &"default":
			return surface
	return &"default"


func event_layers(surface_name: StringName, event_name: StringName) -> Array:
	var data: Variant = surfaces.get(String(surface_name), surfaces.get("default", {}))
	if not (data is Dictionary):
		return []
	var events: Variant = data.get("events", {})
	if events is Dictionary and events.has(String(event_name)):
		var layers: Variant = events[String(event_name)]
		return (layers as Array).duplicate(true) if layers is Array else []
	if surface_name != &"default":
		return event_layers(&"default", event_name)
	return []


func physics_for(surface_name: StringName) -> Dictionary:
	var data: Variant = surfaces.get(String(surface_name), surfaces.get("default", {}))
	if not (data is Dictionary):
		return {}
	var physics: Variant = data.get("physics", {})
	return (physics as Dictionary).duplicate(true) if physics is Dictionary else {}


func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if not surfaces.has("default"):
		errors.append("surface profile requires a default surface")
	for surface_name in surfaces:
		var data: Variant = surfaces[surface_name]
		if not (data is Dictionary):
			errors.append("%s must be an object" % surface_name)
			continue
		var events: Variant = data.get("events", {})
		if not (events is Dictionary):
			errors.append("%s events must be an object" % surface_name)
			continue
		for event_name in events:
			if not events[event_name] is Array:
				errors.append("%s/%s must contain an audio layer array" % [surface_name, event_name])
				continue
			for layer in events[event_name]:
				if not (layer is Dictionary) or String(layer.get("cue", "")).is_empty():
					errors.append("%s/%s contains an invalid audio layer" % [surface_name, event_name])
	return errors
