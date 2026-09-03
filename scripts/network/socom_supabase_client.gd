class_name SocomSupabaseClient
extends Node

## Browser-safe Supabase bridge for guest identity and community map JSON.
## Local Map Lab saving remains authoritative for editing and playtesting.

const MapDocument := preload("res://scripts/maps/socom_map_document.gd")
const MapAssetLibrary := preload("res://scripts/maps/socom_map_asset_library.gd")
const CONFIG_PATH := "res://config/supabase.json"
const PUBLIC_CONFIG_PATH := "res://config/supabase_public.json"
const SESSION_PATH := "user://supabase_guest_session.json"
const CLOUD_LINKS_PATH := "user://community_map_links.json"
const REQUEST_TIMEOUT_SECONDS := 20.0
const CALLSIGN_PREFIXES := [
	"Viper", "Ghost", "Raven", "Nomad", "Kodiak", "Reaper", "Falcon", "Specter",
]

var project_url := ""
var publishable_key := ""
var storage_bucket := "community-map-assets"
var session: Dictionary = {}
var request_adapter: Callable
var binary_request_adapter: Callable
var session_path := SESSION_PATH
var cloud_links_path := CLOUD_LINKS_PATH


func _ready() -> void:
	_load_config()
	session = _load_json_file(session_path)


func is_configured() -> bool:
	return project_url.begins_with("https://") and publishable_key.begins_with("sb_publishable_")


func display_name() -> String:
	return String(session.get("display_name", "Guest"))


func user_id() -> String:
	return String(session.get("user_id", ""))


func has_guest_session() -> bool:
	return not user_id().is_empty() and not String(session.get("access_token", "")).is_empty()


func ensure_guest_session() -> Dictionary:
	if not is_configured():
		return {"ok": false, "message": "Community service is not configured."}
	if _session_is_fresh():
		return _identity_result()
	if not String(session.get("refresh_token", "")).is_empty():
		var refreshed := await _refresh_session()
		if bool(refreshed.get("ok", false)):
			return _identity_result()
		_clear_session()
	var provisional_name := _random_callsign()
	var response := await _request_json(
		"/auth/v1/signup",
		HTTPClient.METHOD_POST,
		{"data": {"display_name": provisional_name}},
		false
	)
	if not bool(response.get("ok", false)):
		var detail := _response_message(response)
		if "anonymous" in detail.to_lower():
			detail = "Enable Anonymous Sign-Ins in Supabase Authentication settings."
		return {"ok": false, "message": detail}
	var payload: Dictionary = response.get("data", {})
	if not _accept_auth_payload(payload, provisional_name):
		return {"ok": false, "message": "Supabase did not return a guest session."}
	await _apply_unique_callsign()
	_save_json_file(session_path, session)
	return _identity_result()


func get_player_profile() -> Dictionary:
	if not is_configured():
		return {"ok": false, "message": "Supabase service is not configured."}
	var u_id := user_id()
	if u_id.is_empty():
		return {"ok": false, "message": "No active user session."}
	var path := "/rest/v1/player_profiles?user_id=eq.%s&select=*" % u_id
	var response: Dictionary = await _request_json(path, HTTPClient.METHOD_GET, {}, true)
	if not bool(response.get("ok", false)):
		return {"ok": false, "message": _response_message(response)}
	var rows: Array = response.get("data", [])
	if rows.is_empty():
		return {"ok": true, "profile": {"elo_rating": 0, "rank_tier": "TIRO III", "tier_kills": 0, "tier_deaths": 0}}
	return {"ok": true, "profile": rows[0]}


func get_gunfight_leaderboard(limit: int = 50) -> Dictionary:
	if not is_configured():
		return {"ok": false, "message": "Supabase service is not configured.", "leaderboard": []}
	var path := "/rest/v1/gunfight_leaderboard?select=*&limit=%d" % limit
	var response: Dictionary = await _request_json(path, HTTPClient.METHOD_GET, {}, true)
	if not bool(response.get("ok", false)):
		return {"ok": false, "message": _response_message(response), "leaderboard": []}
	return {"ok": true, "leaderboard": response.get("data", [])}


