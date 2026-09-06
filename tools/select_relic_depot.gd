extends SceneTree
## Select through the existing library workflow, with a recoverable active-map copy.
const MapDocument := preload("res://scripts/maps/socom_map_document.gd")
func _initialize() -> void:
	call_deferred("_run")
func _run() -> void:
	var backup := "res://art_source/relic_depot_integration/previous_active_map.json"
	if not FileAccess.file_exists(backup):
		assert(MapDocument.save_path(MapDocument.load_active(), backup))
	var saved: Dictionary = MapDocument.save_to_library(MapDocument.load_path("res://config/maps/relic_depot.json"))
	if not saved.get("ok", false):
		push_error("Could not select Relic Depot: " + str(saved))
		quit(1)
		return
	print("RELIC_DEPOT_SELECTED ", saved.path)
	if OS.get_cmdline_user_args().has("--play"):
		ProjectSettings.set_setting("socom/playtest/use_active_bundle", false)
		change_scene_to_file("res://main.tscn")
	else:
		quit()
