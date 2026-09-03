class_name SocomMapRuntime
extends RefCounted

const MapDocument := preload("res://scripts/maps/socom_map_document.gd")
const MapAssetLibrary := preload("res://scripts/maps/socom_map_asset_library.gd")
const FogZoneController := preload("res://scripts/maps/socom_map_fog_zone_controller.gd")
const SwimmingVolume := preload("res://scripts/traversal/socom_swimming_volume.gd")
const DemolitionBombScene := preload("res://scenes/objectives/demolition_bomb.tscn")
const SAFETY_WALL_THICKNESS := 0.60
const SAFETY_WALL_MINIMUM_HEIGHT := 24.0
# The authored albedo maps carry the visible high-frequency detail. This small,
# filtered tile adds material depth/roughness without painting 128x128 maps in
# GDScript for every new surface family during the first playable frame.
const PROCEDURAL_DETAIL_SIZE := 16
const WALKABLE_SURFACE_TYPES: Array[StringName] = [&"ground", &"platform", &"ramp", &"roof", &"stairs"]
const PINE_FOLIAGE_TEXTURE_PATH := "res://assets/textures/environment/original_materials/pine_needles_albedo_v1.png"
const BROADLEAF_FOLIAGE_TEXTURE_PATH := "res://assets/textures/environment/original_materials/broadleaf_foliage_albedo_v1.png"
const TREE_BARK_TEXTURE_PATH := "res://assets/textures/environment/original_materials/pine_bark_albedo_v1.png"
static var surface_texture_cache: Dictionary = {}
static var surface_normal_cache: Dictionary = {}
static var surface_roughness_cache: Dictionary = {}
static var tree_material_cache: Dictionary = {}
static var authored_texture_cache: Dictionary = {}
static var fog_noise_texture: Texture2D


static func build_into(parent: Node3D, document: Dictionary, editor_preview: bool = false) -> Node3D:
	var normalized := MapDocument.normalize(document)
	if normalized.is_empty():
		return null
	var root := Node3D.new()
	root.name = "AuthoredMap"
	root.set_meta("map_name", normalized.get("name", "Map"))
	root.set_meta("gameplay", (normalized.get("gameplay", {}) as Dictionary).duplicate(true))
	parent.add_child(root)
	for object: Dictionary in normalized.get("objects", []):
		var object_started := Time.get_ticks_usec()
		var map_node := build_object(object, editor_preview)
		if map_node != null:
			root.add_child(map_node)
			_apply_camera_passage_policy(map_node, object)
			_apply_collision_policy(map_node, object, editor_preview)
		if OS.get_cmdline_user_args().has("--startup-profile"):
			var elapsed_ms := float(Time.get_ticks_usec() - object_started) / 1000.0
			if elapsed_ms >= 1.0:
				print("STARTUP_MAP_OBJECT %s type=%s step_ms=%.2f" % [
					String(object.get("name", object.get("id", "object"))),
					String(object.get("type", "")),
					elapsed_ms,
				])
	if not editor_preview:
		_add_safety_perimeter(root, normalized)
		var fog_controller := FogZoneController.new()
		fog_controller.name = "TacticalFogZoneController"
		fog_controller.configure(normalized)
		root.add_child(fog_controller)
	return root


static func validate_build(document: Dictionary) -> Dictionary:
	var errors: Array[String] = []
	var normalized := MapDocument.normalize(document)
	if normalized.is_empty():
		return {"ok": false, "errors": ["Map document is empty or invalid."], "built_objects": 0}
	var container := Node3D.new()
	var built_root := build_into(container, normalized, true)
	if built_root == null:
		container.free()
		return {"ok": false, "errors": ["Runtime could not build the map root."], "built_objects": 0}
	var expected_objects: Array = normalized.get("objects", [])
	var built_by_id: Dictionary = {}
	for child: Node in built_root.get_children():
		var object_id := String(child.get_meta("map_object_id", ""))
		if not object_id.is_empty():
			built_by_id[object_id] = child
	for object: Dictionary in expected_objects:
		var object_id := String(object.get("id", ""))
		if not built_by_id.has(object_id):
			errors.append("Runtime did not build object: %s" % object_id)
			continue
		var built_node := built_by_id[object_id] as Node
		var collisions := built_node.find_children("*", "CollisionShape3D", true, false)
		if collisions.is_empty():
			errors.append("Object has no preview collision: %s" % object_id)
		if String(object.get("type", "")) == "point_light" and built_node.find_child("Light", true, false) == null:
			errors.append("Practical light has no runtime light: %s" % object_id)
	var built_count := built_by_id.size()
	if built_count != expected_objects.size():
		errors.append("Runtime built %d of %d map objects." % [built_count, expected_objects.size()])
	container.free()
	return {"ok": errors.is_empty(), "errors": errors, "built_objects": built_count}


static func _add_safety_perimeter(parent: Node3D, document: Dictionary) -> void:
	var bounds := _walkable_bounds(document)
	if bounds.is_empty():
		return
	var min_x := float(bounds.min_x)
	var max_x := float(bounds.max_x)
	var min_z := float(bounds.min_z)
	var max_z := float(bounds.max_z)
	var bottom_y := float(bounds.minimum_top_y) - 8.0
	var top_y := maxf(
		float(bounds.maximum_top_y) + 12.0,
		bottom_y + SAFETY_WALL_MINIMUM_HEIGHT
	)
	var height := top_y - bottom_y
	var center_y := (bottom_y + top_y) * 0.5
	var width := maxf(max_x - min_x, 1.0)
	var depth := maxf(max_z - min_z, 1.0)

	var perimeter := Node3D.new()
	perimeter.name = "SafetyPerimeter"
	perimeter.set_meta("playable_border", true)
	perimeter.set_meta("bounds_min", Vector3(min_x, bottom_y, min_z))
	perimeter.set_meta("bounds_max", Vector3(max_x, top_y, max_z))
	parent.add_child(perimeter)
	_add_invisible_border(
		perimeter,
		"WestBorder",
		Vector3(SAFETY_WALL_THICKNESS, height, depth + SAFETY_WALL_THICKNESS * 2.0),
		Vector3(min_x - SAFETY_WALL_THICKNESS * 0.5, center_y, (min_z + max_z) * 0.5)
	)
	_add_invisible_border(
		perimeter,
		"EastBorder",
		Vector3(SAFETY_WALL_THICKNESS, height, depth + SAFETY_WALL_THICKNESS * 2.0),
		Vector3(max_x + SAFETY_WALL_THICKNESS * 0.5, center_y, (min_z + max_z) * 0.5)
	)
	_add_invisible_border(
		perimeter,
		"NorthBorder",
		Vector3(width, height, SAFETY_WALL_THICKNESS),
		Vector3((min_x + max_x) * 0.5, center_y, min_z - SAFETY_WALL_THICKNESS * 0.5)
	)
	_add_invisible_border(
		perimeter,
		"SouthBorder",
		Vector3(width, height, SAFETY_WALL_THICKNESS),
		Vector3((min_x + max_x) * 0.5, center_y, max_z + SAFETY_WALL_THICKNESS * 0.5)
	)


static func _walkable_bounds(document: Dictionary) -> Dictionary:
	var found := false
	var min_x := INF
	var max_x := -INF
	var min_z := INF
	var max_z := -INF
	var minimum_top_y := INF
	var maximum_top_y := -INF
	for object: Dictionary in document.get("objects", []):
		var type_name := StringName(object.get("type", ""))
		if type_name not in WALKABLE_SURFACE_TYPES:
			continue
		var position := MapDocument.data_to_vector(object.get("position", {}))
		var size := MapDocument.data_to_vector(object.get("size", {}), Vector3.ONE)
		var rotation := MapDocument.data_to_vector(object.get("rotation_degrees", {}))
		var yaw := deg_to_rad(rotation.y)
		var half_x := absf(cos(yaw)) * size.x * 0.5 + absf(sin(yaw)) * size.z * 0.5
		var half_z := absf(sin(yaw)) * size.x * 0.5 + absf(cos(yaw)) * size.z * 0.5
		min_x = minf(min_x, position.x - half_x)
		max_x = maxf(max_x, position.x + half_x)
		min_z = minf(min_z, position.z - half_z)
		max_z = maxf(max_z, position.z + half_z)
		var top_y := position.y + size.y * 0.5
		minimum_top_y = minf(minimum_top_y, top_y)
		maximum_top_y = maxf(maximum_top_y, top_y)
		found = true
	if not found:
		return {}
	return {
		"min_x": min_x,
		"max_x": max_x,
		"min_z": min_z,
		"max_z": max_z,
		"minimum_top_y": minimum_top_y,
		"maximum_top_y": maximum_top_y,
	}


static func _add_invisible_border(
	parent: Node3D,
	border_name: String,
	size: Vector3,
	position: Vector3
) -> void:
	var body := StaticBody3D.new()
	body.name = border_name
	body.position = position
	body.collision_layer = 1
	body.collision_mask = 0
	body.set_meta("playable_border", true)
	var collision := CollisionShape3D.new()
	collision.name = "CollisionShape3D"
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	parent.add_child(body)


static func build_object(object: Dictionary, editor_preview: bool = false) -> Node3D:
	var type_name := StringName(object.get("type", "wall"))
	if type_name == &"player_spawn":
		return _build_spawn(object, editor_preview)
	if type_name == &"point_light":
		return _build_point_light(object, editor_preview)
	if type_name == &"ambience_zone":
		return _build_ambience_zone(object, editor_preview)
	if type_name == &"fog_zone":
		return _build_fog_zone(object, editor_preview)
	if type_name == &"water_volume":
		return _build_water_volume(object, editor_preview)
	if type_name in [&"doorway_wall", &"window_wall"]:
		return _build_opening_wall(object, type_name == &"window_wall")
	if type_name == &"breached_wall":
		return _build_breached_wall(object)
	if type_name == &"stairs":
		return _build_stairs(object)
	if type_name in [&"primitive_cylinder", &"primitive_sphere"]:
		return _build_round_primitive(object, type_name == &"primitive_sphere")
	if type_name == &"favela_building":
		return _build_favela_building(object)
	if type_name == &"wooden_crate":
		return _build_wooden_crate(object)
	if type_name == &"utility_pole":
		return _build_utility_pole(object)
	if type_name == &"cable_curve":
		return _build_cable_curve(object, editor_preview)
	if type_name in MapDocument.SOCOM_OBJECTIVE_TYPES:
		return _build_objective_marker(object, editor_preview)
	if type_name == &"curved_wall":
		return _build_curved_wall(object)
	if type_name == &"jagged_wall":
		return _build_jagged_wall(object)
	if type_name in [&"tree", &"pine_tree"]:
		return _build_tree(object, type_name == &"pine_tree")
	if type_name == &"bush":
		return _build_bush(object, editor_preview)
	if type_name == &"rocky_mountain":
		return _build_rocky_mountain(object)
	if type_name == &"imported_asset":
		return _build_imported_asset(object, editor_preview)
	if type_name == &"ramp":
		return _build_wedge_ramp(object)
	if type_name in [&"training_dummy", &"moving_training_dummy"]:
		return _build_training_marker(object, editor_preview)
	var body := StaticBody3D.new()
	body.name = String(object.get("name", type_name)).validate_node_name()
	body.set_meta("map_object_id", String(object.get("id", "")))
	body.set_meta("map_object_type", type_name)
	body.position = MapDocument.data_to_vector(object.get("position", {}))
	body.rotation_degrees = MapDocument.data_to_vector(object.get("rotation_degrees", {}))
	var size := MapDocument.data_to_vector(object.get("size", {}), Vector3.ONE)
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "Visual"
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh_instance.mesh = mesh
	mesh_instance.material_override = _material_for_object(object)
	body.add_child(mesh_instance)
	var collision := CollisionShape3D.new()
	collision.name = "CollisionShape3D"
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	return body


static func _build_spawn(object: Dictionary, editor_preview: bool) -> Node3D:
	var marker := StaticBody3D.new()
	marker.name = "PlayerSpawn"
	marker.set_meta("map_object_id", String(object.get("id", "")))
	marker.set_meta("map_object_type", &"player_spawn")
	marker.position = MapDocument.data_to_vector(object.get("position", {}))
	marker.rotation_degrees = MapDocument.data_to_vector(object.get("rotation_degrees", {}))
	if not editor_preview:
		return marker
	var visual := MeshInstance3D.new()
	visual.name = "Visual"
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.38
	capsule.height = 1.8
	visual.mesh = capsule
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.25, 1.0, 0.62, 0.55)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	visual.material_override = material
	visual.position.y = 0.9
	marker.add_child(visual)
	var collision := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.38
	shape.height = 1.8
	collision.shape = shape
	collision.position.y = 0.9
	marker.add_child(collision)
	return marker


