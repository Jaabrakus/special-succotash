class_name SocomOperatorTuningProfile
extends RefCounted

## Shared movement and animation tuning document. The playable scene owns UI
## orchestration; this profile owns defaults, migration, persistence, and
## application to the canonical player and visual animation driver.


static func defaults() -> Dictionary:
	return {
		"version": 1,
		"studio_open_on_start": false,
		"movement": {
			"move_speed": 6.5,
			"strafe_speed": 6.5,
			"instant_strafe_response": true,
			"full_gait_input_threshold": 0.72,
			"crouch_speed": 2.6,
			"prone_speed": 1.25,
			"acceleration": 45.0,
			"braking_acceleration": 60.0,
			"reversal_acceleration": 90.0,
			"strafe_burst_frames": 2,
			"strafe_burst_multiplier": 1.18,
			"strafe_burst_decay_seconds": 0.12,
			"strafe_chain_window_seconds": 0.70,
			"torso_to_legs_degrees": 0.5,
		},
		"animation": {
			"state_blend_seconds": 0.12,
			"dive_trim_seconds": 0.78,
			"roll_trim_seconds": 0.62,
			"operator_scale": 62.0,
		},
		"adaptive_intent": {
			"enabled": false,
			"decision_rate_hz": 2.0,
			"maximum_intent_age_seconds": 0.75,
		},
	}


static func load_document(bundled_document: Dictionary, path: String) -> Dictionary:
	var document := bundled_document.duplicate(true)
	if document.is_empty():
		if not FileAccess.file_exists(path):
			return defaults()
		var file := FileAccess.open(path, FileAccess.READ)
		var parsed: Variant = JSON.parse_string(file.get_as_text()) if file else null
		if not (parsed is Dictionary):
			push_warning("Operator tuning JSON is invalid; using safe defaults")
			return defaults()
		document = (parsed as Dictionary).duplicate(true)
	return merge_with_defaults(document)


static func merge_with_defaults(document: Dictionary) -> Dictionary:
	var merged_document := defaults()
	for section_name in document.keys():
		var incoming: Variant = document[section_name]
		if section_name == "movement" and incoming is Dictionary:
			var migrated_movement := (incoming as Dictionary).duplicate(true)
			if not migrated_movement.has("move_speed"):
				migrated_movement["move_speed"] = float(
					migrated_movement.get(
						"run_speed",
						migrated_movement.get("walk_speed", 6.5)
					)
				)
			migrated_movement.erase("walk_speed")
			migrated_movement.erase("run_speed")
			incoming = migrated_movement
		if incoming is Dictionary and merged_document.get(section_name) is Dictionary:
			var merged_section: Dictionary = (
				merged_document[section_name] as Dictionary
			).duplicate(true)
			merged_section.merge(incoming as Dictionary, true)
			merged_document[section_name] = merged_section
		else:
			merged_document[section_name] = incoming
	return merged_document


static func value(
	document: Dictionary,
	section_name: String,
	key: String,
	fallback: float
) -> float:
	var section: Variant = document.get(section_name, {})
	if not (section is Dictionary):
		return fallback
	return float((section as Dictionary).get(key, fallback))


static func set_value(
	document: Dictionary,
	section_name: String,
	key: String,
	new_value: float
) -> void:
	var current_section: Variant = document.get(section_name, {})
	var section: Dictionary = (
		(current_section as Dictionary).duplicate(true)
		if current_section is Dictionary
		else {}
	)
	section[key] = new_value
	document[section_name] = section


static func save_document(document: Dictionary, path: String) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(document, "  "))
	return true


static func apply(document: Dictionary, player: Object, driver: Object) -> void:
	if player != null:
		player.set("move_speed", value(document, "movement", "move_speed", 6.5))
		player.set("strafe_speed", value(document, "movement", "strafe_speed", 6.5))
		var movement: Variant = document.get("movement", {})
		if movement is Dictionary:
			player.set(
				"instant_strafe_response",
				bool((movement as Dictionary).get("instant_strafe_response", true))
			)
		player.set(
			"full_gait_input_threshold",
			value(document, "movement", "full_gait_input_threshold", 0.72)
		)
		player.set("crouch_speed", value(document, "movement", "crouch_speed", 2.6))
		player.set("prone_speed", value(document, "movement", "prone_speed", 1.25))
		player.set("acceleration", value(document, "movement", "acceleration", 45.0))
		player.set(
			"braking_acceleration",
			value(document, "movement", "braking_acceleration", 60.0)
		)
		player.set(
			"reversal_acceleration",
			value(document, "movement", "reversal_acceleration", 90.0)
		)
		player.set(
			"strafe_burst_frames",
			int(round(value(document, "movement", "strafe_burst_frames", 2.0)))
		)
		player.set(
			"strafe_burst_multiplier",
			value(document, "movement", "strafe_burst_multiplier", 1.18)
		)
		player.set(
			"strafe_burst_decay_seconds",
			value(document, "movement", "strafe_burst_decay_seconds", 0.12)
		)
		player.set(
			"strafe_chain_window_seconds",
			value(document, "movement", "strafe_chain_window_seconds", 0.70)
		)
		player.set(
			"torso_turn_in_place_limit_deg",
			value(document, "movement", "torso_to_legs_degrees", 0.5)
		)
	if driver == null:
		return
	driver.set(
		"transition_blend_seconds",
		value(document, "animation", "state_blend_seconds", 0.12)
	)
	driver.set(
		"dive_roll_trim_duration",
		value(document, "animation", "dive_trim_seconds", 0.78)
	)
	driver.set(
		"roll_trim_duration",
		value(document, "animation", "roll_trim_seconds", 0.62)
	)
	if driver.has_method("set_trooper_scale"):
		driver.call(
			"set_trooper_scale",
			value(document, "animation", "operator_scale", 62.0)
		)
