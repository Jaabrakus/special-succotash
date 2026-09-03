class_name SocomWeaponContactGraphContract
extends RefCounted

## Shared authoring/runtime contract adapted from the Godot 4.6 reference.
## Values are offsets from the current animated/socket-derived pose, so the
## graph improves contact presentation without becoming a second camera,
## movement, weapon-transform, or shot owner.

const SCHEMA_VERSION := 1
const TARGET_IDS := [
	"right_shoulder",
	"trigger_hand",
	"support_hand",
	"spine_aim",
]


static func default_profile() -> Dictionary:
	var targets := {}
	for target_id in TARGET_IDS:
		targets[target_id] = {
			"position_offset_m": _vector_to_data(Vector3.ZERO),
			"rotation_offset_degrees": _vector_to_data(Vector3.ZERO),
		}
	return {
		"schema_version": SCHEMA_VERSION,
		"enabled": true,
		"space": "animated_target_local_offsets_meters",
		"targets": targets,
	}


static func parse(raw: Variant) -> Dictionary:
	var result := default_profile()
	if not raw is Dictionary:
		return result
	var source := raw as Dictionary
	result["enabled"] = bool(source.get("enabled", true))
	var source_targets: Variant = source.get("targets", {})
	if source_targets is Dictionary:
		for target_id in TARGET_IDS:
			var raw_target: Variant = (source_targets as Dictionary).get(target_id, {})
			if not raw_target is Dictionary:
				continue
			var target := raw_target as Dictionary
			result["targets"][target_id] = {
				"position_offset_m": _vector_to_data(
					_vector_from_data(target.get("position_offset_m", {})).clamp(
						Vector3.ONE * -0.35,
						Vector3.ONE * 0.35
					)
				),
				"rotation_offset_degrees": _vector_to_data(
					_vector_from_data(target.get("rotation_offset_degrees", {})).clamp(
						Vector3.ONE * -90.0,
						Vector3.ONE * 90.0
					)
				),
			}
	return result


static func target_position_offset(profile: Dictionary, target_id: String) -> Vector3:
	var target := _target(profile, target_id)
	return _vector_from_data(target.get("position_offset_m", {}))


static func target_rotation_offset_degrees(profile: Dictionary, target_id: String) -> Vector3:
	var target := _target(profile, target_id)
	return _vector_from_data(target.get("rotation_offset_degrees", {}))


static func set_target_position_offset(
	profile: Dictionary,
	target_id: String,
	value: Vector3
) -> void:
	_ensure_target(profile, target_id)["position_offset_m"] = _vector_to_data(value)


static func set_target_rotation_offset_degrees(
	profile: Dictionary,
	target_id: String,
	value: Vector3
) -> void:
	_ensure_target(profile, target_id)["rotation_offset_degrees"] = _vector_to_data(value)


static func apply_offset(source: Transform3D, profile: Dictionary, target_id: String) -> Transform3D:
	if not bool(profile.get("enabled", false)):
		return source
	var position_offset := target_position_offset(profile, target_id)
	var rotation_degrees := target_rotation_offset_degrees(profile, target_id)
	var rotation := Basis.from_euler(rotation_degrees * (PI / 180.0), EULER_ORDER_YXZ)
	return Transform3D(
		(source.basis.orthonormalized() * rotation).orthonormalized(),
		source.origin + source.basis.orthonormalized() * position_offset
	)


static func _target(profile: Dictionary, target_id: String) -> Dictionary:
	var targets: Variant = profile.get("targets", {})
	if not targets is Dictionary:
		return {}
	var target: Variant = (targets as Dictionary).get(target_id, {})
	return target as Dictionary if target is Dictionary else {}


static func _ensure_target(profile: Dictionary, target_id: String) -> Dictionary:
	if not profile.get("targets", {}) is Dictionary:
		profile["targets"] = {}
	var targets := profile["targets"] as Dictionary
	if not targets.get(target_id, {}) is Dictionary:
		targets[target_id] = {
			"position_offset_m": _vector_to_data(Vector3.ZERO),
			"rotation_offset_degrees": _vector_to_data(Vector3.ZERO),
		}
	return targets[target_id] as Dictionary


static func _vector_from_data(raw: Variant) -> Vector3:
	if raw is Vector3:
		return raw
	if raw is Dictionary:
		return Vector3(
			float((raw as Dictionary).get("x", 0.0)),
			float((raw as Dictionary).get("y", 0.0)),
			float((raw as Dictionary).get("z", 0.0))
		)
	return Vector3.ZERO


static func _vector_to_data(value: Vector3) -> Dictionary:
	return {"x": value.x, "y": value.y, "z": value.z}
