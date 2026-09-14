class_name SocomMapRuntime
extends RefCounted

const MapDocument := preload("res://scripts/maps/socom_map_document.gd")
const FacadeBuilder := preload("res://scripts/maps/socom_map_facade_builder.gd")
const Materials := preload("res://scripts/maps/socom_map_surface_materials.gd")
const Geometry := preload("res://scripts/maps/socom_map_geometry.gd")
const ImportedAssetBuilder := preload("res://scripts/maps/socom_imported_map_asset_builder.gd")
const StairCollision := preload("res://scripts/maps/socom_stair_collision.gd")
const FogZoneController := preload("res://scripts/maps/socom_map_fog_zone_controller.gd")
const SwimmingVolume := preload("res://scripts/traversal/socom_swimming_volume.gd")
const DemolitionBombScene := preload("res://scenes/objectives/demolition_bomb.tscn")
const SAFETY_WALL_THICKNESS := 0.60
const SAFETY_WALL_MINIMUM_HEIGHT := 24.0
# The authored albedo maps carry the visible high-frequency detail. This small,
# filtered tile adds material depth/roughness without painting 128x128 maps in
# GDScript for every new surface family during the first playable frame.
const WALKABLE_SURFACE_TYPES: Array[StringName] = [&"ground", &"platform", &"ramp", &"roof", &"stairs"]
const PINE_FOLIAGE_TEXTURE_PATH := "res://assets/textures/environment/original_materials/pine_needles_albedo_v1.png"
const BROADLEAF_FOLIAGE_TEXTURE_PATH := "res://assets/textures/environment/original_materials/broadleaf_foliage_albedo_v1.png"
const TREE_BARK_TEXTURE_PATH := "res://assets/textures/environment/original_materials/pine_bark_albedo_v1.png"
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
		return FacadeBuilder._build_opening_wall(object, type_name == &"window_wall")
	if type_name == &"breached_wall":
		return _build_breached_wall(object)
	if type_name == &"stairs":
		return _build_stairs(object)
	if type_name in [&"primitive_cylinder", &"primitive_sphere"]:
		return _build_round_primitive(object, type_name == &"primitive_sphere")
	if type_name == &"favela_building":
		return FacadeBuilder._build_favela_building(object)
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
		return ImportedAssetBuilder.build(object, editor_preview)
	if type_name == &"ramp":
		return _build_wedge_ramp(object)
	if type_name in [&"training_dummy", &"moving_training_dummy"]:
		return _build_training_marker(object, editor_preview)
	var body := StaticBody3D.new()
	body.name = String(object.get("name", type_name)).validate_node_name()
	Geometry._set_object_meta(body, object)
	body.position = MapDocument.data_to_vector(object.get("position", {}))
	body.rotation_degrees = MapDocument.data_to_vector(object.get("rotation_degrees", {}))
	var size := MapDocument.data_to_vector(object.get("size", {}), Vector3.ONE)
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "Visual"
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh_instance.mesh = mesh
	mesh_instance.material_override = Materials._material_for_object(object)
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
	Geometry._set_object_meta(area, object)
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
	Geometry._set_object_meta(area, object)
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
			var broad := Materials._surface_noise(x / 4, y / 4, 211)
			var fine := Materials._surface_noise(x, y, 431)
			var opacity := clampf(0.28 + broad * 0.42 + fine * 0.18, 0.12, 0.88)
			image.set_pixel(x, y, Color(1.0, 1.0, 1.0, opacity))
	fog_noise_texture = ImageTexture.create_from_image(image)
	return fog_noise_texture