func list_public_maps() -> Dictionary:
	if not is_configured():
		return {"ok": false, "message": "Community service is not configured.", "maps": []}
	var path := (
		"/rest/v1/community_maps"
		+ "?select=id,owner_id,slug,title,description,visibility,lifecycle,current_version,updated_at"
		+ "&lifecycle=eq.published&visibility=eq.public&order=updated_at.desc&limit=50"
	)
	var response := await _request_json(path, HTTPClient.METHOD_GET, null, false)
	if not bool(response.get("ok", false)):
		return {"ok": false, "message": _response_message(response), "maps": []}
	var rows: Array = response.get("data", []) if response.get("data", []) is Array else []
	return {"ok": true, "message": "%d community maps found." % rows.size(), "maps": rows}


func publish_map(map_document: Dictionary) -> Dictionary:
	var normalized := MapDocument.normalize(map_document)
	if normalized.is_empty():
		return {"ok": false, "message": "The map document is invalid."}
	var identity := await ensure_guest_session()
	if not bool(identity.get("ok", false)):
		return identity
	var links := _load_json_file(cloud_links_path)
	var local_map_id := String(normalized.get("map_id", ""))
	var link: Dictionary = links.get(local_map_id, {}) if links.get(local_map_id, {}) is Dictionary else {}
	var cloud_map_id := String(link.get("cloud_map_id", ""))
	var cloud_row: Dictionary = {}
	if cloud_map_id.is_empty():
		var existing := await _find_owned_map(local_map_id)
		if bool(existing.get("ok", false)):
			cloud_row = existing.get("map", {})
	if cloud_row.is_empty() and not cloud_map_id.is_empty():
		var existing_by_id := await _get_owned_map(cloud_map_id)
		if bool(existing_by_id.get("ok", false)):
			cloud_row = existing_by_id.get("map", {})
	if cloud_row.is_empty():
		var created := await _request_json(
			"/rest/v1/community_maps",
			HTTPClient.METHOD_POST,
			{
				"owner_id": user_id(),
				"slug": local_map_id,
				"title": String(normalized.get("name", "Untitled Tactical Map")).left(80),
				"description": "Created with the SOCOM-141 Map Lab",
				"visibility": "public",
				"lifecycle": "draft",
			},
			true,
			"return=representation"
		)
		if not bool(created.get("ok", false)):
			return {"ok": false, "message": _response_message(created)}
		var created_rows: Array = created.get("data", []) if created.get("data", []) is Array else []
		if created_rows.is_empty():
			return {"ok": false, "message": "Community map record was not returned."}
		cloud_row = created_rows[0]
	cloud_map_id = String(cloud_row.get("id", ""))
	if cloud_map_id.is_empty():
		return {"ok": false, "message": "Community map identity is missing."}
	var asset_result := await _upload_map_assets(normalized, cloud_map_id)
	if not bool(asset_result.get("ok", false)):
		return asset_result
	var cloud_document: Dictionary = asset_result.get("document", normalized)
	var asset_manifest: Array = asset_result.get("manifest", [])
	var next_version := int(cloud_row.get("current_version", 0)) + 1
	var compact_json := JSON.stringify(cloud_document)
	var version_response := await _request_json(
		"/rest/v1/community_map_versions",
		HTTPClient.METHOD_POST,
		{
			"map_id": cloud_map_id,
			"version_number": next_version,
			"created_by": user_id(),
			"map_document": cloud_document,
			"asset_manifest": asset_manifest,
			"document_sha256": _sha256_text(compact_json),
			"is_published": true,
		},
		true,
		"return=representation"
	)
	if not bool(version_response.get("ok", false)):
		return {"ok": false, "message": _response_message(version_response)}
	var update_response := await _request_json(
		"/rest/v1/community_maps?id=eq.%s" % cloud_map_id.uri_encode(),
		HTTPClient.METHOD_PATCH,
		{
			"title": String(normalized.get("name", "Untitled Tactical Map")).left(80),
			"current_version": next_version,
			"visibility": "public",
			"lifecycle": "published",
		},
		true,
		"return=representation"
	)
	if not bool(update_response.get("ok", false)):
		return {"ok": false, "message": _response_message(update_response)}
	links[local_map_id] = {"cloud_map_id": cloud_map_id, "version": next_version}
	_save_json_file(cloud_links_path, links)
	return {
		"ok": true,
		"message": "Published %s version %d as %s." % [normalized.get("name", "map"), next_version, display_name()],
		"cloud_map_id": cloud_map_id,
		"version": next_version,
	}


