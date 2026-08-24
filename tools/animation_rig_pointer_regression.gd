extends SceneTree

var failures: Array[String] = []


func _initialize() -> void:
	var packed := load("res://animation_library_lab.tscn") as PackedScene
	_expect(packed != null, "Animation Studio scene loads")
	if packed == null:
		_finish()
		return
	var studio := packed.instantiate()
	root.add_child(studio)
	await process_frame
	await process_frame
	studio.call("_show_editor_page", "Pose")
	await process_frame
	await process_frame
	_expect(
		not bool(studio.get("animation_correction_enabled")),
		"Rig & Hands opens on the raw imported animation"
	)
	var overlay := studio.find_child("AnimationStudioGunsmithRigOverlay", true, false)
	var camera := studio.get("camera") as Camera3D
	_expect(overlay != null and camera != null, "live rig overlay and camera exist")
	if overlay == null or camera == null:
		_finish()
		return
	var played_ready: bool = studio.call(
		"_play_state_resource",
		"res://assets/animations/mixamo/Shooter Pack/rifle aiming idle.fbx",
		0.0
	)
	_expect(played_ready, "canonical rifle aim-idle clip plays before rig assertions")
	await process_frame
	await process_frame
	await _verify_raw_pause_fidelity(studio)
	studio.call("_toggle_animation_correction_overlay", true)
	await process_frame
	await _verify_pause_weapon_isolation(studio)
	await _verify_support_forearm_integrity(studio)
	studio.call("_select_animation_rig_target", &"placement_origin")
	await process_frame
	await _verify_ready_grip_contacts(studio)
	studio.call("_toggle_animation_elbow_guides", true)
	await _drag_marker(
		studio, overlay, camera, "placement_origin", &"placement_origin",
		"correction_placement_position", Vector2(24.0, -16.0)
	)
	await _verify_locked_direction(studio, overlay, camera)
	await _drag_marker(
		studio, overlay, camera, "left_hand", &"left_hand",
		"correction_left_hand", Vector2(-18.0, 10.0)
	)
	await _drag_marker(
		studio, overlay, camera, "left_elbow_pole", &"left_elbow_pole",
		"correction_left_elbow", Vector2(-18.0, 10.0)
	)
	var thigh_marker := studio.find_child("FineJoint_left_upper_leg", true, false) as Node3D
	_expect(thigh_marker != null, "small skeleton joint exists for direct manipulation")
	if thigh_marker:
		await _drag_joint_marker(studio, camera, thigh_marker, Vector2(22.0, -14.0))
	_finish()


func _verify_raw_pause_fidelity(studio: Node) -> void:
	var skeleton := studio.get("skeleton") as Skeleton3D
	_expect(skeleton != null, "raw-pose fidelity check resolves the operator skeleton")
	if skeleton == null:
		return
	studio.call("_pause_for_pose_edit")
	await process_frame
	var paused_poses: Array[Transform3D] = []
	for bone_index in range(skeleton.get_bone_count()):
		paused_poses.append(skeleton.get_bone_pose(bone_index))
	for _frame in range(5):
		await process_frame
	var changed_bones := 0
	for bone_index in range(skeleton.get_bone_count()):
		if not skeleton.get_bone_pose(bone_index).is_equal_approx(paused_poses[bone_index]):
			changed_bones += 1
	_expect(
		changed_bones == 0,
		"pausing with corrections OFF preserves every imported bone (%d changed)" % changed_bones
	)


func _verify_pause_weapon_isolation(studio: Node) -> void:
	var weapon := studio.get("weapon_node") as Node3D
	var hand_attachment := studio.get("socket_attachment") as BoneAttachment3D
	_expect(
		weapon != null and weapon.get_parent() == hand_attachment,
		"playing animation keeps the rifle on the Gunsmith hand mount"
	)
	if weapon == null or hand_attachment == null:
		return
	var canonical_mount := weapon.transform
	studio.call("_toggle_play_pause")
	await process_frame
	_expect(
		weapon.get_parent() == hand_attachment,
		"pausing keeps the rifle on the authored right hand"
	)
	for _frame in range(5):
		await process_frame
	_expect(
		weapon.get_parent() == hand_attachment
		and weapon.transform.is_equal_approx(canonical_mount),
		"paused correction cannot rewrite the Gunsmith hand mount"
	)
	studio.call("_toggle_play_pause")
	await process_frame
	_expect(
		weapon.get_parent() == hand_attachment
		and weapon.transform.is_equal_approx(canonical_mount),
		"resuming preserves the exact Gunsmith right-hand mount"
	)
	studio.call("_pause_for_pose_edit")
	await process_frame


