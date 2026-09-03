extends SceneTree

const V1_PATH := "res://config/maps/painterly_coastal_village_2v2.json"
const V2_PATH := "res://config/maps/morro_do_sol_v2_2v2.json"
const V2_COAST := "res://assets/textures/environment/morro_do_sol_v2_distant_coast.png"
const V2_PLASTER := "res://assets/textures/environment/morro_do_sol_v2_painted_plaster.png"
const V2_WOOD := "res://assets/textures/environment/morro_do_sol_v2_exposed_wood.png"
const MapDocument := preload("res://scripts/maps/socom_map_document.gd")
const MapCommands := preload("res://scripts/maps/socom_map_command_service.gd")
const MapRuntime := preload("res://scripts/maps/socom_map_runtime.gd")
const MapAmbience := preload("res://scripts/maps/socom_map_ambience_engine.gd")
const MapGameplay := preload("res://scripts/maps/socom_map_gameplay_contract.gd")

var failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var v1 := MapDocument.load_path(V1_PATH)
	var v2 := MapDocument.load_path(V2_PATH)
	_expect(not v1.is_empty(), "V1 restore-point map remains available")
	_expect(not v2.is_empty(), "Morro do Sol V2 document loads")
	_expect(String(v1.get("map_id", "")) == "morro_do_sol_2v2", "V1 keeps its original map id")
	_expect(String(v2.get("map_id", "")) == "morro_do_sol_v2_2v2", "V2 has a separate map id")
	_expect(String(v2.get("name", "")) == "Morro do Sol V2 — 2v2 Demolition", "V2 has a distinct launcher label")

	var validation := MapCommands.validate_document(v2)
	_expect(bool(validation.get("ok", false)), "V2 map schema and demolition requirements validate")
	if not bool(validation.get("ok", false)):
		for error: Variant in validation.get("errors", []):
			push_error("MORRO DO SOL V2 VALIDATION: %s" % error)
	var runtime_validation := MapRuntime.validate_build(v2)
	_expect(bool(runtime_validation.get("ok", false)), "every V2 map object builds through SocomMapRuntime")
	if not bool(runtime_validation.get("ok", false)):
		for error: Variant in runtime_validation.get("errors", []):
			push_error("MORRO DO SOL V2 RUNTIME: %s" % error)
	_expect(int(runtime_validation.get("built_objects", 0)) == (v2.get("objects", []) as Array).size(), "V2 runtime count matches the saved document")

	var v1_by_id := _objects_by_id(v1)
	var v2_by_id := _objects_by_id(v2)
	var preserved_non_building_geometry := true
	for object_id: String in v1_by_id:
		if _is_legacy_building_piece(object_id):
			continue
		if not v2_by_id.has(object_id):
			preserved_non_building_geometry = false
			break
		var before: Dictionary = v1_by_id[object_id]
		var after: Dictionary = v2_by_id[object_id]
		if String(before.get("type", "")) != String(after.get("type", "")):
			preserved_non_building_geometry = false
			break
		if not _same_vector(before.get("position", {}), after.get("position", {})):
			preserved_non_building_geometry = false
			break
		if not _same_vector(before.get("rotation_degrees", {}), after.get("rotation_degrees", {})):
			preserved_non_building_geometry = false
			break
		if not _same_vector(before.get("size", {}), after.get("size", {})):
			preserved_non_building_geometry = false
			break
	_expect(preserved_non_building_geometry, "all V1 route, objective, and non-building collision transforms remain unchanged")
	var legacy_pieces_remaining := 0
	for object_id: String in v2_by_id:
		if _is_legacy_building_piece(object_id):
			legacy_pieces_remaining += 1
	_expect(legacy_pieces_remaining == 0, "V2 removes all thirty-six disconnected box-building pieces")

	var expected_buildings := _expected_buildings()
	var building_count := 0
	var building_contracts_match := true
	var architecture_nodes_match := true
	var signed_public_buildings := 0
	var stacked_building_count := 0
	var textured_building_count := 0
	for object: Dictionary in v2.get("objects", []):
		if String(object.get("type", "")) != "favela_building":
			continue
		building_count += 1
		var building_id := String(object.get("id", ""))
		if not expected_buildings.has(building_id):
			building_contracts_match = false
			continue
		var expected: Dictionary = expected_buildings[building_id]
		var properties: Dictionary = object.get("properties", {})
		if not _same_vector(object.get("position", {}), expected.get("position", {})):
			building_contracts_match = false
		if not _same_vector(object.get("size", {}), expected.get("size", {})):
			building_contracts_match = false
		if properties.get("entries", []) != expected.get("entries", []):
			building_contracts_match = false
		if properties.get("windows", []) != expected.get("windows", []):
			building_contracts_match = false
		if not bool(properties.get("collision_enabled", false)):
			building_contracts_match = false
		if float(properties.get("parapet_height", 1.0)) > 0.05:
			building_contracts_match = false
		if String(properties.get("masonry_texture_path", "")) != V2_PLASTER:
			building_contracts_match = false
		if String(properties.get("wood_texture_path", "")) != V2_WOOD:
			building_contracts_match = false
		if bool(properties.get("v2_stacked_module", false)):
			stacked_building_count += 1
		var built := MapRuntime.build_object(object, false)
		if built == null:
			architecture_nodes_match = false
			continue
		var required_parts := [
			"CorrugatedDoorAwning", "LeftDoorJamb", "OpenDoorLeaf",
			"WindowSillTrim", "WindowGlass", "WindowMullionVertical",
			"WindowGrilleVertical0", "IrregularPlasterPatch",
			"ExposedBrick00", "RaisedFoundationCourse", "CornerPilasterWN",
			"NorthRoofCornice", "Downspout", "ElectricalMeterBox",
			"CollisionShape3D",
		]
		for part_name: String in required_parts:
			if built.find_child(part_name, true, false) == null:
				architecture_nodes_match = false
		if built.find_child("FacadeSignBoard", true, false) != null and built.find_child("FacadeSignText", true, false) != null:
			signed_public_buildings += 1
		if _count_textured_meshes(built) >= 3:
			textured_building_count += 1
		built.free()
	_expect(building_count == 8, "V2 builds six base structures plus two stacked upper homes")
	_expect(stacked_building_count == 2, "A and B each receive one occupied stacked upper module")
	_expect(building_contracts_match, "all buildings save plaster and wood material contracts with real openings and collision")
	_expect(architecture_nodes_match, "each building has glass sash windows plus constructed doors, foundations, wall damage, utilities, and roof edges")
	_expect(textured_building_count == 8, "every building consumes authored textures in its runtime mesh tree")
	_expect(signed_public_buildings == 3, "the cafe, community hall, and workshop have physical identity signs")

	var detail_counts: Dictionary = {}
	var detail_total := 0
	var collision_free_details := true
	var plaster_contract_count := 0
	var wood_contract_count := 0
	var direct_wood_surface_count := 0
	var utility_pole_count := 0
	var cable_curve_count := 0
	var vertical_by_id: Dictionary = {}
	var vertical_type_counts: Dictionary = {}
	var vertical_collisions_match := true
	for object: Dictionary in v2.get("objects", []):
		var properties: Dictionary = object.get("properties", {})
		var type_name := String(object.get("type", ""))
		if String(object.get("type", "")) == "utility_pole":
			utility_pole_count += 1
		if String(object.get("type", "")) == "cable_curve":
			cable_curve_count += 1
		if bool(properties.get("v2_detail", false)):
			detail_total += 1
			var kind := String(properties.get("v2_detail_kind", ""))
			detail_counts[kind] = int(detail_counts.get(kind, 0)) + 1
			if bool(properties.get("collision_enabled", true)):
				collision_free_details = false
		if String(properties.get("masonry_texture_path", "")) == V2_PLASTER:
			plaster_contract_count += 1
		if String(properties.get("wood_texture_path", "")) == V2_WOOD:
			wood_contract_count += 1
		if String(properties.get("texture_path", "")) == V2_WOOD:
			direct_wood_surface_count += 1
		if bool(properties.get("v2_vertical_route", false)):
			var object_id := String(object.get("id", ""))
			vertical_by_id[object_id] = object
			vertical_type_counts[type_name] = int(vertical_type_counts.get(type_name, 0)) + 1
			if not bool(properties.get("collision_enabled", false)):
				vertical_collisions_match = false
			var built_route := MapRuntime.build_object(object, false)
			if built_route == null or built_route.find_children("*", "CollisionShape3D", true, false).is_empty():
				vertical_collisions_match = false
			if built_route != null:
				built_route.free()
	_expect((v1.get("objects", []) as Array).size() == 99, "V1 keeps its verified 99 authored objects")
	_expect((v2.get("objects", []) as Array).size() == 138, "V2 saves the expected bounded object count after the roof-route expansion")
	_expect(detail_total == 51, "V2 keeps exactly 51 bounded art-direction objects")
	_expect(collision_free_details, "every V2 art addition is collision-free")
	_expect(int(detail_counts.get("terrain", 0)) >= 3, "painted perimeter hills frame the village")
	_expect(int(detail_counts.get("vegetation", 0)) >= 16, "edge vegetation fills the empty hillside perimeter")
	_expect(int(detail_counts.get("frame", 0)) >= 13, "unfinished rooftop framing strengthens the skyline")
	_expect(int(detail_counts.get("facade_patch", 0)) == 0 and int(detail_counts.get("awning", 0)) == 0, "flat facade patches and box awnings are fully removed")
	_expect(utility_pole_count == 6, "six cylindrical utility-pole assemblies replace pole boxes")
	_expect(cable_curve_count == 4 and int(detail_counts.get("cable", 0)) == 4, "four segmented Bezier cables replace twelve box-wire segments")
	_expect(int(detail_counts.get("collapse", 0)) >= 9, "the exterior collapse adds damaged-building storytelling")
	_expect(plaster_contract_count == 8 and wood_contract_count == 8, "all eight buildings consume the supplied plaster and exposed-wood texture contracts")
	_expect(direct_wood_surface_count >= 16, "roof ramps, landings, supports, and crates directly consume the exposed-wood texture")
	_expect(vertical_by_id.size() == 18, "V2 saves exactly 18 roof-route objects")
	_expect(vertical_collisions_match, "every roof-route object builds real runtime collision")
	_expect(
		int(vertical_type_counts.get("favela_building", 0)) == 2
		and int(vertical_type_counts.get("ramp", 0)) == 4
		and int(vertical_type_counts.get("platform", 0)) == 2
		and int(vertical_type_counts.get("column", 0)) == 4
		and int(vertical_type_counts.get("wooden_crate", 0)) == 6,
		"the vertical layer contains two stacked homes, four ramps, two landings, four supports, and six crates"
	)
	_expect(_roof_route_matches(vertical_by_id, "a", 6.95), "Alpha switchback joins terrace, supported landing, and community-hall roof with walkable slopes")
	_expect(_roof_route_matches(vertical_by_id, "b", 6.75), "Bravo switchback joins terrace, supported landing, and workshop roof with walkable slopes")
	_expect(_crate_pyramid_matches(vertical_by_id, "a"), "Alpha crate stack has two grounded crates and one supported climb step")
	_expect(_crate_pyramid_matches(vertical_by_id, "b"), "Bravo crate stack has two grounded crates and one supported climb step")
	_expect(_vertical_layer_is_mirrored(vertical_by_id), "Alpha and Bravo receive mirrored access widths and crate staging")

	var layout := MapGameplay.demolition_layout(v2)
	_expect((layout.get("alpha_spawns", []) as Array).size() == 2, "V2 keeps two Alpha spawns")
	_expect((layout.get("bravo_spawns", []) as Array).size() == 2, "V2 keeps two Bravo spawns")
	_expect((layout.get("bomb_pickups", []) as Array).size() == 1, "V2 keeps one demolition bomb")
	_expect((layout.get("alpha_targets", []) as Array).size() == 1 and (layout.get("bravo_targets", []) as Array).size() == 1, "V2 keeps A and B plant sites")
	_expect(not bool((layout.get("rules", {}) as Dictionary).get("respawns_enabled", true)), "V2 demolition keeps respawns disabled")

	var environment_data: Dictionary = v2.get("environment", {})
	_expect(String(environment_data.get("preset", "")) == "painterly_coastal_v2", "V2 selects its stronger painterly sky")
	_expect(String(environment_data.get("backdrop_texture", "")) == V2_COAST, "V2 selects the new giant-cloud coastal matte")
	var test_world := Node3D.new()
	root.add_child(test_world)
	var atmosphere := MapAmbience.build_into(test_world, v2)
	var world_environment := atmosphere.get_node_or_null("MapWorldEnvironment") as WorldEnvironment
	var sky_material := world_environment.environment.sky.sky_material as ShaderMaterial if world_environment != null and world_environment.environment != null and world_environment.environment.sky != null else null
	_expect(sky_material != null and sky_material.shader != null and sky_material.shader.resource_path == "res://assets/shaders/painterly_coastal_v2_sky.gdshader", "ambience owner uses the V2 monumental-cloud shader")
	var backdrop := atmosphere.get_node_or_null("DistantCoastalBackdrop") as MeshInstance3D
	_expect(backdrop != null and backdrop.get_child_count() == 0, "V2 coast remains presentation-only with no collision child")
	test_world.free()

	var library_path := "/private/tmp/morro_do_sol_v2_library_regression"
	MapDocument.library_directory_override = library_path
	ProjectSettings.set_setting("socom/session/selected_map_document", {})
	MapDocument.ensure_active_map_in_library()
	var listed_ids: Array[String] = []
	for entry: Dictionary in MapDocument.list_library_maps():
		listed_ids.append(String(entry.get("map_id", "")))
	_expect("morro_do_sol_2v2" in listed_ids and "morro_do_sol_v2_2v2" in listed_ids, "launcher lists V1 and V2 separately")
	var selected := MapDocument.select_library_map("morro_do_sol_v2_2v2")
	_expect(String(selected.get("map_id", "")) == "morro_do_sol_v2_2v2", "launcher can select V2")
	var main_scene := load("res://main.tscn") as PackedScene
	var canonical_training := main_scene.instantiate() if main_scene != null else null
	if canonical_training != null:
		root.add_child(canonical_training)
		for _frame in 6:
			await process_frame
	var canonical_document: Dictionary = canonical_training.get("active_map_document") as Dictionary if canonical_training != null else {}
	_expect(String(canonical_document.get("map_id", "")) == "morro_do_sol_v2_2v2", "res://main.tscn consumes V2 as the active map")
	var canonical_atmosphere := canonical_training.get_node_or_null("AuthoredAtmosphere") if canonical_training != null else null
	_expect(canonical_atmosphere != null and canonical_atmosphere.get_node_or_null("DistantCoastalBackdrop") != null, "res://main.tscn builds the V2 coast through SocomMapAmbienceEngine")
	if canonical_training != null:
		canonical_training.free()
	MapDocument.library_directory_override = ""
	ProjectSettings.set_setting("socom/session/selected_map_document", {})

	if failures == 0:
		print("MORRO_DO_SOL_V2_2V2_REGRESSION PASS")
	quit(1 if failures > 0 else 0)


