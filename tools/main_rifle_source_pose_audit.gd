extends "res://tools/main_source_motion_proof.gd"

## Translation card: audit native rifle movement in main without promoting an
## unsafe global switch. Owner: this observer/test. Protected: every runtime,
## asset, camera, movement and weapon timing writer. Proof: same commanded main
## routes, same-frame before/after pose samples and measured weapon geometry.
## MERGE existing main proof with provenance/pose observations; no new solver.
## --require-source-only checks source preservation. --require-combat-alignment
## additionally fails on settled fire grip/bore errors. These are separate gates.

class BeforePresentation extends Node:
	var driver: Node
	var frame := -1
	var poses: Array[Transform3D] = []
	func _process(_delta: float) -> void:
		poses.clear()
		for index in driver.skeleton.get_bone_count():
			poses.append(driver.skeleton.get_bone_global_pose(index))
		frame = Engine.get_process_frames()

var observer: BeforePresentation
var require_source := false
var require_combat := false
var candidate_output := ""
var candidate_native_attachment := false
var short_cardinals := false
var finished := false
var combat_failures: Array[String] = []
var states: Dictionary = {}
var routes: Array[Dictionary] = []
var accepted_shots := 0
var accepted_reloads := 0
var last_shot_frame := -1
var source_samples := 0
var maximum_post_tree_position_m := 0.0
var maximum_post_tree_basis_delta := 0.0
var checked_frames := 0
var source_profile_path := "res://config/operator_animation_map.json"


func _initialize() -> void:
	weapon_id = "m4a1"
	output_prefix = "/private/tmp/main-rifle-source-pose"
	for argument in OS.get_cmdline_user_args():
		if argument == "--require-source-only": require_source = true
		if argument == "--require-combat-alignment": require_combat = true
		if argument.begins_with("--profile="): source_profile_path = argument.trim_prefix("--profile=")
		if argument.begins_with("--write-toggle-candidate="): candidate_output = argument.trim_prefix("--write-toggle-candidate=")
		if argument.begins_with("--write-rifle-attachment-candidate="):
			candidate_output = argument.trim_prefix("--write-rifle-attachment-candidate=")
			candidate_native_attachment = true
		if argument == "--short-fire-cardinals": short_cardinals = true
	super._initialize()


func _run() -> void:
	if not candidate_output.is_empty():
		if not candidate_output.begins_with("/private/tmp/"):
			push_error("Candidate output must be an explicitly named /private/tmp/ JSON file")
			quit(1)
			return
		var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://config/operator_animation_map.json"))
		if candidate_native_attachment:
			data.locomotion["source_rifle_attachment"] = true
			data.locomotion["source_rifle_aim_limit_degrees"] = 85.0
		else:
			data.locomotion["source_pose_only"] = true
		var output := FileAccess.open(candidate_output, FileAccess.WRITE)
		if output == null:
			quit(1)
			return
		output.store_string(JSON.stringify(data, "\t"))
		output.close()
		print("RIFLE_SOURCE_CANDIDATE ", candidate_output, " (", "native rifle attachment" if candidate_native_attachment else "global source_pose_only", "; not activated)")
		quit(0)
		return
	if weapon_id not in ["m4a1", "ak-47"]:
		failures.append("Rifle audit is limited to M4A1 and AK47")
		_finish()
		return
	if capture and DisplayServer.get_name() == "headless":
		failures.append("Capture requires a display-backed run")
		_finish()
		return
	await super._run()


func _install_fixture() -> void:
	super._install_fixture()
	observer = BeforePresentation.new()
	observer.driver = driver
	observer.process_priority = 99
	scene.add_child(observer)


func _request_shot() -> bool:
	var accepted := super._request_shot()
	if accepted:
		accepted_shots += 1
		last_shot_frame = Engine.get_physics_frames()
	return accepted