func _verify_support_forearm_integrity(studio: Node) -> void:
	var skeleton := studio.get("skeleton") as Skeleton3D
	_expect(skeleton != null, "paused pose exposes the operator skeleton")
	if skeleton == null:
		return
	var forearm_index := _find_bone(skeleton, [
		"mixamorig_LeftForeArm", "mixamorig:LeftForeArm", "ArmLower.L",
	])
	var hand_index := _find_bone(skeleton, [
		"mixamorig_LeftHand", "mixamorig:LeftHand", "Hand.L.001",
	])
	_expect(
		forearm_index >= 0 and hand_index >= 0,
		"support forearm and hand bones resolve for integrity checks"
	)
	if forearm_index < 0 or hand_index < 0:
		return
	for _frame in range(3):
		await process_frame
	var forearm_pose := skeleton.get_bone_pose(forearm_index)
	var hand_pose := skeleton.get_bone_pose(hand_index)
	var forearm_scale := forearm_pose.basis.get_scale()
	var hand_scale := hand_pose.basis.get_scale()
	_expect(
		forearm_scale.distance_to(Vector3.ONE) < 0.02,
		"support forearm IK keeps a rotation-only bone basis (%s)" % forearm_scale
	)
	_expect(
		hand_scale.distance_to(Vector3.ONE) < 0.02,
		"support hand IK strips inherited target scale and shear (%s)" % hand_scale
	)


func _verify_ready_grip_contacts(studio: Node) -> void:
	var skeleton := studio.get("skeleton") as Skeleton3D
	var left_target := studio.get("left_hand_marker") as Marker3D
	var right_target := studio.get("right_hand_marker") as Marker3D
	_expect(
		skeleton != null and left_target != null and right_target != null,
		"ready pose exposes both authored weapon grip targets"
	)
	if skeleton == null or left_target == null or right_target == null:
		return
	var left_index := _find_bone(skeleton, [
		"mixamorig_LeftHand", "mixamorig:LeftHand", "Hand.L.001",
	])
	var right_index := _find_bone(skeleton, [
		"mixamorig_RightHand", "mixamorig:RightHand", "Hand.R.001",
	])
	_expect(left_index >= 0 and right_index >= 0, "ready pose resolves both hand bones")
	if left_index < 0 or right_index < 0:
		return
	var left_world := (
		skeleton.global_transform * skeleton.get_bone_global_pose(left_index)
	).origin
	var right_world := (
		skeleton.global_transform * skeleton.get_bone_global_pose(right_index)
	).origin
	var left_gap := left_world.distance_to(left_target.global_position)
	var right_gap := right_world.distance_to(right_target.global_position)
	_expect(
		is_finite(left_gap),
		"support-hand grip distance remains measurable without relocating the rifle"
	)
	_expect(right_gap < 0.16, "right hand remains connected to its rifle grip (%.3f m)" % right_gap)


func _find_bone(skeleton: Skeleton3D, candidates: Array[String]) -> int:
	for candidate in candidates:
		var index := skeleton.find_bone(candidate)
		if index >= 0:
			return index
	return -1


