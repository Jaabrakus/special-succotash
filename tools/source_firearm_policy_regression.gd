extends SceneTree

## Translation/acceptance: docs/SOURCE_FIREARM_RUNTIME.md. Test-owned physics
## fixtures; no saved setting, movement, aim, damage or running-session writes.
const Policy := preload("res://scripts/weapons/source_firearm_policy.gd")
const Ballistics := preload("res://scripts/weapons/weapon_ballistics.gd")
const Penetration := preload("res://scripts/combat/socom_bullet_penetration.gd")
const Dispersion := preload("res://scripts/weapons/source_firearm_dispersion.gd")
const SourceRng := preload("res://scripts/weapons/source_firearm_rng.gd")
var failures: Array[String] = []
var checks := 0
var scene: Node3D
var gun: Node
var signals_seen := 0

class Target extends Area3D:
	func get_hit_region() -> StringName:
		return &"TORSO"
	func get_damage_receiver() -> Node:
		return self


func _initialize() -> void:
	_run.call_deferred()


func expect(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)


func profile(id: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://config/weapons/" + id + ".json"))


func _run() -> void:
	_check_direction_vectors()
	var contract: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Policy.PATH))
	var supported := 0
	var total := 0
	for file in DirAccess.get_files_at("res://config/weapons"):
		if not file.ends_with(".json"):
			continue
		var p: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://config/weapons/" + file))
		if not p.has("weapon_id") or not p.has("ballistics"):
			continue
		total += 1
		var result := Policy.resolve(p)
		if contract.profiles.has(String(p.weapon_id)):
			supported += 1
			expect(result.policy_id == Policy.POLICY_ID and result.strict_terminal_range, file + " explicit identity")
			expect(is_equal_approx(result.query_range_scale, 1.1), file + " padded query")
		else:
			expect(result == Policy.legacy(), file + " unsupported resets")
	expect(supported == 32 and total == 45, "32 explicit profiles; no inferred equipment")
	var m4 := profile("m4a1")
	var bad_identity := m4.duplicate(true)
	bad_identity.reticle.socom2_source_name = "UNVERIFIED"
	expect(Policy.resolve(bad_identity) == Policy.legacy(), "source name mismatch fails closed")
	var missing_name := contract.duplicate(true)
	missing_name.profiles.m4a1.erase("source_name")
	var missing_reference := m4.duplicate(true)
	missing_reference.reticle.erase("socom2_source_name")
	expect(Policy.resolve_from_contract(missing_reference, missing_name) == Policy.legacy(), "missing names cannot match")
	expect(Policy.resolve({"category": "Assault Rifles"}) == Policy.legacy(), "category alone is not identity")
	for malformed in [NAN, INF, -1.0, 0.0, 1.2, "1.1", null]:
		var bad := contract.duplicate(true)
		bad.query_range_scale = malformed
		expect(Policy.resolve_from_contract(m4, bad) == Policy.legacy(), "invalid scale rejected")
	var wrong_mode := contract.duplicate(true)
	wrong_mode.mode = "temporal"
	expect(Policy.resolve_from_contract(m4, wrong_mode) == Policy.legacy(), "unsupported temporal mode rejected")
	# Same boundary cases executed against original FTSCore at 0x3c9cd8.
	for row in [[0.0, false], [999.9, true], [1000.0, false], [1050.0, false], [1100.0, false]]:
		expect(Policy.accepts_impact(Vector3.ZERO, Vector3(0, 0, -float(row[0])), 1000.0, true) == row[1],
			"original strict cutoff " + str(row[0]))
	expect(not Policy.accepts_impact(Vector3.ZERO, Vector3(INF, 0, 0), 1000.0, true), "nonfinite impact rejected")
	expect(not Policy.accepts_impact(Vector3.ZERO, Vector3.FORWARD, NAN, true), "nonfinite range rejected")
	expect(not Policy.accepts_impact(Vector3.ZERO, Vector3.FORWARD, 0.0, true), "zero range rejected")

	scene = Node3D.new()
	root.add_child(scene)
	gun = Ballistics.new()
	scene.add_child(gun)
	gun.set_process(false)
	gun.configure_projectiles(m4.ballistics, m4)
	gun.wallbang_penetrated.connect(func(_a: Vector3, _b: Vector3, _d: float): signals_seen += 1)
	gun.max_range = 10.0
	gun.base_spread_deg = 0.0
	gun.moving_spread_deg = 0.0
	gun.full_gait_spread_deg = 0.0
	gun.bloom_per_shot_deg = 0.0
	gun.damage_per_shot = 34.0
	await physics_frame
	var target := Target.new()
	target.collision_layer = 4
	_add_shape(target, Vector3(4, 4, 1))
	scene.add_child(target)
	for distance in [9.5, 10.0, 10.02, 10.5, 11.5]:
		target.position = Vector3(0, 0, -distance - 0.5)
		await physics_frame
		await physics_frame
		var shot := fire()
		var expected_hit: bool = float(distance) < 10.0
		expect(bool(shot.fired), "source shot accepted")
		expect((shot.hit_collider == target) == expected_hit, "direct+anatomical cutoff at " + str(distance))
		expect(bool(shot.hit_target) == expected_hit, "target classification at " + str(distance))
		expect(shot.trajectory_policy == Policy.POLICY_ID, "canonical projectile carries policy identity")
		for hit in shot.penetrations:
			expect(Policy.accepts_impact(Vector3.ZERO, hit.entry_pos, 10.0, true), "every published penetration in range")
		if not expected_hit:
			expect(Vector3(shot.hit_pos).is_equal_approx(Vector3(0, 0, -10)), "miss endpoint does not gain ten percent")
	# Prove the padding-region target exists and the unguarded query sees it.
	target.position = Vector3(0, 0, -11.0)
	await physics_frame
	await physics_frame
	var space := scene.get_world_3d().direct_space_state
	var padded_query := Penetration.trace_bullet(space, Vector3.ZERO, Vector3.FORWARD, 11.0, 34.0)
	expect(not padded_query.is_empty(), "real padded candidate exists at 10.5m")
	# A legal wallbang may not leak a later out-of-range damage record/signal.
	var wall := StaticBody3D.new()
	wall.name = "WoodSourceRangeFixture"
	wall.position = Vector3(0, 0, -3)
	wall.set_meta("surface_material", "wood")
	_add_shape(wall, Vector3(4, 4, 0.125))
	scene.add_child(wall)
	await physics_frame
	await physics_frame
	signals_seen = 0
	var blocked := fire()
	expect(not blocked.penetrations.is_empty(), "near thin wall detected")
	for hit in blocked.penetrations:
		expect(hit.collider != target, "collateral past maxrange never published")
	expect(signals_seen == 0, "out-of-range collateral emits no wallbang signal")
	expect(blocked.hit_collider != target, "fallback cannot resurrect out-of-range collateral")
	wall.queue_free()
	await physics_frame
	await physics_frame
	# Exercise the selected sampler in the real shot loop, not just its helper.
	gun.fire_cooldown = 0.0
	gun.base_spread_deg = 3.0
	var exclude: Array[RID] = []
	var sampled: Dictionary = gun.try_fire_direction(Vector3.ZERO, Vector3.FORWARD,
		space, exclude, 24681357, &"STANDING", 0.0, false, 1.0)
	var rng := SourceRng.new()
	rng.seed_from_u32(24681357)
	var first := rng.next_raw()
	var draws := SourceRng.signed_draw_pair(first, rng.next_raw())
	var expected_direction := Dispersion.direction_in_envelope(Vector3.FORWARD, sampled.cone_tangent_radius, draws)
	expect(Vector3(sampled.direction).is_equal_approx(expected_direction), "actual seeded shot uses original direction equation")
	expect(sampled.dispersion_distribution == Dispersion.DISTRIBUTION, "accepted shot reports source distribution")
	gun.configure_projectiles({}, {})
	expect(gun.trajectory_policy == Policy.legacy(), "supported-to-unsupported equip resets policy")
	gun.configure_projectiles(m4.ballistics, m4)
	var shotgun := profile("870")
	gun.configure_projectiles(shotgun.ballistics, shotgun)
	expect(gun.pellet_count == 4 and gun.pellet_damage == 35.0, "original four 35-unit pellets")
	gun.max_range = 10.0
	gun.pellet_spread_deg = 0.0
	target.position = Vector3(0, 0, -11)
	await physics_frame
	await physics_frame
	var shell := fire()
	expect(shell.projectiles.size() == 4, "each accepted shell traces four original pellets")
	for pellet in shell.projectiles:
		expect(pellet.hit_collider != target, "each pellet obeys source cutoff")
	scene.queue_free()
	await process_frame
	print("SOURCE_FIREARM_POLICY ", "PASS" if failures.is_empty() else "FAIL", " checks=", checks,
		" profiles=", supported, " failures=", failures)
	quit(0 if failures.is_empty() else 1)


