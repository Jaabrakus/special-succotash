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
			"fire stage owns the real held-trigger latch component"
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
	var fire_layer = driver.locomotion_graph.fire_layer_node
	_expect(fire_layer != null, "fire shoulder-arm layer exists")
	var graph_root := driver.animation_tree.tree_root as AnimationNodeBlendTree
	_expect(
		graph_root != null
		and graph_root.has_node(&"crouch_upper_body")
		and graph_root.has_node(&"crouch_idle_upper_body"),
		"crouch movement and idle share the Aim Idle upper-body owner"
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
		idle_hip_trim <= driver.neutral_hip_roll_trim_deg + 0.01
		and idle_hip_output <= idle_hip_input + 0.01,
		"standing idle keeps authored pelvis direction with only a bounded roll trim"
	)
	if fire_layer != null:
		for bone_name in [
			"mixamorig_Spine", "mixamorig_Spine1", "mixamorig_Spine2",
			"mixamorig_LeftShoulder", "mixamorig_LeftArm",
			"mixamorig_LeftForeArm", "mixamorig_LeftHand",
			"mixamorig_RightShoulder", "mixamorig_RightArm",
			"mixamorig_RightForeArm", "mixamorig_RightHand",
		]:
			_expect(
				fire_layer.is_path_filtered(NodePath(".:%s" % bone_name)),
				"Fire owns %s" % bone_name
			)
		for bone_name in ["mixamorig_Hips", "mixamorig_Head"]:
			_expect(
				not fire_layer.is_path_filtered(NodePath(".:%s" % bone_name)),
				"Fire leaves %s to its earlier hierarchy stage" % bone_name
			)
	driver.set_visual_inputs(
		Vector2.DOWN, &"STANDING", 0.0, 0.0, 0.0, false, 0.0,
		0.8, &"LOCOMOTION", 0.0, &"FULL", 3.0
	)
	driver._process(1.0 / 60.0)
	_expect(driver.notify_fired(), "Fire activates the upper-body hierarchy")
	for _frame in range(4):
		driver._process(1.0 / 60.0)
	var fire_snapshot: Dictionary = driver.get_animation_debug_state()
	var pipeline_snapshot: Dictionary = fire_snapshot.get("pose_pipeline", {})
	_expect(
		StringName(pipeline_snapshot.get("active_upper_body_stage", &""))
		== &"30_FireTorsoShoulderArms",
		"Fire takes torso, shoulders, and arms from Sprint"
	)
	_expect(
		float(fire_snapshot.get("fire_upper_body_grace_seconds", 0.0)) > 1.0,
		"Fire retains upper-body ownership during the ready grace period"
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
		bool(held_latch.get("selected", false))
		and bool(held_latch.get("trigger_held", false)),
		"held automatic fire keeps one persistent upper-body owner"
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
	var crouch_snapshot: Dictionary = driver.get_animation_debug_state()
	var crouch_pose: Dictionary = crouch_snapshot.get("weapon_pose", {})
	var crouch_head := Vector3(crouch_pose.get("head_position", Vector3.ZERO))
	var crouch_trigger := Vector3(crouch_pose.get("trigger_hand_target", Vector3.ZERO))
	var crouch_support := Vector3(crouch_pose.get("support_hand_target", Vector3.ZERO))
	_expect(
		crouch_trigger.y <= crouch_head.y + 0.02
		and crouch_support.y <= crouch_head.y + 0.02,
		"crouch ready hands remain below the operator head"
	)
	driver.set_visual_inputs(
		Vector2.ZERO, &"PRONE", 0.0, 0.0, 0.0, true, 0.0,
		0.0, &"PRONE", 0.0, &"WALK", 0.0
	)
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
		"trigger release retains the fire owner during grace"
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
		"fire owner returns once after trigger release and grace"
	)
	var latch = driver.get("fire_upper_body_latch")
	if latch != null:
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
