extends SceneTree
## Pure original-code golden vectors; does not instantiate another damage owner.

const Damage = preload("res://scripts/combat/source_firearm_damage.gd")
const VECTORS := "res://config/reference/socom2_damage_vectors.json"
var checks := 0
var failures: Array[String] = []
var defaults: Dictionary = {}


func _init() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(VECTORS))
	if not parsed is Dictionary:
		_expect(false, "golden vector file parses")
		_finish()
		return
	defaults = parsed.source.multiplayer_profiles[0]
	var vectors: Dictionary = parsed.fixtures
	var damage = Damage.new()
	_expect(damage.initialize(defaults), "initialize original multiplayer defaults")
	for row in vectors.range_damage:
		var c: Dictionary = row.input
		var actual: float = damage.calculate_projectile_damage(c.impact, c.modifier, c.distance, c.effective, c.maximum, c.get("minimumDamage", 0.0))
		_equal(actual, float(row.output), "range " + str(c))
	for row in vectors.armor:
		var c: Dictionary = row.input
		_expect(damage.initialize(defaults), "reset armor fixture")
		damage._health[3] = damage._f32(c.hp)
		damage._armor[3] = damage._f32(c.armor)
		damage._apply_region_damage(damage._f32(c.damage), damage._f32(c.piercing), 3)
		_equal(damage._health[3], float(row.output.hp), "armor HP " + str(c))
		_equal(damage._armor[3], float(row.output.armor), "armor wear " + str(c))
	for row in vectors.body_pools:
		var c: Dictionary = row.input
		_seed(damage, c)
		var changed: bool = damage._apply_region_damage(damage._f32(c.damage), damage._f32(c.piercing), int(c.region))
		_expect(changed == bool(row.output.changed), "source pool changed flag " + str(c.region))
		for index in range(6):
			_equal(damage._health[index], float(row.output.health[index]), "pool HP " + str(c.region) + "/" + str(index))
			_equal(damage._armor[index], float(row.output.armor[index]), "pool armor " + str(c.region) + "/" + str(index))
	for row in vectors.health_ratio:
		_seed(damage, row.input)
		damage.alive = row.input.active
		_equal(damage.weighted_health_ratio(), float(row.output), "weighted source health")
	for row in vectors.death_condition:
		_seed(damage, row.input)
		damage.alive = row.input.active
		var dead: bool = not damage.alive or damage._health[0] <= 0.0 or damage._health[3] <= 0.0
		_expect(dead == row.output, "source head/body death decision")
	_boundaries(damage)
	_finish()


func _seed(damage: RefCounted, input: Dictionary) -> void:
	damage.initialize(defaults)
	for index in range(6):
		damage._health[index] = damage._f32(input.health[index])
		damage._maxima[index] = damage._f32(input.maxima[index] if input.has("maxima") else defaults.health[String(Damage.REGIONS[index])])
		if input.has("armor"):
			damage._armor[index] = damage._f32(input.armor[index])


