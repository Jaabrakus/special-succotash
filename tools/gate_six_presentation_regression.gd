extends SceneTree

const ControlsGuide := preload("res://scripts/ui/socom_controls_guide.gd")
const FoleyEngine := preload("res://scripts/audio/tactical_foley_engine.gd")
const SmokeCloud := preload("res://scripts/tactical/smoke_cloud.gd")
const ScreenEffects := preload("res://scripts/tactical/tactical_screen_effects.gd")

var failures: Array[String] = []
var settings: Node
var original_settings: Dictionary = {}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	settings = root.get_node_or_null("PresentationSettings")
	_expect(settings != null, "the project loads one presentation-settings contract")
	if settings == null:
		_finish()
		return
	original_settings = settings.call("snapshot") as Dictionary
	_test_mix_contract()
	await _test_player_settings_ui()
	await _test_visual_quality_and_accessibility()
	_restore_settings()
	_finish()


func _test_mix_contract() -> void:
	var expected_sends := {
		&"Music": &"Master",
		&"Effects": &"Master",
		&"Voice": &"Master",
		&"UI": &"Effects",
		&"Ambience": &"Effects",
		&"AcousticDirect": &"Effects",
		&"AcousticWeaponDirect": &"Effects",
		&"AcousticPortal": &"Effects",
	}
	for bus_name: StringName in expected_sends:
		var index := AudioServer.get_bus_index(bus_name)
		_expect(index >= 0, "%s mix bus exists" % bus_name)
		if index >= 0:
			_expect(
				AudioServer.get_bus_send(index) == expected_sends[bus_name],
				"%s routes through %s" % [bus_name, expected_sends[bus_name]]
			)
	settings.call("set_option", &"master_volume", 0.50, false)
	settings.call("set_option", &"effects_volume", 0.25, false)
	var master := AudioServer.get_bus_index(&"Master")
	var effects := AudioServer.get_bus_index(&"Effects")
	_expect(
		is_equal_approx(AudioServer.get_bus_volume_db(master), linear_to_db(0.50)),
		"master slider applies an independent linear mix value"
	)
	_expect(
		is_equal_approx(AudioServer.get_bus_volume_db(effects), linear_to_db(0.25)),
		"effects slider applies without rewriting master volume"
	)
	settings.call("set_option", &"master_muted", true, false)
	_expect(AudioServer.is_bus_mute(master), "master mute applies through the shared mix")
	settings.call("set_option", &"master_muted", false, false)
	settings.call("set_option", &"dynamic_range", &"wide", false)
	var compressor_index := _effect_index(master, AudioEffectCompressor)
	var limiter_index := _effect_index(master, AudioEffectLimiter)
	_expect(compressor_index >= 0 and limiter_index >= 0, "master dynamics include compressor and peak limiter")
	if compressor_index >= 0:
		_expect(
			not AudioServer.is_bus_effect_enabled(master, compressor_index),
			"wide range leaves compression disabled"
		)
	settings.call("set_option", &"dynamic_range", &"night", false)
	if compressor_index >= 0:
		_expect(
			AudioServer.is_bus_effect_enabled(master, compressor_index),
			"night range enables controlled compression"
		)
	var acoustic := root.get_node_or_null("AcousticPropagation")
	var budget := acoustic.call("voice_budget_snapshot") as Dictionary if acoustic != null else {}
	_expect(
		int(budget.get("total_limit", 0)) == 24
		and int(budget.get("frame_event_limit", 0)) == 14
		and int((budget.get("class_limits", {}) as Dictionary).get(&"weapon", 0)) == 10,
		"full-lobby acoustic playback has total, frame, and event-class budgets"
	)
	var foley := FoleyEngine.new()
	root.add_child(foley)
	var fallback_voices := 0
	for child: Node in foley.get_children():
		if child is AudioStreamPlayer3D:
			fallback_voices += 1
	_expect(
		fallback_voices == 0,
		"normal gameplay foley shares the acoustic pool instead of allocating per-operator pools"
	)
	foley.free()
	_expect(not (settings.call("output_devices") as PackedStringArray).is_empty(), "output-device choices always provide a safe fallback")


