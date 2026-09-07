extends "res://tools/firearm_family_transition_regression.gd"

## Actual canonical reload lifecycle; ammunition is seeded only as case setup.
## --weapons=m16a2,m4a1,mark_23 --capture --output-prefix=/private/tmp/reload-attachment
var reload_rows: Array[Dictionary] = []
var reload_lifecycles: Array[Dictionary] = []


func _initialize() -> void:
	var explicit_weapons := false
	for argument in OS.get_cmdline_user_args():
		explicit_weapons = explicit_weapons or argument.begins_with("--weapons=")
	if not explicit_weapons:
		selected_ids.assign(["m16a2"])
	super._initialize()


func _runtime_source_signatures() -> Dictionary:
	var result := super._runtime_source_signatures()
	for name in ["operator_weapon_pose_actions", "operator_weapon_authored_pose", "operator_weapon_pose_kinematics", "operator_weapon_presentation_owner"]:
		result[name] = FileAccess.get_sha256("res://scripts/player/" + name + ".gd")
	return result


func _check_stance(stance: int) -> void:
	await _reload_posture(stance)
	if stance == 1:
		await _reload_posture(2)


func _reload_posture(stance: int) -> void:
	_release_inputs()
	if not player.call("_try_set_posture", stance):
		_fail_once(weapon_id + " reload posture refused")
		return
	await _frames(120)
	var label := weapon_id + "_" + String(["standing", "crouched", "prone"][stance])
	controller.set("rounds_in_magazine", 5)
	controller.set("reserve_rounds", 20)
	if not scene.call("_request_weapon_reload"):
		_fail_once(label + " reload entry refused")
		return
	for frame in 12:
		await _frames(1)
		_measure_reload(label + "_entry", frame)
	await _capture_state(label + "_reload_before_interrupt")
	var before := int(controller.get("rounds_in_magazine"))
	controller.emit_signal("reload_fire_interrupt_requested")
	if bool(controller.get("reload_locked")) or bool(scene.get("reload_commit_pending")):
		_fail_once(label + " interrupt did not release reload lock")
	if not await _accepted_shot(label + "_interrupt"):
		return
	first_fire_frame_pending = false
	if int(controller.get("rounds_in_magazine")) != before - 1:
		_fail_once(label + " interrupt shot did not consume exactly one round")
	_measure_reload(label + "_interrupt_fire", 0)
	await _frames(2)
	if not scene.call("_request_weapon_reload"):
		_fail_once(label + " reload restart refused")
		return
	var action: StringName = driver.requested_action
	var clip: Animation = driver.animation_player.get_animation(action)
	var saved_seconds: float = driver.weapon_reload_duration_seconds()
	var expected_duration := clip.length / clampf(clip.length / saved_seconds, 0.25, 3.0)
	var actual_duration: float = driver.requested_action_total_duration
	var ammo_before := int(controller.get("rounds_in_magazine"))
	var commit_frame := -1
	var committed_while_locked := false
	var frames := 0
	while bool(scene.get("reload_commit_pending")) and frames < 900:
		await _frames(1)
		_measure_reload(label + "_reload", frames)
		if commit_frame < 0 and int(controller.get("rounds_in_magazine")) != ammo_before:
			commit_frame = frames
			committed_while_locked = bool(scene.get("reload_commit_pending")) and bool(controller.get("reload_locked"))
		frames += 1
	if bool(controller.get("reload_locked")) or bool(scene.get("reload_commit_pending")) or commit_frame < 0 or not committed_while_locked:
		_fail_once(label + " reload commit/recovery lifecycle failed")
	var magazine := int(controller.get("rounds_in_magazine"))
	var reserve := int(controller.get("reserve_rounds"))
	if magazine != mini(int(controller.get("magazine_capacity")), ammo_before + 20) or magazine + reserve != ammo_before + 20:
		_fail_once(label + " reload ammunition conservation changed")
	if absf(actual_duration - expected_duration) > 0.0001:
		_fail_once(label + " resolved reload duration changed")
	for frame in 30:
		await _frames(1)
		_measure_reload(label + "_complete", frame)
	await _capture_state(label + "_reload_complete")
	reload_lifecycles.append({"case":label,"clip":action,"expected_duration":expected_duration,"actual_duration":actual_duration,"frames":frames,"commit_frame":commit_frame,"magazine":magazine,"reserve":reserve})


func _measure_reload(label: String, frame: int) -> void:
	_assert_weapon_visible(label)
	if _accepted_shot_count() != expected_accepted_shots:
		_fail_once(label + " unrequested accepted shot")
	var pose: Node = driver.weapon_pose_solver
	var physical := _measure_physical_pose()
	var row := {"weapon":weapon_id,"case":label,"frame":frame,"action":driver.requested_action,"owner":pose.weapon_owner,"weapon_parent":String(pose.weapon_node.get_parent().name),"solver_owned":pose.weapon_solver_owned,"reported_trigger_error_m":pose.action_trigger_contact_error_m,"physical_trigger_error_m":physical.trigger_contact_m,"physical_support_error_m":physical.support_contact_m,"physical_bore_error_deg":physical.bore_to_reticle_degrees,"right_ik_running":pose.right_hand_ik.is_running(),"reload_locked":controller.get("reload_locked"),"commit_pending":scene.get("reload_commit_pending")}
	reload_rows.append(row)
	if float(physical.trigger_contact_m) > 0.01:
		_fail_once(label + " actual trigger palm detached above 10 mm")
	if String(pose.weapon_owner) == "RELOAD_RIGHT_HAND" and (pose.weapon_solver_owned or pose.right_hand_ik.is_running()):
		_fail_once(label + " reload acquired right-arm aim IK ownership")


func _finish() -> void:
	if not list_only and reload_lifecycles.size() != selected_ids.size() * 3:
		_fail_once("Every selected weapon must finish reload in all three postures")
	var report := {"pass":failures.is_empty(),"failures":failures,"rows":reload_rows,"lifecycles":reload_lifecycles,"sources_start":runtime_sources_at_start,"sources_finish":_runtime_source_signatures()}
	var file := FileAccess.open(output_prefix + "-reload.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	print("RELOAD_TRIGGER_ATTACHMENT ", "PASS" if failures.is_empty() else "FAIL", " frames=",reload_rows.size(), " lifecycles=",reload_lifecycles.size()," ",failures)
	super._finish()
