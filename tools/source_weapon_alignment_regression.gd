extends "res://tools/rifle_reference_visual_probe.gd"
## Exercises saved source profiles through canonical main, not a parallel rig.
const Catalog := preload("res://scripts/weapons/socom_weapon_catalog.gd")
const MotionProof := preload("res://tools/main_source_motion_proof.gd")
var baseline := false

func _run() -> void:
	baseline = "--baseline" in OS.get_cmdline_user_args()
	ProjectSettings.set_setting("socom/session/public_training", true)
	root.set_disable_input(true)
	root.size = Vector2i(1280, 800)
	scene = (load("res://main.tscn") as PackedScene).instantiate() as Node3D
	scene.get_node("IndependentCameraRig").capture_mouse_on_ready = false
	root.add_child(scene)
	current_scene = scene
	player = scene.get_node("Player")
	player.set_local_input_enabled(false)
	controller = scene.get_node("WeaponController")
	controller.set_input_enabled(false)
	driver = player.get_node("Mannequin/ProductionAnimation")
	await _frames(45)
	_install_fixture()
	var ids := Catalog.source_arsenal_ids()
	if "--representative" in OS.get_cmdline_user_args():
		ids.assign(["s2_mark_23", "s2_m4a1", "s2_870", "s2_m40a1", "s2_hk5"])
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--only="):
			ids.assign(argument.trim_prefix("--only=").split(","))
			for id: String in ids:
				if not Catalog.source_arsenal_ids().has(id):
					failures.append("Unknown proof weapon " + id)
					_finish()
					return
	for id: String in ids:
		weapon_id = id
		if not controller.apply_authorized_weapon_pickup("res://config/weapons/" + id + ".json"):
			failures.append("Equip refused " + id)
			continue
		for stance in [0, 1, 2]:
			if not player.call("_try_set_posture", stance):
				failures.append("Posture refused " + id + "/" + str(stance))
				continue
			await _frames(90)
			await _check_hold(id + "_" + str(stance) + "_idle")
			if _request_shot():
				await _frames(12)
				await _check_hold(id + "_" + str(stance) + "_fire")
			await _frames(90)
	if not baseline:
		await _release_and_move()
	print("SOURCE_WEAPON_ALIGNMENT ", "PASS" if failures.is_empty() else "FAIL", " samples=", samples.size())
	_finish()

func _release_and_move() -> void:
	weapon_id = "s2_mark_23"
	var pose: Node3D = driver.weapon_pose_solver
	var ik_count: int = driver.skeleton.find_children("*", "SkeletonIK3D", true, false).size()
	if not controller.apply_authorized_weapon_pickup("res://config/weapons/s2_mark_23.json"):
		failures.append("Release proof equip refused")
		return
	if pose.source_support_contact_weight != 0.0 or pose.source_support_contact_active:
		failures.append("Equip did not reset prior grip state")
	player.call("_try_set_posture", 0)
	await _frames(90)
	var feeder := MotionProof.HeldCommandFeeder.new()
	feeder.actor = player
	feeder.process_physics_priority = -100
	scene.add_child(feeder)
	for direction in [Vector2(0, -1), Vector2(-1, 0), Vector2(1, 0)]:
		feeder.direction = direction
		await _frames(36)
		await _check_hold("pistol_move_" + str(direction))
	feeder.direction = Vector2.ZERO
	await _frames(90)
	if _request_shot(): await _frames(20)
	var coordinator: Node = scene.get_node("WeaponReloadCoordinator")
	var ammo_before: Dictionary = controller.get_ammo_snapshot()
	if not coordinator.request_reload():
		failures.append("Canonical reload refused")
	else:
		await _frames(14)
		if not "reload" in String(driver.requested_action): failures.append("Reload did not reach animation")
		if pose.source_support_contact_active or pose.source_support_contact_weight != 0.0 or pose.support_hand_grip_locked:
			failures.append("Support hand remained pinned in reload")
		if driver.weapon_grip_contact.applied_left: failures.append("Support fingers remained closed in reload")
		await _frames(ceili(driver.weapon_reload_duration_seconds() * Engine.physics_ticks_per_second) + 60)
		if coordinator.pending or controller.get_ammo_snapshot().rounds_in_magazine <= ammo_before.rounds_in_magazine:
			failures.append("Canonical reload did not commit")
		await _check_hold("pistol_reload_return")
	feeder.jump_once = true
	await _frames(6)
	if player.get_motion_state_name() != &"AIRBORNE": failures.append("Jump was not airborne")
	if pose.source_support_contact_active or pose.support_hand_grip_locked or driver.weapon_grip_contact.applied_left:
		failures.append("Jump did not release support")
	await _frames(90)
	await _check_hold("pistol_jump_return")
	feeder.queue_free()
	if not controller.apply_authorized_weapon_pickup("res://config/weapons/mark_23.json"):
		failures.append("Protected original pistol equip refused")
	await _frames(90)
	if pose.source_support_contact_active or pose.support_hand_grip_locked:
		failures.append("Opt-in grip leaked into original source-pose pistol")
	if driver.skeleton.find_children("*", "SkeletonIK3D", true, false).size() != ik_count:
		failures.append("Equip appended a second arm IK owner")

func _check_hold(label: String) -> void:
	await _sample(label)
	var measured: Dictionary = samples.back().physical
	var pose: Node3D = driver.weapon_pose_solver
	var grip: Dictionary = driver.weapon_grip_contact.snapshot()
	samples.back()["finger_grip"] = grip
	samples.back()["support_active"] = pose.source_support_contact_active
	samples.back()["reach_limited"] = pose.source_support_reach_limited
	samples.back()["support_mode"] = String(pose.support_hand_mode)
	samples.back()["source_pose_only"] = pose.source_pose_only
	samples.back()["hand_frames"] = {
		"right": str(pose.weapon_node.global_basis.orthonormalized().inverse() * pose._right_hand_grip_world_transform().basis),
		"left": str(pose.weapon_node.global_basis.orthonormalized().inverse() * pose._left_hand_grip_world_transform().basis)}
	if baseline: return
	if not is_finite(float(measured.trigger_contact_m)) or float(measured.trigger_contact_m) > 0.01:
		failures.append("Trigger palm exceeds 1cm " + label + ": " + str(measured.trigger_contact_m))
	var free_carry: bool = label.begins_with("pistol_move_") and pose.source_support_reach_limited
	if free_carry:
		var profile: Dictionary = driver.equipped_weapon_config.support_hand_pose
		var basis: Basis = pose.WeaponContactSolver.support_contact_basis(pose.support_socket.global_basis, profile)
		var desired: Transform3D = pose.WeaponContactSolver.wrist_target_for_contact(driver.skeleton, Transform3D(basis, pose.support_socket.global_position), pose.left_palm_anchor_local)
		var reach: float = pose._bone_world_position(&"mixamorig_LeftArm").distance_to(desired.origin)
		if reach <= pose._arm_length(&"left") * 0.98 or pose.support_hand_grip_locked or grip.left_grip_applied:
			failures.append("Free carry must correspond to real unreachable support, without an arm/finger pin " + label)
	elif not is_finite(float(measured.support_contact_m)) or float(measured.support_contact_m) > 0.01:
		failures.append("Support palm exceeds 1cm " + label + ": " + str(measured.support_contact_m))
	if not grip.right_grip_applied or (not free_carry and not grip.left_grip_applied):
		failures.append("Both finger holds must be applied " + label)
	if not pose.weapon_node.global_transform.is_finite():
		failures.append("Non-finite weapon transform " + label)