func _expected_buildings() -> Dictionary:
	return {
		"v2_cafe_azul": {
			"position": MapDocument.vector_to_data(Vector3(0.0, 0.0, 3.5)),
			"size": MapDocument.vector_to_data(Vector3(8.0, 4.4, 7.0)),
			"entries": ["north", "south"], "windows": ["east", "west"],
		},
		"v2_community_hall": {
			"position": MapDocument.vector_to_data(Vector3(-14.0, 1.8, -4.5)),
			"size": MapDocument.vector_to_data(Vector3(8.0, 4.8, 8.0)),
			"entries": ["south", "east"], "windows": ["north", "west"],
		},
		"v2_repair_workshop": {
			"position": MapDocument.vector_to_data(Vector3(14.0, 1.8, -4.5)),
			"size": MapDocument.vector_to_data(Vector3(8.0, 4.6, 8.0)),
			"entries": ["south", "west"], "windows": ["north", "east"],
		},
		"v2_rose_lane_house": {
			"position": MapDocument.vector_to_data(Vector3(-13.0, 0.0, 10.0)),
			"size": MapDocument.vector_to_data(Vector3(7.0, 4.2, 5.0)),
			"entries": ["north"], "windows": ["south", "east"],
		},
		"v2_ochre_lane_house": {
			"position": MapDocument.vector_to_data(Vector3(13.0, 0.0, 10.0)),
			"size": MapDocument.vector_to_data(Vector3(7.0, 4.2, 5.0)),
			"entries": ["north"], "windows": ["south", "west"],
		},
		"v2_north_gate_homes": {
			"position": MapDocument.vector_to_data(Vector3(0.0, 0.0, -11.5)),
			"size": MapDocument.vector_to_data(Vector3(8.0, 4.5, 5.0)),
			"entries": ["north", "south"], "windows": ["east", "west"],
		},
		"v2_a_upper_home": {
			"position": MapDocument.vector_to_data(Vector3(-12.1, 6.95, -4.5)),
			"size": MapDocument.vector_to_data(Vector3(3.2, 3.4, 3.8)),
			"entries": ["west"], "windows": ["north", "south"],
		},
		"v2_b_upper_home": {
			"position": MapDocument.vector_to_data(Vector3(12.1, 6.75, -4.5)),
			"size": MapDocument.vector_to_data(Vector3(3.2, 3.4, 3.8)),
			"entries": ["east"], "windows": ["north", "south"],
		},
	}


