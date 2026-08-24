class_name SocomPresentationSettings
extends Node

## One client-local contract for audio mix, visual quality, and presentation
## accessibility. These values never change movement, hit detection, smoke
## occlusion, damage, or any other authoritative gameplay result.

signal setting_changed(key: StringName, value: Variant)
signal graphics_preset_changed(preset: StringName)
signal ui_scale_changed(scale: float)
signal output_devices_changed(devices: PackedStringArray)

const SETTINGS_PATH := "user://presentation_settings.cfg"
const GRAPHICS_PRESETS := [&"low", &"medium", &"high", &"ultra"]
const DYNAMIC_RANGE_MODES := [&"wide", &"balanced", &"night"]
const MIX_BUSES := {
	&"Music": &"Master",
	&"Effects": &"Master",
	&"Voice": &"Master",
	&"UI": &"Effects",
	&"Ambience": &"Effects",
}
const DEFAULTS := {
	&"master_volume": 0.82,
	&"music_volume": 0.72,
	&"effects_volume": 0.88,
	&"voice_volume": 0.92,
	&"master_muted": false,
	&"dynamic_range": &"balanced",
	&"output_device": "Default",
	&"graphics_preset": &"high",
	&"ui_scale": 1.0,
	&"reduced_flashes": false,
	&"camera_shake_scale": 1.0,
}

var settings_path_override := ""
var save_enabled := true
var _values: Dictionary = DEFAULTS.duplicate(true)
var _effects_duck_db := 0.0
var _device_poll_elapsed := 0.0
var _known_devices := PackedStringArray()


func _ready() -> void:
	_load_settings()
	_apply_all()
	_known_devices = output_devices()
	set_process(DisplayServer.get_name() != "headless")


func _process(delta: float) -> void:
	_device_poll_elapsed += maxf(delta, 0.0)
	if _device_poll_elapsed < 2.0:
		return
	_device_poll_elapsed = 0.0
	var current_devices := output_devices()
	if current_devices != _known_devices:
		_known_devices = current_devices
		output_devices_changed.emit(current_devices)
	_validate_output_device()


func value_for(key: StringName, fallback: Variant = null) -> Variant:
	return _values.get(key, fallback)


func snapshot() -> Dictionary:
	return _values.duplicate(true)


func set_option(key: StringName, raw_value: Variant, persist := true) -> void:
	if not DEFAULTS.has(key):
		return
	var value: Variant = _normalize_value(key, raw_value)
	if _values.get(key) == value:
		return
	_values[key] = value
	_apply_option(key)
	if persist and save_enabled:
		_save_settings()
	setting_changed.emit(key, value)
	if key == &"graphics_preset":
		graphics_preset_changed.emit(StringName(value))
	elif key == &"ui_scale":
		ui_scale_changed.emit(float(value))


func reset_defaults(persist := true) -> void:
	_values = DEFAULTS.duplicate(true)
	_apply_all()
	if persist and save_enabled:
		_save_settings()
	for key: StringName in DEFAULTS:
		setting_changed.emit(key, _values[key])
	graphics_preset_changed.emit(StringName(_values.graphics_preset))
	ui_scale_changed.emit(float(_values.ui_scale))


func output_devices() -> PackedStringArray:
	var devices := AudioServer.get_output_device_list()
	if devices.is_empty():
		devices.append("Default")
	elif not devices.has("Default"):
		devices.insert(0, "Default")
	return devices


func set_effects_duck_db(decibels: float) -> void:
	_effects_duck_db = clampf(decibels, -36.0, 0.0)
	_apply_mix_volume(&"effects_volume", &"Effects")


func scaled_effect_count(base_count: int, minimum_count := 1) -> int:
	var scale := {
		&"low": 0.38,
		&"medium": 0.62,
		&"high": 0.82,
		&"ultra": 1.0,
	}.get(StringName(_values.graphics_preset), 0.82) as float
	return maxi(minimum_count, int(round(float(base_count) * scale)))


func effect_lights_enabled() -> bool:
	return StringName(_values.graphics_preset) != &"low"


func reduced_flashes_enabled() -> bool:
	return bool(_values.reduced_flashes)


func camera_shake_scale() -> float:
	return float(_values.camera_shake_scale)


func _load_settings() -> void:
	_values = DEFAULTS.duplicate(true)
	var config := ConfigFile.new()
	if config.load(_settings_path()) != OK:
		return
	for key: StringName in DEFAULTS:
		_values[key] = _normalize_value(
			key,
			config.get_value("presentation", String(key), DEFAULTS[key])
		)


func _save_settings() -> bool:
	var config := ConfigFile.new()
	for key: StringName in DEFAULTS:
		config.set_value("presentation", String(key), _values[key])
	return config.save(_settings_path()) == OK


func _settings_path() -> String:
	return SETTINGS_PATH if settings_path_override.is_empty() else settings_path_override


