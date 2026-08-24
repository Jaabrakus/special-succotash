extends RefCounted

const WeaponOwnershipContract := preload("res://scripts/player/weapon_ownership_contract.gd")
const WeaponReloadVisualTimeline := preload("res://scripts/weapons/weapon_reload_visual_timeline.gd")
const GunsmithAnimationFrameEditorScript := preload(
	"res://scripts/labs/gunsmith/gunsmith_animation_frame_editor.gd"
)


static func begin_follow(lab: Node) -> void:
	if not lab.weapon_root or not lab.skeleton or lab.right_hand_idx < 0:
		return
	var hand_world: Transform3D = lab._right_hand_grip_world_transform()
	if lab.right_grip_marker != null:
		lab.weapon_root.global_position += hand_world.origin - lab.right_grip_marker.global_position
	lab.action_return_transform = lab.weapon_root.global_transform
	lab.action_weapon_hand_offset = hand_world.affine_inverse() * lab.weapon_root.global_transform
	lab.action_weapon_follow_active = true
	lab.action_recovery_elapsed = lab.action_recovery_duration
	if lab.right_hand_ik and lab.right_hand_ik.is_running():
		lab.right_hand_ik.stop()


static func finish_follow(lab: Node) -> void:
	if not lab.action_weapon_follow_active:
		return
	lab.action_weapon_follow_active = false
	lab.action_recovery_start = (
		lab.weapon_root.global_transform
		if lab.weapon_root
		else Transform3D.IDENTITY
	)
	lab.action_recovery_elapsed = 0.0


static func update_ownership(lab: Node, delta: float) -> void:
	if not lab.weapon_root:
		return
	if lab.action_weapon_follow_active:
		lab.weapon_root.global_transform = (
			lab._right_hand_grip_world_transform()
			* lab._animation_frame_weapon_correction_transform()
			* lab.action_weapon_hand_offset
		)
		if lab.right_grip_marker != null:
			lab.weapon_root.global_position += (
				lab._right_palm_contact_world() - lab.right_grip_marker.global_position
			)
		return
	if lab.action_recovery_elapsed < lab.action_recovery_duration:
		lab.action_recovery_elapsed = minf(
			lab.action_recovery_elapsed + delta,
			lab.action_recovery_duration
		)
		var amount: float = lab.action_recovery_elapsed / maxf(lab.action_recovery_duration, 0.001)
		amount = amount * amount * (3.0 - 2.0 * amount)
		lab.weapon_root.global_transform = lab.action_recovery_start.interpolate_with(
			lab._weapon_anchor_target_transform(),
			amount
		)


static func editing_action_frame(lab: Node) -> bool:
	return (
		lab.animation_frame_editor != null
		and lab.animation_frame_editor.active
		and WeaponOwnershipContract.weapon_follows_right_hand(lab.weapon_owner_state)
	)


static func frame_correction_transform(lab: Node) -> Transform3D:
	if not editing_action_frame(lab):
		return Transform3D.IDENTITY
	return Transform3D(
		Basis.from_euler(
			lab._degrees_to_radians_vector(lab.animation_frame_weapon_rotation_correction_deg),
			EULER_ORDER_YXZ
		),
		lab.animation_frame_weapon_position_correction
	)


static func adjust_rotation(lab: Node, axis_name: String, delta_degrees: float) -> float:
	var value := 0.0
	if editing_action_frame(lab):
		if axis_name == "pitch":
			lab.animation_frame_weapon_rotation_correction_deg.x = wrapf(
				lab.animation_frame_weapon_rotation_correction_deg.x + delta_degrees,
				-180.0,
				180.0
			)
			value = lab.animation_frame_weapon_rotation_correction_deg.x
		elif axis_name == "yaw":
			lab.animation_frame_weapon_rotation_correction_deg.y = wrapf(
				lab.animation_frame_weapon_rotation_correction_deg.y + delta_degrees,
				-180.0,
				180.0
			)
			value = lab.animation_frame_weapon_rotation_correction_deg.y
		else:
			lab.animation_frame_weapon_rotation_correction_deg.z = wrapf(
				lab.animation_frame_weapon_rotation_correction_deg.z + delta_degrees,
				-180.0,
				180.0
			)
			value = lab.animation_frame_weapon_rotation_correction_deg.z
	else:
		if axis_name == "pitch":
			lab.grip_offset_rot.x = wrapf(lab.grip_offset_rot.x + delta_degrees, -180.0, 180.0)
			value = lab.grip_offset_rot.x
		elif axis_name == "yaw":
			lab.grip_offset_rot.y = wrapf(lab.grip_offset_rot.y + delta_degrees, -180.0, 180.0)
			value = lab.grip_offset_rot.y
		else:
			lab.grip_offset_rot.z = wrapf(lab.grip_offset_rot.z + delta_degrees, -180.0, 180.0)
			value = lab.grip_offset_rot.z
		lab._sync_weapon_transform()
		lab._update_slider_value("rot_" + axis_name, value)
	lab._refresh_rotation_dials()
	return value


