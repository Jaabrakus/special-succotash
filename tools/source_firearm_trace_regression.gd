extends SceneTree

## Test-owned real physics; never loads/restarts a user's main game or edits data.
const Trace := preload("res://scripts/combat/source_firearm_trace.gd")
const MATERIALS := {
	"UNKNOWN": 0.0, "PARTICLE_SYSTEM": 1.0, "WOOD_THIN": 0.25,
	"WOOD_THICK": 0.0, "METAL_THIN": 0.3499999940395355,
	"METAL_THICK": 0.0, "GLASS": 0.9900000095367432,
	"GLASS_THICK": 0.0, "PERSON": 0.9700000286102295,
}
var scene: Node3D
var failures: Array[String] = []
var checks := 0

class Hurtbox extends Area3D:
	var receiver: Node
	func get_damage_receiver() -> Node:
		return receiver
	func get_hit_region() -> StringName:
		return &"TORSO"
	func is_anatomical_hurtbox() -> bool:
		return true

class MovementReceiver extends CharacterBody3D:
	func take_bullet_damage_region() -> void:
		assert(false, "Query helper cannot apply damage")


func _initialize() -> void:
	_run.call_deferred()


func expect(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		push_error(label)


func _run() -> void:
	scene = Node3D.new()
	root.add_child(scene)
	await _sync()
	_scalar_checks()
	for tag: String in ["UNKNOWN", "WOOD_THICK", "METAL_THICK", "GLASS_THICK", "wood", "glass_window", "unmapped"]:
		await _reset()
		var wall := _wall(1.0, tag)
		_person(3.0)
		await _sync()
		var hits := _trace()
		expect(hits.size() == 1 and hits[0].collider == wall, "opaque/unmapped stops " + tag)
		if not hits.is_empty():
			expect(not hits[0].is_target and not hits[0].continues and hits[0].range_after == 0.0, "no fake exit " + tag)
	await _reset()
	var unnamed := _wall(1.0, "")
	unnamed.remove_meta("source_material")
	unnamed.name = "ThinGlassWoodDoor"
	unnamed.set_meta("surface_material", "glass") # Legacy tags do not establish source data.
	_person(3.0)
	await _sync()
	expect(_trace().size() == 1, "no node-name or legacy-material thin inference")
	for tag: String in ["WOOD_THIN", "METAL_THIN", "GLASS", " wood_thin "]:
		await _reset()
		var wall := _wall(2.0, tag)
		var person := _person(10.0)
		await _sync()
		var hits := _trace()
		expect(hits.size() == 2, "explicit source material passes " + tag)
		if hits.size() == 2:
			expect(hits[0].collider == wall and hits[1].receiver == person, "ordered source impacts " + tag)
			expect(hits[0].range_limit == 100.0 and hits[1].range_limit == hits[0].range_after, "global range state " + tag)
			expect(hits[0].exit_pos == hits[0].entry_pos, "no manufactured thickness " + tag)
	await _reset()
	_wall(1.0, "PARTICLE_SYSTEM")
	var visible_person := _person(3.0)
	await _sync()
	var transparent := _trace()
	expect(transparent.size() == 1 and transparent[0].receiver == visible_person, "P1 skips impact")
	if not transparent.is_empty():
		expect(transparent[0].range_limit == 100.0 and not transparent[0].is_wallbang, "P1 does not spend range or create wallbang")
	await _reset()
	var first := _person(2.0, 3)
	var second := _person(5.0, 3)
	await _sync()
	var collateral := _trace()
	expect(collateral.size() == 2, "two people, not six overlapping hurtbox impacts")
	if collateral.size() == 2:
		expect(collateral[0].receiver == first and collateral[1].receiver == second, "ordered distinct receivers")
		expect(collateral[0].source_material == "PERSON" and collateral[1].source_material == "PERSON", "anatomical material explicit")
		expect(collateral[1].range_limit == Trace.reduced_range(100.0, 0.0, MATERIALS.PERSON), "person reduction applied once")
	await _reset()
	var movement := MovementReceiver.new()
	movement.position = Vector3(0, 0, -2.0)
	_shape(movement)
	scene.add_child(movement)
	var anatomy := Hurtbox.new()
	anatomy.receiver = movement
	anatomy.collision_layer = 4
	anatomy.position = Vector3(0, 0, -0.5)
	_shape(anatomy)
	movement.add_child(anatomy)
	var farther_person := _person(5.0)
	await _sync()
	var body_trace := _trace()
	expect(body_trace.size() == 2, "movement body is excluded without replacing hurtbox")
	if body_trace.size() == 2:
		expect(body_trace[0].collider == anatomy and body_trace[0].receiver == movement, "actual animated anatomy wins")
		expect(body_trace[0].range_limit == 100.0 and body_trace[1].receiver == farther_person, "capsule consumes no range and permits collateral")
	await _reset()
	var plain_body := CharacterBody3D.new()
	plain_body.position = Vector3(0, 0, -2)
	_shape(plain_body)
	scene.add_child(plain_body)
	_person(5)
	await _sync()
	var solid_body_trace := _trace()
	expect(solid_body_trace.size() == 1 and solid_body_trace[0].collider == plain_body, "unclassified body stays opaque")
	# A second contact at 30 is only 10m after the wall, but is outside global 25m.
	for distance: float in [24.9, 25.0, 25.1, 30.0]:
		await _reset()
		_wall(20.0, "WOOD_THIN")
		_person(distance)
		await _sync()
		var hits := _trace()
		expect(hits.size() == (2 if distance < 25.0 else 1), "strict global reduced cutoff " + str(distance))
	for distance: float in [99.9, 100.0, 105.0, 110.5]:
		await _reset()
		_person(distance)
		await _sync()
		expect(_trace().size() == (1 if distance < 100.0 else 0), "initial strict padded cutoff " + str(distance))
	await _reset()
	_wall(2.0, "WOOD_THIN")
	_wall(4.0, "WOOD_THIN")
	_person(6.0)
	await _sync()
	var repeated := _trace()
	expect(repeated.size() == 3, "two thin contacts then in-range player")
	if repeated.size() == 3:
		expect(repeated[0].range_after == 25.0 and repeated[1].range_after == 6.25, "repeated absolute-range reduction")
	await _reset()
	var ignored := _wall(1.0, "UNKNOWN")
	_person(3.0)
	await _sync()
	var exclusions: Array[RID] = [ignored.get_rid()]
	var before := exclusions.duplicate()
	expect(_trace(100.0, 0.0, MATERIALS, exclusions).size() == 1, "provided shooter/fixture exclusion preserved")
	expect(exclusions == before, "caller exclusion array not mutated")
	await _reset()
	_wall(-0.125, "UNKNOWN") # The real query begins inside this box.
	_person(3.0)
	await _sync()
	expect(_trace().is_empty(), "origin-overlap blocks without publishing zero-distance impact")
	await _reset()
	_person(-3.0)
	await _sync()
	expect(_trace().is_empty(), "no reversed behind-origin impact")
	await _reset()
	_wall(1.0, "WOOD_THIN")
	_person(3.0)
	await _sync()
	for malformed: Variant in ["0.25", null, true, NAN, INF, -0.01, 1.01]:
		var materials := MATERIALS.duplicate()
		materials.WOOD_THIN = malformed
		var hits := _trace(100.0, 0.0, materials)
		expect(hits.size() == 1 and hits[0].source_material == "UNKNOWN", "invalid coefficient fails closed " + str(malformed))
	var forged := MATERIALS.duplicate()
	forged.UNKNOWN = 1.0
	var node := Node3D.new()
	expect(Trace.material_for(node, null, forged).coefficient == 0.0, "UNKNOWN cannot be made permissive")
	for malformed: Variant in [5, 0.25, null, true, {}, []]:
		node.set_meta("source_material", malformed)
		expect(Trace.material_for(node, null, MATERIALS).name == "UNKNOWN", "malformed material tag fails closed")
	node.free()
	var space := scene.get_world_3d().direct_space_state
	for invalid in [[Vector3(NAN, 0, 0), Vector3.FORWARD, 100.0, 0.0],
		[Vector3.ZERO, Vector3(INF, 0, 0), 100.0, 0.0],
		[Vector3.ZERO, Vector3.ZERO, 100.0, 0.0],
		[Vector3.ZERO, Vector3.FORWARD, NAN, 0.0],
		[Vector3.ZERO, Vector3.FORWARD, -100.0, 0.0],
		[Vector3.ZERO, Vector3.FORWARD, 0.0, 0.0],
		[Vector3.ZERO, Vector3.FORWARD, 100.0, INF],
		[Vector3.ZERO, Vector3.FORWARD, 100.0, -1.0]]:
		expect(Trace.trace(space, invalid[0], invalid[1], invalid[2], invalid[3], [], MATERIALS).is_empty(), "invalid trace input fails closed")
	await _reset()
	for index in Trace.MAX_QUERIES + 2:
		_wall(1.0 + index * 0.3, "PARTICLE_SYSTEM")
	_person(60.0)
	await _sync()
	expect(_trace().is_empty(), "transparent-chain performance bound cannot reach unqueried target")
	scene.queue_free()
	await process_frame
	print("SOURCE_FIREARM_TRACE ", "PASS" if failures.is_empty() else "FAIL", " checks=", checks, " failures=", failures)
	quit(0 if failures.is_empty() else 1)


func _scalar_checks() -> void:
	var fixtures: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://config/reference/socom2_damage_vectors.json"))
	if fixtures is Dictionary and fixtures.get("fixtures", {}).has("penetration"):
		for row: Dictionary in fixtures.fixtures.penetration:
			var input: Dictionary = row.input
			expect(Trace.reduced_range(input.range, input.piercing, input.penetration) == float(row.output.range), "original-instruction range fixture")
	else:
		# Required independent known vector, even before root publishes golden data.
		expect(Trace.reduced_range(1000, 3, 0.25) == 325.0, "original range fixture 1000→325")
	for coefficient: float in [0.0, 0.25, 0.97, 1.0]:
		expect(Trace.reduced_range(100, 10, coefficient) <= 100.0, "source reduction never increases range")


func _trace(maxrange := 100.0, piercing := 0.0, materials := MATERIALS, exclude: Array[RID] = []) -> Array[Dictionary]:
	return Trace.trace(scene.get_world_3d().direct_space_state, Vector3.ZERO, Vector3.FORWARD, maxrange, piercing, exclude, materials)


func _wall(entry_distance: float, material: String) -> StaticBody3D:
	var wall := StaticBody3D.new()
	wall.position = Vector3(0, 0, -entry_distance - 0.125)
	wall.set_meta("source_material", material)
	_shape(wall)
	scene.add_child(wall)
	return wall


func _person(entry_distance: float, count := 1) -> Node3D:
	var receiver := Node3D.new()
	scene.add_child(receiver)
	for index in count:
		var hurtbox := Hurtbox.new()
		hurtbox.receiver = receiver
		hurtbox.collision_layer = 4
		hurtbox.collision_mask = 0
		hurtbox.position = Vector3(0, 0, -entry_distance - 0.125 - index * 0.3)
		_shape(hurtbox)
		receiver.add_child(hurtbox)
	return receiver


func _shape(body: CollisionObject3D) -> void:
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2, 2, 0.25)
	shape.shape = box
	body.add_child(shape)


func _sync() -> void:
	await physics_frame
	await physics_frame


func _reset() -> void:
	for child in scene.get_children():
		child.queue_free()
	await _sync()
