class_name SocomServerBackend
extends Node

## Dedicated-server-only Supabase bridge. The secret key is read from the
## process environment and is never stored in the project, map, logs, or client
## session. Live combat remains in SocomMultiplayerSlice; this bridge handles
## server discovery and final, server-authored records only.

const CONFIG_PATH := "res://config/supabase.json"
const PUBLIC_CONFIG_PATH := "res://config/supabase_public.json"
const SessionCompatibility := preload("res://scripts/network/socom_session_compatibility.gd")
const HEARTBEAT_SECONDS := 15.0
const REQUEST_TIMEOUT_SECONDS := 20.0
const MAX_DIRECTORY_ARENAS := 8
const DIRECTORY_MODE_KEYS := ["demolition", "team_deathmatch", "gunfight_2v2"]
const DIRECTORY_STAGES := [
	"lobby",
	"countdown",
	"active",
	"round_of_16",
	"quarterfinals",
	"semifinals",
	"grand_finals",
	"complete",
]

var project_url := ""
var server_key := ""
var server_id := ""
var match_id := ""
var heartbeat_timer: Timer
var request_adapter: Callable
var directory_snapshot_provider: Callable
var draining := false
var shutdown_in_progress := false
var advertised_capacity := 16
var directory_snapshot := {
	"current_players": 0,
	"mode_key": "demolition",
	"map_key": "unknown",
	"session_stage": "lobby",
	"free_arenas": 1,
}


func _ready() -> void:
	var config := _load_config()
	project_url = String(config.get("project_url", "")).trim_suffix("/")
	server_key = OS.get_environment("SOCOM_SUPABASE_SERVER_KEY").strip_edges()


func _notification(what: int) -> void:
	if what != NOTIFICATION_WM_CLOSE_REQUEST or shutdown_in_progress:
		return
	if get_tree() == null or not is_configured() or server_id.is_empty():
		return
	shutdown_in_progress = true
	get_tree().auto_accept_quit = false
	_mark_offline_before_quit.call_deferred()


func _mark_offline_before_quit() -> void:
	await mark_offline()
	var tree := get_tree()
	if tree != null:
		tree.quit()


func is_configured() -> bool:
	return project_url.begins_with("https://") and not server_key.is_empty()


func set_directory_snapshot_provider(provider: Callable) -> void:
	directory_snapshot_provider = provider
	_refresh_directory_snapshot_from_provider()


func set_directory_snapshot(snapshot: Dictionary) -> Dictionary:
	directory_snapshot = sanitize_directory_snapshot(snapshot, advertised_capacity)
	return directory_snapshot.duplicate(true)


func register_dedicated_server(port: int, advertised_capacity: int = 16) -> Dictionary:
	if not is_configured():
		return {"ok": false, "offline": true, "message": "Cloud registration disabled: server credential is not configured."}
	var public_address := OS.get_environment("SOCOM_SERVER_PUBLIC_ADDRESS").strip_edges()
	var ruleset_id := OS.get_environment("SOCOM_RULESET_ID").strip_edges()
	if public_address.is_empty() or ruleset_id.is_empty():
		return {"ok": false, "offline": true, "message": "Cloud registration needs SOCOM_SERVER_PUBLIC_ADDRESS and SOCOM_RULESET_ID."}
	self.advertised_capacity = sanitize_advertised_capacity(advertised_capacity)
	_refresh_directory_snapshot_from_provider()
	var body := {
		"name": _environment_or("SOCOM_SERVER_NAME", "SOCOM-141 Dedicated"),
		"region": _environment_or("SOCOM_SERVER_REGION", "us-east"),
		"public_address": public_address,
		"public_port": port,
		"game_build": _environment_or("SOCOM_GAME_BUILD", SessionCompatibility.local_build()),
		"protocol_version": SessionCompatibility.PROTOCOL_VERSION,
		"ruleset_id": ruleset_id,
		"capacity": self.advertised_capacity,
		"accepting_players": true,
		"status": "online",
		"last_heartbeat_at": Time.get_datetime_string_from_system(true),
	}
	body.merge(_directory_presence_fields(), true)
	var response := await _request_json(
		"/rest/v1/match_servers?on_conflict=public_address,public_port",
		HTTPClient.METHOD_POST,
		body,
		"resolution=merge-duplicates,return=representation"
	)
	if not bool(response.get("ok", false)):
		return response
	var rows: Array = response.get("data", []) if response.get("data", []) is Array else []
	if rows.is_empty():
		return {"ok": false, "message": "Server registration returned no identity."}
	server_id = String((rows[0] as Dictionary).get("id", ""))
	draining = false
	_start_heartbeat()
	return {"ok": not server_id.is_empty(), "server_id": server_id, "message": "Dedicated server registered."}


