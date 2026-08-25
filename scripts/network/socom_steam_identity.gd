class_name SocomSteamIdentity
extends RefCounted

## GodotSteam Player Identity & Authentication Adapter
## Integrates Steamworks Persona Name, SteamID64, and Avatar with safe fallback.

const DEFAULT_CALLSIGN := "OPERATOR"

static var _steam_initialized: bool = false
static var _is_checking: bool = false


static func is_steam_available() -> bool:
	if Engine.has_singleton("Steam"):
		return true
	if ClassDB.class_exists("Steam"):
		return true
	return false


static func get_player_identity(fallback_peer_id: int = 1) -> Dictionary:
	if is_steam_available():
		var steam_singleton: Object = null
		if Engine.has_singleton("Steam"):
			steam_singleton = Engine.get_singleton("Steam")
		elif ClassDB.class_exists("Steam"):
			steam_singleton = ClassDB.instantiate("Steam")

		if steam_singleton != null and steam_singleton.has_method("getPersonaName"):
			var persona: String = String(steam_singleton.call("getPersonaName")).strip_edges()
			var steam_id: int = 0
			if steam_singleton.has_method("getSteamID"):
				steam_id = int(steam_singleton.call("getSteamID"))
			if not persona.is_empty():
				return {
					"ok": true,
					"source": "steam",
					"user_id": "steam_%d" % steam_id if steam_id != 0 else "steam_local",
					"display_name": persona,
					"steam_id": steam_id,
				}

	# Clean local fallback
	var safe_name := "SPECTRE-%d" % fallback_peer_id if fallback_peer_id > 1 else "SPECTRE"
	return {
		"ok": true,
		"source": "local_guest",
		"user_id": "guest-%d" % fallback_peer_id,
		"display_name": safe_name,
		"steam_id": 0,
	}
