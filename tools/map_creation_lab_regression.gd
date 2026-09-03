extends SceneTree

const MapDocument := preload("res://scripts/maps/socom_map_document.gd")
const MapCommands := preload("res://scripts/maps/socom_map_command_service.gd")
const MapRuntime := preload("res://scripts/maps/socom_map_runtime.gd")
const MapAmbience := preload("res://scripts/maps/socom_map_ambience_engine.gd")
const MapGameplay := preload("res://scripts/maps/socom_map_gameplay_contract.gd")
const MapAssetLibrary := preload("res://scripts/maps/socom_map_asset_library.gd")
const MovingTrainingDummy := preload("res://scripts/combat/socom_moving_training_dummy.gd")
const ControlsGuide := preload("res://scripts/ui/socom_controls_guide.gd")

var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var document := MapDocument.new_document("Regression Map")
	_expect(document.has("environment"), "new maps contain authored atmosphere")
	_expect(document.get("objects", []).size() >= 7, "new maps start with a SOCOM demolition/TDM layout")
	var demolition := MapGameplay.demolition_layout(document)
	_expect(not (demolition.get("alpha_spawns", []) as Array).is_empty(), "new maps include Alpha team spawns")
	_expect(not (demolition.get("bravo_spawns", []) as Array).is_empty(), "new maps include Bravo team spawns")
	_expect(not (demolition.get("bomb_pickups", []) as Array).is_empty(), "new maps include a neutral bomb pickup")
	var default_round_rules := MapGameplay.round_rules(document)
	_expect(int(default_round_rules.get("time_limit_seconds", 0)) == 300, "demolition starts with a five-minute round limit")
	_expect(int(default_round_rules.get("maximum_rounds", 0)) == 7, "demolition starts as a seven-round match")
	_expect(int(default_round_rules.get("rounds_to_win", 0)) == 4, "demolition defaults to first team to four rounds")
	_expect(bool(default_round_rules.get("win_by_elimination", false)), "team elimination wins a demolition round")
	_expect(bool(default_round_rules.get("win_by_bomb_detonation", false)), "bomb detonation wins a demolition round")
	_expect(is_equal_approx(float(MapGameplay.mission_rules(document).get("defuse_time_seconds", 0.0)), 5.0), "demolition starts with a five-second defuse")
	var capabilities := MapCommands.describe_capabilities()
	_expect((capabilities.get("commands", {}) as Dictionary).has("place_object"), "human and LLM editors share place_object")
	_expect((capabilities.get("commands", {}) as Dictionary).has("set_environment"), "atmosphere has a safe command interface")
	_expect((capabilities.get("commands", {}) as Dictionary).has("place_prefab"), "human and LLM editors share reusable prefab placement")
	_expect((capabilities.get("commands", {}) as Dictionary).has("place_on_object"), "LLM placement can rest objects on authored surfaces")
	_expect((capabilities.get("commands", {}) as Dictionary).has("attach_object"), "human and LLM editors can attach modular items")
	_expect((capabilities.get("commands", {}) as Dictionary).has("detach_object"), "human and LLM editors can safely detach modular items")
	_expect((capabilities.get("commands", {}) as Dictionary).has("set_object_color"), "human and LLM editors share saved light and material colors")
	var timed_match := MapCommands.apply(document, {
		"command": "set_gameplay",
		"changes": {"round_time_seconds": 180, "maximum_rounds": 9, "rounds_to_win": 5},
	})
	_expect(bool(timed_match.get("ok", false)), "human and LLM editors can author round and timer rules")
	document = timed_match.get("document", {})
	var authored_round_rules := MapGameplay.round_rules(document)
	_expect(int(authored_round_rules.get("time_limit_seconds", 0)) == 180, "authored round time reaches the gameplay contract")
	_expect(int(authored_round_rules.get("maximum_rounds", 0)) == 9, "authored maximum rounds reach the gameplay contract")
	_expect(int(authored_round_rules.get("rounds_to_win", 0)) == 5, "authored win threshold reaches the gameplay contract")

	var placed := MapCommands.apply(document, {
		"command": "place_object",
		"type": "wall",
		"id": "regression_wall",
		"position": {"x": 1.0, "y": 1.5, "z": -3.0},
	})
	_expect(bool(placed.get("ok", false)), "place command succeeds with a stable object id")
	document = placed.get("document", {})
	var moved := MapCommands.apply(document, {
		"command": "transform_object",
		"id": "regression_wall",
		"size": {"x": 6.0, "y": 3.0, "z": 0.4},
	})
	_expect(bool(moved.get("ok", false)), "transform command resizes an existing object by id")
	document = moved.get("document", {})
	var concrete_surface := MapCommands.apply(document, {
		"command": "set_object_properties", "id": "regression_wall",
		"changes": {"surface_kind": "concrete", "roughness": 0.92},
	})
	_expect(bool(concrete_surface.get("ok", false)), "procedural surface presets save through the shared command path")
	document = concrete_surface.get("document", {})
	var pbr_material := MapRuntime._material_for_object(_find_document_object_by_id(document, "regression_wall"))
	_expect(pbr_material.albedo_texture != null, "surface presets build a tiled albedo layer")
	_expect(pbr_material.normal_enabled and pbr_material.normal_texture != null, "surface presets build physical normal-map depth")
	_expect(pbr_material.roughness_texture != null, "surface presets build varied PBR roughness")
	for surface_name in ["concrete", "stucco", "muddy_limestone", "grass", "dirt", "rock"]:
		var surface_preset: Dictionary = MapDocument.SURFACE_PRESETS[surface_name]
		_expect(
			ResourceLoader.exists(String(surface_preset.get("texture_path", ""))),
			"%s uses an installed authored albedo texture" % surface_name
		)
	for shape_type in ["curved_wall", "jagged_wall", "breached_wall", "ramp"]:
		var shaped := MapCommands.apply(document, {
			"command": "place_object", "type": shape_type,
			"position": {"x": 0.0, "y": 1.5, "z": -5.0},
		})
		_expect(bool(shaped.get("ok", false)), "%s is available as authored tactical geometry" % shape_type)
		document = shaped.get("document", {})
	for modular_type in ["doorway_wall", "window_wall", "stairs", "roof", "column", "fog_zone"]:
		var modular := MapCommands.apply(document, {
			"command": "place_object", "type": modular_type,
			"position": {"x": 8.0, "y": 1.5, "z": -5.0},
		})
		_expect(bool(modular.get("ok", false)), "%s is available in the modular community kit" % modular_type)
		document = modular.get("document", {})
	var prefab := MapCommands.apply(document, {
		"command": "place_prefab", "prefab": "tactical_room",
		"group_id": "regression_room", "position": {"x": 12.0, "y": 0.0, "z": 4.0},
	})
	_expect(bool(prefab.get("ok", false)), "reusable tactical room prefab places as one validated command")
	document = prefab.get("document", {})
	var duplicated_group := MapCommands.apply(document, {
		"command": "duplicate_group", "group_id": "regression_room",
		"new_group_id": "regression_room_copy", "offset": {"x": 10.0, "y": 0.0, "z": 0.0},
	})
	_expect(bool(duplicated_group.get("ok", false)), "a grouped prefab duplicates with relative transforms intact")
	document = duplicated_group.get("document", {})
	var scaled_group := MapCommands.apply(document, {
		"command": "scale_group", "id": "regression_room_00_roof", "group_id": "regression_room", "factor": 1.25,
	})
	_expect(bool(scaled_group.get("ok", false)), "a complete building group scales around its center")
	document = scaled_group.get("document", {})
	var placed_on_surface := MapCommands.apply(document, {
		"command": "place_on_object", "type": "column", "target_id": "regression_wall", "id": "surface_column",
	})
	_expect(bool(placed_on_surface.get("ok", false)), "an object can be placed on a named surface through the shared command path")
	document = placed_on_surface.get("document", {})
	var attached := MapCommands.apply(document, {"command": "attach_object", "id": "surface_column", "parent_id": "regression_wall"})
	_expect(bool(attached.get("ok", false)), "a modular item can attach to another authored element")
	document = attached.get("document", {})
	var attached_before := MapDocument.data_to_vector(_find_document_object_by_id(document, "surface_column").get("position", {}))
	var moved_parent := MapCommands.apply(document, {
		"command": "transform_object", "id": "regression_wall",
		"position": {"x": 4.0, "y": 1.5, "z": -3.0},
	})
	document = moved_parent.get("document", {})
	var attached_after := MapDocument.data_to_vector(_find_document_object_by_id(document, "surface_column").get("position", {}))
	_expect(is_equal_approx(attached_after.x - attached_before.x, 3.0), "attached items follow parent movement")
	var detached := MapCommands.apply(document, {"command": "detach_object", "id": "surface_column"})
	_expect(bool(detached.get("ok", false)) and String((_find_document_object_by_id(detached.get("document", {}), "surface_column").get("properties", {}) as Dictionary).get("attached_to", "")).is_empty(), "detaching preserves the item without a stale parent link")
	document = detached.get("document", {})
	for dummy_type in ["training_dummy", "moving_training_dummy"]:
		var target := MapCommands.apply(document, {
			"command": "place_object", "type": dummy_type,
			"position": {"x": 2.0, "y": 0.05, "z": -2.0},
		})
		_expect(bool(target.get("ok", false)), "%s is available in the map document" % dummy_type)
		document = target.get("document", {})
	for primitive_type in ["primitive_box", "primitive_cylinder", "primitive_sphere"]:
		var primitive := MapCommands.apply(document, {
			"command": "place_object", "type": primitive_type,
			"position": {"x": -8.0, "y": 1.0, "z": 8.0}, "size": {"x": 1.5, "y": 2.5, "z": 3.5},
		})
		_expect(bool(primitive.get("ok", false)), "%s is available for open-ended construction" % primitive_type)
		document = primitive.get("document", {})
	for natural_type in ["tree", "pine_tree", "bush", "rocky_mountain"]:
		var natural_asset := MapCommands.apply(document, {
			"command": "place_object",
			"type": natural_type,
			"id": "regression_%s" % natural_type,
			"position": {"x": -4.0, "y": 0.0, "z": -6.0},
		})
		_expect(bool(natural_asset.get("ok", false)), "%s is available to human and LLM map authors" % natural_type)
		document = natural_asset.get("document", {})
	_expect(not MapAssetLibrary.is_allowed_asset_path("user://untrusted/model.glb"), "community imports are confined to the managed asset library")
	_expect(not MapAssetLibrary.is_allowed_asset_path("user://map_assets/script.gd"), "community imports reject executable project scripts")
	var imported_preview := MapAssetLibrary.instantiate_asset("res://assets/characters/ps1_night_vision_operator/NVoperatorsoldier.glb")
	_expect(bool(imported_preview.get("ok", false)), "the safe GLB loader instantiates self-contained model assets")
	var imported_preview_scene := imported_preview.get("scene") as Node
	if imported_preview_scene != null:
		imported_preview_scene.free()
	var imported_object := MapCommands.apply(document, {
		"command": "place_object",
		"type": "imported_asset",
		"id": "regression_imported_asset",
		"name": "Imported GLB Fixture",
		"position": {"x": 4.0, "y": 0.0, "z": 4.0},
		"size": {"x": 0.5, "y": 0.5, "z": 0.5},
		"properties": {
			"asset_path": "res://assets/characters/ps1_night_vision_operator/NVoperatorsoldier.glb",
			"collision_mode": "box",
			"collision_enabled": true,
		},
	})
	_expect(bool(imported_object.get("ok", false)), "imported GLB assets use the same safe human and LLM placement command")
	document = imported_object.get("document", {})
	var atmosphere := MapCommands.apply(document, {"command": "apply_environment_preset", "preset": "moonlit_night"})
	_expect(bool(atmosphere.get("ok", false)), "atmosphere preset command succeeds")
	document = atmosphere.get("document", {})
	_expect(String((document.get("environment", {}) as Dictionary).get("preset", "")) == "moonlit_night", "atmosphere preset remains in the document")
	var validation := MapCommands.validate_document(document)
	_expect(bool(validation.get("ok", false)), "authored map validates for play")
	var crossfire := MapDocument.load_path("res://config/maps/crossfire_basin_8v8.json")
	var crossfire_validation := MapCommands.validate_document(crossfire)
	_expect(bool(crossfire_validation.get("ok", false)), "the 8v8 Crossfire Basin map validates for demolition and TDM")
	var crossfire_runtime_check := MapRuntime.validate_build(crossfire)
	_expect(bool(crossfire_runtime_check.get("ok", false)), "every Crossfire Basin object builds with its required runtime pieces")
	_expect(int(crossfire_runtime_check.get("built_objects", 0)) == (crossfire.get("objects", []) as Array).size(), "Crossfire Basin runtime object count matches its saved JSON")
	_expect((crossfire.get("objects", []) as Array).size() >= 100, "Crossfire Basin contains a full 8v8 tactical layout")
	var crossfire_tree_count := 0
	var crossfire_bush_count := 0
	for crossfire_object: Dictionary in crossfire.get("objects", []):
		if String(crossfire_object.get("type", "")) in ["tree", "pine_tree"]:
			crossfire_tree_count += 1
		elif String(crossfire_object.get("type", "")) == "bush":
			crossfire_bush_count += 1
	_expect(crossfire_tree_count >= 24, "Crossfire Basin has a dense perimeter tree backdrop without filling combat lanes")
	_expect(crossfire_bush_count >= 12, "Crossfire Basin uses restrained enterable concealment bushes around flank cover")
	for required_type in ["doorway_wall", "window_wall", "breached_wall", "stairs", "roof", "fog_zone"]:
		_expect(_find_document_object(crossfire, required_type) != null, "Crossfire Basin uses %s in its upgraded real-world layout" % required_type)
	var save_path := "/private/tmp/socom_map_creation_regression.json"
	_expect(MapDocument.save_path(document, save_path), "map document saves to JSON")
	var reloaded := MapDocument.load_path(save_path)
	_expect(String(reloaded.get("name", "")) == "Regression Map", "saved map document loads without losing identity")
	var reloaded_round_rules := MapGameplay.round_rules(reloaded)
	_expect(int(reloaded_round_rules.get("time_limit_seconds", 0)) == 180, "saved map keeps its authored round time")
	_expect(int(reloaded_round_rules.get("maximum_rounds", 0)) == 9, "saved map keeps its authored match length")
	_expect(int(reloaded_round_rules.get("rounds_to_win", 0)) == 5, "saved map keeps its authored win threshold")
	DirAccess.remove_absolute(save_path)

	MapDocument.library_directory_override = "/private/tmp/socom_map_library_regression_%s" % Time.get_ticks_usec()
	ProjectSettings.set_setting("socom/session/selected_map_document", {})
	var alpha_map := MapDocument.new_document("Alpha Harbor")
	var bravo_map := MapDocument.new_document("Bravo Ridge")
	var alpha_save := MapDocument.save_to_library(alpha_map)
	var bravo_save := MapDocument.save_to_library(bravo_map)
	_expect(bool(alpha_save.get("ok", false)) and bool(bravo_save.get("ok", false)), "browser map library saves more than one named map")
	var saved_maps := MapDocument.list_library_maps()
	_expect(saved_maps.size() == 2, "browser map library lists every saved map")
	var reopened := MapDocument.select_library_map(String(alpha_map.get("map_id", "")))
	_expect(String(reopened.get("name", "")) == "Alpha Harbor", "a saved map can be reopened for further editing")
	_expect(String(MapDocument.load_active().get("name", "")) == "Alpha Harbor", "the selected host map becomes the active multiplayer map")

	var test_world := Node3D.new()
	root.add_child(test_world)
	var atmosphere_root := MapAmbience.build_into(test_world, document)
	var runtime_root := MapRuntime.build_into(test_world, document, true)
	_expect(atmosphere_root != null and atmosphere_root.get_node_or_null("MapWorldEnvironment") != null, "runtime builds the saved sky and lighting")
	_expect(runtime_root != null and runtime_root.get_child_count() == document.get("objects", []).size(), "runtime builds every authored object")
	var doorway_runtime := _find_map_node(runtime_root, "doorway_wall")
	_expect(doorway_runtime != null and doorway_runtime.find_children("CollisionShape3D", "CollisionShape3D", true, false).size() >= 3, "doorway walls build a walkable opening with compound collision")
	var breached_runtime := _find_map_node(runtime_root, "breached_wall")
	_expect(breached_runtime != null and breached_runtime.find_children("CollisionShape3D", "CollisionShape3D", true, false).size() >= 4, "breached walls build a playable hole with compound collision")
	var stairs_runtime := _find_map_node(runtime_root, "stairs")
	var stair_ramp := (
		stairs_runtime.get_node_or_null("TraversalRamp/CollisionShape3D") as CollisionShape3D
		if stairs_runtime != null
		else null
	)
	_expect(
		stairs_runtime != null
		and stairs_runtime.find_children("Step*", "MeshInstance3D", true, false).size() >= 3
		and stair_ramp != null
		and stair_ramp.shape is ConvexPolygonShape3D,
		"stairs keep visible treads over one smooth traversable collision ramp"
	)
	var bomb_pickup_runtime := _find_map_node(runtime_root, "bomb_pickup")
	_expect(
		bomb_pickup_runtime != null
		and bomb_pickup_runtime.find_child("BombPickupPreview", true, false) != null
		and bomb_pickup_runtime.find_child("Satchel", true, false) is MeshInstance3D,
		"the editor shows the physical demolition bomb at its authored pickup"
	)
	var roof_runtime := _find_map_node(runtime_root, "roof")
	var roof_visual := roof_runtime.find_child("Visual", true, false) as MeshInstance3D if roof_runtime != null else null
	var roof_material := roof_visual.material_override as StandardMaterial3D if roof_visual != null else null
	_expect(roof_material != null and roof_material.albedo_color.get_luminance() < 0.76, "roof and floor slabs retain concrete midtones instead of washing out white")
	for natural_type in ["tree", "pine_tree", "rocky_mountain"]:
		var natural_node := _find_map_node(runtime_root, natural_type)
		_expect(natural_node != null, "%s survives save and builds in the shared runtime" % natural_type)
		_expect(
			natural_node != null and natural_node.get_node_or_null("CollisionShape3D") is CollisionShape3D,
			"%s has gameplay collision" % natural_type
		)
		if natural_type in ["tree", "pine_tree"] and natural_node != null:
			var trunk_visual := natural_node.find_child("TrunkVisual", true, false) as MeshInstance3D
			var foliage_visual := natural_node.find_child("Foliage00", true, false) as MeshInstance3D
			var trunk_material := trunk_visual.material_override as StandardMaterial3D if trunk_visual != null else null
			var foliage_material := foliage_visual.material_override as StandardMaterial3D if foliage_visual != null else null
			_expect(trunk_material != null and trunk_material.albedo_texture != null, "%s uses textured bark" % natural_type)
			_expect(foliage_material != null and foliage_material.albedo_texture != null, "%s uses textured foliage" % natural_type)
	var mountain_runtime := _find_map_node(runtime_root, "rocky_mountain")
	var mountain_visual := mountain_runtime.find_child("Visual", true, false) as MeshInstance3D if mountain_runtime != null else null
	var mountain_material := mountain_visual.material_override as StandardMaterial3D if mountain_visual != null else null
	_expect(mountain_material != null and mountain_material.normal_texture != null, "mountains always receive the detailed rock material")
	_expect(mountain_material != null and mountain_material.albedo_color.get_luminance() < 0.55, "stone materials stay dark enough for tactical scene readability")
	var imported_runtime := _find_map_node(runtime_root, "imported_asset")
	_expect(imported_runtime != null and imported_runtime.find_child("ImportedContent", true, false) is Node3D, "imported GLB geometry survives save and builds in Map Lab")
	_expect(imported_runtime != null and imported_runtime.get_node_or_null("EditorSelectionCollision") is CollisionShape3D, "imported assets remain selectable regardless of gameplay collision mode")
	var bush_runtime := _find_map_node(runtime_root, "bush")
	var bush_foliage := bush_runtime.find_child("Foliage00", true, false) as MeshInstance3D if bush_runtime != null else null
	var bush_material := bush_foliage.material_override as StandardMaterial3D if bush_foliage != null else null
	_expect(bush_runtime != null and bush_material != null and bush_material.albedo_texture != null, "concealment bushes build with textured dense foliage")
	_expect(bush_runtime != null and bush_runtime.get_node_or_null("EditorSelectionCollision") is CollisionShape3D, "concealment bushes remain selectable in Map Lab")
	var playable_runtime_root := MapRuntime.build_into(test_world, document, false)
	var playable_bush := _find_map_node(playable_runtime_root, "bush")
	_expect(playable_bush != null and playable_bush.find_children("*", "CollisionShape3D", true, false).is_empty(), "gameplay bushes remain enterable instead of becoming hard cover")
	var playable_site := _find_map_node(playable_runtime_root, "alpha_bomb_site")
	_expect(playable_site != null and playable_site.find_child("PaintRing00", true, false) is MeshInstance3D, "playable bomb sites use a permanent ground-painted tactical marker")
	_expect(playable_site != null and playable_site.find_child("BombSiteLetter", true, false) is Label3D, "playable bomb sites clearly identify their plant zone")
	var safety_perimeter := (
		playable_runtime_root.get_node_or_null("SafetyPerimeter")
		if playable_runtime_root != null
		else null
	)
	_expect(
		safety_perimeter != null and safety_perimeter.get_child_count() == 4,
		"playable maps receive four invisible collision borders"
	)
	_expect(playable_runtime_root != null and playable_runtime_root.get_node_or_null("TacticalFogZoneController") != null, "playable maps blend localized tactical fog zones")
	_expect(playable_runtime_root != null and playable_runtime_root.find_child("FogSightlineLayers", true, false) != null, "playable fog zones obscure authored sightlines from both sides")
	var playable_fog := _find_map_node(playable_runtime_root, "fog_zone") as Area3D
	var smoke_instances := (
		playable_fog.find_child("SmokeCloudInstances", true, false) as MultiMeshInstance3D
		if playable_fog != null
		else null
	)
	_expect(
		smoke_instances != null
		and smoke_instances.multimesh != null
		and smoke_instances.multimesh.instance_count <= 8,
		"tactical fog uses one bounded instanced smoke group instead of crossed opacity walls"
	)
	_expect(
		playable_fog != null and playable_fog.collision_layer == 0 and playable_fog.collision_mask == 0,
		"invisible fog volumes never block bullet or camera sight rays"
	)
	var ambience_object := MapDocument.make_object(&"ambience_zone", Vector3.ZERO, Vector3(12.0, 4.0, 12.0))
	var playable_ambience := MapRuntime.build_object(ambience_object, false) as Area3D
	_expect(
		playable_ambience != null and playable_ambience.collision_layer == 0 and playable_ambience.collision_mask == 0,
		"invisible ambience volumes never block bullet or camera sight rays"
	)
	if playable_ambience != null:
		playable_ambience.free()
	if safety_perimeter != null:
		var every_border_collides := true
		for border in safety_perimeter.get_children():
			every_border_collides = (
				every_border_collides
				and border is StaticBody3D
				and border.get_node_or_null("CollisionShape3D") is CollisionShape3D
			)
		_expect(every_border_collides, "each playable border is a real movement collider")
	var moving_dummy := MovingTrainingDummy.new()
	moving_dummy.position = Vector3.ZERO
	test_world.add_child(moving_dummy)
	moving_dummy.configure_patrol({"patrol_distance": 6.0, "patrol_speed": 2.0, "turn_pause": 0.0})
	var dummy_start := moving_dummy.global_position
	moving_dummy._physics_process(0.5)
	_expect(not moving_dummy.global_position.is_equal_approx(dummy_start), "moving training dummy follows its authored patrol")
	test_world.free()

	var controls := ControlsGuide.new()
	root.add_child(controls)
	await process_frame
	_expect(controls.find_child("ControlsGuideButton", true, false) != null, "gameplay exposes the F3 Controls Guide button")
	controls.toggle()
	var controls_text := controls.find_child("CompleteControlsText", true, false) as RichTextLabel
	_expect(controls_text != null and "F10" in controls_text.text and "MAP LAB" in controls_text.text, "Controls Guide lists function keys and Map Lab controls")
	controls.free()

	var packed := load("res://map_creation_lab.tscn") as PackedScene
	_expect(packed != null, "Map Lab scene loads")
	if packed != null:
		var lab := packed.instantiate()
		root.add_child(lab)
		await process_frame
		await process_frame
		_expect(lab.find_child("MapEditorViewport", true, false) != null, "Map Lab exposes the visual editor viewport")
		var lab_document := lab.call("get_map_document") as Dictionary
		var first_lab_object: Dictionary = (lab_document.get("objects", []) as Array)[0]
		await physics_frame
		var lab_camera := lab.get("camera") as Camera3D
		var lab_container := lab.find_child("MapEditorViewport", true, false) as SubViewportContainer
		var lab_subviewport := lab.find_child("MapSubViewport", true, false) as SubViewport
		var first_world_position := MapDocument.data_to_vector(first_lab_object.get("position", {}))
		var projected_position := lab_camera.unproject_position(first_world_position)
		var click_position := Vector2(
			projected_position.x / maxf(float(lab_subviewport.size.x), 1.0) * lab_container.size.x,
			projected_position.y / maxf(float(lab_subviewport.size.y), 1.0) * lab_container.size.y
		)
		var actual_pick := lab.call("_pick_object", click_position) as Dictionary
		_expect(not String(actual_pick.get("id", "")).is_empty(), "fullscreen viewport coordinates resolve to a real map object")
		lab.call("_set_navigation_mode", true)
		var preview_identity_before_selection := (lab.get("preview_root") as Node3D).get_instance_id()
		lab.call("_select_object_from_view_hit", String(actual_pick.get("id", "")))
		await process_frame
		_expect((lab.get("preview_root") as Node3D).get_instance_id() == preview_identity_before_selection, "selecting one asset does not rebuild the complete map")
		var picked_document_object := _find_document_object_by_id(lab.call("get_map_document") as Dictionary, String(actual_pick.get("id", "")))
		_expect(not bool(lab.get("navigation_mode")) and String(lab.get("selected_id")) == String(actual_pick.get("id", "")), "clicking visible geometry in Camera mode selects it and switches to Edit Assets")
		var selected_runtime := _find_map_node(lab.get("preview_root") as Node3D, String(picked_document_object.get("type", "")))
		var selected_visual := selected_runtime.find_child("Visual", true, false) as MeshInstance3D if selected_runtime != null else null
		var selected_material := selected_visual.material_override as StandardMaterial3D if selected_visual != null else null
		_expect(selected_material != null and selected_material.emission_enabled, "clicked map geometry receives an obvious highlight")
		_expect(selected_runtime != null and selected_runtime.get_node_or_null("SelectionBounds") is Node3D, "selected geometry receives an explicit visible selection cage")
		_expect(lab.get_window().content_scale_mode == Window.CONTENT_SCALE_MODE_DISABLED, "Map Lab uses the native window resolution instead of stretching a 720p canvas")
		var map_subviewport := lab.find_child("MapSubViewport", true, false) as SubViewport
		_expect(map_subviewport != null and map_subviewport.msaa_3d == Viewport.MSAA_4X, "Map Lab renders map geometry with 4x multisample anti-aliasing")
		var essential_ui_fits := true
		var visible_size: Vector2 = lab.get_viewport_rect().size
		for essential_name in ["MapName", "SavedMapSelector", "OpenSavedMapButton", "SaveMapButton", "ValidateMapButton", "PlayAuthoredMapButton", "MapNavigationMode", "MapFullView", "MapSelectedAssetActions"]:
			var essential_control := lab.find_child(essential_name, true, false) as Control
			if essential_control == null:
				essential_ui_fits = false
				continue
			var visible_rect: Rect2 = essential_control.get_global_rect()
			var control_fits := visible_rect.position.x >= -1.0 and visible_rect.position.y >= -1.0 and visible_rect.end.x <= visible_size.x + 1.0 and visible_rect.end.y <= visible_size.y + 1.0
			if not control_fits:
				print("MAP_UI_FIT_DIAGNOSTIC %s rect=%s viewport=%s" % [essential_name, visible_rect, visible_size])
			essential_ui_fits = essential_ui_fits and control_fits
		_expect(essential_ui_fits, "essential Map Lab controls fit inside the minimum supported window")
		_expect(lab.find_child("Palette_wall", true, false) != null, "Map Lab exposes a wall placement tool")
		_expect(lab.find_child("Palette_point_light", true, false) != null, "Map Lab exposes practical lighting")
		_expect(lab.find_child("Palette_ambience_zone", true, false) != null, "Map Lab exposes ambience zones")
		_expect(lab.find_child("Palette_fog_zone", true, false) != null, "Map Lab exposes tactical fog zones")
		_expect(lab.find_child("MapSightlineBlock", true, false) != null, "Map Lab exposes saved sightline-fog strength")
		_expect(lab.find_child("MapVisualLayers", true, false) != null, "Map Lab exposes saved sightline-fog quality")
		_expect(lab.find_child("Palette_doorway_wall", true, false) != null, "Map Lab exposes doorway architecture")
		_expect(lab.find_child("Palette_window_wall", true, false) != null, "Map Lab exposes window architecture")
		_expect(lab.find_child("Palette_stairs", true, false) != null, "Map Lab exposes traversable stairs")
		_expect(lab.find_child("MapFloorLevel", true, false) != null, "Map Lab exposes vertical floor levels")
		_expect(lab.find_child("MapSurfaceSnap", true, false) != null, "Map Lab exposes click-to-surface placement")
		_expect(lab.find_child("Prefab_tactical_room", true, false) != null, "Map Lab exposes reusable tactical room prefabs")
		_expect(lab.find_child("DuplicateMapGroupButton", true, false) != null, "Map Lab can duplicate grouped structures")
		_expect(lab.find_child("Palette_curved_wall", true, false) != null, "Map Lab exposes curved wall shaping")
		_expect(lab.find_child("Palette_jagged_wall", true, false) != null, "Map Lab exposes broken tactical walls")
		_expect(lab.find_child("Palette_breached_wall", true, false) != null, "Map Lab exposes playable breached walls with holes")
		_expect(lab.find_child("BreachedWallInspector", true, false) != null, "Map Lab exposes breached-wall hole shaping")
		_expect(lab.find_child("Palette_tree", true, false) != null, "Map Lab exposes broadleaf trees")
		_expect(lab.find_child("Palette_pine_tree", true, false) != null, "Map Lab exposes pine trees")
		_expect(lab.find_child("Palette_bush", true, false) != null, "Map Lab exposes enterable concealment bushes")
		_expect(lab.find_child("ImportCommunityGLB", true, false) is Button, "Map Lab exposes safe self-contained GLB importing")
		_expect(lab.find_child("CommunityAssetList", true, false) is VBoxContainer, "Map Lab exposes a persistent local community asset library")
		_expect(lab.find_child("ImportedAssetCollisionMode", true, false) is OptionButton, "imported assets expose no, box, and detailed static collision")
		_expect(lab.find_child("Palette_rocky_mountain", true, false) != null, "Map Lab exposes procedural mountains")
		var rocky_button := lab.find_child("Palette_rocky_mountain", true, false) as Button
		var object_count_before_palette: int = ((lab.call("get_map_document") as Dictionary).get("objects", []) as Array).size()
		if rocky_button != null:
			rocky_button.pressed.emit()
			await process_frame
		var palette_document := lab.call("get_map_document") as Dictionary
		_expect(palette_document.get("objects", []).size() == object_count_before_palette + 1, "pressing a build-palette button immediately creates a visible object")
		var palette_objects: Array = palette_document.get("objects", [])
		var palette_last: Dictionary = palette_objects.back() if not palette_objects.is_empty() else {}
		_expect(String(palette_last.get("type", "")) == "rocky_mountain", "the Rocky Mountain palette button creates the requested asset")
		_expect(lab.find_child("RockyMountainInspector", true, false) != null, "Map Lab exposes mountain shape controls")
		_expect(lab.find_child("Palette_bomb_pickup", true, false) != null, "Map Lab exposes the neutral demolition bomb")
		_expect(lab.find_child("Palette_training_dummy", true, false) != null, "Map Lab exposes stationary training dummies")
		_expect(lab.find_child("Palette_moving_training_dummy", true, false) != null, "Map Lab exposes moving training dummies")
		_expect(lab.find_child("MapTransformMode", true, false) != null, "Map Lab exposes mouse transform-mode cycling")
		_expect(lab.find_child("MapNavigationMode", true, false) != null, "Map Lab exposes explicit Camera and Edit Assets modes")
		_expect(lab.find_child("MapFullView", true, false) != null, "Map Lab exposes a full map view without side panels")
		_expect(lab.find_child("PublishCommunityMapButton", true, false) is Button, "Map Lab exposes community publishing")
		_expect(lab.find_child("RefreshCommunityMapsButton", true, false) is Button, "Map Lab exposes the published map browser")
		_expect(lab.find_child("DownloadCommunityMapButton", true, false) is Button, "Map Lab can download a community map into the local playtest library")
		var play_map_button := lab.find_child("PlayAuthoredMapButton", true, false) as Button
		_expect(play_map_button != null and "Play Map" in play_map_button.text, "Map Lab exposes direct Save + Play Map")
		_expect(lab.find_child("MapSelectedAssetActions", true, false) != null, "Map Lab gives humans visible selected-asset actions")
		_expect(lab.find_child("MapObjectContextMenu", true, false) is PopupMenu, "right-click exposes selected-item actions and properties")
		_expect(lab.find_child("MapAttachNextItem", true, false) is Button, "selected objects can receive a newly attached palette item")
		_expect(lab.find_child("MapGameplayCollision", true, false) is CheckButton, "selected objects expose a plain-language gameplay collision property")
		_expect(lab.find_child("MapAssetMove", true, false) != null and lab.find_child("MapAssetRotate", true, false) != null and lab.find_child("MapAssetResize", true, false) != null, "selected assets expose direct Move, Rotate, and Resize controls")
		lab.call("_set_navigation_mode", true)
		var camera_yaw_before: float = lab.get("orbit_yaw")
		var navigation_press := InputEventMouseButton.new()
		navigation_press.button_index = MOUSE_BUTTON_MIDDLE
		navigation_press.pressed = true
		lab.call("_on_viewport_gui_input", navigation_press)
		var navigation_motion := InputEventMouseMotion.new()
		navigation_motion.relative = Vector2(18.0, -7.0)
		lab.call("_on_viewport_gui_input", navigation_motion)
		var navigation_release := InputEventMouseButton.new()
		navigation_release.button_index = MOUSE_BUTTON_MIDDLE
		navigation_release.pressed = false
		lab.call("_on_viewport_gui_input", navigation_release)
		_expect(not is_equal_approx(float(lab.get("orbit_yaw")), camera_yaw_before), "Mouse 3 drag orbits the map without stealing left-click selection")
		_expect(lab.find_child("MapCameraView", true, false) != null, "Map Lab exposes perspective, top, front, side, focus, and frame-all camera views")
		var camera_target_before: Vector3 = lab.get("orbit_target")
		var pan_motion := InputEventMouseMotion.new()
		pan_motion.relative = Vector2(24.0, 12.0)
		lab.call("_pan_camera", pan_motion)
		_expect((lab.get("orbit_target") as Vector3).distance_to(camera_target_before) > 0.01, "middle-drag camera panning moves the editor viewpoint")
		lab.call("_frame_all_camera")
		_expect(float(lab.get("orbit_distance")) >= 8.0, "frame-all camera view fits the complete map")
		_expect(lab.find_child("BrowseMapTextureButton", true, false) != null, "Map Lab exposes texture selection")
		_expect(lab.find_child("MapSurfacePreset", true, false) != null, "Map Lab exposes procedural grass and concrete presets")
		_expect(lab.find_child("MapMaterialColor", true, false) != null, "Map Lab exposes surface tint painting for procedural and imported textures")
		_expect(lab.find_child("MapLightColor", true, false) != null, "Map Lab exposes saved light color controls")
		var warm_light_button := lab.find_child("LightPreset_warm_lamp", true, false) as Button
		var before_light_count: int = ((lab.call("get_map_document") as Dictionary).get("objects", []) as Array).size()
		if warm_light_button != null:
			warm_light_button.pressed.emit()
			await process_frame
		var light_document := lab.call("get_map_document") as Dictionary
		var light_objects: Array = light_document.get("objects", [])
		var light_last: Dictionary = light_objects.back() if not light_objects.is_empty() else {}
		_expect(light_objects.size() == before_light_count + 1 and String(light_last.get("type", "")) == "point_light", "a lighting preset immediately creates a saved practical light")
		_expect(lab.find_child("MapUniformScale", true, false) != null, "Map Lab exposes universal object scaling")
		_expect(lab.find_child("ScaleWholeMapGroup", true, false) != null, "Map Lab exposes whole-building group scaling")
		_expect(lab.find_child("Palette_primitive_box", true, false) != null, "Map Lab exposes a freeform scalable box")
		_expect(lab.find_child("Palette_primitive_cylinder", true, false) != null, "Map Lab exposes a freeform scalable cylinder")
		_expect(lab.find_child("Palette_primitive_sphere", true, false) != null, "Map Lab exposes a freeform scalable sphere")
		var validate_button := lab.find_child("ValidateMapButton", true, false) as Button
		if validate_button != null:
			validate_button.pressed.emit()
			await process_frame
		var health_status := lab.find_child("MapLabStatus", true, false) as Label
		_expect(health_status != null and "MAP HEALTHY" in health_status.text, "visible Map Health Check validates save, reload, runtime build, lights, and collisions")
		_expect(lab.find_child("RepairSocomMissionButton", true, false) != null, "older maps can add missing SOCOM mission markers in one click")
		_expect(lab.find_child("MapRoundTime", true, false) != null, "Map Lab exposes the round time limit")
		_expect(lab.find_child("MapMaximumRounds", true, false) != null, "Map Lab exposes the match round count")
		_expect(lab.find_child("MapRoundsToWin", true, false) != null, "Map Lab exposes the rounds-to-win threshold")
		_expect(lab.find_child("MapPlantTime", true, false) != null, "Map Lab exposes bomb plant time")
		_expect(lab.find_child("MapDefuseTime", true, false) != null, "Map Lab exposes bomb defuse time")
		_expect(lab.find_child("MapBombFuse", true, false) != null, "Map Lab exposes bomb fuse time")
		_expect(lab.find_child("DemolitionWinConditions", true, false) != null, "Map Lab explains demolition round win conditions")
		_expect(lab.find_child("MapCommandJSON", true, false) != null, "Map Lab exposes the optional safe command surface")
		_expect(lab.find_child("SaveMapButton", true, false) != null, "Map Lab exposes save")
		_expect(lab.find_child("PlayAuthoredMapButton", true, false) != null, "Map Lab exposes save-and-play")
		lab.free()

	_finish()


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("MAP_CREATION_CHECK PASS ", label)
	else:
		failures.append(label)
		push_error("MAP_CREATION_CHECK FAIL %s" % label)


func _find_map_node(runtime_root: Node, type_name: String) -> Node:
	if runtime_root == null:
		return null
	for child: Node in runtime_root.get_children():
		if String(child.get_meta("map_object_type", "")) == type_name:
			return child
	return null


func _find_document_object(document: Dictionary, type_name: String) -> Variant:
	for object: Dictionary in document.get("objects", []):
		if String(object.get("type", "")) == type_name:
			return object
	return null


func _find_document_object_by_id(document: Dictionary, object_id: String) -> Dictionary:
	for object: Dictionary in document.get("objects", []):
		if String(object.get("id", "")) == object_id:
			return object
	return {}


func _finish() -> void:
	if failures.is_empty():
		print("MAP_CREATION_LAB_REGRESSION PASS")
		quit(0)
	else:
		print("MAP_CREATION_LAB_REGRESSION FAIL ", failures)
		quit(1)