func _drag_marker(
	studio: Node,
	overlay: Node,
	camera: Camera3D,
	marker_id: String,
	target_id: StringName,
	property_name: String,
	delta: Vector2
) -> void:
	var marker_position: Vector3 = overlay.call("target_position", StringName(marker_id))
	var screen_position := camera.unproject_position(marker_position)
	var stage := studio.get("stage_input_surface") as Control
	_expect(stage != null and stage.get_global_rect().has_point(screen_position), "%s is inside the stage input surface at %s" % [marker_id, screen_position])
	_expect(
		not studio.call("_pointer_over_animation_editor_ui", screen_position),
		"%s is exposed in the 3D workbench" % marker_id
	)
	var before: Vector3 = studio.get(property_name)
	var elbow_before := Vector3.ZERO
	var elbow_bone_index := -1
	var opposite_elbow_before := Vector3.ZERO
	var opposite_elbow_bone_index := -1
	var weapon_before := Vector3.ZERO
	var weapon_parent_before: Node
	var weapon := studio.get("weapon_node") as Node3D
	var skeleton := studio.get("skeleton") as Skeleton3D
	if skeleton and target_id in [&"right_elbow_pole", &"left_elbow_pole"]:
		var side := "Right" if target_id == &"right_elbow_pole" else "Left"
		var opposite_side := "Left" if side == "Right" else "Right"
		for bone_name in ["mixamorig_%sForeArm" % side, "mixamorig:%sForeArm" % side, "ArmLower.%s" % ("R" if side == "Right" else "L")]:
			elbow_bone_index = skeleton.find_bone(bone_name)
			if elbow_bone_index >= 0:
				break
		if elbow_bone_index >= 0:
			elbow_before = (skeleton.global_transform * skeleton.get_bone_global_pose(elbow_bone_index)).origin
		for bone_name in ["mixamorig_%sForeArm" % opposite_side, "mixamorig:%sForeArm" % opposite_side, "ArmLower.%s" % ("R" if opposite_side == "Right" else "L")]:
			opposite_elbow_bone_index = skeleton.find_bone(bone_name)
			if opposite_elbow_bone_index >= 0:
				break
		if opposite_elbow_bone_index >= 0:
			opposite_elbow_before = (skeleton.global_transform * skeleton.get_bone_global_pose(opposite_elbow_bone_index)).origin
		if weapon:
			weapon_before = weapon.global_position
			weapon_parent_before = weapon.get_parent()
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = screen_position
	press.global_position = screen_position
	_dispatch_pointer_event(stage, press)
	await process_frame
	var selected_target: StringName = studio.get("animation_rig_selected_target")
	_expect(
		selected_target == target_id,
		"real viewport click selects %s (selected %s)" % [marker_id, selected_target]
	)
	if weapon and target_id in [&"right_elbow_pole", &"left_elbow_pole"]:
		_expect(
			weapon.get_parent() == weapon_parent_before,
			"%s leaves rifle ownership on the authored right hand" % marker_id
		)
	var motion := InputEventMouseMotion.new()
	motion.position = screen_position + delta
	motion.global_position = motion.position
	motion.relative = delta
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	_dispatch_pointer_event(stage, motion)
	await process_frame
	if skeleton and opposite_elbow_bone_index >= 0:
		var opposite_elbow_during := (
			skeleton.global_transform
			* skeleton.get_bone_global_pose(opposite_elbow_bone_index)
		).origin
		var opposite_arm_motion := opposite_elbow_during.distance_to(
			opposite_elbow_before
		)
		_expect(
			opposite_arm_motion < 0.001,
			"%s leaves the opposite arm isolated during its drag (%.6f m)" % [
				marker_id, opposite_arm_motion,
			]
		)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = motion.position
	release.global_position = motion.position
	_dispatch_pointer_event(stage, release)
	await process_frame
	var after: Vector3 = studio.get(property_name)
	_expect(not after.is_equal_approx(before), "real viewport drag changes %s" % marker_id)
	if skeleton and elbow_bone_index >= 0:
		await process_frame
		var elbow_after := (skeleton.global_transform * skeleton.get_bone_global_pose(elbow_bone_index)).origin
		var elbow_motion := elbow_after.distance_to(elbow_before)
		_expect(
			elbow_motion > 0.001,
			"%s visibly moves the operator elbow (%.6f m)" % [marker_id, elbow_motion]
		)
		if weapon:
			var weapon_motion := weapon.global_position.distance_to(weapon_before)
			_expect(
				weapon.get_parent() == weapon_parent_before,
				"%s preserves rifle ownership after release" % marker_id
			)
			_expect(
				weapon_motion < 0.02,
				"%s does not visibly relocate the rifle (%.6f m)" % [
					marker_id, weapon_motion,
				]
			)


