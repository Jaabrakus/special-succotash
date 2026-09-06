class_name SocomMatchmakingDirectoryClient
extends RefCounted

## Public read-only directory boundary. Supabase supplies filtered service rows,
## SocomServiceDirectory owns selection policy, and the multiplayer session
## remains the only owner that can open the returned WebSocket endpoint. Player
## identity is deliberately not required merely to discover a public server.

const ServiceDirectory := preload("res://scripts/network/socom_service_directory.gd")
const SessionCompatibility := preload("res://scripts/network/socom_session_compatibility.gd")
const DeploymentProfile := preload("res://scripts/network/socom_multiplayer_deployment_profile.gd")

const REGION_SELECT := (
	"region_key,display_name,lifecycle,status_message,sort_order,last_probe_at"
)
const SERVER_SELECT := (
	"id,name,region,public_address,public_port,game_build,protocol_version,"
	+ "capacity,status,last_heartbeat_at,accepting_players,current_players,"
	+ "mode_key,map_key,session_stage,free_arenas"
)

var _supabase_client: SocomSupabaseClient


func _init(supabase_client: SocomSupabaseClient = null) -> void:
	_supabase_client = supabase_client


func bind_supabase_client(supabase_client: SocomSupabaseClient) -> void:
	_supabase_client = supabase_client


func list_healthy_regions(measured_latency_ms: Dictionary = {}) -> Dictionary:
	var access := _directory_access()
	if not bool(access.get("ok", false)):
		return {
			"ok": false,
			"message": String(access.get("message", "Multiplayer directory unavailable.")),
			"regions": [],
		}
	return await _fetch_healthy_regions(measured_latency_ms)


func list_healthy_servers(region_key: String, now_unix: float = -1.0) -> Dictionary:
	var access := _directory_access()
	if not bool(access.get("ok", false)):
		return {
			"ok": false,
			"message": String(access.get("message", "Multiplayer directory unavailable.")),
			"region_key": region_key,
			"servers": [],
		}
	return await _fetch_healthy_servers(region_key, _resolve_now(now_unix))


func find_quick_match(
	preferred_region: String = "auto",
	measured_latency_ms: Dictionary = {},
	now_unix: float = -1.0,
	require_secure: bool = false,
	required_mode_key: String = "",
	minimum_capacity: int = 0
) -> Dictionary:
	var access := _directory_access()
	if not bool(access.get("ok", false)):
		return {
			"ok": false,
			"message": String(access.get("message", "Multiplayer directory unavailable.")),
		}
	var region_result := await _fetch_healthy_regions(measured_latency_ms)
	if not bool(region_result.get("ok", false)):
		return region_result
	var region_choice := ServiceDirectory.choose_region(
		region_result.get("regions", []),
		preferred_region
	)
	if not bool(region_choice.get("ok", false)):
		return region_choice
	var region: Dictionary = region_choice.get("region", {})
	var region_key := String(region.get("region_key", ""))
	var server_result := await _fetch_healthy_servers(region_key, _resolve_now(now_unix))
	if not bool(server_result.get("ok", false)):
		return server_result

	# A browser must not select an otherwise healthy ws:// row and then fail at
	# connection time. Endpoint validation happens before the pure load policy.
	var secure_socket_required := require_secure or OS.has_feature("web")
	var joinable_servers: Array[Dictionary] = []
	var endpoint_by_server_id: Dictionary = {}
	for raw_server in server_result.get("servers", []):
		if raw_server is not Dictionary:
			continue
		var server := raw_server as Dictionary
		if (
			not required_mode_key.is_empty()
			and String(server.get("mode_key", "")) != required_mode_key
		):
			continue
		if int(server.get("capacity", 0)) < maxi(0, minimum_capacity):
			continue
		var endpoint := join_endpoint(server, secure_socket_required)
		if not bool(endpoint.get("ok", false)):
			continue
		joinable_servers.append(server)
		endpoint_by_server_id[String(server.get("id", ""))] = endpoint

	var server_choice := ServiceDirectory.choose_server(
		joinable_servers,
		region_key,
		SessionCompatibility.local_build(),
		SessionCompatibility.PROTOCOL_VERSION,
		_resolve_now(now_unix)
	)
	if not bool(server_choice.get("ok", false)):
		return server_choice
	var server: Dictionary = server_choice.get("server", {})
	var endpoint: Dictionary = endpoint_by_server_id.get(String(server.get("id", "")), {})
	if endpoint.is_empty():
		return {"ok": false, "message": "The selected server has no WebSocket endpoint."}
	return {
		"ok": true,
		"message": "Quick Match found %s." % String(server.get("name", "SOCOM server")),
		"region": region,
		"server": server,
		"endpoint": endpoint,
	}