func _count_textured_meshes(node: Node) -> int:
	var count := 0
	for found: Node in node.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := found as MeshInstance3D
		var material := mesh_instance.material_override as StandardMaterial3D
		if material != null and material.albedo_texture != null:
			count += 1
	return count


func _roof_route_matches(vertical_by_id: Dictionary, side_id: String, roof_top: float) -> bool:
	var lower: Dictionary = vertical_by_id.get("v2_%s_roof_ramp_lower" % side_id, {})
	var landing: Dictionary = vertical_by_id.get("v2_%s_roof_landing" % side_id, {})
	var upper: Dictionary = vertical_by_id.get("v2_%s_roof_ramp_upper" % side_id, {})
	if lower.is_empty() or landing.is_empty() or upper.is_empty():
		return false
	var lower_position := MapDocument.data_to_vector(lower.get("position", {}))
	var lower_size := MapDocument.data_to_vector(lower.get("size", {}))
	var landing_position := MapDocument.data_to_vector(landing.get("position", {}))
	var landing_size := MapDocument.data_to_vector(landing.get("size", {}))
	var upper_position := MapDocument.data_to_vector(upper.get("position", {}))
	var upper_size := MapDocument.data_to_vector(upper.get("size", {}))
	var lower_rotation := MapDocument.data_to_vector(lower.get("rotation_degrees", {}))
	var upper_rotation := MapDocument.data_to_vector(upper.get("rotation_degrees", {}))
	var terrace_top := 1.975
	var landing_top := landing_position.y + landing_size.y * 0.5
	var lower_landing_overlap := _interval_overlap(
		lower_position.x - lower_size.x * 0.5, lower_position.x + lower_size.x * 0.5,
		landing_position.x - landing_size.x * 0.5, landing_position.x + landing_size.x * 0.5
	)
	var upper_landing_overlap := _interval_overlap(
		upper_position.x - upper_size.x * 0.5, upper_position.x + upper_size.x * 0.5,
		landing_position.x - landing_size.x * 0.5, landing_position.x + landing_size.x * 0.5
	)
	var roof_min_x := -18.0 if side_id == "a" else 10.0
	var roof_max_x := -10.0 if side_id == "a" else 18.0
	var upper_roof_overlap := _interval_overlap(
		upper_position.x - upper_size.x * 0.5, upper_position.x + upper_size.x * 0.5,
		roof_min_x, roof_max_x
	)
	var lower_high_z := lower_position.z - lower_size.z * 0.5
	var upper_low_z := upper_position.z - upper_size.z * 0.5
	var upper_high_z := upper_position.z + upper_size.z * 0.5
	var landing_min_z := landing_position.z - landing_size.z * 0.5
	var landing_max_z := landing_position.z + landing_size.z * 0.5
	return (
		is_equal_approx(lower_position.y - lower_size.y * 0.5, terrace_top)
		and is_equal_approx(lower_position.y + lower_size.y * 0.5, landing_top)
		and is_equal_approx(upper_position.y - upper_size.y * 0.5, landing_top)
		and is_equal_approx(upper_position.y + upper_size.y * 0.5, roof_top)
		and is_equal_approx(lower_rotation.y, 0.0)
		and is_equal_approx(absf(upper_rotation.y), 180.0)
		and rad_to_deg(atan2(lower_size.y, lower_size.z)) <= 30.0
		and rad_to_deg(atan2(upper_size.y, upper_size.z)) <= 30.0
		and lower_size.x + 0.001 >= 1.8
		and upper_size.x + 0.001 >= 1.8
		and lower_landing_overlap >= 1.7
		and upper_landing_overlap >= 1.7
		and upper_roof_overlap >= 1.0
		and lower_high_z >= landing_min_z and lower_high_z <= landing_max_z
		and upper_low_z >= landing_min_z and upper_low_z <= landing_max_z
		and upper_high_z <= -0.5 and upper_high_z >= -0.85
	)