func _dispatch_pointer_event(stage: Control, event: InputEvent) -> void:
	# Deliver through the same Control.gui_input signal the OS-backed viewport
	# emits for a real click. Input.parse_input_event is queued and can use a
	# stale projected marker position after the IK preview updates its arm.
	stage.emit_signal("gui_input", event)


func _verify_locked_direction(studio: Node, overlay: Node, camera: Camera3D) -> void:
	var marker_position: Vector3 = overlay.call("target_position", &"placement_direction")
	var screen_position := camera.unproject_position(marker_position)
	var stage := studio.get("stage_input_surface") as Control
	var before: Vector3 = studio.get("correction_placement_rotation")
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = screen_position
	press.global_position = screen_position
	_dispatch_pointer_event(stage, press)
	await process_frame
	_expect(studio.get("animation_rig_selected_target") == &"placement_direction", "far blue dot remains selectable as the reticle-lock indicator")
	var motion := InputEventMouseMotion.new()
	motion.position = screen_position + Vector2(20.0, -12.0)
	motion.global_position = motion.position
	motion.relative = Vector2(20.0, -12.0)
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	_dispatch_pointer_event(stage, motion)
	await process_frame
	var after: Vector3 = studio.get("correction_placement_rotation")
	_expect(after.is_equal_approx(before), "far blue dot cannot drift away from the reticle")
	var origin: Vector3 = studio.call("_animation_placement_origin_world")
	var direction: Vector3 = studio.call("_animation_placement_direction_world")
	var center: Vector2 = studio.call("_animation_workbench_center_screen")
	var ray_origin := camera.project_ray_origin(center)
	var ray_direction := camera.project_ray_normal(center).normalized()
	var target := ray_origin + ray_direction * 120.0
	var projected := camera.unproject_position(origin + direction * origin.distance_to(target))
	_expect(projected.distance_to(center) <= 0.5, "blue yaw/pitch direction always points to the workbench reticle")
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = motion.position
	release.global_position = motion.position
	_dispatch_pointer_event(stage, release)
	await process_frame


func _drag_joint_marker(
	studio: Node,
	camera: Camera3D,
	marker: Node3D,
	delta: Vector2
) -> void:
	var stage := studio.get("stage_input_surface") as Control
	var screen_position := camera.unproject_position(marker.global_position)
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = screen_position
	press.global_position = screen_position
	_dispatch_pointer_event(stage, press)
	await process_frame
	var selected_bone := String(studio.get("selected_pose_bone"))
	_expect("upleg" in selected_bone.to_lower() or "upperleg" in selected_bone.to_lower(), "real viewport click selects the small thigh joint")
	var before: Vector3 = (studio.get("bone_rot_offsets") as Dictionary).get(selected_bone, Vector3.ZERO)
	var motion := InputEventMouseMotion.new()
	motion.position = screen_position + delta
	motion.global_position = motion.position
	motion.relative = delta
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	_dispatch_pointer_event(stage, motion)
	await process_frame
	var after: Vector3 = (studio.get("bone_rot_offsets") as Dictionary).get(selected_bone, Vector3.ZERO)
	_expect(not after.is_equal_approx(before), "press-drag directly moves the selected skeleton joint")
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = motion.position
	release.global_position = motion.position
	_dispatch_pointer_event(stage, release)
	await process_frame


func _expect(condition: bool, message: String) -> void:
	if condition:
		print("ANIMATION_RIG_POINTER_CHECK PASS ", message)
		return
	failures.append(message)
	push_error("ANIMATION_RIG_POINTER_CHECK FAIL " + message)


func _finish() -> void:
	if failures.is_empty():
		print("ANIMATION_RIG_POINTER_REGRESSION PASS")
		quit(0)
		return
	print("ANIMATION_RIG_POINTER_REGRESSION FAIL count=", failures.size())
	quit(1)
