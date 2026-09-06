extends SceneTree

const MatchmakingDirectoryClient := preload(
	"res://scripts/network/socom_matchmaking_directory_client.gd"
)
const SupabaseClient := preload("res://scripts/network/socom_supabase_client.gd")
const SessionCompatibility := preload("res://scripts/network/socom_session_compatibility.gd")

const NOW_UNIX := 2_000_000.0
const PUBLIC_CONFIG_PATH := "res://config/supabase_public.json"

var failures: Array[String] = []
var requests: Array[Dictionary] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var public_config_value: Variant = JSON.parse_string(
		FileAccess.get_file_as_string(PUBLIC_CONFIG_PATH)
	)
	var public_config: Dictionary = (
		public_config_value as Dictionary
		if public_config_value is Dictionary
		else {}
	)
	_expect(
		String(public_config.get("project_url", "")).begins_with("https://")
		and String(public_config.get("publishable_key", "")).begins_with("sb_publishable_"),
		"browser package has a public-only Supabase endpoint and publishable key"
	)
	_expect(
		not public_config.has("service_role_key")
		and not public_config.has("server_key")
		and not public_config.has("secret_key"),
		"browser Supabase config contains no privileged server credential"
	)
	var public_headers := SupabaseClient.request_headers("sb_publishable_regression")
	var authenticated_headers := SupabaseClient.request_headers(
		"sb_publishable_regression",
		"player-access-token"
	)
	var legacy_headers := SupabaseClient.request_headers("eyJheader.payload.signature")
	_expect(
		_header_starts_with(public_headers, "apikey: ")
		and not _header_starts_with(public_headers, "Authorization: Bearer "),
		"opaque publishable keys use apikey only for public directory reads"
	)
	_expect(
		_header_starts_with(authenticated_headers, "Authorization: Bearer player-access-token")
		and _header_starts_with(legacy_headers, "Authorization: Bearer eyJ"),
		"player access tokens and legacy anon JWTs retain bearer authorization"
	)

	var supabase := SupabaseClient.new()
	supabase.session_path = "/private/tmp/socom_matchmaking_directory_session.json"
	supabase.request_adapter = Callable(self, "_fake_request")
	root.add_child(supabase)
	supabase.project_url = "https://example.supabase.co"
	supabase.publishable_key = "sb_publishable_regression"
	supabase.session = {
		"user_id": "00000000-0000-0000-0000-000000000141",
		"display_name": "DirectoryTester",
		"access_token": "regression-access-token",
		"refresh_token": "regression-refresh-token",
		"expires_at": int(Time.get_unix_time_from_system()) + 3600,
	}

	var directory := MatchmakingDirectoryClient.new(supabase)
	var timestamp := MatchmakingDirectoryClient.timestamp_to_unix(
		"1970-01-01T01:00:10.500+01:00"
	)
	_expect(
		is_equal_approx(timestamp, 10.5),
		"Postgres timestamptz offsets and fractional seconds normalize to Unix time"
	)

	var regions: Dictionary = await directory.list_healthy_regions({
		"us-east": 35.0,
		"eu-west": 92.0,
	})
	var region_rows: Array = regions.get("regions", [])
	_expect(
		bool(regions.get("ok", false))
		and region_rows.size() == 2
		and String((region_rows[0] as Dictionary).get("region_key", "")) == "us-east"
		and is_equal_approx(float((region_rows[0] as Dictionary).get("measured_latency_ms", INF)), 35.0),
		"public region listing rejects maintenance regions and applies measured latency"
	)

	var servers: Dictionary = await directory.list_healthy_servers("us-east", NOW_UNIX)
	var server_rows: Array = servers.get("servers", [])
	_expect(
		bool(servers.get("ok", false))
		and server_rows.size() == 4
		and float((server_rows[0] as Dictionary).get("last_heartbeat_unix", 0.0)) > 0.0
		and String((server_rows[0] as Dictionary).get("mode_key", "")) == "gunfight_2v2"
		and int((server_rows[0] as Dictionary).get("free_arenas", -1)) == 7,
		"server listing normalizes heartbeat time, preserves presence, and rejects stale, full, or off-region rows"
	)

	var secure_quick_match: Dictionary = await directory.find_quick_match(
		"auto",
		{"us-east": 35.0, "eu-west": 92.0},
		NOW_UNIX,
		true,
		"gunfight_2v2",
		32
	)
	var secure_server: Dictionary = secure_quick_match.get("server", {})
	var secure_endpoint: Dictionary = secure_quick_match.get("endpoint", {})
	_expect(
		bool(secure_quick_match.get("ok", false))
		and String(secure_server.get("name", "")) == "healthy-secure"
		and String(secure_endpoint.get("url", "")) == "wss://east.example.test/socom"
		and String(secure_endpoint.get("address", "")) == "wss://east.example.test/socom"
		and String(secure_endpoint.get("transport", "")) == "websocket"
		and String(secure_endpoint.get("mode_key", "")) == "gunfight_2v2"
		and String(secure_endpoint.get("map_key", "")) == "painterly-coastal-village"
		and bool(secure_endpoint.get("secure", false)),
		"browser tournament matchmaking rejects ws-only, incompatible, wrong-mode, and undersized rows"
	)

	var native_quick_match: Dictionary = await directory.find_quick_match(
		"us-east",
		{},
		NOW_UNIX,
		false
	)
	var native_server: Dictionary = native_quick_match.get("server", {})
	var native_endpoint: Dictionary = native_quick_match.get("endpoint", {})
	_expect(
		bool(native_quick_match.get("ok", false))
		and String(native_server.get("name", "")) == "healthy-native"
		and String(native_endpoint.get("url", "")) == "ws://127.0.0.1:14141"
		and not bool(native_endpoint.get("secure", true)),
		"native Quick Match selects the lowest-population compatible server and returns ws endpoint data"
	)

	_expect(
		_all_directory_requests_use_public_read_access(),
		"service_regions and match_servers use public read access without blocking on identity"
	)
	var public_policy := FileAccess.get_file_as_string(
		"res://supabase/migrations/20260902002000_public_matchmaking_directory.sql"
	)
	_expect(
		public_policy.contains(
			"grant select on public.service_regions, public.match_servers to anon"
		)
		and public_policy.contains("for select to anon")
		and public_policy.contains("'us-east'")
		and not public_policy.contains("grant insert")
		and not public_policy.contains("grant update"),
		"anonymous directory migration grants filtered SELECT only and seeds the default region"
	)
	_expect(
		SessionCompatibility.local_build() == "0.1.0",
		"Quick Match compatibility is bound to the canonical application build"
	)

	supabase.free()
	if failures.is_empty():
		print("MATCHMAKING_DIRECTORY_CLIENT_REGRESSION PASS")
		quit(0)
		return
	for failure in failures:
		push_error("MATCHMAKING_DIRECTORY_CLIENT_REGRESSION FAIL: " + failure)
	quit(1)


