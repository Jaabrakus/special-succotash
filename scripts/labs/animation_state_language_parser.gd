@tool
class_name SocomAnimationStateLanguageParser
extends RefCounted

## Converts a small, reviewable command vocabulary into animation-state data.
## It never writes files or changes gameplay code.

const GameplayDictionary := preload(
	"res://scripts/runtime/gameplay_event_dictionary.gd"
)


func propose(command: String, selected_state: String) -> Dictionary:
	var normalized := command.strip_edges().to_lower()
	if normalized.is_empty():
		return {"valid": false, "message": "Describe when the selected animation should play."}
	var event_name := _event_from_text(normalized)
	if event_name.is_empty():
		return {
			"valid": false,
			"message": "Name an event such as fire, reload, jump, grenade, hit, or death.",
		}
	var layer := "FULL_BODY"
	if (
		"torso" in normalized
		or "upper body" in normalized
		or "arms" in normalized
		or "shoulders" in normalized
	):
		layer = "UPPER_BODY"
	var blend_in := _seconds_after(normalized, "blend\\s+in(?:\\s+over)?", 0.12)
	var blend_out := _seconds_after(normalized, "blend\\s+(?:back\\s+)?out(?:\\s+over)?", 0.14)
	var postures: Array[String] = []
	for posture in ["STANDING", "CROUCHED", "PRONE"]:
		if String(posture).to_lower() in normalized:
			postures.append(posture)
	if postures.is_empty():
		postures = ["STANDING", "CROUCHED", "PRONE"]
	return {
		"valid": true,
		"event": event_name,
		"state": selected_state,
		"layer": layer,
		"blend_in_seconds": blend_in,
		"blend_out_seconds": blend_out,
		"return_policy": "CURRENT_BASE",
		"postures": postures,
		"message": "%s → %s → %s → current movement/stance" % [
			event_name,
			selected_state,
			"torso + arms" if layer == "UPPER_BODY" else "whole body",
		],
	}


func _event_from_text(text: String) -> String:
	return GameplayDictionary.event_from_text(text)


func _seconds_after(text: String, prefix_pattern: String, fallback: float) -> float:
	var expression := RegEx.new()
	if expression.compile("%s\\s+([0-9]*\\.?[0-9]+)" % prefix_pattern) != OK:
		return fallback
	var found := expression.search(text)
	if found == null:
		return fallback
	return clampf(float(found.get_string(1)), 0.0, 1.0)
