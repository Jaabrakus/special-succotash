extends "res://scripts/player/operator_weapon_pose_ready.gd"

func bind(target_skeleton: Skeleton3D, attached_weapon: Node3D) -> void:
	skeleton = target_skeleton
	weapon_node = attached_weapon
	weapon_animation_parent = weapon_node.get_parent() if weapon_node != null else null
	weapon_hand_mount_transform = weapon_node.transform if weapon_node != null else Transform3D.IDENTITY
	weapon_solver_anchor = Node3D.new()
	weapon_solver_anchor.name = "WeaponSolverAnchor"
	add_child(weapon_solver_anchor)
	weapon_presentation_owner = WeaponPresentationOwner.new()
	weapon_presentation_owner.bind(
		weapon_node,
		weapon_animation_parent,
		weapon_solver_anchor,
		weapon_hand_mount_transform
	)
	trigger_socket = _find_weapon_socket("Socket_RightHand")
	support_socket = _find_weapon_socket("Socket_LeftHand")
	muzzle_socket = _find_weapon_socket("Socket_Muzzle")
	barrel_base_socket = _find_weapon_socket("Socket_BarrelBase")
	optic_socket = _find_weapon_socket("Socket_Optic")
	stock_socket = _find_weapon_socket("Socket_Buttstock")
	stock_constraint = WeaponStockConstraint.new()
	stock_constraint.name = "ButtstockConstraint"
	add_child(stock_constraint)
	stock_constraint.bind(skeleton, stock_socket)
	socket_contract_active = (
		use_weapon_socket_contract
		and trigger_socket != null
		and support_socket != null
		and muzzle_socket != null
	)
	adaptive_support_socket = (
		support_socket != null
		and not bool(support_socket.get_meta("authored_weapon_socket", false))
	)
	bone_indices.clear()
	if skeleton == null:
		return
	for side: StringName in ARM_BONES:
		var names: Array = ARM_BONES[side]
		for bone_name in names:
			bone_indices[StringName(bone_name)] = _resolve_bone_index(StringName(bone_name))
	bone_indices[GUN_PLACEMENT_FRAME_BONE] = _resolve_bone_index(
		GUN_PLACEMENT_FRAME_BONE
	)
	bone_indices[&"mixamorig_Head"] = _resolve_bone_index(&"mixamorig_Head")
	right_palm_anchor_local = _calculate_palm_anchor(
		"Right",
		int(bone_indices.get(&"mixamorig_RightHand", -1))
	)
	left_palm_anchor_local = _calculate_palm_anchor(
		"Left",
		int(bone_indices.get(&"mixamorig_LeftHand", -1))
	)
	_calibrate_hand_mount_contact()
	weapon_presentation_owner.update_hand_mount(weapon_hand_mount_transform)
	_build_targets()
	_build_socket_ik()


func rebind_weapon(attached_weapon: Node3D) -> void:
	_stop_socket_ik()
	weapon_node = attached_weapon
	weapon_animation_parent = weapon_node.get_parent() if weapon_node != null else null
	weapon_hand_mount_transform = weapon_node.transform if weapon_node != null else Transform3D.IDENTITY
	if weapon_presentation_owner == null:
		weapon_presentation_owner = WeaponPresentationOwner.new()
	weapon_presentation_owner.bind(
		weapon_node,
		weapon_animation_parent,
		weapon_solver_anchor,
		weapon_hand_mount_transform
	)
	trigger_socket = _find_weapon_socket("Socket_RightHand")
	support_socket = _find_weapon_socket("Socket_LeftHand")
	muzzle_socket = _find_weapon_socket("Socket_Muzzle")
	barrel_base_socket = _find_weapon_socket("Socket_BarrelBase")
	optic_socket = _find_weapon_socket("Socket_Optic")
	stock_socket = _find_weapon_socket("Socket_Buttstock")
	if stock_constraint == null:
		stock_constraint = WeaponStockConstraint.new()
		stock_constraint.name = "ButtstockConstraint"
		add_child(stock_constraint)
	stock_constraint.bind(skeleton, stock_socket)
	socket_contract_active = (
		use_weapon_socket_contract
		and trigger_socket != null
		and support_socket != null
		and muzzle_socket != null
	)
	adaptive_support_socket = (
		support_socket != null
		and not bool(support_socket.get_meta("authored_weapon_socket", false))
	)
	_calibrate_hand_mount_contact()
	weapon_presentation_owner.update_hand_mount(weapon_hand_mount_transform)
	weapon_solver_owned = false
	action_weapon_follow_active = false
	gun_placement_baseline_basis_by_posture.clear()
	trigger_hand_grip_basis_by_posture.clear()
	support_hand_grip_basis_by_posture.clear()


