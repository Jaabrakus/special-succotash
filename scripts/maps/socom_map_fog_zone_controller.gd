class_name SocomMapFogZoneController
extends Node

const MapDocument := preload("res://scripts/maps/socom_map_document.gd")

var zones: Array[Dictionary] = []
var world_environment: WorldEnvironment
var base_density := 0.0
var base_color := Color("778590")
var captured_base := false
var current_density := 0.0
var current_color := Color("778590")


func configure(document: Dictionary) -> void:
	zones.clear()
	for object: Dictionary in document.get("objects", []):
		if StringName(object.get("type", "")) == &"fog_zone":
			zones.append(object.duplicate(true))
	set_process(not zones.is_empty())


func _process(delta: float) -> void:
	if not _resolve_environment():
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var target_density := base_density
	var target_color := base_color
	var winning_priority := -INF
	var winning_weight := 0.0
	for zone: Dictionary in zones:
		var weight := _zone_weight(zone, camera.global_position)
		if weight <= 0.0:
			continue
		var properties: Dictionary = zone.get("properties", {})
		var priority := float(properties.get("priority", 0))
		if priority < winning_priority or (is_equal_approx(priority, winning_priority) and weight <= winning_weight):
			continue
		winning_priority = priority
		winning_weight = weight
		var authored_density := clampf(
			float(properties.get("density", 0.035)),
			0.0,
			0.1
		)
		var visibility_scale := clampf(
			float(properties.get("visibility_scale", 0.62)),
			0.20,
			1.0
		)
		# Local fog is tactical smoke, not an opaque fog-of-war volume. Keep the
		# authored color and blend, but cap its camera haze so silhouettes remain
		# visible through the instanced smoke cards.
		var smoke_density := maxf(base_density, authored_density * visibility_scale)
		target_density = lerpf(base_density, smoke_density, weight)
		target_color = base_color.lerp(MapDocument.data_to_color(zone.get("color", {}), base_color), weight)
	var response := 1.0 - exp(-maxf(delta, 0.0) * 5.5)
	current_density = lerpf(current_density, target_density, response)
	current_color = current_color.lerp(target_color, response)
	var environment := world_environment.environment
	if environment != null:
		environment.fog_enabled = current_density > 0.00001
		environment.fog_density = current_density
		environment.fog_light_color = current_color


func _resolve_environment() -> bool:
	if is_instance_valid(world_environment) and world_environment.environment != null:
		return true
	var scene := get_tree().current_scene
	if scene == null:
		return false
	world_environment = scene.find_child("MapWorldEnvironment", true, false) as WorldEnvironment
	if world_environment == null or world_environment.environment == null:
		return false
	base_density = world_environment.environment.fog_density if world_environment.environment.fog_enabled else 0.0
	base_color = world_environment.environment.fog_light_color
	current_density = base_density
	current_color = base_color
	captured_base = true
	return true


func _zone_weight(zone: Dictionary, world_position: Vector3) -> float:
	var center := MapDocument.data_to_vector(zone.get("position", {}))
	var rotation := MapDocument.data_to_vector(zone.get("rotation_degrees", {}))
	var basis := Basis.from_euler(Vector3(deg_to_rad(rotation.x), deg_to_rad(rotation.y), deg_to_rad(rotation.z)))
	var local := basis.inverse() * (world_position - center)
	var half_size := MapDocument.data_to_vector(zone.get("size", {}), Vector3(10.0, 3.0, 10.0)) * 0.5
	var margin := minf(half_size.x - absf(local.x), minf(half_size.y - absf(local.y), half_size.z - absf(local.z)))
	if margin < 0.0:
		return 0.0
	var properties: Dictionary = zone.get("properties", {})
	var blend_distance := maxf(float(properties.get("blend_distance", 2.5)), 0.01)
	return clampf(margin / blend_distance, 0.0, 1.0)
