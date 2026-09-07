extends "res://tools/firearm_family_transition_regression.gd"

## Read-only source/effect proof for PISTOL_MOVING_FIRE_ENTRY_TRANSLATION.md.
## Real accepted shots and canonical input; compares source state immediately
## around the callback and rejects a second mixer evaluation in any one frame.

var timing_rows: Array[Dictionary] = []
var observed_mixers: Array[Dictionary] = []
var observing := false
var playhead_paths: Array[StringName] = []
var lower_bones: Array[int] = []
var signals_bound := false
var diagonal := false

class ReadyMaskSpy extends "res://scripts/player/operator_locomotion_blend_tree.gd":
	var publications := 0
	func publish_accepted_moving_pistol_ready(_posture: StringName, _speed_normalized: float) -> void:
		publications += 1


func _run() -> void:
	_check_publication_guards()
	# This test supplies canonical actions explicitly. Exclude unrelated desktop
	# mouse/keyboard traffic while its native window is open; do not disable the
	# CharacterBody or replace its inputs with visual-only driver values.
	root.set_disable_input(true)
	for action: StringName in InputMap.get_actions():
		InputMap.action_erase_events(action)
	await super._run()


func _check_publication_guards() -> void:
	var isolated: Node = load("res://scripts/player/operator_animation_driver_api.gd").new()
	var spy := ReadyMaskSpy.new()
	isolated.set("locomotion_graph", spy)
	isolated.set("equipped_weapon_handling_profile", {"dynamic_hold": {}})
	var cases := [
		["standing", "TWO_HAND_PISTOL", "STANDING", "LOCOMOTION", "", true, true, 1],
		["crouched", "TWO_HAND_PISTOL", "CROUCHED", "LOCOMOTION", "", true, true, 1],
		["stationary", "TWO_HAND_PISTOL", "STANDING", "LOCOMOTION", "", false, true, 0],
		["prone", "TWO_HAND_PISTOL", "PRONE", "LOCOMOTION", "", true, true, 0],
		["reload", "TWO_HAND_PISTOL", "CROUCHED", "LOCOMOTION", "reload", true, true, 0],
		["dive", "TWO_HAND_PISTOL", "CROUCHED", "DIVING", "", true, true, 0],
		["roll", "TWO_HAND_PISTOL", "CROUCHED", "ROLLING", "", true, true, 0],
		["jump", "TWO_HAND_PISTOL", "STANDING", "AIRBORNE", "", true, true, 0],
		["landing", "TWO_HAND_PISTOL", "STANDING", "LANDING", "", true, true, 0],
		["legacy", "TWO_HAND_PISTOL", "STANDING", "LOCOMOTION", "", true, false, 0],
		["rifle", "TWO_HAND_RIFLE", "STANDING", "LOCOMOTION", "", true, true, 0],
		["long_gun", "LONG_GUN", "CROUCHED", "LOCOMOTION", "", true, true, 0],
	]
	for entry in cases:
		isolated.set("equipped_weapon_family", StringName(entry[1]))
		isolated.set("posture", StringName(entry[2]))
		isolated.set("movement_state", StringName(entry[3]))
		isolated.set("requested_action", StringName(entry[4]))
		isolated.set("_locomotion_active", entry[5])
		isolated.set("use_modern_locomotion", entry[6])
		var before := spy.publications
		isolated.call("_trigger_fire_ready_aim")
		if spy.publications - before != int(entry[7]):
			_fail_once("Accepted-pistol mask guard failed: " + String(entry[0]))
	isolated.free()
	print("PISTOL_ENTRY_GUARDS cases=", cases.size(), " failures=", failures)


func _initialize() -> void:
	selected_ids = ["mark_23"]
	output_prefix = "/private/tmp/pistol-moving-entry-timing"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output-prefix="):
			output_prefix = argument.trim_prefix("--output-prefix=")
		elif argument == "--capture":
			capture = true
		elif argument == "--diagonal":
			diagonal = true
	_run.call_deferred()