func _interval_overlap(first_min: float, first_max: float, second_min: float, second_max: float) -> float:
	return maxf(0.0, minf(first_max, second_max) - maxf(first_min, second_min))


func _crate_pyramid_matches(vertical_by_id: Dictionary, side_id: String) -> bool:
	var inner: Dictionary = vertical_by_id.get("v2_%s_access_crate_inner" % side_id, {})
	var outer: Dictionary = vertical_by_id.get("v2_%s_access_crate_outer" % side_id, {})
	var top: Dictionary = vertical_by_id.get("v2_%s_access_crate_top" % side_id, {})
	if inner.is_empty() or outer.is_empty() or top.is_empty():
		return false
	var inner_position := MapDocument.data_to_vector(inner.get("position", {}))
	var inner_size := MapDocument.data_to_vector(inner.get("size", {}))
	var outer_position := MapDocument.data_to_vector(outer.get("position", {}))
	var outer_size := MapDocument.data_to_vector(outer.get("size", {}))
	var top_position := MapDocument.data_to_vector(top.get("position", {}))
	var top_size := MapDocument.data_to_vector(top.get("size", {}))
	var terrace_top := 1.975
	var bottom_top := inner_position.y + inner_size.y * 0.5
	return (
		is_equal_approx(inner_position.y - inner_size.y * 0.5, terrace_top)
		and is_equal_approx(outer_position.y - outer_size.y * 0.5, terrace_top)
		and is_equal_approx(top_position.y - top_size.y * 0.5, bottom_top)
		and inner_size.is_equal_approx(outer_size)
		and inner_size.is_equal_approx(top_size)
		and absf(inner_position.x - outer_position.x) <= inner_size.x * 1.1
	)


