extends SceneTree

const MAP_PATH := "res://config/maps/painterly_coastal_village_2v2.json"
const MapDocument := preload("res://scripts/maps/socom_map_document.gd")
const MapCommands := preload("res://scripts/maps/socom_map_command_service.gd")
const MapRuntime := preload("res://scripts/maps/socom_map_runtime.gd")
const MapAmbience := preload("res://scripts/maps/socom_map_ambience_engine.gd")
const MapGameplay := preload("res://scripts/maps/socom_map_gameplay_contract.gd")

var failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var document := MapDocument.load_path(MAP_PATH)
	_expect(not document.is_empty(), "bundled Morro do Sol document loads")
	_expect(String(document.get("map_id", "")) == "morro_do_sol_2v2", "map keeps its stable library id")
	var environment_data := document.get("environment", {}) as Dictionary
	_expect(String(environment_data.get("preset", "")) == "painterly_coastal", "map selects the painterly coastal atmosphere")
	_expect(String(environment_data.get("backdrop_texture", "")) == "res://assets/textures/environment/morro_do_sol_distant_coast_v1.png", "map saves the distant beach and ocean art contract")

	var validation := MapCommands.validate_document(document)
	_expect(bool(validation.get("ok", false)), "map schema and demolition requirements validate")
	if not bool(validation.get("ok", false)):
		for error: Variant in validation.get("errors", []):
			push_error("MORRO DO SOL VALIDATION: %s" % error)
	var runtime_validation := MapRuntime.validate_build(document)
	_expect(bool(runtime_validation.get("ok", false)), "all saved village objects build with runtime collision")
	_expect(int(runtime_validation.get("built_objects", 0)) == (document.get("objects", []) as Array).size(), "runtime object count matches the saved map")

	var layout := MapGameplay.demolition_layout(document)
	_expect((layout.get("alpha_spawns", []) as Array).size() == 2, "Alpha has exactly two 2v2 spawns")
	_expect((layout.get("bravo_spawns", []) as Array).size() == 2, "Bravo has exactly two 2v2 spawns")
	_expect((layout.get("bomb_pickups", []) as Array).size() == 1, "demolition has one shared bomb pickup")
	_expect((layout.get("alpha_targets", []) as Array).size() == 1, "demolition has one A site")
	_expect((layout.get("bravo_targets", []) as Array).size() == 1, "demolition has one B site")
	var rules: Dictionary = layout.get("rules", {})
	_expect(String(rules.get("primary_mode", "")) == "demolition", "demolition is the primary mode")
	_expect(not bool(rules.get("respawns_enabled", true)), "2v2 demolition disables respawns")
	_expect(int(rules.get("round_time_seconds", 0)) == 150, "compact rounds use the authored 150-second limit")

	var type_counts: Dictionary = {}
	var painterly_count := 0
	var a_entries := 0
	var b_entries := 0
	for object: Dictionary in document.get("objects", []):
		var type_name := String(object.get("type", ""))
		type_counts[type_name] = int(type_counts.get(type_name, 0)) + 1
		var properties: Dictionary = object.get("properties", {})
		if bool(properties.get("painterly_material", false)):
			painterly_count += 1
		if type_name == "doorway_wall" and String(object.get("id", "")).begins_with("a_chapel_"):
			a_entries += 1
		if type_name == "doorway_wall" and String(object.get("id", "")).begins_with("b_workshop_"):
			b_entries += 1
	_expect((document.get("objects", []) as Array).size() >= 70, "village is a complete tactical layout, not a single art prop")
	_expect(int(type_counts.get("doorway_wall", 0)) >= 10, "buildings contain walkable door openings")
	_expect(int(type_counts.get("window_wall", 0)) >= 10, "buildings contain authored window sightlines")
	_expect(int(type_counts.get("cover_low", 0)) >= 10, "lanes contain deliberate hard-cover beats")
	_expect(int(type_counts.get("ramp", 0)) >= 6, "hillside routes include multiple traversable ramps")
	_expect(int(type_counts.get("platform", 0)) >= 2, "both flanks include a middle elevation tier")
	_expect(int(type_counts.get("stairs", 0)) >= 1, "the contested center has a high roof route")
	_expect(a_entries >= 2 and b_entries >= 2, "both bomb buildings have at least two attack entrances")
	_expect(painterly_count >= 50, "architecture uses the shared painterly material treatment")

	var test_world := Node3D.new()
	root.add_child(test_world)
	var atmosphere := MapAmbience.build_into(test_world, document)
	var map_root := MapRuntime.build_into(test_world, document, true)
	var world_environment := atmosphere.get_node_or_null("MapWorldEnvironment") as WorldEnvironment if atmosphere != null else null
	_expect(world_environment != null and world_environment.environment != null, "canonical ambience owner builds WorldEnvironment")
	var sky_material: Material = world_environment.environment.sky.sky_material if world_environment != null and world_environment.environment != null and world_environment.environment.sky != null else null
	_expect(sky_material is ShaderMaterial, "painterly map uses the custom painted-cloud sky")
	var coastal_backdrop := atmosphere.get_node_or_null("DistantCoastalBackdrop") as MeshInstance3D if atmosphere != null else null
	_expect(coastal_backdrop != null and coastal_backdrop.mesh is QuadMesh, "canonical ambience owner builds the distant coastal backdrop")
	_expect(coastal_backdrop != null and coastal_backdrop.get_child_count() == 0, "distant coast remains presentation-only with no collision owner")
	_expect(map_root != null and map_root.get_child_count() == (document.get("objects", []) as Array).size(), "shared map runtime builds every village object")
	test_world.free()

	# The launcher calls this exact library path before showing its selector. Prove
	# the bundled map is seeded, selectable, and then returned by load_active(),
	# which is the same contract consumed by res://main.tscn.
	var library_path := "/private/tmp/morro_do_sol_library_regression"
	MapDocument.library_directory_override = library_path
	ProjectSettings.set_setting("socom/session/selected_map_document", {})
	MapDocument.ensure_active_map_in_library()
	var listed := false
	for entry: Dictionary in MapDocument.list_library_maps():
		if String(entry.get("map_id", "")) == "morro_do_sol_2v2":
			listed = true
			break
	_expect(listed, "launcher library automatically lists the bundled village")
	var selected := MapDocument.select_library_map("morro_do_sol_2v2")
	_expect(String(selected.get("map_id", "")) == "morro_do_sol_2v2", "launcher can select the village")
	_expect(String(MapDocument.load_active().get("map_id", "")) == "morro_do_sol_2v2", "canonical main-scene loader receives the selected village")
	var main_scene := load("res://main.tscn") as PackedScene
	var canonical_training := main_scene.instantiate() if main_scene != null else null
	if canonical_training != null:
		root.add_child(canonical_training)
		for _frame in 6:
			await process_frame
	_expect(canonical_training != null, "canonical training scene instantiates with the selected village")
	var canonical_document: Dictionary = canonical_training.get("active_map_document") as Dictionary if canonical_training != null else {}
	_expect(String(canonical_document.get("map_id", "")) == "morro_do_sol_2v2", "res://main.tscn consumes Morro do Sol as its active map")
	var canonical_map := canonical_training.get_node_or_null("AuthoredMap") if canonical_training != null else null
	var canonical_atmosphere := canonical_training.get_node_or_null("AuthoredAtmosphere") if canonical_training != null else null
	var canonical_object_count := 0
	if canonical_map != null:
		for child: Node in canonical_map.get_children():
			if not String(child.get_meta("map_object_id", "")).is_empty():
				canonical_object_count += 1
	_expect(canonical_object_count == (document.get("objects", []) as Array).size(), "res://main.tscn builds every saved village object")
	_expect(canonical_atmosphere != null and canonical_atmosphere.get_node_or_null("DistantCoastalBackdrop") != null, "res://main.tscn builds the distant coast through its ambience owner")
	if canonical_training != null:
		canonical_training.free()
	MapDocument.library_directory_override = ""
	ProjectSettings.set_setting("socom/session/selected_map_document", {})

	if failures == 0:
		print("PAINTERLY_VILLAGE_2V2_REGRESSION PASS")
	quit(1 if failures > 0 else 0)


func _expect(condition: bool, message: String) -> void:
	if condition:
		print("[PASS] %s" % message)
		return
	failures += 1
	push_error("[FAIL] %s" % message)
