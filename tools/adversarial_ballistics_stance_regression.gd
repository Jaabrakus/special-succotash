extends SceneTree

const Ballistics := preload("res://scripts/weapons/weapon_ballistics.gd")

var failures: Array[String] = []
var findings: Array[Dictionary] = []
var arena: Node3D


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("=== EMPIRICAL ADVERSARIAL BALLISTICS STANCE AUDIT ===")
	arena = Node3D.new()
	root.add_child(arena)
	await process_frame
	await physics_frame

	_test_1_extreme_burst_lengths()
	_test_2_zero_delay_firing()
	_test_3_bloom_recovery_timing_and_ordering()
	_test_4_iso_scaling_and_max_bloom_limits()
	_test_5_static_and_isolated_stance_invariants()
	_test_6_rapid_stance_transitions_during_continuous_firing()
	_test_7_rapid_stance_swapping_jitter()

	print("\n=== AUDIT SUMMARY ===")
	print("Total failures: %d" % failures.size())
	for f in failures:
		print("  [FAIL] %s" % f)
	for finding in findings:
		print("  [FINDING: %s] %s" % [finding.get("severity", "MEDIUM"), finding.get("description", "")])

	if failures.is_empty():
		print("\nVERDICT: APPROVE (all empirical assertions passed)")
		quit(0)
	else:
		print("\nVERDICT: REQUEST_CHANGES (%d empirical assertions failed)" % failures.size())
		quit(1)


func _test_1_extreme_burst_lengths() -> void:
	print("\n--- Test 1: Extreme Burst Lengths (1, 2, 3, 10, 50 rounds) ---")
	for posture in [&"STANDING", &"CROUCHED", &"PRONE"]:
		var b := _create_ballistics()
		var spreads: Array[float] = []
		var blooms: Array[float] = []

		for shot_idx in range(1, 51):
			b.fire_cooldown = 0.0
			var res := _fire(b, posture)
			_assert(res.get("fired", false), "%s: shot %d fired" % [posture, shot_idx])
			spreads.append(b.total_current_spread_deg)
			blooms.append(b.current_recoil_bloom)

			# 1-round & 2-round burst pinpoint accuracy check
			if shot_idx == 1 or shot_idx == 2:
				_assert(
					is_equal_approx(b.current_recoil_bloom, 0.0),
					"%s: shot %d bloom must be 0.0 (got %.4f)" % [posture, shot_idx, b.current_recoil_bloom]
				)

			# 3-round burst check
			if shot_idx == 3:
				var expected_bloom: float = b._bloom_per_shot_for(posture)
				_assert(
					is_equal_approx(b.current_recoil_bloom, expected_bloom),
					"%s: shot 3 bloom must equal 1x bloom_per_shot (expected %.4f, got %.4f)" % [
						posture, expected_bloom, b.current_recoil_bloom
					]
				)

			# 10-round check
			if shot_idx == 10:
				var max_cap: float = b._maximum_bloom_for(posture)
				_assert(
					b.current_recoil_bloom <= max_cap + 0.0001,
					"%s: shot 10 bloom must not exceed max cap (cap %.4f, got %.4f)" % [
						posture, max_cap, b.current_recoil_bloom
					]
				)

			# 50-round sustained check: must remain capped, no NaN, no Inf, no overflow
			if shot_idx == 50:
				var max_cap: float = b._maximum_bloom_for(posture)
				_assert(
					is_equal_approx(b.current_recoil_bloom, max_cap),
					"%s: shot 50 bloom must remain at max cap (expected %.4f, got %.4f)" % [
						posture, max_cap, b.current_recoil_bloom
					]
				)
				_assert(
					is_finite(b.current_recoil_bloom) and not is_nan(b.current_recoil_bloom),
					"%s: shot 50 bloom is finite and not NaN" % posture
				)

		print(
			"  %s: round 1=%.3f, round 2=%.3f, round 3=%.3f, round 10=%.3f, round 50=%.3f (cap=%.3f)"
			% [posture, blooms[0], blooms[1], blooms[2], blooms[9], blooms[49], b._maximum_bloom_for(posture)]
		)
		b.free()


