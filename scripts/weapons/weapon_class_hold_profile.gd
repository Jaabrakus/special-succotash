class_name SocomWeaponClassHoldProfile
extends RefCounted

## Selective weapon-class inheritance. Class profiles own animation routing and
## operator pose defaults; each weapon profile remains the sole owner of its
## mesh scale, model rotation, mount, grip offset, and physical sockets.

const WeaponAnimationProfile := preload(
	"res://scripts/weapons/weapon_animation_profile.gd"
)

const CLASS_ASSAULT_RIFLE := "ASSAULT_RIFLE"
const CLASS_SUBMACHINE_GUN := "SUBMACHINE_GUN"
const CLASS_SNIPER_RIFLE := "SNIPER_RIFLE"
const CLASS_SHOTGUN := "SHOTGUN"
const CLASS_PISTOL := "PISTOL"
const CLASS_MACHINE_GUN := "MACHINE_GUN"

const ASSAULT_RIFLE_DONOR_PATH := "res://config/weapons/assaultrifle_1.json"
const ASSAULT_RIFLE_HAND_MAPS: Array[String] = [
	"aim_idle", "combat_fire", "idle_crouch", "idle_prone",
]
const ASSAULT_RIFLE_FRAME_POSES: Array[String] = [
	"aim_idle", "combat_fire",
]
const ASSAULT_RIFLE_HANDLING_FIELDS: Array[String] = [
	"dynamic_hold",
	"ready_aim",
	"standing_fire_uses_aim_idle",
	"crouched_fire_uses_aim_idle",
]


static func apply_to_config(raw: Dictionary) -> Dictionary:
	if raw.is_empty():
		return {}
	var config := raw.duplicate(true)
	var weapon_id := String(config.get("weapon_id", ""))
	var weapon_class := resolve_class(
		weapon_id,
		String(config.get("display_name", weapon_id)),
		String(config.get("category", ""))
	)
	var family := animation_family(weapon_class)

	if weapon_class == CLASS_ASSAULT_RIFLE:
		_apply_assault_rifle_pose_defaults(config)

	var handling: Dictionary = (
		(config.get("handling_profile", {}) as Dictionary).duplicate(true)
		if config.get("handling_profile", {}) is Dictionary
		else {}
	)
	handling["class_id"] = weapon_class
	handling["family"] = family
	handling = WeaponAnimationProfile.normalized_profile(family, handling)
	# Profiles normalized before the dedicated moving-rifle clip was connected
	# saved jump_loop as an explicit value. Upgrade that legacy default in memory
	# while preserving any genuinely custom per-weapon jump mapping.
	if family != WeaponAnimationProfile.FAMILY_TWO_HAND_PISTOL:
		var locomotion: Dictionary = handling.get("locomotion_slots", {})
		if String(locomotion.get("jump", "")) in ["", "jump_loop"]:
			locomotion["jump"] = "rifle_jump"
		handling["locomotion_slots"] = locomotion
	config["handling_profile"] = handling
	return config


static func resolve_class(weapon_id: String, display_name: String, category: String) -> String:
	var normalized_id := weapon_id.to_lower()
	# The imported catalog classifies M40A1 with assault rifles. Its long-gun
	# animation contract must win over that source-data mismatch.
	if normalized_id in ["m40a1", "m82a1a", "m87elr", "sr-25", "sr-25_sd"]:
		return CLASS_SNIPER_RIFLE
	match category.to_lower():
		"pistols":
			return CLASS_PISTOL
		"submachine guns":
			return CLASS_SUBMACHINE_GUN
		"sniper rifles":
			return CLASS_SNIPER_RIFLE
		"shotguns":
			return CLASS_SHOTGUN
		"machine guns":
			return CLASS_MACHINE_GUN
		"assault rifles":
			return CLASS_ASSAULT_RIFLE
	var searchable := (weapon_id + " " + display_name + " " + category).to_lower()
	if "pistol" in searchable or "revolver" in searchable:
		return CLASS_PISTOL
	if "sniper" in searchable:
		return CLASS_SNIPER_RIFLE
	if "shotgun" in searchable:
		return CLASS_SHOTGUN
	return CLASS_ASSAULT_RIFLE


static func animation_family(weapon_class: String) -> String:
	match weapon_class:
		CLASS_PISTOL:
			return WeaponAnimationProfile.FAMILY_TWO_HAND_PISTOL
		CLASS_SNIPER_RIFLE, CLASS_SHOTGUN:
			return WeaponAnimationProfile.FAMILY_LONG_GUN
		CLASS_MACHINE_GUN:
			return WeaponAnimationProfile.FAMILY_HEAVY
		_:
			return WeaponAnimationProfile.FAMILY_TWO_HAND_RIFLE


