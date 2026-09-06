extends SceneTree

## Read-only acceptance check for a reviewed GLB already imported into the
## checkout/library. Does not activate maps, install code or certify security.
const Library := preload("res://scripts/maps/socom_map_asset_library.gd")
const Commands := preload("res://scripts/maps/socom_map_command_service.gd")
const Document := preload("res://scripts/maps/socom_map_document.gd")
const Runtime := preload("res://scripts/maps/socom_map_runtime.gd")
const EXAMPLE := "res://config/contributor_examples/place_map_prop.json"

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var command: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(EXAMPLE))
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--asset="):
			command.properties.asset_path = arg.trim_prefix("--asset=")
	var asset_path := String(command.properties.asset_path)
	var loaded := Library.instantiate_asset(asset_path)
	if not bool(loaded.get("ok", false)):
		push_error("CONTRIBUTED_MAP_PROP FAIL: " + String(loaded.get("message", "load rejected")))
		quit(1)
		return
	loaded.scene.free()
	var result := Commands.apply(Document.new_document("Contributor preview"), command)
	if not bool(result.get("ok", false)):
		push_error("CONTRIBUTED_MAP_PROP FAIL: command rejected " + str(result))
		quit(1)
		return
	var errors: Array[String] = []
	var matched := 0
	for object: Dictionary in result.document.objects:
		if object.get("id") != command.id:
			continue
		matched += 1
		for mode in ["none", "box", "detailed_mesh"]:
			object.properties.collision_mode = mode
			var body := Runtime.build_object(object, false)
			if body == null or not body.has_node("ImportedContent"):
				errors.append(mode + ": runtime content missing")
			elif (body.find_children("*", "CollisionShape3D", true, false).size() > 0) != (mode != "none"):
				errors.append(mode + ": unexpected collision result")
			if body != null:
				body.free()
	if matched != 1:
		errors.append("saved command did not produce exactly one identified prop")
	print("CONTRIBUTED_MAP_PROP ", "PASS" if errors.is_empty() else "FAIL",
		" path=", asset_path, " meshes=", loaded.mesh_count, " vertices=", loaded.vertex_count,
		" errors=", errors, " (manual visual/performance/licensing review still required)")
	quit(0 if errors.is_empty() else 1)
