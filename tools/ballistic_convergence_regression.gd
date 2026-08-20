extends SceneTree

const MAIN_SCENE := preload("res://main.tscn")

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var main := MAIN_SCENE.instantiate()
	root.add_child(main)
	for _frame in 90:
		await physics_frame

	var rig: Node3D = main.get("camera_rig") as Node3D
	_expect(rig != null, "playable range owns the shared camera aim rig")
	if rig != null:
		var profile: Resource = rig.get("profile") as Resource
		var view_target: Vector3 = rig.get("view_aim_point")
		var weapon_target: Vector3 = rig.get("weapon_aim_point")
		var shot_point: Vector3 = rig.get("shot_point")
		_expect(
			float(profile.get("minimum_ballistic_convergence_distance")) <= 12.01,
			"normal-range ballistic zero is no longer locked beyond 45 metres"
		)
		_expect(
			float(profile.get("maximum_convergence_angle_deg")) >= 5.99,
			"third-person parallax may converge within the playable range"
		)
		_expect(bool(rig.get("aim_hit")), "center reticle acquires the range target")
		_expect(
			weapon_target.distance_to(view_target) <= 0.05,
			"muzzle trajectory converges at the acquired reticle target"
		)
		_expect(
			shot_point.distance_to(view_target) <= 0.08,
			"validated shot reaches the visible reticle impact instead of landing low"
		)

	main.queue_free()
	await process_frame
	if failures.is_empty():
		print("BALLISTIC_CONVERGENCE_REGRESSION PASS")
		quit(0)
		return
	for failure in failures:
		push_error("BALLISTIC_CONVERGENCE_REGRESSION: %s" % failure)
	quit(1)


func _expect(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
