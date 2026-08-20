extends SceneTree

const MapDocument := preload("res://scripts/maps/socom_map_document.gd")
const MapCommands := preload("res://scripts/maps/socom_map_command_service.gd")


func _initialize() -> void:
	var options := _parse_options(OS.get_cmdline_user_args())
	if options.has("describe"):
		print(JSON.stringify(MapCommands.describe_capabilities(), "  "))
		quit(0)
		return
	var map_path := String(options.get("map", MapDocument.ACTIVE_MAP_PATH))
	var document := MapDocument.load_path(map_path)
	if document.is_empty():
		document = MapDocument.new_document()
	var command := _load_command(options)
	if command.is_empty():
		_print_error("Provide --command-file=PATH or --command-json=JSON. Use --describe for the contract.")
		return
	var result := MapCommands.apply(document, command)
	if not bool(result.get("ok", false)):
		print(JSON.stringify(result))
		quit(1)
		return
	var validation := MapCommands.validate_document(result.get("document", {}))
	result["validation"] = validation
	result["saved"] = false
	if not options.has("dry-run"):
		result["saved"] = MapDocument.save_path(result["document"], map_path)
		if not bool(result["saved"]):
			result["ok"] = false
			result["message"] = "Command succeeded but the map could not be saved."
	print(JSON.stringify(result, "  "))
	quit(0 if bool(result.get("ok", false)) else 1)


func _parse_options(arguments: PackedStringArray) -> Dictionary:
	var options := {}
	for argument: String in arguments:
		if argument == "--describe":
			options["describe"] = true
		elif argument == "--dry-run":
			options["dry-run"] = true
		elif argument.begins_with("--map="):
			options["map"] = argument.trim_prefix("--map=")
		elif argument.begins_with("--command-file="):
			options["command-file"] = argument.trim_prefix("--command-file=")
		elif argument.begins_with("--command-json="):
			options["command-json"] = argument.trim_prefix("--command-json=")
	return options


func _load_command(options: Dictionary) -> Dictionary:
	var source := String(options.get("command-json", ""))
	var command_file := String(options.get("command-file", ""))
	if not command_file.is_empty():
		if not FileAccess.file_exists(command_file):
			return {}
		var file := FileAccess.open(command_file, FileAccess.READ)
		source = file.get_as_text() if file else ""
	var parsed: Variant = JSON.parse_string(source)
	return parsed as Dictionary if parsed is Dictionary else {}


func _print_error(message: String) -> void:
	print(JSON.stringify({"ok": false, "message": message}))
	quit(2)