func _vertical_layer_is_mirrored(vertical_by_id: Dictionary) -> bool:
	for suffix: String in [
		"roof_ramp_lower", "roof_landing", "landing_post_0", "landing_post_1",
		"access_crate_inner", "access_crate_outer", "access_crate_top",
	]:
		var alpha: Dictionary = vertical_by_id.get("v2_a_%s" % suffix, {})
		var bravo: Dictionary = vertical_by_id.get("v2_b_%s" % suffix, {})
		if alpha.is_empty() or bravo.is_empty():
			return false
		var alpha_position := MapDocument.data_to_vector(alpha.get("position", {}))
		var bravo_position := MapDocument.data_to_vector(bravo.get("position", {}))
		if not is_equal_approx(absf(alpha_position.x), absf(bravo_position.x)):
			return false
		if not is_equal_approx(alpha_position.z, bravo_position.z):
			return false
		if not MapDocument.data_to_vector(alpha.get("size", {})).is_equal_approx(MapDocument.data_to_vector(bravo.get("size", {}))):
			return false
	return true


func _is_legacy_building_piece(object_id: String) -> bool:
	for prefix: String in [
		"center_cafe_", "a_chapel_", "b_workshop_",
		"southwest_home_", "southeast_home_", "north_inn_",
	]:
		if object_id.begins_with(prefix):
			return true
	return false


func _objects_by_id(document: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for object: Dictionary in document.get("objects", []):
		result[String(object.get("id", ""))] = object
	return result


func _same_vector(first: Variant, second: Variant) -> bool:
	return MapDocument.data_to_vector(first).is_equal_approx(MapDocument.data_to_vector(second))


func _expect(condition: bool, message: String) -> void:
	if condition:
		print("[PASS] %s" % message)
		return
	failures += 1
	push_error("[FAIL] %s" % message)
