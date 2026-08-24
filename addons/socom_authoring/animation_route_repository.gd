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
var loaded_source_sha256 := ""
var saved_document: Dictionary = {}


func load_profile(path: String = PROFILE_PATH) -> bool:
	profile_path = path
	if not FileAccess.file_exists(path):
		_reset_state()
		errors.append("Animation map does not exist: %s" % path)
		return false
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_reset_state()
		errors.append("Animation map cannot be read: %s" % path)
		return false
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary:
		_reset_state()
		errors.append("Animation map is not valid JSON data.")
		return false
	_apply_document(parsed as Dictionary)
	if not errors.is_empty():
		return false
	loaded_source_sha256 = FileAccess.get_sha256(path)
	saved_document = document.duplicate(true)
	return true


func replace_document(candidate: Dictionary) -> Dictionary:
	var previous: Dictionary = document.duplicate(true)
	_apply_document(candidate)
	if errors.is_empty():
		return {"ok": true, "errors": []}
	var candidate_errors: Array[String] = errors.duplicate()
	_apply_document(previous)
	return {"ok": false, "errors": candidate_errors}


func document_snapshot() -> Dictionary:
	return document.duplicate(true)


func is_dirty() -> bool:
	return JSON.stringify(document) != JSON.stringify(saved_document)


func build_route_proposal(proposal: Dictionary) -> Dictionary:
	var proposal_errors: Array[String] = []
	var event_name := String(proposal.get("event", "")).to_upper()
	var state_name := String(proposal.get("state", ""))
	var layer := String(proposal.get("layer", StateContract.FULL_BODY)).to_upper()
	if event_name not in StateContract.VALID_EVENTS:
		proposal_errors.append("Choose a defined Gameplay Dictionary event.")
	if not slots.has(state_name):
		proposal_errors.append("Choose a mapped animation state.")
	if layer not in StateContract.VALID_LAYERS:
		proposal_errors.append("Choose FULL BODY or UPPER BODY.")
	if slots.has(state_name):
		var compatibility_slot := state_name
		if event_name == "FIRE_ACCEPTED":
			compatibility_slot = "combat_fire"
		elif event_name == "RELOAD_STARTED":
			compatibility_slot = "reload"
		var compatibility_error := StateContract.clip_compatibility_error(
			compatibility_slot,
			String(slots.get(state_name, "")).get_file(),
			String(slots.get(state_name, ""))
		)
		if not compatibility_error.is_empty():
			proposal_errors.append(compatibility_error)
	var postures: Array[String] = []
	var raw_postures: Variant = proposal.get("postures", [])
	if raw_postures is Array:
		for raw_posture: Variant in raw_postures:
			var posture := String(raw_posture).to_upper()
			if posture in ["STANDING", "CROUCHED", "PRONE"] and posture not in postures:
				postures.append(posture)
	if postures.is_empty():
		proposal_errors.append("Choose at least one posture.")
	if not proposal_errors.is_empty():
		return {"ok": false, "errors": proposal_errors, "document": {}}

	var candidate: Dictionary = document.duplicate(true)
	var raw_state_rules: Variant = candidate.get("state_rules", {})
	var state_rules: Dictionary = (
		(raw_state_rules as Dictionary).duplicate(true) if raw_state_rules is Dictionary else {}
	)
	var raw_rule: Variant = state_rules.get(state_name, {})
	var rule: Dictionary = (
		(raw_rule as Dictionary).duplicate(true) if raw_rule is Dictionary else {}
	)
	rule["layer"] = layer
	rule["blend_in_seconds"] = clampf(
		float(proposal.get("blend_in_seconds", 0.12)),
		0.0,
		1.0
	)
	rule["blend_out_seconds"] = clampf(
		float(proposal.get("blend_out_seconds", 0.14)),
		0.0,
		1.0
	)
	rule["return_state"] = StateContract.CURRENT_BASE
	var source_rule := String(proposal.get("source_rule", "")).strip_edges()
	if not source_rule.is_empty():
		rule["source_rule"] = source_rule
		rule["authoring_mode"] = "SOCOM_RULES"
	state_rules[state_name] = rule
	candidate["state_rules"] = state_rules

	var raw_event_routes: Variant = candidate.get("event_routes", {})
	var event_routes: Dictionary = (
		(raw_event_routes as Dictionary).duplicate(true) if raw_event_routes is Dictionary else {}
	)
	var raw_route: Variant = event_routes.get(event_name, {})
	var route: Dictionary = (
		(raw_route as Dictionary).duplicate(true) if raw_route is Dictionary else {}
	)
	route["default_state"] = state_name
	var raw_posture_states: Variant = route.get("posture_states", {})
	var posture_states: Dictionary = (
		(raw_posture_states as Dictionary).duplicate(true)
		if raw_posture_states is Dictionary else {}
	)
	for posture: String in postures:
		posture_states[posture] = state_name
	route["posture_states"] = posture_states
	var weapon_family := String(proposal.get("weapon_family", "")).to_upper()
	if not weapon_family.is_empty() and weapon_family != "ANY":
		var raw_family_states: Variant = route.get("family_states", {})
		var family_states: Dictionary = (
			(raw_family_states as Dictionary).duplicate(true)
			if raw_family_states is Dictionary else {}
		)
		var raw_family_route: Variant = family_states.get(weapon_family, {})
		var family_route: Dictionary = (
			(raw_family_route as Dictionary).duplicate(true)
			if raw_family_route is Dictionary else {}
		)
		family_route["default_state"] = state_name
		var raw_family_postures: Variant = family_route.get("posture_states", {})
		var family_postures: Dictionary = (
			(raw_family_postures as Dictionary).duplicate(true)
			if raw_family_postures is Dictionary else {}
		)
		for posture: String in postures:
			family_postures[posture] = state_name
		family_route["posture_states"] = family_postures
		family_states[weapon_family] = family_route
		route["family_states"] = family_states
	route["return_policy"] = StateContract.CURRENT_BASE
	route["interrupt_policy"] = String(proposal.get("interrupt_policy", "RESTART"))
	route["priority"] = clampi(int(proposal.get("priority", 50)), 0, 100)
	var effects: Array[String] = []
	var raw_effects: Variant = proposal.get("effects", StateContract.default_effects(event_name))
	if raw_effects is Array:
		for raw_effect: Variant in raw_effects:
			var effect_name := String(raw_effect).to_upper()
			if effect_name in StateContract.VALID_EFFECTS and effect_name not in effects:
				effects.append(effect_name)
	route["effects"] = effects
	event_routes[event_name] = route
	candidate["event_routes"] = event_routes

	var previous: Dictionary = document.duplicate(true)
	_apply_document(candidate)
	var normalized_errors: Array[String] = errors.duplicate()
	_apply_document(previous)
	if not normalized_errors.is_empty():
		return {"ok": false, "errors": normalized_errors, "document": {}}
	return {
		"ok": true,
		"errors": [],
		"document": candidate,
		"summary": "%s → %s for %s" % [event_name, state_name, ", ".join(postures)],
	}


