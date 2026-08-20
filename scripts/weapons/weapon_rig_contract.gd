class_name SocomWeaponRigContract
extends RefCounted

## One read contract shared by Gunsmith consumers. Older saved profiles are
## upgraded in memory so a missing field never makes the Studio, runtime rig,
## and weapon controller choose three different fallbacks.

const LOADOUT_PATH := "res://config/weapons/operator_loadout.json"
const CURRENT_SCHEMA_VERSION := 3
const PlaytestStateCollector := preload("res://scripts/runtime/playtest_state_collector.gd")


static func resolve_config_path(fallback_weapon_id: String = "") -> String:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--weapon-rig-config="):
			var override_path := argument.trim_prefix("--weapon-rig-config=")
			if FileAccess.file_exists(override_path):
				return override_path
	if FileAccess.file_exists(LOADOUT_PATH):
		var loadout := _read_dictionary(LOADOUT_PATH)
		var equipped_path := String(loadout.get("rig_config", ""))
		if FileAccess.file_exists(equipped_path):
			return equipped_path
	if not fallback_weapon_id.is_empty():
		var fallback_path := "res://config/weapons/%s.json" % fallback_weapon_id.to_lower()
		if FileAccess.file_exists(fallback_path):
			return fallback_path
	return ""


static func load_equipped_config(fallback_weapon_id: String = "") -> Dictionary:
	var bundled := PlaytestStateCollector.bundled_state("equipped_weapon")
	if not bundled.is_empty():
		var bundle: Dictionary = ProjectSettings.get_setting("socom/playtest/active_bundle", {})
		var source: Dictionary = (bundle.get("sources", {}) as Dictionary).get("equipped_weapon", {})
		return normalize_config(bundled, String(source.get("path", "")))
	var config_path := resolve_config_path(fallback_weapon_id)
	if config_path.is_empty():
		return {}
	var raw := _read_dictionary(config_path)
	if raw.is_empty():
		return {}
	return normalize_config(raw, config_path)


static func load_config(config_path: String) -> Dictionary:
	if config_path.is_empty() or not FileAccess.file_exists(config_path):
		return {}
	var raw := _read_dictionary(config_path)
	return normalize_config(raw, config_path) if not raw.is_empty() else {}