func _test_player_settings_ui() -> void:
	var guide := ControlsGuide.new()
	guide.set("save_changes_to_user_profile", false)
	root.add_child(guide)
	await process_frame
	guide.call("set_guide_visible", true)
	guide.call("_set_editing_presentation", true)
	for control_name in [
		"MasterVolumeSlider",
		"MusicVolumeSlider",
		"EffectsVolumeSlider",
		"VoiceVolumeSlider",
		"MasterMuteToggle",
		"DynamicRangeSelector",
		"AudioOutputDeviceSelector",
		"GraphicsPresetSelector",
		"UIScaleSlider",
		"ReducedFlashToggle",
		"CameraShakeSlider",
	]:
		_expect(
			guide.find_child(control_name, true, false) != null,
			"player settings expose %s" % control_name
		)
	guide.free()


func _test_visual_quality_and_accessibility() -> void:
	settings.call("set_option", &"graphics_preset", &"low", false)
	var low_cloud := SmokeCloud.new()
	root.add_child(low_cloud)
	await process_frame
	var low_particles := low_cloud.get("_particles") as GPUParticles3D
	var low_count := low_particles.amount if low_particles != null else 0
	var low_radius := float(low_cloud.get("maximum_radius"))
	low_cloud.free()
	settings.call("set_option", &"graphics_preset", &"ultra", false)
	var ultra_cloud := SmokeCloud.new()
	root.add_child(ultra_cloud)
	await process_frame
	var ultra_particles := ultra_cloud.get("_particles") as GPUParticles3D
	var ultra_count := ultra_particles.amount if ultra_particles != null else 0
	var ultra_radius := float(ultra_cloud.get("maximum_radius"))
	ultra_cloud.free()
	_expect(
		low_count >= 56 and low_count < ultra_count,
		"graphics presets reduce particle cost with a readable minimum"
	)
	_expect(
		is_equal_approx(low_radius, ultra_radius),
		"graphics presets do not change authoritative smoke-cover radius"
	)
	settings.call("set_option", &"ui_scale", 2.0, false)
	_expect(
		is_equal_approx(float(settings.call("value_for", &"ui_scale", 0.0)), 1.50),
		"UI scale clamps to the supported readable range"
	)
	var world := Node3D.new()
	root.add_child(world)
	var camera := Camera3D.new()
	world.add_child(camera)
	var screen_effects := ScreenEffects.new()
	root.add_child(screen_effects)
	await process_frame
	screen_effects.call("bind_camera", camera)
	settings.call("set_option", &"reduced_flashes", true, false)
	screen_effects.call("apply_flash_from_world", Vector3(0.0, 0.0, -2.0), 18.0)
	_expect(
		is_equal_approx(float(screen_effects.get("flash_peak_strength")), 0.62)
		and float(screen_effects.get("flash_hold_remaining")) > 0.0,
		"reduced flashes lower peak luminance without shortening impairment timing"
	)
	settings.call("set_option", &"camera_shake_scale", 0.0, false)
	screen_effects.call("apply_explosion_shake", Vector3.ZERO, 12.0)
	screen_effects.call("_process", 0.016)
	_expect(
		is_zero_approx(camera.h_offset) and is_zero_approx(camera.v_offset),
		"camera-shake accessibility can remove visual displacement"
	)
	screen_effects.free()
	world.free()


func _effect_index(bus_index: int, effect_type: Variant) -> int:
	for index in AudioServer.get_bus_effect_count(bus_index):
		if is_instance_of(AudioServer.get_bus_effect(bus_index, index), effect_type):
			return index
	return -1


func _restore_settings() -> void:
	settings.call("set_effects_duck_db", 0.0)
	for key: StringName in original_settings:
		settings.call("set_option", key, original_settings[key], false)


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("GATE_SIX_PRESENTATION_CHECK PASS ", label)
	else:
		failures.append(label)
		push_error("GATE_SIX_PRESENTATION_CHECK FAIL %s" % label)


func _finish() -> void:
	if failures.is_empty():
		print("GATE_SIX_PRESENTATION_REGRESSION PASS")
		quit(0)
	else:
		print("GATE_SIX_PRESENTATION_REGRESSION FAIL ", failures)
		quit(1)
