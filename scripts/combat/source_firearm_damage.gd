class_name SourceFirearmDamage
extends RefCounted
## Pure source-equation state. Existing receiver remains the only damage writer.
## PCs and provenance: docs/SOURCE_DAMAGE_EQUATION_DECODE.md.

const REGIONS: Array[StringName] = [&"head", &"rarm", &"larm", &"body", &"rleg", &"lleg"]

var alive: bool = false
var _initialized: bool = false
var _health: Array[float] = []
var _maxima: Array[float] = []
var _armor: Array[float] = []
var _rounding := PackedFloat32Array([0.0])


func initialize(defaults: Dictionary) -> bool:
	var hp: Variant = defaults.get("health")
	var protection: Variant = defaults.get("armor")
	if not hp is Dictionary or not protection is Dictionary:
		return false
	var staged_health: Array[float] = []
	var staged_armor: Array[float] = []
	for region in REGIONS:
		var h: Variant = hp.get(String(region))
		var a: Variant = protection.get(String(region))
		if not _valid_number(h) or not _valid_number(a):
			return false
		var hf := _f32(float(h))
		var af := _f32(float(a))
		if not is_finite(hf) or not is_finite(af) or hf <= 0.0 or af < 0.0:
			return false
		staged_health.append(hf)
		staged_armor.append(af)
	_health = staged_health
	_maxima = staged_health.duplicate()
	_armor = staged_armor
	alive = true
	_initialized = true
	return true


func apply_projectile(impact_damage: float, modifier: float, piercing: float,
		distance: float, effective_range: float, maximum_range: float,
		region: StringName) -> Dictionary:
	var index := REGIONS.find(region)
	if not _initialized or not alive or index < 0 or not is_finite(piercing) or piercing < 0.0 or piercing > 10.0:
		return {"accepted": false, "changed": false}
	var damage := calculate_projectile_damage(impact_damage, modifier, distance, effective_range, maximum_range)
	if not is_finite(damage):
		return {"accepted": false, "changed": false}
	var before_ratio := weighted_health_ratio()
	var before_health := _sum(_health)
	var before_armor := _sum(_armor)
	var before_region := _health[index]
	var changed := _apply_region_damage(damage, _f32(piercing), index)
	alive = _health[0] > 0.0 and _health[3] > 0.0
	var hp_damage := before_health - _sum(_health)
	return {
		"accepted": true, "changed": changed, "region": String(region),
		"source_damage": damage, "hp_damage": hp_damage, "health_damage": hp_damage,
		"region_damage": before_region - _health[index], "armor_damage": before_armor - _sum(_armor),
		"before_ratio": before_ratio, "health_ratio": weighted_health_ratio(),
		"after_ratio": weighted_health_ratio(), "alive": alive, "killed": not alive,
	}


func calculate_projectile_damage(impact: float, modifier: float, distance: float,
		effective: float, maximum: float, minimum_damage: float = 0.0) -> float:
	for value in [impact, modifier, distance, effective, maximum, minimum_damage]:
		if not is_finite(value) or not is_finite(_f32(value)):
			return NAN
	if impact < 0.0 or distance < 0.0 or effective < 0.0 or maximum < 0.0 or minimum_damage < 0.0:
		return NAN
	var damage := _f32(_f32(impact) + _f32(modifier))
	distance = _f32(distance)
	effective = _f32(effective)
	maximum = _f32(maximum)
	if distance > effective:
		var width := _f32(maximum - effective)
		damage = 0.0 if width <= 0.0 else _f32(damage * _f32(1.0 - _f32(_f32(distance - effective) / width)))
	if damage == 0.0 or damage < _f32(minimum_damage):
		return 0.0
	return _f32(14.0 * damage)


func weighted_health_ratio() -> float:
	if not _initialized or not alive:
		return 0.0
	var numerator := _f32(3.0 * _health[0])
	var denominator := _f32(3.0 * _maxima[0])
	for index in [3, 1, 2, 4, 5]:
		numerator = _f32(numerator + _health[index])
		denominator = _f32(denominator + _maxima[index])
	return 0.0 if denominator <= 0.0 else _f32(numerator / denominator)


func cap_legacy_health_ratio(ratio: float) -> bool:
	## NON-SOURCE adapter: interleaved legacy/explosion damage can never heal pools.
	if not _initialized or not is_finite(ratio):
		return false
	ratio = clampf(ratio, 0.0, 1.0)
	var current := weighted_health_ratio()
	if current <= ratio or current <= 0.0:
		return false
	var scale := ratio / current
	for index in range(6):
		_health[index] = minf(_health[index], _f32(_health[index] * scale))
	alive = _health[0] > 0.0 and _health[3] > 0.0
	# Float32 round-to-nearest can put the computed ratio one ULP over the cap.
	if weighted_health_ratio() > ratio:
		for index in range(6):
			_health[index] = _f32(_health[index] * 0.9999998)
	return true


func snapshot() -> Dictionary:
	var health: Dictionary = {}
	var maxima: Dictionary = {}
	var armor: Dictionary = {}
	if _initialized:
		for index in range(6):
			health[String(REGIONS[index])] = _health[index]
			maxima[String(REGIONS[index])] = _maxima[index]
			armor[String(REGIONS[index])] = _armor[index]
	return {"schema_version": 1, "initialized": _initialized, "health": health,
		"maxima": maxima, "armor": armor, "alive": alive, "health_ratio": weighted_health_ratio()}


func _apply_region_damage(damage: float, piercing: float, index: int) -> bool:
	if damage <= 0.0 or index < 0 or index >= 6:
		return false
	if _health[index] <= 0.0:
		if index == 0 or index == 3:
			return false
		return _apply_region_damage(_f32(damage * _f32(0.3)), 10.0, 3)
	var through := maxf(0.0, _f32(damage - _f32(_armor[index] * _f32(_f32(10.0 - piercing) / 10.0))))
	_armor[index] = maxf(0.0, _f32(_armor[index] - _f32(_f32(damage - through) / 4.0)))
	_health[index] = maxf(0.0, _f32(_health[index] - through))
	if index == 3:
		var fraction := _f32(_health[3] / _maxima[3])
		for limb in [2, 1, 5, 4]:
			_health[limb] = minf(_health[limb], _f32(_maxima[limb] * fraction))
	return true


func _f32(value: float) -> float:
	_rounding[0] = value
	return _rounding[0]


func _valid_number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))


func _sum(values: Array[float]) -> float:
	var result := 0.0
	for value in values:
		result += value
	return result
