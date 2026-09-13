extends Node
## Selection/launch only. Gameplay always enters the canonical main scene.
const Maps := preload("res://scripts/maps/socom_map_document.gd")
const MAP_PATH := "user://maps/desert_glory_rebuild.json"
const SOURCE_MAP_PATH := "user://maps/desert_glory_source_enhanced.json"

func _ready() -> void:
	var selected := SOURCE_MAP_PATH if FileAccess.file_exists(SOURCE_MAP_PATH) and not "--replacement-assets" in OS.get_cmdline_user_args() else MAP_PATH
	var document := Maps.load_path(selected)
	if document.is_empty():
		push_error("Build the local Desert Glory map with tools/build_desert_glory.gd first.")
		return
	ProjectSettings.set_setting("socom/session/selected_map_document", document)
	ProjectSettings.set_setting("socom/playtest/use_active_bundle", false)
	var scene := "res://map_creation_lab.tscn" if "--map-editor" in OS.get_cmdline_user_args() else "res://main.tscn"
	get_tree().change_scene_to_file.call_deferred(scene)
