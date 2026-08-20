class_name SocomMapAmbienceEngine
extends RefCounted

const MapDocument := preload("res://scripts/maps/socom_map_document.gd")


static func build_into(parent: Node, document: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = "AuthoredAtmosphere"
	parent.add_child(root)
	var data := MapDocument.normalize_environment(document.get("environment", {}))

	var world := WorldEnvironment.new()
	world.name = "MapWorldEnvironment"
	var environment := Environment.new()
	var sky := Sky.new()
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
	environment.fog_enabled = bool(data["fog_enabled"])
	environment.fog_light_color = MapDocument.data_to_color(data["fog_color"])
	environment.fog_light_energy = 0.7
	environment.fog_density = float(data["fog_density"])
	environment.fog_aerial_perspective = 0.55
	world.environment = environment
	root.add_child(world)

	var sun := DirectionalLight3D.new()
	sun.name = "MapSun"
	sun.rotation_degrees = MapDocument.data_to_vector(data["sun_rotation"])
	sun.light_color = MapDocument.data_to_color(data["sun_color"])
	sun.light_energy = float(data["sun_energy"])
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 90.0
	sun.directional_shadow_blend_splits = true
	sun.directional_shadow_fade_start = 0.82
	root.add_child(sun)
	root.set_meta("soundscape", String(data.get("soundscape", "outdoor_tactical")))
	return root
