extends SceneTree
## Local research kit only. Existing assets and edited maps are never overwritten.
const Assets := preload("res://scripts/maps/socom_map_asset_library.gd")
const Maps := preload("res://scripts/maps/socom_map_document.gd")
const Runtime := preload("res://scripts/maps/socom_map_runtime.gd")
const MAP_PATH := "user://maps/mp51_geometry_kit.json"
const SPEC := "res://config/maps/mp51_geometry_kit_spec.json"

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var kit := ""
	var source := ""
	for arg in args:
		if arg.begins_with("--kit="): kit = arg.trim_prefix("--kit=")
		if arg.begins_with("--world="): source = arg.trim_prefix("--world=")
	if kit.is_empty() or source.is_empty():
		_fail("Pass --kit=<converted props> --world=<converted world>")
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(source.path_join("world.json")))
	if not parsed is Dictionary or not parsed.has("chunks"):
		_fail("Missing world manifest")
		return
	var report: Dictionary = parsed
	var spec: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SPEC))
	if report["chunks"].size() != int(spec["expected_world_chunks"]):
		_fail("World conversion does not match this kit specification")
		return
	var imported := {}
	for folder in [kit, source]:
		for filename in DirAccess.get_files_at(folder):
			if not filename.ends_with(".glb") or filename == "overview.glb": continue
			var from: String = folder.path_join(filename)
			var existing: String = Assets.USER_ASSET_DIRECTORY.path_join(filename.to_lower())
			if FileAccess.file_exists(existing) and FileAccess.get_sha256(existing) == FileAccess.get_sha256(from):
				imported[filename] = existing
				continue
			var result := Assets.import_glb(from)
			if not result.get("ok", false):
				_fail(str(result))
				return
			imported[filename] = result["path"]
	var document := Maps.new_document(spec["name"])
	document["map_id"] = spec["map_id"]
	document["gameplay"]["primary_mode"] = "team_deathmatch"
	document["gameplay"]["supported_modes"] = ["team_deathmatch"]
	document["objects"] = []
	document["environment"] = Maps.environment_from_preset("high_contrast_day")
	for chunk: Dictionary in report["chunks"]:
		var xyz: Array = chunk["origin"]
		var object := Maps.make_object(&"imported_asset", Vector3(xyz[0],xyz[1],xyz[2]), Vector3.ONE)
		object["id"] = "mp51_" + String(chunk["name"])
		object["name"] = "MP51 " + String(chunk["name"])
		object["properties"] = {"asset_path": imported[chunk["file"]], "collision_mode": "detailed_mesh", "collision_enabled": true}
		document["objects"].append(object)
	# Place a local preview spawn on a surface verified by the canonical collision builder.
	var host := Node3D.new()
	root.add_child(host)
	Runtime.build_into(host, document, false)
	await physics_frame
	await physics_frame
	var query := PhysicsRayQueryParameters3D.create(Vector3(90,60,78), Vector3(90,-20,78), 1)
	var hit := host.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		host.free()
		_fail("No verified preview spawn surface; map not saved")
		return
	var position: Vector3 = hit["position"] + Vector3.UP * 0.1
	document["objects"].append(Maps.make_object(&"player_spawn", position))
	for spawn_spec in [[&"team_alpha_spawn", Vector3(80,60,78)], [&"team_bravo_spawn", Vector3(100,60,78)]]:
		var start: Vector3 = spawn_spec[1]
		var team_hit := host.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(start, start - Vector3.UP * 80, 1))
		if team_hit.is_empty():
			host.free()
			_fail("No verified team preview surface")
			return
		document["objects"].append(Maps.make_object(spawn_spec[0], team_hit["position"] + Vector3.UP * 0.1))
	host.free()
	if FileAccess.file_exists(MAP_PATH):
		document = Maps.load_path(MAP_PATH)
	elif not Maps.save_path(document, MAP_PATH):
		_fail("Map save failed")
		return
	print("SOCOM_GEOMETRY_IMPORT PASS: %d assets, %d world chunks; %s" % [imported.size(), report["chunks"].size(), ProjectSettings.globalize_path(MAP_PATH)])
	if args.has("--open-editor"):
		ProjectSettings.set_setting("socom/session/selected_map_document", document)
		change_scene_to_file("res://map_creation_lab.tscn")
		await scene_changed
		current_scene.set("orbit_target", Vector3(90,8,78))
		current_scene.set("orbit_distance", 180.0)
		current_scene.call("_update_camera")
		print("SOCOM_GEOMETRY_EDITOR READY: original geometry study")
	else: quit()

func _fail(message: String) -> void:
	push_error("SOCOM_GEOMETRY_IMPORT FAIL: " + message)
	quit(1)
