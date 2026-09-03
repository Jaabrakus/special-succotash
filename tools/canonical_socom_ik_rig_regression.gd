extends SceneTree

const RIG_PATH := "res://config/operator_rig.json"

var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var rig := _load_json(RIG_PATH)
	_expect(
		String(rig.get("scene_path", ""))
		== "res://scenes/player/canonical_socom_operator_rig.tscn",
		"editor-authored canonical SOCOM hierarchy is the live rig"
	)
	_expect(
		bool(rig.get("scene_is_authored_wrapper", false)),
		"canonical runtime consumes the saved editor wrapper"
	)
	_expect(
		String(rig.get("ik_control_scene_path", ""))
		== "res://scenes/player/socom_ik_control_graph.tscn",
		"editable Godot IK controls load as a separate scene"
	)
	_expect(not bool(rig.get("strict_authored_pose", true)), "canonical layered pose mode is active")
	_expect(not bool(rig.get("debug_skeleton_visible", true)), "runtime skeleton debug drawing is disabled")
	var packed := load("res://main.tscn") as PackedScene
	_expect(packed != null, "canonical main scene loads")
	if packed == null:
		_finish()
		return
	var scene := packed.instantiate()
	root.add_child(scene)
	for _frame in range(75):
		await process_frame
	var driver := scene.get_node_or_null("Player/Mannequin/ProductionAnimation")
	_expect(driver != null, "canonical production animation driver is live")
	if driver == null:
		_finish()
		return
	var model_root := driver.get("model_root") as Node3D
	var skeleton := driver.get("skeleton") as Skeleton3D
	var solver: Variant = driver.get("weapon_pose_solver")
	_expect(
		model_root != null and model_root.name == "CanonicalSocomOperatorRig",
		"AGLS character replacement is not instantiated"
	)
	_expect(skeleton != null and skeleton.get_bone_count() >= 65, "canonical 65-bone contract is intact")
	if skeleton == null or model_root == null:
		_finish()
		return
	_expect(
		String(skeleton.get_meta("socom_source_rig", "")) != "agls_native_69",
		"live skeleton is not the incompatible AGLS skeleton"
	)
	_expect(skeleton.get_node_or_null("AglsSkeletonVisual") == null, "no cyan debug skeleton can render in play")
	var graph := driver.get("ik_control_graph") as Node3D
	_expect(graph != null, "canonical scene contains the imported Godot IK control graph")
	_expect(graph != null and not graph.visible, "runtime hides TargetPivot calibration handles")
	for node_path in [
		"TargetPivot/RHUpperArmWeaponTarget",
		"TargetPivot/RHWeaponTarget",
		"TargetPivot/LHWeaponContactTarget",
		"TargetPivot/SpineTargetWeaponAim",
		"LHPoleAnchor/LHPoleTarget",
	]:
		_expect(graph != null and graph.get_node_or_null(node_path) is Marker3D, "IK control exists: %s" % node_path)
	var native_aim_runtime: Variant = driver.get("godot_ik_aim_runtime")
	if native_aim_runtime != null and graph != null:
		_expect(
			native_aim_runtime.get("right_hand_target") == graph.get_node("TargetPivot/RHWeaponTarget")
			and native_aim_runtime.get("left_hand_target") == graph.get_node("TargetPivot/LHWeaponContactTarget")
			and native_aim_runtime.get("spine_target") == graph.get_node("TargetPivot/SpineTargetWeaponAim"),
			"live hand and spine consumers use the authored scene controls"
		)
	skeleton.force_update_all_bone_transforms()
	var head := _bone_world(skeleton, &"mixamorig_Head")
	var hips := _bone_world(skeleton, &"mixamorig_Hips")
	var left_foot := _bone_world(skeleton, &"mixamorig_LeftFoot")
	var right_foot := _bone_world(skeleton, &"mixamorig_RightFoot")
	var feet := (left_foot + right_foot) * 0.5
	var height := head.distance_to(feet)
	print("CANONICAL_IK_RIG_METRIC head=%s hips=%s feet=%s height=%.4f" % [head, hips, feet, height])
	_expect(height >= 1.20 and height <= 2.20, "rendered skeleton stays human-sized")
	_expect(head.y > hips.y and hips.y > feet.y, "rendered skeleton stays upright")
	for pair in [
		[&"mixamorig_LeftArm", &"mixamorig_LeftForeArm"],
		[&"mixamorig_LeftForeArm", &"mixamorig_LeftHand"],
		[&"mixamorig_RightArm", &"mixamorig_RightForeArm"],
		[&"mixamorig_RightForeArm", &"mixamorig_RightHand"],
	]:
		_expect(
			_bone_world(skeleton, pair[0]).distance_to(_bone_world(skeleton, pair[1])) < 0.75,
			"arm segment is not exploded: %s" % [pair]
		)
	var player := scene.get_node("Player") as CharacterBody3D
	var mannequin := player.get_node("Mannequin") as Node3D
	# Stop only the mannequin's automatic input copy so this focused proof can
	# feed deterministic presentation state. The production driver keeps running.
	mannequin.set_process(false)
	driver.call(
		"set_visual_inputs",
		Vector2(0.0, 1.0), &"STANDING", 0.0, 0.0, 1.0, false, 0.0,
		0.65, &"LOCOMOTION", 0.0, &"WALK", 2.0,
		player.global_position + Vector3(0.0, 1.35, -25.0),
		Vector2(0.0, 1.0), 1.0, &"SUSTAINED", 0.0
	)
	for _frame in range(8):
		await process_frame
	var spine_target := graph.get_node("TargetPivot/SpineTargetWeaponAim") as Marker3D
	_expect(
		spine_target.global_position.distance_to(player.global_position) < 4.0,
		"spine target stays body-local instead of following the distant reticle ray"
	)
	var active_weapon := driver.get("weapon_node") as Node3D
	_expect(bool(mannequin.call("notify_operator_fired")), "accepted fire reaches canonical presentation")
	for _frame in range(12):
		await process_frame
	var fire_snapshot: Dictionary = driver.call("get_animation_debug_state")
	print(
		"CANONICAL_IK_RIG_METRIC fire right_arm=%.3f connected_arm=%.3f left_hand=%.3f" % [
			float(native_aim_runtime.get("right_arm_copy").influence),
			float(native_aim_runtime.get("target_pivot_arm_aim").influence),
			float(native_aim_runtime.get("left_hand_ik").influence),
		]
	)
	var connected_arm_aim: Variant = native_aim_runtime.get("target_pivot_arm_aim")
	print(
		"CANONICAL_IK_RIG_METRIC connected_arm count=%d modifier_dot=%.5f arm=%s hand=%s" % [
			int(connected_arm_aim.get("process_count")),
			float(connected_arm_aim.get("last_aim_dot")),
			connected_arm_aim.get("last_arm_origin"),
			connected_arm_aim.get("last_hand_origin"),
		]
	)
	_expect(
		String((fire_snapshot.get("last_event_presentation", {}) as Dictionary).get("event", ""))
		== "FIRE_ACCEPTED",
		"combat fire routes through the canonical AnimationTree"
	)
	_expect(
		float(connected_arm_aim.get("influence")) > 0.90
		and int(connected_arm_aim.get("process_count")) > 0
		and float(native_aim_runtime.get("right_arm_copy").influence) < 0.05
		and float(native_aim_runtime.get("left_hand_ik").influence) > 0.90
		and float(native_aim_runtime.get("left_hand_copy").influence) > 0.90
		and float(native_aim_runtime.get("spine_ik").influence) > 0.90
		and float(native_aim_runtime.get("weapon_hand_attachment").influence) > 0.45
		and int(native_aim_runtime.get("weapon_hand_attachment").get("process_count")) > 0,
		"combat mode activates the complete TargetPivot presentation graph"
	)
	var standing_barrel_direction: Vector3 = mannequin.call("get_active_barrel_direction")
	var standing_aim_direction := (
		player.global_position + Vector3(0.0, 1.35, -25.0)
		- (_find_named_node(active_weapon, "Socket_Muzzle") as Node3D).global_position
	).normalized()
	var restored_pose_trigger_error := (
		(_find_named_node(active_weapon, "Socket_RightHand") as Node3D).global_position
		.distance_to(_bone_world(skeleton, &"mixamorig_RightHand"))
	)
	var standing_trigger_error := float(
		native_aim_runtime.get("weapon_hand_attachment").get(
			"last_trigger_contact_error"
		)
	)
	print(
		"CANONICAL_IK_RIG_METRIC ready_barrel=%s aim_dot=%.5f modifier_trigger_error=%.5f restored_pose_delta=%.5f"
		% [
			standing_barrel_direction,
			standing_barrel_direction.normalized().dot(standing_aim_direction),
			standing_trigger_error,
			restored_pose_trigger_error,
		]
	)
	_expect(
		absf(standing_barrel_direction.dot(Vector3.UP)) < 0.10
		and standing_barrel_direction.normalized().dot(standing_aim_direction) > 0.99,
		"combat-ready M4 bore is horizontal and follows the shared aim point"
	)
	_expect(
		standing_trigger_error <= 0.01,
		"combat-ready M4 trigger socket remains attached to the right hand"
	)
	print("CANONICAL_IK_RIG_METRIC standing_fire right_hand=%s left_hand=%s right_target=%s left_target=%s" % [
		_bone_world(skeleton, &"mixamorig_RightHand"),
		_bone_world(skeleton, &"mixamorig_LeftHand"),
		(native_aim_runtime.get("right_hand_target") as Node3D).global_position,
		(native_aim_runtime.get("left_hand_target") as Node3D).global_position,
	])
	print("CANONICAL_IK_RIG_METRIC standing_basis hand=%s target=%s" % [
		(skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone(&"mixamorig_RightHand"))).basis,
		(native_aim_runtime.get("right_hand_target") as Node3D).global_basis,
	])
	_expect(
		bool(driver.call("play_semantic_action", &"reload", 0.12)),
		"standing reload enters the canonical action graph"
	)
	for _frame in range(4):
		await process_frame
	var reload_snapshot: Dictionary = driver.call("get_animation_debug_state")
	print(
		"CANONICAL_IK_RIG_METRIC reload upper=%s clip=%s requested=%s" % [
			reload_snapshot.get("upper_body_reload_layer", false),
			reload_snapshot.get("logical_clip", &""),
			driver.get("requested_action"),
		]
	)
	_expect(
		bool(reload_snapshot.get("upper_body_reload_layer", false))
		and StringName(reload_snapshot.get("logical_clip", &"")) == &"run_forward",
		"reload owns the torso while locomotion keeps the moving legs"
	)
	var reload_action := StringName(driver.get("requested_action"))
	var reload_remaining_before := float(driver.get("requested_action_remaining"))
	for transition_case in [
		{
			"label": "crouched movement",
			"posture": &"CROUCHED",
			"state": &"LOCOMOTION",
			"vertical_speed": 0.0,
		},
		{
			"label": "airborne movement",
			"posture": &"CROUCHED",
			"state": &"AIRBORNE",
			"vertical_speed": 4.0,
		},
		{
			"label": "prone movement",
			"posture": &"PRONE",
			"state": &"LOCOMOTION",
			"vertical_speed": 0.0,
		},
	]:
		driver.call(
			"set_visual_inputs",
			Vector2(0.0, 1.0), transition_case["posture"], 0.0, 0.0,
			1.0, false, 0.0, 0.65, transition_case["state"],
			transition_case["vertical_speed"], &"WALK", 2.0,
			player.global_position + Vector3(0.0, 1.35, -25.0),
			Vector2(0.0, 1.0), 1.0, &"SUSTAINED", 0.0
		)
		for _frame in range(3):
			await process_frame
		var transition_snapshot: Dictionary = driver.call("get_animation_debug_state")
		_expect(
			StringName(driver.get("requested_action")) == reload_action
			and bool(transition_snapshot.get("upper_body_reload_layer", false)),
			"authored reload continues through %s" % transition_case["label"]
		)
		_expect(
			StringName(transition_snapshot.get("logical_clip", &"")) != reload_action,
			"%s remains the lower-body animation under reload" % transition_case["label"]
		)
	_expect(
		float(driver.get("requested_action_remaining")) < reload_remaining_before
		and float(driver.get("requested_action_remaining")) > 0.0,
		"reload animation playhead advances without restart across state changes"
	)
	_expect(
		float(native_aim_runtime.get("right_arm_copy").influence) < 0.05
		and float(native_aim_runtime.get("left_hand_ik").influence) < 0.05,
		"authored reload releases combat-ready hand IK while it plays"
	)
	_expect(bool(driver.call("cancel_reload_action")), "focused proof can end the active reload")
	driver.call(
		"set_visual_inputs",
		Vector2(0.0, 1.0), &"STANDING", 0.0, 0.0, 1.0, false, 0.0,
		0.65, &"AIRBORNE", 4.0, &"WALK", 2.0,
		player.global_position + Vector3(0.0, 1.35, -25.0),
		Vector2(0.0, 1.0), 1.0, &"SUSTAINED", 0.0
	)
	_expect(bool(mannequin.call("notify_operator_fired")), "accepted airborne fire reaches presentation")
	for _frame in range(12):
		await process_frame
	var airborne_fire_snapshot: Dictionary = driver.call("get_animation_debug_state")
	_expect(
		StringName(airborne_fire_snapshot.get("gameplay_state", &"")) == &"AIRBORNE"
		and bool(airborne_fire_snapshot.get("presentation_fire_selected", false)),
		"jump legs continue under the combat-ready fire pose"
	)
	_expect(
		float(native_aim_runtime.get("right_arm_copy").influence) < 0.05
		and float(native_aim_runtime.get("target_pivot_arm_aim").influence) > 0.90
		and float(native_aim_runtime.get("left_hand_ik").influence) > 0.90
		and float(native_aim_runtime.get("left_hand_copy").influence) > 0.90
		and float(native_aim_runtime.get("spine_ik").influence) > 0.90
		and float(native_aim_runtime.get("weapon_hand_attachment").influence) > 0.45,
		"airborne combat mode activates TargetPivot over locomotion legs"
	)
	print("CANONICAL_IK_RIG_METRIC mount bone=%s mode=%s parent=%s local=%s" % [
		String((driver.get("weapon_attachment") as BoneAttachment3D).bone_name),
		String((driver.get("equipped_weapon_config") as Dictionary).get("operator_mount", {}).get("attachment_mode", "")),
		String(active_weapon.get_parent().name) if active_weapon != null else "missing",
		active_weapon.transform if active_weapon != null else Transform3D.IDENTITY,
	])
	print("CANONICAL_IK_RIG_METRIC mount_world=%s right_hand_world=%s socket_world=%s" % [
		(driver.get("weapon_attachment") as BoneAttachment3D).global_position,
		_bone_world(skeleton, &"mixamorig_RightHand"),
		(_find_named_node(active_weapon, "Socket_RightHand") as Node3D).global_position,
	])
	print("CANONICAL_IK_RIG_METRIC hand_mount_modifier count=%s last_hand=%s influence=%s" % [
		native_aim_runtime.get("weapon_hand_attachment").get("process_count"),
		native_aim_runtime.get("weapon_hand_attachment").get("last_trigger_hand_world"),
		native_aim_runtime.get("weapon_hand_attachment").get("influence"),
	])
	var runtime_library := driver.get("dynamic_anim_lib") as AnimationLibrary
	for audit_clip in [&"aim_idle_m4a1", &"jump_up", &"jump_loop", &"combat_fire", &"reload_m4a1"]:
		print("CANONICAL_IK_RIG_TRACKS %s %s" % [
			audit_clip,
			_animation_track_summary(
				runtime_library,
				audit_clip,
				[&"ik_hand_gun", &"mixamorig_RightArm", &"mixamorig_RightHand", &"mixamorig_LeftHand"]
			),
		])
	var trigger_socket := _find_named_node(active_weapon, "Socket_RightHand") as Node3D
	var support_socket := _find_named_node(active_weapon, "Socket_LeftHand") as Node3D
	var airborne_trigger_error := float(
		native_aim_runtime.get("weapon_hand_attachment").get(
			"last_trigger_contact_error"
		)
	)
	var airborne_support_error := (
		support_socket.global_position.distance_to(_bone_world(skeleton, &"mixamorig_LeftHand"))
		if support_socket != null else INF
	)
	print(
		"CANONICAL_IK_RIG_METRIC airborne trigger_error=%.4f support_error=%.4f weapon=%s right_hand=%s left_hand=%s jump_upper=%s jump_ready=%s tree_state=%s" % [
			airborne_trigger_error,
			airborne_support_error,
			active_weapon.global_position if active_weapon != null else Vector3.ZERO,
			_bone_world(skeleton, &"mixamorig_RightHand"),
			_bone_world(skeleton, &"mixamorig_LeftHand"),
			driver.get("animation_tree").get("parameters/modern_state_jump_loop_upper_body/blend_amount"),
			driver.get("animation_tree").get("parameters/modern_state_jump_loop_ready/blend_amount"),
			driver.get("locomotion_graph").get("current_state"),
		]
	)
	print("CANONICAL_IK_RIG_METRIC airborne_left shoulder=%s elbow=%s hand=%s target=%s reach=%.4f target_distance=%.4f" % [
		_bone_world(skeleton, &"mixamorig_LeftArm"),
		_bone_world(skeleton, &"mixamorig_LeftForeArm"),
		_bone_world(skeleton, &"mixamorig_LeftHand"),
		(native_aim_runtime.get("left_hand_target") as Node3D).global_position,
		_bone_world(skeleton, &"mixamorig_LeftArm").distance_to(_bone_world(skeleton, &"mixamorig_LeftForeArm")) + _bone_world(skeleton, &"mixamorig_LeftForeArm").distance_to(_bone_world(skeleton, &"mixamorig_LeftHand")),
		_bone_world(skeleton, &"mixamorig_LeftArm").distance_to((native_aim_runtime.get("left_hand_target") as Node3D).global_position),
	])
	var clip_paths: Dictionary = driver.get("clip_paths")
	_expect(
		String(clip_paths.get(&"run_forward", "")).begins_with("res://assets/animations/mixamo/"),
		"canonical locomotion remains on the compatible base skeleton"
	)
	_expect(
		String(clip_paths.get(&"reload_m4a1", "")).contains("/agls_intake/imported/weapon_reload/"),
		"selected AGLS reload remains an action source"
	)
	var runtime_player := driver.get("animation_player") as AnimationPlayer
	if runtime_player != null:
		runtime_player.stop()
	driver.set_process(false)
	skeleton.reset_bone_poses()
	skeleton.force_update_all_bone_transforms()
	var bind_error := _maximum_rest_bind_error(model_root, skeleton)
	print("CANONICAL_IK_RIG_METRIC maximum_rest_bind_error=%.8f" % bind_error)
	_expect(bind_error <= 0.001, "canonical Skin bind matches the canonical skeleton rest")
	scene.queue_free()
	_finish()