func _test_2_zero_delay_firing() -> void:
	print("\n--- Test 2: Zero-Delay Firing & Cooldown Rejection ---")
	var b := _create_ballistics()
	# First shot should succeed
	var res1 := _fire(b, &"STANDING")
	_assert(res1.get("fired", false), "First shot fires")
	_assert(b.continuous_shot_count == 1, "Continuous count is 1")
	_assert(b.fire_cooldown > 0.0, "Cooldown active after shot")

	# Immediate repeated attempts with zero delay (no _process time elapsed)
	for i in range(10):
		var res := _fire(b, &"STANDING")
		_assert(not res.get("fired", false), "Zero-delay attempt %d rejected" % i)
		_assert(b.continuous_shot_count == 1, "Continuous count did not increment on rejected shot %d" % i)
		_assert(is_equal_approx(b.current_recoil_bloom, 0.0), "Bloom did not change on rejected shot %d" % i)

	# Try record_shot_state directly while cooldown active
	var recorded := b.record_shot_state(&"STANDING", 0.0, false)
	_assert(not recorded, "record_shot_state returns false when cooldown > 0")
	_assert(b.continuous_shot_count == 1, "Continuous count preserved")

	b.free()


func _test_3_bloom_recovery_timing_and_ordering() -> void:
	print("\n--- Test 3: Bloom Recovery Timing & Ordering (Prone >= Crouch >= Stand) ---")
	var b := _create_ballistics()

	# Verify configured/export recovery rates
	var prone_spd: float = b.prone_bloom_recovery_speed
	var crouch_spd: float = b.crouch_bloom_recovery_speed
	var stand_spd: float = b.bloom_recovery_speed

	print("  Recovery rates: Prone=%.2f deg/s, Crouch=%.2f deg/s, Stand=%.2f deg/s" % [prone_spd, crouch_spd, stand_spd])
	_assert(
		prone_spd >= crouch_spd,
		"Prone recovery speed (%.2f) >= Crouch recovery speed (%.2f)" % [prone_spd, crouch_spd]
	)
	_assert(
		crouch_spd >= stand_spd,
		"Crouch recovery speed (%.2f) >= Stand recovery speed (%.2f)" % [crouch_spd, stand_spd]
	)

	# Dynamic runtime recovery rate test:
	# Set each to identical starting bloom (1.0 deg) and measure decay over 0.1s after delay
	var decays: Dictionary = {}
	for posture in [&"STANDING", &"CROUCHED", &"PRONE"]:
		var gun := _create_ballistics()
		gun.current_posture = posture
		gun.current_recoil_bloom = 1.0
		gun.seconds_since_last_shot = 0.0
		gun.is_firing_held = false

		# Advance through quiet period
		var delay := gun.bloom_recovery_delay_seconds
		gun._process(delay)
		_assert(
			is_equal_approx(gun.current_recoil_bloom, 1.0),
			"%s retains full bloom during quiet period (%.2fs)" % [posture, delay]
		)

		# Advance 0.05s into recovery window
		gun._process(0.05)
		var decay_amount: float = 1.0 - gun.current_recoil_bloom
		decays[posture] = decay_amount
		gun.free()

	print("  0.05s decay amount: Prone=%.4f°, Crouch=%.4f°, Stand=%.4f°" % [
		decays[&"PRONE"], decays[&"CROUCHED"], decays[&"STANDING"]
	])
	_assert(
		decays[&"PRONE"] >= decays[&"CROUCHED"] - 0.0001,
		"Dynamic prone recovery (%.4f) >= crouch recovery (%.4f)" % [decays[&"PRONE"], decays[&"CROUCHED"]]
	)
	_assert(
		decays[&"CROUCHED"] >= decays[&"STANDING"] - 0.0001,
		"Dynamic crouch recovery (%.4f) >= stand recovery (%.4f)" % [decays[&"CROUCHED"], decays[&"STANDING"]]
	)

	b.free()


func _test_4_iso_scaling_and_max_bloom_limits() -> void:
	print("\n--- Test 4: ISO 20/45 Scaling & Prone Max Bloom <= 1.07° ---")
	var b := _create_ballistics()

	var stand_max: float = b.max_recoil_bloom_deg
	var crouch_max: float = b.crouch_max_recoil_bloom_deg
	var prone_max: float = b.prone_max_recoil_bloom_deg

	print("  Max recoil bloom export values: Stand=%.3f°, Crouch=%.3f°, Prone=%.3f°" % [stand_max, crouch_max, prone_max])

	# Requirement 3: Prone maximum bloom does not exceed 1.07° (ISO 20/45 scaling of 2.40°)
	var iso_expected_prone_max := stand_max * (20.0 / 45.0)
	print("  ISO 20/45 expected prone max: %.4f°" % iso_expected_prone_max)
	_assert(
		prone_max <= 1.07001,
		"Prone max recoil bloom export (%.4f°) does not exceed 1.07°" % prone_max
	)
	_assert(
		absf(prone_max - iso_expected_prone_max) <= 0.01,
		"Prone max bloom aligns with ISO 20/45 scaling (%.4f vs %.4f)" % [prone_max, iso_expected_prone_max]
	)
	_assert(
		crouch_max <= stand_max,
		"Crouch max bloom (%.3f) <= Stand max bloom (%.3f)" % [crouch_max, stand_max]
	)
	_assert(
		prone_max <= crouch_max,
		"Prone max bloom (%.3f) <= Crouch max bloom (%.3f)" % [prone_max, crouch_max]
	)

	b.free()


