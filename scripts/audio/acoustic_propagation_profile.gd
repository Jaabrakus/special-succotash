class_name AcousticPropagationProfile
extends RefCounted

const PROFILE_PATH := "res://config/acoustic_propagation.json"
const SCHEMA_VERSION := 1

var values: Dictionary = {}


func _init() -> void:
	values = defaults()


static func defaults() -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"speed_of_sound_mps": 343.0,
		"delay_scale": 1.0,
		"max_portal_hops": 6,
		"max_path_meters": 160.0,
		"portal_loss_db": -2.5,
		"blocked_loss_db": -18.0,
		"portal_lowpass_hz": 7200.0,
		"blocked_lowpass_hz": 1350.0,
		"early_reflection_gain": 0.34,
		"reverb_wet": 0.24,
		"event_policies": {
			"weapon": {"max_distance_m": 220.0, "max_portal_hops": 6, "priority": 100, "delay_scale": 1.0, "volume_bias_db": 0.0},
			"explosion": {"max_distance_m": 300.0, "max_portal_hops": 6, "priority": 95, "delay_scale": 1.0, "volume_bias_db": 0.0},
			"body_impact": {"max_distance_m": 90.0, "max_portal_hops": 3, "priority": 70, "delay_scale": 0.85, "volume_bias_db": -1.0},
			"world_impact": {"max_distance_m": 120.0, "max_portal_hops": 4, "priority": 65, "delay_scale": 0.9, "volume_bias_db": -1.0},
			"voice": {"max_distance_m": 70.0, "max_portal_hops": 4, "priority": 60, "delay_scale": 0.65, "volume_bias_db": 0.0},
			"footstep": {"max_distance_m": 32.0, "max_portal_hops": 2, "priority": 30, "delay_scale": 0.35, "volume_bias_db": -1.5},
			"foley": {"max_distance_m": 45.0, "max_portal_hops": 2, "priority": 25, "delay_scale": 0.35, "volume_bias_db": -2.0},
			"ambience": {"max_distance_m": 140.0, "max_portal_hops": 3, "priority": 10, "delay_scale": 0.0, "volume_bias_db": -4.0},
		},
		"materials": {
			"concrete": {"loss_db": -12.0, "lowpass_hz": 1100.0},
			"wood": {"loss_db": -8.0, "lowpass_hz": 2100.0},
			"glass": {"loss_db": -5.0, "lowpass_hz": 4200.0},
			"metal": {"loss_db": -15.0, "lowpass_hz": 900.0},
			"foliage": {"loss_db": -3.0, "lowpass_hz": 5600.0},
		},
	}


func load_from_file(path := PROFILE_PATH) -> bool:
	if not FileAccess.file_exists(path):
		values = defaults()
		return false
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return false
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		return false
	values = defaults()
	_merge_dictionary(values, parsed as Dictionary)
	return validate().is_empty()


func save_to_file(path := PROFILE_PATH) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(values, "  ") + "\n")
	return true


func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if int(values.get("schema_version", 0)) != SCHEMA_VERSION:
		errors.append("Unsupported acoustic profile schema")
	if float(values.get("speed_of_sound_mps", 0.0)) <= 0.0:
		errors.append("Speed of sound must be positive")
	if int(values.get("max_portal_hops", 0)) < 1:
		errors.append("At least one portal hop must be allowed")
	if float(values.get("max_path_meters", 0.0)) <= 0.0:
		errors.append("Maximum acoustic path must be positive")
	if float(values.get("portal_lowpass_hz", 0.0)) < 100.0:
		errors.append("Portal low-pass cutoff is too low")
	if float(values.get("blocked_lowpass_hz", 0.0)) < 100.0:
		errors.append("Blocked low-pass cutoff is too low")
	var policies: Variant = values.get("event_policies", {})
	if not policies is Dictionary or (policies as Dictionary).is_empty():
		errors.append("Acoustic event policies are required")
	else:
		for policy_name: Variant in policies:
			var policy: Variant = policies[policy_name]
			if not policy is Dictionary:
				errors.append("%s acoustic policy must be an object" % policy_name)
				continue
			if float((policy as Dictionary).get("max_distance_m", 0.0)) <= 0.0:
				errors.append("%s acoustic range must be positive" % policy_name)
	return errors


func get_float(key: StringName, fallback := 0.0) -> float:
	return float(values.get(String(key), fallback))


func get_int(key: StringName, fallback := 0) -> int:
	return int(values.get(String(key), fallback))


func set_value(key: StringName, value: Variant) -> void:
	values[String(key)] = value


func policy_for(event_class: StringName) -> Dictionary:
	var policies: Variant = values.get("event_policies", {})
	if not policies is Dictionary:
		return {}
	var selected: Variant = (policies as Dictionary).get(
		String(event_class), (policies as Dictionary).get("foley", {})
	)
	return (selected as Dictionary).duplicate(true) if selected is Dictionary else {}


func material_for(surface_name: StringName) -> Dictionary:
	var materials: Variant = values.get("materials", {})
	if not materials is Dictionary:
		return {}
	var selected: Variant = (materials as Dictionary).get(
		String(surface_name), (materials as Dictionary).get("concrete", {})
	)
	return (selected as Dictionary).duplicate(true) if selected is Dictionary else {}


func material_names() -> PackedStringArray:
	var materials: Variant = values.get("materials", {})
	return PackedStringArray((materials as Dictionary).keys()) if materials is Dictionary else PackedStringArray()


static func _merge_dictionary(target: Dictionary, source: Dictionary) -> void:
	for key: Variant in source:
		var incoming: Variant = source[key]
		if incoming is Dictionary and target.get(key) is Dictionary:
			_merge_dictionary(target[key] as Dictionary, incoming as Dictionary)
		else:
			target[key] = incoming