static func _build_wooden_crate(object: Dictionary) -> Node3D:
	var body := StaticBody3D.new()
	body.name = String(object.get("name", "Climbable Timber Crate")).validate_node_name()
	body.position = MapDocument.data_to_vector(object.get("position", {}))
	body.rotation_degrees = MapDocument.data_to_vector(object.get("rotation_degrees", {}))
	Geometry._set_object_meta(body, object)
	var size := MapDocument.data_to_vector(object.get("size", {}), Vector3(1.4, 0.55, 1.4))
	var properties: Dictionary = object.get("properties", {})
	var texture_path := String(properties.get("texture_path", ""))

	var panel_object := object.duplicate(true)
	FacadeBuilder._apply_authored_surface_texture(panel_object, texture_path, float(properties.get("uv_scale", 0.62)), 0.04, Color("aaa08e"))
	var panel := MeshInstance3D.new()
	panel.name = "WoodPlankBody"
	var panel_mesh := BoxMesh.new()
	panel_mesh.size = size * Vector3(0.90, 0.82, 0.90)
	panel.mesh = panel_mesh
	panel.material_override = Materials._material_for_object(panel_object)
	body.add_child(panel)

	var brace_object := FacadeBuilder._building_part_object(object, "crate_brace", Color("392b24"), "default")
	FacadeBuilder._apply_authored_surface_texture(brace_object, texture_path, 0.48, 0.12, Color("817665"))
	var post_size := Vector3(0.11, size.y * 0.96, 0.11)
	for x_sign in [-1.0, 1.0]:
		for z_sign in [-1.0, 1.0]:
			Geometry._add_visual_box(
				body, "CornerPost%s%s" % ["L" if x_sign < 0.0 else "R", "F" if z_sign < 0.0 else "B"],
				post_size, Vector3(x_sign * size.x * 0.44, 0.0, z_sign * size.z * 0.44),
				Vector3.ZERO, brace_object
			)
	for y_sign in [-1.0, 1.0]:
		for z_sign in [-1.0, 1.0]:
			Geometry._add_visual_box(
				body, "FaceRail%s%s" % ["Top" if y_sign > 0.0 else "Bottom", "Front" if z_sign < 0.0 else "Back"],
				Vector3(size.x * 0.86, 0.10, 0.09),
				Vector3(0.0, y_sign * size.y * 0.39, z_sign * size.z * 0.455),
				Vector3.ZERO, brace_object
			)
	var diagonal_length := Vector2(size.x * 0.72, size.y * 0.60).length()
	var diagonal_angle := rad_to_deg(atan2(size.y * 0.60, size.x * 0.72))
	for z_sign in [-1.0, 1.0]:
		Geometry._add_visual_box(
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
	Geometry._set_object_meta(body, object)
	var size := MapDocument.data_to_vector(object.get("size", {}), Vector3(0.24, 7.6, 0.24))
	var properties: Dictionary = object.get("properties", {})
	var pole_object := FacadeBuilder._building_part_object(object, "pole", MapDocument.data_to_color(object.get("color", {}), Color("4b362d")), "default")
	var trunk := MeshInstance3D.new()
	trunk.name = "TaperedTimberPole"
	var trunk_mesh := CylinderMesh.new()
	trunk_mesh.top_radius = size.x * 0.38
	trunk_mesh.bottom_radius = size.x * 0.52
	trunk_mesh.height = size.y
	trunk_mesh.radial_segments = 10
	trunk.mesh = trunk_mesh
	trunk.material_override = Materials._material_for_object(pole_object)
	body.add_child(trunk)
	var crossbar_width := clampf(float(properties.get("crossbar_width", 1.4)), 0.8, 2.4)
	Geometry._add_visual_box(body, "Crossbar", Vector3(crossbar_width, 0.13, 0.16), Vector3(0.0, size.y * 0.43, 0.0), Vector3.ZERO, pole_object)
	var insulator_object := FacadeBuilder._building_part_object(object, "insulator", Color("a9b8b2"), "default")
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
		insulator.material_override = Materials._material_for_object(insulator_object)
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
	Geometry._set_object_meta(root, object)
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
	var cable_object := FacadeBuilder._building_part_object(object, "cable", MapDocument.data_to_color(object.get("color", {}), Color("20262a")), "default")
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
	visual.material_override = Materials._material_for_object(source)
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(visual)


static func _build_breached_wall(object: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = String(object.get("name", "Breached Wall")).validate_node_name()
	root.position = MapDocument.data_to_vector(object.get("position", {}))
	root.rotation_degrees = MapDocument.data_to_vector(object.get("rotation_degrees", {}))
	Geometry._set_object_meta(root, object)
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
		Geometry._add_compound_box(root, "BrokenLeftPier", Vector3(left_width, size.y, size.z), Vector3(-size.x * 0.5 + left_width * 0.5, 0.0, 0.0), object)
	if right_width > 0.1:
		Geometry._add_compound_box(root, "BrokenRightPier", Vector3(right_width, size.y, size.z), Vector3(size.x * 0.5 - right_width * 0.5, 0.0, 0.0), object)
	if hole_bottom > 0.1:
		Geometry._add_compound_box(
			root,
			"BrokenSill",
			Vector3(hole_width, hole_bottom, size.z),
			Vector3(hole_offset, -size.y * 0.5 + hole_bottom * 0.5, 0.0),
			object
		)
	var header_height := size.y - hole_bottom - hole_height
	if header_height > 0.1:
		Geometry._add_compound_box(
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
		Geometry._set_object_meta(fragment, object)
		Geometry._add_box_parts(fragment, fragment_size, object)
		root.add_child(fragment)
	return root


static func _build_stairs(object: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = String(object.get("name", "Stairs")).validate_node_name()
	root.position = MapDocument.data_to_vector(object.get("position", {}))
	root.rotation_degrees = MapDocument.data_to_vector(object.get("rotation_degrees", {}))
	Geometry._set_object_meta(root, object)
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
		Geometry._add_visual_box(
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
	traversal_ramp.add_to_group(StairCollision.GROUP)
	Geometry._set_object_meta(traversal_ramp, object)
	var collision := CollisionShape3D.new()
	collision.name = "CollisionShape3D"
	var shape := ConvexPolygonShape3D.new()
	shape.points = StairCollision.points(AABB(-size * 0.5, size))
	collision.shape = shape
	traversal_ramp.add_child(collision)
	root.add_child(traversal_ramp)
	return root


static func _build_round_primitive(object: Dictionary, sphere: bool) -> Node3D:
	var body := StaticBody3D.new()
	body.name = String(object.get("name", "Freeform Sphere" if sphere else "Freeform Cylinder")).validate_node_name()
	body.position = MapDocument.data_to_vector(object.get("position", {}))
	body.rotation_degrees = MapDocument.data_to_vector(object.get("rotation_degrees", {}))
	Geometry._set_object_meta(body, object)
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
	visual.material_override = Materials._material_for_object(object)
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
	label.fixed_size = false
	label.pixel_size = radius / 185.0
	marker.add_child(label)


static func _build_training_marker(object: Dictionary, editor_preview: bool) -> Node3D:
	var marker := StaticBody3D.new()
	var type_name := StringName(object.get("type", "training_dummy"))
	marker.name = String(object.get("name", type_name)).validate_node_name()
	marker.position = MapDocument.data_to_vector(object.get("position", {}))
	marker.rotation_degrees = MapDocument.data_to_vector(object.get("rotation_degrees", {}))
	Geometry._set_object_meta(marker, object)
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
	Geometry._set_object_meta(body, object)
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
	trunk.material_override = Materials._tree_texture_material("bark", TREE_BARK_TEXTURE_PATH)
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
		foliage.material_override = Materials._tree_texture_material(
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
	Geometry._set_object_meta(body, object)
	body.set_meta("concealment_asset", true)
	body.set_meta("blocks_movement", false)
	var size := MapDocument.data_to_vector(object.get("size", {}), Vector3(3.4, 2.1, 2.8))
	var properties: Dictionary = object.get("properties", {})
	var cluster_count := clampi(int(properties.get("cluster_count", 7)), 3, 14)
	var seed_value := int(properties.get("variation_seed", 0))
	if seed_value == 0:
		seed_value = absi(String(object.get("id", "bush")).hash()) % 10007
	var foliage_material := Materials._tree_texture_material("bush_foliage", BROADLEAF_FOLIAGE_TEXTURE_PATH)
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
	Geometry._set_object_meta(body, object)
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
	var material := Materials._material_for_object(object)
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


static func _build_wedge_ramp(object: Dictionary) -> Node3D:
	var body := StaticBody3D.new()
	body.name = String(object.get("name", "Ramp")).validate_node_name()
	body.position = MapDocument.data_to_vector(object.get("position", {}))
	body.rotation_degrees = MapDocument.data_to_vector(object.get("rotation_degrees", {}))
	Geometry._set_object_meta(body, object)
	var size := MapDocument.data_to_vector(object.get("size", {}), Vector3(3.0, 1.5, 5.0))
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "Visual"
	mesh_instance.mesh = _wedge_mesh(size)
	mesh_instance.material_override = Materials._material_for_object(object)
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
	Geometry._set_object_meta(root, object)
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
		Geometry._set_object_meta(segment, object)
		Geometry._add_box_parts(segment, Vector3(chord, size.y, size.z), object)
		root.add_child(segment)
	return root


static func _build_jagged_wall(object: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = String(object.get("name", "Broken Wall")).validate_node_name()
	root.position = MapDocument.data_to_vector(object.get("position", {}))
	root.rotation_degrees = MapDocument.data_to_vector(object.get("rotation_degrees", {}))
	Geometry._set_object_meta(root, object)
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
		Geometry._set_object_meta(piece, object)
		Geometry._add_box_parts(piece, Vector3(piece_width * 1.04, piece_height, size.z), object)
		root.add_child(piece)
	return root


static func _apply_camera_passage_policy(node: Node, object: Dictionary) -> void:
	var properties: Dictionary = object.get("properties", {})
	if not bool(properties.get("camera_soft_occluder", false)):
		return
	# This tag is consumed only by the rendered camera collision solver. The
	# object's ordinary physics layers continue blocking players and bullets.
	node.add_to_group("camera_soft_occluder")
	node.set_meta("camera_soft_occluder", true)


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


# Compatibility entry used by material authoring probes.
static func _material_for_object(object: Dictionary) -> StandardMaterial3D:
	return Materials._material_for_object(object)
