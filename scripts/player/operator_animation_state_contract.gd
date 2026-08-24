@tool
class_name SocomOperatorAnimationStateContract
extends RefCounted

## Shared, data-only rules used by Animation Studio and the runtime driver.
## Gameplay authority never lives here; these settings affect presentation only.

const FULL_BODY := "FULL_BODY"
const UPPER_BODY := "UPPER_BODY"
const CURRENT_BASE := "CURRENT_BASE"
const RAIL_TO_BLUE_LINE := "RAIL_TO_BLUE_LINE"
const ENTER_READY_AIM := "ENTER_READY_AIM"
const APPLY_WEAPON_FAMILY := "APPLY_WEAPON_FAMILY"
const VALID_LAYERS := [FULL_BODY, UPPER_BODY]
const VALID_EFFECTS := [RAIL_TO_BLUE_LINE, ENTER_READY_AIM, APPLY_WEAPON_FAMILY]
const VALID_EVENTS := [
	"WEAPON_EQUIPPED",
	"FIRE_ACCEPTED",
	"RELOAD_STARTED",
	"POSTURE_CHANGED",
	"JUMPED",
	"GRENADE_RELEASED",
	"HIT_RECEIVED",
	"DIED",
]


static func normalized_rules(slots: Dictionary, saved_rules: Dictionary = {}) -> Dictionary:
	var result: Dictionary = {}
	for raw_slot in slots.keys():
		var slot_name := String(raw_slot)
		var defaults := default_rule(slot_name)
		var raw_rule: Variant = saved_rules.get(slot_name, {})
		if raw_rule is Dictionary:
			var rule := raw_rule as Dictionary
			defaults["layer"] = _valid_layer(String(rule.get("layer", defaults["layer"])))
			defaults["blend_in_seconds"] = clampf(
				float(rule.get("blend_in_seconds", defaults["blend_in_seconds"])),
				0.0,
				1.0
			)
			defaults["blend_out_seconds"] = clampf(
				float(rule.get("blend_out_seconds", defaults["blend_out_seconds"])),
				0.0,
				1.0
			)
			var return_state := String(rule.get("return_state", defaults["return_state"]))
			defaults["return_state"] = (
				return_state
				if return_state == CURRENT_BASE or slots.has(return_state)
				else defaults["return_state"]
			)
			var source_rule := String(rule.get("source_rule", "")).strip_edges()
			if not source_rule.is_empty():
				defaults["source_rule"] = source_rule
				defaults["authoring_mode"] = "SOCOM_RULES"
		defaults["layer"] = _safe_layer_for_state(slot_name, String(defaults["layer"]))
		result[slot_name] = defaults
	return result


static func default_rule(slot_name: String) -> Dictionary:
	return {
		"layer": UPPER_BODY if state_supports_layer_choice(slot_name) else FULL_BODY,
		"blend_in_seconds": 0.06 if _is_fire_state(slot_name) else 0.12,
		"blend_out_seconds": 0.10 if _is_fire_state(slot_name) else 0.14,
		"return_state": _default_return_state(slot_name),
	}


