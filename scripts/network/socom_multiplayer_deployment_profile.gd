class_name SocomMultiplayerDeploymentProfile
extends RefCounted

## Saved deployment boundary shared by the launcher and canonical multiplayer
## scene. It selects transport only; MultiplayerAPI/session authority remains in
## SocomMultiplayerSession and match authority remains on the server.

const PROFILE_PATH := "res://config/network/browser_multiarena_deployment.json"
const TRANSPORT_ENET := "enet"
const TRANSPORT_WEBSOCKET := "websocket"
const MatchInvite := preload("res://scripts/network/socom_match_invite.gd")


static func load_profile(path: String = PROFILE_PATH) -> Dictionary:
	var profile := {
		"schema_version": 1,
		"default_port": 14141,
		"dedicated_transport": TRANSPORT_WEBSOCKET,
		"browser_transport": TRANSPORT_WEBSOCKET,
		"browser_server_url": "",
		"server_map_document": "res://config/maps/painterly_coastal_village_2v2.json",
		"require_secure_browser_socket": true,
		"max_players": 32,
		"arena_instances": 8,
		"players_per_arena": 4,
	}
	if not FileAccess.file_exists(path):
		return profile
	var file := FileAccess.open(path, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(file.get_as_text()) if file != null else null
	if parsed is Dictionary:
		profile.merge(parsed as Dictionary, true)
	profile["default_port"] = clampi(int(profile.get("default_port", 14141)), 1, 65535)
	profile["max_players"] = clampi(int(profile.get("max_players", 32)), 1, 32)
	profile["arena_instances"] = clampi(int(profile.get("arena_instances", 8)), 1, 8)
	profile["players_per_arena"] = clampi(int(profile.get("players_per_arena", 4)), 2, 4)
	profile["dedicated_transport"] = _normalized_transport(
		String(profile.get("dedicated_transport", TRANSPORT_WEBSOCKET))
	)
	profile["browser_transport"] = TRANSPORT_WEBSOCKET
	profile["browser_server_url"] = String(
		profile.get("browser_server_url", "")
	).strip_edges()
	profile["server_map_document"] = String(
		profile.get(
			"server_map_document",
			"res://config/maps/painterly_coastal_village_2v2.json"
		)
	).strip_edges()
	profile["require_secure_browser_socket"] = bool(
		profile.get("require_secure_browser_socket", true)
	)
	return profile


static func requested_server_transport(
	args: PackedStringArray,
	dedicated: bool,
	profile: Dictionary
) -> String:
	for argument: String in args:
		if argument.begins_with("--mp-transport="):
			return _normalized_transport(argument.trim_prefix("--mp-transport="))
	if args.has("--mp-websocket"):
		return TRANSPORT_WEBSOCKET
	if dedicated:
		return _normalized_transport(String(profile.get(
			"dedicated_transport",
			TRANSPORT_WEBSOCKET
		)))
	return TRANSPORT_ENET


static func requested_client_transport(
	address: String,
	args: PackedStringArray,
	is_web: bool
) -> String:
	if is_web:
		return TRANSPORT_WEBSOCKET
	var clean := address.strip_edges().to_lower()
	if clean.begins_with("ws://") or clean.begins_with("wss://"):
		return TRANSPORT_WEBSOCKET
	for argument: String in args:
		if argument.begins_with("--mp-transport="):
			return _normalized_transport(argument.trim_prefix("--mp-transport="))
	if args.has("--mp-websocket"):
		return TRANSPORT_WEBSOCKET
	return TRANSPORT_ENET


static func websocket_endpoint(
	value: String,
	default_port: int,
	require_secure: bool
) -> Dictionary:
	var clean := value.strip_edges()
	if clean.is_empty():
		return {
			"ok": false,
			"message": "Enter the dedicated server's wss:// address.",
		}
	var lower := clean.to_lower()
	if lower.begins_with("wss://"):
		return {"ok": true, "url": clean, "secure": true}
	if lower.begins_with("ws://"):
		if require_secure:
			return {
				"ok": false,
				"message": "Browser play on itch.io requires a secure wss:// server address.",
			}
		return {"ok": true, "url": clean, "secure": false}
	if clean.contains("/"):
		return {
			"ok": false,
			"message": "WebSocket paths must include the full ws:// or wss:// URL.",
		}
	var parsed := MatchInvite.parse(clean, default_port)
	if not bool(parsed.get("ok", false)):
		return parsed
	var scheme := "wss" if require_secure else "ws"
	return {
		"ok": true,
		"url": "%s://%s:%d" % [
			scheme,
			String(parsed.get("address", "127.0.0.1")),
			int(parsed.get("port", default_port)),
		],
		"secure": require_secure,
	}


static func browser_query_server_url() -> String:
	if not OS.has_feature("web"):
		return ""
	var result: Variant = JavaScriptBridge.eval(
		"new URLSearchParams(window.location.search).get('server') || ''"
	)
	return String(result).strip_edges() if result is String else ""


static func _normalized_transport(value: String) -> String:
	return (
		TRANSPORT_WEBSOCKET
		if value.strip_edges().to_lower() == TRANSPORT_WEBSOCKET
		else TRANSPORT_ENET
	)