func _check_frame(label: String, firing_sample: bool) -> void:
	var geometry := _measure_physical_pose()
	if geometry.is_empty():
		_check(false, "Physical rifle geometry exists")
		return
	var state: Dictionary = states.get(label, {"frames": 0, "trigger_max_m": 0.0,
		"support_max_m": 0.0, "barrel_max_degrees": 0.0, "settled_barrel_max_degrees": 0.0,
		"post_tree_position_max_m": 0.0, "post_tree_basis_max_delta": 0.0})
	state.frames += 1
	state.trigger_max_m = maxf(state.trigger_max_m, float(geometry.trigger_contact_m))
	maximum_grip_error = maxf(maximum_grip_error, float(geometry.trigger_contact_m))
	state.support_max_m = maxf(state.support_max_m, float(geometry.support_contact_m))
	state.barrel_max_degrees = maxf(state.barrel_max_degrees, float(geometry.bore_to_reticle_degrees))
	_check(is_finite(float(geometry.trigger_contact_m)) and is_finite(float(geometry.bore_to_reticle_degrees)), "Finite rifle contact/bore: " + label)
	_check(float(geometry.trigger_contact_m) <= 0.015, "Right trigger attachment <=1.5cm: " + label)
	_check(player.is_on_floor(), "Body remains grounded: " + label)
	if require_source:
		_check(bool(driver.source_pose_only), "Source-only policy active")
		_check(not driver.weapon_pose_solver.left_hand_ik.is_running() and not driver.weapon_pose_solver.right_hand_ik.is_running(), "Source arm IK stopped")
	var skeleton: Skeleton3D = driver.skeleton
	# SceneTree.process_frame can resume this coroutine before node _process.
	# Then both poses belong to the last completed presentation pass, not the
	# just-announced frame. Reject an older/stale observer either way.
	_check(Engine.get_process_frames() - observer.frame in [0, 1], "Recent pre/post presentation observer pair exists")
	for index in skeleton.get_bone_count():
		var after := skeleton.get_bone_global_pose(index)
		_check(after.origin.is_finite() and after.basis.x.is_finite() and after.basis.y.is_finite() and after.basis.z.is_finite(), "Finite bone: " + skeleton.get_bone_name(index))
		if observer.poses.size() != skeleton.get_bone_count(): continue
		var before: Transform3D = observer.poses[index]
		var displacement := (skeleton.global_basis * (after.origin - before.origin)).length()
		state.post_tree_position_max_m = maxf(state.post_tree_position_max_m, displacement)
		for axis in 3:
			state.post_tree_basis_max_delta = maxf(state.post_tree_basis_max_delta, after.basis[axis].distance_to(before.basis[axis]))
	maximum_post_tree_position_m = maxf(maximum_post_tree_position_m, state.post_tree_position_max_m)
	maximum_post_tree_basis_delta = maxf(maximum_post_tree_basis_delta, state.post_tree_basis_max_delta)
	if require_source:
		_check(state.post_tree_position_max_m < 0.001, "Source body translation preserved: " + label)
		_check(state.post_tree_basis_max_delta < 0.001, "Source body rotation preserved: " + label)
	if firing_sample and last_shot_frame >= 0 and Engine.get_physics_frames() - last_shot_frame >= 20:
		state.settled_barrel_max_degrees = maxf(state.settled_barrel_max_degrees, float(geometry.bore_to_reticle_degrees))
		_combat_check(float(geometry.bore_to_reticle_degrees) <= 6.0, "Settled rifle bore >6deg: " + label)
		_combat_check(float(geometry.support_contact_m) <= 0.03, "Settled rifle support gap >3cm: " + label)
	states[label] = state
	checked_frames += 1


func _sample(label: String) -> void:
	if short_cardinals and not (label.begins_with(weapon_id + "_standing_move_") and label.ends_with("_fire_20")):
		return
	await super._sample(label)
	var row: Dictionary = samples.back()
	row["source_pose_only"] = driver.source_pose_only
	row["source_pistol_attachment"] = driver.source_pistol_attachment
	row["source_rifle_attachment"] = driver.get("source_rifle_attachment")
	row["actual_character_path"] = driver.model_root.scene_file_path
	row["logical_source_metadata"] = _metadata(StringName(row.current_clip))
	row["source_only_is_not_original_engine_parity"] = true
	if routes.is_empty():
		for prefix in ["walk", "run", "crouch"]:
			for direction in ["forward", "backward", "left", "right"]:
				for firing_route in [false, true]:
					var slot: String = prefix + "_" + direction
					var clip: StringName = driver.locomotion_graph._weapon_locomotion_clip(slot, &"run_forward", driver.available_clips, firing_route)
					routes.append({"slot": slot, "firing": firing_route, "metadata": _metadata(clip)})
	if short_cardinals and label.ends_with("_right_fire_20"):
		_finish()


