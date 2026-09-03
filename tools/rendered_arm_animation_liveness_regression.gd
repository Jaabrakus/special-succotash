extends SceneTree

const MotionObserver := preload("res://scripts/player/operator_bone_motion_observer.gd")
const ARM_BONES: Array[StringName] = [
	&"mixamorig_RightArm",
	&"mixamorig_RightForeArm",
	&"mixamorig_RightHand",
	&"mixamorig_LeftArm",
	&"mixamorig_LeftForeArm",
	&"mixamorig_LeftHand",
]
const TRACKED_BONES: Array[StringName] = [
	&"mixamorig_Head",
	&"mixamorig_RightShoulder",
	&"mixamorig_LeftShoulder",
	&"mixamorig_RightArm",
	&"mixamorig_RightForeArm",
	&"mixamorig_RightHand",
	&"mixamorig_LeftArm",
	&"mixamorig_LeftForeArm",
	&"mixamorig_LeftHand",
]

var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var packed := load("res://main.tscn") as PackedScene
	_expect(packed != null, "canonical main scene loads")
	if packed == null:
		_finish()
		return
	var scene := packed.instantiate()
	root.add_child(scene)
	for _frame in range(75):
		await process_frame
	var player := scene.get_node_or_null("Player") as CharacterBody3D
	var mannequin := scene.get_node_or_null("Player/Mannequin")
	var driver := scene.get_node_or_null("Player/Mannequin/ProductionAnimation")
	var skeleton := driver.get("skeleton") as Skeleton3D if driver != null else null
	_expect(player != null and mannequin != null and driver != null and skeleton != null, "live player animation rig exists")
	if player == null or mannequin == null or driver == null or skeleton == null:
		_finish()
		return

	var observer := MotionObserver.new()
	observer.name = "RenderedArmAnimationLivenessObserver"
	skeleton.add_child(observer)
	observer.bind(skeleton, TRACKED_BONES)
	mannequin.set_process(false)
	driver.call(
		"set_visual_inputs",
		Vector2(0.0, 1.0), &"STANDING", 0.0, 0.0, 0.0, false, 0.0,
		1.0, &"LOCOMOTION", 0.0, &"FULL", 5.45,
		player.global_position + Vector3(0.0, 1.35, -25.0),
		Vector2(0.0, 1.0), 1.0, &"SUSTAINED", 0.0
	)
	for _frame in range(16):
		await process_frame
	observer.reset_samples()
	for _frame in range(36):
		await process_frame
	var sprint_motion: Dictionary = observer.get_motion_degrees()
	print("ARM_LIVENESS forward_sprint=%s" % JSON.stringify(sprint_motion))
	_expect_run_motion(sprint_motion, "spawn forward run")
	var sprint_snapshot: Dictionary = driver.call("get_animation_debug_state")
	_expect(
		StringName(sprint_snapshot.get("presentation_mode", &"")) == &"RELAXED_RIFLE"
		and float(sprint_snapshot.get("upper_body_ready_blend", 1.0)) <= 0.001,
		"spawn forward run keeps the authored full-body owner"
	)

	driver.call(
		"set_visual_inputs",
		Vector2(0.0, 1.0), &"STANDING", 0.0, 0.0, 0.0, false, 0.0,
		0.65, &"LOCOMOTION", 0.0, &"WALK", 2.0,
		player.global_position + Vector3(0.0, 1.35, -25.0),
		Vector2(0.0, 1.0), 1.0, &"SUSTAINED", 0.0
	)
	for _frame in range(16):
		await process_frame
	var before_fire: Dictionary = driver.call("get_animation_debug_state")
	var fire_count_before := int(before_fire.get("fire_trigger_count", 0))
	observer.reset_samples()
	_expect(bool(mannequin.call("notify_operator_fired")), "accepted fire enters presentation")
	for _frame in range(30):
		await process_frame
	var recovery_motion: Dictionary = observer.get_motion_degrees()
	print("ARM_LIVENESS fire_recovery=%s" % JSON.stringify(recovery_motion))
	var recovery_snapshot: Dictionary = driver.call("get_animation_debug_state")
	var recovery_latch: Dictionary = recovery_snapshot.get("fire_upper_body_latch", {})
	var recovery_ccdik: Dictionary = recovery_snapshot.get("combat_ready_ccdik", {})
	var recovery_weapon_pose: Dictionary = recovery_snapshot.get("weapon_pose", {})
	_expect(
		StringName(recovery_latch.get("owner_state", &"")) == &"FIRE_RECOVERY"
		and bool(recovery_latch.get("selected", false)),
		"accepted shot remains in FIRE_RECOVERY during the bounded interval"
	)
	_expect(
		int(recovery_snapshot.get("fire_trigger_count", -1)) == fire_count_before
		and StringName(recovery_snapshot.get("active_fire_clip", &"invalid")) == &"",
		"FIRE_RECOVERY does not trigger combat_fire or crouch_fire"
	)
	_expect(
		float(recovery_snapshot.get("upper_body_ready_blend", 0.0)) >= 0.99,
		"mapped recovery animation owns the bounded upper-body presentation"
	)
	_expect(
		int(recovery_snapshot.get("animation_frame_rotation_override_count", -1)) == 0
		and float(recovery_ccdik.get("active_weight", 1.0)) <= 0.001
		and float(recovery_ccdik.get("modifier_influence", 1.0)) <= 0.001,
		"recovery keeps saved shoulder rotations and spine/head CCDIK disabled"
	)
	_expect(
		not bool(recovery_weapon_pose.get("hand_socket_ik_enabled", true))
		and not bool(recovery_weapon_pose.get("weapon_solver_owned", true)),
		"recovery keeps the procedural hand and weapon solver disabled"
	)
	_expect_recovery_motion(recovery_motion)

	await create_timer(1.35).timeout
	observer.reset_samples()
	for _frame in range(36):
		await process_frame
	var returned_motion: Dictionary = observer.get_motion_degrees()
	print("ARM_LIVENESS returned_forward_run=%s" % JSON.stringify(returned_motion))
	var returned_snapshot: Dictionary = driver.call("get_animation_debug_state")
	var returned_latch: Dictionary = returned_snapshot.get("fire_upper_body_latch", {})
	_expect(
		StringName(returned_latch.get("owner_state", &"")) == &"BASE"
		and not bool(returned_latch.get("selected", true)),
		"FIRE_RECOVERY ends after 1.2 seconds"
	)
	_expect(
		StringName(returned_snapshot.get("presentation_mode", &"")) == &"RELAXED_RIFLE"
		and float(returned_snapshot.get("upper_body_ready_blend", 1.0)) <= 0.05,
		"forward run returns to its authored presentation after the recovery blend"
	)
	_expect_run_motion(returned_motion, "returned forward run")

	scene.queue_free()
	_finish()


