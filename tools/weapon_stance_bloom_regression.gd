extends SceneTree

const Ballistics := preload("res://scripts/weapons/weapon_ballistics.gd")

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	# 1. Verify default instance values align with authentic ISO values
	var default_ballistics := Ballistics.new()
	_expect(
		default_ballistics.crouch_bloom_per_shot_deg <= 0.32,
		"default crouch bloom rate per shot is <= 0.32"
	)
	_expect(
		default_ballistics.crouch_bloom_per_shot_deg <= default_ballistics.bloom_per_shot_deg,
		"default crouch bloom rate per shot is less than or equal to standing bloom rate"
	)
	_expect(
		default_ballistics.prone_bloom_per_shot_deg <= default_ballistics.crouch_bloom_per_shot_deg,
		"default prone bloom rate per shot is less than or equal to crouch bloom rate"
	)
	var expected_iso_prone_max := default_ballistics.max_recoil_bloom_deg * (20.0 / 45.0)
	_expect(
		absf(default_ballistics.prone_max_recoil_bloom_deg - expected_iso_prone_max) < 0.01,
		"prone maximum bloom reduction matches authentic ISO reduction (ReticuleKnockMax: 20 vs Stand 45)"
	)
	_expect(
		default_ballistics._bloom_per_shot_for(&"PRONE") == default_ballistics.prone_bloom_per_shot_deg,
		"prone bloom per shot helper returns prone parameter"
	)
	_expect(
		default_ballistics._maximum_bloom_for(&"PRONE") == default_ballistics.prone_max_recoil_bloom_deg,
		"prone maximum bloom helper returns prone parameter"
	)
	_expect(
		default_ballistics._recovery_speed_for(&"PRONE") == default_ballistics.prone_bloom_recovery_speed,
		"prone recovery speed helper returns prone parameter"
	)
	default_ballistics.free()

	# 2. Dynamic runtime arena firing simulation across stances
	var arena := Node3D.new()
	root.add_child(arena)
	await process_frame
	await physics_frame

	var standing := Ballistics.new()
	var crouched := Ballistics.new()
	var prone := Ballistics.new()
	arena.add_child(standing)
	arena.add_child(crouched)
	arena.add_child(prone)
	_configure_release_values(standing)
	_configure_release_values(crouched)
	_configure_release_values(prone)

	var standing_third := _fire_burst_shot(standing, arena, &"STANDING", 3)
	var crouched_third := _fire_burst_shot(crouched, arena, &"CROUCHED", 3)
	var prone_third := _fire_burst_shot(prone, arena, &"PRONE", 3)
	_expect(
		crouched_third <= standing_third,
		"crouch bloom rate per shot is less than or equal to standing bloom rate"
	)
	_expect(
		prone_third <= crouched_third,
		"prone third shot spread <= crouched third shot spread"
	)
	_expect(
		prone_third <= standing_third,
		"prone third shot spread <= standing third shot spread"
	)

	var standing_fourth := _fire_one(standing, arena, &"STANDING")
	var crouched_fourth := _fire_one(crouched, arena, &"CROUCHED")
	var prone_fourth := _fire_one(prone, arena, &"PRONE")
	_expect(
		crouched_fourth < standing_fourth,
		"crouch sustained-fire maximum remains below standing"
	)
	_expect(
		prone_fourth < crouched_fourth,
		"prone sustained-fire maximum remains below crouch"
	)

	var configured_iso_prone_max := standing.max_recoil_bloom_deg * (20.0 / 45.0)
	_expect(
		absf(prone._maximum_bloom_for(&"PRONE") - configured_iso_prone_max) < 0.01,
		"configured prone maximum bloom matches authentic ISO reduction (ReticuleKnockMax: 20 vs Stand 45)"
	)

	var standing_before := standing.current_recoil_bloom
	var crouched_before := crouched.current_recoil_bloom
	var prone_before := prone.current_recoil_bloom
	standing.release_trigger()
	crouched.release_trigger()
	prone.release_trigger()
	standing._process(standing.bloom_recovery_delay_seconds)
	crouched._process(crouched.bloom_recovery_delay_seconds)
	prone._process(prone.bloom_recovery_delay_seconds)
	_expect(is_equal_approx(standing.current_recoil_bloom, standing_before), "standing retains bloom during quiet period")
	_expect(is_equal_approx(crouched.current_recoil_bloom, crouched_before), "crouch retains bloom during quiet period")
	_expect(is_equal_approx(prone.current_recoil_bloom, prone_before), "prone retains bloom during quiet period")
	standing._process(0.05)
	crouched._process(0.05)
	prone._process(0.05)
	var standing_recovery := standing_before - standing.current_recoil_bloom
	var crouched_recovery := crouched_before - crouched.current_recoil_bloom
	var prone_recovery := prone_before - prone.current_recoil_bloom
	_expect(
		crouched_recovery > standing_recovery,
		"crouch bloom recovers faster after trigger release"
	)
	_expect(
		prone_recovery >= crouched_recovery,
		"prone bloom recovers as fast or faster than crouch"
	)

	if failures.is_empty():
		print(
			"WEAPON_STANCE_BLOOM_REGRESSION PASS third=%.3f/%.3f/%.3f fourth=%.3f/%.3f/%.3f recovery=%.3f/%.3f/%.3f"
			% [
				standing_third,
				crouched_third,
				prone_third,
				standing_fourth,
				crouched_fourth,
				prone_fourth,
				standing_recovery,
				crouched_recovery,
				prone_recovery,
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
	ballistics.crouch_bloom_per_shot_deg = 0.90 # 1.20 * (9 / 12) per ISO ReticuleKnock
	ballistics.crouch_max_recoil_bloom_deg = 1.70
	ballistics.crouch_bloom_recovery_speed = 18.0
	ballistics.prone_bloom_per_shot_deg = 0.80 # 1.20 * (8 / 12) per ISO ReticuleKnock
	ballistics.prone_max_recoil_bloom_deg = 1.07 # 2.40 * (20 / 45) per ISO ReticuleKnockMax
	ballistics.prone_bloom_recovery_speed = 18.0


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
