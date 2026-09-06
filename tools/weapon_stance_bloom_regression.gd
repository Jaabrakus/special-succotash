extends SceneTree

const Ballistics := preload("res://scripts/weapons/weapon_ballistics.gd")

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var arena := Node3D.new()
	root.add_child(arena)
	await process_frame
	await physics_frame

	var standing := Ballistics.new()
	var crouched := Ballistics.new()
	arena.add_child(standing)
	arena.add_child(crouched)
	_configure_release_values(standing)
	_configure_release_values(crouched)

	var standing_third := _fire_burst_shot(standing, arena, &"STANDING", 3)
	var crouched_third := _fire_burst_shot(crouched, arena, &"CROUCHED", 3)
	_expect(
		crouched_third > standing_third,
		"crouch bloom opens faster on the third shot"
	)

	var standing_fourth := _fire_one(standing, arena, &"STANDING")
	var crouched_fourth := _fire_one(crouched, arena, &"CROUCHED")
	_expect(
		crouched_fourth < standing_fourth,
		"crouch sustained-fire maximum remains below standing"
	)

	var standing_before := standing.current_recoil_bloom
	var crouched_before := crouched.current_recoil_bloom
	standing.release_trigger()
	crouched.release_trigger()
	standing._process(standing.bloom_recovery_delay_seconds)
	crouched._process(crouched.bloom_recovery_delay_seconds)
	_expect(is_equal_approx(standing.current_recoil_bloom, standing_before), "standing retains bloom during quiet period")
	_expect(is_equal_approx(crouched.current_recoil_bloom, crouched_before), "crouch retains bloom during quiet period")
	standing._process(0.05)
	crouched._process(0.05)
	var standing_recovery := standing_before - standing.current_recoil_bloom
	var crouched_recovery := crouched_before - crouched.current_recoil_bloom
	_expect(
		crouched_recovery > standing_recovery,
		"crouch bloom recovers faster after trigger release"
	)

	if failures.is_empty():
		print(
			"WEAPON_STANCE_BLOOM_REGRESSION PASS third=%.3f/%.3f fourth=%.3f/%.3f recovery=%.3f/%.3f"
			% [
				standing_third,
				crouched_third,
				standing_fourth,
				crouched_fourth,
				standing_recovery,
				crouched_recovery,
			]
		)
		quit(0)
		return
	for failure in failures:
		push_error("WEAPON_STANCE_BLOOM_REGRESSION: %s" % failure)
	quit(1)


func _configure_release_values(ballistics) -> void:
	ballistics.base_spread_deg = 0.40
	ballistics.bloom_per_shot_deg = 1.20
	ballistics.max_recoil_bloom_deg = 2.40
	ballistics.bloom_recovery_speed = 14.0
	ballistics.crouch_spread_multiplier = 0.72
	ballistics.crouch_bloom_per_shot_deg = 1.35
	ballistics.crouch_max_recoil_bloom_deg = 1.70
	ballistics.crouch_bloom_recovery_speed = 18.0


func _fire_burst_shot(ballistics, arena: Node3D, posture: StringName, shot_count: int) -> float:
	var spread := 0.0
	for _shot in shot_count:
		spread = _fire_one(ballistics, arena, posture)
	return spread


func _fire_one(ballistics, arena: Node3D, posture: StringName) -> float:
	ballistics.fire_cooldown = 0.0
	var excluded_rids: Array[RID] = []
	var result: Dictionary = ballistics.try_fire_direction(
		Vector3.ZERO,
		Vector3.FORWARD,
		arena.get_world_3d().direct_space_state,
		excluded_rids,
		ballistics.continuous_shot_count + 100,
		posture,
		0.0,
		false,
		1.0
	)
	_expect(bool(result.get("fired", false)), "burst shot fires")
	return float(result.get("spread_deg", 0.0))


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("STANCE_BLOOM_CHECK PASS ", label)
	else:
		failures.append(label)