static func _build_point_light(object: Dictionary, editor_preview: bool) -> Node3D:
	var marker := StaticBody3D.new()
	marker.name = String(object.get("name", "Practical Light")).validate_node_name()
	marker.position = MapDocument.data_to_vector(object.get("position", {}))
	marker.set_meta("map_object_id", String(object.get("id", "")))
	marker.set_meta("map_object_type", &"point_light")
	var properties: Dictionary = object.get("properties", {})
	var light := OmniLight3D.new()
	light.name = "Light"
	light.light_color = MapDocument.data_to_color(object.get("color", {}), Color("ffd59b"))
	light.light_energy = float(properties.get("energy", 4.0))
	light.omni_range = float(properties.get("range", 8.0))
	# The editor can contain many practical lights. Realtime omni shadows on all
	# of them make navigation needlessly expensive; gameplay keeps authored shadows.
	light.shadow_enabled = false if editor_preview else bool(properties.get("shadow_enabled", true))
	marker.add_child(light)
	if editor_preview:
		_add_translucent_box(marker, Vector3(0.3, 0.3, 0.3), light.light_color, 0.85)
		var collision := CollisionShape3D.new()
		var shape := SphereShape3D.new()
		shape.radius = 0.3
		collision.shape = shape
		marker.add_child(collision)
	return marker


static func _build_ambience_zone(object: Dictionary, editor_preview: bool) -> Node3D:
	var area := Area3D.new()
	area.name = String(object.get("name", "Ambience Zone")).validate_node_name()
	area.position = MapDocument.data_to_vector(object.get("position", {}))
	area.rotation_degrees = MapDocument.data_to_vector(object.get("rotation_degrees", {}))
	area.set_meta("map_object_id", String(object.get("id", "")))
	area.set_meta("map_object_type", &"ambience_zone")
	# Audio-zone membership is calculated from the authored document. Runtime
	# bullets must not collide with this invisible editor/select volume.
	if not editor_preview:
		area.collision_layer = 0
		area.collision_mask = 0
	var properties: Dictionary = object.get("properties", {})
	for key: String in properties:
		area.set_meta(key, properties[key])
	var size := MapDocument.data_to_vector(object.get("size", {}), Vector3(6.0, 3.0, 6.0))
	var collision := CollisionShape3D.new()
	collision.name = "CollisionShape3D"
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	area.add_child(collision)
	if editor_preview:
		_add_translucent_box(area, size, MapDocument.data_to_color(object.get("color", {}), Color("8b6be8")), 0.16)
	return area


static func _build_fog_zone(object: Dictionary, editor_preview: bool) -> Node3D:
	var area := Area3D.new()
	area.name = String(object.get("name", "Tactical Fog Zone")).validate_node_name()
	area.position = MapDocument.data_to_vector(object.get("position", {}))
	area.rotation_degrees = MapDocument.data_to_vector(object.get("rotation_degrees", {}))
	_set_object_meta(area, object)
	# Fog blending also reads the document directly. Keeping this Area3D on the
	# world layer made its large invisible box win bullet and camera sight rays.
	if not editor_preview:
		area.collision_layer = 0
		area.collision_mask = 0
	var properties: Dictionary = object.get("properties", {})
	for key: String in properties:
		area.set_meta(key, properties[key])
	area.set_meta("fog_color", object.get("color", {}))
	var size := MapDocument.data_to_vector(object.get("size", {}), Vector3(10.0, 3.0, 10.0))
	area.set_meta("zone_size", MapDocument.vector_to_data(size))
	var collision := CollisionShape3D.new()
	collision.name = "CollisionShape3D"
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	area.add_child(collision)
	_add_fog_sightline_layers(
		area,
		size,
		MapDocument.data_to_color(object.get("color", {}), Color("7d99a8")),
		properties
	)
	if editor_preview:
		_add_translucent_box(area, size, MapDocument.data_to_color(object.get("color", {}), Color("7d99a8")), 0.13)
	return area


static func _build_water_volume(object: Dictionary, editor_preview: bool) -> Node3D:
	var area := SwimmingVolume.new()
	area.name = String(object.get("name", "Swimmable Water")).validate_node_name()
	area.position = MapDocument.data_to_vector(object.get("position", {}))
	area.rotation_degrees = MapDocument.data_to_vector(object.get("rotation_degrees", {}))
	_set_object_meta(area, object)
	var properties: Dictionary = object.get("properties", {})
	var size := MapDocument.data_to_vector(
		object.get("size", {}),
		Vector3(12.0, 3.0, 12.0)
	)
	area.surface_offset_y = float(properties.get("surface_offset_y", size.y * 0.5))
	var authored_source_id := String(properties.get("source_id", "")).strip_edges()
	area.source_id = StringName(
		authored_source_id
		if not authored_source_id.is_empty()
		else String(object.get("id", "map_water"))
	)
	area.collision_layer = 0
	area.collision_mask = 1
	var collision := CollisionShape3D.new()
	collision.name = "CollisionShape3D"
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	area.add_child(collision)

	var water_visual := MeshInstance3D.new()
	water_visual.name = "WaterSurface"
	water_visual.position.y = area.surface_offset_y
	var water_mesh := PlaneMesh.new()
	water_mesh.size = Vector2(size.x, size.z)
	water_visual.mesh = water_mesh
	var material := StandardMaterial3D.new()
	var color := MapDocument.data_to_color(object.get("color", {}), Color("257ca8"))
	material.albedo_color = Color(color.r, color.g, color.b, 0.48 if editor_preview else 0.38)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	material.roughness = 0.18
	water_visual.material_override = material
	area.add_child(water_visual)
	if editor_preview:
		_add_translucent_box(area, size, color, 0.08)
	return area


static func _add_fog_sightline_layers(parent: Node3D, size: Vector3, color: Color, properties: Dictionary) -> void:
	var strength := clampf(float(properties.get("occlusion_strength", 0.35)), 0.0, 0.95)
	if strength <= 0.001:
		return
	var layer_count := clampi(int(properties.get("layer_count", 6)), 2, 12)
	var layers := Node3D.new()
	layers.name = "FogSightlineLayers"
	parent.add_child(layers)
	# One MultiMesh per zone replaces the old crossed stacks of full-volume
	# transparent planes. The old layout behaved like a visibility wall and made
	# Crossroads render 72 overlapping transparent objects. These soft billboard
	# clouds remain see-through and cost one instanced draw object per zone.
	var cloud_count := clampi(layer_count, 3, 8)
	var cloud_mesh := QuadMesh.new()
	cloud_mesh.size = Vector2.ONE
	cloud_mesh.material = _fog_layer_material(
		color,
		minf(0.10, strength * 0.20)
	)
	var clouds := MultiMesh.new()
	clouds.transform_format = MultiMesh.TRANSFORM_3D
	clouds.mesh = cloud_mesh
	clouds.instance_count = cloud_count
	var seed_value := absi(String(parent.get_meta("map_object_id", parent.name)).hash())
	var cloud_width := maxf(minf(size.x, size.z) * 0.52, 1.6)
	var cloud_height := maxf(size.y * 0.82, 1.2)
	for index in cloud_count:
		var scale_noise := 0.82 + absf(_asset_noise(seed_value, index + 41)) * 0.34
		var transform := Transform3D(
			Basis.IDENTITY.scaled(Vector3(
				cloud_width * scale_noise,
				cloud_height * scale_noise,
				1.0
			)),
			Vector3(
				_asset_noise(seed_value, index + 3) * size.x * 0.40,
				_asset_noise(seed_value, index + 17) * size.y * 0.22,
				_asset_noise(seed_value, index + 29) * size.z * 0.40
			)
		)
		clouds.set_instance_transform(index, transform)
	var smoke_instance := MultiMeshInstance3D.new()
	smoke_instance.name = "SmokeCloudInstances"
	smoke_instance.multimesh = clouds
	layers.add_child(smoke_instance)