func download_map(cloud_map: Dictionary) -> Dictionary:
	var cloud_map_id := String(cloud_map.get("id", ""))
	var version := int(cloud_map.get("current_version", 0))
	if cloud_map_id.is_empty() or version <= 0:
		return {"ok": false, "message": "That community map has no published version."}
	var path := (
		"/rest/v1/community_map_versions?map_id=eq.%s&version_number=eq.%d"
		+ "&is_published=eq.true&select=map_document,asset_manifest,version_number,document_sha256&limit=1"
	) % [cloud_map_id.uri_encode(), version]
	var response := await _request_json(path, HTTPClient.METHOD_GET, null, false)
	if not bool(response.get("ok", false)):
		return {"ok": false, "message": _response_message(response)}
	var rows: Array = response.get("data", []) if response.get("data", []) is Array else []
	if rows.is_empty():
		return {"ok": false, "message": "Published map version was not found."}
	var row: Dictionary = rows[0]
	var downloaded: Dictionary = row.get("map_document", {}) if row.get("map_document", {}) is Dictionary else {}
	var asset_result := await _download_map_assets(downloaded, row.get("asset_manifest", []))
	if not bool(asset_result.get("ok", false)):
		return asset_result
	downloaded = asset_result.get("document", downloaded)
	downloaded["map_id"] = "community_%s" % cloud_map_id.replace("-", "").left(24)
	downloaded["name"] = String(cloud_map.get("title", downloaded.get("name", "Community Map")))
	downloaded = MapDocument.normalize(downloaded)
	if downloaded.is_empty():
		return {"ok": false, "message": "Downloaded map data is invalid."}
	var links := _load_json_file(cloud_links_path)
	links[String(downloaded.get("map_id", ""))] = {"cloud_map_id": cloud_map_id, "version": version}
	_save_json_file(cloud_links_path, links)
	return {"ok": true, "message": "Downloaded %s." % downloaded.get("name", "community map"), "document": downloaded}


func _request_binary(
	path: String,
	method: HTTPClient.Method,
	body: PackedByteArray = PackedByteArray(),
	authenticated: bool = false,
	extra_headers: PackedStringArray = PackedStringArray()
) -> Dictionary:
	if binary_request_adapter.is_valid():
		return await binary_request_adapter.call(path, method, body, authenticated, extra_headers)
	var request := HTTPRequest.new()
	request.timeout = REQUEST_TIMEOUT_SECONDS
	add_child(request)
	var access_token := String(session.get("access_token", "")) if authenticated else ""
	var headers := request_headers(publishable_key, access_token)
	for header in extra_headers:
		headers.append(header)
	var start_error := request.request_raw(project_url + path, headers, method, body)
	if start_error != OK:
		request.queue_free()
		return {"ok": false, "status": 0, "message": error_string(start_error)}
	var completed: Array = await request.request_completed
	request.queue_free()
	var transport_result := int(completed[0])
	var status := int(completed[1])
	var response_bytes := completed[3] as PackedByteArray
	var response_text := response_bytes.get_string_from_utf8()
	var parsed: Variant = JSON.parse_string(response_text) if not response_text.is_empty() else {}
	return {
		"ok": transport_result == HTTPRequest.RESULT_SUCCESS and status >= 200 and status < 300,
		"status": status,
		"data": parsed if parsed is Dictionary or parsed is Array else {},
		"bytes": response_bytes,
		"raw": response_text.left(1000),
	}


