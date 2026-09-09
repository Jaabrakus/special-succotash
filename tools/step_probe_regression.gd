extends SceneTree

const Player := preload("res://scripts/network/socom_network_operator.gd")
const Probe := preload("res://scripts/player/player_step_probe.gd")
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var player := Player.new()
	player.visual_runtime_enabled = false
	player.set_local_input_enabled(false)
	world.add_child(player)
	player.set_physics_process(false)
	player.position = Vector3(0, 0.001, 0.4)
	var step := _box(world, Vector3(3, 0.18, 2), Vector3(0, 0.09, -1))
	await physics_frame
	var motion := Vector3(0, 0, -0.2)
	_check(Probe.lift(player, motion) > 0.1, "untagged 18cm static step accepted")
	var ceiling := _box(world, Vector3(4, 0.1, 4), Vector3(0, 1.95, 0))
	await physics_frame
	_check(Probe.lift(player, motion) == 0.0, "ceiling rejects full-body rise")
	ceiling.free()
	step.free()
	step = _box(world, Vector3(3, 0.5, 2), Vector3(0, 0.25, -1))
	await physics_frame
	_check(Probe.lift(player, motion) == 0.0, "50cm obstacle is not an automatic step")
	step.free()
	await physics_frame
	_check(Probe.edge_snap_distance(player) < 0, "empty space cannot become fake ground")
	step = _box(world, Vector3(4, 0.1, 4), Vector3(0, -0.6, 0))
	await physics_frame
	_check(Probe.edge_snap_distance(player) < 0, "large drop is not snapped down")
	world.free()
	print("STEP_PROBE_REGRESSION ", "PASS" if failures.is_empty() else "FAIL", " ", failures)
	quit(0 if failures.is_empty() else 1)

func _box(parent: Node3D, size: Vector3, point: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	body.position = point
	parent.add_child(body)
	return body

func _check(ok: bool, label: String) -> void:
	print("STEP_PROBE ", "PASS " if ok else "FAIL ", label)
	if not ok: failures.append(label)
