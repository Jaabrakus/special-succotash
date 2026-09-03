class_name GunsLab2VisualRigRepository
extends RefCounted

const CONTRACT := preload(
	"res://scripts/labs/gunsmith2/weapon_visual_rig_contract.gd"
)

var published_directory := "res://config/weapon_visual_rigs/"
var draft_directory := "res://config/weapon_visual_rigs/drafts/"
var weapon_directory := "res://config/weapons/"


func _init(
	published_path: String = "res://config/weapon_visual_rigs/",
	draft_path: String = "res://config/weapon_visual_rigs/drafts/",
	weapon_path: String = "res://config/weapons/"
) -> void:
	published_directory = _with_trailing_slash(published_path)
	draft_directory = _with_trailing_slash(draft_path)
	weapon_directory = _with_trailing_slash(weapon_path)


func save_draft(base_id: String, source_profile: Dictionary) -> Dictionary:
	var clean_id := _clean_id(base_id)
	if clean_id.is_empty():
		return {"ok": false, "error": "Visual rig ID is empty."}
	var document := CONTRACT.extract(source_profile, clean_id, 1, "draft")
	var validation := CONTRACT.validate(document, false)
	if not bool(validation.get("ok", false)):
		return {
			"ok": false,
			"error": "Draft validation failed.",
			"errors": validation.get("errors", []),
		}
	return _write_json(draft_directory + clean_id + ".json", document)


func save_draft_document(base_id: String, document: Dictionary) -> Dictionary:
	var clean_id := _clean_id(base_id)
	var next_document := document.duplicate(true)
	next_document["schema_version"] = CONTRACT.CURRENT_SCHEMA_VERSION
	next_document["visual_rig_id"] = clean_id
	next_document["revision"] = maxi(int(next_document.get("revision", 1)), 1)
	next_document["status"] = "draft"
	var validation := CONTRACT.validate(next_document, false)
	if not bool(validation.get("ok", false)):
		return {
			"ok": false,
			"error": "Draft validation failed.",
			"errors": validation.get("errors", []),
		}
	return _write_json(draft_directory + clean_id + ".json", next_document)


func publish(base_id: String) -> Dictionary:
	var clean_id := _clean_id(base_id)
	var draft := _read_json(draft_directory + clean_id + ".json")
	if draft.is_empty():
		return {"ok": false, "error": "Save a draft before publishing."}
	var revision := _next_revision(clean_id)
	var published_id := "%s_v%d" % [clean_id, revision]
	draft["visual_rig_id"] = published_id
	draft["revision"] = revision
	draft["status"] = "published"
	var validation := CONTRACT.validate(draft, true)
	if not bool(validation.get("ok", false)):
		return {
			"ok": false,
			"error": "Publish validation failed.",
			"errors": validation.get("errors", []),
		}
	var path := published_directory + published_id + ".json"
	if FileAccess.file_exists(path):
		return {"ok": false, "error": "Published versions are immutable."}
	var result := _write_json(path, draft)
	if bool(result.get("ok", false)):
		result["visual_rig_id"] = published_id
		result["revision"] = revision
	return result


func assign_to_weapon(weapon_id: String, visual_rig_id: String) -> Dictionary:
	var clean_visual_rig_id := _clean_id(visual_rig_id)
	var rig := _read_json(published_directory + clean_visual_rig_id + ".json")
	var validation := CONTRACT.validate(rig, true, clean_visual_rig_id)
	if not bool(validation.get("ok", false)):
		return {"ok": false, "error": "Only a valid published rig can be assigned."}
	var clean_weapon_id := _clean_id(weapon_id)
	var path := weapon_directory + clean_weapon_id + ".json"
	var profile := _read_json(path)
	if profile.is_empty():
		return {"ok": false, "error": "Weapon profile does not exist: %s" % clean_weapon_id}
	profile["visual_rig_id"] = String(rig.visual_rig_id)
	profile["visual_rig_schema_version"] = CONTRACT.CURRENT_SCHEMA_VERSION
	return _write_json(path, profile)


func load_draft(base_id: String) -> Dictionary:
	return _read_json(draft_directory + _clean_id(base_id) + ".json")


func load_published(visual_rig_id: String) -> Dictionary:
	return _read_json(published_directory + _clean_id(visual_rig_id) + ".json")


func list_published() -> PackedStringArray:
	var result := PackedStringArray()
	var directory := DirAccess.open(published_directory)
	if directory == null:
		return result
	for file_name in directory.get_files():
		if file_name.ends_with(".json"):
			result.append(file_name.get_basename())
	result.sort()
	return result


func _next_revision(base_id: String) -> int:
	var highest := 0
	for published_id in list_published():
		var prefix := base_id + "_v"
		if String(published_id).begins_with(prefix):
			highest = maxi(highest, int(String(published_id).trim_prefix(prefix)))
	return highest + 1


func _write_json(path: String, document: Dictionary) -> Dictionary:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "error": "Could not write %s" % path}
	file.store_string(JSON.stringify(document, "  "))
	file.close()
	return {"ok": true, "path": path, "document": document.duplicate(true)}


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(file.get_as_text()) if file != null else null
	return (parsed as Dictionary).duplicate(true) if parsed is Dictionary else {}


func _clean_id(value: String) -> String:
	var clean := value.to_lower().strip_edges().replace(" ", "_")
	var result := ""
	for character in clean:
		if character in "abcdefghijklmnopqrstuvwxyz0123456789_-":
			result += character
	return result


func _with_trailing_slash(path: String) -> String:
	return path if path.ends_with("/") else path + "/"
