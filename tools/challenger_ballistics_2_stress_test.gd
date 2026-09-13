extends SceneTree

const Ballistics := preload("res://scripts/weapons/weapon_ballistics.gd")

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	print("=== CHALLENGER 2 EMPIRICAL ADVERSARIAL RE-VERIFICATION ===")
	var arena := Node3D.new()
	root.add_child(arena)
	await process_frame
	await physics_frame

	_test_stand_to_crouch_clamping(arena)
	_test_stand_to_prone_clamping(arena)
	_test_no_fire_posture_transition_clamping(arena)
	_test_recovery_during_stance_transition(arena)
	_test_extreme_adversarial_stance_jitter_100_rounds(arena)
	_test_preview_next_shot_cone_clamping(arena)

	print("\n=== SUMMARY OF EMPIRICAL ADVERSARIAL TESTS ===")
	print("Failures: %d" % failures.size())
	for f in failures:
		print("  [FAIL] %s" % f)

	if failures.is_empty():
		print("\nALL EMPIRICAL TESTS PASSED PERFECTLY.")
		quit(0)
	else:
		print("\nEMPIRICAL VERIFICATION FAILED.")
		quit(1)

func _test_stand_to_crouch_clamping(arena: Node3D) -> void:
	print("\n[Stress 1] Stand (10 rounds) -> Crouch: bloom <= 1.70°")
	var b := Ballistics.new()
	arena.add_child(b)
	for i in 10:
		b.fire_cooldown = 0.0
		_fire(b, arena, &"STANDING")
	var stand_bloom := b.current_recoil_bloom
	print("  Stand bloom after 10 rounds: %.4f°" % stand_bloom)
	_assert(is_equal_approx(stand_bloom, 2.40), "Stand reached 2.40°")

	# Fire shot 11 in crouch
	b.fire_cooldown = 0.0
	_fire(b, arena, &"CROUCHED")
	var crouch_bloom := b.current_recoil_bloom
	print("  Crouch bloom after transition shot 11: %.4f° (cap=%.4f°)" % [crouch_bloom, b.crouch_max_recoil_bloom_deg])
	_assert(crouch_bloom <= 1.70001, "Crouch bloom <= 1.70° (got %.4f°)" % crouch_bloom)
	_assert(crouch_bloom <= b.crouch_max_recoil_bloom_deg + 0.0001, "Crouch bloom <= crouch_max_recoil_bloom_deg")
	b.free()

func _test_stand_to_prone_clamping(arena: Node3D) -> void:
	print("\n[Stress 2] Stand (10 rounds) -> Prone: bloom <= 1.07° (ISO 20/45 scaling)")
	var b := Ballistics.new()
	arena.add_child(b)
	for i in 10:
		b.fire_cooldown = 0.0
		_fire(b, arena, &"STANDING")
	
	# Fire shot 11 in prone
	b.fire_cooldown = 0.0
	_fire(b, arena, &"PRONE")
	var prone_bloom := b.current_recoil_bloom
	print("  Prone bloom after transition shot 11: %.4f° (cap=%.4f°)" % [prone_bloom, b.prone_max_recoil_bloom_deg])
	_assert(prone_bloom <= 1.07001, "Prone bloom <= 1.07° (got %.4f°)" % prone_bloom)
	_assert(prone_bloom <= b.prone_max_recoil_bloom_deg + 0.0001, "Prone bloom <= prone_max_recoil_bloom_deg")

	# Also test Crouch (10 rounds) -> Prone
	var b2 := Ballistics.new()
	arena.add_child(b2)
	for i in 10:
		b2.fire_cooldown = 0.0
		_fire(b2, arena, &"CROUCHED")
	print("  Crouch bloom after 10 rounds: %.4f°" % b2.current_recoil_bloom)
	b2.fire_cooldown = 0.0
	_fire(b2, arena, &"PRONE")
	print("  Prone bloom after transition from Crouch: %.4f°" % b2.current_recoil_bloom)
	_assert(b2.current_recoil_bloom <= 1.07001, "Prone bloom from Crouch <= 1.07° (got %.4f°)" % b2.current_recoil_bloom)
	b.free()
	b2.free()

func _test_no_fire_posture_transition_clamping(arena: Node3D) -> void:
	print("\n[Stress 3] Non-firing posture transition (calculate_current_spread / update_spread_state)")
	var b := Ballistics.new()
	arena.add_child(b)
	for i in 10:
		b.fire_cooldown = 0.0
		_fire(b, arena, &"STANDING")
	_assert(is_equal_approx(b.current_recoil_bloom, 2.40), "Stand bloom is 2.40°")

	# Player changes stance to CROUCHED without firing a shot
	b.calculate_current_spread(&"CROUCHED", 0.0, false)
	print("  After calculate_current_spread(CROUCHED, 0, false): bloom=%.4f°, spread=%.4f°" % [b.current_recoil_bloom, b.total_current_spread_deg])
	_assert(b.current_recoil_bloom <= 1.70001, "Bloom clamped to crouch cap without firing (got %.4f°)" % b.current_recoil_bloom)

	# Player changes stance to PRONE without firing a shot
	b.calculate_current_spread(&"PRONE", 0.0, false)
	print("  After calculate_current_spread(PRONE, 0, false): bloom=%.4f°, spread=%.4f°" % [b.current_recoil_bloom, b.total_current_spread_deg])
	_assert(b.current_recoil_bloom <= 1.07001, "Bloom clamped to prone cap without firing (got %.4f°)" % b.current_recoil_bloom)
	b.free()

