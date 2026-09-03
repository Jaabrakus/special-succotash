extends "res://scripts/network/socom_multiplayer_admission.gd"

## Supplies bounded, read-only session facts to SocomServerBackend. This layer
## does not publish rows and cannot change lobby, match, or combat authority.


func _server_directory_snapshot() -> Dictionary:
	var gameplay: Dictionary = (
		active_map_document.get("gameplay", {})
		if active_map_document.get("gameplay", {}) is Dictionary
		else {}
	)
	var stage := "lobby"
	match String(lobby.phase):
		LobbyStateScript.PHASE_COUNTDOWN:
			stage = "countdown"
		LobbyStateScript.PHASE_PLAYING, LobbyStateScript.PHASE_ROUND_END:
			stage = "active"
		LobbyStateScript.PHASE_MATCH_END:
			stage = "complete"
	return {
		"current_players": lobby.players.size(),
		"mode_key": String(gameplay.get("primary_mode", "demolition")),
		"map_key": String(active_map_document.get("map_id", "unknown")),
		"session_stage": stage,
		"free_arenas": 1 if stage == "lobby" else 0,
	}
