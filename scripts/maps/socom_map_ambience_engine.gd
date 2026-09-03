class_name SocomMapAmbienceEngine
extends RefCounted

const MapDocument := preload("res://scripts/maps/socom_map_document.gd")
const PainterlyCoastalSky := preload("res://assets/shaders/painterly_coastal_sky.gdshader")
const PainterlyCoastalV2Sky := preload("res://assets/shaders/painterly_coastal_v2_sky.gdshader")


static func build_into(parent: Node, document: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = "AuthoredAtmosphere"
	parent.add_child(root)
	var data := MapDocument.normalize_environment(document.get("environment", {}))

	var world := WorldEnvironment.new()
	world.name = "MapWorldEnvironment"
	var environment := Environment.new()
	var sky := Sky.new()
	var preset_name := String(data.get("preset", ""))
	var painterly_coastal_v2 := preset_name == "painterly_coastal_v2"
	var painterly_coastal := preset_name in ["painterly_coastal", "painterly_coastal_v2"]
	if painterly_coastal:
		var sky_material := ShaderMaterial.new()
		sky_material.shader = PainterlyCoastalV2Sky if painterly_coastal_v2 else PainterlyCoastalSky
		sky_material.set_shader_parameter("sky_top_color", MapDocument.data_to_color(data["sky_top"]))
		sky_material.set_shader_parameter("sky_horizon_color", MapDocument.data_to_color(data["sky_horizon"]))
		sky_material.set_shader_parameter("ground_color", MapDocument.data_to_color(data["ground_color"]))
		sky.sky_material = sky_material
	else:
		var sky_material := ProceduralSkyMaterial.new()
		sky_material.sky_top_color = MapDocument.data_to_color(data["sky_top"])
		sky_material.sky_horizon_color = MapDocument.data_to_color(data["sky_horizon"])
		sky_material.ground_bottom_color = MapDocument.data_to_color(data["ground_color"]).darkened(0.35)
		sky_material.ground_horizon_color = MapDocument.data_to_color(data["ground_color"])
		sky_material.sun_angle_max = 12.0
		sky_material.sun_curve = 0.08
		sky.sky_material = sky_material
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = MapDocument.data_to_color(data["ambient_color"])
	environment.ambient_light_energy = float(data["ambient_energy"])
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	environment.tonemap_exposure = float(data["exposure"])
	environment.adjustment_enabled = true
	environment.adjustment_brightness = 0.87 if painterly_coastal_v2 else (0.94 if painterly_coastal else 0.88)
	environment.adjustment_contrast = 1.14 if painterly_coastal_v2 else (1.08 if painterly_coastal else 1.03)
	environment.adjustment_saturation = 1.00 if painterly_coastal_v2 else (1.04 if painterly_coastal else 0.96)
	environment.fog_enabled = bool(data["fog_enabled"])
	environment.fog_light_color = MapDocument.data_to_color(data["fog_color"])
	environment.fog_light_energy = 0.7
	environment.fog_density = float(data["fog_density"])
	environment.fog_aerial_perspective = 0.72 if painterly_coastal else 0.55
	world.environment = environment
	root.add_child(world)
	_add_distant_backdrop(root, data)

	var sun := DirectionalLight3D.new()
	sun.name = "MapSun"
	sun.rotation_degrees = MapDocument.data_to_vector(data["sun_rotation"])
	sun.light_color = MapDocument.data_to_color(data["sun_color"])
	sun.light_energy = float(data["sun_energy"])
	sun.shadow_enabled = true
	sun.shadow_bias = 0.035
	sun.shadow_normal_bias = 1.1
	sun.directional_shadow_max_distance = 90.0
	sun.directional_shadow_blend_splits = true
	sun.directional_shadow_fade_start = 0.82
	root.add_child(sun)
	root.set_meta("soundscape", String(data.get("soundscape", "outdoor_tactical")))
	return root


static func _add_distant_backdrop(root: Node3D, data: Dictionary) -> void:
	var texture_path := String(data.get("backdrop_texture", ""))
	if texture_path.is_empty():
		return
	var texture: Texture2D = null
	if ResourceLoader.exists(texture_path):
		texture = load(texture_path) as Texture2D
	elif FileAccess.file_exists(texture_path):
		# Command-line first runs can reach a newly added PNG before the editor has
		# created its import artifact. Shipped projects use ResourceLoader above.
		var source_image := Image.new()
		if source_image.load(ProjectSettings.globalize_path(texture_path)) == OK:
			texture = ImageTexture.create_from_image(source_image)
	if texture == null:
		push_warning("Map backdrop could not load: %s" % texture_path)
		return
	var size_data := MapDocument.data_to_vector(data.get("backdrop_size", {}), Vector3(120.0, 56.0, 0.0))
	var quad := QuadMesh.new()
	quad.size = Vector2(maxf(size_data.x, 1.0), maxf(size_data.y, 1.0))
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_texture = texture
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	quad.material = material
	var backdrop := MeshInstance3D.new()
	backdrop.name = "DistantCoastalBackdrop"
	backdrop.mesh = quad
	backdrop.position = MapDocument.data_to_vector(data.get("backdrop_position", {}))
	backdrop.rotation_degrees = MapDocument.data_to_vector(data.get("backdrop_rotation", {}))
	backdrop.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	backdrop.extra_cull_margin = 32.0
	backdrop.set_meta("map_ambience_only", true)
	backdrop.set_meta("source_texture", texture_path)
	root.add_child(backdrop)
