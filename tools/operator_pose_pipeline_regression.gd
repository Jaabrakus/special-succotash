extends SceneTree

const DriverScript := preload(
	"res://scripts/player/operator_animation_driver.gd"
)
const PoseHandoff := preload(
	"res://scripts/player/operator_pose_handoff.gd"
)
const CameraMarkerFilter := preload(
	"res://scripts/player/operator_camera_marker_filter.gd"
)

const AIM_FRAME_BONES: Array[String] = [
	"mixamorig_Spine",
	"mixamorig_Spine1",
	"mixamorig_Spine2",
	"mixamorig_Neck",
	"mixamorig_Head",
]

const FIRE_RECOVERY_LIMB_BONES: Array[String] = [
	"mixamorig_LeftShoulder", "mixamorig_LeftArm", "mixamorig_LeftForeArm", "mixamorig_LeftHand",
	"mixamorig_RightShoulder", "mixamorig_RightArm", "mixamorig_RightForeArm", "mixamorig_RightHand",
	"mixamorig_LeftHandThumb1", "mixamorig_LeftHandThumb2", "mixamorig_LeftHandThumb3",
	"mixamorig_LeftHandIndex1", "mixamorig_LeftHandIndex2", "mixamorig_LeftHandIndex3",
	"mixamorig_LeftHandMiddle1", "mixamorig_LeftHandMiddle2", "mixamorig_LeftHandMiddle3",
	"mixamorig_LeftHandRing1", "mixamorig_LeftHandRing2", "mixamorig_LeftHandRing3",
	"mixamorig_LeftHandPinky1", "mixamorig_LeftHandPinky2", "mixamorig_LeftHandPinky3",
	"mixamorig_RightHandThumb1", "mixamorig_RightHandThumb2", "mixamorig_RightHandThumb3",
	"mixamorig_RightHandIndex1", "mixamorig_RightHandIndex2", "mixamorig_RightHandIndex3",
	"mixamorig_RightHandMiddle1", "mixamorig_RightHandMiddle2", "mixamorig_RightHandMiddle3",
	"mixamorig_RightHandRing1", "mixamorig_RightHandRing2", "mixamorig_RightHandRing3",
	"mixamorig_RightHandPinky1", "mixamorig_RightHandPinky2", "mixamorig_RightHandPinky3",
]