func _sha256_bytes(value: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(value)
	return context.finish().hex_encode()


func _upload_map_assets(map_document: Dictionary, cloud_map_id: String) -> Dictionary:
	var cloud_document := map_document.duplicate(true)
	var manifest: Array = []
	var replacements: Dictionary = {}
	for local_path in _local_asset_paths(cloud_document):
		var asset := _read_local_glb(local_path)
		if not bool(asset.get("ok", false)):
			return asset
		var sha256 := String(asset.get("sha256", ""))
		var storage_path := "%s/%s/%s.glb" % [user_id(), cloud_map_id, sha256]
		var upload := await _request_binary(
			"/storage/v1/object/%s/%s" % [storage_bucket.uri_encode(), storage_path],
			HTTPClient.METHOD_POST,
			asset.get("bytes", PackedByteArray()),
			true,
			PackedStringArray(["Content-Type: model/gltf-binary", "x-upsert: true"])
		)
		if not bool(upload.get("ok", false)):
			return {"ok": false, "message": "Could not upload %s: %s" % [local_path.get_file(), _response_message(upload)]}
		var metadata := {
			"map_id": cloud_map_id,
			"owner_id": user_id(),
			"storage_path": storage_path,
			"original_filename": local_path.get_file(),
			"sha256": sha256,
			"byte_size": int(asset.get("byte_size", 0)),
			"mime_type": "model/gltf-binary",
		}
		var register := await _request_json(
			"/rest/v1/community_map_assets?on_conflict=map_id,sha256",
			HTTPClient.METHOD_POST,
			metadata,
			true,
			"resolution=merge-duplicates,return=minimal"
		)
		if not bool(register.get("ok", false)):
			return {"ok": false, "message": "Uploaded %s but could not register it: %s" % [local_path.get_file(), _response_message(register)]}
		manifest.append(metadata)
		replacements[local_path] = _cloud_asset_uri(storage_path)
	_rewrite_asset_paths(cloud_document, replacements)
	return {"ok": true, "document": cloud_document, "manifest": manifest}


func _download_map_assets(map_document: Dictionary, raw_manifest: Variant) -> Dictionary:
	var local_document := map_document.duplicate(true)
	var manifest: Array = raw_manifest if raw_manifest is Array else []
	var replacements: Dictionary = {}
	for raw_entry in manifest:
		if not raw_entry is Dictionary:
			return {"ok": false, "message": "Community asset manifest is malformed."}
		var entry := raw_entry as Dictionary
		var storage_path := String(entry.get("storage_path", ""))
		var expected_sha := String(entry.get("sha256", ""))
		var expected_size := int(entry.get("byte_size", 0))
		if storage_path.is_empty() or expected_sha.length() != 64:
			return {"ok": false, "message": "Community asset manifest is incomplete."}
		var local_path := "%s/community_%s.glb" % [MapAssetLibrary.USER_ASSET_DIRECTORY, expected_sha]
		if not _local_asset_matches(local_path, expected_sha, expected_size):
			var download := await _request_binary(
				"/storage/v1/object/authenticated/%s/%s" % [storage_bucket.uri_encode(), storage_path],
				HTTPClient.METHOD_GET,
				PackedByteArray(),
				has_guest_session()
			)
			if not bool(download.get("ok", false)):
				return {"ok": false, "message": "Could not download %s: %s" % [String(entry.get("original_filename", "map asset")), _response_message(download)]}
			var bytes: PackedByteArray = download.get("bytes", PackedByteArray())
			if bytes.size() != expected_size or _sha256_bytes(bytes) != expected_sha:
				return {"ok": false, "message": "Community asset failed its integrity check."}
			DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(MapAssetLibrary.USER_ASSET_DIRECTORY))
			var output := FileAccess.open(local_path, FileAccess.WRITE)
			if output == null:
				return {"ok": false, "message": "Could not save the downloaded map asset locally."}
			output.store_buffer(bytes)
			output.close()
		replacements[_cloud_asset_uri(storage_path)] = local_path
	_rewrite_asset_paths(local_document, replacements)
	return {"ok": true, "document": local_document}


func _read_local_glb(path: String) -> Dictionary:
	if not MapAssetLibrary.is_allowed_asset_path(path) or not path.begins_with("user://") or not FileAccess.file_exists(path):
		return {"ok": false, "message": "Map asset is missing or outside the safe GLB library: %s" % path}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "message": "Could not open map asset: %s" % path.get_file()}
	var byte_size := file.get_length()
	if byte_size <= 0 or byte_size > MapAssetLibrary.MAX_ASSET_BYTES:
		file.close()
		return {"ok": false, "message": "GLB must be between 1 byte and 128 MB."}
	var bytes := file.get_buffer(byte_size)
	file.close()
	return {"ok": true, "bytes": bytes, "byte_size": byte_size, "sha256": _sha256_bytes(bytes)}


