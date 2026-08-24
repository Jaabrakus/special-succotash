extends SceneTree

const GrenadeProfile := preload("res://scripts/tactical/tactical_grenade_profile.gd")
const GrenadeThrower := preload("res://scripts/tactical/tactical_grenade_thrower.gd")

const GRAVITY_METERS_PER_SECOND_SQUARED := 9.8

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var thrower := GrenadeThrower.new()
	thrower.configure_profile(GrenadeProfile.load_profile())
	root.add_child(thrower)
	await process_frame
	var level_aim := Vector3.FORWARD
	var high_aim := Vector3(0.0, sin(deg_to_rad(35.0)), -cos(deg_to_rad(35.0)))
	var low_aim := Vector3(0.0, sin(deg_to_rad(-20.0)), -cos(deg_to_rad(-20.0)))
	for mode in [GrenadeThrower.ThrowMode.OVERHAND, GrenadeThrower.ThrowMode.UNDERHAND]:
		var level_velocity := thrower.calculate_launch_velocity(level_aim, Vector3.UP, mode, 1.0)
		var high_velocity := thrower.calculate_launch_velocity(high_aim, Vector3.UP, mode, 1.0)
		var low_velocity := thrower.calculate_launch_velocity(low_aim, Vector3.UP, mode, 1.0)
		var level_apex := _apex_height(level_velocity)
		var high_apex := _apex_height(high_velocity)
		var low_apex := _apex_height(low_velocity)
		var mode_name := "overhand" if mode == GrenadeThrower.ThrowMode.OVERHAND else "underhand"
		var required_high_gain := (
			0.75 if mode == GrenadeThrower.ThrowMode.OVERHAND else 0.20
		)
		print(
			"GRENADE_AIM_PITCH_METRIC mode=%s low_apex=%.2f level_apex=%.2f high_apex=%.2f"
			% [mode_name, low_apex, level_apex, high_apex]
		)
		_expect(
			high_apex > level_apex + required_high_gain
			and level_apex > low_apex,
			"%s aim pitch produces progressively taller physical arcs" % mode_name
		)
		_expect(
			is_equal_approx(high_velocity.length(), level_velocity.length())
			and is_equal_approx(low_velocity.length(), level_velocity.length()),
			"%s aim pitch changes elevation without changing throw power" % mode_name
		)
	thrower.queue_free()
	await process_frame
	if failures.is_empty():
		print("GRENADE_AIM_PITCH_REGRESSION PASS")
		quit(0)
		return
	for failure in failures:
		push_error("GRENADE_AIM_PITCH_REGRESSION: %s" % failure)
	quit(1)


func _apex_height(velocity: Vector3) -> float:
	return pow(maxf(velocity.y, 0.0), 2.0) / (
		2.0 * GRAVITY_METERS_PER_SECOND_SQUARED
	)


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("GRENADE_AIM_PITCH_CHECK PASS ", label)
	else:
		failures.append(label)
