class_name SocomOperatorPoseTuner
extends PanelContainer

const BONES := [
	&"spine", &"spine1", &"spine2", &"neck", &"head",
	&"left_shoulder", &"right_shoulder",
	&"left_upper_arm", &"right_upper_arm",
]

var player: CharacterBody3D
var driver: SocomOperatorAnimationDriver
var bone_picker: OptionButton
var current_bone: StringName = &"spine2"
var pitch_slider: HSlider
var yaw_slider: HSlider
var roll_slider: HSlider
var pitch_value: Label
var yaw_value: Label
var roll_value: Label
var pause_button: CheckButton
var posture_label: Label
var status_label: Label
var syncing: bool = false


func _ready() -> void:
	_build_ui()
	visible = false


func configure(target_driver: SocomOperatorAnimationDriver, target_player: CharacterBody3D) -> void:
	driver = target_driver
	player = target_player
	_sync_from_profile()


func set_open(open: bool) -> void:
	visible = open
	if open:
		_sync_from_profile()
	elif pause_button != null and pause_button.button_pressed:
		pause_button.button_pressed = false


func _process(_delta: float) -> void:
	if visible and posture_label != null:
		posture_label.text = "Editing stance: %s" % String(_current_posture()).capitalize()


func _build_ui() -> void:
	anchor_left = 0.69
	anchor_top = 0.12
	anchor_right = 0.985
	anchor_bottom = 0.72
	offset_left = 0.0
	offset_top = 0.0
	offset_right = 0.0
	offset_bottom = 0.0

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	add_child(vbox)

	var title := Label.new()
	title.text = "PROCEDURAL POSE TRANSLATOR"
	title.add_theme_font_size_override("font_size", 15)
	title.add_theme_color_override("font_color", Color("77f29a"))
	vbox.add_child(title)

	var explanation := Label.new()
	explanation.text = (
		"Nondestructive correction: source clip → this stance profile → aim → weapon IK. "
		+ "The saved correction is reused by every compatible animation."
	)
	explanation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(explanation)

	pause_button = CheckButton.new()
	pause_button.text = "Pause operator for pose editing"
	pause_button.toggled.connect(_set_paused)
	vbox.add_child(pause_button)

	posture_label = Label.new()
	posture_label.text = "Editing stance: Standing"
	posture_label.add_theme_color_override("font_color", Color("55e7ff"))
	vbox.add_child(posture_label)

	var bone_row := HBoxContainer.new()
	vbox.add_child(bone_row)
	var bone_label := Label.new()
	bone_label.text = "Bone"
	bone_label.custom_minimum_size.x = 82.0
	bone_row.add_child(bone_label)
	bone_picker = OptionButton.new()
	bone_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for bone: StringName in BONES:
		bone_picker.add_item(String(bone).capitalize())
	bone_picker.select(BONES.find(current_bone))
	bone_picker.item_selected.connect(func(index: int):
		current_bone = BONES[index]
		_sync_from_profile()
	)
	bone_row.add_child(bone_picker)

	pitch_slider = _add_axis(vbox, "Pitch", pitch_value)
	pitch_value = pitch_slider.get_meta("value_label") as Label
	yaw_slider = _add_axis(vbox, "Yaw", yaw_value)
	yaw_value = yaw_slider.get_meta("value_label") as Label
	roll_slider = _add_axis(vbox, "Roll", roll_value)
	roll_value = roll_slider.get_meta("value_label") as Label
	pitch_slider.value_changed.connect(_axis_changed)
	yaw_slider.value_changed.connect(_axis_changed)
	roll_slider.value_changed.connect(_axis_changed)

	var buttons := HBoxContainer.new()
	vbox.add_child(buttons)
	var reset := Button.new()
	reset.text = "Reset Bone"
	reset.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reset.pressed.connect(func():
		if driver:
			driver.set_procedural_pose_rotation(_current_posture(), current_bone, Vector3.ZERO)
		_sync_from_profile()
	)
	buttons.add_child(reset)
	var reload := Button.new()
	reload.text = "Reload Saved"
	reload.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reload.pressed.connect(func():
		if driver:
			driver.reload_procedural_pose_profile()
		_sync_from_profile()
	)
	buttons.add_child(reload)

	var save := Button.new()
	save.text = "Save Stance Corrections"
	save.add_theme_color_override("font_color", Color("ffdc62"))
	save.pressed.connect(_save_profile)
	vbox.add_child(save)

	status_label = Label.new()
	status_label.text = "Pause, select a highlighted upper-body joint, then tune its local rotation. Elbow XYZ is calibrated per weapon in Gunsmith."
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.add_theme_font_size_override("font_size", 11)
	vbox.add_child(status_label)


func _add_axis(parent: VBoxContainer, label_text: String, _unused: Label) -> HSlider:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size.x = 82.0
	row.add_child(label)
	var slider := HSlider.new()
	slider.min_value = -30.0
	slider.max_value = 30.0
	slider.step = 0.25
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(slider)
	var value := Label.new()
	value.text = "0.0°"
	value.custom_minimum_size.x = 58.0
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value)
	slider.set_meta("value_label", value)
	return slider


func _axis_changed(_value: float) -> void:
	if syncing:
		return
	_update_value_labels()
	if driver:
		driver.set_procedural_pose_rotation(
			_current_posture(),
			current_bone,
			Vector3(pitch_slider.value, yaw_slider.value, roll_slider.value)
		)


func _sync_from_profile() -> void:
	if pitch_slider == null:
		return
	syncing = true
	var rotation := (
		driver.get_procedural_pose_rotation(_current_posture(), current_bone)
		if driver
		else Vector3.ZERO
	)
	pitch_slider.value = rotation.x
	yaw_slider.value = rotation.y
	roll_slider.value = rotation.z
	syncing = false
	_update_value_labels()


func _update_value_labels() -> void:
	if pitch_value:
		pitch_value.text = "%+.1f°" % pitch_slider.value
	if yaw_value:
		yaw_value.text = "%+.1f°" % yaw_slider.value
	if roll_value:
		roll_value.text = "%+.1f°" % roll_slider.value


func _set_paused(paused: bool) -> void:
	if player:
		player.set_local_input_enabled(not paused)
		if paused:
			player.velocity = Vector3.ZERO
	if driver:
		driver.set_pose_preview_paused(paused)
	if status_label:
		status_label.text = (
			"Operator frozen. Camera and pose controls remain active."
			if paused
			else "Live playback resumed; saved corrections remain procedural."
		)
	if paused:
		_sync_from_profile()


func _save_profile() -> void:
	var saved := driver != null and driver.save_procedural_pose_profile()
	status_label.text = (
		"Saved config/operator_procedural_pose_profile.json"
		if saved
		else "Could not save the procedural pose profile."
	)


func _current_posture() -> StringName:
	if player != null and player.has_method("get_posture_name"):
		return StringName(player.call("get_posture_name"))
	return &"STANDING"
