extends SceneTree

const Motor := preload("res://scripts/traversal/socom_narrow_ledge_motor.gd")
var failures: Array[String] = []
var world: Node3D
var body: CharacterBody3D
var motor: Motor

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	world = Node3D.new()
	root.add_child(world)
	motor = Motor.new()
	var narrow := _box(Vector3(5,2,0.8), Vector3(0,1,0))
	_box(Vector3(5,2,5), Vector3(10,1,0))
	_box(Vector3(5,2,0.2), Vector3(20,1,0))
	var slope := _box(Vector3(5,0.2,4), Vector3(30,2,0))
	slope.rotation.x = deg_to_rad(60)
	body = CharacterBody3D.new()
	body.collision_layer = 2
	body.collision_mask = 1
	var collider := CollisionShape3D.new()
	collider.name = "CollisionShape3D"
	var capsule := CapsuleShape3D.new()
	capsule.height = 1.8
	capsule.radius = 0.32
	collider.shape = capsule
	collider.position.y = capsule.height*0.5
	body.add_child(collider)
	world.add_child(body)
	body.position = Vector3(0,2.08,0)
	await physics_frame
	await physics_frame
	var original := body.global_transform
	var context := _classify(body.position)
	_check(bool(context.get("accepted", false)), "safe narrow top accepted " + str(context))
	_check(not bool(_classify(Vector3(10,2.08,0)).accepted), "broad platform remains ordinary locomotion")
	var landing_inset := 0.32+float(motor.climb_profile.stand_inset_extra_m)
	_check(not bool(_classify(Vector3(10,2.08,2.5-landing_inset)).accepted), "ordinary broad-platform climb landing near edge is not narrow")
	_check(not bool(_classify(Vector3(20,2.08,0)).accepted), "razor platform cannot shrink five-point footprint")
	_check(not bool(_classify(Vector3(30,2.28,0)).accepted), "steep support rejected")
	narrow.add_to_group("no_climb")
	_check(not bool(_classify(body.position).accepted), "no_climb surface rejected")
	narrow.remove_from_group("no_climb")
	narrow.add_to_group("walkable_stairs")
	_check(not bool(_classify(body.position).accepted), "stairs remain normal locomotion")
	narrow.remove_from_group("walkable_stairs")
	motor.climb_profile.require_climbable_group = true
	_check(not bool(_classify(body.position).accepted), "shared tag-required policy respected")
	narrow.add_to_group("climbable")
	_check(bool(_classify(body.position).accepted), "shared allowed tag enables support")
	motor.climb_profile.require_climbable_group = false
	for type_name: String in ["AnimatableBody3D", "RigidBody3D"]:
		var dynamic := ClassDB.instantiate(type_name) as PhysicsBody3D
		dynamic.collision_layer = 1
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(5,2,0.8)
		shape.shape = box
		dynamic.add_child(shape)
		world.add_child(dynamic)
		dynamic.position = Vector3(40,1,0)
		if dynamic is RigidBody3D: dynamic.freeze = true
		await physics_frame
		_check(not bool(_classify(Vector3(40,2.08,0)).accepted), type_name + " cannot become a stationary narrow anchor")
		dynamic.free()
		await physics_frame
	if bool(context.get("accepted", false)):
		var step := motor.solve(body, Vector3(900,0,200), context, 1.0/60.0)
		_check(Vector3(step.velocity).is_equal_approx(Vector3(0.6,-0.5,0)) and not step.finished, "input is capped and projected onto tangent")
		_check(absf(float(step.progress_delta)-0.01)<0.00001, "approved signed progress matches capped step")
		var reverse := motor.solve(body, Vector3(-900,0,0), context, 1.0/60.0)
		_check(Vector3(reverse.velocity).is_equal_approx(Vector3(-0.6,-0.5,0)), "reverse shuffle is equally bounded")
		var forward := motor.solve(body, Vector3.FORWARD, context, 1.0/60.0)
		_check(Vector3(forward.velocity).is_equal_approx(Vector3(0,-0.5,0)) and forward.progress_delta == 0.0, "wall-normal input cannot step off edge")
		var stalled_frame := motor.solve(body, Vector3.RIGHT, context, 2.0)
		_check(absf(float(stalled_frame.progress_delta)) <= 0.030001 and Vector3(stalled_frame.velocity).x*2.0 <= 0.030001, "large frame delta cannot skip a gap")
		_check(body.global_transform == original, "classification and solving never move CharacterBody3D")
		body.position = Vector3(2.22,2.08,0)
		var end := motor.solve(body, Vector3.RIGHT, context, 0.05)
		_check(Vector3(end.velocity).x == 0.0 and not end.finished and end.progress_delta == 0.0, "lateral support end stops before losing footprint")
		body.position = Vector3(1.06,2.08,0)
		var wall := _box(Vector3(0.2,3,1.0), Vector3(1.5,3,0))
		await physics_frame
		var blocked := motor.solve(body, Vector3.RIGHT, context, 0.05)
		_check(Vector3(blocked.velocity).x == 0.0 and blocked.progress_delta == 0.0, "actual capsule sweep stops a blocking wall")
		wall.free()
		await physics_frame
		body.position = Vector3(0,2.08,0)
		var ceiling := _box(Vector3(1,0.2,1), Vector3(0,3.85,0))
		await physics_frame
		_check(not bool(_classify(body.position).accepted), "insufficient overhead capsule room rejects entry")
		var ceiling_step := motor.solve(body, Vector3.RIGHT, context, 0.05)
		_check(Vector3(ceiling_step.velocity).x == 0.0 and ceiling_step.progress_delta == 0.0, "new ceiling blocks an active step")
		ceiling.free()
		await physics_frame
		body.position = Vector3(10,2.08,0)
		_check(bool(motor.solve(body, Vector3.RIGHT, context, 0.05).finished), "broad support finishes narrow mode")
		body.position = Vector3(50,2.08,0)
		_check(bool(motor.solve(body, Vector3.RIGHT, context, 0.05).finished), "lost current support returns movement ownership to normal gravity")
		body.position = Vector3(0,2.08,0)
		for bad in [Vector3.INF, Vector3(NAN,0,0)]:
			var result := motor.solve(body, bad, context, 0.05)
			_check(result.velocity == Vector3.ZERO and result.progress_delta == 0.0, "non-finite input rejected")
		for bad_delta in [0.0, -0.1, NAN, INF]:
			_check(motor.solve(body, Vector3.RIGHT, context, bad_delta).velocity == Vector3.ZERO, "invalid delta rejected " + str(bad_delta))
		for bad_context: Dictionary in [{}, {"surface_normal":Vector3.INF}, {"travel_axis":Vector3.BACK}, {"capsule_radius":0.02}, {"capsule_radius":"bad"}]:
			var bad := context.duplicate()
			if bad_context.is_empty(): bad.clear()
			else: bad.merge(bad_context, true)
			_check(motor.solve(body, Vector3.RIGHT, bad, 0.05).velocity == Vector3.ZERO, "invalid or shrunken capsule context rejected " + str(bad_context))
	_check(not bool(motor.classify(body, Vector3.INF, Vector3.BACK, 1.8, 0.32).accepted), "non-finite landing rejected")
	_check(not bool(motor.classify(body, body.position, Vector3.UP, 1.8, 0.32).accepted), "vertical wall normal rejected")
	_check(not bool(motor.classify(body, body.position, Vector3.BACK, 1.8, 0.02).accepted), "caller cannot shrink the actual capsule")
	world.free()
	print("NARROW_LEDGE_MOTOR ", "PASS" if failures.is_empty() else "FAIL", " ", failures)
	quit(0 if failures.is_empty() else 1)

func _classify(point: Vector3) -> Dictionary:
	return motor.classify(body, point, Vector3.BACK, 1.8, 0.32)

func _box(size: Vector3, point: Vector3) -> StaticBody3D:
	var node := StaticBody3D.new()
	node.collision_layer = 1
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	node.add_child(collision)
	world.add_child(node)
	node.position = point
	return node

func _check(ok: bool, label: String) -> void:
	print("NARROW_CHECK ", "PASS " if ok else "FAIL ", label)
	if not ok: failures.append(label)