func _calibrate_hand_mount_contact() -> void:
	if (
		weapon_node == null
		or trigger_socket == null
		or skeleton == null
		or weapon_animation_parent == null
		or weapon_node.get_parent() != weapon_animation_parent
	):
		return
	skeleton.force_update_all_bone_transforms()
	var palm_world := _right_hand_grip_world_transform().origin
	weapon_presentation_owner.translate_world(
		palm_world - trigger_socket.global_position
	)
	# This corrected transform is the sole persistent hand mount. Ready, relaxed,
	# reload recovery and weapon swaps all return to the same palm contact.
	weapon_hand_mount_transform = weapon_node.transform
	weapon_presentation_owner.update_hand_mount(weapon_hand_mount_transform)


func set_weapon_presentation_visible(enabled: bool) -> void:
	if weapon_presentation_owner != null:
		weapon_presentation_owner.set_visible(enabled)
	elif weapon_node != null:
		weapon_node.visible = enabled


func get_weapon_presentation_owner_state() -> Dictionary:
	return (
		weapon_presentation_owner.snapshot()
		if weapon_presentation_owner != null
		else {}
	)


func configure_joint_poles(raw_poles: Variant) -> void:
	elbow_pole_offsets_by_posture.clear()
	if not raw_poles is Dictionary:
		return
	var pole_document := raw_poles as Dictionary
	var by_stance: Variant = pole_document.get("by_stance", {})
	if by_stance is Dictionary:
		for posture_name in (by_stance as Dictionary).keys():
			var stance_value: Variant = (by_stance as Dictionary)[posture_name]
			if stance_value is Dictionary:
				elbow_pole_offsets_by_posture[StringName(posture_name)] = {
					"right": _vector_from_data((stance_value as Dictionary).get("right", {})),
					"left": _vector_from_data((stance_value as Dictionary).get("left", {})),
				}
	if elbow_pole_offsets_by_posture.is_empty():
		var fallback := {
			"right": _vector_from_data(pole_document.get("right", {})),
			"left": _vector_from_data(pole_document.get("left", {})),
		}
		for posture_name: StringName in [&"STANDING", &"CROUCHED", &"PRONE"]:
			elbow_pole_offsets_by_posture[posture_name] = fallback.duplicate(true)


func configure_dynamic_hold(raw_profile: Variant) -> void:
	if not raw_profile is Dictionary:
		return
	var profile := raw_profile as Dictionary
	animation_carry_weight = clampf(
		float(profile.get("animation_carry_weight", animation_carry_weight)),
		0.0,
		1.0
	)
	animation_carry_limit_m = clampf(
		float(profile.get("animation_carry_limit_m", animation_carry_limit_m)),
		0.0,
		0.08
	)
	ownership_return_seconds = clampf(
		float(profile.get("reload_return_blend_seconds", ownership_return_seconds)),
		0.05,
		0.35
	)
	maximum_wrist_correction_deg = clampf(
		float(profile.get("hand_owned_aim_correction_limit_deg", maximum_wrist_correction_deg)),
		25.0,
		180.0
	)
	right_hand_owns_ready_weapon = bool(
		profile.get("right_hand_owns_weapon", right_hand_owns_ready_weapon)
	)
	animation_drives_ready_hands = bool(
		profile.get("animation_drives_ready_hands", animation_drives_ready_hands)
	)
	if stock_constraint != null:
		stock_constraint.configure(profile.get("buttstock_constraint", {}))