func _fake_request(
	path: String,
	method: HTTPClient.Method,
	body: Variant,
	authenticated: bool,
	prefer: String
) -> Dictionary:
	requests.append({
		"path": path,
		"method": method,
		"body": body,
		"authenticated": authenticated,
		"prefer": prefer,
	})
	if path.begins_with("/rest/v1/service_regions"):
		return {
			"ok": true,
			"status": 200,
			"data": [
				{
					"region_key": "us-east",
					"display_name": "US East",
					"lifecycle": "operational",
					"sort_order": 10,
				},
				{
					"region_key": "eu-west",
					"display_name": "EU West",
					"lifecycle": "degraded",
					"sort_order": 20,
				},
				{
					"region_key": "us-west",
					"display_name": "US West",
					"lifecycle": "maintenance",
					"sort_order": 1,
				},
			],
		}
	if path.begins_with("/rest/v1/match_servers"):
		return {"ok": true, "status": 200, "data": _server_rows()}
	return {"ok": false, "status": 404, "data": {"message": "Unexpected regression route."}}


func _server_rows() -> Array[Dictionary]:
	return [
		_server(
			"healthy-native",
			"ws://127.0.0.1:14141",
			1,
			32,
			NOW_UNIX - 2.0
		),
		_server(
			"healthy-secure",
			"wss://east.example.test/socom",
			4,
			32,
			NOW_UNIX - 3.0
		),
		_server(
			"wrong-build",
			"wss://old.example.test/socom",
			0,
			32,
			NOW_UNIX - 1.0,
			"0.0.1"
		),
		_server(
			"wrong-protocol",
			"wss://future.example.test/socom",
			0,
			32,
			NOW_UNIX - 1.0,
			SessionCompatibility.local_build(),
			SessionCompatibility.PROTOCOL_VERSION + 1
		),
		_server("full", "wss://full.example.test/socom", 32, 32, NOW_UNIX - 1.0),
		_server("stale", "wss://stale.example.test/socom", 0, 32, NOW_UNIX - 60.0),
		{
			"id": "off-region",
			"name": "off-region",
			"region": "eu-west",
			"public_address": "wss://europe.example.test/socom",
			"public_port": 443,
			"game_build": SessionCompatibility.local_build(),
			"protocol_version": SessionCompatibility.PROTOCOL_VERSION,
			"capacity": 32,
			"current_players": 1,
			"accepting_players": true,
			"status": "online",
			"last_heartbeat_at": _timestamp(NOW_UNIX - 2.0),
		},
	]


func _server(
	name: String,
	address: String,
	players: int,
	capacity: int,
	heartbeat_unix: float,
	game_build: String = "",
	protocol_version: int = SessionCompatibility.PROTOCOL_VERSION
) -> Dictionary:
	return {
		"id": name,
		"name": name,
		"region": "us-east",
		"public_address": address,
		"public_port": 14141,
		"game_build": SessionCompatibility.local_build() if game_build.is_empty() else game_build,
		"protocol_version": protocol_version,
		"capacity": capacity,
		"current_players": players,
		"accepting_players": true,
		"status": "online",
		"last_heartbeat_at": _timestamp(heartbeat_unix),
			"mode_key": "gunfight_2v2",
		"map_key": "painterly-coastal-village",
		"session_stage": "lobby",
		"free_arenas": 7,
	}


func _timestamp(unix_time: float) -> String:
	return "%s.250+00:00" % Time.get_datetime_string_from_unix_time(int(unix_time))


func _all_directory_requests_use_public_read_access() -> bool:
	if requests.is_empty():
		return false
	for request: Dictionary in requests:
		var path := String(request.get("path", ""))
		if (
			path.begins_with("/rest/v1/service_regions")
			or path.begins_with("/rest/v1/match_servers")
		):
			if (
				int(request.get("method", -1)) != HTTPClient.METHOD_GET
				or bool(request.get("authenticated", true))
			):
				return false
	return true


func _header_starts_with(headers: PackedStringArray, prefix: String) -> bool:
	for header in headers:
		if header.begins_with(prefix):
			return true
	return false


func _expect(condition: bool, message: String) -> void:
	if condition:
		print("MATCHMAKING_DIRECTORY_CHECK PASS " + message)
	else:
		failures.append(message)
