class_name SocomMatchEventLogger
extends RefCounted

## Server-authoritative match and tournament event logger.
## Records structured JSONL event records to disk and provides live audit logs.

const LOG_DIR := "user://logs/matches"

var log_file_path: String = ""
var file_handle: FileAccess
var match_id: String = ""
var session_active: bool = false
var in_memory_events: Array[Dictionary] = []


func initialize_session(new_match_id: String = "") -> String:
	match_id = new_match_id if not new_match_id.is_empty() else "match_%d" % int(Time.get_unix_time_from_system())
	session_active = true
	in_memory_events.clear()
	var dir_err := DirAccess.make_dir_recursive_absolute(LOG_DIR)
	if dir_err != OK and dir_err != ERR_ALREADY_EXISTS:
		push_warning("Failed to create log directory: %s (error %d)" % [LOG_DIR, dir_err])
	log_file_path = "%s/%s.jsonl" % [LOG_DIR, match_id]
	file_handle = FileAccess.open(log_file_path, FileAccess.WRITE)
	if file_handle == null:
		push_warning("Failed to open match event log: %s" % log_file_path)
	log_event("SESSION_INITIALIZED", {
		"match_id": match_id,
		"started_at_unix": Time.get_unix_time_from_system(),
		"started_at_iso": Time.get_datetime_string_from_system(true),
	}, 0)
	return match_id


func start_session(new_match_id: String = "") -> String:
	return initialize_session(new_match_id)


func log_event(event_type: String, event_data: Dictionary, round_idx: int = 0) -> Dictionary:
	var record := {
		"timestamp_ms": Time.get_ticks_msec(),
		"unix_time": Time.get_unix_time_from_system(),
		"round": round_idx,
		"event": event_type,
		"data": event_data,
	}
	in_memory_events.append(record)
	if file_handle != null:
		file_handle.store_line(JSON.stringify(record))
		file_handle.flush()
	return record


func end_session() -> void:
	if not session_active:
		return
	log_event("SESSION_COMPLETED", {
		"match_id": match_id,
		"ended_at_unix": Time.get_unix_time_from_system(),
		"total_events_logged": in_memory_events.size(),
	}, 0)
	if file_handle != null:
		file_handle.close()
		file_handle = null
	session_active = false


func get_in_memory_events() -> Array[Dictionary]:
	return in_memory_events.duplicate(true)
