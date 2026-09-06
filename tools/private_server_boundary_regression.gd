extends SceneTree

func _initialize() -> void:
	var session := FileAccess.get_file_as_string("res://scripts/network/socom_multiplayer_session.gd")
	var state := FileAccess.get_file_as_string("res://scripts/network/socom_multiplayer_state.gd")
	var tournament := FileAccess.get_file_as_string("res://scripts/network/socom_multiplayer_tournament_runtime.gd")
	assert(not state.contains("ServerBackendScript"))
	assert(session.contains('if OS.has_feature("web"):\n\t\treturn ERR_UNAVAILABLE'))
	assert(not session.contains("as SocomServerBackend"))
	assert(not tournament.contains('preload("res://scripts/server/socom_tournament_event_outbox.gd")'))
	assert(tournament.contains('if OS.has_feature("web") or not dedicated_server_mode or not multiplayer.is_server():'))
	# Native services still instantiate; browser absence is proved by the PCK audit.
	var backend = load("res://scripts/server/socom_server_backend.gd").new()
	assert(backend.has_method("register_dedicated_server"))
	backend.free()
	var outbox = load("res://scripts/server/socom_tournament_event_outbox.gd").new()
	assert(outbox.has_method("start_session"))
	assert(load("res://multiplayer_slice.tscn") != null)
	print("PRIVATE_SERVER_BOUNDARY PASS: native services and scene load; run export audit for browser absence")
	quit()
