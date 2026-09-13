extends "res://tools/main_source_motion_proof.gd"

## Separate acceptance from the two-hand-contact trial. A free source arm must
## stay free, not pass by being pulled to a support socket.
class PoseObserver extends Node:
	var driver: Node3D
	var before: Array[Transform3D] = []
	var frame := 0
	func _process(_delta: float) -> void:
		before.clear()
		for index in driver.skeleton.get_bone_count():
			before.append(driver.skeleton.get_bone_global_pose(index))
		frame = Engine.get_process_frames()

var observer: PoseObserver
var maximum_body_delta_m := 0.0
var maximum_basis_delta := 0.0
var maximum_free_hand_gap_m := 0.0
var checked_frames := 0

func _install_fixture() -> void:
	super._install_fixture()
	observer = PoseObserver.new()
	observer.driver = driver
	observer.process_priority = 99 # tree sample -> observe -> driver at 100
	scene.add_child(observer)

func _check_frame(label: String, _firing: bool) -> void:
	var measured := _measure_physical_pose()
	maximum_grip_error = maxf(maximum_grip_error, float(measured.trigger_contact_m))
	maximum_free_hand_gap_m = maxf(maximum_free_hand_gap_m, float(measured.support_contact_m))
	_check(bool(driver.get("source_pose_only")), "source-only policy active")
	_check(not driver.animation_tree.tree_root.has_node(&"legacy_pistol_upper"), "legacy upper absent")
	_check(float(measured.trigger_contact_m) <= 0.015, "right palm remains on weapon")
	_check(player.is_on_floor(), "CharacterBody stays grounded")
	var solver = driver.weapon_pose_solver
	_check(solver.support_hand_mode == &"ANIMATION_FREE", "support arm belongs to source")
	_check(not solver.left_hand_ik.is_running() and not solver.right_hand_ik.is_running(), "arm IK stopped")
	_check(not solver.support_hand_grip_locked and not solver.trigger_hand_grip_locked, "no wrist pins")
	if observer.before.size() == driver.skeleton.get_bone_count():
		for index in observer.before.size():
			var after: Transform3D = driver.skeleton.get_bone_global_pose(index)
			maximum_body_delta_m = maxf(maximum_body_delta_m,
				after.origin.distance_to(observer.before[index].origin) * driver.skeleton.global_basis.get_scale().length() / sqrt(3.0))
			for axis in 3:
				maximum_basis_delta = maxf(maximum_basis_delta,
					after.basis[axis].distance_to(observer.before[index].basis[axis]))
		checked_frames += 1
	_check(maximum_body_delta_m < 0.001, "no post-tree body translation")
	_check(maximum_basis_delta < 0.001, "no post-tree body rotation")

func _check(ok: bool, message: String) -> void:
	if not ok and not message in failures: failures.append(message)

func _extra_actions() -> void:
	# Accepted reload owns timing and ammo. The source-only policy must not
	# leave it pending or silently change its duration to hide presentation.
	player.call("_try_set_posture", 0)
	for frame in 40: await _command(Vector2.ZERO)
	var ammo_before: Dictionary = controller.get_ammo_snapshot()
	var coordinator: Node = scene.get_node("WeaponReloadCoordinator")
	_check(coordinator.request_reload(), "canonical reload accepted")
	var duration: float = driver.weapon_reload_duration_seconds()
	for frame in ceili(duration * 60.0) + 45:
		await _command(Vector2.ZERO)
		if frame in [6, ceili(duration * 30.0), ceili(duration * 60.0) - 5]:
			await _sample(weapon_id + "_source_reload_" + str(frame))
	_check(not bool(coordinator.get("pending")), "reload transaction completed")
	var ammo_after: Dictionary = controller.get_ammo_snapshot()
	_check(int(ammo_after.rounds_in_magazine) > int(ammo_before.rounds_in_magazine), "reload committed ammunition")
	await _sample(weapon_id + "_source_reload_return")
	for frame in 20: await _command(Vector2(0, -1))
	feeder.jump_once = true
	await physics_frame
	await process_frame
	var airborne := false
	for frame in 100:
		await _command(Vector2(0, -1) if frame < 35 else Vector2.ZERO)
		airborne = airborne or not player.is_on_floor()
		if frame in [6, 18, 70]: await _sample(weapon_id + "_source_jump_" + str(frame))
	_check(airborne and player.is_on_floor(), "real running jump left floor and landed")
	_check(not driver.weapon_pose_solver.left_hand_ik.is_running(), "jump retains free source hand")
	await _sample(weapon_id + "_source_landed")

func _finish() -> void:
	_check(checked_frames > 300, "real movement frames checked")
	if weapon_id in ["mark_23", "de__50", "f57"]:
		_check(maximum_free_hand_gap_m > 0.10, "running source has free support arm")
	print("SOURCE_POSE_ONLY_MAIN ", JSON.stringify({"checked_frames": checked_frames,
		"max_body_delta_m": maximum_body_delta_m, "max_basis_delta": maximum_basis_delta,
		"max_trigger_error_m": maximum_grip_error, "max_free_support_gap_m": maximum_free_hand_gap_m,
		"failures": failures}))
	super._finish()