func _expect_run_motion(motion: Dictionary, label: String) -> void:
	for bone_name in ARM_BONES:
		var sample: Dictionary = motion.get(String(bone_name), {})
		var minimum_motion := 4.0 if String(bone_name).ends_with("Hand") else 8.0
		_expect(
			float(sample.get("accumulated_deg", 0.0)) >= minimum_motion,
			"%s visibly animates %s" % [label, String(bone_name)]
		)
	for bone_name in TRACKED_BONES:
		var sample: Dictionary = motion.get(String(bone_name), {})
		_expect(
			float(sample.get("maximum_step_deg", INF)) <= 12.0,
			"%s has no head, shoulder, or arm pose snap at %s" % [
				label, String(bone_name)
			]
		)


func _expect_recovery_motion(motion: Dictionary) -> void:
	for bone_name in ARM_BONES:
		var sample: Dictionary = motion.get(String(bone_name), {})
		_expect(
			float(sample.get("accumulated_deg", 0.0)) >= 2.0,
			"mapped recovery visibly animates %s" % String(bone_name)
		)
	for bone_name in TRACKED_BONES:
		var sample: Dictionary = motion.get(String(bone_name), {})
		_expect(
			float(sample.get("maximum_step_deg", INF)) <= 12.0,
			"mapped recovery has no head, shoulder, or arm snap at %s" % String(bone_name)
		)


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("ARM_LIVENESS PASS ", label)
	else:
		failures.append(label)
		push_error("ARM_LIVENESS FAIL %s" % label)


func _finish() -> void:
	if failures.is_empty():
		print("RENDERED_ARM_ANIMATION_LIVENESS_REGRESSION PASS")
		quit(0)
	else:
		print("RENDERED_ARM_ANIMATION_LIVENESS_REGRESSION FAIL %s" % [failures])
		quit(1)
