class_name SocomAnimationCastingRepository
extends RefCounted

## Stores human animation-review decisions as project data. The board does not
## alter runtime animation mappings until a designer explicitly builds or
## assigns an approved recipe.

const SCHEMA_VERSION := 1
const UNREVIEWED := "unreviewed"
const USE := "use"
const REPAIR := "repair"
const PASS := "pass"
const REGION_KEYS := [
	"full_body",
	"legs_root",
	"torso_spine",
	"left_arm_shoulder",
	"right_arm_shoulder",
	"hands_weapon",
]


func empty_board() -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"clips": {},
	}


func load_board(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return empty_board()
	var file := FileAccess.open(path, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(file.get_as_text()) if file else null
	if not parsed is Dictionary:
		return empty_board()
	var board := (parsed as Dictionary).duplicate(true)
	board["schema_version"] = SCHEMA_VERSION
	if not board.get("clips", {}) is Dictionary:
		board["clips"] = {}
	return board


func save_board(path: String, board: Dictionary) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	var normalized := board.duplicate(true)
	normalized["schema_version"] = SCHEMA_VERSION
	if not normalized.get("clips", {}) is Dictionary:
		normalized["clips"] = {}
	file.store_string(JSON.stringify(normalized, "  "))
	return true


func entry_identity(entry: Dictionary) -> String:
	var path := String(entry.get("path", "")).strip_edges()
	if not path.is_empty():
		return path
	return "%s:%s" % [
		String(entry.get("type", "UNKNOWN")),
		String(entry.get("key", entry.get("name", "unnamed"))),
	]


func record_for(board: Dictionary, entry: Dictionary) -> Dictionary:
	var clips: Dictionary = board.get("clips", {})
	var identity := entry_identity(entry)
	if clips.has(identity) and clips[identity] is Dictionary:
		return (clips[identity] as Dictionary).duplicate(true)
	return {
		"identity": identity,
		"display": String(entry.get("display", identity)),
		"path": String(entry.get("path", "")),
		"type": String(entry.get("type", "UNKNOWN")),
		"decision": UNREVIEWED,
		"regions": {},
		"frame_range": {"start_seconds": 0.0, "end_seconds": 0.0},
	}


func save_review(
	board: Dictionary,
	entry: Dictionary,
	decision: String,
	regions: Dictionary,
	start_seconds: float,
	end_seconds: float
) -> Dictionary:
	var next_board := board.duplicate(true)
	var clips: Dictionary = next_board.get("clips", {}).duplicate(true)
	var record := record_for(next_board, entry)
	record["decision"] = decision if decision in [USE, REPAIR, PASS] else UNREVIEWED
	var clean_regions: Dictionary = {}
	for region_key in REGION_KEYS:
		if bool(regions.get(region_key, false)):
			clean_regions[region_key] = true
	if clean_regions.is_empty() and record["decision"] != PASS:
		clean_regions["full_body"] = true
	record["regions"] = clean_regions
	record["frame_range"] = {
		"start_seconds": maxf(start_seconds, 0.0),
		"end_seconds": maxf(end_seconds, start_seconds),
	}
	clips[entry_identity(entry)] = record
	next_board["clips"] = clips
	next_board["schema_version"] = SCHEMA_VERSION
	return next_board


func counts(board: Dictionary) -> Dictionary:
	var result := {USE: 0, REPAIR: 0, PASS: 0, UNREVIEWED: 0, "reviewed": 0}
	var clips: Dictionary = board.get("clips", {})
	for record_variant in clips.values():
		if not record_variant is Dictionary:
			continue
		var decision := String((record_variant as Dictionary).get("decision", UNREVIEWED))
		if not result.has(decision):
			decision = UNREVIEWED
		result[decision] = int(result[decision]) + 1
		if decision != UNREVIEWED:
			result["reviewed"] = int(result["reviewed"]) + 1
	return result