func _normalize_value(key: StringName, value: Variant) -> Variant:
	match key:
		&"master_volume", &"music_volume", &"effects_volume", &"voice_volume":
			return clampf(float(value), 0.0, 1.0)
		&"master_muted", &"reduced_flashes":
			return bool(value)
		&"dynamic_range":
			var mode := StringName(value)
			return mode if mode in DYNAMIC_RANGE_MODES else DEFAULTS[key]
		&"output_device":
			return String(value).strip_edges() if not String(value).strip_edges().is_empty() else "Default"
		&"graphics_preset":
			var preset := StringName(value)
			return preset if preset in GRAPHICS_PRESETS else DEFAULTS[key]
		&"ui_scale":
			return clampf(float(value), 0.75, 1.50)
		&"camera_shake_scale":
			return clampf(float(value), 0.0, 1.0)
	return value


func _apply_all() -> void:
	_ensure_mix_buses()
	for key: StringName in DEFAULTS:
		_apply_option(key)


func _apply_option(key: StringName) -> void:
	match key:
		&"master_volume": _apply_mix_volume(key, &"Master")
		&"music_volume": _apply_mix_volume(key, &"Music")
		&"effects_volume": _apply_mix_volume(key, &"Effects")
		&"voice_volume": _apply_mix_volume(key, &"Voice")
		&"master_muted":
			var master := AudioServer.get_bus_index(&"Master")
			if master >= 0:
				AudioServer.set_bus_mute(master, bool(_values.master_muted))
		&"dynamic_range": _apply_dynamic_range()
		&"output_device": _validate_output_device()
		&"graphics_preset":
			ProjectSettings.set_setting("socom/presentation/graphics_preset", String(_values.graphics_preset))
			if is_inside_tree():
				get_tree().call_group(
					&"presentation_quality_consumers", &"apply_graphics_preset"
				)
		&"ui_scale":
			var window := get_window()
			if window != null:
				window.content_scale_factor = float(_values.ui_scale)
		&"reduced_flashes":
			ProjectSettings.set_setting("socom/presentation/reduced_flashes", bool(_values.reduced_flashes))
		&"camera_shake_scale":
			ProjectSettings.set_setting("socom/presentation/camera_shake_scale", float(_values.camera_shake_scale))


func _ensure_mix_buses() -> void:
	for bus_name: StringName in MIX_BUSES:
		var index := AudioServer.get_bus_index(bus_name)
		if index < 0:
			AudioServer.add_bus()
			index = AudioServer.bus_count - 1
			AudioServer.set_bus_name(index, bus_name)
		AudioServer.set_bus_send(index, MIX_BUSES[bus_name])
	_ensure_master_dynamics()


func _ensure_master_dynamics() -> void:
	var master := AudioServer.get_bus_index(&"Master")
	if master < 0:
		return
	if _find_bus_effect(master, AudioEffectCompressor) < 0:
		var compressor := AudioEffectCompressor.new()
		compressor.threshold = -14.0
		compressor.ratio = 3.0
		compressor.attack_us = 18000.0
		compressor.release_ms = 180.0
		AudioServer.add_bus_effect(master, compressor)
	if _find_bus_effect(master, AudioEffectLimiter) < 0:
		var limiter := AudioEffectLimiter.new()
		limiter.ceiling_db = -0.6
		limiter.threshold_db = -3.0
		AudioServer.add_bus_effect(master, limiter)


func _find_bus_effect(bus_index: int, effect_type: Variant) -> int:
	for index in AudioServer.get_bus_effect_count(bus_index):
		var effect := AudioServer.get_bus_effect(bus_index, index)
		if is_instance_of(effect, effect_type):
			return index
	return -1


func _apply_mix_volume(key: StringName, bus_name: StringName) -> void:
	var bus_index := AudioServer.get_bus_index(bus_name)
	if bus_index < 0:
		return
	var linear := float(_values.get(key, 1.0))
	var decibels := -80.0 if linear <= 0.0001 else linear_to_db(linear)
	if bus_name == &"Effects":
		decibels += _effects_duck_db
	AudioServer.set_bus_volume_db(bus_index, clampf(decibels, -80.0, 6.0))


func _apply_dynamic_range() -> void:
	var master := AudioServer.get_bus_index(&"Master")
	if master < 0:
		return
	var compressor_index := _find_bus_effect(master, AudioEffectCompressor)
	var limiter_index := _find_bus_effect(master, AudioEffectLimiter)
	var mode := StringName(_values.dynamic_range)
	if compressor_index >= 0:
		var compressor := AudioServer.get_bus_effect(master, compressor_index) as AudioEffectCompressor
		AudioServer.set_bus_effect_enabled(master, compressor_index, mode != &"wide")
		if compressor != null:
			compressor.threshold = -19.0 if mode == &"night" else -14.0
			compressor.ratio = 5.5 if mode == &"night" else 3.0
			compressor.gain = 3.0 if mode == &"night" else 1.0
	if limiter_index >= 0:
		AudioServer.set_bus_effect_enabled(master, limiter_index, true)


func _validate_output_device() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var requested := String(_values.output_device)
	var devices := output_devices()
	if not devices.has(requested):
		requested = "Default"
		_values.output_device = requested
	AudioServer.output_device = requested