func _metadata(clip: StringName) -> Dictionary:
	var animation: Animation = driver.animation_player.get_animation(clip) if driver.animation_player.has_animation(clip) else null
	var source := String(animation.get_meta("source_name", "")) if animation != null else ""
	if source.begins_with("seal_"): source_samples += 1
	return {"clip": String(clip), "path": String(driver.clip_paths.get(clip, "")),
		"source_name": source, "source_sha256": animation.get_meta("source_sha256", "") if animation != null else "",
		"seal_reference": animation.get_meta("seal_reference", false) if animation != null else false,
		"note": "Resolved resource provenance, not proof that the final mixed pose equals this one clip."}


func _extra_actions() -> void:
	player.call("_try_set_posture", 0)
	for frame in 40: await _command(Vector2.ZERO)
	if _request_shot():
		for frame in 30:
			await _command(Vector2.ZERO)
			_check_frame("standing_idle_fire", true)
			if frame in [1, 8, 24]: await _sample("standing_idle_fire_" + str(frame))
	for frame in 100: await _command(Vector2.ZERO)
	var before: Dictionary = controller.get_ammo_snapshot()
	var coordinator: Node = scene.get_node("WeaponReloadCoordinator")
	var accepted := bool(coordinator.request_reload())
	_check(accepted, "Canonical rifle reload accepted")
	if accepted:
		accepted_reloads += 1
		var duration := float(driver.weapon_reload_duration_seconds())
		for frame in ceili(duration * Engine.physics_ticks_per_second) + 45:
			await _command(Vector2.ZERO)
			_check_frame("standing_reload", false)
			if frame in [6, ceili(duration * 30.0), ceili(duration * 60.0) - 5]: await _sample("standing_reload_" + str(frame))
		_check(not coordinator.pending, "Reload completes")
		var after: Dictionary = controller.get_ammo_snapshot()
		_check(int(after.rounds_in_magazine) > int(before.rounds_in_magazine), "Reload commits ammo")
	await _sample("standing_reload_return")


func _check(ok: bool, message: String) -> void:
	if not ok and message not in failures: failures.append(message)


func _combat_check(ok: bool, message: String) -> void:
	if not ok and message not in combat_failures: combat_failures.append(message)
	if require_combat: _check(ok, message)


func _finish() -> void:
	if finished: return
	finished = true
	_check(checked_frames >= (210 if short_cardinals else 432), "Real commanded rifle frames checked")
	var report := {"canonical_scene": "res://main.tscn", "weapon": weapon_id,
		"profile": source_profile_path, "profile_sha256": FileAccess.get_sha256(source_profile_path),
		"require_source_only": require_source, "require_combat_alignment": require_combat,
		"scope": "standing forward/left/right late fire only" if short_cardinals else "standing/crouched movement, fire and standing reload",
		"checked_frames": checked_frames, "accepted_shots": accepted_shots, "accepted_reloads": accepted_reloads,
		"maximum_post_tree_position_m": maximum_post_tree_position_m,
		"maximum_post_tree_basis_delta": maximum_post_tree_basis_delta,
		"states": states, "routes": routes, "samples": samples,
		"combat_failures": combat_failures, "failures": failures, "pass": failures.is_empty(),
		"safe_for_gameplay_promotion": failures.is_empty() and combat_failures.is_empty(),
		"note": "Pose preservation and rifle aiming/contact are separate gates. This observer measures post-tree changes, not original EE engine composition or original timing. No global switch is promoted by running this tool."}
	DirAccess.make_dir_recursive_absolute(output_prefix.get_base_dir())
	var output := FileAccess.open(output_prefix + ".json", FileAccess.WRITE)
	if output != null:
		output.store_string(JSON.stringify(report, "\t"))
		output.close()
	else: _check(false, "Cannot save rifle audit")
	print("MAIN_RIFLE_SOURCE_AUDIT ", "PASS" if failures.is_empty() else "FAIL", " safety=", combat_failures, " ", output_prefix)
	if scene != null: scene.queue_free()
	quit(0 if failures.is_empty() else 1)
