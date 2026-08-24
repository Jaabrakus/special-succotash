@tool
class_name SocomOperatorPresentationRouter
extends RefCounted

## The one data-only entry point for character presentation decisions.
## Gameplay remains authoritative and sends only accepted semantic events.
## Animation Studio and the playable runtime both resolve those events here.

const StateContract := preload("res://scripts/player/operator_animation_state_contract.gd")

var slots: Dictionary = {}
var rules: Dictionary = {}
var routes: Dictionary = {}


func configure(
	next_slots: Dictionary,
	next_rules: Dictionary,
	next_routes: Dictionary
) -> void:
	slots = next_slots.duplicate(true)
	rules = StateContract.normalized_rules(slots, next_rules)
	routes = StateContract.normalized_event_routes(slots, next_routes)


func resolve(event_name: StringName, context: Dictionary = {}) -> Dictionary:
	var posture := StringName(String(context.get("posture", "STANDING")).to_upper())
	var weapon_family := StringName(
		String(context.get("weapon_family", "")).to_upper()
	)
	var plan := StateContract.resolve_event_presentation(
		slots,
		rules,
		routes,
		event_name,
		posture,
		weapon_family
	)
	if plan.is_empty():
		return {
			"valid": false,
			"event": String(event_name),
			"posture": String(posture),
			"weapon_family": String(weapon_family),
			"error": "No presentation route is connected for this context.",
			"source": "operator_presentation_router",
		}
	var current_base := String(context.get("current_base_state", ""))
	var return_policy := String(plan.get("return_policy", StateContract.CURRENT_BASE))
	plan["valid"] = true
	plan["source"] = "operator_presentation_router"
	plan["context"] = context.duplicate(true)
	plan["resolved_return_state"] = (
		current_base
		if return_policy == StateContract.CURRENT_BASE
		else String(plan.get("return_state", current_base))
	)
	plan["trace"] = _build_trace(plan)
	return plan


func present(
	event_name: StringName,
	context: Dictionary = {},
	consumer: Callable = Callable()
) -> Dictionary:
	var plan := resolve(event_name, context)
	plan["applied"] = false
	if bool(plan.get("valid", false)) and consumer.is_valid():
		plan["applied"] = bool(consumer.call(plan))
	return plan


func describe(plan: Dictionary) -> String:
	if not bool(plan.get("valid", false)):
		return "%s — NOT CONNECTED\n%s" % [
			String(plan.get("event", "EVENT")),
			String(plan.get("error", "No presentation route.")),
		]
	var effects: Array = plan.get("effects", [])
	var effect_text := "none" if effects.is_empty() else ", ".join(effects)
	var family := String(plan.get("weapon_family", "ANY"))
	if family.is_empty():
		family = "ANY WEAPON"
	return (
		"%s\n%s + %s\n↓\n%s → %s\n%s • %.2fs in / %.2fs out\n"
		+ "↓ %s\nEffects: %s"
	) % [
		String(plan.get("event", "EVENT")),
		family,
		String(plan.get("posture", "STANDING")),
		String(plan.get("state", "UNMAPPED")),
		String(plan.get("clip_path", "")).get_file(),
		String(plan.get("layer", StateContract.FULL_BODY)).replace("_", " "),
		float(plan.get("blend_in_seconds", 0.0)),
		float(plan.get("blend_out_seconds", 0.0)),
		String(plan.get("resolved_return_state", "CURRENT MOVEMENT")),
		effect_text,
	]


func _build_trace(plan: Dictionary) -> Array[String]:
	var result: Array[String] = [
		String(plan.get("event", "")),
		"%s / %s" % [
			String(plan.get("weapon_family", "ANY")),
			String(plan.get("posture", "STANDING")),
		],
		String(plan.get("state", "")),
		String(plan.get("clip_path", "")).get_file(),
		String(plan.get("layer", StateContract.FULL_BODY)),
		String(plan.get("resolved_return_state", "")),
	]
	return result
