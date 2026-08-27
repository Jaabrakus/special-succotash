class_name GunsmithActionFooter
extends RefCounted

## Builds the persistent Gunsmith actions without owning save or launch logic.


static func build(lab, sidebar: VBoxContainer) -> void:
	var footer := VBoxContainer.new()
	footer.add_child(HSeparator.new())
	sidebar.add_child(footer)

	var save_button := Button.new()
	save_button.name = "SaveWeaponRigButton"
	save_button.text = "Save Weapon Rig + Equip (Cmd/Ctrl+S)"
	save_button.tooltip_text = "Save this weapon's model alignment, physical sockets, ballistics, reticle, and composure."
	save_button.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	save_button.pressed.connect(lab._request_save_everything)
	save_button.disabled = not lab.weapon_master_pose_initialized
	lab.save_rig_button = save_button
	footer.add_child(save_button)

	var play_button := Button.new()
	play_button.text = "Save Weapon + Play Current Game"
	play_button.tooltip_text = "Save this exact gun rig and launch the canonical current gameplay scene."
	play_button.add_theme_color_override("font_color", Color(0.35, 1.0, 0.55))
	play_button.pressed.connect(lab._save_and_play_latest_playground)
	play_button.disabled = not lab.weapon_master_pose_initialized
	lab.play_latest_button = play_button
	footer.add_child(play_button)

	lab.hud_status = Label.new()
	lab.hud_status.text = "Weapon rig ready. Drag a socket marker or edit its exact values."
	lab.hud_status.add_theme_font_size_override("font_size", 11)
	lab.hud_status.add_theme_color_override("font_color", Color(0.4, 1.0, 0.4))
	lab.hud_status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	lab.hud_status.tooltip_text = lab.hud_status.text
	footer.add_child(lab.hud_status)
