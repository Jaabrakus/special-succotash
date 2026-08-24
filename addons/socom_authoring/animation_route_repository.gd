@tool
class_name SocomEditorAnimationRouteRepository
extends RefCounted

## Editor-only adapter for the saved animation map. It owns no animation rules.
## Normalization and resolution stay in the same data-only runtime contracts.

const PROFILE_PATH := "res://config/operator_animation_map.json"
const StateContract := preload(
	"res://scripts/player/operator_animation_state_contract.gd"
)
const PresentationRouter := preload(
	"res://scripts/player/operator_presentation_router.gd"
)
const GameplayDictionary := preload(
	"res://scripts/runtime/gameplay_event_dictionary.gd"
)

var profile_path := PROFILE_PATH
var document: Dictionary = {}
var slots: Dictionary = {}
var rules: Dictionary = {}
var routes: Dictionary = {}
var errors: Array[String] = []
var warnings: Array[String] = []
var router = PresentationRouter.new()


func load_profile(path: String = PROFILE_PATH) -> bool:
	profile_path = path
	document.clear()
	slots.clear()
	rules.clear()
	routes.clear()
	errors.clear()
	warnings.clear()
	if not FileAccess.file_exists(path):
		errors.append("Animation map does not exist: %s" % path)
		return false
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		errors.append("Animation map cannot be read: %s" % path)
		return false
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary:
		errors.append("Animation map is not valid JSON data.")
		return false
	document = (parsed as Dictionary).duplicate(true)
	var raw_slots: Variant = document.get("clips", {})
	if not raw_slots is Dictionary or (raw_slots as Dictionary).is_empty():
		errors.append("Animation map has no clip slots.")
		return false
	for raw_slot: Variant in (raw_slots as Dictionary).keys():
		var slot_name := String(raw_slot)
		var clip_path := String((raw_slots as Dictionary)[raw_slot])
		if slot_name.is_empty() or clip_path.is_empty():
			errors.append("Animation map contains an empty clip assignment.")
			continue
		slots[slot_name] = clip_path
		if not ResourceLoader.exists(clip_path):
			errors.append("%s points to a missing clip: %s" % [slot_name, clip_path])
	rules = StateContract.normalized_rules(
		slots,
		document.get("state_rules", {}) as Dictionary
	)
	routes = StateContract.normalized_event_routes(
		slots,
		document.get("event_routes", {}) as Dictionary
	)
	_validate_saved_routes(document.get("event_routes", {}))
	router.configure(slots, rules, routes)
	return errors.is_empty()


func resolve(
	event_name: String,
	posture: String = "STANDING",
	weapon_family: String = "TWO_HAND_RIFLE",
	current_base_state: String = "idle_rifle"
) -> Dictionary:
	return router.resolve(StringName(event_name), {
		"posture": posture,
		"weapon_family": weapon_family,
		"current_base_state": current_base_state,
	})


func describe(plan: Dictionary) -> String:
	return router.describe(plan)


func event_names() -> Array[String]:
	var result := GameplayDictionary.event_names()
	result.sort()
	return result


func weapon_families() -> Array[String]:
	var result: Array[String] = []
	for raw_route: Variant in routes.values():
		if not raw_route is Dictionary:
			continue
		var family_states: Variant = (raw_route as Dictionary).get("family_states", {})
		if not family_states is Dictionary:
			continue
		for raw_family: Variant in (family_states as Dictionary).keys():
			var family := String(raw_family)
			if not family.is_empty() and family not in result:
				result.append(family)
	result.sort()
	return result


func event_description(event_name: String) -> String:
	return GameplayDictionary.describe_event(event_name)


func validation_snapshot() -> Dictionary:
	return {
		"ok": errors.is_empty(),
		"path": profile_path,
		"sha256": FileAccess.get_sha256(profile_path) if FileAccess.file_exists(profile_path) else "",
		"clip_count": slots.size(),
		"rule_count": rules.size(),
		"route_count": routes.size(),
		"errors": errors.duplicate(),
		"warnings": warnings.duplicate(),
	}


func _validate_saved_routes(raw_routes: Variant) -> void:
	if not raw_routes is Dictionary:
		errors.append("Animation map has no event-routes dictionary.")
		return
	for raw_event: Variant in (raw_routes as Dictionary).keys():
		var event_name := String(raw_event).to_upper()
		if event_name not in StateContract.VALID_EVENTS:
			warnings.append("Unknown presentation event is ignored: %s" % event_name)
		elif not routes.has(event_name):
			errors.append("Presentation event has no valid state target: %s" % event_name)
