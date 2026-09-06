class_name GunsLab2VisualRigContract
extends RefCounted

## Visual-only contract published by Guns Lab 2.0.
## Gameplay identity and authority fields never enter this document.

const CURRENT_SCHEMA_VERSION := 1
const VISUAL_FIELDS: Array[String] = [
	"model_fbx",
	"normalized_scale",
	"user_scale_multiplier",
	"model_rotation_degrees",
	"operator_mount",
	"grip_offset",
	"weapon_sockets",
	"support_hand_pose",
	"elbow_poles",
	"stances",
	"animation_hand_maps",
	"animation_frame_pose_keys",
	"handling_profile",
	"gun_placement_line",
	"camo_skin",
	"scope_attachment",
	"silencer_attachment",
]
const REQUIRED_SOCKETS: Array[String] = [
	"right_hand_grip_target",
	"left_hand_ik_target",
	"muzzle_socket",
	"barrel_base_socket",
	"buttstock_socket",
	"optic_rail",
	"ejection_port",
]
const DICTIONARY_VISUAL_FIELDS: Array[String] = [
	"support_hand_pose",
	"elbow_poles",
	"stances",
	"animation_hand_maps",
	"animation_frame_pose_keys",
	"handling_profile",
	"gun_placement_line",
]
const STRING_VISUAL_FIELDS: Array[String] = [
	"camo_skin",
	"scope_attachment",
	"silencer_attachment",
]
const GRIP_OFFSET_COMPONENTS: Array[String] = [
	"pos_x", "pos_y", "pos_z", "rot_x", "rot_y", "rot_z",
]
const FORBIDDEN_GAMEPLAY_FIELDS: Array[String] = [
	"weapon_id",
	"display_name",
	"ballistics",
	"fire_modes",
	"default_fire_mode",
	"burst_size",
	"damage",
	"magazine_capacity",
	"reserve_ammo",
	"penetration",
]


static func extract(
	weapon_profile: Dictionary,
	base_id: String,
	revision: int = 1,
	status: String = "draft"
) -> Dictionary:
	var visual: Dictionary = {}
	for field in VISUAL_FIELDS:
		if weapon_profile.has(field):
			visual[field] = _clone_value(weapon_profile[field])
	return {
		"schema_version": CURRENT_SCHEMA_VERSION,
		"visual_rig_id": base_id,
		"revision": maxi(revision, 1),
		"status": status,
		"source_model_fbx": String(visual.get("model_fbx", "")),
		"family": _visual_family(visual),
		"visual": visual,
		"certification": {
			"required_stances": ["STANDING", "CROUCHED", "PRONE"],
			"required_actions": ["aim_idle", "combat_fire", "reload"],
			"maximum_palm_error_m": 0.005,
			"published_by": "guns_lab_2",
		},
	}


static func merge_for_presentation(
	weapon_profile: Dictionary,
	visual_rig: Dictionary
) -> Dictionary:
	var result := weapon_profile.duplicate(true)
	var validation := validate(visual_rig, true)
	if not bool(validation.get("ok", false)):
		return result
	var visual: Dictionary = visual_rig.get("visual", {})
	for field in VISUAL_FIELDS:
		if visual.has(field):
			result[field] = _clone_value(visual[field])
	# A published visual rig has already passed the complete seven-socket
	# contract below. Mark those inherited contacts as authored so the runtime
	# preserves the physical foregrip instead of moving it like a legacy marker.
	result["socket_contract_authored"] = true
	result["coordinate_space"] = {
		"grip_offset": "weapon_root_local_meters",
		"weapon_sockets": "weapon_pivot_local_meters",
	}
	result["_visual_rig_id"] = String(visual_rig.get("visual_rig_id", ""))
	result["_visual_rig_revision"] = int(visual_rig.get("revision", 0))
	result["_visual_rig_status"] = String(visual_rig.get("status", ""))
	return result


static func published_documents_match(
	existing: Dictionary,
	candidate: Dictionary
) -> bool:
	# Compare the exact canonical representation persisted by _write_json. This
	# normalizes key order and the float precision lost in a JSON disk round trip,
	# while still covering every nested key and value that can reach the file.
	return _persisted_canonical_json(existing) == _persisted_canonical_json(candidate)


