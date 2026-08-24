class_name GunsmithAnimationQualityAuditor
extends RefCounted

## Owns animation compatibility scoring, catalog filtering, audit state, and
## safe replacement selection. The Gunsmith remains responsible only for
## sampling its live preview rig and presenting the returned report.

var audit_running: bool = false
var autofix_running: bool = false
var last_audit: Dictionary = {}
var previous_slots: Dictionary = {}


func score(trigger_error_cm: float, support_error_cm: float, support_free: bool) -> float:
	var penalty := minf(trigger_error_cm, 20.0) * 10.0
	if not support_free:
		penalty += minf(support_error_cm, 20.0) * 6.0
	return clampf(100.0 - penalty, 0.0, 100.0)


func grade(quality_score: float) -> String:
	if quality_score >= 92.0:
		return "A"
	if quality_score >= 82.0:
		return "B"
	if quality_score >= 68.0:
		return "C"
	if quality_score >= 50.0:
		return "D"
	return "F"


func audit(
	slots: Dictionary,
	slot_order: Array,
	slot_labels: Dictionary,
	measure: Callable,
	progress: Callable = Callable(),
	still_valid: Callable = Callable()
) -> Dictionary:
	if audit_running or not measure.is_valid():
		return {"ok": false, "busy": audit_running, "results": last_audit.duplicate(true)}
	audit_running = true
	last_audit.clear()
	var lines: Array[String] = []
	var cancelled := false
	for raw_slot_name: Variant in slot_order:
		if still_valid.is_valid() and not bool(still_valid.call()):
			cancelled = true
			break
		var slot_name := String(raw_slot_name)
		var clip_name := StringName(slots.get(slot_name, ""))
		var label := String(slot_labels.get(slot_name, slot_name))
		if clip_name == &"":
			lines.append("— %s: missing" % label)
			_emit_progress(progress, lines)
			continue
		var result: Dictionary = await measure.call(slot_name, clip_name)
		last_audit[slot_name] = result.duplicate(true)
		lines.append(_format_result(label, clip_name, result))
		_emit_progress(progress, lines)
	audit_running = false
	return {
		"ok": not cancelled,
		"cancelled": cancelled,
		"results": last_audit.duplicate(true),
		"lines": lines.duplicate(),
	}


func build_autofix(
	slots: Dictionary,
	slot_order: Array,
	slot_labels: Dictionary,
	catalog_paths: Dictionary,
	measure: Callable
) -> Dictionary:
	if autofix_running or audit_running or not measure.is_valid():
		return {"ok": false, "busy": true}
	autofix_running = true
	previous_slots = slots.duplicate(true)
	var updated_slots := slots.duplicate(true)
	var changes: Array[String] = []
	var unresolved: Array[String] = []
	for raw_slot_name: Variant in slot_order:
		var slot_name := String(raw_slot_name)
		var baseline: Dictionary = last_audit.get(slot_name, {})
		var baseline_score := float(baseline.get("score", 0.0))
		if baseline_score >= 82.0:
			continue
		var current_clip := StringName(updated_slots.get(slot_name, ""))
		var best_clip := current_clip
		var best_score := baseline_score
		for candidate: StringName in compatible_candidates(slot_name, catalog_paths):
			if candidate == current_clip:
				continue
			var candidate_result: Dictionary = await measure.call(slot_name, candidate)
			var candidate_score := float(candidate_result.get("score", 0.0))
			if candidate_score > best_score:
				best_score = candidate_score
				best_clip = candidate
		if best_clip != current_clip and best_score >= baseline_score + 8.0:
			updated_slots[slot_name] = String(best_clip)
			changes.append("%s: %s → %s (%.0f → %.0f)" % [
				String(slot_labels.get(slot_name, slot_name)),
				current_clip,
				best_clip,
				baseline_score,
				best_score,
			])
		else:
			unresolved.append(String(slot_labels.get(slot_name, slot_name)))
	autofix_running = false
	return {
		"ok": true,
		"slots": updated_slots,
		"changes": changes,
		"unresolved": unresolved,
	}


func take_previous_slots() -> Dictionary:
	var restored := previous_slots.duplicate(true)
	previous_slots.clear()
	last_audit.clear()
	return restored


func compatible_candidates(slot_name: String, catalog_paths: Dictionary) -> Array[StringName]:
	var result: Array[StringName] = []
	var intent := "idle" if slot_name.begins_with("idle_") else ("reload" if slot_name.begins_with("reload_") else "fire")
	var posture := "prone" if slot_name.ends_with("prone") else ("crouch" if slot_name.ends_with("crouched") else "standing")
	for raw_clip_name: Variant in catalog_paths.keys():
		var clip_name := String(raw_clip_name).to_lower()
		var intent_match := (
			("idle" in clip_name or "aim" in clip_name) if intent == "idle"
			else (("reload" in clip_name) if intent == "reload" else ("fire" in clip_name or "shoot" in clip_name))
		)
		if not intent_match:
			continue
		var has_prone := "prone" in clip_name
		var has_crouch := "crouch" in clip_name or "kneel" in clip_name
		var posture_match := (
			has_prone if posture == "prone"
			else (has_crouch and not has_prone if posture == "crouch" else not has_prone and not has_crouch)
		)
		if posture_match:
			result.append(StringName(raw_clip_name))
	result.sort_custom(func(a: StringName, b: StringName): return String(a).naturalnocasecmp_to(String(b)) < 0)
	if result.size() > 8:
		result.resize(8)
	return result


func _format_result(label: String, clip_name: StringName, result: Dictionary) -> String:
	return "%s %s — %s  trigger %.2f cm  support %s  travel %.1f cm" % [
		String(result.get("grade", "?")),
		label,
		clip_name,
		float(result.get("trigger_error_cm", INF)),
		"FREE" if bool(result.get("support_free", false)) else "%.2f cm" % float(result.get("support_error_cm", INF)),
		float(result.get("weapon_travel_cm", 0.0)),
	]


func _emit_progress(progress: Callable, lines: Array[String]) -> void:
	if progress.is_valid():
		progress.call("\n".join(lines))