static func adjust_translation(lab: Node, axis_name: String, delta_meters: float) -> float:
	var value := 0.0
	if editing_action_frame(lab):
		if axis_name == "x":
			lab.animation_frame_weapon_position_correction.x = clampf(
				lab.animation_frame_weapon_position_correction.x + delta_meters, -0.25, 0.25
			)
			value = lab.animation_frame_weapon_position_correction.x
		elif axis_name == "y":
			lab.animation_frame_weapon_position_correction.y = clampf(
				lab.animation_frame_weapon_position_correction.y + delta_meters, -0.25, 0.25
			)
			value = lab.animation_frame_weapon_position_correction.y
		else:
			lab.animation_frame_weapon_position_correction.z = clampf(
				lab.animation_frame_weapon_position_correction.z + delta_meters, -0.25, 0.25
			)
			value = lab.animation_frame_weapon_position_correction.z
	else:
		if axis_name == "x":
			lab.grip_offset_pos.x = clampf(lab.grip_offset_pos.x + delta_meters, -0.25, 0.25)
			value = lab.grip_offset_pos.x
		elif axis_name == "y":
			lab.grip_offset_pos.y = clampf(lab.grip_offset_pos.y + delta_meters, -0.25, 0.25)
			value = lab.grip_offset_pos.y
		else:
			lab.grip_offset_pos.z = clampf(lab.grip_offset_pos.z + delta_meters, -0.25, 0.25)
			value = lab.grip_offset_pos.z
		lab._sync_weapon_translation()
		lab._update_slider_value("grip_" + axis_name, value)
	return value


static func active_reload_timeline(lab: Node) -> Dictionary:
	if lab.active_reload_visual_slot.is_empty():
		return {}
	return WeaponReloadVisualTimeline.ensure_profile_timeline(
		lab.handling_profile,
		lab.active_reload_visual_slot,
		active_reload_frame_count(lab)
	)


static func active_reload_frame_count(lab: Node) -> int:
	if lab.animation_frame_editor.active:
		return lab.animation_frame_editor.frame_count()
	if lab.animation_player and lab.animation_player.current_animation != &"":
		var animation: Animation = lab.animation_player.get_animation(
			lab.animation_player.current_animation
		)
		if animation:
			return maxi(
				1,
				int(round(animation.length * GunsmithAnimationFrameEditorScript.DEFAULT_FPS))
			)
	return 1


static func active_reload_frame_index(lab: Node) -> int:
	if lab.animation_frame_editor.active:
		return lab.animation_frame_editor.frame_index()
	if lab.animation_player:
		return maxi(0, int(round(
			lab.animation_player.current_animation_position
			* GunsmithAnimationFrameEditorScript.DEFAULT_FPS
		)))
	return 0


static func update_reload_support_handoff(lab: Node) -> void:
	if not lab.is_reloading or lab.active_reload_visual_slot.is_empty():
		return
	var timeline: Dictionary = active_reload_timeline(lab)
	var events: Dictionary = timeline.get("events", {})
	lab.support_hand_policy = (
		WeaponOwnershipContract.SUPPORT_IK_TO_WEAPON
		if WeaponReloadVisualTimeline.support_hand_should_regrip(
			events,
			active_reload_frame_index(lab)
		)
		else WeaponOwnershipContract.SUPPORT_FREE
	)


static func update_reload_magazine_visual(lab: Node) -> void:
	if lab.reload_magazine_proxy == null:
		return
	if not lab.is_reloading or lab.active_reload_visual_slot.is_empty() or lab.skeleton == null:
		lab.reload_magazine_proxy.visible = false
		return
	var timeline: Dictionary = active_reload_timeline(lab)
	var events: Dictionary = timeline.get("events", {})
	lab.reload_visual_state = WeaponReloadVisualTimeline.state_at_frame(
		events,
		active_reload_frame_index(lab)
	)
	lab.reload_magazine_proxy.visible = WeaponReloadVisualTimeline.magazine_is_in_left_hand(
		lab.reload_visual_state
	)
	if not lab.reload_magazine_proxy.visible:
		return
	var offset: Dictionary = timeline.get("magazine_hand_offset", {})
	var position: Vector3 = lab._vector_from_data(
		offset.get("position", {}),
		Vector3(0.0, -0.075, 0.018)
	)
	var rotation_degrees: Vector3 = lab._vector_from_data(
		offset.get("rotation_degrees", {}),
		Vector3(8.0, 0.0, 90.0)
	)
	var hand_world: Transform3D = lab._left_hand_world_transform()
	var hand_clean := Transform3D(hand_world.basis.orthonormalized(), hand_world.origin)
	lab.reload_magazine_proxy.global_transform = hand_clean * Transform3D(
		Basis.from_euler(Vector3(
			deg_to_rad(rotation_degrees.x),
			deg_to_rad(rotation_degrees.y),
			deg_to_rad(rotation_degrees.z)
		)),
		position
	)
