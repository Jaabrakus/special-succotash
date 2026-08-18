extends SceneTree

var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var packed := load("res://main.tscn") as PackedScene
	_expect(packed != null, "main scene loads")
	if packed == null:
		_finish()
		return
	var scene := packed.instantiate()
	root.add_child(scene)
	await _steps(45)
	var player := scene.get_node_or_null("Player") as CharacterBody3D
	var rig := scene.get_node_or_null("IndependentCameraRig")
	var weapon := scene.get_node_or_null("WeaponController")
	_expect(player != null and rig != null and weapon != null, "live weapon path is wired")
	_expect(InputMap.has_action("fire"), "left-click fire action exists")
	if player == null or rig == null or weapon == null:
		_finish()
		return

	player.velocity = Vector3.RIGHT * float(player.get("move_speed"))
	var intent_before: Dictionary = rig.call("build_local_aim_intent")
	var intended_direction: Vector3 = intent_before.direction
	var first: Dictionary = weapon.call("request_fire")
	_expect(bool(first.get("fired", false)), "first authoritative shot fires")
	_expect(
		float(first.get("spread_deg", 99.0)) <= 0.66,
		"first full-strafe shot stays inside the SOCOM opening-burst cone"
	)
	var first_error := rad_to_deg(
		intended_direction.angle_to(Vector3(first.get("direction", Vector3.ZERO)))
	)
	_expect(
		first_error <= float(first.get("spread_deg", 0.0)) + 0.05,
		"dispersion stays centered on authoritative barrel aim"
	)
	_expect(
		tan(deg_to_rad(float(first.get("spread_deg", 99.0)))) * 25.0 <= 0.30,
		"opening strafe burst remains torso-accurate at 25 metres"
	)

	var blocked_by_cadence: Dictionary = weapon.call("request_fire")
	_expect(not bool(blocked_by_cadence.get("fired", false)), "fire rate rejects same-tick shot spam")
	weapon.ballistics._process(0.11)
	var second: Dictionary = weapon.call("request_fire")
	_expect(bool(second.get("fired", false)), "second burst shot fires after cadence interval")
	_expect(
		float(second.get("spread_deg", 99.0)) <= 0.66,
		"second shot retains opening-burst accuracy"
	)
	weapon.ballistics._process(0.11)
	var third: Dictionary = weapon.call("request_fire")
	_expect(bool(third.get("fired", false)), "third automatic shot fires")
	_expect(
		float(third.get("spread_deg", 0.0)) > float(second.get("spread_deg", 0.0)),
		"sustained fire blooms only after the accurate opening pair"
	)
	_expect(
		int(first.get("sequence", -1)) < int(second.get("sequence", -1))
		and int(second.get("sequence", -1)) < int(third.get("sequence", -1)),
		"accepted shots keep a monotonic multiplayer sequence"
	)
	_expect(
		Vector3(rig.get("last_fired_direction")).is_equal_approx(
			Vector3(third.get("direction", Vector3.ZERO))
		),
		"workbench tracer records the actual fired direction"
	)

	var mannequin := player.get_node_or_null("Mannequin")
	if mannequin != null and mannequin.muzzle_marker != null:
		var muzzle: Vector3 = mannequin.muzzle_marker.global_position
		var prospective: Vector3 = (
			Vector3(rig.get("weapon_aim_point")) - muzzle
		).normalized()
		var view_ray: Vector3 = (
			Vector3(rig.get("view_aim_point")) - rig.global_position
		).normalized()
		var convergence := rad_to_deg(view_ray.angle_to(prospective))
		_expect(
			convergence <= float(rig.get("profile").maximum_convergence_angle_deg) + 0.15,
			"prospective barrel ray never inherits the old steep red-line climb"
		)

	scene.queue_free()
	_finish()


func _steps(count: int) -> void:
	for _index in range(count):
		await physics_frame


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("WEAPON_FIRE_CHECK PASS ", label)
	else:
		failures.append(label)
		push_error("WEAPON_FIRE_CHECK FAIL %s" % label)


func _finish() -> void:
	if failures.is_empty():
		print("WEAPON_FIRE_REGRESSION PASS")
		quit(0)
	else:
		print("WEAPON_FIRE_REGRESSION FAIL ", failures)
		quit(1)
