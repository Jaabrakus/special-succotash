extends SceneTree
func _initialize() -> void:
	var profile: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://config/network/browser_multiarena_deployment.json"))
	assert(profile.server_map_document == "res://config/maps/relic_depot.json")
	var map: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(profile.server_map_document))
	var active: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://config/maps/current_map.json"))
	assert(active.map_id == map.map_id)
	for object: Dictionary in map.objects:
		var path := String(object.get("properties", {}).get("asset_path", ""))
		if not path.is_empty():
			assert(ResourceLoader.exists(path), "missing depot asset: " + path)
	for path in ["res://scripts/audio/acoustic_propagation_engine.gd", "res://scripts/audio/lab_leak_audio_engine.gd"]:
		assert(FileAccess.get_file_as_string(path).contains("playback_type = AudioServer.PLAYBACK_TYPE_STREAM"))
	assert(FileAccess.get_file_as_string("res://deploy/server/Dockerfile.dockerignore").contains("!assets/environment/**"))
	print("DEPOT_WEB_RELEASE PASS: map resources and audio playback contract; browser output needs live probe")
	quit()