func fire() -> Dictionary:
	gun.fire_cooldown = 0.0
	var exclude: Array[RID] = []
	return gun.try_fire_direction(Vector3.ZERO, Vector3.FORWARD,
		scene.get_world_3d().direct_space_state, exclude, 8675309, &"STANDING", 0.0, false, 0.0)


func _add_shape(body: CollisionObject3D, size: Vector3) -> void:
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	collision.shape = box
	body.add_child(collision)


func _check_direction_vectors() -> void:
	var evidence: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://config/reference/socom2_fire_direction_vectors.json"))
	expect(evidence.get("status") == "PASS" and evidence.fixtures.size() == 14, "14 original-instruction golden directions")
	for row in evidence.fixtures:
		var direction := vec3(row.direction)
		var accuracy := vec3(row.accuracy)
		var draws := Vector2(row.expected.draws[0].u, row.expected.draws[1].u)
		var actual := Dispersion.raw_direction(direction, accuracy, draws)
		var expected := vec3(row.original_execution.raw_direction)
		expect(actual.distance_to(expected) <= 0.000002, "original raw direction vector match")
		expect(actual.normalized().distance_to(vec3(row.expected.normalized_direction_for_adapted_consumer)) <= 0.000002,
			"normalized ONE_FRAME direction vector match")
	var random := RandomNumberGenerator.new()
	random.seed = 54321
	var radius := 0.03
	for direction in [Vector3.FORWARD, Vector3(0, 0.6, -0.8), Vector3(0.6, 0.0, -0.8), Vector3.UP, Vector3.DOWN]:
		for sample in 400:
			var draws := Vector2(random.randf() * 2.0 - 1.0, random.randf() * 2.0 - 1.0)
			var actual := Dispersion.direction_in_envelope(direction, radius, draws)
			var forward_component: float = actual.dot(direction)
			var tangent: float = (actual - direction * forward_component).length() / forward_component
			expect(actual.is_finite() and is_equal_approx(actual.length(), 1.0), "finite normalized direction")
			expect(tangent <= radius + 0.000001, "source distribution stays inside authored envelope")
		var corner := Dispersion.direction_in_envelope(direction, radius, Vector2.ONE)
		var forward_component: float = corner.dot(direction)
		expect((corner - direction * forward_component).length() / forward_component <= radius + 0.000001,
			"extreme square corner fits circular reticle")
	expect(Dispersion.direction_in_envelope(Vector3.UP, radius, Vector2.ONE) == Vector3.UP,
		"verified vertical-axis collapse is explicit")
	expect(is_equal_approx(Dispersion.signed_square(-0.5), -0.25), "negative draw remains negative")
	expect(is_equal_approx(Dispersion.signed_square(0.5), 0.25), "positive draw squared toward center")


func vec3(values: Array) -> Vector3:
	return Vector3(float(values[0]), float(values[1]), float(values[2]))