static func _apply_assault_rifle_pose_defaults(config: Dictionary) -> void:
	var donor := _read_json(ASSAULT_RIFLE_DONOR_PATH)
	if donor.is_empty():
		return
	var target_sockets: Dictionary = (
		config.get("weapon_sockets", {}) as Dictionary
		if config.get("weapon_sockets", {}) is Dictionary
		else {}
	)
	var left_grip: Dictionary = _vector_map(
		target_sockets.get("left_hand_ik_target", {}),
		Vector3(-0.22, -0.01, -0.08)
	)
	var right_grip: Dictionary = _vector_map(
		target_sockets.get("right_hand_grip_target", {}),
		Vector3.ZERO
	)

	for field in ["support_hand_pose", "elbow_poles", "stances"]:
		var inherited: Variant = donor.get(field, {})
		if inherited is Dictionary:
			var pose_defaults := (inherited as Dictionary).duplicate(true)
			_remap_hand_contacts(pose_defaults, left_grip, right_grip)
			config[field] = _merge_missing_dictionary(config.get(field, {}), pose_defaults)

	var donor_maps: Dictionary = donor.get("animation_hand_maps", {})
	var target_maps: Dictionary = (
		(config.get("animation_hand_maps", {}) as Dictionary).duplicate(true)
		if config.get("animation_hand_maps", {}) is Dictionary
		else {}
	)
	for clip_name in ASSAULT_RIFLE_HAND_MAPS:
		if not donor_maps.get(clip_name, {}) is Dictionary:
			continue
		var pose := (donor_maps[clip_name] as Dictionary).duplicate(true)
		_remap_hand_contacts(pose, left_grip, right_grip)
		target_maps[clip_name] = _merge_missing_dictionary(target_maps.get(clip_name, {}), pose)
	config["animation_hand_maps"] = target_maps

	var donor_frames: Dictionary = donor.get("animation_frame_pose_keys", {})
	var target_frames: Dictionary = (
		(config.get("animation_frame_pose_keys", {}) as Dictionary).duplicate(true)
		if config.get("animation_frame_pose_keys", {}) is Dictionary
		else {}
	)
	for clip_name in ASSAULT_RIFLE_FRAME_POSES:
		if not donor_frames.get(clip_name, {}) is Dictionary:
			continue
		var frames := (donor_frames[clip_name] as Dictionary).duplicate(true)
		_remap_hand_contacts(frames, left_grip, right_grip)
		target_frames[clip_name] = _merge_missing_dictionary(target_frames.get(clip_name, {}), frames)
	config["animation_frame_pose_keys"] = target_frames

	var donor_handling: Dictionary = donor.get("handling_profile", {})
	var target_handling: Dictionary = (
		(config.get("handling_profile", {}) as Dictionary).duplicate(true)
		if config.get("handling_profile", {}) is Dictionary
		else {}
	)
	for field in ASSAULT_RIFLE_HANDLING_FIELDS:
		if not donor_handling.has(field):
			continue
		var inherited: Variant = donor_handling[field]
		if inherited is Dictionary:
			target_handling[field] = _merge_missing_dictionary(
				target_handling.get(field, {}),
				(inherited as Dictionary).duplicate(true)
			)
		elif not target_handling.has(field):
			target_handling[field] = inherited
	target_handling["class_pose_source"] = "AssaultRifle_1"
	config["handling_profile"] = target_handling


static func _merge_missing_dictionary(current: Variant, defaults: Dictionary) -> Dictionary:
	var merged: Dictionary = (
		(current as Dictionary).duplicate(true) if current is Dictionary else {}
	)
	for key: Variant in defaults.keys():
		if not merged.has(key):
			merged[key] = defaults[key]
		elif merged[key] is Dictionary and defaults[key] is Dictionary:
			merged[key] = _merge_missing_dictionary(merged[key], defaults[key])
	return merged


static func _remap_hand_contacts(value: Variant, left_grip: Dictionary, right_grip: Dictionary) -> void:
	if value is Dictionary:
		var dictionary := value as Dictionary
		for key: Variant in dictionary.keys():
			var key_name := String(key)
			if key_name in ["left_grip", "left_hand_target", "support_grip"]:
				dictionary[key] = left_grip.duplicate(true)
			elif key_name in ["right_grip", "right_hand_target", "trigger_grip"]:
				dictionary[key] = right_grip.duplicate(true)
			else:
				_remap_hand_contacts(dictionary[key], left_grip, right_grip)
	elif value is Array:
		for item: Variant in value:
			_remap_hand_contacts(item, left_grip, right_grip)


static func _vector_map(value: Variant, fallback: Vector3) -> Dictionary:
	if not value is Dictionary:
		return {"x": fallback.x, "y": fallback.y, "z": fallback.z}
	var map := value as Dictionary
	return {
		"x": float(map.get("x", fallback.x)),
		"y": float(map.get("y", fallback.y)),
		"z": float(map.get("z", fallback.z)),
	}


static func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(file.get_as_text()) if file != null else null
	return (parsed as Dictionary).duplicate(true) if parsed is Dictionary else {}