static func normalize_server_row(raw_server: Dictionary) -> Dictionary:
	var server := raw_server.duplicate(true)
	server["last_heartbeat_unix"] = timestamp_to_unix(
		server.get("last_heartbeat_at", server.get("last_heartbeat_unix", 0.0))
	)
	server["public_address"] = String(server.get("public_address", "")).strip_edges()
	server["public_port"] = int(server.get("public_port", 0))
	server["current_players"] = maxi(0, int(server.get("current_players", 0)))
	server["capacity"] = maxi(0, int(server.get("capacity", 0)))
	server["protocol_version"] = int(server.get("protocol_version", 0))
	return server


static func timestamp_to_unix(value: Variant) -> float:
	if value is int or value is float:
		return float(value)
	var timestamp := String(value).strip_edges()
	if timestamp.is_empty():
		return 0.0
	if timestamp.is_valid_float():
		return float(timestamp)

	# Postgres timestamptz values are RFC 3339. Godot's Time conversion does not
	# apply a timezone suffix, so remove and apply the offset explicitly.
	var timezone_offset_seconds := 0
	if timestamp.ends_with("Z") or timestamp.ends_with("z"):
		timestamp = timestamp.left(-1)
	elif timestamp.length() >= 6:
		var timezone_start := timestamp.length() - 6
		var timezone_sign := timestamp.substr(timezone_start, 1)
		var timezone_separator := timestamp.substr(timezone_start + 3, 1)
		var timezone_hours := timestamp.substr(timezone_start + 1, 2)
		var timezone_minutes := timestamp.substr(timezone_start + 4, 2)
		if (
			timezone_sign in ["+", "-"]
			and timezone_separator == ":"
			and timezone_hours.is_valid_int()
			and timezone_minutes.is_valid_int()
		):
			timezone_offset_seconds = (
				int(timezone_hours) * 3600 + int(timezone_minutes) * 60
			)
			if timezone_sign == "-":
				timezone_offset_seconds *= -1
			timestamp = timestamp.substr(0, timezone_start)

	var fractional_seconds := 0.0
	var decimal_index := timestamp.find(".")
	if decimal_index >= 0:
		var fractional_text := timestamp.substr(decimal_index + 1)
		if not fractional_text.is_empty() and fractional_text.is_valid_int():
			fractional_seconds = float("0.%s" % fractional_text)
		timestamp = timestamp.substr(0, decimal_index)
	if not _is_supported_datetime(timestamp):
		return 0.0
	return (
		float(Time.get_unix_time_from_datetime_string(timestamp))
		+ fractional_seconds
		- float(timezone_offset_seconds)
	)


static func join_endpoint(server: Dictionary, require_secure: bool = false) -> Dictionary:
	var advertised_address := String(server.get("public_address", "")).strip_edges()
	var advertised_port := int(server.get("public_port", 0))
	if advertised_port < 1 or advertised_port > 65535:
		return {"ok": false, "message": "The server advertised an invalid port."}
	var normalized := DeploymentProfile.websocket_endpoint(
		advertised_address,
		advertised_port,
		require_secure
	)
	if not bool(normalized.get("ok", false)):
		return normalized
	var url := String(normalized.get("url", ""))
	return {
		"ok": true,
		"url": url,
		"address": url,
		"port": advertised_port,
		"transport": DeploymentProfile.TRANSPORT_WEBSOCKET,
		"secure": bool(normalized.get("secure", false)),
		"server_id": String(server.get("id", "")),
		"region": String(server.get("region", "")),
		"mode_key": String(server.get("mode_key", "demolition")),
		"map_key": String(server.get("map_key", "unknown")),
	}


func _directory_access() -> Dictionary:
	if _supabase_client == null:
		return {"ok": false, "message": "The Supabase client is unavailable."}
	if not _supabase_client.is_configured():
		return {"ok": false, "message": "The public multiplayer directory is not configured."}
	return {"ok": true}


