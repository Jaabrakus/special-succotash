extends "res://tools/main_source_motion_proof.gd"

## Translation card: prove the selected character's source-pistol attachment in
## main.tscn through commanded movement, accepted shots and committed reloads.
## Owner: this read-only regression; the existing body/weapon/animation owners
## execute actions. No saved profile, asset, gameplay timing or camera edit.
## Acceptance: trigger <= 0.015 m, finite poses, explicit source-pistol policy,
## no legacy upper layer, stopped arm IK under that policy; optional real renders.
## System delta MERGE: retain the inherited input-driven main-scene proof and add
## pistol-specific contact, provenance and reload coverage. Numerical contact is
## not proof of original-game visual parity or a verified original aiming equation.
## Run without --automated-test. --capture [--hands-closeup] needs a display.

const CHARACTER_PROFILE := "res://config/operator_character.json"
const TRIGGER_LIMIT_M := 0.015
const SETTLED_FIRE_FRAMES := 20
const Weapons := preload("res://scripts/weapons/weapon_rig_contract.gd")

var checked_frames := 0
var last_checked_frame := -1
var accepted_shots := 0
var accepted_reloads := 0
var committed_reloads := 0
var last_shot_frame := -1
var settled_aim_checked_frames := 0
var aim_limited_frames := 0
var maximum_barrel_error_degrees := 0.0
var maximum_settled_barrel_error_degrees := 0.0
var minimum_native_wrist_gap_m := INF
var maximum_native_wrist_gap_m := 0.0
var character_provenance: Dictionary = {}
var reloads: Array[Dictionary] = []
var clip_provenance_cache: Dictionary = {}
var pistol_routing: Array[Dictionary] = []


func _initialize() -> void:
	weapon_id = "mark_23"
	output_prefix = "/private/tmp/main-pistol-source-attachment"
	super._initialize()


func _run() -> void:
	if weapon_id != "mark_23" or require_shoulder_lock:
		_expect(false, "This probe covers Mark23 source attachment, not rifle shoulder locking")
		_finish()
		return
	if capture and DisplayServer.get_name() == "headless":
		_expect(false, "--capture requires a display-backed run")
		_finish()
		return
	await super._run()


func _request_shot() -> bool:
	var accepted := super._request_shot()
	if accepted:
		accepted_shots += 1
		last_shot_frame = Engine.get_physics_frames()
	return accepted


func _check_frame(label: String, firing_sample: bool) -> void:
	var measured := _measure_physical_pose()
	var first_check_this_frame := last_checked_frame != Engine.get_physics_frames()
	_expect(not measured.is_empty(), "Physical pistol measurements exist: " + label)
	if measured.is_empty():
		return
	var solver: Node = driver.weapon_pose_solver
	var source_mode := bool(driver.get("source_pistol_attachment"))
	_expect(source_mode and bool(solver.get("source_pistol_attachment")), "Source-pistol attachment policy is active")
	_expect(bool(driver.get("source_pose_only")), "Pistol source-pose presentation path is active")
	_expect(not driver.locomotion_graph.PistolUpperLayer.enabled(driver.locomotion_graph), "Legacy pistol upper policy is disabled")
	_expect(not driver.animation_tree.tree_root.has_node(&"legacy_pistol_upper"), "Legacy pistol upper graph is absent")
	# Do not impose this on other weapon families: only this explicit pistol
	# policy promises source arms without independent left/right socket IK.
	if source_mode:
		_expect(not _ik_running(solver.get("left_hand_ik")) and not _ik_running(solver.get("right_hand_ik")), "Source-pistol arm IK is stopped")
	var trigger := float(measured.get("trigger_contact_m", INF))
	_expect(is_finite(trigger) and trigger <= TRIGGER_LIMIT_M, "Trigger contact exceeds 1.5 cm: " + label)
	if is_finite(trigger):
		maximum_grip_error = maxf(maximum_grip_error, trigger)
	_expect(player.is_on_floor(), "CharacterBody remains grounded: " + label)
	_expect(_finite_transform(player.global_transform), "Player transform is finite")
	_expect(_finite_transform(driver.model_root.global_transform), "Selected character transform is finite")
	_expect(_finite_transform(driver.weapon_node.global_transform), "Equipped pistol transform is finite")
	var skeleton: Skeleton3D = driver.skeleton
	for index in skeleton.get_bone_count():
		_expect(_finite_transform(skeleton.get_bone_global_pose(index)), "Finite bone pose: " + skeleton.get_bone_name(index))
	var hands := _hand_measurements()
	_expect(bool(hands.get("finite", false)), "Native wrist/palm measurements are finite")
	var gap := float(hands.get("native_pose_runtime_wrist_gap_m", NAN))
	if is_finite(gap):
		minimum_native_wrist_gap_m = minf(minimum_native_wrist_gap_m, gap)
		maximum_native_wrist_gap_m = maxf(maximum_native_wrist_gap_m, gap)
	var bore := float(measured.get("bore_to_reticle_degrees", NAN))
	_expect(is_finite(bore), "Measured barrel-to-reticle angle is finite")
	if is_finite(bore):
		maximum_barrel_error_degrees = maxf(maximum_barrel_error_degrees, bore)
	var applied := absf(float(solver.get("source_pistol_aim_applied_degrees")))
	var limit := float(solver.get("source_pistol_aim_limit_degrees"))
	_expect(is_finite(applied) and is_finite(limit), "Source-pistol aim diagnostics are finite")
	if firing_sample and last_shot_frame >= 0 and Engine.get_physics_frames() - last_shot_frame >= SETTLED_FIRE_FRAMES:
		if applied < limit - 0.25:
			if first_check_this_frame:
				settled_aim_checked_frames += 1
			maximum_settled_barrel_error_degrees = maxf(maximum_settled_barrel_error_degrees, bore)
			_expect(is_finite(bore) and bore <= 6.0, "Unclamped settled firing bore exceeds 6 degrees: " + label)
		else:
			if first_check_this_frame:
				aim_limited_frames += 1
	if first_check_this_frame:
		checked_frames += 1
		last_checked_frame = Engine.get_physics_frames()


