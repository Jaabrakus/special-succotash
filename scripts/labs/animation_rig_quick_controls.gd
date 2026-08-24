class_name SocomAnimationRigQuickControls
extends VBoxContainer

signal target_selected(target_id: StringName)
signal elbow_guides_toggled(enabled: bool)

## Clear shortcuts for the placement controls used most often while
## authoring a weapon animation. Detailed rotation remains on the corner gizmo.


func _ready() -> void:
	name = "AnimationRigQuickControls"
	var title := Label.new()
	title.text = "DIRECT PLACEMENT — CLICK A TARGET, THEN DRAG IT"
	title.add_theme_color_override("font_color", Color(0.45, 0.9, 1.0))
	add_child(title)
	var row := HBoxContainer.new()
	add_child(row)
	_add_target_button(row, "Weapon Mount", &"weapon_mount", Color(1.0, 0.62, 0.12))
	_add_target_button(row, "Left Hand", &"left_hand", Color(0.15, 0.95, 1.0))
	_add_target_button(row, "Blue Position", &"placement_origin", Color(0.4, 0.68, 1.0))
	_add_target_button(row, "Blue Aim: LOCKED", &"placement_direction", Color(0.62, 0.82, 1.0))
	var elbow_row := HBoxContainer.new()
	add_child(elbow_row)
	_add_target_button(elbow_row, "Left Elbow", &"left_elbow_pole", Color(0.86, 0.48, 1.0))
	var elbow_toggle := CheckButton.new()
	elbow_toggle.name = "AnimationElbowGuidesToggle"
	elbow_toggle.text = "Pink elbow bend guides"
	elbow_toggle.tooltip_text = (
		"These are IK pole guides. Move one to choose which direction that elbow bends. "
		+ "They do not move the hand or change arm length."
	)
	elbow_toggle.button_pressed = true
	elbow_toggle.toggled.connect(elbow_guides_toggled.emit)
	add_child(elbow_toggle)
	var help := Label.new()
	help.name = "AnimationElbowGuideHelp"
	help.text = (
		"Left purple = support-arm bend direction. The animation owns the right arm; "
		+ "edit its skeleton joints or move Weapon Mount."
	)
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.add_theme_font_size_override("font_size", 11)
	help.add_theme_color_override("font_color", Color(0.9, 0.62, 1.0))
	add_child(help)


func _add_target_button(
	row: HBoxContainer,
	label: String,
	target_id: StringName,
	color: Color
) -> void:
	var button := Button.new()
	button.name = "Select%s" % String(target_id).to_pascal_case()
	button.text = label
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.add_theme_color_override("font_color", color)
	button.tooltip_text = (
		"Drag the selected dot directly in the workbench. Pink elbows change bend direction "
		+ "without moving the hand or changing arm length. Blue Aim stays locked to the reticle. "
		+ "Use the corner control for a single axis or palm rotation."
	)
	button.pressed.connect(target_selected.emit.bind(target_id))
	row.add_child(button)
