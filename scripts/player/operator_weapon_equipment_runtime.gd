class_name SocomOperatorWeaponEquipmentRuntime
extends RefCounted

## Applies an already-authorized weapon pickup to visual runtime consumers.
## This component never validates ownership and never grants gameplay equipment.

const WeaponContract := preload("res://scripts/weapons/weapon_rig_contract.gd")


static func apply(driver, raw_config: Dictionary) -> bool:
	if raw_config.is_empty() or driver.asset_runtime == null or driver.skeleton == null:
		return false
	var config_path := String(raw_config.get("_rig_config_path", ""))
	var next_config := WeaponContract.normalize_config(raw_config, config_path)
	var raw_handling: Variant = next_config.get("handling_profile", {})
	if not raw_handling is Dictionary:
		return false
	var next_handling := (raw_handling as Dictionary).duplicate(true)
	var next_family := StringName(next_handling.get("family", ""))
	if next_family == &"":
		return false
	var previous_weapon = driver.weapon_node
	if driver.ik_contract != null:
		driver.ik_contract.rebind_weapon(null)
	var next_weapon: Node3D = driver.asset_runtime.equip_weapon(next_config)
	if next_weapon == null:
		if driver.ik_contract != null:
			driver.ik_contract.rebind_weapon(previous_weapon)
		return false
	_reset_weapon_presentation_state(driver)
	driver.equipped_weapon_config = next_config
	driver.equipped_weapon_handling_profile = next_handling
	driver.equipped_weapon_family = next_family
	driver.weapon_node = next_weapon
	driver.weapon_attachment = driver.asset_runtime.weapon_attachment
	driver.animation_frame_pose_runtime.configure(
		driver.equipped_weapon_config.get("animation_frame_pose_keys", {})
	)
	driver.call("_build_animation_tree")
	if driver.ik_contract != null:
		driver.ik_contract.rebind_weapon(driver.weapon_node)
	if driver.weapon_pose_solver != null:
		driver.weapon_pose_solver.rebind_weapon(driver.weapon_node)
		driver.weapon_pose_solver.configure_joint_poles(
			driver.equipped_weapon_config.get("elbow_poles", {})
		)
		driver.weapon_pose_solver.configure_dynamic_hold(
			driver.equipped_weapon_handling_profile.get("dynamic_hold", {})
		)
		driver.weapon_pose_solver.configure_gun_placement_line(
			driver.equipped_weapon_config.get("gun_placement_line", {})
		)
	if driver.combat_ready_ccdik != null:
		# Weapon swaps keep the same operator skeleton and modifier owner. Rebinding
		# would append another dormant CCDIK3D on every equip and make long weapon-
		# comparison sessions progressively slower; only its saved contact data changes.
		driver.combat_ready_ccdik.reconfigure(
			driver.equipped_weapon_config.get("weapon_contact_graph", {})
		)
	if driver.weapon_grip_contact != null:
		driver.weapon_grip_contact.rebind_weapon(driver.weapon_node)
	driver._last_event_presentation = driver.resolve_presentation_event(
		&"WEAPON_EQUIPPED"
	)
	var ready_state := StringName(driver._last_event_presentation.get("state", ""))
	var ready_slot := "idle_%s" % String(driver.posture).to_lower()
	ready_state = driver.call("_equipped_action_clip", ready_slot, ready_state)
	if ready_state != &"":
		driver.call("_request_clip", ready_state, 0.10)
	driver.call("_update_weapon_visibility")
	driver.weapon_family_changed.emit(
		StringName(driver.equipped_weapon_config.get("weapon_id", "")),
		driver.equipped_weapon_family
	)
	return true


static func _reset_weapon_presentation_state(driver) -> void:
	# A weapon family swap starts from the new weapon's saved presentation data.
	# Preserve locomotion, dive/roll and reload ownership, but discard the old
	# weapon's bounded fire overlay, frame socket override and solver blend.
	if driver.has_method("clear_fire_ready_aim"):
		driver.call("clear_fire_ready_aim")
	driver._fire_pose_clip = &""
	driver._fire_pose_time = 0.0
	driver._fire_pose_duration = 0.0
	driver._presentation_fire_selected = false
	driver._active_frame_pose = {}
	if driver.posture_layer != null:
		driver.posture_layer.set_animation_frame_rotation_overrides({})
	if driver.weapon_pose_solver != null:
		driver.weapon_pose_solver.clear_animation_frame_pose()
		driver.weapon_pose_solver.release_visual_control()