static func normalized_event_routes(
	slots: Dictionary,
	saved_routes: Dictionary = {}
) -> Dictionary:
	var routes: Dictionary = {}
	for event_name in VALID_EVENTS:
		var raw: Variant = saved_routes.get(event_name, {})
		if not raw is Dictionary or (raw as Dictionary).is_empty():
			continue
		var raw_route := raw as Dictionary
		var default_state := String(raw_route.get("default_state", ""))
		if not slots.has(default_state):
			continue
		var posture_states: Dictionary = {}
		var raw_postures: Variant = raw_route.get("posture_states", {})
		if raw_postures is Dictionary:
			for raw_posture in (raw_postures as Dictionary).keys():
				var posture := String(raw_posture).to_upper()
				var state_name := String((raw_postures as Dictionary)[raw_posture])
				if posture in ["STANDING", "CROUCHED", "PRONE", "ANY"] and slots.has(state_name):
					posture_states[posture] = state_name
		var family_states: Dictionary = {}
		var raw_families: Variant = raw_route.get("family_states", {})
		if raw_families is Dictionary:
			for raw_family in (raw_families as Dictionary).keys():
				var family_name := String(raw_family).to_upper()
				var raw_family_route: Variant = (raw_families as Dictionary)[raw_family]
				if family_name.is_empty() or not raw_family_route is Dictionary:
					continue
				var family_route := raw_family_route as Dictionary
				var family_default := String(family_route.get("default_state", default_state))
				if not slots.has(family_default):
					continue
				var family_postures: Dictionary = {}
				var raw_family_postures: Variant = family_route.get("posture_states", {})
				if raw_family_postures is Dictionary:
					for raw_posture in (raw_family_postures as Dictionary).keys():
						var posture := String(raw_posture).to_upper()
						var state_name := String((raw_family_postures as Dictionary)[raw_posture])
						if posture in ["STANDING", "CROUCHED", "PRONE", "ANY"] and slots.has(state_name):
							family_postures[posture] = state_name
				family_states[family_name] = {
					"default_state": family_default,
					"posture_states": family_postures,
				}
		var effects: Array[String] = []
		var raw_effects: Variant = raw_route.get("effects", default_effects(event_name))
		if raw_effects is Array:
			for raw_effect in raw_effects:
				var effect_name := String(raw_effect).to_upper()
				if effect_name in VALID_EFFECTS and effect_name not in effects:
					effects.append(effect_name)
		routes[event_name] = {
			"default_state": default_state,
			"posture_states": posture_states,
			"family_states": family_states,
			"return_policy": CURRENT_BASE,
			"interrupt_policy": String(raw_route.get("interrupt_policy", "RESTART")),
			"priority": clampi(int(raw_route.get("priority", 50)), 0, 100),
			"effects": effects,
		}
	return routes


static func default_effects(event_name: String) -> Array[String]:
	if event_name == "FIRE_ACCEPTED":
		return [ENTER_READY_AIM, RAIL_TO_BLUE_LINE]
	if event_name == "WEAPON_EQUIPPED":
		return [APPLY_WEAPON_FAMILY]
	return []


static func resolve_event_state(
	routes: Dictionary,
	event_name: StringName,
	posture: StringName,
	weapon_family: StringName = &""
) -> StringName:
	var raw: Variant = routes.get(String(event_name), {})
	if not raw is Dictionary:
		return &""
	var route := raw as Dictionary
	var posture_key := String(posture).to_upper()
	var family_key := String(weapon_family).to_upper()
	var family_states: Variant = route.get("family_states", {})
	if not family_key.is_empty() and family_states is Dictionary:
		var family_route: Variant = (family_states as Dictionary).get(family_key, {})
		if family_route is Dictionary and not (family_route as Dictionary).is_empty():
			var family_postures: Variant = (family_route as Dictionary).get("posture_states", {})
			if family_postures is Dictionary:
				var family_selected := String(
					(family_postures as Dictionary).get(
						posture_key,
						(family_postures as Dictionary).get("ANY", "")
					)
				)
				if not family_selected.is_empty():
					return StringName(family_selected)
			var family_default := String((family_route as Dictionary).get("default_state", ""))
			if not family_default.is_empty():
				return StringName(family_default)
	var posture_states: Variant = route.get("posture_states", {})
	if posture_states is Dictionary:
		var selected := String(
			(posture_states as Dictionary).get(
				posture_key,
				(posture_states as Dictionary).get("ANY", "")
			)
		)
		if not selected.is_empty():
			return StringName(selected)
	return StringName(route.get("default_state", ""))


static func resolve_event_presentation(
	slots: Dictionary,
	rules: Dictionary,
	routes: Dictionary,
	event_name: StringName,
	posture: StringName,
	weapon_family: StringName = &""
) -> Dictionary:
	var state_name := resolve_event_state(routes, event_name, posture, weapon_family)
	if state_name == &"" or not slots.has(state_name):
		return {}
	var route: Dictionary = routes.get(String(event_name), {})
	var rule := rule_for(rules, state_name)
	return {
		"event": String(event_name),
		"posture": String(posture).to_upper(),
		"weapon_family": String(weapon_family).to_upper(),
		"state": String(state_name),
		"clip_path": String(slots.get(state_name, "")),
		"layer": layer_for(rules, state_name),
		"blend_in_seconds": float(rule.get("blend_in_seconds", 0.12)),
		"blend_out_seconds": float(rule.get("blend_out_seconds", 0.14)),
		"return_state": String(rule.get("return_state", CURRENT_BASE)),
		"return_policy": String(route.get("return_policy", CURRENT_BASE)),
		"interrupt_policy": String(route.get("interrupt_policy", "RESTART")),
		"priority": int(route.get("priority", 50)),
		"effects": (route.get("effects", []) as Array).duplicate(),
	}


