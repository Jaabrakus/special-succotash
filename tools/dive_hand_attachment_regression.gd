extends SceneTree

const CAPTURE_DIR := "/private/tmp/socom-dive-hand-attachment"
const PoseGeometry := preload("res://scripts/player/operator_weapon_pose_geometry.gd")

var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var packed := load("res://main.tscn") as PackedScene
	_expect(packed != null, "main scene loads")
	if packed == null:
		_finish()
		return
	var scene := packed.instantiate()
	root.add_child(scene)
	await _physics_steps(30)
	var player := scene.get_node_or_null("Player") as CharacterBody3D
	var mannequin := scene.get_node_or_null("Player/Mannequin")
	var driver = mannequin.get("production_animation") if mannequin != null else null
	var solver = driver.get("weapon_pose_solver") if driver != null else null
	_expect(player != null and solver != null, "live operator and weapon solver exist")
	if player == null or solver == null:
		_finish()
		return

	# Use the clear runway reserved for automated mobility checks. Earlier broad
	# regressions can leave the operator beside a wall and hide the hand contact.
	player.global_position = Vector3(-8.0, 0.30, 3.0)
	player.global_rotation = Vector3.ZERO
	player.velocity = Vector3.ZERO
	await _physics_steps(10)
	Input.action_press(&"move_forward")
	await _physics_steps(3)
	Input.action_press(&"dive")
	await _physics_steps(2)
	Input.action_release(&"dive")
	await _physics_steps(8)
	await _process_steps(8)
	var dive_debug: Dictionary = solver.call("get_debug_state")
	var dive_contact := float(dive_debug.get("action_trigger_contact_error_m", 1.0))
	var dive_support_contact := float(
		dive_debug.get("action_support_contact_error_m", 1.0)
	)
	var dive_phase := float(player.call("get_action_phase"))
	var dive_anchor_world: Vector3 = dive_debug.get(
		"stable_chest_anchor_world",
		Vector3.ZERO
	)
	var dive_anchor_local := player.to_local(dive_anchor_world)
	var dive_profile: Dictionary = dive_debug.get("dive_weapon_presentation", {})
	var standing_descent_ratio := clampf(
		(
			PoseGeometry.STANDING_CHEST_ANCHOR_LOCAL.y
			- dive_anchor_local.y
		) / (
			PoseGeometry.STANDING_CHEST_ANCHOR_LOCAL.y
			- PoseGeometry.PRONE_CHEST_ANCHOR_LOCAL.y
		),
		0.0,
		1.0
	)
	var support_shoulder: Vector3 = solver.call(
		"_bone_world_position", &"mixamorig_LeftArm"
	)
	var support_elbow: Vector3 = solver.call(
		"_bone_world_position", &"mixamorig_LeftForeArm"
	)
	var support_hand: Vector3 = solver.call(
		"_bone_world_position", &"mixamorig_LeftHand"
	)
	var support_target: Vector3 = dive_debug.get("support_hand_target", Vector3.ZERO)
	var support_reach := (
		support_shoulder.distance_to(support_elbow)
		+ support_elbow.distance_to(support_hand)
	)
	print("DIVE_HAND_METRIC owner=%s trigger_m=%.5f support_m=%.5f" % [
		String(dive_debug.get("weapon_owner", &"")),
		dive_contact,
		dive_support_contact,
	])
	print("DIVE_SUPPORT_REACH_METRIC target_distance=%.5f chain_reach=%.5f wrist_distance=%.5f" % [
		support_shoulder.distance_to(support_target),
		support_reach,
		support_hand.distance_to(support_target),
	])
	print("DIVE_DESCENT_METRIC phase=%.4f anchor_local_y=%.4f descent_ratio=%.4f start_phase=%.3f end_phase=%.3f" % [
		dive_phase,
		dive_anchor_local.y,
		standing_descent_ratio,
		float(dive_profile.get("anchor_descent_start_phase", -1.0)),
		float(dive_profile.get("anchor_descent_end_phase", -1.0)),
	])
	_expect(
		dive_phase <= float(dive_profile.get("early_phase_limit", 0.30)),
		"standing dive descent is sampled during its declared early phase"
	)
	_expect(
		standing_descent_ratio
		<= float(dive_profile.get("maximum_early_descent_ratio", 0.10)),
		"standing dive keeps at least 90 percent of gun height through the early phase"
	)
	_expect(
		StringName(dive_debug.get("weapon_owner", &"")) == &"MOBILITY_CHEST_CARRY",
		"dive gives the rendered rifle to the stable chest carry"
	)
	_expect(dive_contact <= 0.010, "dive keeps the trigger socket within 1.0 cm of the right palm")
	_expect(
		dive_support_contact <= 0.020,
		"dive keeps the bounded foregrip contact within 2.0 cm of the left palm"
	)
	await _capture("dive_right_hand")

	for _frame in range(120):
		await physics_frame
		if StringName(player.call("get_motion_state_name")) == &"PRONE":
			break
	Input.action_release(&"move_forward")
	# The pose coordinator advances on physics frames. Render-only frames can
	# inspect the preceding mobility ownership before prone recovery has solved.
	await _physics_steps(24)
	await _process_steps(8)
	var prone_debug: Dictionary = solver.call("get_debug_state")
	var prone_contact := float(prone_debug.get("trigger_hand_error_m", 1.0))
	print("PRONE_HAND_METRIC owner=%s contact_m=%.5f follow=%s solver_owned=%s weight=%.5f" % [
		String(prone_debug.get("weapon_owner", &"")),
		prone_contact,
		str(prone_debug.get("action_weapon_follow_active", false)),
		str(prone_debug.get("weapon_solver_owned", false)),
		float(prone_debug.get("weight", 0.0)),
	])
	_expect(
		StringName(player.call("get_motion_state_name")) == &"PRONE",
		"dive settles into prone"
	)
	_expect(
		StringName(prone_debug.get("weapon_owner", &""))
		in [&"READY_SOLVER", &"RELAXED_RIFLE_LOCOMOTION"],
		"prone returns the rifle to its stable posture owner"
	)
	_expect(prone_contact <= 0.005, "prone keeps the right hand on its trigger grip")
	await _capture("prone_right_hand")

	# Reproduce the user's fast crouch -> dive -> prone route. The action must
	# keep its crouched entry anchor instead of silently switching to standing.
	Input.action_press(&"crouch")
	await _physics_steps(2)
	Input.action_release(&"crouch")
	await _physics_steps(12)
	_expect(
		StringName(player.call("get_posture_name")) == &"CROUCHED",
		"prone tap returns to crouched before the quick dive"
	)
	Input.action_press(&"move_forward")
	await _physics_steps(3)
	Input.action_press(&"dive")
	await _physics_steps(2)
	Input.action_release(&"dive")
	await _physics_steps(8)
	await _process_steps(8)
	var crouched_dive_debug: Dictionary = solver.call("get_debug_state")
	print("CROUCHED_DIVE_HAND_METRIC owner=%s trigger_m=%.5f support_m=%.5f" % [
		String(crouched_dive_debug.get("weapon_owner", &"")),
		float(crouched_dive_debug.get("action_trigger_contact_error_m", 1.0)),
		float(crouched_dive_debug.get("action_support_contact_error_m", 1.0)),
	])
	_expect(
		StringName(player.call("get_motion_state_name")) == &"DIVING"
		and StringName(player.call("get_posture_name")) == &"CROUCHED",
		"quick crouched dive preserves its crouched entry posture"
	)
	_expect(
		float(crouched_dive_debug.get("action_trigger_contact_error_m", 1.0)) <= 0.010,
		"quick crouched dive keeps the right palm on the trigger socket"
	)
	_expect(
		float(crouched_dive_debug.get("action_support_contact_error_m", 1.0)) <= 0.030,
		"quick crouched dive keeps left-palm foregrip contact within 3.0 cm"
	)
	for _frame in range(120):
		await physics_frame
		if StringName(player.call("get_motion_state_name")) == &"PRONE":
			break
	Input.action_release(&"move_forward")
	await _physics_steps(24)
	await _process_steps(8)
	var crouched_prone_debug: Dictionary = solver.call("get_debug_state")
	print("CROUCHED_PRONE_HAND_METRIC owner=%s trigger_m=%.5f follow=%s solver_owned=%s animation_parent=%s mount_error_m=%.5f weapon=%s hand=%s" % [
		String(crouched_prone_debug.get("weapon_owner", &"")),
		float(crouched_prone_debug.get("trigger_hand_error_m", 1.0)),
		str(crouched_prone_debug.get("action_weapon_follow_active", false)),
		str(crouched_prone_debug.get("weapon_solver_owned", false)),
		str(crouched_prone_debug.get("weapon_parent_is_animation_mount", false)),
		float(crouched_prone_debug.get("animation_mount_position_error_m", -1.0)),
		str(crouched_prone_debug.get("weapon_world_position", Vector3.ZERO)),
		str(crouched_prone_debug.get("trigger_hand_position", Vector3.ZERO)),
	])
	_expect(
		StringName(player.call("get_motion_state_name")) == &"PRONE",
		"quick crouched dive settles into prone"
	)
	_expect(
		float(crouched_prone_debug.get("trigger_hand_error_m", 1.0)) <= 0.005,
		"quick crouched dive recovers prone trigger contact"
	)
	_finish()