func _test_recovery_during_stance_transition(arena: Node3D) -> void:
	print("\n[Stress 4] Recoil recovery during stance transitions")
	var b := Ballistics.new()
	arena.add_child(b)
	for i in 10:
		b.fire_cooldown = 0.0
		_fire(b, arena, &"STANDING")

	# Stop firing, wait for quiet delay (0.30s)
	b.release_trigger()
	b._process(b.bloom_recovery_delay_seconds)
	_assert(is_equal_approx(b.current_recoil_bloom, 2.40), "Bloom retained during quiet delay")

	# Switch stance to CROUCHED during recovery using canonical API
	b.update_spread_state(&"CROUCHED", 0.0, false)
	_assert(is_equal_approx(b.current_recoil_bloom, 1.70), "Bloom immediately clamped to 1.70 upon stance transition")
	b._process(0.05)
	# 0.05s of crouch recovery: crouch speed = 18.0 deg/s.
	# 1.70 - (18.0 * 0.05) = 1.70 - 0.90 = 0.80
	print("  Crouch bloom after 0.05s recovery: %.4f°" % b.current_recoil_bloom)
	_assert(b.current_recoil_bloom <= 1.70001, "Crouch bloom <= 1.70 during recovery")
	_assert(is_equal_approx(b.current_recoil_bloom, 0.80), "Decay is exactly 0.90 from crouch cap 1.70 (got %.4f)" % b.current_recoil_bloom)
	b.free()

func _test_extreme_adversarial_stance_jitter_100_rounds(arena: Node3D) -> void:
	print("\n[Stress 5] 100-round continuous fire with aggressive random-like stance switching")
	var b := Ballistics.new()
	arena.add_child(b)

	var postures: Array[StringName] = [&"STANDING", &"CROUCHED", &"PRONE"]
	# Deterministic pseudo-random sequence
	var rng := RandomNumberGenerator.new()
	rng.seed = 987654321

	var previous_posture := &"STANDING"
	for shot in range(1, 101):
		var posture_idx := rng.randi_range(0, 2)
		var posture: StringName = postures[posture_idx]
		b.fire_cooldown = 0.0
		_fire(b, arena, posture)

		var cap: float = b._maximum_bloom_for(posture)
		var bloom: float = b.current_recoil_bloom
		var spread: float = b.total_current_spread_deg

		# Invariant 1: Bloom never exceeds current posture's cap
		if bloom > cap + 0.0001:
			_assert(false, "Shot %d (%s -> %s): bloom %.4f > cap %.4f!" % [shot, previous_posture, posture, bloom, cap])

		# Invariant 2: Prone bloom never exceeds 1.07°
		if posture == &"PRONE":
			if bloom > 1.07001:
				_assert(false, "Shot %d (PRONE): bloom %.4f > 1.07°!" % [shot, bloom])

		# Invariant 3: Crouch bloom never exceeds 1.70°
		if posture == &"CROUCHED":
			if bloom > 1.70001:
				_assert(false, "Shot %d (CROUCHED): bloom %.4f > 1.70°!" % [shot, bloom])

		# Invariant 4: Prone spread is always less than standing spread with same shot count
		if posture == &"PRONE":
			if spread > 1.07 + 0.40 * 0.22 + 0.0001:
				_assert(false, "Shot %d (PRONE): stationary spread %.4f exceeded max prone spread!" % [shot, spread])

		previous_posture = posture

	print("  100-round stance jitter finished with all invariants strictly maintained!")
	b.free()

func _test_preview_next_shot_cone_clamping(arena: Node3D) -> void:
	print("\n[Stress 6] preview_next_shot_cone clamping")
	var b := Ballistics.new()
	arena.add_child(b)
	for i in 10:
		b.fire_cooldown = 0.0
		_fire(b, arena, &"STANDING")
	_assert(is_equal_approx(b.current_recoil_bloom, 2.40), "Stand bloom is 2.40°")

	# Preview next shot cone for CROUCHED and PRONE while standing with 2.40° bloom
	var preview_crouch: Dictionary = b.preview_next_shot_cone(&"CROUCHED", 0.0, false, 1.0)
	var preview_prone: Dictionary = b.preview_next_shot_cone(&"PRONE", 0.0, false, 1.0)

	var crouch_preview_spread: float = float(preview_crouch.get("spread_deg", 99.0))
	var prone_preview_spread: float = float(preview_prone.get("spread_deg", 99.0))

	print("  Preview Crouch spread from 2.40° stand: %.4f°" % crouch_preview_spread)
	print("  Preview Prone spread from 2.40° stand: %.4f°" % prone_preview_spread)

	# Max crouch spread stationary = base (0.40 * 0.72 = 0.288) + crouch bloom cap (1.70) = 1.988°
	_assert(crouch_preview_spread <= 1.988 + 0.001, "Preview crouch spread clamped (got %.4f, max 1.988)" % crouch_preview_spread)
	# Max prone spread stationary = base (0.40 * 0.22 = 0.088) + prone bloom cap (1.07) = 1.158°
	_assert(prone_preview_spread <= 1.158 + 0.001, "Preview prone spread clamped (got %.4f, max 1.158)" % prone_preview_spread)
	_assert(prone_preview_spread < crouch_preview_spread, "Prone preview spread < Crouch preview spread")
	b.free()

func _fire(ballistics, arena: Node3D, posture: StringName) -> Dictionary:
	var excluded_rids: Array[RID] = []
	return ballistics.try_fire_direction(
		Vector3.ZERO,
		Vector3.FORWARD,
		arena.get_world_3d().direct_space_state,
		excluded_rids,
		ballistics.continuous_shot_count + 1,
		posture,
		0.0,
		false,
		1.0
	)

func _assert(condition: bool, msg: String) -> void:
	if not condition:
		failures.append(msg)
		push_error("FAIL: %s" % msg)