static func sanitize_advertised_capacity(advertised_capacity: int) -> int:
	return clampi(advertised_capacity, 2, 32)


static func sanitize_directory_snapshot(snapshot: Dictionary, capacity: int = 16) -> Dictionary:
	var safe_capacity := sanitize_advertised_capacity(capacity)
	var mode_key := _sanitize_directory_key(snapshot.get("mode_key", "demolition"), "demolition", 40)
	if mode_key not in DIRECTORY_MODE_KEYS:
		mode_key = "demolition"
	var stage := _sanitize_directory_key(snapshot.get("session_stage", "lobby"), "lobby", 24)
	if stage not in DIRECTORY_STAGES:
		stage = "lobby"
	return {
		"current_players": clampi(int(snapshot.get("current_players", 0)), 0, safe_capacity),
		"mode_key": mode_key,
		"map_key": _sanitize_directory_key(snapshot.get("map_key", "unknown"), "unknown", 64),
		"session_stage": stage,
		"free_arenas": clampi(int(snapshot.get("free_arenas", 0)), 0, MAX_DIRECTORY_ARENAS),
	}


func complete_ranked_match(result: Dictionary) -> Dictionary:
	if not is_configured() or match_id.is_empty():
		return {"ok": false, "message": "No registered ranked match is active."}
	return await _request_json(
		"/rest/v1/rpc/server_complete_ranked_match",
		HTTPClient.METHOD_POST,
		{"target_match_id": match_id, "result_payload": result}
	)


func record_tournament_event(event: Dictionary) -> Dictionary:
	# The authoritative game server is the only caller. The database endpoint
	# treats event_id as an idempotency key, so a local outbox retry cannot create
	# a second match record, advancement, or later reward transaction.
	if not is_configured():
		return {"ok": false, "offline": true, "message": "Cloud delivery is disabled: server credential is not configured."}
	var event_id := String(event.get("event_id", "")).strip_edges()
	var event_match_id := String(event.get("match_id", "")).strip_edges()
	var event_type := String(event.get("event_type", "")).strip_edges()
	var payload: Variant = event.get("payload", {})
	if event_id.is_empty() or event_match_id.is_empty() or event_type.is_empty() or not payload is Dictionary:
		return {"ok": false, "message": "Tournament event is malformed."}
	return await _request_json(
		"/rest/v1/rpc/server_record_tournament_event",
		HTTPClient.METHOD_POST,
		{
			"target_event_id": event_id,
			"target_match_id": event_match_id,
			"target_arena_id": int(event.get("arena_id", -1)),
			"target_event_type": event_type,
			"target_payload": payload,
		}
	)


func mark_offline() -> void:
	if not is_configured() or server_id.is_empty():
		return
	draining = true
	if heartbeat_timer != null:
		heartbeat_timer.stop()
	await _request_json(
		"/rest/v1/match_servers?id=eq.%s" % server_id.uri_encode(),
		HTTPClient.METHOD_PATCH,
		{"status": "offline", "last_heartbeat_at": Time.get_datetime_string_from_system(true)},
		"return=minimal"
	)


func begin_drain() -> Dictionary:
	if not is_configured() or server_id.is_empty():
		return {"ok": false, "message": "No registered dedicated server is active."}
	draining = true
	return await _request_json(
		"/rest/v1/match_servers?id=eq.%s" % server_id.uri_encode(),
		HTTPClient.METHOD_PATCH,
		{
			"status": "draining",
			"accepting_players": false,
			"last_heartbeat_at": Time.get_datetime_string_from_system(true),
		},
		"return=minimal"
	)


func _start_heartbeat() -> void:
	if heartbeat_timer != null:
		return
	heartbeat_timer = Timer.new()
	heartbeat_timer.wait_time = HEARTBEAT_SECONDS
	heartbeat_timer.autostart = true
	heartbeat_timer.timeout.connect(_send_heartbeat)
	add_child(heartbeat_timer)


