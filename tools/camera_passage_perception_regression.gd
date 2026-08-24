extends SceneTree

const PassagePolicy := preload("res://scripts/camera/camera_passage_policy.gd")
const PerceptionSensor := preload("res://scripts/camera/tactical_perception_sensor.gd")
const MapRuntime := preload("res://scripts/maps/socom_map_runtime.gd")

var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var world_root := Node3D.new()
	root.add_child(world_root)
	var soft := _make_wall("SoftDoorTrim", Vector3(0.0, 0.0, -2.0))
	world_root.add_child(soft)
	MapRuntime._apply_camera_passage_policy(
		soft,
		{"properties": {"camera_soft_occluder": true}}
	)
	_expect(
		soft.is_in_group("camera_soft_occluder"),
		"map property exposes an explicit camera-soft authoring control"
	)
	var hard := _make_wall("HardBuildingWall", Vector3(0.0, 0.0, -3.3))
	world_root.add_child(hard)
	await physics_frame

	var policy := PassagePolicy.new()
	var camera_shape := SphereShape3D.new()
	camera_shape.radius = 0.20
	var blocked: Dictionary = policy.cast_camera_motion(
		world_root.get_world_3d(),
		camera_shape,
		Vector3.ZERO,
		Vector3(0.0, 0.0, -5.0),
		0.02,
		[]
	)
	print("CAMERA_PASSAGE_METRIC hard_safe=%.3f skipped_soft=%d" % [
		float(blocked.get("safe_fraction", 1.0)),
		int(blocked.get("soft_occluder_count", 0)),
	])
	_expect(
		int(blocked.get("soft_occluder_count", 0)) >= 1,
		"camera passage skips explicitly tagged soft doorway geometry"
	)
	_expect(
		float(blocked.get("safe_fraction", 1.0)) < 0.999,
		"untagged building wall remains a hard camera blocker"
	)
	hard.queue_free()
	await physics_frame
	var clear: Dictionary = policy.cast_camera_motion(
		world_root.get_world_3d(),
		camera_shape,
		Vector3.ZERO,
		Vector3(0.0, 0.0, -5.0),
		0.02,
		[]
	)
	_expect(
		float(clear.get("safe_fraction", 0.0)) >= 0.999,
		"soft doorway geometry alone does not cramp the rendered camera"
	)
	soft.queue_free()
	await physics_frame

	var observer := Node3D.new()
	observer.set_meta("team_id", 0)
	world_root.add_child(observer)
	var camera := Camera3D.new()
	camera.fov = 68.0
	observer.add_child(camera)
	var sensor := PerceptionSensor.new()
	observer.add_child(sensor)
	sensor.configure(camera, observer)
	var enemy := Node3D.new()
	enemy.position = Vector3(0.0, -1.35, -5.0)
	enemy.set_meta("team_id", 1)
	world_root.add_child(enemy)
	await process_frame
	var visible_contacts: Array[Dictionary] = sensor.scan_candidates([enemy])
	_expect(
		visible_contacts.size() == 1
		and StringName(visible_contacts[0].get("relationship", &"")) == &"ENEMY",
		"non-rendering sensor classifies a visible enemy in the real camera frustum"
	)
	var los_wall := _make_wall("PerceptionWall", Vector3(0.0, 0.0, -2.5))
	world_root.add_child(los_wall)
	await physics_frame
	var hidden_contacts: Array[Dictionary] = sensor.scan_candidates([enemy])
	_expect(
		hidden_contacts.is_empty(),
		"sensor never reveals an enemy through unapproved world geometry"
	)
	world_root.queue_free()
	_finish()


func _make_wall(node_name: String, position_value: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = node_name
	body.position = position_value
	var shape_node := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(2.0, 2.0, 0.20)
	shape_node.shape = shape
	body.add_child(shape_node)
	return body


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("CAMERA_PASSAGE_CHECK PASS %s" % label)
	else:
		failures.append(label)
		push_error("CAMERA_PASSAGE_CHECK FAIL %s" % label)


func _finish() -> void:
	if failures.is_empty():
		print("CAMERA_PASSAGE_PERCEPTION_REGRESSION PASS")
		quit(0)
	else:
		push_error("CAMERA_PASSAGE_PERCEPTION_REGRESSION FAIL %s" % [failures])
		quit(1)
