extends "res://tools/retro_1212_reload_regression.gd"

## Observe the canonical driver's evaluated source; never override its pose.
var evaluated_source: Dictionary = {}
var retained_frames := 0
var idle_contact_frames := 0

class SourceObserver extends Node:
	var probe: SceneTree
	func _process(_delta: float) -> void:
		probe.evaluated_source = {
			"action": probe.driver.requested_action,
			"regrip": probe.driver.get("_reload_support_regrip"),
		}


func _install_fixture() -> void:
	super._install_fixture()
	var observer := SourceObserver.new()
	observer.probe = self
	observer.process_priority = 99
	root.add_child(observer)


func _measure_reload(label: String, frame: int) -> void:
	super._measure_reload(label, frame)
	var pose: Node3D = driver.weapon_pose_solver
	var row: Dictionary = reload_rows.back()
	row["evaluated_source"] = evaluated_source.duplicate()
	row["presentation_action"] = pose.last_requested_action
	var source_action := String(evaluated_source.get("action", ""))
	if "reload" in source_action and driver.requested_action == &"":
		retained_frames += 1
		if String(pose.last_requested_action) != source_action or String(pose.weapon_owner) != "RELOAD_RIGHT_HAND":
			_fail_once(label + " final evaluated reload frame lost authored ownership")
		if pose.last_reload_support_regrip != bool(evaluated_source.get("regrip", false)):
			_fail_once(label + " final reload frame changed evaluated support policy")
	if source_action.is_empty() and driver.requested_action == &"" and not label.ends_with("_interrupt_fire"):
		idle_contact_frames += 1
		if String(pose.weapon_owner) == "RELOAD_RIGHT_HAND":
			_fail_once(label + " reload ownership leaked into actual idle source")
		if float(row.physical_support_error_m) > 0.01:
			_fail_once(label + " actual idle-source support palm detached above10mm")
	if label.ends_with("_interrupt_fire") and String(pose.weapon_owner) == "RELOAD_RIGHT_HAND":
		_fail_once(label + " accepted interruption retained reload presentation")


func _finish() -> void:
	if retained_frames != selected_ids.size() * 3 or idle_contact_frames < selected_ids.size() * 3:
		_fail_once("Every posture must exercise exactly one retained source frame and its idle handoff")
	if runtime_sources_at_start != _runtime_source_signatures():
		_fail_once("Runtime changed during evaluated reload source proof")
	print("RELOAD_EVALUATED_SOURCE frames=",retained_frames," idle_contacts=",idle_contact_frames)
	super._finish()