static func _fog_layer_material(color: Color, alpha: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.albedo_color = Color(color.r, color.g, color.b, alpha)
	material.albedo_texture = _fog_noise()
	return material


static func _fog_noise() -> Texture2D:
	if fog_noise_texture != null:
		return fog_noise_texture
	var image := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	for y in 64:
		for x in 64:
			var broad := _surface_noise(x / 4, y / 4, 211)
			var fine := _surface_noise(x, y, 431)
			var opacity := clampf(0.28 + broad * 0.42 + fine * 0.18, 0.12, 0.88)
			image.set_pixel(x, y, Color(1.0, 1.0, 1.0, opacity))
	fog_noise_texture = ImageTexture.create_from_image(image)
	return fog_noise_texture


static func _build_opening_wall(object: Dictionary, window_opening: bool) -> Node3D:
	var root := Node3D.new()
	root.name = String(object.get("name", "Window Wall" if window_opening else "Doorway Wall")).validate_node_name()
	root.position = MapDocument.data_to_vector(object.get("position", {}))
	root.rotation_degrees = MapDocument.data_to_vector(object.get("rotation_degrees", {}))
	_set_object_meta(root, object)
	var size := MapDocument.data_to_vector(object.get("size", {}), Vector3(4.0, 3.0, 0.3))
	var properties: Dictionary = object.get("properties", {})
	var opening_width := clampf(float(properties.get("opening_width", 1.25)), 0.6, maxf(size.x - 0.4, 0.6))
	var opening_height := clampf(float(properties.get("opening_height", 1.25 if window_opening else 2.2)), 0.5, maxf(size.y - 0.2, 0.5))
	var side_width := maxf((size.x - opening_width) * 0.5, 0.1)
	_add_compound_box(root, "LeftPier", Vector3(side_width, size.y, size.z), Vector3(-(opening_width + side_width) * 0.5, 0.0, 0.0), object)
	_add_compound_box(root, "RightPier", Vector3(side_width, size.y, size.z), Vector3((opening_width + side_width) * 0.5, 0.0, 0.0), object)
	if window_opening:
		var sill_height := maxf((size.y - opening_height) * 0.48, 0.55)
		var header_height := maxf(size.y - opening_height - sill_height, 0.1)
		_add_compound_box(root, "WindowSill", Vector3(opening_width, sill_height, size.z), Vector3(0.0, -size.y * 0.5 + sill_height * 0.5, 0.0), object)
		_add_compound_box(root, "WindowHeader", Vector3(opening_width, header_height, size.z), Vector3(0.0, size.y * 0.5 - header_height * 0.5, 0.0), object)
	else:
		var header_height := maxf(size.y - opening_height, 0.1)
		_add_compound_box(root, "DoorHeader", Vector3(opening_width, header_height, size.z), Vector3(0.0, size.y * 0.5 - header_height * 0.5, 0.0), object)
	return root


static func _build_favela_building(object: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = String(object.get("name", "Favela Building Assembly")).validate_node_name()
	root.position = MapDocument.data_to_vector(object.get("position", {}))
	root.rotation_degrees = MapDocument.data_to_vector(object.get("rotation_degrees", {}))
	_set_object_meta(root, object)
	var size := MapDocument.data_to_vector(object.get("size", {}), Vector3(8.0, 4.4, 7.0))
	var properties: Dictionary = object.get("properties", {})
	var entries: Array = properties.get("entries", ["south"])
	var windows: Array = properties.get("windows", ["north"])
	var door_width := clampf(float(properties.get("door_width", 1.55)), 0.8, minf(size.x, size.z) - 0.8)
	var door_height := clampf(float(properties.get("door_height", 2.35)), 1.8, size.y - 0.2)
	var window_width := clampf(float(properties.get("window_width", 1.65)), 0.8, minf(size.x, size.z) - 0.8)
	var window_height := clampf(float(properties.get("window_height", 1.25)), 0.7, size.y - 1.0)
	var wall_thickness := 0.35
	var base_color := MapDocument.data_to_color(object.get("color", {}), Color("d1b58c"))
	var trim_color := MapDocument.data_to_color(properties.get("trim_color", {}), Color("e3d8bd"))
	var roof_color := MapDocument.data_to_color(properties.get("roof_color", {}), Color("62564f"))
	var damage_side := String(properties.get("damage_side", "south"))
	var downspout_side := String(properties.get("downspout_side", "east"))
	var masonry_texture_path := String(properties.get("masonry_texture_path", ""))
	var wood_texture_path := String(properties.get("wood_texture_path", ""))
	var wood_wall_sides: Array = properties.get("wood_wall_sides", [])
	var building_id := String(object.get("id", "favela_building"))

	var slab_object := _building_part_object(object, "slab", roof_color, "concrete")
	_add_compound_box(root, "FloorSlab", Vector3(size.x, 0.35, size.z), Vector3(0.0, 0.175, 0.0), slab_object)
	_add_compound_box(root, "RoofSlab", Vector3(size.x, 0.35, size.z), Vector3(0.0, size.y + 0.175, 0.0), slab_object)

	for side_index in 4:
		var side: String = ["north", "south", "east", "west"][side_index]
		var wall_position := Vector3(0.0, size.y * 0.5, 0.0)
		var wall_size := Vector3(size.x, size.y, wall_thickness)
		var wall_yaw := 0.0
		var exterior_sign := 1.0
		if side == "north":
			wall_position.z = -size.z * 0.5
			exterior_sign = -1.0
		elif side == "south":
			wall_position.z = size.z * 0.5
		elif side == "east":
			wall_position.x = size.x * 0.5
			wall_size.x = size.z
			wall_yaw = 90.0
		elif side == "west":
			wall_position.x = -size.x * 0.5
			wall_size.x = size.z
			wall_yaw = 90.0
			exterior_sign = -1.0
		var wall_color := base_color.lightened(0.045 * float((side_index + building_id.length()) % 3))
		if side_index == 2:
			wall_color = wall_color.darkened(0.06)
		var wall_object := _building_part_object(object, "%s_wall" % side, wall_color, "default")
		var wall_texture_path := wood_texture_path if side in wood_wall_sides else masonry_texture_path
		_apply_authored_surface_texture(
			wall_object,
			wall_texture_path,
			0.46 if side in wood_wall_sides else 0.34,
			0.08 if side in wood_wall_sides else 0.04,
			Color("b4aa99") if side in wood_wall_sides else Color("d4cab8")
		)
		wall_object["position"] = MapDocument.vector_to_data(wall_position)
		wall_object["rotation_degrees"] = MapDocument.vector_to_data(Vector3(0.0, wall_yaw, 0.0))
		wall_object["size"] = MapDocument.vector_to_data(wall_size)
		var wall_properties: Dictionary = wall_object.get("properties", {})
		wall_properties["building_side"] = side
		wall_object["properties"] = wall_properties
		var wall_node: Node3D
		if side in entries:
			wall_properties["opening_width"] = door_width
			wall_properties["opening_height"] = door_height
			wall_object["properties"] = wall_properties
			wall_node = _build_opening_wall(wall_object, false)
			_add_door_architecture(wall_node, wall_size, door_width, door_height, exterior_sign, trim_color, roof_color, wall_object)
		elif side in windows:
			wall_properties["opening_width"] = window_width
			wall_properties["opening_height"] = window_height
			wall_object["properties"] = wall_properties
			wall_node = _build_opening_wall(wall_object, true)
			_add_window_architecture(wall_node, wall_size, window_width, window_height, exterior_sign, trim_color, roof_color, wall_object)
		else:
			wall_node = Node3D.new()
			wall_node.name = "%sWall" % side.capitalize()
			wall_node.position = wall_position
			wall_node.rotation_degrees.y = wall_yaw
			_set_object_meta(wall_node, wall_object)
			_add_compound_box(wall_node, "WallMass", wall_size, Vector3.ZERO, wall_object)
		root.add_child(wall_node)
		if side == damage_side:
			_add_exposed_brick_relief(wall_node, wall_size, exterior_sign, wall_object)
		else:
			_add_irregular_plaster_patch(wall_node, wall_size, exterior_sign, wall_color, side_index, wall_object)
		_add_foundation_band(wall_node, wall_size, exterior_sign, roof_color, wall_object)
		if side == downspout_side:
			_add_downspout(wall_node, wall_size, exterior_sign, wall_object)
			_add_electrical_service(wall_node, wall_size, exterior_sign, wall_object)

	_add_corner_pilasters(root, size, trim_color.darkened(0.14), object)
	_add_roof_cornice(root, size, roof_color, object)

	var parapet_height := clampf(float(properties.get("parapet_height", 0.35)), 0.0, 0.8)
	if parapet_height > 0.05:
		var parapet_object := _building_part_object(object, "parapet", base_color.darkened(0.16), "default")
		var parapet_y := size.y + 0.35 + parapet_height * 0.5
		_add_compound_box(root, "NorthParapet", Vector3(size.x, parapet_height, 0.22), Vector3(0.0, parapet_y, -size.z * 0.5 + 0.11), parapet_object)
		_add_compound_box(root, "SouthParapet", Vector3(size.x, parapet_height, 0.22), Vector3(0.0, parapet_y, size.z * 0.5 - 0.11), parapet_object)
		_add_compound_box(root, "EastParapet", Vector3(0.22, parapet_height, size.z), Vector3(size.x * 0.5 - 0.11, parapet_y, 0.0), parapet_object)
		_add_compound_box(root, "WestParapet", Vector3(0.22, parapet_height, size.z), Vector3(-size.x * 0.5 + 0.11, parapet_y, 0.0), parapet_object)
	return root


static func _building_part_object(source: Dictionary, suffix: String, color: Color, surface_kind: String) -> Dictionary:
	var result := source.duplicate(true)
	result["id"] = "%s_%s" % [String(source.get("id", "building")), suffix]
	result["color"] = MapDocument.color_to_data(color)
	var properties: Dictionary = (source.get("properties", {}) as Dictionary).duplicate(true)
	properties["painterly_material"] = true
	properties["painterly_material_v2"] = true
	properties["surface_kind"] = surface_kind
	properties["roughness"] = 1.0
	properties["normal_strength"] = 0.035
	properties.erase("texture_path")
	result["properties"] = properties
	return result


static func _apply_authored_surface_texture(
	object: Dictionary, texture_path: String, uv_scale: float,
	tint_weight: float, texture_multiplier: Color
) -> void:
	if texture_path.is_empty():
		return
	var properties: Dictionary = (object.get("properties", {}) as Dictionary).duplicate(true)
	properties["texture_path"] = texture_path
	properties["surface_kind"] = "default"
	properties["uv_scale"] = uv_scale
	properties["texture_tint_weight"] = tint_weight
	properties["texture_multiplier"] = MapDocument.color_to_data(texture_multiplier)
	object["properties"] = properties


static func _add_door_architecture(
	wall: Node3D, wall_size: Vector3, opening_width: float, opening_height: float,
	exterior_sign: float, trim_color: Color, awning_color: Color, source: Dictionary
) -> void:
	var trim_object := _building_part_object(source, "door_trim", trim_color, "default")
	var face_z := exterior_sign * (wall_size.z * 0.5 + 0.055)
	var center_y := -wall_size.y * 0.5 + opening_height * 0.5
	_add_visual_box(wall, "LeftDoorJamb", Vector3(0.13, opening_height + 0.08, 0.10), Vector3(-opening_width * 0.5 - 0.065, center_y, face_z), Vector3.ZERO, trim_object)
	_add_visual_box(wall, "RightDoorJamb", Vector3(0.13, opening_height + 0.08, 0.10), Vector3(opening_width * 0.5 + 0.065, center_y, face_z), Vector3.ZERO, trim_object)
	_add_visual_box(wall, "DoorLintel", Vector3(opening_width + 0.26, 0.15, 0.10), Vector3(0.0, -wall_size.y * 0.5 + opening_height + 0.075, face_z), Vector3.ZERO, trim_object)
	var door_hinge := Node3D.new()
	door_hinge.name = "OpenDoorHinge"
	door_hinge.position = Vector3(-opening_width * 0.5 + 0.05, center_y, 0.0)
	door_hinge.rotation_degrees.y = 58.0 * exterior_sign
	wall.add_child(door_hinge)
	var door_object := _building_part_object(source, "door_leaf", awning_color.darkened(0.22), "default")
	var source_properties: Dictionary = source.get("properties", {})
	_apply_authored_surface_texture(
		door_object, String(source_properties.get("wood_texture_path", "")), 0.48, 0.06, Color("a89b87")
	)
	_add_visual_box(
		door_hinge, "OpenDoorLeaf",
		Vector3(opening_width * 0.78, opening_height * 0.94, 0.085),
		Vector3(opening_width * 0.39, 0.0, 0.0), Vector3.ZERO, door_object
	)
	_add_corrugated_awning(wall, wall_size, opening_width + 0.65, opening_height, exterior_sign, awning_color, source)
	var properties: Dictionary = source.get("properties", {})
	var sign_text := String(properties.get("sign_text", ""))
	var building_side := String(properties.get("building_side", ""))
	if not sign_text.is_empty() and building_side == String(properties.get("sign_side", "south")):
		_add_facade_sign(wall, wall_size, opening_height, exterior_sign, sign_text, source)


static func _add_facade_sign(
	wall: Node3D, wall_size: Vector3, opening_height: float,
	exterior_sign: float, sign_text: String, source: Dictionary
) -> void:
	var board_width := clampf(0.62 + float(sign_text.length()) * 0.23, 1.7, minf(wall_size.x * 0.62, 3.6))
	var board_y := -wall_size.y * 0.5 + opening_height + 0.82
	var board_z := exterior_sign * (wall_size.z * 0.5 + 0.085)
	var board_object := _building_part_object(source, "facade_sign", Color("374847"), "default")
	var properties: Dictionary = source.get("properties", {})
	_apply_authored_surface_texture(
		board_object, String(properties.get("wood_texture_path", "")), 0.55, 0.20, Color("827869")
	)
	_add_visual_box(
		wall, "FacadeSignBoard", Vector3(board_width, 0.52, 0.13),
		Vector3(0.0, board_y, board_z), Vector3.ZERO, board_object
	)
	var label := Label3D.new()
	label.name = "FacadeSignText"
	label.text = sign_text
	label.font_size = 64
	label.pixel_size = 0.0062
	label.outline_size = 8
	label.modulate = Color("f1dfae")
	label.outline_modulate = Color("202b2b")
	label.position = Vector3(0.0, board_y, board_z + exterior_sign * 0.075)
	label.rotation_degrees.y = 180.0 if exterior_sign < 0.0 else 0.0
	wall.add_child(label)


static func _add_window_architecture(
	wall: Node3D, wall_size: Vector3, opening_width: float, opening_height: float,
	exterior_sign: float, trim_color: Color, shutter_color: Color, source: Dictionary
) -> void:
	var sill_height := maxf((wall_size.y - opening_height) * 0.48, 0.55)
	var center_y := -wall_size.y * 0.5 + sill_height + opening_height * 0.5
	var face_z := exterior_sign * (wall_size.z * 0.5 + 0.055)
	var trim_object := _building_part_object(source, "window_trim", trim_color, "default")
	_add_visual_box(wall, "LeftWindowJamb", Vector3(0.11, opening_height + 0.18, 0.09), Vector3(-opening_width * 0.5 - 0.055, center_y, face_z), Vector3.ZERO, trim_object)
	_add_visual_box(wall, "RightWindowJamb", Vector3(0.11, opening_height + 0.18, 0.09), Vector3(opening_width * 0.5 + 0.055, center_y, face_z), Vector3.ZERO, trim_object)
	_add_visual_box(wall, "WindowHeaderTrim", Vector3(opening_width + 0.22, 0.11, 0.09), Vector3(0.0, center_y + opening_height * 0.5 + 0.055, face_z), Vector3.ZERO, trim_object)
	_add_visual_box(wall, "WindowSillTrim", Vector3(opening_width + 0.34, 0.13, 0.18), Vector3(0.0, center_y - opening_height * 0.5 - 0.05, face_z + exterior_sign * 0.04), Vector3.ZERO, trim_object)
	var shutter_object := _building_part_object(source, "shutters", shutter_color.darkened(0.18), "default")
	var source_properties: Dictionary = source.get("properties", {})
	_apply_authored_surface_texture(
		shutter_object, String(source_properties.get("wood_texture_path", "")), 0.52, 0.08, Color("a99d8a")
	)
	var shutter_width := minf(opening_width * 0.30, 0.52)
	_add_visual_box(wall, "LeftShutter", Vector3(shutter_width, opening_height + 0.04, 0.08), Vector3(-opening_width * 0.5 - shutter_width * 0.58, center_y, face_z + exterior_sign * 0.03), Vector3(0.0, -10.0 * exterior_sign, 0.0), shutter_object)
	_add_visual_box(wall, "RightShutter", Vector3(shutter_width, opening_height + 0.04, 0.08), Vector3(opening_width * 0.5 + shutter_width * 0.58, center_y, face_z + exterior_sign * 0.03), Vector3(0.0, 10.0 * exterior_sign, 0.0), shutter_object)
	_add_window_sash_and_glass(wall, wall_size, opening_width, opening_height, center_y, exterior_sign, source)
	var grille_object := _building_part_object(source, "window_grille", Color("384342"), "default")
	for index in 3:
		var grille_x := (float(index) - 1.0) * opening_width * 0.27
		_add_visual_box(wall, "WindowGrilleVertical%d" % index, Vector3(0.035, opening_height * 0.88, 0.045), Vector3(grille_x, center_y, face_z + exterior_sign * 0.06), Vector3.ZERO, grille_object)
	for index in 2:
		var grille_y := center_y + (float(index) - 0.5) * opening_height * 0.38
		_add_visual_box(wall, "WindowGrilleHorizontal%d" % index, Vector3(opening_width * 0.92, 0.035, 0.045), Vector3(0.0, grille_y, face_z + exterior_sign * 0.06), Vector3.ZERO, grille_object)


static func _add_window_sash_and_glass(
	wall: Node3D, wall_size: Vector3, opening_width: float, opening_height: float,
	center_y: float, exterior_sign: float, source: Dictionary
) -> void:
	var sash_width := opening_width * 0.82
	var sash_height := opening_height * 0.80
	var glass_z := -exterior_sign * wall_size.z * 0.12
	var glass := MeshInstance3D.new()
	glass.name = "WindowGlass"
	var glass_mesh := BoxMesh.new()
	glass_mesh.size = Vector3(sash_width * 0.94, sash_height * 0.94, 0.018)
	glass.mesh = glass_mesh
	glass.position = Vector3(0.0, center_y, glass_z)
	var glass_material := StandardMaterial3D.new()
	glass_material.albedo_color = Color(0.25, 0.48, 0.53, 0.42)
	glass_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass_material.roughness = 0.22
	glass_material.metallic = 0.08
	glass_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	glass.material_override = glass_material
	glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	wall.add_child(glass)

	var source_properties: Dictionary = source.get("properties", {})
	var sash_object := _building_part_object(source, "window_sash", Color("625244"), "default")
	_apply_authored_surface_texture(
		sash_object, String(source_properties.get("wood_texture_path", "")), 0.58, 0.05, Color("9f927f")
	)
	var sash_z := glass_z + exterior_sign * 0.025
	var rail := 0.065
	_add_visual_box(wall, "WindowSashLeft", Vector3(rail, sash_height, 0.055), Vector3(-sash_width * 0.5, center_y, sash_z), Vector3.ZERO, sash_object)
	_add_visual_box(wall, "WindowSashRight", Vector3(rail, sash_height, 0.055), Vector3(sash_width * 0.5, center_y, sash_z), Vector3.ZERO, sash_object)
	_add_visual_box(wall, "WindowSashTop", Vector3(sash_width, rail, 0.055), Vector3(0.0, center_y + sash_height * 0.5, sash_z), Vector3.ZERO, sash_object)
	_add_visual_box(wall, "WindowSashBottom", Vector3(sash_width, rail, 0.055), Vector3(0.0, center_y - sash_height * 0.5, sash_z), Vector3.ZERO, sash_object)
	_add_visual_box(wall, "WindowMullionVertical", Vector3(rail * 0.72, sash_height, 0.060), Vector3(0.0, center_y, sash_z + exterior_sign * 0.01), Vector3.ZERO, sash_object)
	_add_visual_box(wall, "WindowMullionHorizontal", Vector3(sash_width, rail * 0.72, 0.060), Vector3(0.0, center_y, sash_z + exterior_sign * 0.01), Vector3.ZERO, sash_object)


static func _add_corrugated_awning(
	wall: Node3D, wall_size: Vector3, width: float, opening_height: float,
	exterior_sign: float, color: Color, source: Dictionary
) -> void:
	var awning_root := Node3D.new()
	awning_root.name = "CorrugatedDoorAwning"
	awning_root.position = Vector3(
		0.0,
		-wall_size.y * 0.5 + opening_height + 0.34,
		exterior_sign * (wall_size.z * 0.5 + 0.48)
	)
	awning_root.rotation_degrees.x = exterior_sign * 7.0
	wall.add_child(awning_root)
	var panel_object := _building_part_object(source, "corrugated_awning", color.darkened(0.08), "default")
	var rib_count := 11
	var rib_width := width / float(rib_count)
	for index in rib_count:
		var x := -width * 0.5 + rib_width * (float(index) + 0.5)
		var ridge_y := 0.025 if index % 2 == 0 else -0.025
		_add_visual_box(awning_root, "Corrugation%02d" % index, Vector3(rib_width * 1.04, 0.065, 0.95), Vector3(x, ridge_y, 0.0), Vector3.ZERO, panel_object)
	for side in [-1.0, 1.0]:
		_add_visual_box(awning_root, "AwningBrace%s" % ("L" if side < 0.0 else "R"), Vector3(0.07, 0.07, 0.88), Vector3(side * width * 0.40, -0.22, -0.05), Vector3(22.0 * exterior_sign, 0.0, 0.0), panel_object)


static func _add_irregular_plaster_patch(
	wall: Node3D, wall_size: Vector3, exterior_sign: float, wall_color: Color,
	variant: int, source: Dictionary
) -> void:
	var patch_width := minf(wall_size.x * 0.22, 1.55)
	var patch_height := minf(wall_size.y * 0.20, 0.95)
	var patch_x := wall_size.x * (0.31 if variant % 2 == 0 else -0.31)
	var patch_y := wall_size.y * (-0.16 if variant % 3 == 0 else 0.18)
	var outline: Array[Vector2] = [
		Vector2(-0.53, -0.19), Vector2(-0.31, -0.51), Vector2(0.12, -0.45),
		Vector2(0.54, -0.20), Vector2(0.43, 0.29), Vector2(0.08, 0.52),
		Vector2(-0.39, 0.37),
	]
	var surface_tool := SurfaceTool.new()
	surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var normal := Vector3(0.0, 0.0, exterior_sign)
	var face_z := exterior_sign * (wall_size.z * 0.5 + 0.058)
	for index in outline.size():
		var first := outline[index]
		var second := outline[(index + 1) % outline.size()]
		for point: Vector2 in [Vector2.ZERO, first, second]:
			surface_tool.set_normal(normal)
			surface_tool.add_vertex(Vector3(
				patch_x + point.x * patch_width,
				patch_y + point.y * patch_height,
				face_z
			))
	var patch := MeshInstance3D.new()
	patch.name = "IrregularPlasterPatch"
	patch.mesh = surface_tool.commit()
	var patch_color := wall_color.darkened(0.14) if variant % 2 == 0 else wall_color.lightened(0.11)
	patch.material_override = _material_for_object(_building_part_object(source, "plaster_patch", patch_color, "default"))
	patch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	wall.add_child(patch)


static func _add_foundation_band(
	wall: Node3D, wall_size: Vector3, exterior_sign: float,
	color: Color, source: Dictionary
) -> void:
	var foundation_object := _building_part_object(source, "foundation", color.darkened(0.28), "default")
	var face_z := exterior_sign * (wall_size.z * 0.5 + 0.075)
	_add_visual_box(
		wall, "RaisedFoundationCourse", Vector3(wall_size.x * 0.94, 0.30, 0.11),
		Vector3(0.0, -wall_size.y * 0.5 + 0.15, face_z), Vector3.ZERO, foundation_object
	)
	for index in 3:
		var seam_x := (float(index) - 1.0) * wall_size.x * 0.24
		_add_visual_box(
			wall, "FoundationJoint%d" % index, Vector3(0.025, 0.27, 0.018),
			Vector3(seam_x, -wall_size.y * 0.5 + 0.15, face_z + exterior_sign * 0.06),
			Vector3.ZERO, _building_part_object(source, "foundation_joint", color.darkened(0.42), "default")
		)


static func _add_electrical_service(wall: Node3D, wall_size: Vector3, exterior_sign: float, source: Dictionary) -> void:
	var service_object := _building_part_object(source, "electrical_service", Color("4a5554"), "default")
	var x := -wall_size.x * 0.32
	var face_z := exterior_sign * (wall_size.z * 0.5 + 0.095)
	_add_visual_box(
		wall, "ElectricalMeterBox", Vector3(0.34, 0.46, 0.16),
		Vector3(x, -wall_size.y * 0.05, face_z), Vector3.ZERO, service_object
	)
	var conduit := MeshInstance3D.new()
	conduit.name = "ElectricalConduit"
	var conduit_mesh := CylinderMesh.new()
	conduit_mesh.top_radius = 0.028
	conduit_mesh.bottom_radius = 0.028
	conduit_mesh.height = wall_size.y * 0.48
	conduit_mesh.radial_segments = 8
	conduit.mesh = conduit_mesh
	conduit.position = Vector3(x, -wall_size.y * 0.29, face_z)
	conduit.material_override = _material_for_object(service_object)
	wall.add_child(conduit)


static func _add_corner_pilasters(root: Node3D, size: Vector3, color: Color, source: Dictionary) -> void:
	var pilaster_object := _building_part_object(source, "corner_pilaster", color, "default")
	for x_sign in [-1.0, 1.0]:
		for z_sign in [-1.0, 1.0]:
			_add_visual_box(
				root, "CornerPilaster%s%s" % ["W" if x_sign < 0.0 else "E", "N" if z_sign < 0.0 else "S"],
				Vector3(0.30, size.y + 0.12, 0.30),
				Vector3(x_sign * size.x * 0.5, size.y * 0.5, z_sign * size.z * 0.5),
				Vector3.ZERO, pilaster_object
			)


static func _add_roof_cornice(root: Node3D, size: Vector3, color: Color, source: Dictionary) -> void:
	var cornice_object := _building_part_object(source, "roof_cornice", color.darkened(0.12), "default")
	var cornice_y := size.y + 0.28
	_add_visual_box(root, "NorthRoofCornice", Vector3(size.x + 0.34, 0.22, 0.26), Vector3(0.0, cornice_y, -size.z * 0.5), Vector3.ZERO, cornice_object)
	_add_visual_box(root, "SouthRoofCornice", Vector3(size.x + 0.34, 0.22, 0.26), Vector3(0.0, cornice_y, size.z * 0.5), Vector3.ZERO, cornice_object)
	_add_visual_box(root, "EastRoofCornice", Vector3(0.26, 0.22, size.z), Vector3(size.x * 0.5, cornice_y, 0.0), Vector3.ZERO, cornice_object)
	_add_visual_box(root, "WestRoofCornice", Vector3(0.26, 0.22, size.z), Vector3(-size.x * 0.5, cornice_y, 0.0), Vector3.ZERO, cornice_object)


static func _add_exposed_brick_relief(wall: Node3D, wall_size: Vector3, exterior_sign: float, source: Dictionary) -> void:
	var mortar_object := _building_part_object(source, "damage_mortar", Color("6d635b"), "default")
	var brick_object := _building_part_object(source, "exposed_brick", Color("87513d"), "default")
	var face_z := exterior_sign * (wall_size.z * 0.5 + 0.045)
	var patch_x := wall_size.x * 0.28
	var patch_y := wall_size.y * 0.12
	_add_visual_box(wall, "BrokenPlasterRecess", Vector3(1.28, 0.84, 0.055), Vector3(patch_x, patch_y, face_z), Vector3(0.0, 0.0, -4.0), mortar_object)
	for index in 8:
		var row := index / 3
		var column := index % 3
		var brick_x := patch_x - 0.43 + float(column) * 0.40 + (0.18 if row % 2 == 1 else 0.0)
		var brick_y := patch_y - 0.27 + float(row) * 0.27
		_add_visual_box(wall, "ExposedBrick%02d" % index, Vector3(0.34, 0.17, 0.075), Vector3(brick_x, brick_y, face_z + exterior_sign * 0.045), Vector3(0.0, 0.0, float((index % 3) - 1) * 2.5), brick_object)


static func _add_downspout(wall: Node3D, wall_size: Vector3, exterior_sign: float, source: Dictionary) -> void:
	var pipe_object := _building_part_object(source, "downspout", Color("3d4646"), "default")
	var pipe := MeshInstance3D.new()
	pipe.name = "Downspout"
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.045
	mesh.bottom_radius = 0.052
	mesh.height = wall_size.y * 0.88
	mesh.radial_segments = 8
	pipe.mesh = mesh
	pipe.position = Vector3(wall_size.x * 0.43, -wall_size.y * 0.04, exterior_sign * (wall_size.z * 0.5 + 0.075))
	pipe.material_override = _material_for_object(pipe_object)
	wall.add_child(pipe)
	_add_visual_box(wall, "RoofGutter", Vector3(wall_size.x * 0.94, 0.08, 0.09), Vector3(0.0, wall_size.y * 0.47, exterior_sign * (wall_size.z * 0.5 + 0.075)), Vector3.ZERO, pipe_object)


static func _add_visual_box(parent: Node3D, name_value: String, size: Vector3, position: Vector3, rotation: Vector3, source: Dictionary) -> void:
	var visual := MeshInstance3D.new()
	visual.name = name_value
	var mesh := BoxMesh.new()
	mesh.size = size
	visual.mesh = mesh
	visual.position = position
	visual.rotation_degrees = rotation
	visual.material_override = _material_for_object(source)
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	parent.add_child(visual)


static func _build_wooden_crate(object: Dictionary) -> Node3D:
	var body := StaticBody3D.new()
	body.name = String(object.get("name", "Climbable Timber Crate")).validate_node_name()
	body.position = MapDocument.data_to_vector(object.get("position", {}))
	body.rotation_degrees = MapDocument.data_to_vector(object.get("rotation_degrees", {}))
	_set_object_meta(body, object)
	var size := MapDocument.data_to_vector(object.get("size", {}), Vector3(1.4, 0.55, 1.4))
	var properties: Dictionary = object.get("properties", {})
	var texture_path := String(properties.get("texture_path", ""))

	var panel_object := object.duplicate(true)
	_apply_authored_surface_texture(panel_object, texture_path, float(properties.get("uv_scale", 0.62)), 0.04, Color("aaa08e"))
	var panel := MeshInstance3D.new()
	panel.name = "WoodPlankBody"
	var panel_mesh := BoxMesh.new()
	panel_mesh.size = size * Vector3(0.90, 0.82, 0.90)
	panel.mesh = panel_mesh
	panel.material_override = _material_for_object(panel_object)
	body.add_child(panel)

	var brace_object := _building_part_object(object, "crate_brace", Color("392b24"), "default")
	_apply_authored_surface_texture(brace_object, texture_path, 0.48, 0.12, Color("817665"))
	var post_size := Vector3(0.11, size.y * 0.96, 0.11)
	for x_sign in [-1.0, 1.0]:
		for z_sign in [-1.0, 1.0]:
			_add_visual_box(
				body, "CornerPost%s%s" % ["L" if x_sign < 0.0 else "R", "F" if z_sign < 0.0 else "B"],
				post_size, Vector3(x_sign * size.x * 0.44, 0.0, z_sign * size.z * 0.44),
				Vector3.ZERO, brace_object
			)
	for y_sign in [-1.0, 1.0]:
		for z_sign in [-1.0, 1.0]:
			_add_visual_box(
				body, "FaceRail%s%s" % ["Top" if y_sign > 0.0 else "Bottom", "Front" if z_sign < 0.0 else "Back"],
				Vector3(size.x * 0.86, 0.10, 0.09),
				Vector3(0.0, y_sign * size.y * 0.39, z_sign * size.z * 0.455),
				Vector3.ZERO, brace_object
			)
	var diagonal_length := Vector2(size.x * 0.72, size.y * 0.60).length()
	var diagonal_angle := rad_to_deg(atan2(size.y * 0.60, size.x * 0.72))
	for z_sign in [-1.0, 1.0]:
		_add_visual_box(
			body, "DiagonalBrace%s" % ("Front" if z_sign < 0.0 else "Back"),
			Vector3(diagonal_length, 0.085, 0.075),
			Vector3(0.0, 0.0, z_sign * size.z * 0.465),
			Vector3(0.0, 0.0, diagonal_angle * z_sign), brace_object
		)

	var collision := CollisionShape3D.new()
	collision.name = "CollisionShape3D"
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	return body


static func _build_utility_pole(object: Dictionary) -> Node3D:
	var body := StaticBody3D.new()
	body.name = String(object.get("name", "Utility Pole Assembly")).validate_node_name()
	body.position = MapDocument.data_to_vector(object.get("position", {}))
	body.rotation_degrees = MapDocument.data_to_vector(object.get("rotation_degrees", {}))
	_set_object_meta(body, object)
	var size := MapDocument.data_to_vector(object.get("size", {}), Vector3(0.24, 7.6, 0.24))
	var properties: Dictionary = object.get("properties", {})
	var pole_object := _building_part_object(object, "pole", MapDocument.data_to_color(object.get("color", {}), Color("4b362d")), "default")
	var trunk := MeshInstance3D.new()
	trunk.name = "TaperedTimberPole"
	var trunk_mesh := CylinderMesh.new()
	trunk_mesh.top_radius = size.x * 0.38
	trunk_mesh.bottom_radius = size.x * 0.52
	trunk_mesh.height = size.y
	trunk_mesh.radial_segments = 10
	trunk.mesh = trunk_mesh
	trunk.material_override = _material_for_object(pole_object)
	body.add_child(trunk)
	var crossbar_width := clampf(float(properties.get("crossbar_width", 1.4)), 0.8, 2.4)
	_add_visual_box(body, "Crossbar", Vector3(crossbar_width, 0.13, 0.16), Vector3(0.0, size.y * 0.43, 0.0), Vector3.ZERO, pole_object)
	var insulator_object := _building_part_object(object, "insulator", Color("a9b8b2"), "default")
	for index in 3:
		var insulator := MeshInstance3D.new()
		insulator.name = "Insulator%d" % index
		var insulator_mesh := SphereMesh.new()
		insulator_mesh.radius = 0.085
		insulator_mesh.height = 0.17
		insulator_mesh.radial_segments = 8
		insulator_mesh.rings = 4
		insulator.mesh = insulator_mesh
		insulator.position = Vector3((float(index) - 1.0) * crossbar_width * 0.36, size.y * 0.43 + 0.14, 0.0)
		insulator.material_override = _material_for_object(insulator_object)
		body.add_child(insulator)
	var collision := CollisionShape3D.new()
	collision.name = "CollisionShape3D"
	var shape := CylinderShape3D.new()
	shape.radius = size.x * 0.52
	shape.height = size.y
	collision.shape = shape
	body.add_child(collision)
	return body


static func _build_cable_curve(object: Dictionary, editor_preview: bool) -> Node3D:
	var root := StaticBody3D.new()
	root.name = String(object.get("name", "Overhead Cable Curve")).validate_node_name()
	root.position = MapDocument.data_to_vector(object.get("position", {}))
	root.rotation_degrees = MapDocument.data_to_vector(object.get("rotation_degrees", {}))
	_set_object_meta(root, object)
	var properties: Dictionary = object.get("properties", {})
	var raw_points: Array = properties.get("points", [])
	if raw_points.size() < 4:
		return root
	var points: Array[Vector3] = []
	for point: Variant in raw_points:
		points.append(MapDocument.data_to_vector(point))
	if editor_preview:
		var minimum := points[0]
		var maximum := points[0]
		for point: Vector3 in points:
			minimum = minimum.min(point)
			maximum = maximum.max(point)
		var selection := CollisionShape3D.new()
		selection.name = "EditorSelectionCollision"
		var selection_shape := BoxShape3D.new()
		selection_shape.size = Vector3(
			maxf(maximum.x - minimum.x, 0.20),
			maxf(maximum.y - minimum.y, 0.20),
			maxf(maximum.z - minimum.z, 0.20)
		)
		selection.shape = selection_shape
		selection.position = (minimum + maximum) * 0.5
		root.add_child(selection)
	var radius := clampf(float(properties.get("radius", 0.018)), 0.008, 0.05)
	var segment_count := clampi(int(properties.get("segment_count", 12)), 6, 24)
	var cable_object := _building_part_object(object, "cable", MapDocument.data_to_color(object.get("color", {}), Color("20262a")), "default")
	var previous := points[0]
	for index in segment_count:
		var t := float(index + 1) / float(segment_count)
		var inverse := 1.0 - t
		var current := (
			points[0] * inverse * inverse * inverse
			+ points[1] * 3.0 * inverse * inverse * t
			+ points[2] * 3.0 * inverse * t * t
			+ points[3] * t * t * t
		)
		_add_cylinder_between(root, "CableSegment%02d" % index, previous, current, radius, cable_object)
		previous = current
	return root


static func _add_cylinder_between(parent: Node3D, name_value: String, start: Vector3, finish: Vector3, radius: float, source: Dictionary) -> void:
	var direction := finish - start
	var length := direction.length()
	if length <= 0.001:
		return
	var visual := MeshInstance3D.new()
	visual.name = name_value
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = length
	mesh.radial_segments = 6
	visual.mesh = mesh
	visual.position = (start + finish) * 0.5
	visual.quaternion = Quaternion(Vector3.UP, direction.normalized())
	visual.material_override = _material_for_object(source)
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(visual)


static func _build_breached_wall(object: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = String(object.get("name", "Breached Wall")).validate_node_name()
	root.position = MapDocument.data_to_vector(object.get("position", {}))
	root.rotation_degrees = MapDocument.data_to_vector(object.get("rotation_degrees", {}))
	_set_object_meta(root, object)
	var size := MapDocument.data_to_vector(object.get("size", {}), Vector3(6.0, 3.0, 0.45))
	var properties: Dictionary = object.get("properties", {})
	var hole_width := clampf(float(properties.get("hole_width", 1.8)), 0.7, maxf(size.x - 0.6, 0.7))
	var hole_height := clampf(float(properties.get("hole_height", 1.55)), 0.7, maxf(size.y - 0.4, 0.7))
	var hole_bottom := clampf(float(properties.get("hole_bottom", 0.55)), 0.0, maxf(size.y - hole_height - 0.15, 0.0))
	var max_offset := maxf((size.x - hole_width) * 0.5 - 0.3, 0.0)
	var hole_offset := clampf(float(properties.get("hole_offset_x", 0.0)), -max_offset, max_offset)
	var left_edge := hole_offset - hole_width * 0.5
	var right_edge := hole_offset + hole_width * 0.5
	var left_width := left_edge + size.x * 0.5
	var right_width := size.x * 0.5 - right_edge
	if left_width > 0.1:
		_add_compound_box(root, "BrokenLeftPier", Vector3(left_width, size.y, size.z), Vector3(-size.x * 0.5 + left_width * 0.5, 0.0, 0.0), object)
	if right_width > 0.1:
		_add_compound_box(root, "BrokenRightPier", Vector3(right_width, size.y, size.z), Vector3(size.x * 0.5 - right_width * 0.5, 0.0, 0.0), object)
	if hole_bottom > 0.1:
		_add_compound_box(
			root,
			"BrokenSill",
			Vector3(hole_width, hole_bottom, size.z),
			Vector3(hole_offset, -size.y * 0.5 + hole_bottom * 0.5, 0.0),
			object
		)
	var header_height := size.y - hole_bottom - hole_height
	if header_height > 0.1:
		_add_compound_box(
			root,
			"BrokenHeader",
			Vector3(hole_width, header_height, size.z),
			Vector3(hole_offset, size.y * 0.5 - header_height * 0.5, 0.0),
			object
		)
	var fragment_size := Vector3(minf(hole_width * 0.16, 0.35), minf(hole_height * 0.22, 0.38), size.z * 1.08)
	for side in [-1.0, 1.0]:
		var fragment := StaticBody3D.new()
		fragment.name = "BrokenEdgeFragment%s" % ("Left" if side < 0.0 else "Right")
		fragment.position = Vector3(hole_offset + side * hole_width * 0.46, -size.y * 0.5 + hole_bottom + hole_height * 0.48, 0.0)
		fragment.rotation_degrees.z = side * 16.0
		_set_object_meta(fragment, object)
		_add_box_parts(fragment, fragment_size, object)
		root.add_child(fragment)
	return root


static func _build_stairs(object: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = String(object.get("name", "Stairs")).validate_node_name()
	root.position = MapDocument.data_to_vector(object.get("position", {}))
	root.rotation_degrees = MapDocument.data_to_vector(object.get("rotation_degrees", {}))
	_set_object_meta(root, object)
	var size := MapDocument.data_to_vector(object.get("size", {}), Vector3(3.0, 2.5, 5.0))
	var properties: Dictionary = object.get("properties", {})
	var step_count := clampi(int(properties.get("steps", 10)), 3, 24)
	var tread_depth := size.z / float(step_count)
	var step_height := size.y / float(step_count)
	for index in step_count:
		var height := step_height * float(index + 1)
		var step_size := Vector3(size.x, height, tread_depth)
		var z := size.z * 0.5 - tread_depth * (float(index) + 0.5)
		var y := -size.y * 0.5 + height * 0.5
		_add_visual_box(
			root,
			"Step%02d" % index,
			step_size,
			Vector3(0.0, y, z),
			Vector3.ZERO,
			object
		)
	# The authored treads remain visual. One continuous convex surface owns
	# gameplay collision, so CharacterBody3D can climb without a second movement
	# solver and bullets/camera still query one deterministic map collider.
	var traversal_ramp := StaticBody3D.new()
	traversal_ramp.name = "TraversalRamp"
	_set_object_meta(traversal_ramp, object)
	var collision := CollisionShape3D.new()
	collision.name = "CollisionShape3D"
	var shape := ConvexPolygonShape3D.new()
	shape.points = _wedge_points(size)
	collision.shape = shape
	traversal_ramp.add_child(collision)
	root.add_child(traversal_ramp)
	return root


static func _build_round_primitive(object: Dictionary, sphere: bool) -> Node3D:
	var body := StaticBody3D.new()
	body.name = String(object.get("name", "Freeform Sphere" if sphere else "Freeform Cylinder")).validate_node_name()
	body.position = MapDocument.data_to_vector(object.get("position", {}))
	body.rotation_degrees = MapDocument.data_to_vector(object.get("rotation_degrees", {}))
	_set_object_meta(body, object)
	var size := MapDocument.data_to_vector(object.get("size", {}), Vector3(2.0, 2.0, 2.0))
	var visual := MeshInstance3D.new()
	visual.name = "Visual"
	if sphere:
		var mesh := SphereMesh.new()
		mesh.radius = 1.0
		mesh.height = 2.0
		visual.mesh = mesh
		visual.scale = size * 0.5
	else:
		var mesh := CylinderMesh.new()
		mesh.top_radius = 0.5
		mesh.bottom_radius = 0.5
		mesh.height = 1.0
		mesh.radial_segments = 24
		visual.mesh = mesh
		visual.scale = size
	visual.material_override = _material_for_object(object)
	body.add_child(visual)
	var collision := CollisionShape3D.new()
	collision.name = "CollisionShape3D"
	if sphere:
		var shape := SphereShape3D.new()
		shape.radius = maxf(size.x, maxf(size.y, size.z)) * 0.5
		collision.shape = shape
	else:
		var shape := CylinderShape3D.new()
		shape.radius = maxf(size.x, size.z) * 0.5
		shape.height = size.y
		collision.shape = shape
	body.add_child(collision)
	return body


static func _add_compound_box(parent: Node3D, part_name: String, size: Vector3, position: Vector3, object: Dictionary) -> void:
	var body := StaticBody3D.new()
	body.name = part_name
	body.position = position
	_set_object_meta(body, object)
	_add_box_parts(body, size, object)
	parent.add_child(body)


static func _build_objective_marker(object: Dictionary, editor_preview: bool) -> Node3D:
	var marker := StaticBody3D.new()
	var type_name := StringName(object.get("type", ""))
	marker.name = String(object.get("name", type_name)).validate_node_name()
	marker.position = MapDocument.data_to_vector(object.get("position", {}))
	marker.rotation_degrees = MapDocument.data_to_vector(object.get("rotation_degrees", {}))
	marker.set_meta("map_object_id", String(object.get("id", "")))
	marker.set_meta("map_object_type", type_name)
	marker.set_meta("socom_objective", true)
	var size := MapDocument.data_to_vector(object.get("size", {}), Vector3.ONE)
	if type_name in [&"alpha_bomb_site", &"bravo_bomb_site"]:
		_add_painted_bomb_site(marker, size, "A" if type_name == &"alpha_bomb_site" else "B")
	if not editor_preview:
		return marker
	if type_name == &"bomb_pickup":
		var bomb_preview := DemolitionBombScene.instantiate() as Node3D
		bomb_preview.name = "BombPickupPreview"
		marker.add_child(bomb_preview)
	_add_translucent_box(marker, size, MapDocument.data_to_color(object.get("color", {})), 0.46)
	var collision := CollisionShape3D.new()
	collision.name = "CollisionShape3D"
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	marker.add_child(collision)
	return marker


static func _add_painted_bomb_site(marker: Node3D, size: Vector3, site_letter: String) -> void:
	var radius := maxf(minf(size.x, size.z) * 0.43, 0.65)
	var paint := StandardMaterial3D.new()
	paint.albedo_color = Color(0.57, 0.20, 0.10, 0.88)
	paint.roughness = 0.98
	paint.metallic = 0.0
	paint.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	for index in 16:
		var angle := TAU * float(index) / 16.0
		var segment := MeshInstance3D.new()
		segment.name = "PaintRing%02d" % index
		var segment_mesh := BoxMesh.new()
		segment_mesh.size = Vector3(radius * 0.38, 0.018, maxf(radius * 0.09, 0.08))
		segment.mesh = segment_mesh
		segment.position = Vector3(cos(angle) * radius, 0.018, sin(angle) * radius)
		segment.rotation.y = -angle
		segment.material_override = paint
		marker.add_child(segment)
	for angle_degrees in [-45.0, 45.0]:
		var slash := MeshInstance3D.new()
		slash.name = "PaintSlash"
		var slash_mesh := BoxMesh.new()
		slash_mesh.size = Vector3(radius * 1.08, 0.021, maxf(radius * 0.11, 0.10))
		slash.mesh = slash_mesh
		slash.position.y = 0.021
		slash.rotation_degrees.y = angle_degrees
		slash.material_override = paint
		marker.add_child(slash)
	var label := Label3D.new()
	label.name = "BombSiteLetter"
	label.text = site_letter
	label.position = Vector3(0.0, 0.035, 0.0)
	label.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	label.font_size = 96
	label.modulate = Color(0.67, 0.27, 0.13, 0.92)
	label.outline_size = 8
	label.outline_modulate = Color(0.20, 0.09, 0.05, 0.72)
	label.fixed_size = true
	label.pixel_size = radius / 185.0
	marker.add_child(label)


static func _build_training_marker(object: Dictionary, editor_preview: bool) -> Node3D:
	var marker := StaticBody3D.new()
	var type_name := StringName(object.get("type", "training_dummy"))
	marker.name = String(object.get("name", type_name)).validate_node_name()
	marker.position = MapDocument.data_to_vector(object.get("position", {}))
	marker.rotation_degrees = MapDocument.data_to_vector(object.get("rotation_degrees", {}))
	_set_object_meta(marker, object)
	marker.set_meta("training_target", true)
	if not editor_preview:
		return marker
	var visual := MeshInstance3D.new()
	visual.name = "Visual"
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.38
	capsule.height = 1.8
	visual.mesh = capsule
	visual.position.y = 0.9
	var material := StandardMaterial3D.new()
	material.albedo_color = MapDocument.data_to_color(object.get("color", {}), Color("f39a55"))
	material.roughness = 0.8
	visual.material_override = material
	marker.add_child(visual)
	var collision := CollisionShape3D.new()
	collision.name = "CollisionShape3D"
	var shape := CapsuleShape3D.new()
	shape.radius = 0.38
	shape.height = 1.8
	collision.shape = shape
	collision.position.y = 0.9
	marker.add_child(collision)
	var label := Label3D.new()
	label.text = "MOVING" if type_name == &"moving_training_dummy" else "STATIC"
	label.position.y = 2.15
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 22
	label.modulate = material.albedo_color
	marker.add_child(label)
	if type_name == &"moving_training_dummy":
		var properties: Dictionary = object.get("properties", {})
		var distance := clampf(float(properties.get("patrol_distance", 6.0)), 0.5, 50.0)
		var path := MeshInstance3D.new()
		path.name = "PatrolPath"
		var path_mesh := BoxMesh.new()
		path_mesh.size = Vector3(distance, 0.035, 0.08)
		path.mesh = path_mesh
		path.position.y = 0.04
		var path_material := StandardMaterial3D.new()
		path_material.albedo_color = Color(0.2, 0.95, 1.0, 0.75)
		path_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		path_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		path.material_override = path_material
		marker.add_child(path)
	return marker


static func _build_tree(object: Dictionary, pine: bool) -> Node3D:
	var body := StaticBody3D.new()
	body.name = String(object.get("name", "Pine Tree" if pine else "Broadleaf Tree")).validate_node_name()
	body.position = MapDocument.data_to_vector(object.get("position", {}))
	body.rotation_degrees = MapDocument.data_to_vector(object.get("rotation_degrees", {}))
	_set_object_meta(body, object)
	var size := MapDocument.data_to_vector(object.get("size", {}), Vector3(3.5, 7.0, 3.5))
	var properties: Dictionary = object.get("properties", {})
	var layers := clampi(int(properties.get("canopy_layers", 3)), 1, 6)
	var trunk_ratio := clampf(float(properties.get("trunk_ratio", 0.42)), 0.2, 0.7)
	var seed_value := int(properties.get("variation_seed", 0))
	if seed_value == 0:
		seed_value = absi(String(object.get("id", "tree")).hash()) % 10007
	var horizontal_size := maxf(minf(size.x, size.z), 0.4)
	var trunk_height := maxf(size.y * trunk_ratio, 0.3)
	var trunk_radius := maxf(horizontal_size * (0.075 + absf(_asset_noise(seed_value, 2)) * 0.025), 0.08)

	var trunk := MeshInstance3D.new()
	trunk.name = "TrunkVisual"
	var trunk_mesh := CylinderMesh.new()
	trunk_mesh.top_radius = trunk_radius * 0.78
	trunk_mesh.bottom_radius = trunk_radius
	trunk_mesh.height = trunk_height
	trunk_mesh.radial_segments = 8
	trunk.mesh = trunk_mesh
	trunk.position.y = trunk_height * 0.5
	trunk.material_override = _tree_texture_material("bark", TREE_BARK_TEXTURE_PATH)
	body.add_child(trunk)

	var crown_bottom := trunk_height * 0.62
	var crown_height := maxf(size.y - crown_bottom, 0.35)
	for index in layers:
		var layer_t := (float(index) + 0.5) / float(layers)
		var layer_noise := _asset_noise(seed_value, 20 + index)
		var foliage := MeshInstance3D.new()
		foliage.name = "Foliage%02d" % index
		if pine:
			var cone := CylinderMesh.new()
			var taper := 1.0 - layer_t * 0.52
			cone.top_radius = 0.0
			cone.bottom_radius = maxf(horizontal_size * 0.5 * taper * (1.0 + layer_noise * 0.08), 0.15)
			cone.height = crown_height * minf(0.68, 1.3 / float(layers))
			cone.radial_segments = 9
			foliage.mesh = cone
		else:
			var sphere := SphereMesh.new()
			sphere.radius = maxf(horizontal_size * (0.25 + 0.08 * (1.0 - absf(layer_t - 0.5) * 2.0)), 0.15)
			sphere.height = maxf(crown_height * minf(0.72, 1.25 / float(layers)), 0.25)
			sphere.radial_segments = 10
			sphere.rings = 6
			foliage.mesh = sphere
		foliage.position = Vector3(
			layer_noise * horizontal_size * 0.075,
			crown_bottom + crown_height * layer_t,
			_asset_noise(seed_value, 40 + index) * horizontal_size * 0.075
		)
		foliage.material_override = _tree_texture_material(
			"pine_foliage" if pine else "broadleaf_foliage",
			PINE_FOLIAGE_TEXTURE_PATH if pine else BROADLEAF_FOLIAGE_TEXTURE_PATH
		)
		body.add_child(foliage)

	var collision := CollisionShape3D.new()
	collision.name = "CollisionShape3D"
	var trunk_shape := CylinderShape3D.new()
	trunk_shape.radius = trunk_radius
	trunk_shape.height = trunk_height
	collision.shape = trunk_shape
	collision.position.y = trunk_height * 0.5
	body.add_child(collision)
	return body


static func _build_bush(object: Dictionary, editor_preview: bool) -> Node3D:
	var body := StaticBody3D.new()
	body.name = String(object.get("name", "Concealment Bush")).validate_node_name()
	body.position = MapDocument.data_to_vector(object.get("position", {}))
	body.rotation_degrees = MapDocument.data_to_vector(object.get("rotation_degrees", {}))
	_set_object_meta(body, object)
	body.set_meta("concealment_asset", true)
	body.set_meta("blocks_movement", false)
	var size := MapDocument.data_to_vector(object.get("size", {}), Vector3(3.4, 2.1, 2.8))
	var properties: Dictionary = object.get("properties", {})
	var cluster_count := clampi(int(properties.get("cluster_count", 7)), 3, 14)
	var seed_value := int(properties.get("variation_seed", 0))
	if seed_value == 0:
		seed_value = absi(String(object.get("id", "bush")).hash()) % 10007
	var foliage_material := _tree_texture_material("bush_foliage", BROADLEAF_FOLIAGE_TEXTURE_PATH)
	for index in cluster_count:
		var angle := TAU * float(index) / float(cluster_count) + _asset_noise(seed_value, index + 3) * 0.55
		var ring := 0.16 + 0.30 * float(index % 3) / 2.0
		var lobe := MeshInstance3D.new()
		lobe.name = "Foliage%02d" % index
		var sphere := SphereMesh.new()
		var width_scale := 0.30 + absf(_asset_noise(seed_value, index + 20)) * 0.10
		var lobe_radius := maxf(minf(size.x, size.z) * width_scale, 0.22)
		sphere.radius = lobe_radius
		sphere.height = maxf(size.y * (0.62 + absf(_asset_noise(seed_value, index + 40)) * 0.22), 0.35)
		sphere.radial_segments = 10
		sphere.rings = 7
		lobe.mesh = sphere
		lobe.scale = Vector3(maxf(size.x / maxf(size.z, 0.01), 0.55), 1.0, 1.0)
		lobe.position = Vector3(
			cos(angle) * size.x * ring,
			size.y * (0.38 + absf(_asset_noise(seed_value, index + 60)) * 0.18),
			sin(angle) * size.z * ring
		)
		lobe.material_override = foliage_material
		body.add_child(lobe)
	# Selection needs a volume in Map Lab, while gameplay bushes intentionally
	# remain penetrable so they provide concealment instead of hard cover.
	if editor_preview or bool(properties.get("collision_enabled", false)):
		var selection_collision := CollisionShape3D.new()
		selection_collision.name = "EditorSelectionCollision" if editor_preview else "CollisionShape3D"
		var selection_shape := BoxShape3D.new()
		selection_shape.size = Vector3(size.x, maxf(size.y, 0.25), size.z)
		selection_collision.shape = selection_shape
		selection_collision.position.y = size.y * 0.5
		body.add_child(selection_collision)
	return body


static func _apply_collision_policy(node: Node3D, object: Dictionary, editor_preview: bool) -> void:
	if editor_preview:
		return
	var properties: Dictionary = object.get("properties", {})
	var default_enabled := String(object.get("type", "")) != "bush"
	if bool(properties.get("collision_enabled", default_enabled)):
		return
	for found: Node in node.find_children("*", "CollisionShape3D", true, false):
		(found as CollisionShape3D).disabled = true
	if node is CollisionObject3D:
		(node as CollisionObject3D).collision_layer = 0
		(node as CollisionObject3D).collision_mask = 0


static func _build_rocky_mountain(object: Dictionary) -> Node3D:
	var body := StaticBody3D.new()
	body.name = String(object.get("name", "Rocky Mountain")).validate_node_name()
	body.position = MapDocument.data_to_vector(object.get("position", {}))
	body.rotation_degrees = MapDocument.data_to_vector(object.get("rotation_degrees", {}))
	_set_object_meta(body, object)
	var size := MapDocument.data_to_vector(object.get("size", {}), Vector3(18.0, 12.0, 18.0))
	var properties: Dictionary = object.get("properties", {})
	var segments := clampi(int(properties.get("ridge_segments", 12)), 6, 32)
	var roughness := clampf(float(properties.get("roughness_amount", 0.22)), 0.0, 0.45)
	var peak_offset := Vector2(
		clampf(float(properties.get("peak_offset_x", 0.0)), -0.4, 0.4) * size.x,
		clampf(float(properties.get("peak_offset_z", 0.0)), -0.4, 0.4) * size.z
	)
	var seed_value := int(properties.get("variation_seed", 0))
	if seed_value == 0:
		seed_value = absi(String(object.get("id", "mountain")).hash()) % 10007
	var geometry := _mountain_geometry(size, segments, roughness, peak_offset, seed_value)
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "Visual"
	mesh_instance.mesh = geometry.get("mesh") as ArrayMesh
	var material := _material_for_object(object)
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh_instance.material_override = material
	body.add_child(mesh_instance)
	var collision := CollisionShape3D.new()
	collision.name = "CollisionShape3D"
	var shape := ConvexPolygonShape3D.new()
	shape.points = geometry.get("points") as PackedVector3Array
	collision.shape = shape
	body.add_child(collision)
	return body


static func _build_imported_asset(object: Dictionary, editor_preview: bool) -> Node3D:
	var body := StaticBody3D.new()
	body.name = String(object.get("name", "Imported Community Asset")).validate_node_name()
	body.position = MapDocument.data_to_vector(object.get("position", {}))
	body.rotation_degrees = MapDocument.data_to_vector(object.get("rotation_degrees", {}))
	_set_object_meta(body, object)
	var size := MapDocument.data_to_vector(object.get("size", {}), Vector3.ONE)
	var properties: Dictionary = object.get("properties", {})
	var asset_path := String(properties.get("asset_path", ""))
	var load_result := MapAssetLibrary.instantiate_asset(asset_path)
	if not bool(load_result.get("ok", false)):
		if editor_preview:
			_add_missing_asset_placeholder(body, size, String(load_result.get("message", "Missing GLB")))
		return body
	var content := load_result.get("scene") as Node3D
	content.name = "ImportedContent"
	body.add_child(content)
	var original_bounds := _combined_mesh_bounds(content)
	content.scale = size
	var collision_mode := String(properties.get("collision_mode", "box"))
	if editor_preview or collision_mode == "box":
		var collision := CollisionShape3D.new()
		collision.name = "EditorSelectionCollision" if editor_preview else "CollisionShape3D"
		var shape := BoxShape3D.new()
		var scaled_bounds_size := Vector3(
			maxf(original_bounds.size.x * absf(size.x), 0.1),
			maxf(original_bounds.size.y * absf(size.y), 0.1),
			maxf(original_bounds.size.z * absf(size.z), 0.1)
		)
		shape.size = scaled_bounds_size
		collision.shape = shape
		collision.position = Vector3(
			(original_bounds.position.x + original_bounds.size.x * 0.5) * size.x,
			(original_bounds.position.y + original_bounds.size.y * 0.5) * size.y,
			(original_bounds.position.z + original_bounds.size.z * 0.5) * size.z
		)
		body.add_child(collision)
	elif collision_mode == "detailed_mesh":
		for found: Node in content.find_children("*", "MeshInstance3D", true, false):
			var mesh_instance := found as MeshInstance3D
			if mesh_instance.mesh != null:
				mesh_instance.create_trimesh_collision()
	return body


static func _combined_mesh_bounds(content: Node3D) -> AABB:
	var combined := AABB(Vector3.ZERO, Vector3.ONE)
	var has_bounds := false
	for found: Node in content.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := found as MeshInstance3D
		if mesh_instance.mesh == null:
			continue
		var source := mesh_instance.get_aabb()
		var relative_transform := _node_transform_relative_to(mesh_instance, content)
		for corner_index in 8:
			var corner := source.position + Vector3(
				source.size.x if (corner_index & 1) != 0 else 0.0,
				source.size.y if (corner_index & 2) != 0 else 0.0,
				source.size.z if (corner_index & 4) != 0 else 0.0
			)
			var point := relative_transform * corner
			if not has_bounds:
				combined = AABB(point, Vector3.ZERO)
				has_bounds = true
			else:
				combined = combined.expand(point)
	return combined if has_bounds else AABB(Vector3.ZERO, Vector3.ONE)


static func _node_transform_relative_to(node: Node3D, root: Node3D) -> Transform3D:
	var result := node.transform
	var parent := node.get_parent()
	while parent != null and parent != root:
		if parent is Node3D:
			result = (parent as Node3D).transform * result
		parent = parent.get_parent()
	return result


static func _add_missing_asset_placeholder(body: StaticBody3D, size: Vector3, message: String) -> void:
	var visual := MeshInstance3D.new()
	visual.name = "MissingAssetVisual"
	var mesh := BoxMesh.new()
	mesh.size = size
	visual.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.9, 0.12, 0.55, 0.78)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	visual.material_override = material
	body.add_child(visual)
	var collision := CollisionShape3D.new()
	collision.name = "EditorSelectionCollision"
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	var label := Label3D.new()
	label.name = "MissingAssetLabel"
	label.text = message
	label.position.y = maxf(size.y * 0.65, 0.8)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 28
	label.modulate = Color("ff77bd")
	body.add_child(label)


static func _mountain_geometry(
	size: Vector3,
	segments: int,
	roughness: float,
	peak_offset: Vector2,
	seed_value: int
) -> Dictionary:
	var ring_heights := [0.0, 0.42, 0.74]
	var ring_scales := [1.0, 0.64, 0.31]
	var rings: Array[PackedVector3Array] = []
	var collision_points := PackedVector3Array()
	for ring_index in ring_heights.size():
		var ring := PackedVector3Array()
		var height_t: float = ring_heights[ring_index]
		var radius_scale: float = ring_scales[ring_index]
		for segment_index in segments:
			var angle := TAU * float(segment_index) / float(segments)
			var noise := _asset_noise(seed_value + ring_index * 101, segment_index)
			var radius_noise := 1.0 + noise * roughness
			var point := Vector3(
				cos(angle) * size.x * 0.5 * radius_scale * radius_noise + peak_offset.x * height_t,
				size.y * height_t,
				sin(angle) * size.z * 0.5 * radius_scale * radius_noise + peak_offset.y * height_t
			)
			ring.append(point)
			collision_points.append(point)
		rings.append(ring)
	var peak := Vector3(peak_offset.x, size.y, peak_offset.y)
	collision_points.append(peak)
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for ring_index in rings.size() - 1:
		var lower := rings[ring_index]
		var upper := rings[ring_index + 1]
		for segment_index in segments:
			var next := (segment_index + 1) % segments
			_add_mountain_triangle(surface, lower[segment_index], upper[next], lower[next], size)
			_add_mountain_triangle(surface, lower[segment_index], upper[segment_index], upper[next], size)
	var top_ring := rings[rings.size() - 1]
	for segment_index in segments:
		var next := (segment_index + 1) % segments
		_add_mountain_triangle(surface, top_ring[segment_index], peak, top_ring[next], size)
	var base_center := Vector3.ZERO
	var base_ring := rings[0]
	for segment_index in segments:
		var next := (segment_index + 1) % segments
		_add_mountain_triangle(surface, base_center, base_ring[next], base_ring[segment_index], size)
	surface.generate_normals()
	return {"mesh": surface.commit(), "points": collision_points}


static func _add_mountain_triangle(
	surface: SurfaceTool,
	a: Vector3,
	b: Vector3,
	c: Vector3,
	size: Vector3
) -> void:
	for point in [a, b, c]:
		surface.set_uv(Vector2(point.x / maxf(size.x, 0.1) + 0.5, point.z / maxf(size.z, 0.1) + 0.5))
		surface.add_vertex(point)


static func _asset_noise(seed_value: int, index: int) -> float:
	return sin(float(seed_value * 17 + index * 73) * 0.11937)


static func _solid_material(color: Color, roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	return material


static func _build_wedge_ramp(object: Dictionary) -> Node3D:
	var body := StaticBody3D.new()
	body.name = String(object.get("name", "Ramp")).validate_node_name()
	body.position = MapDocument.data_to_vector(object.get("position", {}))
	body.rotation_degrees = MapDocument.data_to_vector(object.get("rotation_degrees", {}))
	_set_object_meta(body, object)
	var size := MapDocument.data_to_vector(object.get("size", {}), Vector3(3.0, 1.5, 5.0))
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "Visual"
	mesh_instance.mesh = _wedge_mesh(size)
	mesh_instance.material_override = _material_for_object(object)
	body.add_child(mesh_instance)
	var collision := CollisionShape3D.new()
	collision.name = "CollisionShape3D"
	var shape := ConvexPolygonShape3D.new()
	shape.points = _wedge_points(size)
	collision.shape = shape
	body.add_child(collision)
	return body


static func _build_curved_wall(object: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = String(object.get("name", "Curved Wall")).validate_node_name()
	root.position = MapDocument.data_to_vector(object.get("position", {}))
	root.rotation_degrees = MapDocument.data_to_vector(object.get("rotation_degrees", {}))
	_set_object_meta(root, object)
	var size := MapDocument.data_to_vector(object.get("size", {}), Vector3(5.0, 3.0, 0.35))
	var properties: Dictionary = object.get("properties", {})
	var radius := maxf(float(properties.get("radius", 4.0)), 0.5)
	var arc_degrees := clampf(float(properties.get("arc_degrees", 90.0)), 5.0, 330.0)
	var segments := clampi(int(properties.get("segments", 8)), 2, 48)
	var step_radians := deg_to_rad(arc_degrees / float(segments))
	var chord := maxf(2.0 * radius * sin(step_radians * 0.5), 0.1)
	for index in segments:
		var angle_degrees := -arc_degrees * 0.5 + (float(index) + 0.5) * arc_degrees / float(segments)
		var angle := deg_to_rad(angle_degrees)
		var segment := StaticBody3D.new()
		segment.name = "CurveSegment%02d" % index
		segment.position = Vector3(sin(angle) * radius, 0.0, cos(angle) * radius - radius)
		segment.rotation_degrees.y = angle_degrees
		_set_object_meta(segment, object)
		_add_box_parts(segment, Vector3(chord, size.y, size.z), object)
		root.add_child(segment)
	return root


static func _build_jagged_wall(object: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = String(object.get("name", "Broken Wall")).validate_node_name()
	root.position = MapDocument.data_to_vector(object.get("position", {}))
	root.rotation_degrees = MapDocument.data_to_vector(object.get("rotation_degrees", {}))
	_set_object_meta(root, object)
	var size := MapDocument.data_to_vector(object.get("size", {}), Vector3(5.0, 2.6, 0.45))
	var properties: Dictionary = object.get("properties", {})
	var pieces := clampi(int(properties.get("pieces", 6)), 2, 24)
	var variance := clampf(float(properties.get("height_variance", 0.8)), 0.0, size.y * 0.8)
	var edge_rotation := clampf(float(properties.get("edge_rotation", 5.0)), 0.0, 25.0)
	var piece_width := size.x / float(pieces)
	var seed_value: int = absi(String(object.get("id", "wall")).hash()) % 997
	for index in pieces:
		var noise := sin(float(seed_value + index * 37) * 0.731)
		var piece_height := maxf(0.25, size.y - absf(noise) * variance)
		var piece := StaticBody3D.new()
		piece.name = "BrokenPiece%02d" % index
		piece.position = Vector3(-size.x * 0.5 + piece_width * (float(index) + 0.5), -size.y * 0.5 + piece_height * 0.5, 0.0)
		piece.rotation_degrees.z = noise * edge_rotation
		_set_object_meta(piece, object)
		_add_box_parts(piece, Vector3(piece_width * 1.04, piece_height, size.z), object)
		root.add_child(piece)
	return root


static func _add_box_parts(body: StaticBody3D, size: Vector3, object: Dictionary) -> void:
	var visual := MeshInstance3D.new()
	visual.name = "Visual"
	var mesh := BoxMesh.new()
	mesh.size = size
	visual.mesh = mesh
	visual.material_override = _material_for_object(object)
	body.add_child(visual)
	var collision := CollisionShape3D.new()
	collision.name = "CollisionShape3D"
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)


static func _set_object_meta(node: Node, object: Dictionary) -> void:
	node.set_meta("map_object_id", String(object.get("id", "")))
	node.set_meta("map_object_type", StringName(object.get("type", "")))


static func _apply_camera_passage_policy(node: Node, object: Dictionary) -> void:
	var properties: Dictionary = object.get("properties", {})
	if not bool(properties.get("camera_soft_occluder", false)):
		return
	# This tag is consumed only by the rendered camera collision solver. The
	# object's ordinary physics layers continue blocking players and bullets.
	node.add_to_group("camera_soft_occluder")
	node.set_meta("camera_soft_occluder", true)


static func _material_for_object(object: Dictionary) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	var object_color := MapDocument.data_to_color(object.get("color", {}), Color("626973"))
	material.albedo_color = object_color
	var properties: Dictionary = object.get("properties", {})
	var painterly_v2 := bool(properties.get("painterly_material_v2", false))
	var painterly_material := bool(properties.get("painterly_material", false)) or painterly_v2
	if painterly_material:
		# Preserve broad painted color masses and a soft light boundary. This is a
		# material presentation choice only; collision and tactical visibility use
		# the same authored geometry as every other map.
		material.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT_WRAP
		material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	var surface_kind := String(properties.get("surface_kind", "default"))
	var type_name := StringName(object.get("type", ""))
	if not properties.has("surface_kind") and type_name in [
		&"wall", &"doorway_wall", &"window_wall", &"column",
		&"curved_wall", &"jagged_wall", &"breached_wall",
	]:
		surface_kind = "stucco"
	elif not properties.has("surface_kind") and type_name in [&"cover_low", &"cover_tall", &"platform", &"ramp", &"stairs", &"roof"]:
		surface_kind = "concrete"
	elif type_name == &"rocky_mountain" and surface_kind == "default":
		surface_kind = "rock"
	var preset: Dictionary = MapDocument.SURFACE_PRESETS.get(surface_kind, MapDocument.SURFACE_PRESETS["default"])
	material.roughness = 1.0 if painterly_v2 else clampf(float(properties.get("roughness", preset.get("roughness", 0.9))), 0.0, 1.0)
	material.metallic = clampf(float(properties.get("metallic", preset.get("metallic", 0.0))), 0.0, 1.0)
	var texture_path := String(properties.get("texture_path", ""))
	if texture_path.is_empty():
		texture_path = String(preset.get("texture_path", ""))
	var texture := _load_authored_texture(texture_path)
	if texture != null:
		material.albedo_texture = texture
		# V2 keeps the generated albedo's damaged linework and color variation.
		# A darker multiplier prevents sun and ACES exposure from bleaching it.
		var default_texture_multiplier := (
			Color("74716b") if painterly_v2
			else Color("85827d") if surface_kind == "rock"
			else Color("a8a59f")
		)
		var texture_multiplier := MapDocument.data_to_color(
			properties.get("texture_multiplier", {}), default_texture_multiplier
		)
		var default_tint_weight := 0.26 if painterly_v2 else (0.42 if painterly_material else 0.08)
		var tint_weight := clampf(float(properties.get("texture_tint_weight", default_tint_weight)), 0.0, 1.0)
		material.albedo_color = texture_multiplier.lerp(object_color, tint_weight)
		var uv_scale := maxf(float(properties.get("uv_scale", 1.0)), 0.01)
		material.uv1_scale = Vector3(uv_scale, uv_scale, uv_scale)
		material.uv1_triplanar = true
		material.uv1_world_triplanar = true
	else:
		if surface_kind != "default" and MapDocument.SURFACE_PRESETS.has(surface_kind):
			material.albedo_texture = _procedural_surface_texture(surface_kind)
			material.albedo_color = object_color.darkened(0.12) if surface_kind == "rock" else Color("c2c2bd").lerp(object_color, 0.18)
			var uv_scale := maxf(float(properties.get("uv_scale", 1.0)), 0.01)
			material.uv1_scale = Vector3(uv_scale, uv_scale, uv_scale)
			material.uv1_triplanar = true
			material.uv1_world_triplanar = true
	if surface_kind != "default" and MapDocument.SURFACE_PRESETS.has(surface_kind):
		material.normal_enabled = true
		material.normal_texture = _procedural_surface_normal(surface_kind)
		var default_normal_strength := (
			0.045 if painterly_v2
			else 0.12 if painterly_material
			else (0.24 if material.albedo_texture != null else 0.55)
		)
		material.normal_scale = clampf(float(properties.get("normal_strength", default_normal_strength)), 0.0, 2.0)
		material.roughness_texture = _procedural_surface_roughness(surface_kind)
		material.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	return material


static func _load_authored_texture(texture_path: String) -> Texture2D:
	if texture_path.is_empty():
		return null
	if authored_texture_cache.has(texture_path):
		return authored_texture_cache[texture_path] as Texture2D
	var texture: Texture2D = null
	if ResourceLoader.exists(texture_path):
		texture = load(texture_path) as Texture2D
	elif FileAccess.file_exists(texture_path):
		# A newly generated project asset can be visible before Godot creates its
		# import artifact. The raw-image fallback keeps first launch and script-mode
		# visual checks identical; subsequent runs use ResourceLoader above.
		var source_image := Image.new()
		if source_image.load(ProjectSettings.globalize_path(texture_path)) == OK:
			if not source_image.has_mipmaps():
				source_image.generate_mipmaps()
			texture = ImageTexture.create_from_image(source_image)
	if texture != null:
		authored_texture_cache[texture_path] = texture
	return texture


static func _tree_texture_material(cache_key: String, texture_path: String) -> StandardMaterial3D:
	if tree_material_cache.has(cache_key):
		return tree_material_cache[cache_key] as StandardMaterial3D
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("a8a59f")
	material.roughness = 0.98
	material.metallic = 0.0
	if ResourceLoader.exists(texture_path):
		material.albedo_texture = load(texture_path) as Texture2D
		material.uv1_scale = Vector3(1.35, 1.35, 1.35) if cache_key == "bark" else Vector3(1.8, 1.8, 1.8)
		material.uv1_triplanar = true
		material.uv1_world_triplanar = true
	if cache_key == "bush_foliage":
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.normal_enabled = true
	material.normal_texture = _procedural_surface_normal("rock" if cache_key == "bark" else "grass")
	material.normal_scale = 0.16 if cache_key == "bark" else 0.10
	tree_material_cache[cache_key] = material
	return material
static func _procedural_surface_texture(surface_kind: String) -> Texture2D:
	if surface_texture_cache.has(surface_kind):
		return surface_texture_cache[surface_kind] as Texture2D
	var image := Image.create(
		PROCEDURAL_DETAIL_SIZE,
		PROCEDURAL_DETAIL_SIZE,
		false,
		Image.FORMAT_RGBA8
	)
	for y in PROCEDURAL_DETAIL_SIZE:
		for x in PROCEDURAL_DETAIL_SIZE:
			var grain := _surface_noise(x, y, 17)
			var detail := _surface_noise(x, y, 83)
			var color := Color.WHITE
			if surface_kind == "stucco":
				var crack := 0.16 if ((x * 3 + y * 7 + int(grain * 11.0)) % 53) < 2 else 0.0
				color = Color(0.50 + grain * 0.15 - crack, 0.46 + detail * 0.13 - crack, 0.39 + grain * 0.10 - crack, 1.0)
			elif surface_kind == "muddy_limestone":
				color = Color(0.34 + grain * 0.15, 0.30 + detail * 0.12, 0.24 + grain * 0.09, 1.0)
			elif surface_kind == "grass":
				var blade := 0.08 if ((x * 7 + y * 13) % 29) < 3 else 0.0
				color = Color(0.14 + grain * 0.08, 0.25 + detail * 0.13 + blade, 0.11 + grain * 0.07, 1.0)
			elif surface_kind == "dirt":
				color = Color(0.32 + grain * 0.12, 0.25 + detail * 0.09, 0.18 + grain * 0.06, 1.0)
			elif surface_kind == "rock":
				var seam := 0.15 if ((x + y * 3 + int(grain * 9.0)) % 31) == 0 else 0.0
				color = Color(0.30 + grain * 0.14 - seam, 0.30 + detail * 0.12 - seam, 0.29 + grain * 0.10 - seam, 1.0)
			else:
				var joint := 0.10 if x % 32 == 0 or y % 32 == 0 else 0.0
				color = Color(0.42 + grain * 0.12 - joint, 0.43 + detail * 0.11 - joint, 0.44 + grain * 0.10 - joint, 1.0)
			image.set_pixel(x, y, color)
	var texture := ImageTexture.create_from_image(image)
	surface_texture_cache[surface_kind] = texture
	return texture


static func _procedural_surface_normal(surface_kind: String) -> Texture2D:
	if surface_normal_cache.has(surface_kind):
		return surface_normal_cache[surface_kind] as Texture2D
	var image := Image.create(
		PROCEDURAL_DETAIL_SIZE,
		PROCEDURAL_DETAIL_SIZE,
		false,
		Image.FORMAT_RGB8
	)
	var strength := 3.2 if surface_kind in ["rock", "muddy_limestone"] else 2.2
	for y in PROCEDURAL_DETAIL_SIZE:
		for x in PROCEDURAL_DETAIL_SIZE:
			var left := _surface_height(surface_kind, posmod(x - 1, PROCEDURAL_DETAIL_SIZE), y)
			var right := _surface_height(surface_kind, posmod(x + 1, PROCEDURAL_DETAIL_SIZE), y)
			var above := _surface_height(surface_kind, x, posmod(y - 1, PROCEDURAL_DETAIL_SIZE))
			var below := _surface_height(surface_kind, x, posmod(y + 1, PROCEDURAL_DETAIL_SIZE))
			var normal := Vector3((left - right) * strength, (above - below) * strength, 1.0).normalized()
			image.set_pixel(x, y, Color(normal.x * 0.5 + 0.5, normal.y * 0.5 + 0.5, normal.z * 0.5 + 0.5))
	var texture := ImageTexture.create_from_image(image)
	surface_normal_cache[surface_kind] = texture
	return texture


static func _procedural_surface_roughness(surface_kind: String) -> Texture2D:
	if surface_roughness_cache.has(surface_kind):
		return surface_roughness_cache[surface_kind] as Texture2D
	var image := Image.create(
		PROCEDURAL_DETAIL_SIZE,
		PROCEDURAL_DETAIL_SIZE,
		false,
		Image.FORMAT_R8
	)
	var base := 0.90 if surface_kind == "concrete" else 0.96
	for y in PROCEDURAL_DETAIL_SIZE:
		for x in PROCEDURAL_DETAIL_SIZE:
			var variation := (_surface_noise(x, y, 157) - 0.5) * 0.04
			var value := clampf(base + variation, 0.72, 1.0)
			image.set_pixel(x, y, Color(value, value, value))
	var texture := ImageTexture.create_from_image(image)
	surface_roughness_cache[surface_kind] = texture
	return texture


static func _surface_height(surface_kind: String, x: int, y: int) -> float:
	var broad := _surface_noise(x / 3, y / 3, 29)
	var fine := _surface_noise(x, y, 97)
	if surface_kind == "stucco":
		var crack := 0.8 if ((x * 3 + y * 7 + int(fine * 11.0)) % 53) < 2 else 0.0
		return broad * 0.55 + fine * 0.25 - crack
	if surface_kind == "grass":
		return broad * 0.35 + fine * 0.65
	if surface_kind in ["rock", "muddy_limestone"]:
		return broad * 0.72 + fine * 0.28
	var joint := 0.65 if x % 32 < 2 or y % 32 < 2 else 0.0
	return broad * 0.45 + fine * 0.25 - joint


static func _surface_noise(x: int, y: int, seed_value: int) -> float:
	# This runs tens of thousands of times while the first material set is
	# created. A deterministic integer mix preserves the authored grain without
	# paying for a trigonometric function on the playable build's first frame.
	var value: int = x * 374761393 + y * 668265263 + seed_value * 1442695041
	value = (value ^ (value >> 13)) * 1274126177
	value = value ^ (value >> 16)
	return float(value & 0x7fffffff) / 2147483647.0


static func _wedge_points(size: Vector3) -> PackedVector3Array:
	var hx := size.x * 0.5
	var hy := size.y * 0.5
	var hz := size.z * 0.5
	return PackedVector3Array([
		Vector3(-hx, -hy, -hz), Vector3(hx, -hy, -hz), Vector3(-hx, hy, -hz), Vector3(hx, hy, -hz),
		Vector3(-hx, -hy, hz), Vector3(hx, -hy, hz),
	])


static func _wedge_mesh(size: Vector3) -> ArrayMesh:
	var points := _wedge_points(size)
	var triangles := [
		0, 1, 3, 0, 3, 2,
		4, 5, 1, 4, 1, 0,
		2, 3, 5, 2, 5, 4,
		0, 2, 4,
		1, 5, 3,
	]
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for point_index: int in triangles:
		surface.set_uv(Vector2(points[point_index].x, points[point_index].z))
		surface.add_vertex(points[point_index])
	surface.generate_normals()
	return surface.commit()


static func _add_translucent_box(parent: Node3D, size: Vector3, color: Color, alpha: float) -> void:
	var visual := MeshInstance3D.new()
	visual.name = "Visual"
	var mesh := BoxMesh.new()
	mesh.size = size
	visual.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(color.r, color.g, color.b, alpha)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	visual.material_override = material
	parent.add_child(visual)