static func condition_summary(slot_name: String) -> String:
	if slot_name == "aim_idle":
		return "Weapon is ready and the operator is not moving"
	if _is_fire_state(slot_name):
		return "A valid shot is fired"
	if "reload" in slot_name:
		return "Reload begins for the current posture"
	if slot_name.begins_with("idle_"):
		return "No movement input in this posture"
	if slot_name.begins_with("walk_") or slot_name.begins_with("run_"):
		return "Movement input points " + slot_name.get_slice("_", 1).replace("_", " ")
	if slot_name.begins_with("crouch_"):
		return "Operator is crouched and this movement/action is active"
	if slot_name.begins_with("prone_"):
		return "Operator is prone and this movement/action is active"
	if slot_name.begins_with("jump_"):
		return "Operator is airborne"
	if slot_name in ["dive_roll", "roll"]:
		return "The matching mobility action begins"
	if slot_name.begins_with("start_") or slot_name.begins_with("stop_"):
		return "Movement starts or stops"
	if slot_name.begins_with("turn_"):
		return "A planted aim turn crosses its threshold"
	return "The runtime requests this animation state"


static func state_supports_layer_choice(slot_name: String) -> bool:
	return slot_name == "aim_idle" or _is_fire_state(slot_name) or "reload" in slot_name


static func clip_compatibility_error(
	slot_name: String,
	clip_label: String,
	clip_path: String
) -> String:
	# Designers may deliberately use an idle/aim take for fire because the
	# RAIL_TO_BLUE_LINE effect supplies the visible firing posture. Reject only
	# clips that clearly describe an unrelated locomotion action. This prevents a
	# full-body sprint from being masked onto crouched torso/arms while keeping
	# custom and neutrally named authored clips available.
	var text := (clip_label + " " + clip_path).to_lower()
	var is_fire_slot := _is_fire_state(slot_name)
	var is_reload_slot := "reload" in slot_name
	if not is_fire_slot and not is_reload_slot:
		return ""
	var action_words := (
		["fire", "firing", "shoot", "recoil", "aim", "idle"]
		if is_fire_slot
		else ["reload", "reloading", "magazine"]
	)
	for action_word in action_words:
		if action_word in text:
			return ""
	for locomotion_word in [
		"sprint", "run", "walk", "strafe", "jump", "roll", "dive", "climb",
	]:
		if locomotion_word in text:
			return (
				"%s is a locomotion clip and cannot drive the %s action layer."
				% [clip_label, slot_name]
			)
	return ""


static func rule_for(rules: Dictionary, slot_name: StringName) -> Dictionary:
	var raw: Variant = rules.get(String(slot_name), {})
	return (raw as Dictionary).duplicate(true) if raw is Dictionary else default_rule(String(slot_name))


static func blend_in(rules: Dictionary, slot_name: StringName, fallback: float) -> float:
	return clampf(float(rule_for(rules, slot_name).get("blend_in_seconds", fallback)), 0.0, 1.0)


static func blend_out(rules: Dictionary, slot_name: StringName, fallback: float) -> float:
	return clampf(float(rule_for(rules, slot_name).get("blend_out_seconds", fallback)), 0.0, 1.0)


static func layer_for(rules: Dictionary, slot_name: StringName) -> String:
	return _safe_layer_for_state(
		String(slot_name),
		_valid_layer(String(rule_for(rules, slot_name).get("layer", FULL_BODY)))
	)


static func _valid_layer(layer_name: String) -> String:
	return layer_name if layer_name in VALID_LAYERS else FULL_BODY


static func _safe_layer_for_state(slot_name: String, requested_layer: String) -> String:
	return requested_layer if state_supports_layer_choice(slot_name) else FULL_BODY


static func _is_fire_state(slot_name: String) -> bool:
	return "fire" in slot_name


static func _is_action_state(slot_name: String) -> bool:
	return (
		slot_name == "aim_idle"
		or _is_fire_state(slot_name)
		or "reload" in slot_name
		or "grenade" in slot_name
	)


static func _default_return_state(slot_name: String) -> String:
	if _is_action_state(slot_name):
		return CURRENT_BASE
	if slot_name.begins_with("prone_"):
		return "idle_prone"
	if slot_name.begins_with("crouch_"):
		return "idle_crouch"
	return slot_name
