class_name SocomWeaponGunPlacementProfile
extends RefCounted

## Parses the saved Gunsmith placement line for visual runtime consumers.
## This data never changes camera aim, muzzle authority, or damage.

const RETICLE_LOCK_DISTANCE_METERS := 120.0


static func reticle_locked_direction(
	camera: Camera3D,
	placement_origin: Vector3,
	reticle_screen_position: Vector2
) -> Vector3:
	if camera == null:
		return Vector3.FORWARD
	var ray_origin := camera.project_ray_origin(reticle_screen_position)
	var ray_direction := camera.project_ray_normal(reticle_screen_position).normalized()
	var reticle_world_target := (
		ray_origin + ray_direction * RETICLE_LOCK_DISTANCE_METERS
	)
	var direction := (reticle_world_target - placement_origin).normalized()
	return ray_direction if direction.length_squared() < 0.50 else direction


static func parse(raw_profile: Variant) -> Dictionary:
	var result := {
		"by_posture": {},
		"authored": false,
		"runtime_enabled": false,
		"direction_mode": "reticle_locked",
	}
	if not raw_profile is Dictionary:
		return result
	result["runtime_enabled"] = bool(raw_profile.get("runtime_enabled", false))
	var raw_stances: Variant = raw_profile.get("by_stance", {})
	if not raw_stances is Dictionary:
		return result
	var parsed_stances: Dictionary = {}
	for posture: StringName in [&"STANDING", &"CROUCHED", &"PRONE"]:
		var raw_stance: Variant = raw_stances.get(String(posture), {})
		if not raw_stance is Dictionary:
			continue
		var offset := _vector_from(raw_stance.get("position_offset_meters", {}))
		var pitch := float(raw_stance.get("pitch_degrees", 0.0))
		var yaw := float(raw_stance.get("yaw_degrees", 0.0))
		var roll := float(raw_stance.get("roll_degrees", 0.0))
		# Presence is authorship. A saved zero-offset stance means “use this
		# stance's live head/eye anchor without an extra trim,” not “disable the
		# blue line.” Treating zero as absent silently disabled crouched and prone
		# FIRE_ACCEPTED placement even though both entries were saved by Gunsmith.
		var authored := true
		parsed_stances[posture] = {
			"position_offset_meters": offset,
			"pitch_degrees": pitch,
			"yaw_degrees": yaw,
			"roll_degrees": roll,
			"authored": authored,
		}
		result["authored"] = bool(result["authored"]) or authored
	result["by_posture"] = parsed_stances
	return result


static func _vector_from(raw: Variant) -> Vector3:
	if raw is Vector3:
		return raw
	if not raw is Dictionary:
		return Vector3.ZERO
	return Vector3(
		float(raw.get("x", 0.0)),
		float(raw.get("y", 0.0)),
		float(raw.get("z", 0.0))
	)