func _sample(state: String) -> void:
	_check_frame(state, state.contains("_fire_"))
	await super._sample(state)
	var row: Dictionary = samples.back()
	var solver: Node = driver.weapon_pose_solver
	var debug: Dictionary = driver.get_animation_debug_state()
	if character_provenance.is_empty():
		var selected: Variant = JSON.parse_string(FileAccess.get_file_as_string(CHARACTER_PROFILE))
		var actual_path := String(driver.model_root.scene_file_path)
		var selected_path := String(selected.get("scene", "")) if selected is Dictionary else ""
		character_provenance = {
			"selection_profile": CHARACTER_PROFILE,
			"selection_profile_sha256": FileAccess.get_sha256(CHARACTER_PROFILE),
			"selected_character_path": selected_path,
			"actual_character_path": actual_path,
			"actual_character_sha256": FileAccess.get_sha256(actual_path) if FileAccess.file_exists(actual_path) else "",
			"skeleton_node": String(driver.skeleton.get_path()),
			"bone_count": driver.skeleton.get_bone_count(),
		}
		_expect(not actual_path.is_empty() and actual_path == selected_path, "Actual rendered character matches the saved selection")
		_expect(not String(character_provenance.actual_character_sha256).is_empty(), "Selected character content hash is available")
	row["character"] = character_provenance
	row["source_pistol_attachment"] = bool(driver.get("source_pistol_attachment"))
	row["source_pose_only"] = bool(driver.get("source_pose_only"))
	row["legacy_upper_enabled"] = driver.locomotion_graph.PistolUpperLayer.enabled(driver.locomotion_graph)
	row["left_arm_ik_running"] = _ik_running(solver.get("left_hand_ik"))
	row["right_arm_ik_running"] = _ik_running(solver.get("right_hand_ik"))
	row["source_pistol_aim_applied_degrees"] = solver.get("source_pistol_aim_applied_degrees")
	row["source_pistol_aim_limit_degrees"] = solver.get("source_pistol_aim_limit_degrees")
	row["logical_clip_resource"] = String(debug.get("resource_path", ""))
	row["logical_clip_provenance"] = _clip_provenance(StringName(debug.get("logical_clip", "")))
	row["raw_source_current_clip"] = String(row.logical_clip_provenance.get("source_name", ""))
	row["native_hand_measurements"] = _hand_measurements()
	row["accepted_shots_so_far"] = accepted_shots
	row["frames_since_accepted_shot"] = Engine.get_physics_frames() - last_shot_frame if last_shot_frame >= 0 else -1
	print("PISTOL_SOURCE_ATTACHMENT_SAMPLE ", state, " source=", row.raw_source_current_clip,
		" trigger_m=", row.physical.get("trigger_contact_m", -1.0),
		" barrel_deg=", row.physical.get("bore_to_reticle_degrees", -1.0))


