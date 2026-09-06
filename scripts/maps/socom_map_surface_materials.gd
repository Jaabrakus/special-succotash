extends RefCounted

const MapDocument := preload("res://scripts/maps/socom_map_document.gd")
const PROCEDURAL_DETAIL_SIZE := 16
static var surface_texture_cache: Dictionary = {}
static var surface_normal_cache: Dictionary = {}
static var surface_roughness_cache: Dictionary = {}
static var tree_material_cache: Dictionary = {}
static var authored_texture_cache: Dictionary = {}

static func _solid_material(color: Color, roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	return material


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
