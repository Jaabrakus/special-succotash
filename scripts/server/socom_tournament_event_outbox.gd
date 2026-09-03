class_name SocomTournamentEventOutbox
extends RefCounted

## Durable server-side delivery journal for tournament results.
##
## This is deliberately not part of the realtime ENet path. Movement, aim,
## shots, and snapshots are transient gameplay traffic. Only completed arena
## matches and final tournament outcomes are journaled for cloud delivery.

const DEFAULT_STORAGE_ROOT := "user://server_outbox"
const RETRY_BASE_SECONDS := 2.0
const RETRY_MAX_SECONDS := 60.0

var storage_root := DEFAULT_STORAGE_ROOT
var match_id := ""
var journal_path := ""
var entries: Dictionary = {}


func start_session(new_match_id: String, requested_storage_root: String = "") -> bool:
	match_id = new_match_id.strip_edges()
	if match_id.is_empty():
		return false
	storage_root = requested_storage_root if not requested_storage_root.is_empty() else DEFAULT_STORAGE_ROOT
	var directory_error := DirAccess.make_dir_recursive_absolute(storage_root)
	if directory_error != OK and directory_error != ERR_ALREADY_EXISTS:
		push_warning("TOURNAMENT_OUTBOX_DIRECTORY_FAILED error=%d" % directory_error)
		return false
	journal_path = "%s/%s.jsonl" % [storage_root.path_join("tournaments"), _safe_path_component(match_id)]
	var tournament_directory := journal_path.get_base_dir()
	directory_error = DirAccess.make_dir_recursive_absolute(tournament_directory)
	if directory_error != OK and directory_error != ERR_ALREADY_EXISTS:
		push_warning("TOURNAMENT_OUTBOX_DIRECTORY_FAILED error=%d" % directory_error)
		return false
	entries.clear()
	_rehydrate()
	return true


func enqueue(event: Dictionary) -> Dictionary:
	var normalized := _normalize_event(event)
	if normalized.is_empty():
		return {"accepted": false, "reason": "INVALID_EVENT"}
	var event_id := String(normalized.get("event_id", ""))
	if entries.has(event_id):
		return {"accepted": true, "duplicate": true, "event_id": event_id}
	entries[event_id] = normalized
	_append({"record_type": "queued", "event": normalized})
	return {"accepted": true, "duplicate": false, "event_id": event_id}


func next_pending(now_unix: float = -1.0) -> Dictionary:
	var now := Time.get_unix_time_from_system() if now_unix < 0.0 else now_unix
	var selected: Dictionary = {}
	for raw_event_id in entries:
		var entry: Dictionary = entries[raw_event_id]
		if String(entry.get("delivery_status", "pending")) != "pending":
			continue
		if float(entry.get("next_attempt_unix", 0.0)) > now:
			continue
		if selected.is_empty() or float(entry.get("queued_at_unix", 0.0)) < float(selected.get("queued_at_unix", 0.0)):
			selected = entry.duplicate(true)
	return selected


func mark_delivered(event_id: String, delivered_at_unix: float = -1.0) -> bool:
	if not entries.has(event_id):
		return false
	var entry: Dictionary = entries[event_id]
	if String(entry.get("delivery_status", "pending")) == "delivered":
		return true
	entry["delivery_status"] = "delivered"
	entry["delivered_at_unix"] = Time.get_unix_time_from_system() if delivered_at_unix < 0.0 else delivered_at_unix
	entries[event_id] = entry
	_append({
		"record_type": "delivered",
		"event_id": event_id,
		"delivered_at_unix": entry["delivered_at_unix"],
	})
	return true