func _extra_actions() -> void:
	for stance in [0, 1]:
		_expect(player.call("_try_set_posture", stance), "Idle-shot/reload posture accepted")
		for frame in 45:
			await _command(Vector2.ZERO)
		var label := "mark_23_" + ("standing" if stance == 0 else "crouched")
		if _request_shot():
			for frame in 30:
				await _command(Vector2.ZERO)
				_check_frame(label + "_idle_fire", true)
				if frame in [1, 8, 24]:
					await _sample(label + "_idle_fire_" + str(frame))
		for frame in 110:
			await _command(Vector2.ZERO)
		var coordinator: Node = scene.get_node("WeaponReloadCoordinator")
		var ammo_before: Dictionary = controller.get_ammo_snapshot()
		var duration := float(driver.weapon_reload_duration_seconds())
		var accepted := bool(coordinator.call("request_reload"))
		_expect(accepted, "Canonical reload accepted: " + label)
		if not accepted:
			continue
		accepted_reloads += 1
		var saw_action := false
		var start_tick := Engine.get_physics_frames()
		var completion_tick := -1
		# Wall-clock-independent physics tick budget; no edits to reload duration.
		var action_frames := ceili(duration * float(Engine.physics_ticks_per_second))
		var middle_frame := ceili(float(action_frames) * 0.5)
		for frame in action_frames + 60:
			await _command(Vector2.ZERO)
			saw_action = saw_action or "reload" in String(driver.get("requested_action")).to_lower()
			_check_frame(label + "_reload", false)
			if completion_tick < 0 and not bool(coordinator.get("pending")):
				completion_tick = Engine.get_physics_frames()
			if frame in [6, middle_frame, maxi(action_frames - 6, 7)]:
				await _sample(label + "_reload_" + str(frame))
		var ammo_after: Dictionary = controller.get_ammo_snapshot()
		var committed := int(ammo_after.rounds_in_magazine) > int(ammo_before.rounds_in_magazine)
		_expect(saw_action, "Accepted reload reached a live reload animation: " + label)
		_expect(not bool(coordinator.get("pending")), "Reload transaction completed: " + label)
		_expect(committed, "Reload committed magazine ammunition: " + label)
		if committed:
			committed_reloads += 1
		reloads.append({"state": label, "configured_duration_seconds": duration,
			"observed_completion_ticks": completion_tick - start_tick if completion_tick >= 0 else -1,
			"saw_reload_animation": saw_action, "ammo_before": ammo_before, "ammo_after": ammo_after})
		await _sample(label + "_reload_returned_idle")
	if "--all-pistol-routing" in OS.get_cmdline_user_args():
		await _check_all_pistol_routing()


func _check_all_pistol_routing() -> void:
	# Separate routing-only extension. The inherited movement/action/render
	# matrix remains Mark23; this does not claim nine weapons visually verified.
	for file in DirAccess.get_files_at("res://config/weapons"):
		if not file.ends_with(".json"):
			continue
		var path := "res://config/weapons/" + file
		var config: Dictionary = Weapons.load_config(path)
		if String(config.get("handling_profile", {}).get("family", "")) != "TWO_HAND_PISTOL":
			continue
		_expect(controller.call("apply_authorized_weapon_pickup", path), "Routing pistol equips through main controller: " + file)
		for frame in 12:
			await _command(Vector2.ZERO)
		_expect(bool(driver.get("source_pistol_attachment")), "Routing pistol uses source attachment: " + file)
		_expect(not driver.animation_tree.tree_root.has_node(&"legacy_pistol_upper"), "Routing pistol has no legacy upper: " + file)
		var solver: Node = driver.weapon_pose_solver
		_expect(not _ik_running(solver.get("left_hand_ik")) and not _ik_running(solver.get("right_hand_ik")), "Routing pistol source arm IK stopped: " + file)
		var routes: Array[Dictionary] = []
		for slot in ["idle_standing", "idle_standing_moving", "idle_crouched", "ready_standing", "ready_standing_moving", "ready_crouched", "ready_crouched_moving"]:
			var clip: StringName = driver._equipped_action_clip(slot, &"aim_idle")
			routes.append(_check_native_route(clip, file + " " + slot))
		for prefix in ["walk", "run", "crouch"]:
			for direction in ["forward", "backward", "left", "right"]:
				var slot: String = prefix + "_" + direction
				for fire in [false, true]:
					var clip: StringName = driver.locomotion_graph._weapon_locomotion_clip(slot, &"run_forward", driver.available_clips, fire)
					routes.append(_check_native_route(clip, file + " " + slot + (" fire" if fire else " carry")))
		pistol_routing.append({"weapon_config": path, "weapon_config_sha256": FileAccess.get_sha256(path), "routes": routes})
	_expect(pistol_routing.size() >= 9, "All nine normalized catalog pistols received routing checks")
	_expect(controller.call("apply_authorized_weapon_pickup", "res://config/weapons/mark_23.json"), "Restore Mark23 through main controller after routing checks")
	for frame in 12:
		await _command(Vector2.ZERO)


func _check_native_route(clip: StringName, label: String) -> Dictionary:
	var provenance := _clip_provenance(clip)
	_expect(driver.available_clips.has(clip), "Resolved pistol route exists: " + label)
	_expect(String(provenance.get("source_name", "")).begins_with("seal_p"), "Resolved route has native pistol metadata: " + label)
	_expect(int(provenance.get("track_count", 0)) > 0, "Resolved pistol route has pose tracks: " + label)
	_expect(not String(clip).begins_with("legacy_"), "No legacy route fallback: " + label)
	return {"route": label, "clip": String(clip), "provenance": provenance}


