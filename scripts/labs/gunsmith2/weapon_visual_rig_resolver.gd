class_name GunsLab2VisualRigResolver
extends RefCounted

const CONTRACT := preload(
	"res://scripts/labs/gunsmith2/weapon_visual_rig_contract.gd"
)
const PUBLISHED_DIRECTORY := "res://config/weapon_visual_rigs/"
const FAMILY_ASSIGNMENTS_PATH := "res://config/weapon_family_visual_assignments.json"

static var _cache: Dictionary = {}
static var _family_assignments: Dictionary = {}
static var _family_assignments_loaded := false


static func resolve_for_presentation(weapon_profile: Dictionary) -> Dictionary:
	var visual_rig_id := String(weapon_profile.get("visual_rig_id", "")).strip_edges()
	var inherited_from_family := false
	if visual_rig_id.is_empty() and not bool(
		weapon_profile.get("socket_contract_authored", false)
	):
		visual_rig_id = _family_visual_rig_id(weapon_profile)
		inherited_from_family = not visual_rig_id.is_empty()
	if visual_rig_id.is_empty():
		return weapon_profile.duplicate(true)
	var assigned_rig := load_published(visual_rig_id)
	if assigned_rig.is_empty():
		push_warning(
			"Assigned weapon visual rig '%s' is unavailable; using the weapon profile." \
			% visual_rig_id
		)
		return weapon_profile.duplicate(true)
	var result := CONTRACT.merge_for_presentation(weapon_profile, assigned_rig)
	result["_visual_rig_assignment"] = (
		"family_model" if inherited_from_family else "weapon_profile"
	)
	return result


static func load_published(visual_rig_id: String) -> Dictionary:
	var requested_id := visual_rig_id.strip_edges()
	if requested_id.is_empty() or requested_id.get_file() != requested_id:
		return {}
	if _cache.has(requested_id):
		return (_cache[requested_id] as Dictionary).duplicate(true)
	var path := PUBLISHED_DIRECTORY + requested_id + ".json"
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(file.get_as_text()) if file != null else null
	if not parsed is Dictionary:
		return {}
	var document := parsed as Dictionary
	var validation := CONTRACT.validate(document, true, requested_id)
	if not bool(validation.get("ok", false)):
		push_warning(
			"Weapon visual rig '%s' was rejected: %s" % [
				requested_id,
				str(validation.get("errors", [])),
			]
		)
		return {}
	_cache[requested_id] = document.duplicate(true)
	return document.duplicate(true)


static func clear_cache() -> void:
	_cache.clear()
	_family_assignments.clear()
	_family_assignments_loaded = false


static func _family_visual_rig_id(weapon_profile: Dictionary) -> String:
	_load_family_assignments()
	var weapon_id := String(weapon_profile.get("weapon_id", "")).to_lower()
	var excluded: Variant = _family_assignments.get("excluded_weapon_ids", [])
	if excluded is Array and weapon_id in (excluded as Array):
		return ""
	var model_path := String(weapon_profile.get("model_fbx", ""))
	var assignments: Variant = _family_assignments.get("model_assignments", {})
	if not assignments is Dictionary or not (assignments as Dictionary).has(model_path):
		return ""
	var entry: Variant = (assignments as Dictionary).get(model_path, {})
	if not entry is Dictionary:
		return ""
	var categories: Variant = (entry as Dictionary).get("categories", [])
	var category := String(weapon_profile.get("category", ""))
	if categories is Array and not (categories as Array).is_empty():
		if category not in (categories as Array):
			return ""
	return String((entry as Dictionary).get("visual_rig_id", ""))


static func _load_family_assignments() -> void:
	if _family_assignments_loaded:
		return
	_family_assignments_loaded = true
	if not FileAccess.file_exists(FAMILY_ASSIGNMENTS_PATH):
		return
	var file := FileAccess.open(FAMILY_ASSIGNMENTS_PATH, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(file.get_as_text()) if file != null else null
	if parsed is Dictionary and int((parsed as Dictionary).get("schema_version", 0)) == 1:
		_family_assignments = (parsed as Dictionary).duplicate(true)
