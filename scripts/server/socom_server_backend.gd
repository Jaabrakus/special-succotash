class_name SocomServerBackend
extends Node

## Dedicated-server-only Supabase bridge. The secret key is read from the
## process environment and is never stored in the project, map, logs, or client
## session. Live combat remains in SocomMultiplayerSlice; this bridge handles
## server discovery and final, server-authored records only.

const CONFIG_PATH := "res://config/supabase.json"
const SessionCompatibility := preload("res://scripts/network/socom_session_compatibility.gd")
const HEARTBEAT_SECONDS := 15.0
const REQUEST_TIMEOUT_SECONDS := 20.0

var project_url := ""
var server_key := ""
var server_id := ""
var match_id := ""
var heartbeat_timer: Timer
var request_adapter: Callable
var draining := false


func _ready() -> void:
	var config := _load_config()
	project_url = String(config.get("project_url", "")).trim_suffix("/")
	server_key = OS.get_environment("SOCOM_SUPABASE_SERVER_KEY").strip_edges()


func is_configured() -> bool:
	return project_url.begins_with("https://") and not server_key.is_empty()


func register_dedicated_server(port: int) -> Dictionary:
	if not is_configured():
		return {"ok": false, "offline": true, "message": "Cloud registration disabled: server credential is not configured."}
	var public_address := OS.get_environment("SOCOM_SERVER_PUBLIC_ADDRESS").strip_edges()
	var ruleset_id := OS.get_environment("SOCOM_RULESET_ID").strip_edges()
	if public_address.is_empty() or ruleset_id.is_empty():
		return {"ok": false, "offline": true, "message": "Cloud registration needs SOCOM_SERVER_PUBLIC_ADDRESS and SOCOM_RULESET_ID."}
	var body := {
		"name": _environment_or("SOCOM_SERVER_NAME", "SOCOM-141 Dedicated"),
		"region": _environment_or("SOCOM_SERVER_REGION", "us-east"),
		"public_address": public_address,
		"public_port": port,
		"game_build": _environment_or("SOCOM_GAME_BUILD", SessionCompatibility.local_build()),
		"protocol_version": SessionCompatibility.PROTOCOL_VERSION,
		"ruleset_id": ruleset_id,
		"capacity": 16,
		"current_players": 0,
		"accepting_players": true,
		"status": "online",
		"last_heartbeat_at": Time.get_datetime_string_from_system(true),
	}
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


func complete_ranked_match(result: Dictionary) -> Dictionary:
	if not is_configured() or match_id.is_empty():
		return {"ok": false, "message": "No registered ranked match is active."}
	return await _request_json(
		"/rest/v1/rpc/server_complete_ranked_match",
		HTTPClient.METHOD_POST,
		{"target_match_id": match_id, "result_payload": result}
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
	var response := await _request_json(
		"/rest/v1/match_servers?id=eq.%s" % server_id.uri_encode(),
		HTTPClient.METHOD_PATCH,
		{
			"status": "draining" if draining else "online",
			"accepting_players": not draining,
			"last_heartbeat_at": Time.get_datetime_string_from_system(true),
		},
		"return=minimal"
	)
	if not bool(response.get("ok", false)):
		push_warning("DEDICATED_SERVER_HEARTBEAT_FAILED status=%d" % int(response.get("status", 0)))


func _request_json(path: String, method: HTTPClient.Method, body: Variant = null, prefer: String = "") -> Dictionary:
	if request_adapter.is_valid():
		return await request_adapter.call(path, method, body, prefer)
	var request := HTTPRequest.new()
	request.timeout = REQUEST_TIMEOUT_SECONDS
	add_child(request)
	var headers := PackedStringArray([
		"apikey: %s" % server_key,
		"Authorization: Bearer %s" % server_key,
		"Content-Type: application/json",
	])
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


func _safe_error_message(parsed: Variant, status: int) -> String:
	if parsed is Dictionary:
		return String((parsed as Dictionary).get("message", (parsed as Dictionary).get("hint", "Server backend request failed.")))
	return "Server backend request failed (%d)." % status


func _load_config() -> Dictionary:
	if not FileAccess.file_exists(CONFIG_PATH):
		return {}
	var file := FileAccess.open(CONFIG_PATH, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	return parsed as Dictionary if parsed is Dictionary else {}


func _environment_or(name: String, fallback: String) -> String:
	var value := OS.get_environment(name).strip_edges()
	return fallback if value.is_empty() else value