func _rewrite_asset_paths(document: Dictionary, replacements: Dictionary) -> void:
	for object: Dictionary in document.get("objects", []):
		if String(object.get("type", "")) != "imported_asset":
			continue
		var properties: Dictionary = object.get("properties", {})
		var path := String(properties.get("asset_path", ""))
		if replacements.has(path):
			properties["asset_path"] = replacements[path]
			object["properties"] = properties


func _cloud_asset_uri(storage_path: String) -> String:
	return "supabase://%s/%s" % [storage_bucket, storage_path]


func _local_asset_matches(path: String, expected_sha: String, expected_size: int) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() != expected_size:
		if file != null:
			file.close()
		return false
	var bytes := file.get_buffer(file.get_length())
	file.close()
	return _sha256_bytes(bytes) == expected_sha


func _find_owned_map(slug: String) -> Dictionary:
	var path := (
		"/rest/v1/community_maps?owner_id=eq.%s&slug=eq.%s"
		+ "&select=id,owner_id,slug,title,current_version&limit=1"
	) % [user_id().uri_encode(), slug.uri_encode()]
	var response := await _request_json(path, HTTPClient.METHOD_GET, null, true)
	if not bool(response.get("ok", false)):
		return {"ok": false}
	var rows: Array = response.get("data", []) if response.get("data", []) is Array else []
	return {"ok": not rows.is_empty(), "map": rows[0] if not rows.is_empty() else {}}


func _get_owned_map(cloud_map_id: String) -> Dictionary:
	var path := "/rest/v1/community_maps?id=eq.%s&owner_id=eq.%s&select=id,owner_id,slug,title,current_version&limit=1" % [
		cloud_map_id.uri_encode(), user_id().uri_encode(),
	]
	var response := await _request_json(path, HTTPClient.METHOD_GET, null, true)
	if not bool(response.get("ok", false)):
		return {"ok": false}
	var rows: Array = response.get("data", []) if response.get("data", []) is Array else []
	return {"ok": not rows.is_empty(), "map": rows[0] if not rows.is_empty() else {}}


func _refresh_session() -> Dictionary:
	var response := await _request_json(
		"/auth/v1/token?grant_type=refresh_token",
		HTTPClient.METHOD_POST,
		{"refresh_token": String(session.get("refresh_token", ""))},
		false
	)
	if not bool(response.get("ok", false)):
		return response
	var old_name := display_name()
	if not _accept_auth_payload(response.get("data", {}), old_name):
		return {"ok": false, "message": "Guest session refresh was incomplete."}
	_save_json_file(session_path, session)
	return {"ok": true}


func _accept_auth_payload(payload: Dictionary, fallback_name: String) -> bool:
	var auth: Dictionary = payload.get("session", payload) if payload.get("session", payload) is Dictionary else {}
	var user: Dictionary = payload.get("user", auth.get("user", {})) if payload.get("user", auth.get("user", {})) is Dictionary else {}
	var access_token := String(auth.get("access_token", ""))
	var refresh_token := String(auth.get("refresh_token", ""))
	var auth_user_id := String(user.get("id", session.get("user_id", "")))
	if access_token.is_empty() or refresh_token.is_empty() or auth_user_id.is_empty():
		return false
	var expires_at := int(auth.get("expires_at", 0))
	if expires_at <= 0:
		expires_at = int(Time.get_unix_time_from_system()) + int(auth.get("expires_in", 3600))
	session = {
		"access_token": access_token,
		"refresh_token": refresh_token,
		"expires_at": expires_at,
		"user_id": auth_user_id,
		"display_name": fallback_name if not fallback_name.is_empty() else "Guest",
	}
	return true


func _apply_unique_callsign() -> void:
	var suffix := user_id().replace("-", "").right(6)
	var base_name := display_name().split("_")[0]
	var unique_name := "%s_%s" % [base_name, suffix]
	var response := await _request_json(
		"/rest/v1/player_profiles?user_id=eq.%s" % user_id().uri_encode(),
		HTTPClient.METHOD_PATCH,
		{"handle": unique_name, "display_name": unique_name},
		true,
		"return=minimal"
	)
	# Profile setup is optional for immediate play. Keep the guest session even
	# when the server schema has not been migrated yet.
	if bool(response.get("ok", false)):
		session["display_name"] = unique_name