func _test_5_static_and_isolated_stance_invariants() -> void:
	print("\n--- Test 5: Isolated Stance Invariant (Prone <= Crouch <= Stand for isolated bursts) ---")
	var standing := _create_ballistics()
	var crouched := _create_ballistics()
	var prone := _create_ballistics()

	for shot_idx in range(1, 21):
		standing.fire_cooldown = 0.0
		crouched.fire_cooldown = 0.0
		prone.fire_cooldown = 0.0

		_fire(standing, &"STANDING")
		_fire(crouched, &"CROUCHED")
		_fire(prone, &"PRONE")

		var s_bloom := standing.current_recoil_bloom
		var c_bloom := crouched.current_recoil_bloom
		var p_bloom := prone.current_recoil_bloom

		var s_spread := standing.total_current_spread_deg
		var c_spread := crouched.total_current_spread_deg
		var p_spread := prone.total_current_spread_deg

		_assert(
			c_bloom <= s_bloom + 0.0001,
			"Isolated shot %d: Crouch bloom (%.4f) <= Stand bloom (%.4f)" % [shot_idx, c_bloom, s_bloom]
		)
		_assert(
			p_bloom <= c_bloom + 0.0001,
			"Isolated shot %d: Prone bloom (%.4f) <= Crouch bloom (%.4f)" % [shot_idx, p_bloom, c_bloom]
		)
		_assert(
			c_spread <= s_spread + 0.0001,
			"Isolated shot %d: Crouch spread (%.4f) <= Stand spread (%.4f)" % [shot_idx, c_spread, s_spread]
		)
		_assert(
			p_spread <= c_spread + 0.0001,
			"Isolated shot %d: Prone spread (%.4f) <= Crouch spread (%.4f)" % [shot_idx, p_spread, c_spread]
		)

	standing.free()
	crouched.free()
	prone.free()