func _send_heartbeat() -> void:
	if server_id.is_empty():
		return
	_refresh_directory_snapshot_from_provider()
	var heartbeat_body := {
		"status": "draining" if draining else "online",
		"accepting_players": not draining,
		"last_heartbeat_at": Time.get_datetime_string_from_system(true),
	}
	heartbeat_body.merge(_directory_presence_fields(), true)
	var response := await _request_json(
		"/rest/v1/match_servers?id=eq.%s" % server_id.uri_encode(),
		HTTPClient.METHOD_PATCH,
		heartbeat_body,
		"return=minimal"
	)
	if not bool(response.get("ok", false)):
		push_warning("DEDICATED_SERVER_HEARTBEAT_FAILED status=%d" % int(response.get("status", 0)))


func _refresh_directory_snapshot_from_provider() -> void:
	if not directory_snapshot_provider.is_valid():
		return
	var provided: Variant = directory_snapshot_provider.call()
	if provided is Dictionary:
		set_directory_snapshot(provided)


func _directory_presence_fields() -> Dictionary:
	return directory_snapshot.duplicate(true)


static func _sanitize_directory_key(value: Variant, fallback: String, maximum_length: int) -> String:
	var source := String(value).strip_edges().to_lower()
	var sanitized := ""
	for index in source.length():
		var character := source.substr(index, 1)
		var is_alphanumeric := (
			(character >= "a" and character <= "z")
			or (character >= "0" and character <= "9")
		)
		if is_alphanumeric:
			sanitized += character
		elif character in ["_", "-"] and not sanitized.is_empty():
			sanitized += character
		elif character == " " and not sanitized.is_empty() and not sanitized.ends_with("_"):
			sanitized += "_"
		if sanitized.length() >= maximum_length:
			break
	return fallback if sanitized.is_empty() else sanitized


func _request_json(path: String, method: HTTPClient.Method, body: Variant = null, prefer: String = "") -> Dictionary:
	if request_adapter.is_valid():
		return await request_adapter.call(path, method, body, prefer)
	var request := HTTPRequest.new()
	request.timeout = REQUEST_TIMEOUT_SECONDS
	add_child(request)
	var headers := request_headers(server_key)
	if not prefer.is_empty():
		headers.append("Prefer: %s" % prefer)
	var error := request.request(project_url + path, headers, method, "" if body == null else JSON.stringify(body))
	if error != OK:
		request.queue_free()
		return {"ok": false, "status": 0, "message": error_string(error)}
	var completed: Array = await request.request_completed
	request.queue_free()
	var status := int(completed[1])
	var response_body := (completed[3] as PackedByteArray).get_string_from_utf8()
	var parsed: Variant = JSON.parse_string(response_body) if not response_body.is_empty() else {}
	return {
		"ok": int(completed[0]) == HTTPRequest.RESULT_SUCCESS and status >= 200 and status < 300,
		"status": status,
		"data": parsed if parsed is Dictionary or parsed is Array else {},
		"message": _safe_error_message(parsed, status),
	}


static func request_headers(api_key: String) -> PackedStringArray:
	var headers := PackedStringArray([
		"apikey: %s" % api_key,
		"Content-Type: application/json",
	])
	# Legacy service credentials are JWTs and may be used as bearer tokens. New
	# Supabase secret keys are opaque API keys and must stay in `apikey` only.
	if api_key.begins_with("eyJ") and api_key.count(".") == 2:
		headers.append("Authorization: Bearer %s" % api_key)
	return headers


func _safe_error_message(parsed: Variant, status: int) -> String:
	if parsed is Dictionary:
		return String((parsed as Dictionary).get("message", (parsed as Dictionary).get("hint", "Server backend request failed.")))
	return "Server backend request failed (%d)." % status


func _load_config() -> Dictionary:
	var config_path := (
		CONFIG_PATH
		if FileAccess.file_exists(CONFIG_PATH)
		else PUBLIC_CONFIG_PATH
	)
	if not FileAccess.file_exists(config_path):
		return {}
	var file := FileAccess.open(config_path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	return parsed as Dictionary if parsed is Dictionary else {}


func _environment_or(name: String, fallback: String) -> String:
	var value := OS.get_environment(name).strip_edges()
	return fallback if value.is_empty() else value
