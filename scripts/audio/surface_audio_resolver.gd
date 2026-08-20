class_name SurfaceAudioResolver
extends Node

const Profile := preload("res://scripts/audio/surface_audio_profile.gd")

var profile: SurfaceAudioProfile


func _ready() -> void:
	_ensure_profile()


func resolve_surface(collider: Node) -> StringName:
	_ensure_profile()
	return profile.surface_for_collider(collider)


func resolve_surface_below(world_position: Vector3, exclude: Array[RID] = []) -> Dictionary:
	_ensure_profile()
	var viewport := get_viewport()
	if viewport == null or viewport.world_3d == null:
		return {"surface": &"default", "collider": null}
	var query := PhysicsRayQueryParameters3D.create(
		world_position + Vector3.UP * 0.12,
		world_position + Vector3.DOWN * 1.35
	)
	query.exclude = exclude
	query.collide_with_areas = false
	var hit := viewport.world_3d.direct_space_state.intersect_ray(query)
	var collider := hit.get("collider") as Node
	return {"surface": resolve_surface(collider), "collider": collider}


func play_event(
	foley: Node,
	event_name: StringName,
	world_position: Vector3,
	intensity := 1.0,
	collider: Node = null,
	explicit_surface: StringName = &""
) -> StringName:
	_ensure_profile()
	var surface := explicit_surface
	if surface.is_empty():
		if collider != null:
			surface = resolve_surface(collider)
		else:
			surface = StringName(resolve_surface_below(world_position).get("surface", &"default"))
	var strength := clampf(intensity, 0.05, 1.5)
	var intensity_db := 12.0 * log(strength) / log(2.0)
	for layer in profile.event_layers(surface, event_name):
		var chance := clampf(float(layer.get("chance", 1.0)), 0.0, 1.0)
		if randf() > chance:
			continue
		var minimum := float(layer.get("pitch_min", 0.96))
		var maximum := float(layer.get("pitch_max", 1.04))
		foley.call(
			"play_cue",
			StringName(layer.get("cue", "")),
			world_position,
			clampf(float(layer.get("volume_db", 0.0)) + intensity_db, -36.0, 8.0),
			randf_range(minimum, maximum)
		)
	return surface


func physics_for(surface_name: StringName) -> Dictionary:
	_ensure_profile()
	return profile.physics_for(surface_name)


func _ensure_profile() -> void:
	if profile == null:
		profile = Profile.new()
		profile.load_from_file()
