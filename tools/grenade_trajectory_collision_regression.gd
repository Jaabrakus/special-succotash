extends SceneTree

const GrenadeBase := preload("res://scripts/tactical/tactical_grenade_base.gd")
const Trajectory := preload("res://scripts/runtime/main_grenade_trajectory.gd")

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var arena := Node3D.new()
	root.add_child(arena)
	var wall := StaticBody3D.new()
	wall.collision_layer = GrenadeBase.COLLISION_MASK
	wall.collision_mask = GrenadeBase.COLLISION_MASK
	wall.position = Vector3(0.0, 1.0, -1.0)
	var wall_collision := CollisionShape3D.new()
	var wall_shape := BoxShape3D.new()
	wall_shape.size = Vector3(4.0, 4.0, 0.10)
	wall_collision.shape = wall_shape
	wall.add_child(wall_collision)
	arena.add_child(wall)
	await physics_frame

	var trajectory := Trajectory.new()
	trajectory.configure(arena)
	var origin := Vector3(0.0, 1.0, 0.0)
	var velocity := Vector3(0.0, 0.0, -24.0)
	var prediction := trajectory.predict_path(origin, velocity, null)
	var points: Array = prediction.get("points", [])
	var first_bounce_index := int(prediction.get("first_bounce_index", -1))
	var predicted_contact_center := (
		Vector3(points[first_bounce_index])
		if first_bounce_index >= 0 and first_bounce_index < points.size()
		else Vector3.INF
	)
	var wall_front_z := wall.position.z + wall_shape.size.z * 0.5
	_expect(first_bounce_index >= 0, "volume preview detects the thin wall")
	_expect(
		predicted_contact_center.is_finite()
		and predicted_contact_center.z >= wall_front_z + GrenadeBase.COLLISION_RADIUS_METERS - 0.01,
		"preview stops the grenade radius before the wall surface"
	)

	var grenade := GrenadeBase.new()
	grenade.arm_on_ready = false
	arena.add_child(grenade)
	grenade.global_position = origin
	grenade.launch(velocity, Vector3.ZERO)
	var minimum_z := grenade.global_position.z
	var reversed_after_contact := false
	for _frame in 16:
		await physics_frame
		minimum_z = minf(minimum_z, grenade.global_position.z)
		if grenade.linear_velocity.z > 0.05:
			reversed_after_contact = true
	_expect(grenade.continuous_cd, "runtime grenade uses continuous collision detection")
	_expect(reversed_after_contact, "runtime grenade collides with and rebounds from the thin wall")
	_expect(
		minimum_z >= predicted_contact_center.z - 0.06,
		"runtime contact remains inside the preview collision envelope"
	)

	print(
		"GRENADE_TRAJECTORY_COLLISION_METRIC predicted_z=%.4f runtime_min_z=%.4f"
		% [predicted_contact_center.z, minimum_z]
	)
	grenade.queue_free()
	arena.queue_free()
	await process_frame
	if failures.is_empty():
		print("GRENADE_TRAJECTORY_COLLISION_REGRESSION PASS")
		quit(0)
		return
	for failure in failures:
		push_error("GRENADE_TRAJECTORY_COLLISION_REGRESSION: %s" % failure)
	quit(1)


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("GRENADE_TRAJECTORY_COLLISION_CHECK PASS ", label)
	else:
		failures.append(label)