func _test_6_rapid_stance_transitions_during_continuous_firing() -> void:
	print("\n--- Test 6: Adversarial Rapid Stance Transitions (Stand -> Crouch -> Prone -> Stand) ---")
	# Scenario: Operator fires 10 rounds standing (max bloom 2.40 reached),
	# then transitions to CROUCH mid-burst (continuous firing),
	# then transitions to PRONE mid-burst,
	# then transitions back to STAND mid-burst.

	var b := _create_ballistics()

	# Phase A: 10 rounds Standing
	print("  Phase A: Firing 10 rounds STANDING...")
	for i in range(10):
		b.fire_cooldown = 0.0
		_fire(b, &"STANDING")

	var stand_10_bloom := b.current_recoil_bloom
	var stand_10_spread := b.total_current_spread_deg
	print("    After 10 Stand shots: bloom=%.4f°, spread=%.4f°" % [stand_10_bloom, stand_10_spread])
	_assert(is_equal_approx(stand_10_bloom, 2.40), "Standing bloom reached 2.40° cap")

	# Phase B: Transition to CROUCH and fire round 11
	print("  Phase B: Transitioning to CROUCHED (shot 11)...")
	b.fire_cooldown = 0.0
	_fire(b, &"CROUCHED")
	var crouch_11_bloom := b.current_recoil_bloom
	var crouch_11_spread := b.total_current_spread_deg
	print("    Shot 11 in CROUCH: bloom=%.4f°, spread=%.4f° (crouch cap=%.4f°)" % [
		crouch_11_bloom, crouch_11_spread, b.crouch_max_recoil_bloom_deg
	])

	# Check: Does crouch bloom exceed standing max bloom?
	_assert(
		crouch_11_bloom <= b.max_recoil_bloom_deg + 0.0001,
		"Transition Stand->Crouch: crouch bloom (%.4f) <= standing max bloom (%.4f)" % [
			crouch_11_bloom, b.max_recoil_bloom_deg
		]
	)

	# Check: Does crouch bloom exceed crouch max cap?
	var crouch_cap_violated: bool = crouch_11_bloom > b.crouch_max_recoil_bloom_deg + 0.0001
	if crouch_cap_violated:
		_fail("CRITICAL: Crouch bloom (%.4f°) EXCEEDS crouch_max_recoil_bloom_deg (%.4f°) after Stand->Crouch transition!" % [
			crouch_11_bloom, b.crouch_max_recoil_bloom_deg
		])
		findings.append({
			"severity": "CRITICAL",
			"description": "Stand->Crouch transition during continuous fire leaks standing bloom (2.40°) into crouch (cap 1.70°)."
		})
	else:
		print("    PASS: Crouch bloom respects crouch max cap.")

	# Phase C: Transition to PRONE and fire round 12
	print("  Phase C: Transitioning to PRONE (shot 12)...")
	b.fire_cooldown = 0.0
	_fire(b, &"PRONE")
	var prone_12_bloom := b.current_recoil_bloom
	var prone_12_spread := b.total_current_spread_deg
	print("    Shot 12 in PRONE: bloom=%.4f°, spread=%.4f° (prone cap=%.4f°)" % [
		prone_12_bloom, prone_12_spread, b.prone_max_recoil_bloom_deg
	])

	# Requirement 3 check: Prone maximum bloom does not exceed 1.07°
	var prone_107_violated: bool = prone_12_bloom > 1.07001
	if prone_107_violated:
		_fail("CRITICAL: Prone bloom (%.4f°) EXCEEDS 1.07° limit after transition! Prone cap (%.4f°) was bypassed!" % [
			prone_12_bloom, b.prone_max_recoil_bloom_deg
		])
		findings.append({
			"severity": "CRITICAL",
			"description": "Continuous fire transition Stand->Prone bypasses prone max bloom cap (1.07°), leaving bloom at 2.40°."
		})
	else:
		print("    PASS: Prone bloom does not exceed 1.07°.")

	# Requirement 2 check: Prone bloom <= Crouch bloom
	# Compare prone bloom to crouch max cap or crouch bloom of a crouched shooter
	var crouch_solo := _create_ballistics()
	for i in range(12):
		crouch_solo.fire_cooldown = 0.0
		_fire(crouch_solo, &"CROUCHED")
	var pure_crouch_bloom := crouch_solo.current_recoil_bloom
	crouch_solo.free()

	print("    Comparing Prone bloom (%.4f°) vs pure Crouch bloom (%.4f°)..." % [prone_12_bloom, pure_crouch_bloom])
	if prone_12_bloom > pure_crouch_bloom + 0.0001:
		_fail("CRITICAL: Prone bloom (%.4f°) EXCEEDS Crouch bloom (%.4f°)!" % [
			prone_12_bloom, pure_crouch_bloom
		])
		findings.append({
			"severity": "CRITICAL",
			"description": "Under continuous fire, transitioning from Stand into Prone causes prone bloom to exceed crouch bloom."
		})
	else:
		print("    PASS: Prone bloom <= Crouch bloom.")

	# Phase D: Transition back to STAND and fire round 13
	print("  Phase D: Transitioning back to STAND (shot 13)...")
	b.fire_cooldown = 0.0
	_fire(b, &"STANDING")
	print("    Shot 13 in STAND: bloom=%.4f°, spread=%.4f°" % [b.current_recoil_bloom, b.total_current_spread_deg])
	_assert(
		b.current_recoil_bloom <= b.max_recoil_bloom_deg + 0.0001,
		"Stand bloom bounded at max"
	)

	b.free()


func _test_7_rapid_stance_swapping_jitter() -> void:
	print("\n--- Test 7: Rapid Per-Shot Stance Swapping (S->C->P->S cycle for 30 shots) ---")
	var b := _create_ballistics()
	var cycle: Array[StringName] = [&"STANDING", &"CROUCHED", &"PRONE"]

	for shot in range(1, 31):
		var posture: StringName = cycle[(shot - 1) % 3]
		b.fire_cooldown = 0.0
		_fire(b, posture)

		var cap: float = b._maximum_bloom_for(posture)
		if b.current_recoil_bloom > cap + 0.0001:
			_fail("Per-shot cycling: shot %d (%s) bloom %.4f EXCEEDS cap %.4f!" % [
				shot, posture, b.current_recoil_bloom, cap
			])
			findings.append({
				"severity": "HIGH",
				"description": "Per-shot stance cycling shot %d (%s) has bloom %.4f > cap %.4f" % [
					shot, posture, b.current_recoil_bloom, cap
				]
			})
			break

	b.free()


func _create_ballistics() -> SocomWeaponBallistics:
	var b := Ballistics.new()
	arena.add_child(b)
	b.set_process(true)
	return b


func _fire(b: SocomWeaponBallistics, posture: StringName) -> Dictionary:
	var excluded_rids: Array[RID] = []
	return b.try_fire_direction(
		Vector3.ZERO,
		Vector3.FORWARD,
		arena.get_world_3d().direct_space_state,
		excluded_rids,
		b.continuous_shot_count + 1,
		posture,
		0.0,
		false,
		1.0
	)


func _assert(condition: bool, msg: String) -> void:
	if not condition:
		_fail(msg)


func _fail(msg: String) -> void:
	failures.append(msg)
	push_error("FAIL: %s" % msg)
