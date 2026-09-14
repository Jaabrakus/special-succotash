extends "res://tools/main_source_motion_proof.gd"

var checks := 0
var frozen_frames := 0
var frozen_keys: Array = []
var observed_freezes := 0
var observed_releases := 0
var captured_stages: Dictionary = {}
var snapshot_rows: Array[Dictionary] = []

func _initialize() -> void:
	weapon_id = "m4a1"
	output_prefix = "/private/tmp/source-transition-snapshot-main"
	super._initialize()

func _run() -> void:
	if capture and DisplayServer.get_name() == "headless":
		failures.append("--capture requires a display-backed run")
		_finish()
		return
	ProjectSettings.set_setting("socom/session/public_training", true)
	await super._run()

func _request_shot() -> bool:
	# Grounded snapshot eligibility explicitly excludes accepted-shot overlays.
	return false

func _sample(state: String) -> void:
	var requested := capture
	capture = capture and state.begins_with("snapshot_")
	await super._sample(state)
	capture = requested

func _command(direction: Vector2) -> void:
	await super._command(direction)
	var graph: RefCounted = driver.locomotion_graph
	var snapshot: RefCounted = graph.source_transition_snapshot
	_check(snapshot.enabled, "saved native rifle snapshot policy active in main")
	observed_releases = maxi(observed_releases, snapshot.releases)
	if snapshot.frozen_state == &"": return
	frozen_frames += 1
	var animation: Animation = snapshot.animations[snapshot.frozen_state]
	var keys: Array = []
	for track in animation.get_track_count(): keys.append(animation.track_get_key_value(track, 0))
	if observed_freezes != snapshot.freezes:
		observed_freezes = snapshot.freezes
		frozen_keys = keys
	else:
		_check(keys == frozen_keys, "private outgoing keys remain constant throughout fade")
	_check(snapshot.frozen_state in [&"standing", &"idle", &"crouch", &"idle_crouch"], "only grounded sources frozen")
	_check(snapshot.target_state in [&"idle", &"idle_crouch"], "only verified idle destinations frozen")
	_check(driver.requested_action == &"" and player.is_on_floor(), "grounded action-free body owns movement")
	var pose := _measure_physical_pose()
	_check(float(pose.trigger_contact_m) < .015 and float(pose.support_contact_m) < .015, "normal weapon owner preserves hand contacts")
	var remaining := float(driver.animation_tree.get("parameters/modern_transition/prev_xfading"))
	# The exposed timer has already been decremented; label the pose actually
	# evaluated, not the next frame's blend. Capture delays make this observable.
	var evaluated_states: Array[StringName] = [snapshot.target_state]
	var evaluated_weight: float = graph.evaluated_modern_state_weight(
		evaluated_states, driver.animation_tree.get_process_delta_time())
	var row := {"frame":Engine.get_process_frames(), "from":snapshot.frozen_state, "to":snapshot.target_state,
		"freeze":snapshot.freezes, "remaining":remaining, "evaluated_target_weight":evaluated_weight, "root":str(snapshot.root_source),
		"frozen_root":str(animation.track_get_key_value(snapshot.positions.size() * 3, 0)),
		"body":str(player.global_position), "trigger_m":pose.trigger_contact_m, "support_m":pose.support_contact_m}
	snapshot_rows.append(row)
	# First real stop only: six images for early/middle/late, two views each.
	if snapshot.freezes == 1 and StringName(driver.animation_tree.get("parameters/modern_transition/current_state")) == snapshot.target_state:
		var stage := "early" if evaluated_weight < .1 else ("middle" if evaluated_weight >= .35 and evaluated_weight <= .7 else ("late" if evaluated_weight >= .85 else ""))
		if stage != "" and not captured_stages.has(stage):
			captured_stages[stage] = true
			await _sample("snapshot_" + stage)
			if not samples.is_empty(): samples[-1]["snapshot_evaluated_target_weight"] = evaluated_weight

func _extra_actions() -> void:
	var snapshot: RefCounted = driver.locomotion_graph.source_transition_snapshot
	_check(observed_freezes >= 3 and frozen_frames >= 30, "actual input stops exercised repeated source snapshots")
	_check(snapshot.frozen_state == &"" and snapshot.releases == snapshot.freezes, "all main stop snapshots completed and released")
	_check(captured_stages.size() == 3, "actual fade early/middle/late sampled")
	var before: int = snapshot.freezes
	_check(super._request_shot(), "real shot accepted for exclusion check")
	await _frames(2)
	_check(not driver.locomotion_graph._source_snapshot_safe() and not snapshot.latest_valid, "accepted fire suppresses snapshot capture")
	_check(snapshot.freezes == before, "shot cannot create a snapshot")
	var old_graph: WeakRef = weakref(driver.locomotion_graph)
	var old_snapshot: WeakRef = weakref(snapshot)
	snapshot = null
	_check(controller.apply_authorized_weapon_pickup("res://config/weapons/mark_23.json"), "canonical pistol equip")
	await _frames(35)
	_check(not driver.locomotion_graph.source_transition_snapshot.enabled, "pistol graph retains fallback")
	_check(not driver.animation_player.has_animation_library(&"source_transition_snapshot"), "pistol rebuild removes previous private snapshot library")
	_check(old_graph.get_ref() == null and old_snapshot.get_ref() == null, "rebuilt graph and snapshot do not retain a callable ownership cycle")
	var file := FileAccess.open(output_prefix + "-snapshot.json", FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify({"checks":checks, "frames":frozen_frames, "freezes":observed_freezes, "failures":failures, "rows":snapshot_rows}, "\t"))
	else: _check(false, "snapshot report writable")
	print("SOURCE_TRANSITION_SNAPSHOT_MAIN ", "PASS" if failures.is_empty() else "FAIL", " checks=", checks, " frozen_frames=", frozen_frames, " freezes=", observed_freezes, " releases=", observed_releases, " ", failures)

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok and not failures.has(label):
		failures.append(label)
		push_error("SOURCE_TRANSITION_SNAPSHOT_MAIN " + label)