func _bone_world(skeleton: Skeleton3D, bone_name: StringName) -> Vector3:
	var index := skeleton.find_bone(bone_name)
	return (
		(skeleton.global_transform * skeleton.get_bone_global_pose(index)).origin
		if index >= 0 else Vector3.ZERO
	)


func _find_named_node(node: Node, wanted_name: String) -> Node:
	if node == null:
		return null
	if node.name == wanted_name:
		return node
	for child in node.get_children():
		var found := _find_named_node(child, wanted_name)
		if found != null:
			return found
	return null


func _animation_track_summary(
	library: AnimationLibrary,
	clip_name: StringName,
	bone_names: Array[StringName]
) -> Dictionary:
	var result: Dictionary = {}
	if library == null or not library.has_animation(clip_name):
		return result
	var animation := library.get_animation(clip_name)
	for bone_name in bone_names:
		result[String(bone_name)] = []
	for track_index in animation.get_track_count():
		var path_text := String(animation.track_get_path(track_index))
		for bone_name in bone_names:
			if not path_text.ends_with(":%s" % bone_name):
				continue
			(result[String(bone_name)] as Array).append({
				"type": animation.track_get_type(track_index),
				"path": path_text,
				"keys": animation.track_get_key_count(track_index),
			})
	return result


func _load_json(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed as Dictionary if parsed is Dictionary else {}


func _maximum_rest_bind_error(node: Node, runtime_skeleton: Skeleton3D) -> float:
	var maximum := 0.0
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.skin != null:
			for bind_index in mesh_instance.skin.get_bind_count():
				var bone_index := runtime_skeleton.find_bone(
					String(mesh_instance.skin.get_bind_name(bind_index))
				)
				if bone_index < 0:
					continue
				var combined := (
					runtime_skeleton.get_bone_global_pose(bone_index)
					* mesh_instance.skin.get_bind_pose(bind_index)
				)
				maximum = maxf(maximum, combined.origin.length())
				for axis in [combined.basis.x, combined.basis.y, combined.basis.z]:
					maximum = maxf(maximum, absf(axis.length() - 1.0))
	for child in node.get_children():
		maximum = maxf(maximum, _maximum_rest_bind_error(child, runtime_skeleton))
	return maximum


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("CANONICAL_IK_RIG PASS %s" % label)
		return
	failures.append(label)
	push_error("CANONICAL_IK_RIG FAIL %s" % label)


func _finish() -> void:
	if failures.is_empty():
		print("CANONICAL_SOCOM_IK_RIG_REGRESSION PASS")
		quit(0)
		return
	print("CANONICAL_SOCOM_IK_RIG_REGRESSION FAIL %s" % [failures])
	quit(1)
