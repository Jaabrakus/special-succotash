class_name SocomPresentationSettingsPanel
extends VBoxContainer

## Customer-facing editor for the shared client-local presentation contract.

var settings: Node
var device_selector: OptionButton
var status_label: Label


func _ready() -> void:
	name = "PresentationSettingsEditor"
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 10)
	settings = get_node_or_null("/root/PresentationSettings")
	_build_interface()
	if settings != null and settings.has_signal("output_devices_changed"):
		settings.output_devices_changed.connect(_refresh_devices)


func _build_interface() -> void:
	var title := Label.new()
	title.text = "AUDIO, VISUALS, AND ACCESSIBILITY"
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color("8bc5ae"))
	add_child(title)
	var help := Label.new()
	help.text = "Changes apply immediately and save for the next launch. Visual choices do not change hit detection, damage, smoke cover, or other match rules."
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.add_theme_color_override("font_color", Color("aeb9c9"))
	add_child(help)
	add_child(HSeparator.new())
	_add_section("MIX")
	_add_volume_slider("Master", &"master_volume")
	_add_volume_slider("Music", &"music_volume")
	_add_volume_slider("Effects", &"effects_volume")
	_add_volume_slider("Voice", &"voice_volume")
	var mute := CheckButton.new()
	mute.name = "MasterMuteToggle"
	mute.text = "Mute all audio"
	mute.button_pressed = bool(_value(&"master_muted", false))
	mute.toggled.connect(func(enabled: bool): _apply_setting(&"master_muted", enabled))
	add_child(mute)
	_add_choice(
		"Dynamic range",
		&"dynamic_range",
		[
			{"label": "Wide — home theater", "value": &"wide"},
			{"label": "Balanced — default", "value": &"balanced"},
			{"label": "Night — quieter peaks", "value": &"night"},
		],
		"DynamicRangeSelector"
	)
	_build_device_selector()
	add_child(HSeparator.new())
	_add_section("VISUALS AND HUD")
	_add_choice(
		"Graphics preset",
		&"graphics_preset",
		[
			{"label": "Low", "value": &"low"},
			{"label": "Medium", "value": &"medium"},
			{"label": "High", "value": &"high"},
			{"label": "Ultra", "value": &"ultra"},
		],
		"GraphicsPresetSelector"
	)
	_add_percent_slider("HUD and menu scale", &"ui_scale", 75.0, 150.0, 100.0, "UIScaleSlider")
	var reduced_flash := CheckButton.new()
	reduced_flash.name = "ReducedFlashToggle"
	reduced_flash.text = "Reduced flash brightness (impairment timing stays unchanged)"
	reduced_flash.button_pressed = bool(_value(&"reduced_flashes", false))
	reduced_flash.toggled.connect(func(enabled: bool): _apply_setting(&"reduced_flashes", enabled))
	add_child(reduced_flash)
	_add_percent_slider("Camera shake", &"camera_shake_scale", 0.0, 100.0, 100.0, "CameraShakeSlider")
	var reset := Button.new()
	reset.name = "ResetPresentationDefaultsButton"
	reset.text = "Restore Audio and Visual Defaults"
	reset.pressed.connect(_reset_defaults)
	add_child(reset)
	status_label = Label.new()
	status_label.name = "PresentationSettingsStatus"
	status_label.text = "Settings are saved automatically."
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.add_theme_color_override("font_color", Color("8fe6b0"))
	add_child(status_label)


func _add_section(text_value: String) -> void:
	var label := Label.new()
	label.text = text_value
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", Color("f2cf72"))
	add_child(label)


func _add_volume_slider(label_text: String, key: StringName) -> void:
	_add_percent_slider(label_text, key, 0.0, 100.0, 100.0, "%sVolumeSlider" % label_text)


func _add_percent_slider(
	label_text: String,
	key: StringName,
	minimum: float,
	maximum: float,
	value_multiplier: float,
	node_name: String
) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	add_child(row)
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size.x = 170.0
	row.add_child(label)
	var slider := HSlider.new()
	slider.name = node_name
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = 5.0
	slider.value = float(_value(key, 1.0)) * value_multiplier
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(slider)
	var readout := Label.new()
	readout.custom_minimum_size.x = 54.0
	readout.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	readout.text = "%d%%" % int(round(slider.value))
	row.add_child(readout)
	slider.value_changed.connect(func(value: float):
		readout.text = "%d%%" % int(round(value))
		_apply_setting(key, value / value_multiplier)
	)


func _add_choice(
	label_text: String,
	key: StringName,
	choices: Array,
	node_name: String
) -> OptionButton:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	add_child(row)
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size.x = 170.0
	row.add_child(label)
	var option := OptionButton.new()
	option.name = node_name
	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var current := StringName(_value(key, &""))
	for entry: Dictionary in choices:
		option.add_item(String(entry.label))
		option.set_item_metadata(option.item_count - 1, entry.value)
		if StringName(entry.value) == current:
			option.select(option.item_count - 1)
	option.item_selected.connect(func(index: int):
		_apply_setting(key, option.get_item_metadata(index))
	)
	row.add_child(option)
	return option


func _build_device_selector() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	add_child(row)
	var label := Label.new()
	label.text = "Output device"
	label.custom_minimum_size.x = 170.0
	row.add_child(label)
	device_selector = OptionButton.new()
	device_selector.name = "AudioOutputDeviceSelector"
	device_selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	device_selector.item_selected.connect(_select_device)
	row.add_child(device_selector)
	_refresh_devices(_device_list())


func _refresh_devices(devices: PackedStringArray) -> void:
	if device_selector == null:
		return
	var current := String(_value(&"output_device", "Default"))
	device_selector.clear()
	for device: String in devices:
		device_selector.add_item(device)
		if device == current:
			device_selector.select(device_selector.item_count - 1)


func _select_device(index: int) -> void:
	if device_selector == null or index < 0 or index >= device_selector.item_count:
		return
	_apply_setting(&"output_device", device_selector.get_item_text(index))


func _device_list() -> PackedStringArray:
	if settings != null:
		return settings.call("output_devices") as PackedStringArray
	return PackedStringArray(["Default"])


func _value(key: StringName, fallback: Variant) -> Variant:
	return settings.call("value_for", key, fallback) if settings != null else fallback


func _apply_setting(key: StringName, value: Variant) -> void:
	if settings != null:
		settings.call("set_option", key, value)
	if status_label != null:
		status_label.text = "Saved. Changes are active now."


func _reset_defaults() -> void:
	if settings != null:
		settings.call("reset_defaults")
	if status_label != null:
		status_label.text = "Audio and visual defaults restored. Close and reopen this panel to refresh every control."