static func normalize_config(raw: Dictionary, config_path: String = "") -> Dictionary:
	var config := raw.duplicate(true)
	config["_rig_config_path"] = config_path
	config["_source_schema_version"] = int(config.get("schema_version", 0))
	config["schema_version"] = CURRENT_SCHEMA_VERSION
	var weapon_id := String(config.get("weapon_id", config_path.get_file().get_basename()))
	config["weapon_id"] = weapon_id
	config["socket_contract_authored"] = bool(config.get("socket_contract_authored", false))

	if not config.get("operator_mount", {}) is Dictionary or (config.get("operator_mount", {}) as Dictionary).is_empty():
		config["operator_mount"] = {
			"position": {"x": -0.02, "y": 0.08, "z": 0.05},
			"rotation_degrees": {"x": -90.0, "y": 180.0, "z": 0.0},
		}
	if not config.get("model_rotation_degrees", {}) is Dictionary:
		config["model_rotation_degrees"] = {}
	for dictionary_field in [
		"support_hand_pose", "stances", "animation_hand_maps",
		"animation_frame_pose_keys", "handling_profile",
	]:
		if not config.get(dictionary_field, {}) is Dictionary:
			config[dictionary_field] = {}

	var sockets: Dictionary = (
		(config.get("weapon_sockets", {}) as Dictionary).duplicate(true)
		if config.get("weapon_sockets", {}) is Dictionary
		else {}
	)
	var right := vector3_from_map(sockets.get("right_hand_grip_target", {}), Vector3.ZERO)
	var left := vector3_from_map(sockets.get("left_hand_ik_target", {}), Vector3(-0.22, -0.01, -0.08))
	var muzzle := vector3_from_map(sockets.get("muzzle_socket", {}), Vector3(0.70, 0.02, 0.0))
	var barrel_base := vector3_from_map(
		sockets.get("barrel_base_socket", {}),
		derived_barrel_base(right, muzzle)
	)
	sockets["right_hand_grip_target"] = vector3_to_map(right)
	sockets["left_hand_ik_target"] = vector3_to_map(left)
	sockets["barrel_base_socket"] = vector3_to_map(barrel_base)
	sockets["muzzle_socket"] = vector3_to_map(muzzle)
	if not sockets.has("ejection_port"):
		sockets["ejection_port"] = vector3_to_map(Vector3.ZERO)
	if not sockets.has("optic_rail"):
		sockets["optic_rail"] = vector3_to_map(Vector3.ZERO)
	config["weapon_sockets"] = sockets

	var ballistics: Dictionary = (
		(config.get("ballistics", {}) as Dictionary).duplicate(true)
		if config.get("ballistics", {}) is Dictionary
		else {}
	)
	ballistics["fire_rate_rpm"] = float(ballistics.get("fire_rate_rpm", 650.0))
	ballistics["damage"] = float(ballistics.get("damage", 34.0))
	ballistics["muzzle_velocity_mps"] = float(
		ballistics.get("muzzle_velocity_mps", default_muzzle_velocity(config))
	)
	ballistics["base_spread_deg"] = float(ballistics.get("base_spread_deg", 0.4))
	ballistics["bloom_per_shot_deg"] = float(ballistics.get("bloom_per_shot_deg", 1.2))
	ballistics["max_recoil_bloom_deg"] = float(ballistics.get("max_recoil_bloom_deg", 2.4))
	ballistics["bloom_recovery_speed"] = float(ballistics.get("bloom_recovery_speed", 14.0))
	ballistics["is_silenced"] = bool(ballistics.get("is_silenced", false))
	config["ballistics"] = ballistics

	var reticle: Dictionary = (
		(config.get("reticle", {}) as Dictionary).duplicate(true)
		if config.get("reticle", {}) is Dictionary
		else {}
	)
	reticle["base_gap_px"] = float(reticle.get("base_gap_px", 10.0))
	reticle["max_gap_px"] = float(reticle.get("max_gap_px", 46.0))
	reticle["response_speed"] = float(reticle.get("response_speed", 24.0))
	reticle["shot_kick_px"] = float(reticle.get("shot_kick_px", 6.0))
	reticle["shot_kick_return"] = float(reticle.get("shot_kick_return", 18.0))
	reticle["maximum_shot_kick_px"] = float(reticle.get("maximum_shot_kick_px", 18.0))
	reticle["shot_bounce_duration"] = float(reticle.get("shot_bounce_duration", 0.070))
	config["reticle"] = reticle

	var composure: Dictionary = (
		(config.get("composure", {}) as Dictionary).duplicate(true)
		if config.get("composure", {}) is Dictionary
		else {}
	)
	composure["shot_stress"] = float(composure.get("shot_stress", 0.085))
	composure["movement_stress"] = float(composure.get("movement_stress", 0.58))
	composure["turning_stress"] = float(composure.get("turning_stress", 0.34))
	composure["stress_attack_speed"] = float(composure.get("stress_attack_speed", 4.8))
	composure["recovery_speed"] = float(composure.get("recovery_speed", 1.45))
	composure["minimum_core_scale"] = float(composure.get("minimum_core_scale", 0.70))
	composure["visual_spring"] = float(composure.get("visual_spring", 72.0))
	composure["visual_damping"] = float(composure.get("visual_damping", 13.5))
	composure["bounce_duration"] = float(composure.get("bounce_duration", 0.070))
	composure["bounce_strength"] = float(composure.get("bounce_strength", 1.0))
	composure["settled_first_shot_threshold"] = float(
		composure.get("settled_first_shot_threshold", 0.035)
	)
	composure["settled_motion_threshold"] = float(
		composure.get("settled_motion_threshold", 0.08)
	)
	composure["moving_first_shot_multiplier"] = float(
		composure.get("moving_first_shot_multiplier", 0.42)
	)
	composure["second_shot_multiplier"] = float(
		composure.get("second_shot_multiplier", 0.18)
	)
	composure["opening_stress_multiplier"] = float(
		composure.get("opening_stress_multiplier", 0.28)
	)
	composure["graze_damage_scale"] = float(
		composure.get("graze_damage_scale", 0.38)
	)
	config["composure"] = composure
	return config


static func default_muzzle_velocity(config: Dictionary) -> float:
	var category := String(config.get("category", "")).to_lower()
	var weapon_id := String(config.get("weapon_id", "")).to_lower()
	if "shotgun" in category or "shotgun" in weapon_id:
		return 400.0
	if "pistol" in category or "pistol" in weapon_id or "9mm" in weapon_id:
		return 360.0
	if "submachine" in category or "submachine" in weapon_id or "smg" in weapon_id:
		return 410.0
	if "sniper" in category or "sniper" in weapon_id:
		return 850.0
	return 715.0


static func derived_barrel_base(right_grip: Vector3, muzzle: Vector3) -> Vector3:
	# Gunsmith normalizes imported weapons so local +X is the bore. Do not infer
	# the barrel from a grip below the receiver; legacy profiles simply lacked a
	# separately authored barrel-base marker.
	return muzzle - Vector3.RIGHT * minf(
		0.18,
		maxf(absf(muzzle.x - right_grip.x) * 0.35, 0.08)
	)


static func vector3_from_map(value: Variant, fallback: Vector3) -> Vector3:
	if not value is Dictionary:
		return fallback
	var map := value as Dictionary
	return Vector3(
		float(map.get("x", fallback.x)),
		float(map.get("y", fallback.y)),
		float(map.get("z", fallback.z))
	)


static func vector3_to_map(value: Vector3) -> Dictionary:
	return {"x": value.x, "y": value.y, "z": value.z}


static func _read_dictionary(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	var value: Variant = JSON.parse_string(file.get_as_text()) if file != null else null
	return (value as Dictionary).duplicate(true) if value is Dictionary else {}
