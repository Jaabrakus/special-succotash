extends RefCounted

## Verified ONE_FRAME geometry, not a second weapon/physics/damage owner.
## Source fixtures and adaptation boundaries: docs/SOURCE_FIREARM_RUNTIME.md.
const PATH := "res://config/source_firearm_policy.json"
const POLICY_ID := "socom2_verified_one_frame_v1"
const Dispersion := preload("res://scripts/weapons/source_firearm_dispersion.gd")
const SourceRng := preload("res://scripts/weapons/source_firearm_rng.gd")
const DAMAGE_MODEL := "socom2_mp_regions_v1"
static var _saved: Dictionary = {}


static func legacy() -> Dictionary:
	return {"policy_id": "project_hitscan", "query_range_scale": 1.0,
		"strict_terminal_range": false, "dispersion_distribution": "project_uniform_disk"}


static func resolve(weapon_config: Dictionary) -> Dictionary:
	if _saved.is_empty() and FileAccess.file_exists(PATH):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if parsed is Dictionary:
			_saved = parsed
	return resolve_from_contract(weapon_config, _saved)


static func resolve_from_contract(weapon_config: Dictionary, contract: Dictionary) -> Dictionary:
	# No category inference and no client-supplied shot fields. Configure from the
	# owner's saved weapon only. A missing/malformed identity resets to legacy.
	var profiles: Variant = contract.get("profiles", {})
	var reticle: Variant = weapon_config.get("reticle", {})
	if not profiles is Dictionary or not reticle is Dictionary:
		return legacy()
	var identity: Variant = profiles.get(String(weapon_config.get("weapon_id", "")), {})
	if not identity is Dictionary or identity.is_empty():
		return legacy()
	var source_name: Variant = identity.get("source_name", null)
	if not source_name is String or source_name.is_empty() or source_name != reticle.get("socom2_source_name", null):
		return legacy()
	var scale: Variant = contract.get("query_range_scale", null)
	if not (scale is float or scale is int) or not is_finite(float(scale)):
		return legacy()
	if contract.get("schema_version", 0) != 1 or contract.get("policy_id", "") != POLICY_ID:
		return legacy()
	if String(contract.get("mode", "")) != "one_frame" or contract.get("strict_terminal_range") != true:
		return legacy()
	# This version has one verified equation. Other scales need another reviewed
	# policy/version, not an unchecked extra damage-range tuning knob.
	if not is_equal_approx(float(scale), 1.1):
		return legacy()
	if contract.get("dispersion_distribution", "") != Dispersion.DISTRIBUTION:
		return legacy()
	if contract.get("rng_algorithm", "") != SourceRng.ALGORITHM:
		return legacy()
	var combat: Variant = identity.get("combat", {})
	if contract.get("damage_model", "") != DAMAGE_MODEL or not valid_combat(combat):
		return legacy()
	return {"policy_id": POLICY_ID, "query_range_scale": 1.1,
		"strict_terminal_range": true, "source_name": identity.source_name,
		"rng_algorithm": SourceRng.ALGORITHM,
		"damage_model": DAMAGE_MODEL, "combat": combat.duplicate(true),
		"dispersion_distribution": Dispersion.DISTRIBUTION}


static func valid_combat(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	for key in ["impact_damage", "damage_modifier", "piercing", "effective_range_m", "maximum_range_m", "pellet_count"]:
		var n: Variant = value.get(key)
		if not (n is float or n is int) or not is_finite(float(n)) or (key != "damage_modifier" and float(n) < 0.0):
			return false
	return value.impact_damage + value.damage_modifier >= 0.0 and value.piercing <= 10.0 \
		and value.maximum_range_m > 0.0 and value.maximum_range_m >= value.effective_range_m \
		and value.pellet_count >= 1 and value.pellet_count <= 32 and int(value.pellet_count) == value.pellet_count


static func multiplayer_defaults() -> Dictionary:
	# Load using the same trusted saved contract, not client shot fields.
	if _saved.is_empty():
		resolve({})
	var value: Variant = _saved.get("multiplayer_defaults", {})
	return value.duplicate(true) if value is Dictionary else {}


static func valid_impact(combat: Dictionary, hit_region: StringName) -> bool:
	var distance: Variant = combat.get("distance_m")
	return valid_combat(combat) and (distance is float or distance is int) \
		and is_finite(float(distance)) and float(distance) >= 0.0 and not source_region(hit_region).is_empty()


static func material_coefficients() -> Dictionary:
	if _saved.is_empty(): resolve({})
	var value: Variant = _saved.get("materials", {})
	return value.duplicate(true) if value is Dictionary else {"UNKNOWN": 0.0}


static func source_region(region: StringName) -> StringName:
	var name := String(region)
	if name == "HEAD": return &"head"
	if name in ["TORSO", "PELVIS"]: return &"body"
	var side := "r" if name.begins_with("RIGHT_") else ("l" if name.begins_with("LEFT_") else "")
	if side.is_empty(): return &""
	if "ARM" in name: return StringName(side + "arm")
	if "LEG" in name or "THIGH" in name or "CALF" in name or "FOOT" in name:
		return StringName(side + "leg")
	return &""


static func accepts_impact(origin: Vector3, impact: Vector3, maximum_range: float,
	strict_terminal_range: bool) -> bool:
	if not strict_terminal_range:
		return true
	if not origin.is_finite() or not impact.is_finite() or not is_finite(maximum_range) or maximum_range <= 0.0:
		return false
	var distance_squared := origin.distance_squared_to(impact)
	return distance_squared > 0.0 and distance_squared < maximum_range * maximum_range
