extends RefCounted

const WeaponAnimationProfile := preload(
	"res://scripts/weapons/weapon_animation_profile.gd"
)
const WeaponOwnershipContract := preload(
	"res://scripts/player/weapon_ownership_contract.gd"
)


static func trigger_reload(lab: Node) -> void:
	var plan: Dictionary = lab.presentation_router.resolve(
		&"RELOAD_STARTED",
		{
			"posture": String(lab.preview_posture),
			"weapon_family": String(lab.handling_profile.get("family", "TWO_HAND_RIFLE")),
			"current_base_state": String(lab._posture_idle_clip()),
		}
	)
	var clip_name := StringName(plan.get("state", ""))
	if not bool(plan.get("valid", false)) or clip_name == &"":
		if lab.hud_status:
			lab.hud_status.text = "⚠ Connect RELOAD_STARTED in Animation Studio before previewing reload."
		return
	lab._preview_animation_slot(
		"reload_%s" % String(lab.preview_posture).to_lower(),
		clip_name
	)


static func posture_fire_slot(lab: Node) -> String:
	match lab.preview_posture:
		&"CROUCHED": return "fire_crouched"
		&"PRONE": return "fire_prone"
		_: return "fire_standing"


static func fire_event_presentation(lab: Node) -> Dictionary:
	if lab.presentation_router == null:
		return {}
	return lab.presentation_router.resolve(
		&"FIRE_ACCEPTED",
		{
			"posture": String(lab.preview_posture),
			"weapon_family": String(lab.handling_profile.get("family", "TWO_HAND_RIFLE")),
			"current_base_state": String(lab._posture_idle_clip()),
		}
	)


static func preview_fire(lab: Node, presentation: Dictionary = {}) -> void:
	var slot_name: String = posture_fire_slot(lab)
	if presentation.is_empty():
		presentation = fire_event_presentation(lab)
	var clip_name := StringName(presentation.get("state", ""))
	if clip_name == &"" or not lab._ensure_preview_clip(clip_name):
		if lab.hud_status:
			lab.hud_status.text = "⚠ Connect FIRE_ACCEPTED to a mapped animation state before firing."
		return
	lab._set_animation_edit_candidate(slot_name, clip_name)
	if not lab.animation_frame_editor.active or lab.animation_frame_editor.clip_name != clip_name:
		lab._enter_animation_frame_editor(slot_name, clip_name)
	if not lab.animation_frame_editor.active or lab.animation_player == null:
		return
	lab.selected_animation_key = clip_name
	lab.animation_frame_editor.playing = true
	lab.animation_frame_editor.set_time(0.0)
	lab.animation_frame_last_applied = -1
	lab.animation_player.play(clip_name, 0.0)
	lab.animation_player.seek(0.0, true)
	lab._apply_animation_frame_pose_for_current_time()
	lab._refresh_animation_frame_editor_ui()
	if lab.hud_status:
		lab.hud_status.text = "💥 FIRE_ACCEPTED → %s. This is the same event route used by Playable Range." % clip_name


static func set_support_hand_attached(
	lab: Node,
	attached: bool,
	announce: bool = true
) -> void:
	lab.support_hand_attached = attached
	if lab.left_hand_ik:
		if attached and lab.support_hand_policy == WeaponOwnershipContract.SUPPORT_IK_TO_WEAPON:
			if not lab.left_hand_ik.is_running():
				lab.left_hand_ik.start()
		elif lab.left_hand_ik.is_running():
			lab.left_hand_ik.stop()
	if lab.support_hand_toggle and lab.support_hand_toggle.button_pressed != attached:
		lab.support_hand_toggle.set_pressed_no_signal(attached)
	if announce and lab.hud_status:
		lab.hud_status.text = (
			"🤲 Support hand attached to foregrip"
			if attached
			else "✋ Support hand released; firing hand keeps the weapon anchored"
		)


static func on_handling_family_selected(lab: Node, index: int) -> void:
	if lab.handling_family_select == null:
		return
	var family := String(lab.handling_family_select.get_item_metadata(index))
	lab.handling_profile = WeaponAnimationProfile.build_default(
		family,
		lab.animation_catalog.clip_paths if lab.animation_catalog else {}
	)
	refresh_handling_ui(lab)


static func auto_build_animation_set(lab: Node) -> void:
	var family := String(lab.handling_profile.get(
		"family",
		WeaponAnimationProfile.infer_family(lab.weapon_name, lab.selected_category)
	))
	lab.handling_profile = WeaponAnimationProfile.build_default(
		family,
		lab.animation_catalog.clip_paths if lab.animation_catalog else {}
	)
	refresh_handling_ui(lab)
	if lab.hud_status:
		lab.hud_status.text = "⚡ Animation set built for %s. Preview it, then save the weapon profile." % family.replace("_", " ")