func _fetch_healthy_regions(measured_latency_ms: Dictionary) -> Dictionary:
	var path := (
		"/rest/v1/service_regions?select=%s"
		+ "&lifecycle=in.(operational,degraded)&order=sort_order.asc,region_key.asc"
	) % REGION_SELECT
	var response: Dictionary = await _supabase_client._request_json(
		path,
		HTTPClient.METHOD_GET,
		null,
		false
	)
	if not bool(response.get("ok", false)):
		return {
			"ok": false,
			"message": _response_message(response, "Could not load multiplayer regions."),
			"regions": [],
		}
	var rows: Array = response.get("data", []) if response.get("data", []) is Array else []
	var regions: Array[Dictionary] = []
	for raw_region in rows:
		if raw_region is not Dictionary:
			continue
		var region := (raw_region as Dictionary).duplicate(true)
		if String(region.get("lifecycle", "offline")) not in ServiceDirectory.HEALTHY_REGION_STATES:
			continue
		var region_key := String(region.get("region_key", ""))
		if measured_latency_ms.has(region_key):
			region["measured_latency_ms"] = maxf(
				0.0,
				float(measured_latency_ms.get(region_key, INF))
			)
		regions.append(region)
	regions.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_order := int(a.get("sort_order", 100))
		var b_order := int(b.get("sort_order", 100))
		if a_order != b_order:
			return a_order < b_order
		return String(a.get("region_key", "")) < String(b.get("region_key", ""))
	)
	return {
		"ok": true,
		"message": "%d multiplayer region(s) available." % regions.size(),
		"regions": regions,
	}


func _fetch_healthy_servers(region_key: String, now_unix: float) -> Dictionary:
	var clean_region := region_key.strip_edges()
	if clean_region.is_empty() or clean_region == "auto":
		return {
			"ok": false,
			"message": "Select a multiplayer region before listing servers.",
			"region_key": clean_region,
			"servers": [],
		}
	var path := (
		"/rest/v1/match_servers?select=%s&region=eq.%s"
		+ "&status=eq.online&accepting_players=eq.true&order=current_players.asc,name.asc"
	) % [SERVER_SELECT, clean_region.uri_encode()]
	var response: Dictionary = await _supabase_client._request_json(
		path,
		HTTPClient.METHOD_GET,
		null,
		false
	)
	if not bool(response.get("ok", false)):
		return {
			"ok": false,
			"message": _response_message(response, "Could not load multiplayer servers."),
			"region_key": clean_region,
			"servers": [],
		}
	var rows: Array = response.get("data", []) if response.get("data", []) is Array else []
	var servers: Array[Dictionary] = []
	for raw_server in rows:
		if raw_server is not Dictionary:
			continue
		var server := normalize_server_row(raw_server as Dictionary)
		if not _is_healthy_server(server, clean_region, now_unix):
			continue
		servers.append(server)
	servers.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_players := int(a.get("current_players", 0))
		var b_players := int(b.get("current_players", 0))
		if a_players != b_players:
			return a_players < b_players
		return String(a.get("name", "")) < String(b.get("name", ""))
	)
	return {
		"ok": true,
		"message": "%d healthy server(s) available." % servers.size(),
		"region_key": clean_region,
		"servers": servers,
	}


static func _is_healthy_server(server: Dictionary, region_key: String, now_unix: float) -> bool:
	var heartbeat_unix := float(server.get("last_heartbeat_unix", 0.0))
	return (
		String(server.get("region", "")) == region_key
		and String(server.get("status", "")) == "online"
		and bool(server.get("accepting_players", false))
		and int(server.get("capacity", 0)) > 0
		and int(server.get("current_players", 0)) < int(server.get("capacity", 0))
		and heartbeat_unix > 0.0
		and now_unix - heartbeat_unix <= ServiceDirectory.SERVER_HEARTBEAT_MAX_AGE_SECONDS
	)


static func _is_supported_datetime(value: String) -> bool:
	if value.length() != 19 or value.substr(10, 1) not in ["T", " "]:
		return false
	for index in [4, 7]:
		if value.substr(index, 1) != "-":
			return false
	for index in [13, 16]:
		if value.substr(index, 1) != ":":
			return false
	var compact := value.replace("-", "").replace(":", "").replace("T", "").replace(" ", "")
	return compact.is_valid_int()


static func _response_message(response: Dictionary, fallback: String) -> String:
	var data: Variant = response.get("data", {})
	if data is Dictionary:
		for key in ["message", "msg", "error_description", "error", "hint"]:
			var message := String((data as Dictionary).get(key, ""))
			if not message.is_empty():
				return message
	var message := String(response.get("message", response.get("raw", ""))).strip_edges()
	return message if not message.is_empty() else fallback


static func _resolve_now(now_unix: float) -> float:
	return Time.get_unix_time_from_system() if now_unix <= 0.0 else now_unix