var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var driver := DriverScript.new()
	root.add_child(driver)
	await process_frame
	await process_frame
	var pipeline = driver.get("pose_pipeline")
	_expect(pipeline != null, "operator exposes one pose-pipeline node")
	if pipeline != null:
		var expected: Array[StringName] = [
			&"10_BaseAnimation",
			&"20_PostureAndShoulderFrame",
			&"30_FireTorsoShoulderArms",
			&"40_WeaponMuzzleAlignment",
			&"50_HandContact",
			&"60_FootGrounding",
			&"70_PresentationEvents",
		]
		_expect(pipeline.ordered_stage_names() == expected, "pose stages use one deterministic order")
		_expect(
			pipeline.get_node_or_null(
				"20_PostureAndShoulderFrame/BodyBeforeHandsHandoff"
			) != null,
			"posture stage owns the body-before-hands evaluation barrier"
		)
		_expect(
			pipeline.get_node_or_null("40_WeaponMuzzleAlignment/WeaponPoseSolver") != null,
			"muzzle alignment owns the weapon solver node"
		)
		_expect(
			pipeline.get_node_or_null("50_HandContact/OperatorIKContract") != null,
			"hand contact owns the IK contract node"
		)
		_expect(
			pipeline.get_node_or_null(
				"30_FireTorsoShoulderArms/FireUpperBodyLatch"
			) != null,
			"fire stage owns the accepted-shot recovery latch component"
		)
	var marker_filter = CameraMarkerFilter.new()
	marker_filter.name = "CameraMarkerFilter"
	root.add_child(marker_filter)
	var bounded_head_delta: Vector3 = marker_filter.filtered_delta(
		Vector3(1.0, 1.0, 1.0),
		&"HEAD"
	)
	_expect(
		bounded_head_delta.y <= 0.0151
		and absf(bounded_head_delta.x) <= 0.0251
		and marker_filter.maximum_weighted_vertical_offset(&"HEAD") <= 0.0151,
		"camera marker filter limits animated head bob before camera framing"
	)
	var ready_head_delta: Vector3 = marker_filter.filtered_delta(
		Vector3(1.0, 1.0, 1.0),
		&"HEAD",
		&"READY"
	)
	var ready_torso_delta: Vector3 = marker_filter.filtered_delta(
		Vector3(1.0, 1.0, 1.0),
		&"TORSO",
		&"READY"
	)
	var ready_pelvis_delta: Vector3 = marker_filter.filtered_delta(
		Vector3(1.0, 1.0, 1.0),
		&"PELVIS",
		&"READY"
	)
	_expect(
		ready_head_delta.is_zero_approx()
		and ready_torso_delta.is_zero_approx()
		and ready_pelvis_delta.is_zero_approx()
		and is_zero_approx(
			marker_filter.maximum_weighted_vertical_offset(
				&"HEAD", &"READY"
			)
		),
		"ready and fire keep all camera markers on stable stance anchors"
	)
	marker_filter.queue_free()
	var handoff = PoseHandoff.new()
	handoff.prime(&"STANDING", false, 0.0)
	var body_first: Dictionary = handoff.resolve(&"CROUCHED", true, 1.0)
	_expect(
		bool(body_first.get("barrier_active", false))
		and StringName(body_first.get("presentation_posture", &"")) == &"STANDING"
		and is_zero_approx(float(body_first.get("presentation_ready_weight", -1.0))),
		"simultaneous stance/movement/fire gives the body one evaluation first"
	)
	var hands_follow: Dictionary = handoff.resolve(&"CROUCHED", true, 1.0)
	_expect(
		not bool(hands_follow.get("barrier_active", true))
		and bool(hands_follow.get("released_hands", false))
		and StringName(hands_follow.get("presentation_posture", &"")) == &"CROUCHED"
		and is_equal_approx(float(hands_follow.get("presentation_ready_weight", 0.0)), 1.0),
		"hands and weapon follow the committed crouch route on the next evaluation"
	)
	handoff.free()
	var graph_root := driver.animation_tree.tree_root as AnimationNodeBlendTree
	_expect(
		graph_root != null
		and graph_root.has_node(&"crouch_upper_body")
		and graph_root.has_node(&"crouch_idle_upper_body")
		and graph_root.has_node(&"standing_aim_frame")
		and graph_root.has_node(&"standing_idle_aim_frame")
		and graph_root.has_node(&"crouch_aim_frame")
		and graph_root.has_node(&"crouch_idle_aim_frame"),
		"standing and crouched movement/idle expose separate aim-frame and recovery layers"
	)
	for layer_name in driver.locomotion_graph.standing_transition_layer_nodes:
		_expect(
			is_equal_approx(float(driver.animation_tree.get(
				"parameters/%s/blend_amount" % layer_name
			)), 1.0),
			"standing transition keeps its Idle Rifle/Aim Idle upper-body owner"
		)
	var idle_snapshot: Dictionary = driver.get_animation_debug_state()
	_expect(
		int(idle_snapshot.get("square_idle_reference_bone_count", 0)) == 2,
		"standing idle squares the head without replacing authored leg rotations"
	)
	var idle_hip_input := absf(float(idle_snapshot.get("default_hip_roll_input_deg", 0.0)))
	var idle_hip_trim := absf(float(idle_snapshot.get("default_hip_roll_trim_deg", 0.0)))
	var idle_hip_output := absf(float(idle_snapshot.get("default_hip_roll_output_deg", 0.0)))
	_expect(
		idle_hip_trim <= idle_hip_input + 0.01
		and idle_hip_output <= 0.10,
		"standing idle squares pelvis roll without replacing authored leg rotations"
	)
	var recovery_layer_names: Array[StringName] = [
		&"standing_upper_body",
		&"standing_idle_upper_body",
		&"crouch_upper_body",
		&"crouch_idle_upper_body",
	]
	for layer_name: StringName in recovery_layer_names:
		var recovery_layer := graph_root.get_node(layer_name) as AnimationNodeBlend2
		_expect(
			recovery_layer != null and recovery_layer.filter_enabled,
			"%s is a filtered recovery layer" % layer_name
		)
		if recovery_layer == null:
			continue
		for bone_name: String in FIRE_RECOVERY_LIMB_BONES:
			_expect(
				recovery_layer.is_path_filtered(NodePath(".:%s" % bone_name)),
				"%s owns recovery limb %s" % [layer_name, bone_name]
			)
		for bone_name in [
			"mixamorig_Hips", "mixamorig_Spine", "mixamorig_Spine1",
			"mixamorig_Spine2", "mixamorig_Neck", "mixamorig_Head",
		]:
			_expect(
				not recovery_layer.is_path_filtered(NodePath(".:%s" % bone_name)),
					"%s leaves stable frame bone %s to its declared owner" % [layer_name, bone_name]
				)
	var aim_frame_layer_names: Array[StringName] = [
		&"standing_aim_frame",
		&"standing_idle_aim_frame",
		&"crouch_aim_frame",
		&"crouch_idle_aim_frame",
	]
	for layer_name: StringName in aim_frame_layer_names:
		var aim_frame_layer := graph_root.get_node(layer_name) as AnimationNodeBlend2
		_expect(
			aim_frame_layer != null and aim_frame_layer.filter_enabled,
			"%s is a filtered stationary-pose aim frame" % layer_name
		)
		if aim_frame_layer == null:
			continue
		for bone_name: String in AIM_FRAME_BONES:
			_expect(
				aim_frame_layer.is_path_filtered(NodePath(".:%s" % bone_name)),
				"%s owns aim-frame bone %s" % [layer_name, bone_name]
			)
		for bone_name in [
			"mixamorig_Hips", "mixamorig_LeftShoulder", "mixamorig_RightShoulder",
			"mixamorig_LeftArm", "mixamorig_RightArm", "mixamorig_LeftHand",
			"mixamorig_RightHand", "mixamorig_LeftLeg", "mixamorig_RightLeg",
		]:
			_expect(
				not aim_frame_layer.is_path_filtered(NodePath(".:%s" % bone_name)),
				"%s cannot claim non-frame bone %s" % [layer_name, bone_name]
			)
	_expect(
		is_zero_approx(float(driver.animation_tree.get(
			"parameters/standing_idle_aim_frame/blend_amount"
		)))
		and is_zero_approx(float(driver.animation_tree.get(
			"parameters/crouch_idle_aim_frame/blend_amount"
		))),
		"aim-frame layers stay inactive before an accepted shot"
	)
	_expect(
		driver._lower_body_separation_weight(&"STANDING", 1.0) > 0.99
		and driver._lower_body_separation_weight(&"CROUCHED", 1.0) > 0.99
		and is_zero_approx(driver._lower_body_separation_weight(&"PRONE", 1.0)),
		"ready recovery isolates standing and crouched aim frames without changing prone"
	)
	driver.set_visual_inputs(
		Vector2.DOWN, &"STANDING", deg_to_rad(20.0), deg_to_rad(-8.0), 0.0, false, 0.0,
		0.8, &"LOCOMOTION", 0.0, &"FULL", 3.0
	)
	driver._process(1.0 / 60.0)
	_expect(driver.notify_fired(), "Fire activates the upper-body hierarchy")
	for _frame in range(12):
		driver._process(1.0 / 60.0)
	var fire_snapshot: Dictionary = driver.get_animation_debug_state()
	var fire_latch: Dictionary = fire_snapshot.get("fire_upper_body_latch", {})
	var combat_ready_ccdik: Dictionary = fire_snapshot.get("combat_ready_ccdik", {})
	var fire_weapon_pose: Dictionary = fire_snapshot.get("weapon_pose", {})
	_expect(
		StringName(fire_latch.get("owner_state", &"")) == &"FIRE_RECOVERY"
		and int(fire_snapshot.get("animation_frame_rotation_override_count", -1)) == 0,
		"FIRE_RECOVERY keeps the imported mapped pose free of saved joint rotation overrides"
	)
	_expect(
		absf(float(fire_snapshot.get("applied_yaw_rad", 0.0)) - deg_to_rad(20.0)) <= 0.02
		and absf(float(fire_snapshot.get("applied_pitch_rad", 0.0)) - deg_to_rad(-8.0)) <= 0.02
		and int(fire_snapshot.get("square_idle_reference_bone_count", -1)) == 0,
		"torso-only recovery aim turns Spine, Spine1, and Spine2 toward the reticle"
	)
	_expect(
		is_zero_approx(float(fire_snapshot.get("shoulder_square_weight", 1.0)))
		and is_zero_approx(float(fire_snapshot.get("chest_square_correction_deg", 1.0))),
		"moving FIRE_RECOVERY keeps the authored square frame free of procedural clavicle correction"
	)
	_expect(
		(
			not combat_ready_ccdik.has("active_weight")
			or is_zero_approx(float(combat_ready_ccdik.get("active_weight", 0.0)))
		)
		and (
			not combat_ready_ccdik.has("modifier_influence")
			or is_zero_approx(float(combat_ready_ccdik.get("modifier_influence", 0.0)))
		),
		"FIRE_RECOVERY leaves procedural spine CCDIK inactive"
	)
	_expect(
		(
			not fire_weapon_pose.has("hand_socket_ik_enabled")
			or not bool(fire_weapon_pose.get("hand_socket_ik_enabled", true))
		)
		and bool(fire_weapon_pose.get("support_hand_socket_ik_enabled", false))
		and (
			not fire_weapon_pose.has("weapon_solver_owned")
			or not bool(fire_weapon_pose.get("weapon_solver_owned", true))
		),
		"FIRE_RECOVERY enables only support-hand contact while weapon-solver ownership stays inactive"
	)
	_expect(
		float(fire_snapshot.get("fire_upper_body_grace_seconds", 0.0)) > 1.0,
		"Fire retains upper-body ownership during the ready grace period"
	)
	var standing_latch: Dictionary = fire_snapshot.get("fire_upper_body_latch", {})
	_expect(
		StringName(standing_latch.get("owner_state", &"")) == &"FIRE_RECOVERY"
		and StringName(standing_latch.get("posture", &"")) == &"STANDING",
		"accepted standing shot enters FIRE_RECOVERY without a trigger-held owner"
	)
	var standing_fire_count := int(fire_snapshot.get("fire_trigger_count", 0))
	for _frame in range(120):
		driver.set_visual_inputs(
			Vector2.DOWN, &"STANDING", 0.0, 0.0, 0.0, true, 0.0,
			0.8, &"LOCOMOTION", 0.0, &"FULL", 3.0
		)
		driver._process(1.0 / 60.0)
	var held_snapshot: Dictionary = driver.get_animation_debug_state()
	var held_latch: Dictionary = held_snapshot.get("fire_upper_body_latch", {})
	_expect(
		not bool(held_latch.get("selected", true))
		and StringName(held_latch.get("owner_state", &"")) == &"BASE",
		"held fire input cannot extend recovery without another accepted shot"
	)
	_expect(
		int(held_snapshot.get("fire_trigger_count", -1)) == standing_fire_count,
		"standing bullets do not restart the upper-body one-shot"
	)
	driver.set_visual_inputs(
		Vector2.ZERO, &"CROUCHED", 0.0, 0.0, 0.0, true, 0.0,
		0.0, &"CROUCHED", 0.0, &"WALK", 0.0
	)
	for _frame in range(20):
		driver._process(1.0 / 60.0)
	var crouch_base_snapshot: Dictionary = driver.get_animation_debug_state()
	var crouch_base_latch: Dictionary = crouch_base_snapshot.get(
		"fire_upper_body_latch", {}
	)
	_expect(
		StringName(crouch_base_latch.get("owner_state", &"")) == &"BASE"
		and driver.current_clip == &"idle_crouch",
		"crouched held fire stays in crouched base without an accepted shot"
	)
	_expect(driver.notify_fired(), "accepted crouched shot starts recovery")
	for _frame in range(4):
		driver._process(1.0 / 60.0)
	var crouch_snapshot: Dictionary = driver.get_animation_debug_state()
	var crouch_latch: Dictionary = crouch_snapshot.get("fire_upper_body_latch", {})
	var crouch_pose: Dictionary = crouch_snapshot.get("weapon_pose", {})
	var crouch_head := Vector3(crouch_pose.get("head_position", Vector3.ZERO))
	var crouch_trigger := Vector3(crouch_pose.get("trigger_hand_target", Vector3.ZERO))
	var crouch_support := Vector3(crouch_pose.get("support_hand_target", Vector3.ZERO))
	_expect(
		StringName(crouch_latch.get("owner_state", &"")) == &"FIRE_RECOVERY"
		and StringName(crouch_latch.get("posture", &"")) == &"CROUCHED"
		and driver.current_clip == &"idle_crouch",
		"accepted crouched shot uses FIRE_RECOVERY over the crouched base"
	)
	_expect(
		crouch_trigger.y <= crouch_head.y + 0.02
		and crouch_support.y <= crouch_head.y + 0.02,
		"crouch ready hands remain below the operator head"
	)
	driver.set_visual_inputs(
		Vector2.ZERO, &"PRONE", 0.0, 0.0, 0.0, true, 0.0,
		0.0, &"PRONE", 0.0, &"WALK", 0.0
	)
	_expect(driver.notify_fired(), "accepted prone shot starts recovery")
	for _frame in range(20):
		driver._process(1.0 / 60.0)
	var prone_snapshot: Dictionary = driver.get_animation_debug_state()
	var prone_pose: Dictionary = prone_snapshot.get("weapon_pose", {})
	var prone_trigger := Vector3(prone_pose.get("trigger_hand_target", Vector3.ZERO))
	var prone_support := Vector3(prone_pose.get("support_hand_target", Vector3.ZERO))
	var prone_right_pole := Vector3(prone_pose.get("right_elbow_pole_position", Vector3.ZERO))
	var prone_left_pole := Vector3(prone_pose.get("left_elbow_pole_position", Vector3.ZERO))
	var prone_grip_ceiling := float(prone_pose.get("prone_grip_ceiling_y", INF))
	var prone_elbow_ceiling := float(prone_pose.get("prone_elbow_ceiling_y", INF))
	_expect(
		prone_trigger.y <= prone_grip_ceiling + 0.001
		and prone_support.y <= prone_grip_ceiling + 0.001,
		"prone fire hands stay inside the chest-relative height rail"
	)
	_expect(
		prone_right_pole.y <= prone_elbow_ceiling + 0.001
		and prone_left_pole.y <= prone_elbow_ceiling + 0.001,
		"prone fire elbow guides cannot rise over the chest frame"
	)
	driver.set_visual_inputs(
		Vector2.DOWN, &"STANDING", 0.0, 0.0, 0.0, false, 0.0,
		0.8, &"LOCOMOTION", 0.0, &"FULL", 3.0
	)
	for _frame in range(30):
		driver._process(1.0 / 60.0)
	var grace_snapshot: Dictionary = driver.get_animation_debug_state()
	_expect(
		StringName(
			(grace_snapshot.get("pose_pipeline", {}) as Dictionary).get(
				"active_upper_body_stage",
				&""
			)
		) == &"30_FireTorsoShoulderArms",
		"accepted shot retains the fire owner during recovery"
	)
	for _frame in range(60):
		driver._process(1.0 / 60.0)
	var released_snapshot: Dictionary = driver.get_animation_debug_state()
	_expect(
		StringName(
			(released_snapshot.get("pose_pipeline", {}) as Dictionary).get(
				"active_upper_body_stage",
				&""
			)
		) == &"10_BaseAnimation",
		"fire owner returns once after accepted-shot recovery"
	)
	var latch = driver.get("fire_upper_body_latch")
	if latch != null:
		latch.clear()
		latch.configure(1.2)
		latch.set_context(&"CROUCHED", false)
		latch.notify_accepted_shot()
		latch.advance(1.19, false)
		_expect(
			StringName(latch.owner_state()) == &"FIRE_RECOVERY"
			and StringName(latch.posture) == &"CROUCHED",
			"crouched accepted shot remains in recovery through 1.19 seconds"
		)
		latch.advance(0.02, false)
		_expect(
			StringName(latch.owner_state()) == &"BASE"
			and not latch.is_selected(),
			"fire recovery returns to crouched base after the 1.2-second boundary"
		)
		latch.notify_accepted_shot()
		latch.advance(2.0, true)
		_expect(
			float(latch.grace_remaining_seconds) > 1.0,
			"reload suspends the fire owner without consuming return grace"
		)
		_expect(
			StringName(latch.owner_state()) == &"ACTION_OVERRIDE"
			and not latch.is_selected(),
			"full-body action becomes the only upper-body owner"
		)
		latch.advance(0.25, false)
		_expect(
			StringName(latch.owner_state()) == &"FIRE_RECOVERY"
			and float(latch.grace_remaining_seconds) < 1.0,
			"action completion returns once through fire recovery"
		)
	if failures.is_empty():
		print("OPERATOR_POSE_PIPELINE_REGRESSION PASS")
		quit(0)
		return
	for failure in failures:
		push_error("OPERATOR_POSE_PIPELINE_CHECK FAIL %s" % failure)
	quit(1)


func _expect(condition: bool, message: String) -> void:
	if condition:
		print("OPERATOR_POSE_PIPELINE_CHECK PASS ", message)
	else:
		failures.append(message)
