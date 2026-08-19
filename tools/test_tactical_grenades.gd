extends SceneTree


func _init() -> void:
	var failures: Array[String] = []
	var direct := TacticalFlashbangGrenade.calculate_exposure(
		Vector3(0, 0, -2), Vector3.ZERO, Vector3(0, 0, -1), true, 18.0
	)
	var turned := TacticalFlashbangGrenade.calculate_exposure(
		Vector3(0, 0, -2), Vector3.ZERO, Vector3(0, 0, 1), true, 18.0
	)
	if direct <= turned or direct < 0.5:
		failures.append("flash angle falloff is invalid")
	if TacticalFlashbangGrenade.calculate_exposure(Vector3.ZERO, Vector3.ONE, Vector3.FORWARD, false) != 0.0:
		failures.append("blocked flash retained exposure")
	var thrower := TacticalGrenadeThrower.new()
	var overhand := thrower.calculate_launch_velocity(Vector3.FORWARD, Vector3.UP, TacticalGrenadeThrower.ThrowMode.OVERHAND)
	var underhand := thrower.calculate_launch_velocity(Vector3.FORWARD, Vector3.UP, TacticalGrenadeThrower.ThrowMode.UNDERHAND)
	if overhand.length() <= underhand.length() or overhand.y <= underhand.y:
		failures.append("throw modes do not produce distinct arcs")
	if failures.is_empty():
		print("TACTICAL_GRENADE_REGRESSION_PASS direct=%.3f turned=%.3f" % [direct, turned])
		thrower.free()
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		thrower.free()
		quit(1)
