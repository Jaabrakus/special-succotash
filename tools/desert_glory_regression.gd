extends SceneTree
const Maps := preload("res://scripts/maps/socom_map_document.gd")
const Commands := preload("res://scripts/maps/socom_map_command_service.gd")
const Runtime := preload("res://scripts/maps/socom_map_runtime.gd")
const Ambience := preload("res://scripts/maps/socom_map_ambience_engine.gd")
var errors: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	_expect(Maps.normalize_environment({}).film_grain_strength == 0.0, "Existing maps default grain off")
	_expect(Maps.normalize_environment({"film_grain_strength": 5}).film_grain_strength == 0.12, "Grain is bounded")
	var document := Maps.new_document("Grain regression")
	var result := Commands.apply(document, {"command":"set_environment", "changes":{"film_grain_strength":0.035}})
	_expect(result.ok and is_equal_approx(result.document.environment.film_grain_strength,0.035), "Map editor command writes shared field")
	_expect(is_equal_approx(Maps.normalize_environment(document.environment).film_grain_strength,0.0), "Command does not mutate original/undo data")
	var roundtrip := "/private/tmp/desert-glory-grain-roundtrip.json"
	_expect(Maps.save_path(result.document, roundtrip), "Shared contract saves")
	_expect(Maps.load_path(roundtrip) == result.document, "Shared contract roundtrips")
	var host := Node3D.new()
	root.add_child(host)
	var atmosphere := Ambience.build_into(host, result.document)
	var grain := atmosphere.get_node_or_null("MapFilmGrain")
	if DisplayServer.get_name() == "headless":
		_expect(grain == null, "No screen layer on headless server")
	else:
		_expect(grain != null and grain.layer == -1, "Grain renders below HUD")
		_expect(is_equal_approx(grain.get_node("GrainOverlay").material.get_shader_parameter("strength"),0.035), "Shader consumes saved strength")
	host.free()
	if "--local-map" in OS.get_cmdline_user_args():
		var source_variant := "--source-assets" in OS.get_cmdline_user_args()
		document = Maps.load_path("user://maps/desert_glory_source_enhanced.json" if source_variant else "user://maps/desert_glory_rebuild.json")
		_expect(not document.is_empty(), "Local map installed")
		if not document.is_empty():
			_expect(document.map_id == ("desert_glory_source_enhanced" if source_variant else "desert_glory_local"), "Correct library selection")
			var sectors := 0
			var props := 0
			host = Node3D.new()
			root.add_child(host)
			Runtime.build_into(host, document, false)
			await physics_frame
			await physics_frame
			for object: Dictionary in document.objects:
				if String(object.id).begins_with("dg_sector_"):
					sectors += 1
					_expect(FileAccess.file_exists(object.properties.asset_path), "Sector asset exists")
					_expect(object.properties.collision_mode == "detailed_mesh", "Architecture has exact mesh collision")
				if String(object.id).begins_with("dg_prop_"): props += 1
				if String(object.id).begins_with("dg_source_prop_"):
					props += 1
					_expect(bool(object.properties.get("local_research_only", false)), "Source prop provenance retained")
				if source_variant and String(object.type) == "imported_asset":
					_expect(not String(object.properties.asset_path).contains("relic_depot"), "No substitute props in source variant")
				if String(object.type).ends_with("spawn"):
					var position := Maps.data_to_vector(object.position)
					var hit := host.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(position + Vector3.UP * .1, position - Vector3.UP * .3, 1))
					_expect(not hit.is_empty() and (hit.normal as Vector3).y >= .85, "Spawn supported: " + String(object.type))
			_expect(sectors == 10 and props == (95 if source_variant else 40), "Architecture and prop census")
		host.free()
	if "--editor" in OS.get_cmdline_user_args():
		Maps.library_directory_override = "/private/tmp/desert-glory-editor-regression-library"
		var test_document := Maps.new_document("Grain editor test")
		test_document.environment["film_grain_strength"] = 0.018
		ProjectSettings.set_setting("socom/session/selected_map_document", test_document)
		change_scene_to_file("res://map_creation_lab.tscn")
		await scene_changed
		for frame in 3: await process_frame
		var lab := current_scene
		var field := lab.environment_fields["film_grain_strength"] as SpinBox
		_expect(is_equal_approx(field.value,0.018), "Map Lab reads shared grain")
		field.value = 0.05
		_expect(is_equal_approx(lab.document.environment.film_grain_strength,0.05), "Map Lab changes shared grain")
		lab._undo()
		_expect(is_equal_approx(lab.document.environment.film_grain_strength,0.018), "Map Lab undo restores grain")
		lab.free()
	print("DESERT_GLORY_REGRESSION ", "PASS" if errors.is_empty() else "FAIL", " ", errors)
	quit(0 if errors.is_empty() else 1)

func _expect(ok: bool, label: String) -> void:
	if not ok:
		errors.append(label)
		push_error(label)