func save_profile(path: String = "") -> Dictionary:
	var target_path := profile_path if path.is_empty() else path
	if not errors.is_empty():
		return {"ok": false, "error": "Fix profile validation errors before saving."}
	if target_path == profile_path and FileAccess.file_exists(target_path):
		var disk_hash := FileAccess.get_sha256(target_path)
		if not loaded_source_sha256.is_empty() and disk_hash != loaded_source_sha256:
			return {
				"ok": false,
				"error": "The animation map changed on disk. Refresh before saving.",
			}
	var absolute_path := ProjectSettings.globalize_path(target_path)
	var temporary_path := "%s.socom-writing-%d" % [absolute_path, OS.get_process_id()]
	var file := FileAccess.open(temporary_path, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "error": "Could not open the temporary profile file."}
	file.store_string(JSON.stringify(document, "  ") + "\n")
	file.flush()
	file.close()
	var rename_error := DirAccess.rename_absolute(temporary_path, absolute_path)
	if rename_error != OK:
		DirAccess.remove_absolute(temporary_path)
		return {"ok": false, "error": "Could not replace the saved profile atomically."}
	profile_path = target_path
	loaded_source_sha256 = FileAccess.get_sha256(target_path)
	saved_document = document.duplicate(true)
	return {"ok": true, "path": target_path, "sha256": loaded_source_sha256}


func _apply_document(candidate: Dictionary) -> void:
	_reset_state()
	document = candidate.duplicate(true)
	var raw_slots: Variant = document.get("clips", {})
	if not raw_slots is Dictionary or (raw_slots as Dictionary).is_empty():
		errors.append("Animation map has no clip slots.")
		return
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


func _reset_state() -> void:
	document.clear()
	slots.clear()
	rules.clear()
	routes.clear()
	errors.clear()
	warnings.clear()


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
		"dirty": is_dirty(),
		"loaded_sha256": loaded_source_sha256,
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