func mark_delivery_failed(event_id: String, message: String, now_unix: float = -1.0) -> bool:
	if not entries.has(event_id):
		return false
	var now := Time.get_unix_time_from_system() if now_unix < 0.0 else now_unix
	var entry: Dictionary = entries[event_id]
	var attempts := int(entry.get("delivery_attempts", 0)) + 1
	var retry_seconds := minf(RETRY_BASE_SECONDS * pow(2.0, attempts - 1), RETRY_MAX_SECONDS)
	entry["delivery_attempts"] = attempts
	entry["last_error"] = message.left(240)
	entry["last_attempt_unix"] = now
	entry["next_attempt_unix"] = now + retry_seconds
	entries[event_id] = entry
	_append({
		"record_type": "retry_scheduled",
		"event_id": event_id,
		"delivery_attempts": attempts,
		"last_error": entry["last_error"],
		"last_attempt_unix": now,
		"next_attempt_unix": entry["next_attempt_unix"],
	})
	return true


func pending_count() -> int:
	var count := 0
	for entry: Dictionary in entries.values():
		if String(entry.get("delivery_status", "pending")) == "pending":
			count += 1
	return count


func get_entry(event_id: String) -> Dictionary:
	var entry: Dictionary = entries.get(event_id, {})
	return entry.duplicate(true)


func _normalize_event(event: Dictionary) -> Dictionary:
	var event_id := String(event.get("event_id", "")).strip_edges()
	var event_match_id := String(event.get("match_id", "")).strip_edges()
	var event_type := String(event.get("event_type", "")).strip_edges()
	var payload: Variant = event.get("payload", {})
	if event_id.is_empty() or event_match_id != match_id or event_type.is_empty() or not payload is Dictionary:
		return {}
	return {
		"event_id": event_id,
		"match_id": event_match_id,
		"arena_id": int(event.get("arena_id", -1)),
		"event_type": event_type,
		"payload": (payload as Dictionary).duplicate(true),
		"queued_at_unix": float(event.get("queued_at_unix", Time.get_unix_time_from_system())),
		"delivery_status": "pending",
		"delivery_attempts": 0,
		"next_attempt_unix": 0.0,
	}


func _rehydrate() -> void:
	if journal_path.is_empty() or not FileAccess.file_exists(journal_path):
		return
	var file := FileAccess.open(journal_path, FileAccess.READ)
	if file == null:
		return
	while not file.eof_reached():
		var line := file.get_line().strip_edges()
		if line.is_empty():
			continue
		var parsed: Variant = JSON.parse_string(line)
		if not parsed is Dictionary:
			continue
		_apply_journal_record(parsed as Dictionary)
	file.close()


func _apply_journal_record(record: Dictionary) -> void:
	match String(record.get("record_type", "")):
		"queued":
			var raw_event: Variant = record.get("event", {})
			if raw_event is Dictionary:
				var event: Dictionary = raw_event
				var event_id := String(event.get("event_id", ""))
				if not event_id.is_empty():
					entries[event_id] = event.duplicate(true)
		"delivered":
			var delivered_id := String(record.get("event_id", ""))
			if entries.has(delivered_id):
				var delivered: Dictionary = entries[delivered_id]
				delivered["delivery_status"] = "delivered"
				delivered["delivered_at_unix"] = float(record.get("delivered_at_unix", 0.0))
				entries[delivered_id] = delivered
		"retry_scheduled":
			var retry_id := String(record.get("event_id", ""))
			if entries.has(retry_id):
				var retry: Dictionary = entries[retry_id]
				retry["delivery_attempts"] = int(record.get("delivery_attempts", 0))
				retry["last_error"] = String(record.get("last_error", ""))
				retry["last_attempt_unix"] = float(record.get("last_attempt_unix", 0.0))
				retry["next_attempt_unix"] = float(record.get("next_attempt_unix", 0.0))
				entries[retry_id] = retry


func _append(record: Dictionary) -> void:
	if journal_path.is_empty():
		return
	var file: FileAccess
	if FileAccess.file_exists(journal_path):
		file = FileAccess.open(journal_path, FileAccess.READ_WRITE)
		if file != null:
			file.seek_end()
	else:
		file = FileAccess.open(journal_path, FileAccess.WRITE)
	if file == null:
		push_warning("TOURNAMENT_OUTBOX_APPEND_FAILED %s" % journal_path)
		return
	file.store_line(JSON.stringify(record))
	file.flush()
	file.close()


func _safe_path_component(value: String) -> String:
	return value.replace("/", "_").replace("\\", "_").replace(":", "_")
