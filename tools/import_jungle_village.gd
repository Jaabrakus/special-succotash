extends SceneTree
const Maps := preload("res://scripts/maps/socom_map_document.gd")
const Assets := preload("res://scripts/maps/socom_map_asset_library.gd")
const Runtime := preload("res://scripts/maps/socom_map_runtime.gd")
const Commands := preload("res://scripts/maps/socom_map_command_service.gd")
const SPEC := "res://config/maps/jungle_village_placement.json"
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var kit := ""
	var replace_sha := ""
	for arg in args:
		if arg.begins_with("--kit="): kit = arg.trim_prefix("--kit=")
		if arg.begins_with("--replace-sha="): replace_sha = arg.trim_prefix("--replace-sha=")
	if not FileAccess.file_exists(kit.path_join("conversion.json")):
		_fail("Pass --kit=<converted jungle GLB directory>")
		return
	var spec: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SPEC))
	var source_path: String = spec["source_map"]
	var source_hash := FileAccess.get_sha256(source_path)
	var source := Maps.load_path(source_path)
	if source.is_empty():
		_fail("Original village is missing")
		return
	var paths := {}
	for filename in DirAccess.get_files_at(kit):
		if not filename.ends_with(".glb"): continue
		var from := kit.path_join(filename)
		var existing: String = Assets.USER_ASSET_DIRECTORY.path_join(filename.to_lower())
		if FileAccess.file_exists(existing) and FileAccess.get_sha256(existing) == FileAccess.get_sha256(from):
			paths[filename] = existing
		else:
			var result := Assets.import_glb(from)
			if not result.get("ok", false):
				_fail(str(result))
				return
			paths[filename] = result["path"]
	var document := source.duplicate(true)
	document["map_id"] = spec["map_id"]
	document["name"] = spec["name"]
	for key: String in spec.get("environment_overrides", {}):
		document["environment"][key] = spec["environment_overrides"][key]
	var host := Node3D.new()
	root.add_child(host)
	Runtime.build_into(host, source, false)
	await physics_frame
	await physics_frame
	var added := 0
	var rejected := 0
	for entry: Dictionary in spec["placements"]:
		var a: Array = entry["position"]
		var p := Vector3(a[0],a[1],a[2])
		var ray := PhysicsRayQueryParameters3D.create(Vector3(p.x,70,p.z),Vector3(p.x,-20,p.z),1)
		var hit := host.get_world_3d().direct_space_state.intersect_ray(ray)
		# Reject covered grass, roof intersections or changed geometry; never plant on a roof.
		if hit.is_empty() or absf(hit["position"].y-p.y)>float(spec["max_surface_error"]):
			rejected += 1
			continue
		var object := Maps.make_object(&"imported_asset", hit["position"], Vector3.ONE*float(entry["scale"]))
		object["id"] = entry["id"]
		object["name"] = "Jungle " + String(entry["asset"]).get_basename()
		object["rotation_degrees"] = Maps.vector_to_data(Vector3(0,entry["yaw"],0))
		# Decoration is nonblocking. Never use leaf-card triangles as gameplay walls.
		object["properties"] = {"asset_path":paths[entry["asset"]],"collision_mode":"none","collision_enabled":false}
		document["objects"].append(object)
		added += 1
	host.free()
	if added < 100 or not Commands.validate_document(document).get("ok",false):
		_fail("Insufficient valid placements or invalid saved contract")
		return
	var destination: String = spec["library_path"]
	if FileAccess.file_exists(destination) and not replace_sha.is_empty():
		if FileAccess.get_sha256(destination) != replace_sha:
			_fail("Variant changed since inspection; preserved")
			return
		if not Maps.save_path(document,destination):
			_fail("Variant refresh failed")
			return
	elif FileAccess.file_exists(destination): document = Maps.load_path(destination)
	elif not Maps.save_path(document,destination):
		_fail("Map save failed")
		return
	if source_hash != FileAccess.get_sha256(source_path):
		_fail("Original village changed during import")
		return
	print("JUNGLE_VILLAGE_IMPORT PASS: %d assets; %d grass placements; %d occluded candidates skipped; original preserved" % [paths.size(),added,rejected])
	if args.has("--open-editor"):
		ProjectSettings.set_setting("socom/session/selected_map_document",document)
		change_scene_to_file("res://map_creation_lab.tscn")
		await scene_changed
		current_scene.set("orbit_target",Vector3(90,10,78))
		current_scene.set("orbit_distance",180.0)
		current_scene.call("_update_camera")
		print("JUNGLE_VILLAGE_EDITOR READY")
	else: quit()
func _fail(message: String) -> void:
	push_error("JUNGLE_VILLAGE_IMPORT FAIL: "+message)
	quit(1)