func _check_stance(stance: int) -> void:
	_release_inputs()
	player.global_position = Vector3(500, 0.02, 500)
	player.velocity = Vector3.ZERO
	if not bool(player.call("_try_set_posture", stance)):
		_fail_once("Pistol timing posture refused")
		return
	await _frames(110)
	var tree := driver.get("animation_tree") as AnimationTree
	var skeleton := driver.get("skeleton") as Skeleton3D
	if not signals_bound:
		for property in tree.get_property_list():
			var path := StringName(property.name)
			if String(path).ends_with("/current_position"):
				playhead_paths.append(path)
		for bone in ["Hips", "LeftUpLeg", "LeftLeg", "LeftFoot", "RightUpLeg", "RightLeg", "RightFoot"]:
			lower_bones.append(skeleton.find_bone("mixamorig_" + bone))
		tree.mixer_applied.connect(_observe_mixer)
		signals_bound = true
	Input.action_press(&"move_left")
	if diagonal:
		Input.action_press(&"move_forward")
	await _frames(28)
	var label := "standing" if stance == 0 else "crouched"
	_assert_moving(label)
	var graph: RefCounted = driver.get("locomotion_graph")
	var before_events := _event_counts()
	observed_mixers.clear()
	observing = true
	var immediate_before := _mixer_state()
	var shot: Dictionary = controller.call("request_fire")
	var immediate_after := _mixer_state()
	if bool(shot.get("fired", false)):
		await _frames(1)
		first_fire_frame_pending = true
		for entry_frame in 8:
			await _record_transition(label + "_A_fire", 1, true)
			if not transition_rows.is_empty():
				transition_rows[-1]["accepted_entry_frame"] = entry_frame + 1
				transition_rows[-1]["canonical_input"] = "WA" if diagonal else "A"
			if entry_frame in [0, 1, 3, 7]:
				await _capture_state(label + "_A_fire_%02d" % (entry_frame + 1))
	else:
		_fail_once(label + " canonical shot refused")
	observing = false
	var after_events := _event_counts()
	if int(after_events.accepted) != int(before_events.accepted) + 1:
		_fail_once(label + " accepted shot emitted more/less than once")
	for key in ["fire_oneshot", "reload_standing", "reload_crouched"]:
		if after_events[key] != before_events[key]:
			_fail_once(label + " replayed unrelated animation event " + key)
	var repeated_pairs := 0
	var max_phase_delta := 0.0
	var max_lower_rotation_delta := 0.0
	var max_lower_position_delta := 0.0
	for path: StringName in playhead_paths:
		max_phase_delta = maxf(max_phase_delta, absf(float(immediate_after.playheads[path]) - float(immediate_before.playheads[path])))
	for index_bone in lower_bones.size():
		var before_transform: Transform3D = immediate_before.lower_body[index_bone]
		var after_transform: Transform3D = immediate_after.lower_body[index_bone]
		# Exact equality avoids acos numerical noise near an identical quaternion.
		if before_transform != after_transform:
			max_lower_rotation_delta = maxf(max_lower_rotation_delta, rad_to_deg(before_transform.basis.get_rotation_quaternion().angle_to(after_transform.basis.get_rotation_quaternion())))
			max_lower_position_delta = maxf(max_lower_position_delta, before_transform.origin.distance_to(after_transform.origin))
	for key: String in ["shared_phase", "smoothed_direction", "rendered_direction", "full_gait_weight", "playback_rate", "modern_state"]:
		if immediate_before.graph[key] != immediate_after.graph[key]:
			_fail_once(label + " accepted callback changed protected graph field " + key)
	for index in range(1, observed_mixers.size()):
		var previous: Dictionary = observed_mixers[index - 1]
		var current: Dictionary = observed_mixers[index]
		if previous.process_frame != current.process_frame:
			continue
		repeated_pairs += 1
	if repeated_pairs != 0:
		_fail_once(label + " accepted entry caused a second source evaluation; got " + str(repeated_pairs))
	if playhead_paths.is_empty() or max_phase_delta > 0.000001:
		_fail_once(label + " accepted callback altered a source playhead")
	if max_lower_rotation_delta > 0.05 or max_lower_position_delta > 0.00001:
		_fail_once(label + " accepted callback changed evaluated hips/legs")
	var timing := {
		"stance": label, "same_frame_refreshes": repeated_pairs,
		"canonical_input": "WA" if diagonal else "A",
		"source_playheads": playhead_paths.size(), "max_playhead_delta_seconds": max_phase_delta,
		"max_lower_rotation_delta_degrees": max_lower_rotation_delta,
		"max_lower_position_delta_m": max_lower_position_delta,
		"before_events": before_events, "after_events": after_events,
		"accepted_recovery_hold_seconds": driver.get("fire_ready_hold_seconds"),
		"graph_ready_mask": graph.get("upper_body_ready_blend"),
	}
	timing_rows.append(timing)
	print("PISTOL_ENTRY_TIMING ", JSON.stringify(timing))
	_release_inputs()
	await _frames(110)


func _observe_mixer() -> void:
	if not observing:
		return
	observed_mixers.append(_mixer_state())


func _mixer_state() -> Dictionary:
	var tree := driver.get("animation_tree") as AnimationTree
	var skeleton := driver.get("skeleton") as Skeleton3D
	var times := {}
	for path in playhead_paths:
		times[path] = tree.get(path)
	var bones: Array[Transform3D] = []
	for index in lower_bones:
		bones.append(skeleton.get_bone_pose(index))
	return {"process_frame": Engine.get_process_frames(), "playheads": times, "lower_body": bones, "graph": driver.get("locomotion_graph").get_debug_state()}


func _event_counts() -> Dictionary:
	var debug: Dictionary = driver.call("get_animation_debug_state")
	var graph: RefCounted = driver.get("locomotion_graph")
	return {
		"accepted": debug.get("fire_upper_body_latch", {}).get("accepted_shot_count", 0),
		"fire_oneshot": graph.get("fire_trigger_count"),
		"reload_standing": graph.get("standing_reload_trigger_count"),
		"reload_crouched": graph.get("crouched_reload_trigger_count"),
	}


func _finish() -> void:
	var output := FileAccess.open(output_prefix + "-timing.json", FileAccess.WRITE)
	if output:
		output.store_string(JSON.stringify({"timing": timing_rows, "failures": failures}, "\t"))
		output.close()
	super._finish()
