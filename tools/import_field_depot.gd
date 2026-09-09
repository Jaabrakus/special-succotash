extends SceneTree
## Local-only importer. Never changes current_map.json or overwrites an edited map.

const MapDocument := preload("res://scripts/maps/socom_map_document.gd")
const DOCUMENT := "res://config/maps/field_depot_research.json"
const MANIFEST := "res://config/maps/field_depot_assets.json"
const LIBRARY_MAP := "user://maps/field_depot_research.json"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var source := ""
	for arg in args:
		if arg.begins_with("--source="):
			source = arg.trim_prefix("--source=")
	if source.is_empty():
		_fail("Pass --source=/absolute/path/to/SOCOM-II-map-assets/library")
		return
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	var destination := String(manifest["destination"])
	var receipt: Array[Dictionary] = []
	# Validate every source and collision before writing anything.
	for entry: Dictionary in manifest["textures"]:
		var from := source.path_join(String(entry["source"]))
		var to := destination.path_join(String(entry["target"]))
		var image := Image.new()
		if image.load(from) != OK or image.is_empty():
			_fail("Missing or invalid texture: %s" % from)
			return
		var digest := FileAccess.get_sha256(from)
		if FileAccess.file_exists(to) and FileAccess.get_sha256(to) != digest:
			_fail("Preserving modified asset; destination differs: %s" % to)
			return
		receipt.append({"source": from, "target": to, "sha256": digest, "width": image.get_width(), "height": image.get_height()})
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(destination)) != OK:
		_fail("Cannot create local asset library.")
		return
	for entry in receipt:
		if not FileAccess.file_exists(entry["target"]):
			if DirAccess.copy_absolute(entry["source"], ProjectSettings.globalize_path(entry["target"])) != OK:
				_fail("Copy failed: %s" % entry["target"])
				return
	var document := MapDocument.load_path(DOCUMENT)
	if not FileAccess.file_exists(LIBRARY_MAP):
		if not MapDocument.save_path(document, LIBRARY_MAP):
			_fail("Could not save map library entry.")
			return
	else:
		document = MapDocument.load_path(LIBRARY_MAP)
		if document.is_empty():
			_fail("Existing map is invalid; left untouched: %s" % LIBRARY_MAP)
			return
	var receipt_path := destination.path_join("provenance.json")
	if not FileAccess.file_exists(receipt_path):
		var file := FileAccess.open(receipt_path, FileAccess.WRITE)
		if file == null:
			_fail("Cannot write provenance receipt.")
			return
		file.store_string(JSON.stringify({"manifest": manifest, "files": receipt}, "\t"))
		file.close()
	print("FIELD_DEPOT_IMPORT PASS: %d textures; map %s" % [receipt.size(), ProjectSettings.globalize_path(LIBRARY_MAP)])
	if args.has("--open-editor"):
		ProjectSettings.set_setting("socom/session/selected_map_document", document)
		change_scene_to_file("res://map_creation_lab.tscn")
	else:
		quit()


func _fail(message: String) -> void:
	push_error("FIELD_DEPOT_IMPORT FAIL: " + message)
	quit(1)
