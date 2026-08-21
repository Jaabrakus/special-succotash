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
	var frag_near := TacticalFragGrenade.damage_falloff(1.0, 7.0)
	var frag_mid := TacticalFragGrenade.damage_falloff(3.5, 7.0)
	var frag_edge := TacticalFragGrenade.damage_falloff(7.0, 7.0)
	if frag_near <= frag_mid or frag_mid <= frag_edge or frag_edge != 0.0:
		failures.append("frag distance damage falloff is invalid")
	var thrower := TacticalGrenadeThrower.new()
	var overhand := thrower.calculate_launch_velocity(Vector3.FORWARD, Vector3.UP, TacticalGrenadeThrower.ThrowMode.OVERHAND)
	var underhand := thrower.calculate_launch_velocity(Vector3.FORWARD, Vector3.UP, TacticalGrenadeThrower.ThrowMode.UNDERHAND)
	if overhand.length() <= underhand.length() or overhand.y <= underhand.y:
		failures.append("throw modes do not produce distinct arcs")
	var quick_charge := thrower.charge_for_hold(0.12)
	var full_charge := thrower.charge_for_hold(thrower.full_throw_charge_seconds)
	var quick_throw := thrower.calculate_launch_velocity(
		Vector3.FORWARD,
		Vector3.UP,
		TacticalGrenadeThrower.ThrowMode.OVERHAND,
		quick_charge
	)
	var full_throw := thrower.calculate_launch_velocity(
		Vector3.FORWARD,
		Vector3.UP,
		TacticalGrenadeThrower.ThrowMode.OVERHAND,
		full_charge
	)
	if full_charge < 0.999 or full_throw.length() <= quick_throw.length() or full_throw.y <= quick_throw.y:
		failures.append("hold duration does not build a stronger, higher throw arc")
	if thrower.charge_for_hold(10.0) > 1.0:
		failures.append("throw charge exceeds the human power cap")
	var safe_fuse := thrower.remaining_fuse(3.0, 10.0)
	if safe_fuse < thrower.minimum_remaining_fuse_seconds or safe_fuse >= 3.0:
		failures.append("grenade cook is not capped to a safe human window")
	if failures.is_empty():
		print("TACTICAL_GRENADE_REGRESSION_PASS direct=%.3f turned=%.3f frag_near=%.3f frag_mid=%.3f charge=%.2f fuse=%.2f" % [direct, turned, frag_near, frag_mid, full_charge, safe_fuse])
		thrower.free()
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		thrower.free()
		quit(1)