static func on_animation_slot_selected(
	lab: Node,
	index: int,
	slot_name: String,
	selector: OptionButton
) -> void:
	var slots: Dictionary = lab.handling_profile.get("animation_slots", {}).duplicate(true)
	slots[slot_name] = String(selector.get_item_metadata(index))
	lab.handling_profile["animation_slots"] = slots
	refresh_handling_ui(lab, false)


static func refresh_handling_ui(lab: Node, sync_selectors: bool = true) -> void:
	if lab.handling_family_select == null:
		return
	var family := String(lab.handling_profile.get(
		"family",
		WeaponAnimationProfile.infer_family(lab.weapon_name, lab.selected_category)
	))
	for index in lab.handling_family_select.item_count:
		if String(lab.handling_family_select.get_item_metadata(index)) == family:
			lab.handling_family_select.select(index)
			break
	var slots: Dictionary = lab.handling_profile.get("animation_slots", {})
	if sync_selectors:
		for slot_name in lab.animation_slot_selectors:
			var selector: OptionButton = lab.animation_slot_selectors[slot_name]
			var wanted := String(slots.get(slot_name, ""))
			selector.select(0)
			for item_index in selector.item_count:
				if String(selector.get_item_metadata(item_index)) == wanted:
					selector.select(item_index)
					break
	var audit: Dictionary = WeaponAnimationProfile.validate(
		lab.handling_profile,
		lab.animation_catalog.clip_paths if lab.animation_catalog else {}
	)
	if lab.animation_mapping_status:
		var missing: Array = audit.get("missing", [])
		lab.animation_mapping_status.text = "%d/%d combat slots mapped%s\nMovement pack: %d/%d directional and posture clips ready" % [
			int(audit.get("mapped", 0)),
			int(audit.get("total", 0)),
			"" if missing.is_empty() else " • Missing: " + ", ".join(missing),
			int(audit.get("locomotion_mapped", 0)),
			int(audit.get("locomotion_total", 0)),
		]
		lab.animation_mapping_status.add_theme_color_override(
			"font_color",
			Color(0.45, 1.0, 0.55)
			if bool(audit.get("complete", false))
			else Color(1.0, 0.72, 0.25)
		)


static func preview_animation_slot(
	lab: Node,
	slot_name: String,
	forced_clip_name: StringName = &""
) -> void:
	lab._leave_animation_frame_editor()
	if lab.animation_player == null or lab.animation_catalog == null:
		return
	var slots: Dictionary = lab.handling_profile.get("animation_slots", {})
	var clip_name := (
		forced_clip_name
		if forced_clip_name != &""
		else StringName(slots.get(slot_name, ""))
	)
	if clip_name == &"":
		if lab.hud_status:
			lab.hud_status.text = "⚠ No clip mapped to %s yet." % String(
				WeaponAnimationProfile.SLOT_LABELS.get(slot_name, slot_name)
			)
		return
	if not lab._ensure_preview_clip(clip_name):
		if lab.hud_status:
			lab.hud_status.text = "⚠ Could not load animation clip: %s" % clip_name
		return
	lab._set_animation_edit_candidate(slot_name, clip_name)
	lab.selected_animation_key = clip_name
	lab.animation_frame_weapon_position_correction = Vector3.ZERO
	lab.animation_frame_weapon_rotation_correction_deg = Vector3.ZERO
	lab._apply_animation_hand_map(clip_name)
	lab.animation_preview_token += 1
	var token: int = lab.animation_preview_token
	var is_idle := slot_name.begins_with("idle_")
	lab.active_reload_visual_slot = slot_name if slot_name.begins_with("reload_") else ""
	lab._apply_weapon_ownership_policy(
		WeaponOwnershipContract.preview_policy(slot_name, clip_name),
		slot_name.begins_with("reload_")
	)
	lab.animation_player.play(clip_name, 0.10)
	if lab.hud_status:
		lab.hud_status.text = "▶ Previewing %s → %s" % [
			String(WeaponAnimationProfile.SLOT_LABELS.get(slot_name, slot_name)),
			clip_name,
		]
	if is_idle:
		return
	var animation: Animation = lab.animation_player.get_animation(clip_name)
	var duration := maxf(animation.length if animation else 1.0, 0.10)
	lab.get_tree().create_timer(duration).timeout.connect(func():
		if token != lab.animation_preview_token:
			return
		var idle_slot: String = lab._posture_idle_slot()
		lab.active_reload_visual_slot = ""
		lab._apply_weapon_ownership_policy(
			WeaponOwnershipContract.preview_policy(idle_slot),
			false
		)
		var idle_clip: StringName = lab._posture_idle_clip()
		if idle_clip != &"" and lab._ensure_preview_clip(idle_clip):
			lab.animation_player.play(idle_clip, 0.10)
		if lab.hud_status:
			lab.hud_status.text = "✅ Preview complete. Choose another slot or save this weapon profile."
	)