func configure_gun_placement_line(raw_profile: Variant) -> void:
	gun_placement_line_by_posture.clear()
	gun_placement_baseline_basis_by_posture.clear()
	trigger_hand_grip_basis_by_posture.clear()
	support_hand_grip_basis_by_posture.clear()
	gun_placement_anchor_local_by_posture.clear()
	gun_placement_frame_origin_local_by_posture.clear()
	gun_placement_shoulder_delta_local_by_posture.clear()
	ready_trigger_shoulder_offset_by_posture.clear()
	gun_placement_locomotion_carry_local = Vector3.ZERO
	gun_placement_shoulder_alternation_m = 0.0
	gun_placement_line_active = false
	gun_placement_line_authored = false
	rail_to_blue_line_event_remaining = 0.0
	var parsed := GunPlacementProfile.parse(raw_profile)
	gun_placement_line_by_posture = parsed.get("by_posture", {})
	gun_placement_line_authored = bool(parsed.get("authored", false))
	gun_placement_line_active = (
		gun_placement_line_authored and bool(parsed.get("runtime_enabled", false))
	)


func trigger_rail_to_blue_line(duration_seconds: float) -> bool:
	if not gun_placement_line_authored:
		return false
	rail_to_blue_line_event_remaining = maxf(
		rail_to_blue_line_event_remaining,
		maxf(duration_seconds, 0.05)
	)
	if weapon_node != null:
		ownership_return_start = weapon_node.global_transform
		ownership_return_elapsed = 0.0
	return true


func release_visual_control() -> void:
	rail_to_blue_line_event_remaining = 0.0
	current_weight = 0.0
	desired_weight = 0.0
	_release_trigger_hand_grip_lock()
	_release_support_hand_grip_lock()
	_stop_socket_ik()
	_set_weapon_solver_owned(false)


func set_animation_frame_pose(raw_pose: Variant) -> void:
	var next_pose := raw_pose as Dictionary if raw_pose is Dictionary else {}
	if next_pose.is_empty():
		_clear_frame_socket_override()
		animation_frame_pose = {}
		return
	if not frame_socket_override_active:
		frame_trigger_socket_base = trigger_socket.position if trigger_socket != null else Vector3.ZERO
		frame_support_socket_base = support_socket.position if support_socket != null else Vector3.ZERO
		frame_socket_override_active = true
	animation_frame_pose = next_pose.duplicate(true)
	if (
		trigger_socket != null
		and animation_frame_pose.has("right_hand_target")
		and animation_frame_pose["right_hand_target"] is Dictionary
	):
		trigger_socket.position = _vector_from_data(animation_frame_pose["right_hand_target"])
	if (
		support_socket != null
		and animation_frame_pose.has("left_hand_target")
		and animation_frame_pose["left_hand_target"] is Dictionary
	):
		support_socket.position = _vector_from_data(animation_frame_pose["left_hand_target"])


func clear_animation_frame_pose() -> void:
	set_animation_frame_pose({})


func interrupt_action_weapon_follow() -> void:
	action_weapon_follow_active = false
	# Preserve the exact visible action frame and let the next approved owner
	# blend away from it. Marking the return complete here made jump interruption
	# apply the ready pose in one frame, producing a half-metre rifle teleport.
	if weapon_node != null:
		ownership_return_start = weapon_node.global_transform
	ownership_return_elapsed = 0.0
	clear_animation_frame_pose()
	_stop_socket_ik()


func _clear_frame_socket_override() -> void:
	if not frame_socket_override_active:
		return
	if trigger_socket != null:
		trigger_socket.position = frame_trigger_socket_base
	if support_socket != null:
		support_socket.position = frame_support_socket_base
	frame_socket_override_active = false