func _boundaries(damage: RefCounted) -> void:
	damage.initialize(defaults)
	# Separately executed original 0x3c7600 negative-modifier cases: source
	# 9mm Pistol/HK5SD and M63A. Signed modifier is valid; damage cannot be negative.
	_equal(damage.calculate_projectile_damage(1.5, -0.2, 0.0, 40.0, 85.0), 18.19999885559082, "source negative 9mm modifier")
	_equal(damage.calculate_projectile_damage(1.5, -0.2, 0.0, 110.0, 250.0), 18.19999885559082, "source negative HK5SD modifier")
	_equal(damage.calculate_projectile_damage(2.3, -0.4, 0.0, 400.0, 800.0), 26.600000381469727, "source negative M63A modifier")
	var hit: Dictionary = damage.apply_projectile(2.3, 0.3, 3.0, 0.0, 50.0, 100.0, &"body")
	_expect(hit.accepted and hit.changed and damage.alive, "first M4 body hit survives")
	_equal(hit.source_damage, damage._f32(damage._f32(damage._f32(2.3) + damage._f32(0.3)) * 14.0), "source damage x14")
	_expect(hit.hp_damage > hit.region_damage and hit.region_damage > 0.0, "body damage caps limbs separately")
	_expect(hit.health_ratio < 1.0 and hit.health_ratio > 0.0, "HUD exposes weighted health")
	damage.apply_projectile(2.3, 0.3, 3.0, 0.0, 50.0, 100.0, &"body")
	hit = damage.apply_projectile(2.3, 0.3, 3.0, 0.0, 50.0, 100.0, &"body")
	_expect(not damage.alive and hit.killed, "body depletion kills")
	_equal(damage.weighted_health_ratio(), 0.0, "dead body returns zero HUD health despite head pool")
	var before: Dictionary = damage.snapshot()
	_expect(not damage.apply_projectile(2.3, 0.3, 3.0, 0.0, 50.0, 100.0, &"body").accepted, "dead target rejects further source damage")
	_expect(before == damage.snapshot(), "dead state unchanged")
	damage.initialize(defaults)
	hit = damage.apply_projectile(2.3, 0.3, 3.0, 0.0, 50.0, 100.0, &"head")
	_expect(hit.killed and not damage.alive, "unarmored eight-point head dies")
	damage.initialize(defaults)
	hit = damage.apply_projectile(10.0, 0.0, 10.0, 0.0, 50.0, 100.0, &"rarm")
	_equal(damage._health[3], 50.0, "first limb depletion does not spill excess into body")
	_expect(damage.alive and damage._health[1] == 0.0, "limb alone not fatal")
	hit = damage.apply_projectile(1.0, 0.0, 0.0, 0.0, 50.0, 100.0, &"rarm")
	_equal(damage._health[3], damage._f32(50.0 - damage._f32(14.0 * damage._f32(0.3))), "depleted limb redirects thirty percent ignoring body armor")
	_equal(damage._armor[3], 25.0, "redirect piercing ten does not wear body armor")
	damage._health[3] = 0.0
	_expect(not damage._apply_region_damage(20.0, 3.0, 3), "depleted body does not recurse")
	_expect(not damage._apply_region_damage(20.0, 3.0, 1), "depleted limb to depleted body terminates")
	damage.initialize(defaults)
	before = damage.snapshot()
	var altered: Dictionary = damage.snapshot()
	altered.health.head = 0.0
	_expect(before == damage.snapshot(), "snapshot isolated from runtime pools")
	for bad in [NAN, INF, -INF]:
		_expect(not damage.apply_projectile(bad, 0.0, 3.0, 0.0, 50.0, 100.0, &"body").accepted, "nonfinite impact rejected")
		_expect(not damage.apply_projectile(2.3, 0.0, bad, 0.0, 50.0, 100.0, &"body").accepted, "nonfinite piercing rejected")
		_expect(not damage.apply_projectile(2.3, bad, 3.0, 0.0, 50.0, 100.0, &"body").accepted, "nonfinite modifier rejected")
	_expect(not damage.apply_projectile(2.3, 0.0, 3.0, -1.0, 50.0, 100.0, &"body").accepted, "negative distance rejected")
	_expect(not damage.apply_projectile(2.3, 0.0, 3.0, 0.0, 50.0, 100.0, &"torso").accepted, "unsupported region rejected, not guessed")
	_expect(not damage.apply_projectile(2.3, 0.0, 11.0, 0.0, 50.0, 100.0, &"body").accepted, "out-of-domain piercing rejected")
	_expect(not damage.initialize({"health": {"head": 1}, "armor": {}}), "malformed defaults rejected")
	_expect(before == damage.snapshot(), "all invalid inputs preserve original snapshot")
	var blank = Damage.new()
	_expect(not blank.apply_projectile(2.3, 0.0, 3.0, 0.0, 50.0, 100.0, &"body").accepted, "uninitialized target rejects")
	for cap in [0.75, 0.23456789, 0.00001, 0.0]:
		var pool_before: Array[float] = damage._health.duplicate()
		_expect(damage.cap_legacy_health_ratio(cap), "NON-SOURCE legacy cap reduces health")
		_expect(damage.weighted_health_ratio() <= cap, "legacy cap bounds weighted health")
		for index in range(6):
			_expect(damage._health[index] <= pool_before[index], "legacy cap never raises any pool")
		before = damage.snapshot()
		_expect(not damage.cap_legacy_health_ratio(1.0), "legacy increase ignored")
		_expect(before == damage.snapshot(), "legacy increase cannot heal")
	_expect(not damage.alive, "legacy zero cap kills")


func _equal(actual: float, expected: float, label: String) -> void:
	# JSON decimal parsing is not bit-preserving double serialization. The source
	# values are float32, so round expected to that exact domain, not a tolerance.
	var source_expected := PackedFloat32Array([expected])[0]
	_expect(actual == source_expected, "%s actual=%s expected=%s" % [label, actual, source_expected])


func _expect(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		push_error("SOURCE_DAMAGE_FAIL " + label)


func _finish() -> void:
	print("SOURCE_FIREARM_DAMAGE_REGRESSION %s checks=%d failures=%d" % ["PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