func _capture(label: String) -> void:
	if DisplayServer.get_name() == "headless":
		print("DIVE_HAND_CAPTURE SKIP %s (headless renderer)" % label)
		return
	DirAccess.make_dir_recursive_absolute(CAPTURE_DIR)
	var image := root.get_viewport().get_texture().get_image()
	_expect(image != null and not image.is_empty(), "%s capture is available" % label)
	if image == null or image.is_empty():
		return
	var path := CAPTURE_DIR.path_join("%s.png" % label)
	var result := image.save_png(path)
	_expect(result == OK, "%s capture saves" % label)
	if result == OK:
		print("DIVE_HAND_CAPTURE ", path)


func _physics_steps(count: int) -> void:
	for _frame in count:
		await physics_frame


func _process_steps(count: int) -> void:
	for _frame in count:
		await process_frame


func _expect(condition: bool, message: String) -> void:
	if condition:
		print("DIVE_HAND_CHECK PASS ", message)
	else:
		failures.append(message)
		push_error("DIVE_HAND_CHECK FAIL %s" % message)


func _finish() -> void:
	for action in [&"move_forward", &"dive", &"crouch"]:
		Input.action_release(action)
	if failures.is_empty():
		print("DIVE_HAND_ATTACHMENT_REGRESSION PASS")
	else:
		push_error("DIVE_HAND_ATTACHMENT_REGRESSION FAIL %s" % str(failures))
	quit(0 if failures.is_empty() else 1)
