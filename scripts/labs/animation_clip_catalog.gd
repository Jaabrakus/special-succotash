class_name SocomAnimationClipCatalog
extends RefCounted

## Read-only catalog labels for Animation Studio. A filename may suggest a
## weapon family, but only an exact state-slot assignment is called live.

const WeaponRigContract := preload("res://scripts/weapons/weapon_rig_contract.gd")
const ANIMATION_MAP_PATH := "res://config/operator_animation_map.json"

const LIVE := "LIVE"
const ASSIGNED_OTHER := "ASSIGNED_OTHER"
const RIFLE_CANDIDATE := "RIFLE_CANDIDATE"
const OTHER_FAMILY := "OTHER_FAMILY"
const UNCLASSIFIED := "UNCLASSIFIED"

var weapon_family: String = "TWO_HAND_RIFLE"
var family_state_names: Dictionary = {}


func refresh_equipped_family() -> void:
	weapon_family = "TWO_HAND_RIFLE"
	family_state_names.clear()
	var config := WeaponRigContract.load_equipped_config()
	var profile: Variant = config.get("handling_profile", {})
	if not profile is Dictionary:
		return
	weapon_family = String((profile as Dictionary).get("family", weapon_family))
	for section_name in ["animation_slots", "locomotion_slots"]:
		var raw_section: Variant = (profile as Dictionary).get(section_name, {})
		if not raw_section is Dictionary:
			continue
		for state_name in (raw_section as Dictionary).values():
			var normalized := String(state_name)
			if not normalized.is_empty():
				family_state_names[normalized] = true
	_include_approved_playtest_states()


func describe(entry: Dictionary, state_slots: Dictionary, suggested_state: String = "") -> Dictionary:
	var assigned_states: Array[String] = []
	var live_states: Array[String] = []
	var resource_path := String(entry.get("path", ""))
	if not resource_path.is_empty():
		for raw_state in state_slots.keys():
			var state_name := String(raw_state)
			if String(state_slots[raw_state]) != resource_path:
				continue
			assigned_states.append(state_name)
			if family_state_names.has(state_name):
				live_states.append(state_name)
	assigned_states.sort()
	live_states.sort()

	var status := UNCLASSIFIED
	var family_hint := _family_hint(entry)
	var badge := "? UNCLASSIFIED • preview only"
	var detail := "This clip is not connected to gameplay and its weapon family is not confirmed."
	var color := Color(0.72, 0.76, 0.82)
	if not live_states.is_empty():
		status = LIVE
		badge = "✓ LIVE %s • %s" % [_friendly_family(weapon_family), ", ".join(live_states)]
		detail = "Exact saved assignment in the approved playable set: %s." % ", ".join(live_states)
		color = Color(0.38, 1.0, 0.64)
	elif not assigned_states.is_empty():
		status = ASSIGNED_OTHER
		badge = "• ASSIGNED OTHER STATE • %s" % ", ".join(assigned_states)
		detail = "Assigned in the shared map, but not selected by the equipped %s profile." % weapon_family
		color = Color(0.55, 0.82, 1.0)
	elif family_hint in ["RIFLE", "SHOOTER"]:
		status = RIFLE_CANDIDATE
		badge = "◇ %s CANDIDATE%s" % [
			family_hint,
			" → try %s" % suggested_state if not suggested_state.is_empty() else " • not connected",
		]
		detail = "The source name suggests a compatible clip, but gameplay does not use it until you assign and approve a state."
		color = Color(1.0, 0.80, 0.38)
	elif family_hint != "":
		status = OTHER_FAMILY
		badge = "OTHER FAMILY • %s" % family_hint
		detail = "Kept separate from the equipped %s animation family." % weapon_family
		color = Color(0.95, 0.58, 0.78)

	return {
		"status": status,
		"badge": badge,
		"detail": detail,
		"color": color,
		"title": _clean_title(String(entry.get("display", "Animation clip"))),
		"family_hint": family_hint,
		"assigned_states": assigned_states,
		"live_states": live_states,
	}


func filter(entries: Array[Dictionary], state_slots: Dictionary, catalog_filter: String) -> Array[Dictionary]:
	var filtered: Array[Dictionary] = []
	for entry in entries:
		var status := String(describe(entry, state_slots).get("status", UNCLASSIFIED))
		var include := (
			catalog_filter == "ALL"
			or (catalog_filter == "LIVE IN GAME" and status == LIVE)
			or (catalog_filter == "RIFLE + SHOOTER CANDIDATES" and status == RIFLE_CANDIDATE)
			or (catalog_filter == "NEEDS CLASSIFICATION" and status == UNCLASSIFIED)
		)
		if include:
			filtered.append(entry)
	return filtered


func legend_text() -> String:
	return "EQUIPPED: %s\n✓ LIVE = approved playable set   ◇ CANDIDATE = preview only   ? = classify first" % _friendly_family(weapon_family)


func _include_approved_playtest_states() -> void:
	if not FileAccess.file_exists(ANIMATION_MAP_PATH):
		return
	var file := FileAccess.open(ANIMATION_MAP_PATH, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(file.get_as_text()) if file != null else null
	if not parsed is Dictionary:
		return
	var raw_clips: Variant = (parsed as Dictionary).get("clips", {})
	if not raw_clips is Dictionary:
		return
	var pistol_family := weapon_family in ["ONE_HAND", "TWO_HAND_PISTOL"]
	for raw_state_name in (raw_clips as Dictionary).keys():
		var state_name := String(raw_state_name)
		var pistol_state := state_name.begins_with("pistol_")
		if pistol_state == pistol_family or _is_shared_action_state(state_name):
			family_state_names[state_name] = true


func _is_shared_action_state(state_name: String) -> bool:
	return (
		state_name in [
			"dive_roll", "roll", "climb", "death_right",
			"grenade_toss", "grenade_throw", "crouch_grenade_toss",
			"jump_forward_action", "jump_backward_action",
		]
		or state_name.begins_with("jump_")
	)


func _family_hint(entry: Dictionary) -> String:
	var searchable := (String(entry.get("display", "")) + " " + String(entry.get("path", ""))).to_lower()
	if "pistol" in searchable or "revolver" in searchable:
		return "PISTOL"
	if "rifle" in searchable or "long gun" in searchable or "lite rifle" in searchable:
		return "RIFLE"
	if "shooter pack" in searchable or "[shooter]" in searchable:
		return "SHOOTER"
	return ""


func _friendly_family(value: String) -> String:
	return value.replace("TWO_HAND_", "").replace("_", " ")


func _clean_title(value: String) -> String:
	for prefix in ["[Rifle] ", "[Pistol] ", "[Shooter] "]:
		if value.begins_with(prefix):
			return value.trim_prefix(prefix)
	return value