func _clip_provenance(clip: StringName) -> Dictionary:
	if clip_provenance_cache.has(clip):
		return clip_provenance_cache[clip]
	var path := String(driver.clip_paths.get(clip, ""))
	var animation: Animation = driver.animation_player.get_animation(clip) if driver.animation_player.has_animation(clip) else null
	var row := {"logical_clip": String(clip), "resource_path": path,
		"resource_sha256": FileAccess.get_sha256(path) if FileAccess.file_exists(path) else "",
		"source_name": String(animation.get_meta("source_name", "")) if animation != null else "",
		"source_sha256": String(animation.get_meta("source_sha256", "")) if animation != null else "",
		"seal_reference": bool(animation.get_meta("seal_reference", false)) if animation != null else false,
		"track_count": animation.get_track_count() if animation != null else 0,
		"note": "Metadata of the resolved logical animation, not an assertion that no other graph layer contributes to the final pose."}
	clip_provenance_cache[clip] = row
	return row


func _hand_measurements() -> Dictionary:
	var solver: Node = driver.weapon_pose_solver
	var right_wrist: Vector3 = solver.call("_bone_world_position", &"mixamorig_RightHand")
	var left_wrist: Vector3 = solver.call("_bone_world_position", &"mixamorig_LeftHand")
	var right_palm: Transform3D = solver.call("_right_hand_grip_world_transform")
	var left_palm: Transform3D = solver.call("_left_hand_grip_world_transform")
	return {"finite": right_wrist.is_finite() and left_wrist.is_finite() and _finite_transform(right_palm) and _finite_transform(left_palm),
		"native_pose_runtime_wrist_gap_m": right_wrist.distance_to(left_wrist),
		"native_pose_runtime_palm_gap_m": right_palm.origin.distance_to(left_palm.origin),
		"left_wrist_in_right_palm_frame_m": str(right_palm.affine_inverse() * left_wrist),
		"note": "Current runtime source-pose geometry; not a separate decoded source-frame comparison. Support contact and hand separation are diagnostic, not two-hand IK gates."}


func _ik_running(ik: Object) -> bool:
	return ik != null and bool(ik.call("is_running"))


func _finite_transform(value: Transform3D) -> bool:
	return value.origin.is_finite() and value.basis.x.is_finite() and value.basis.y.is_finite() and value.basis.z.is_finite()


func _expect(ok: bool, message: String) -> void:
	if not ok and message not in failures:
		failures.append(message)


func _finish() -> void:
	_expect(checked_frames >= 432, "Standing/crouched commanded movement frames were checked")
	_expect(accepted_shots == 8, "All six directional and two idle shots were accepted")
	_expect(accepted_reloads == 2 and committed_reloads == 2, "Standing and crouched reloads were accepted and committed")
	paused = false
	var report := {"canonical_scene": "res://main.tscn", "weapon": weapon_id,
		"character": character_provenance, "capture_enabled": capture,
		"checked_frames": checked_frames, "accepted_shots": accepted_shots,
		"accepted_reloads": accepted_reloads, "committed_reloads": committed_reloads,
		"maximum_trigger_contact_m": maximum_grip_error,
		"maximum_barrel_error_degrees_all_states": maximum_barrel_error_degrees,
		"maximum_unclamped_settled_firing_barrel_error_degrees": maximum_settled_barrel_error_degrees,
		"settled_aim_checked_frames": settled_aim_checked_frames, "settled_aim_limited_frames": aim_limited_frames,
		"minimum_native_wrist_gap_m": minimum_native_wrist_gap_m if is_finite(minimum_native_wrist_gap_m) else null,
		"maximum_native_wrist_gap_m": maximum_native_wrist_gap_m,
		"reloads": reloads, "pistol_routing": pistol_routing,
		"samples": samples, "failures": failures, "pass": failures.is_empty(),
		"note": "Contact, policy, finite transforms and action completion only. Inspect rendered early/middle/late views for visual quality. Neither these numbers nor the Godot source-pistol aim adaptation prove original SOCOM runtime parity."}
	DirAccess.make_dir_recursive_absolute(output_prefix.get_base_dir())
	var output := FileAccess.open(output_prefix + ".json", FileAccess.WRITE)
	if output != null:
		output.store_string(JSON.stringify(report, "\t"))
		output.close()
	else:
		_expect(false, "Could not save pistol attachment report")
	print("MAIN_PISTOL_SOURCE_ATTACHMENT ", "PASS" if failures.is_empty() else "FAIL", " ", output_prefix, " ", failures)
	if scene != null:
		scene.queue_free()
	quit(0 if failures.is_empty() else 1)
