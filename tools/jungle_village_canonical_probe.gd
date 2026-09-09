extends SceneTree
const Maps := preload("res://scripts/maps/socom_map_document.gd")
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	var document := Maps.load_path("user://maps/mp51_jungle_village.json")
	assert(not document.is_empty())
	ProjectSettings.set_setting("socom/session/selected_map_document",document)
	assert(change_scene_to_file("res://main.tscn")==OK)
	await scene_changed
	for i in range(12): await physics_frame
	assert(current_scene.scene_file_path=="res://main.tscn")
	assert(current_scene.get("active_map_document")["map_id"]=="mp51_jungle_village")
	assert(current_scene.has_node("AuthoredMap"))
	print("JUNGLE_CANONICAL_PROBE PASS: main.tscn consumes the saved Jungle Village")
	quit()