func _request_json(
	path: String,
	method: HTTPClient.Method,
	body: Variant = null,
	authenticated: bool = false,
	prefer: String = ""
) -> Dictionary:
	if request_adapter.is_valid():
		return await request_adapter.call(path, method, body, authenticated, prefer)
	var request := HTTPRequest.new()
	request.timeout = REQUEST_TIMEOUT_SECONDS
	add_child(request)
	var access_token := String(session.get("access_token", "")) if authenticated else ""
	var headers := request_headers(publishable_key, access_token, "application/json")
	if not prefer.is_empty():
		headers.append("Prefer: %s" % prefer)
	var request_body := "" if body == null else JSON.stringify(body)
	var start_error := request.request(project_url + path, headers, method, request_body)
	if start_error != OK:
		request.queue_free()
		return {"ok": false, "status": 0, "message": error_string(start_error)}
	var completed: Array = await request.request_completed
	request.queue_free()
	var transport_result := int(completed[0])
	var status := int(completed[1])
	var response_body := (completed[3] as PackedByteArray).get_string_from_utf8()
	var parsed: Variant = JSON.parse_string(response_body) if not response_body.is_empty() else {}
	var data: Variant = parsed if parsed is Dictionary or parsed is Array else {}
	return {
		"ok": transport_result == HTTPRequest.RESULT_SUCCESS and status >= 200 and status < 300,
		"status": status,
		"data": data,
		"raw": response_body.left(1000),
	}


static func request_headers(
	api_key: String,
	access_token: String = "",
	content_type: String = ""
) -> PackedStringArray:
	var headers := PackedStringArray(["apikey: %s" % api_key])
	var bearer := access_token.strip_edges()
	# New sb_publishable_ keys are opaque gateway keys, not JWT bearer tokens.
	# An authenticated player token and a legacy anon JWT remain valid bearers.
	if bearer.is_empty() and api_key.begins_with("eyJ") and api_key.count(".") == 2:
		bearer = api_key
	if not bearer.is_empty():
		headers.append("Authorization: Bearer %s" % bearer)
	if not content_type.is_empty():
		headers.append("Content-Type: %s" % content_type)
	return headers


func _response_message(response: Dictionary) -> String:
	var data: Variant = response.get("data", {})
	if data is Dictionary:
		for key in ["message", "msg", "error_description", "error", "hint"]:
			var value := String((data as Dictionary).get(key, ""))
			if not value.is_empty():
				return value
	var raw := String(response.get("raw", "")).strip_edges()
	return raw if not raw.is_empty() else "Community service request failed (%d)." % int(response.get("status", 0))


func _identity_result() -> Dictionary:
	return {"ok": true, "message": "Playing as %s" % display_name(), "user_id": user_id(), "display_name": display_name()}


func _session_is_fresh() -> bool:
	return (
		has_guest_session()
		and int(session.get("expires_at", 0)) > int(Time.get_unix_time_from_system()) + 60
	)


func _clear_session() -> void:
	session.clear()
	if FileAccess.file_exists(session_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(session_path))


func _load_config() -> void:
	var config := _load_json_file(CONFIG_PATH)
	if config.is_empty():
		config = _load_json_file(PUBLIC_CONFIG_PATH)
	project_url = String(config.get("project_url", "")).trim_suffix("/")
	publishable_key = String(config.get("publishable_key", ""))
	storage_bucket = String(config.get("storage_bucket", "community-map-assets"))


func _random_callsign() -> String:
	var random := RandomNumberGenerator.new()
	random.randomize()
	return "%s_%04d" % [CALLSIGN_PREFIXES[random.randi_range(0, CALLSIGN_PREFIXES.size() - 1)], random.randi_range(1000, 9999)]


func _local_asset_paths(map_document: Dictionary) -> Array[String]:
	var paths: Array[String] = []
	for object: Dictionary in map_document.get("objects", []):
		if String(object.get("type", "")) != "imported_asset":
			continue
		var path := String((object.get("properties", {}) as Dictionary).get("asset_path", ""))
		if path.begins_with("user://") and path not in paths:
			paths.append(path)
	return paths


func _sha256_text(value: String) -> String:
	return _sha256_bytes(value.to_utf8_buffer())


func _load_json_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	return parsed as Dictionary if parsed is Dictionary else {}


func _save_json_file(path: String, data: Dictionary) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(data, "  "))
	file.close()
	return true
