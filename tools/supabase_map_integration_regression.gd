extends SceneTree

const SupabaseClientScript := preload("res://scripts/network/socom_supabase_client.gd")
const MapDocument := preload("res://scripts/maps/socom_map_document.gd")

var failures: Array[String] = []
var requests: Array[Dictionary] = []
var fixture_document: Dictionary


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var client := SupabaseClientScript.new()
	client.session_path = "/private/tmp/socom_supabase_session_regression.json"
	client.cloud_links_path = "/private/tmp/socom_supabase_links_regression.json"
	client.request_adapter = Callable(self, "_fake_request")
	root.add_child(client)
	client.project_url = "https://example.supabase.co"
	client.publishable_key = "sb_publishable_regression"
	client.session = {
		"access_token": "test-access-token",
		"refresh_token": "test-refresh-token",
		"expires_at": int(Time.get_unix_time_from_system()) + 3600,
		"user_id": "11111111-1111-1111-1111-111111111111",
		"display_name": "Viper_111111",
	}
	fixture_document = MapDocument.new_document("Community Regression")
	var identity: Dictionary = await client.ensure_guest_session()
	_expect(bool(identity.get("ok", false)) and String(identity.get("display_name", "")) == "Viper_111111", "existing guest session starts without a login form")
	var published: Dictionary = await client.publish_map(fixture_document)
	_expect(bool(published.get("ok", false)) and int(published.get("version", 0)) == 1, "local map JSON publishes as a versioned community map")
	_expect(_saw_request("/rest/v1/community_map_versions", HTTPClient.METHOD_POST), "publishing writes an immutable map version")
	_expect(_saw_request("/rest/v1/community_maps?id=eq.", HTTPClient.METHOD_PATCH), "publishing advances the community map pointer")
	var listed: Dictionary = await client.list_public_maps()
	_expect(bool(listed.get("ok", false)) and (listed.get("maps", []) as Array).size() == 1, "published community maps are browsable without player credentials")
	var downloaded: Dictionary = await client.download_map((listed.get("maps", []) as Array)[0])
	var downloaded_document: Dictionary = downloaded.get("document", {})
	_expect(bool(downloaded.get("ok", false)) and String(downloaded_document.get("name", "")) == "Community Regression", "community map downloads into a valid local map document")
	var custom_asset_map := fixture_document.duplicate(true)
	(custom_asset_map.get("objects", []) as Array).append({
		"id": "local_glb", "type": "imported_asset", "name": "Local GLB",
		"position": {"x": 0, "y": 0, "z": 0}, "rotation_degrees": {"x": 0, "y": 0, "z": 0},
		"size": {"x": 1, "y": 1, "z": 1}, "color": {"r": 1, "g": 1, "b": 1, "a": 1},
		"properties": {"asset_path": "user://map_assets/private.glb"},
	})
	var blocked: Dictionary = await client.publish_map(custom_asset_map)
	_expect(not bool(blocked.get("ok", true)) and "GLB" in String(blocked.get("message", "")), "publishing blocks maps with unuploaded local GLB dependencies")
	client.free()
	for path in ["/private/tmp/socom_supabase_session_regression.json", "/private/tmp/socom_supabase_links_regression.json"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	if failures.is_empty():
		print("SUPABASE_MAP_INTEGRATION_REGRESSION PASS")
		quit(0)
	else:
		for failure in failures:
			push_error("SUPABASE_MAP_INTEGRATION_REGRESSION FAIL: %s" % failure)
		quit(1)


func _fake_request(path: String, method: HTTPClient.Method, body: Variant, authenticated: bool, _prefer: String) -> Dictionary:
	requests.append({"path": path, "method": method, "body": body, "authenticated": authenticated})
	if path.begins_with("/rest/v1/community_maps?owner_id="):
		return {"ok": true, "status": 200, "data": []}
	if path == "/rest/v1/community_maps" and method == HTTPClient.METHOD_POST:
		return {"ok": true, "status": 201, "data": [{
			"id": "22222222-2222-2222-2222-222222222222",
			"owner_id": "11111111-1111-1111-1111-111111111111",
			"slug": String((body as Dictionary).get("slug", "")),
			"title": "Community Regression",
			"current_version": 0,
		}]}
	if path == "/rest/v1/community_map_versions" and method == HTTPClient.METHOD_POST:
		return {"ok": true, "status": 201, "data": [body]}
	if path.begins_with("/rest/v1/community_maps?id=eq.") and method == HTTPClient.METHOD_PATCH:
		return {"ok": true, "status": 200, "data": [body]}
	if path.begins_with("/rest/v1/community_maps?select="):
		return {"ok": true, "status": 200, "data": [{
			"id": "22222222-2222-2222-2222-222222222222",
			"owner_id": "11111111-1111-1111-1111-111111111111",
			"slug": String(fixture_document.get("map_id", "")),
			"title": "Community Regression",
			"description": "Regression map",
			"visibility": "public",
			"lifecycle": "published",
			"current_version": 1,
		}]}
	if path.begins_with("/rest/v1/community_map_versions?map_id=eq."):
		return {"ok": true, "status": 200, "data": [{
			"map_document": fixture_document,
			"version_number": 1,
			"document_sha256": "0".repeat(64),
		}]}
	return {"ok": false, "status": 404, "data": {"message": "Unexpected fake request: %s" % path}}


func _saw_request(path_prefix: String, method: HTTPClient.Method) -> bool:
	for entry: Dictionary in requests:
		if String(entry.get("path", "")).begins_with(path_prefix) and int(entry.get("method", -1)) == int(method):
			return true
	return false


func _expect(condition: bool, message: String) -> void:
	if condition:
		print("SUPABASE_MAP_CHECK PASS %s" % message)
	else:
		failures.append(message)
