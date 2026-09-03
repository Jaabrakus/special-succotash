extends SceneTree

const MapDocument := preload("res://scripts/maps/socom_map_document.gd")
const OUTPUT_PATH := "res://config/maps/painterly_coastal_village_2v2.json"

const IVORY := Color("d9c39c")
const OCHRE := Color("bd7f4c")
const FADED_BLUE := Color("6c8d99")
const DUSTY_ROSE := Color("b36d5c")
const STONE := Color("75685e")
const EARTH := Color("77705e")
const ROOF := Color("62564f")
const COAST_BACKDROP := "res://assets/textures/environment/morro_do_sol_distant_coast_v1.png"


func _init() -> void:
	var objects: Array[Dictionary] = []
	_add(objects, "village_ground", &"ground", "Morro do Sol Ground", Vector3(0.0, -0.125, 0.0), Vector3(44.0, 0.25, 36.0), EARTH, {"surface_kind": "dirt", "uv_scale": 0.58, "painterly_material": true})

	# Objective and spawn contract: two players per side, one shared bomb, two sites.
	_add(objects, "training_spawn", &"player_spawn", "Training Spawn", Vector3(0.0, 0.05, 14.8), Vector3(0.8, 1.8, 0.8), Color("55dca0"))
	_add(objects, "alpha_spawn_left", &"team_alpha_spawn", "Alpha Left Spawn", Vector3(-1.6, 0.05, 15.2), Vector3(1.0, 1.8, 1.0), Color("4fa3ff"))
	_add(objects, "alpha_spawn_right", &"team_alpha_spawn", "Alpha Right Spawn", Vector3(1.6, 0.05, 15.2), Vector3(1.0, 1.8, 1.0), Color("4fa3ff"))
	_add(objects, "bravo_spawn_left", &"team_bravo_spawn", "Bravo Left Spawn", Vector3(-1.6, 0.05, -15.4), Vector3(1.0, 1.8, 1.0), Color("ff655e"))
	_add(objects, "bravo_spawn_right", &"team_bravo_spawn", "Bravo Right Spawn", Vector3(1.6, 0.05, -15.4), Vector3(1.0, 1.8, 1.0), Color("ff655e"))
	_add(objects, "village_bomb", &"bomb_pickup", "Demolition Satchel", Vector3(0.0, 0.35, 12.2), Vector3(0.8, 0.8, 0.8), Color("f4d34f"))
	_add(objects, "site_a", &"alpha_bomb_site", "A — Community Hall", Vector3(-14.0, 1.925, -4.5), Vector3(3.2, 0.25, 3.2), Color("4fa3ff"))
	_add(objects, "site_b", &"bravo_bomb_site", "B — Repair Workshop", Vector3(14.0, 1.925, -4.5), Vector3(3.2, 0.25, 3.2), Color("ff655e"))

	# The map boundary is architectural, not an invisible open field.
	_add_wall(objects, "north_boundary", "North Retaining Wall", Vector3(0.0, 1.7, -17.75), Vector3(44.0, 3.4, 0.5), STONE)
	_add_wall(objects, "south_boundary", "South Retaining Wall", Vector3(0.0, 1.7, 17.75), Vector3(44.0, 3.4, 0.5), STONE)
	_add_wall(objects, "west_boundary", "West Retaining Wall", Vector3(-21.75, 1.7, 0.0), Vector3(36.0, 3.4, 0.5), STONE, 90.0)
	_add_wall(objects, "east_boundary", "East Retaining Wall", Vector3(21.75, 1.7, 0.0), Vector3(36.0, 3.4, 0.5), STONE, 90.0)

	# Six complete structures form three routes. Their openings are real compound
	# collision, so the blockout and the shipped tactical paths are identical.
	_add_building(objects, "center_cafe", "Cafe Azul", Vector3(0.0, 0.0, 3.5), Vector2(8.0, 7.0), 4.4, FADED_BLUE, ["south", "north"], ["east", "west"])
	_add_building(objects, "a_chapel", "Community Hall", Vector3(-14.0, 1.8, -4.5), Vector2(8.0, 8.0), 4.8, IVORY, ["south", "east"], ["north", "west"])
	_add_building(objects, "b_workshop", "Repair Workshop", Vector3(14.0, 1.8, -4.5), Vector2(8.0, 8.0), 4.6, OCHRE, ["south", "west"], ["north", "east"])
	_add_building(objects, "southwest_home", "Rose Lane House", Vector3(-13.0, 0.0, 10.0), Vector2(7.0, 5.0), 4.2, DUSTY_ROSE, ["north"], ["east", "south"])
	_add_building(objects, "southeast_home", "Ochre Lane House", Vector3(13.0, 0.0, 10.0), Vector2(7.0, 5.0), 4.2, OCHRE, ["north"], ["west", "south"])
	_add_building(objects, "north_inn", "North Gate Homes", Vector3(0.0, 0.0, -11.5), Vector2(8.0, 5.0), 4.5, IVORY, ["south", "north"], ["east", "west"])

	# A and B sit on the middle hillside tier. Attackers can climb the direct site
	# ramp or use the long side terrace; defenders reach the same terrace from the
	# north. The open undercroft creates low-route cover without another plant zone.
	for support_data: Array in [
		["a_support_sw", Vector3(-17.3, 0.9, -1.2)], ["a_support_se", Vector3(-10.7, 0.9, -1.2)],
		["a_support_nw", Vector3(-17.3, 0.9, -7.8)], ["a_support_ne", Vector3(-10.7, 0.9, -7.8)],
		["b_support_sw", Vector3(10.7, 0.9, -1.2)], ["b_support_se", Vector3(17.3, 0.9, -1.2)],
		["b_support_nw", Vector3(10.7, 0.9, -7.8)], ["b_support_ne", Vector3(17.3, 0.9, -7.8)],
	]:
		_add(objects, String(support_data[0]), &"column", "Raised House Support", support_data[1] as Vector3, Vector3(0.55, 1.8, 0.55), STONE, _painted_surface("concrete"))
	_add(objects, "a_direct_ramp", &"ramp", "A Site Main Ramp", Vector3(-14.0, 0.9, 2.75), Vector3(3.0, 1.8, 6.5), OCHRE, _painted_surface("concrete"))
	_add(objects, "b_direct_ramp", &"ramp", "B Site Main Ramp", Vector3(14.0, 0.9, 2.75), Vector3(3.0, 1.8, 6.5), FADED_BLUE, _painted_surface("concrete"))
	for side_data: Array in [["west", -8.0, OCHRE], ["east", 8.0, FADED_BLUE]]:
		var side_name := String(side_data[0])
		var side_x := float(side_data[1])
		var side_color := side_data[2] as Color
		_add(objects, "%s_mid_terrace" % side_name, &"platform", "%s Hillside Terrace" % side_name.capitalize(), Vector3(side_x, 1.8, -2.5), Vector3(4.0, 0.35, 12.0), side_color, _painted_surface("concrete"))
		_add(objects, "%s_south_ramp" % side_name, &"ramp", "%s South Ramp" % side_name.capitalize(), Vector3(side_x, 0.9, 6.75), Vector3(3.4, 1.8, 6.5), side_color, _painted_surface("concrete"))
		_add(objects, "%s_north_ramp" % side_name, &"ramp", "%s North Ramp" % side_name.capitalize(), Vector3(side_x, 0.9, -11.75), Vector3(3.4, 1.8, 6.5), side_color, _painted_surface("concrete"), 180.0)
		var rail_x := side_x - 1.82 if side_x < 0.0 else side_x + 1.82
		_add_cover(objects, "%s_terrace_rail" % side_name, "%s Terrace Wall" % side_name.capitalize(), Vector3(rail_x, 2.3, -2.5), Vector3(9.0, 0.9, 0.3), STONE, 90.0)

	# A single contestable roof adds vertical choice without placing either bomb
	# site below a dominant power position.
	_add(objects, "cafe_roof_stairs", &"stairs", "Cafe Roof Stairs", Vector3(5.35, 2.2, 3.5), Vector3(2.4, 4.4, 5.8), STONE, _painted_surface("concrete"), 90.0)
	_add_cover(objects, "cafe_parapet_north", "Cafe North Parapet", Vector3(0.0, 4.85, 0.15), Vector3(8.0, 0.75, 0.35), ROOF)
	_add_cover(objects, "cafe_parapet_south", "Cafe South Parapet", Vector3(0.0, 4.85, 6.85), Vector3(8.0, 0.75, 0.35), ROOF)
	_add_cover(objects, "cafe_parapet_west", "Cafe West Parapet", Vector3(-3.85, 4.85, 3.5), Vector3(6.7, 0.75, 0.35), ROOF, 90.0)
	_add(objects, "cafe_water_tank", &"primitive_cylinder", "Cafe Roof Water Tank", Vector3(-2.5, 5.45, 3.5), Vector3(1.35, 1.5, 1.35), Color("4a7f9c"), _painted_surface("concrete"))
	_add(objects, "a_water_tank", &"primitive_cylinder", "Community Hall Water Tank", Vector3(-15.6, 7.4, -4.5), Vector3(1.4, 1.6, 1.4), Color("4a7f9c"), _painted_surface("concrete"))
	_add(objects, "b_water_tank", &"primitive_cylinder", "Workshop Water Tank", Vector3(15.6, 7.2, -4.5), Vector3(1.4, 1.6, 1.4), Color("4a7f9c"), _painted_surface("concrete"))

	# Route shaping: each lane has a sequence of hard cover with no single spawn-
	# to-site sightline. The center fountain lets either duo rotate under pressure.
	_add(objects, "center_fountain", &"primitive_cylinder", "Old Market Fountain", Vector3(0.0, 0.55, -2.1), Vector3(2.8, 1.1, 2.8), FADED_BLUE, _painted_surface("concrete"))
	_add(objects, "center_broken_west", &"jagged_wall", "West Market Ruin", Vector3(-5.8, 1.35, -1.7), Vector3(5.0, 2.7, 0.45), IVORY, _painted_surface("stucco"), 90.0)
	_add(objects, "center_broken_east", &"jagged_wall", "East Market Ruin", Vector3(5.8, 1.35, -1.7), Vector3(5.0, 2.7, 0.45), OCHRE, _painted_surface("stucco"), 90.0)
	_add_cover(objects, "market_stall_west", "West Market Stall", Vector3(-5.1, 0.55, 6.8), Vector3(3.4, 1.1, 0.75), DUSTY_ROSE, -12.0)
	_add_cover(objects, "market_stall_east", "East Market Stall", Vector3(5.1, 0.55, 6.8), Vector3(3.4, 1.1, 0.75), FADED_BLUE, 12.0)
	_add_cover(objects, "west_lane_cover_south", "West Lane Cart", Vector3(-18.0, 0.55, 8.1), Vector3(3.2, 1.1, 0.8), OCHRE, 90.0)
	_add_cover(objects, "west_lane_cover_mid", "West Lane Masonry", Vector3(-18.1, 0.55, 1.0), Vector3(3.4, 1.1, 0.75), STONE, 78.0)
	_add_cover(objects, "east_lane_cover_south", "East Lane Cart", Vector3(18.0, 0.55, 8.1), Vector3(3.2, 1.1, 0.8), FADED_BLUE, 90.0)
	_add_cover(objects, "east_lane_cover_mid", "East Lane Masonry", Vector3(18.1, 0.55, 1.0), Vector3(3.4, 1.1, 0.75), STONE, 102.0)
	_add_cover(objects, "a_site_cover", "Community Hall Bench", Vector3(-14.8, 2.35, -5.4), Vector3(2.4, 1.1, 0.6), ROOF, 90.0)
	_add_cover(objects, "b_site_cover", "Workshop Bench", Vector3(14.8, 2.35, -5.4), Vector3(2.4, 1.1, 0.6), ROOF, 90.0)
	_add_cover(objects, "north_exit_west", "North West Sandstone", Vector3(-6.7, 0.55, -12.4), Vector3(3.0, 1.1, 0.7), STONE, 18.0)
	_add_cover(objects, "north_exit_east", "North East Sandstone", Vector3(6.7, 0.55, -12.4), Vector3(3.0, 1.1, 0.7), STONE, -18.0)

	# Small silhouettes and practical lights sell the village identity while
	# staying outside the central combat-readability cone.
	for tree_data: Array in [
		["tree_sw", Vector3(-19.2, 0.0, 14.0), 201],
		["tree_se", Vector3(19.2, 0.0, 14.0), 202],
		["tree_nw", Vector3(-19.0, 0.0, -13.8), 203],
		["tree_ne", Vector3(19.0, 0.0, -13.8), 204],
	]:
		_add(objects, String(tree_data[0]), &"tree", "Village Plane Tree", tree_data[1] as Vector3, Vector3(3.0, 6.5, 3.0), Color("60754f"), {"canopy_layers": 4, "trunk_ratio": 0.40, "variation_seed": int(tree_data[2])})
	for bush_data: Array in [
		["bush_a_south", Vector3(-10.2, 0.0, 0.0), 301],
		["bush_a_north", Vector3(-10.3, 0.0, -9.2), 302],
		["bush_b_south", Vector3(10.2, 0.0, 0.0), 303],
		["bush_b_north", Vector3(10.3, 0.0, -9.2), 304],
	]:
		_add(objects, String(bush_data[0]), &"bush", "Low Village Shrub", bush_data[1] as Vector3, Vector3(2.2, 1.25, 1.8), Color("566747"), {"cluster_count": 6, "variation_seed": int(bush_data[2]), "concealment": false, "blocks_movement": false, "collision_enabled": false})
	for light_data: Array in [
		["lamp_a", Vector3(-10.3, 2.4, -1.1)],
		["lamp_b", Vector3(10.3, 2.4, -1.1)],
		["lamp_cafe_s", Vector3(0.0, 2.5, 7.1)],
		["lamp_cafe_n", Vector3(0.0, 2.5, -0.1)],
	]:
		_add(objects, String(light_data[0]), &"point_light", "Warm Village Lamp", light_data[1] as Vector3, Vector3(0.35, 0.35, 0.35), Color("ffd09a"), {"energy": 2.2, "range": 6.5, "shadow_enabled": false})

	var environment := MapDocument.environment_from_preset("painterly_coastal")
	# The coast is a far, collision-free ambience card beyond the downhill edge.
	# Its dimensions preserve the source image ratio and keep every map route 3D.
	environment["backdrop_texture"] = COAST_BACKDROP
	environment["backdrop_position"] = MapDocument.vector_to_data(Vector3(0.0, -1.0, 105.0))
	environment["backdrop_size"] = MapDocument.vector_to_data(Vector3(250.0, 116.0, 0.0))
	environment["backdrop_rotation"] = MapDocument.vector_to_data(Vector3.ZERO)
	var document := {
		"schema_version": 1,
		"map_id": "morro_do_sol_2v2",
		"enabled": true,
		"name": "Morro do Sol — 2v2 Demolition",
		"grid_size": 0.25,
		"environment": environment,
		"gameplay": {
			"primary_mode": "demolition",
			"supported_modes": ["demolition", "team_deathmatch"],
			"round_time_seconds": 150,
			"maximum_rounds": 7,
			"rounds_to_win": 4,
			"elimination_wins_round": true,
			"bomb_detonation_wins_round": true,
			"round_timeout_result": "bravo",
			"bomb_fuse_seconds": 35,
			"plant_time_seconds": 5.0,
			"defuse_time_seconds": 5.0,
			"respawns_enabled": false,
		},
		"objects": objects,
	}
	if not MapDocument.save_path(document, OUTPUT_PATH):
		push_error("Could not write %s" % OUTPUT_PATH)
		quit(1)
		return
	print("PAINTERLY_VILLAGE_GENERATED path=%s objects=%d" % [OUTPUT_PATH, objects.size()])
	quit(0)