static func validate(
	visual_rig: Dictionary,
	require_published: bool = false,
	expected_visual_rig_id: String = ""
) -> Dictionary:
	var errors: Array[String] = []
	var warnings: Array[String] = []
	if int(visual_rig.get("schema_version", 0)) != CURRENT_SCHEMA_VERSION:
		errors.append("unsupported visual-rig schema")
	var visual_rig_id := String(visual_rig.get("visual_rig_id", "")).strip_edges()
	if visual_rig_id.is_empty():
		errors.append("visual_rig_id is required")
	elif not expected_visual_rig_id.is_empty() and visual_rig_id != expected_visual_rig_id:
		errors.append(
			"visual_rig_id does not match requested ID: %s" % expected_visual_rig_id
		)
	if int(visual_rig.get("revision", 0)) < 1:
		errors.append("revision must be at least 1")
	var status := String(visual_rig.get("status", ""))
	if status not in ["draft", "published"]:
		errors.append("status must be draft or published")
	if require_published and status != "published":
		errors.append("runtime accepts published visual rigs only")
	var visual_value: Variant = visual_rig.get("visual", {})
	if not visual_value is Dictionary:
		errors.append("visual must be a dictionary")
		return {"ok": false, "errors": errors, "warnings": warnings}
	var visual := visual_value as Dictionary
	for field: Variant in visual:
		var field_name := String(field)
		if field_name not in VISUAL_FIELDS:
			errors.append("visual field is not allowed: %s" % field_name)
		if field_name in FORBIDDEN_GAMEPLAY_FIELDS:
			errors.append("gameplay field entered visual rig: %s" % field_name)
	var model_path := String(visual.get("model_fbx", ""))
	if model_path.is_empty():
		errors.append("model_fbx is required")
	# Exported FBX sources are remapped to imported PackedScenes, not raw files.
	elif not ResourceLoader.exists(model_path, "PackedScene"):
		errors.append("model_fbx does not exist: %s" % model_path)
	var normalized_scale_value: Variant = visual.get("normalized_scale", null)
	if not _valid_finite_number(normalized_scale_value):
		errors.append("normalized_scale must be a finite number")
	elif float(normalized_scale_value) <= 0.0 or float(normalized_scale_value) > 10.0:
		errors.append("normalized_scale is outside the safe range")
	if visual.has("user_scale_multiplier"):
		var multiplier: Variant = visual.get("user_scale_multiplier")
		if (
			not _valid_finite_number(multiplier)
			or float(multiplier) <= 0.0
			or float(multiplier) > 10.0
		):
			errors.append("user_scale_multiplier is outside the safe range")
	if visual.has("model_rotation_degrees") and not _valid_vector_map(
		visual.get("model_rotation_degrees")
	):
		errors.append("model_rotation_degrees must be a finite vector")
	if visual.has("operator_mount"):
		var mount_value: Variant = visual.get("operator_mount")
		if not mount_value is Dictionary:
			errors.append("operator_mount must be a dictionary")
		else:
			var mount := mount_value as Dictionary
			if not _valid_vector_map(mount.get("position")):
				errors.append("operator_mount.position must be a finite vector")
			if not _valid_vector_map(mount.get("rotation_degrees")):
				errors.append("operator_mount.rotation_degrees must be a finite vector")
	if visual.has("grip_offset"):
		var grip_value: Variant = visual.get("grip_offset")
		if not grip_value is Dictionary:
			errors.append("grip_offset must be a dictionary")
		else:
			var grip := grip_value as Dictionary
			for component in GRIP_OFFSET_COMPONENTS:
				if not grip.has(component) or not _valid_finite_number(grip[component]):
					errors.append("grip_offset.%s must be a finite number" % component)
	for field_name in DICTIONARY_VISUAL_FIELDS:
		if visual.has(field_name) and not visual[field_name] is Dictionary:
			errors.append("%s must be a dictionary" % field_name)
	for field_name in STRING_VISUAL_FIELDS:
		if visual.has(field_name) and not visual[field_name] is String:
			errors.append("%s must be a string" % field_name)
	var sockets_value: Variant = visual.get("weapon_sockets", {})
	if not sockets_value is Dictionary:
		errors.append("weapon_sockets must be a dictionary")
	else:
		var sockets := sockets_value as Dictionary
		for socket_name in REQUIRED_SOCKETS:
			if not sockets.has(socket_name):
				errors.append("required socket is missing: %s" % socket_name)
			elif not _valid_vector_map(sockets[socket_name]):
				errors.append("socket is not a finite vector: %s" % socket_name)
		if errors.is_empty():
			var muzzle := _vector_from_map(sockets["muzzle_socket"])
			var barrel_base := _vector_from_map(sockets["barrel_base_socket"])
			if muzzle.distance_to(barrel_base) < 0.15:
				errors.append("muzzle and barrel base do not define a usable bore")
			var trigger := _vector_from_map(sockets["right_hand_grip_target"])
			var support := _vector_from_map(sockets["left_hand_ik_target"])
			if trigger.distance_to(support) > 1.20:
				errors.append("hand sockets exceed the two-hand calibration envelope")
	var source_model := String(visual_rig.get("source_model_fbx", ""))
	if not source_model.is_empty() and source_model != model_path:
		warnings.append("source_model_fbx differs from the published visual model")
	var certification_value: Variant = visual_rig.get("certification", null)
	if require_published and not certification_value is Dictionary:
		errors.append("published visual rigs require certification metadata")
	elif certification_value is Dictionary:
		var certification := certification_value as Dictionary
		if not certification.get("required_stances", null) is Array:
			errors.append("certification.required_stances must be an array")
		if not certification.get("required_actions", null) is Array:
			errors.append("certification.required_actions must be an array")
		var maximum_error: Variant = certification.get("maximum_palm_error_m", null)
		if not _valid_finite_number(maximum_error) or float(maximum_error) <= 0.0:
			errors.append("certification.maximum_palm_error_m must be positive and finite")
	return {
		"ok": errors.is_empty(),
		"errors": errors,
		"warnings": warnings,
	}


static func _visual_family(visual: Dictionary) -> String:
	var handling: Variant = visual.get("handling_profile", {})
	return (
		String((handling as Dictionary).get("family", "TWO_HAND_RIFLE"))
		if handling is Dictionary
		else "TWO_HAND_RIFLE"
	)


static func _valid_vector_map(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	var map := value as Dictionary
	for axis in ["x", "y", "z"]:
		if not map.has(axis) or not _valid_finite_number(map[axis]):
			return false
	return true


static func _valid_finite_number(value: Variant) -> bool:
	if typeof(value) not in [TYPE_INT, TYPE_FLOAT]:
		return false
	var number := float(value)
	return not is_nan(number) and not is_inf(number)


static func _persisted_canonical_json(document: Dictionary) -> String:
	var persisted := JSON.stringify(document, "", true)
	var reparsed: Variant = JSON.parse_string(persisted)
	return JSON.stringify(reparsed, "", true, true)


static func _vector_from_map(value: Variant) -> Vector3:
	var map := value as Dictionary
	return Vector3(float(map.x), float(map.y), float(map.z))


static func _clone_value(value: Variant) -> Variant:
	if value is Dictionary or value is Array:
		return value.duplicate(true)
	return value
