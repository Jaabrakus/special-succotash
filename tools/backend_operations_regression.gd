extends SceneTree

const ServiceDirectory := preload("res://scripts/network/socom_service_directory.gd")
const ServerBackend := preload("res://scripts/server/socom_server_backend.gd")
const SessionCompatibility := preload("res://scripts/network/socom_session_compatibility.gd")
const OPERATIONS_MIGRATION := "res://supabase/migrations/20260824002000_create_multiplayer_operations.sql"
const SERVER_BACKEND_PATH := "res://scripts/server/socom_server_backend.gd"

var failures: Array[String] = []
var requests: Array[Dictionary] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var regions: Array = [
		{"region_key": "us-west", "lifecycle": "offline", "measured_latency_ms": 15.0, "sort_order": 1},
		{"region_key": "us-east", "lifecycle": "operational", "measured_latency_ms": 42.0, "sort_order": 2},
		{"region_key": "eu-west", "lifecycle": "degraded", "measured_latency_ms": 90.0, "sort_order": 3},
	]
	var automatic := ServiceDirectory.choose_region(regions)
	_expect(
		bool(automatic.get("ok", false))
		and String((automatic.get("region", {}) as Dictionary).get("region_key", "")) == "us-east",
		"automatic region selection excludes offline service and chooses lowest measured latency"
	)
	var preferred := ServiceDirectory.choose_region(regions, "eu-west")
	_expect(
		bool(preferred.get("ok", false))
		and String((preferred.get("region", {}) as Dictionary).get("region_key", "")) == "eu-west",
		"explicit healthy region preference is preserved"
	)
	var now_unix := 2_000_000.0
	var servers: Array = [
		_server_fixture("full", 16, 16, now_unix - 2.0),
		_server_fixture("stale", 2, 16, now_unix - 60.0),
		_server_fixture("wrong-build", 1, 16, now_unix - 2.0, "0.0.1"),
		_server_fixture("healthy", 4, 16, now_unix - 2.0),
	]
	var selected := ServiceDirectory.choose_server(
		servers,
		"us-east",
		SessionCompatibility.local_build(),
		SessionCompatibility.PROTOCOL_VERSION,
		now_unix
	)
	_expect(
		bool(selected.get("ok", false))
		and String((selected.get("server", {}) as Dictionary).get("name", "")) == "healthy",
		"server discovery rejects stale, full, and incompatible hosts"
	)

	var migration := FileAccess.get_file_as_string(OPERATIONS_MIGRATION)
	for required_table in [
		"service_regions", "player_blocks", "player_mutes", "moderation_reports",
		"moderation_evidence", "moderation_actions", "moderation_appeals", "security_audit_log",
		"private.api_rate_limits",
	]:
		_expect(required_table in migration, "operations schema includes " + required_table)
	_expect("consume_api_rate_limit" in migration and "security definer" in migration, "backend rate limiting is atomic and server-defined")
	_expect("enable row level security" in migration, "operations tables enable row-level security")
	_expect("players discover compatible healthy match servers" in migration, "discovery exposes only fresh compatible capacity")
	_expect(
		not _authenticated_grant_contains(migration, "moderation_evidence")
		and not _authenticated_grant_contains(migration, "security_audit_log"),
		"clients cannot read evidence or the security audit log"
	)

	var server_source := FileAccess.get_file_as_string(SERVER_BACKEND_PATH)
	_expect("SOCOM_SUPABASE_SERVER_KEY" in server_source, "privileged server credential comes from process environment")
	_expect("service_role" not in server_source and "sb_secret_" not in server_source, "server source contains no embedded privileged credential")

	OS.set_environment("SOCOM_SUPABASE_SERVER_KEY", "regression-server-secret")
	OS.set_environment("SOCOM_SERVER_PUBLIC_ADDRESS", "203.0.113.141")
	OS.set_environment("SOCOM_RULESET_ID", "11111111-1111-1111-1111-111111111111")
	OS.set_environment("SOCOM_GAME_BUILD", "")
	var backend := ServerBackend.new()
	backend.request_adapter = Callable(self, "_fake_server_request")
	root.add_child(backend)
	backend.project_url = "https://example.supabase.co"
	backend.server_key = "regression-server-secret"
	var registration: Dictionary = await backend.register_dedicated_server(14141)
	_expect(bool(registration.get("ok", false)), "dedicated server registers through the privileged backend boundary")
	var registration_body: Dictionary = requests[0].get("body", {}) if not requests.is_empty() else {}
	_expect(
		String(registration_body.get("game_build", "")) == SessionCompatibility.local_build()
		and int(registration_body.get("protocol_version", 0)) == SessionCompatibility.PROTOCOL_VERSION,
		"server discovery publishes the same build and protocol required by admission"
	)
	var drain: Dictionary = await backend.begin_drain()
	_expect(bool(drain.get("ok", false)) and _saw_draining_request(), "graceful drain removes the server from new-player selection")
	requests.clear()
	await backend.call("_send_heartbeat")
	_expect(_saw_draining_request(), "later heartbeats cannot reopen a draining server")
	backend.free()
	for key in ["SOCOM_SUPABASE_SERVER_KEY", "SOCOM_SERVER_PUBLIC_ADDRESS", "SOCOM_RULESET_ID", "SOCOM_GAME_BUILD"]:
		OS.set_environment(key, "")

	if failures.is_empty():
		print("BACKEND_OPERATIONS_REGRESSION PASS")
		quit(0)
		return
	for failure in failures:
		push_error("BACKEND_OPERATIONS_REGRESSION FAIL: " + failure)
	quit(1)


func _server_fixture(name: String, players: int, capacity: int, heartbeat: float, build: String = "") -> Dictionary:
	return {
		"name": name,
		"region": "us-east",
		"status": "online",
		"accepting_players": true,
		"current_players": players,
		"capacity": capacity,
		"game_build": SessionCompatibility.local_build() if build.is_empty() else build,
		"protocol_version": SessionCompatibility.PROTOCOL_VERSION,
		"last_heartbeat_unix": heartbeat,
	}


func _fake_server_request(path: String, method: HTTPClient.Method, body: Variant, prefer: String) -> Dictionary:
	requests.append({"path": path, "method": method, "body": body, "prefer": prefer})
	if method == HTTPClient.METHOD_POST:
		return {"ok": true, "status": 201, "data": [{"id": "server-regression"}]}
	return {"ok": true, "status": 204, "data": {}}


func _saw_draining_request() -> bool:
	for request: Dictionary in requests:
		var body: Dictionary = request.get("body", {}) if request.get("body", {}) is Dictionary else {}
		if String(body.get("status", "")) == "draining" and not bool(body.get("accepting_players", true)):
			return true
	return false


func _authenticated_grant_contains(source: String, table_name: String) -> bool:
	for statement in source.split(";"):
		if "grant " in statement.to_lower() and "authenticated" in statement.to_lower() and table_name in statement:
			return true
	return false


func _expect(condition: bool, message: String) -> void:
	if condition:
		print("BACKEND_OPERATIONS_CHECK PASS " + message)
	else:
		failures.append(message)