func _painted_surface(kind: String) -> Dictionary:
	return {
		"surface_kind": kind,
		"roughness": 0.96,
		"metallic": 0.0,
		"uv_scale": 0.82,
		"painterly_material": true,
	}


func _add_wall(objects: Array[Dictionary], id: String, label: String, position: Vector3, size: Vector3, color: Color, yaw: float = 0.0) -> void:
	_add(objects, id, &"wall", label, position, size, color, _painted_surface("stucco"), yaw)


func _add_cover(objects: Array[Dictionary], id: String, label: String, position: Vector3, size: Vector3, color: Color, yaw: float = 0.0) -> void:
	_add(objects, id, &"cover_low", label, position, size, color, _painted_surface("concrete"), yaw)


func _add_building(objects: Array[Dictionary], id: String, label: String, center: Vector3, footprint: Vector2, height: float, color: Color, entries: Array[String], windows: Array[String]) -> void:
	var half_x := footprint.x * 0.5
	var half_z := footprint.y * 0.5
	var wall_y := height * 0.5
	_add(objects, "%s_floor" % id, &"roof", "%s Floor" % label, center + Vector3(0.0, 0.175, 0.0), Vector3(footprint.x, 0.35, footprint.y), ROOF, _painted_surface("concrete"))
	var roof_properties := _painted_surface("concrete")
	roof_properties["camera_soft_occluder"] = true
	_add(objects, "%s_roof" % id, &"roof", "%s Roof" % label, center + Vector3(0.0, height + 0.175, 0.0), Vector3(footprint.x, 0.35, footprint.y), ROOF, roof_properties)
	for side in ["north", "south", "east", "west"]:
		var wall_type: StringName = &"wall"
		if side in entries:
			wall_type = &"doorway_wall"
		elif side in windows:
			wall_type = &"window_wall"
		var position := center + Vector3(0.0, wall_y, 0.0)
		var size := Vector3(footprint.x, height, 0.35)
		var yaw := 0.0
		if side == "north":
			position.z -= half_z
		elif side == "south":
			position.z += half_z
		elif side == "east":
			position.x += half_x
			size.x = footprint.y
			yaw = 90.0
		else:
			position.x -= half_x
			size.x = footprint.y
			yaw = 90.0
		var properties := _painted_surface("stucco")
		if wall_type == &"doorway_wall":
			properties["opening_width"] = 1.55
			properties["opening_height"] = minf(2.35, height - 0.2)
		elif wall_type == &"window_wall":
			properties["opening_width"] = 1.65
			properties["opening_height"] = 1.25
		_add(objects, "%s_%s_wall" % [id, side], wall_type, "%s %s Wall" % [label, side.capitalize()], position, size, color, properties, yaw)


func _add(objects: Array[Dictionary], id: String, type_name: StringName, label: String, position: Vector3, size: Vector3, color: Color, properties: Dictionary = {}, yaw: float = 0.0) -> void:
	var object := MapDocument.make_object(type_name, position, size)
	object["id"] = id
	object["name"] = label
	object["rotation_degrees"] = MapDocument.vector_to_data(Vector3(0.0, yaw, 0.0))
	object["color"] = MapDocument.color_to_data(color)
	var merged: Dictionary = object.get("properties", {}).duplicate(true)
	merged.merge(properties, true)
	object["properties"] = merged
	objects.append(object)
