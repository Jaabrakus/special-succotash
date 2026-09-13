# Handoff Report: Ballistics Stance Transition Bloom Clamping Remediation

**Agent**: `worker_ballistics_transition_2`  
**Working Directory**: `/Users/kiwimango/socom-141-camera-lab/.agents/worker_ballistics_transition_2`  
**Status**: **COMPLETE / READY FOR REVIEW**  
**Verdict**: **APPROVE**  

---

## Translation Card

1. **Player intent**: When transitioning from standing down to crouch or prone while firing or under accumulated recoil bloom, weapon dispersion and recoil bloom must immediately clamp to the lower stance's tighter maximum dispersion cap rather than leaking excessive standing bloom into crouched or prone firing.
2. **Acceptance rule**:
   - In `_bloom_after_shot(posture, shot_count)`, incoming bloom is clamped to `_maximum_bloom_for(posture)`.
   - In `calculate_current_spread(posture, movement_speed_norm, is_airborne)`, `effective_bloom = minf(current_recoil_bloom, _maximum_bloom_for(posture))` is assigned to `current_recoil_bloom` and passed to `_spread_for()`.
   - Crouch bloom never exceeds `crouch_max_recoil_bloom_deg` (1.70°) and Prone bloom never exceeds `prone_max_recoil_bloom_deg` (1.07°), even under continuous fire stance transitions or rapid per-shot stance swapping.
   - `tools/adversarial_ballistics_stance_regression.gd`, `tools/weapon_stance_bloom_regression.gd`, and `tools/feature_contract_regression.gd` pass with 0 failures.
3. **System owner**: `scripts/weapons/weapon_ballistics.gd` (`WeaponBallistics` node).
4. **Must not change**: CharacterBody3D movement, camera/aim intent, damage authority, first two pinpoint shots (0.0° bloom), and ISO 20/45 scaling.
5. **Proof**: Headless test execution of `tools/adversarial_ballistics_stance_regression.gd` (PASS, 0 failures), `tools/weapon_stance_bloom_regression.gd` (PASS), and `tools/feature_contract_regression.gd` (PASS, 121 contracts).

---

## 1. Observation

### 1.1 Defect Under Review
In `scripts/weapons/weapon_ballistics.gd`:
Prior implementation of `_bloom_after_shot`:
```gdscript
func _bloom_after_shot(posture: StringName, shot_count: int) -> float:
	var bloom := current_recoil_bloom
	if shot_count > 2:
		var bloom_cap := _maximum_bloom_for(posture)
		if bloom < bloom_cap:
			bloom = minf(bloom_cap, bloom + _bloom_per_shot_for(posture))
	return bloom
```
When `current_recoil_bloom` exceeded `bloom_cap` (e.g., player fires 10 rounds Standing to reach 2.40° bloom and then switches stance to `CROUCHED` [cap 1.70°] or `PRONE` [cap 1.07°]), the condition `if bloom < bloom_cap:` evaluated to `false`. As a result, the function returned `bloom` (2.40°) completely unadjusted.

Furthermore, `calculate_current_spread()` did not clamp `current_recoil_bloom` to `_maximum_bloom_for(posture)` when evaluating `total_current_spread_deg`.

### 1.2 Verbatim Challenger Baseline Failure
Running `tools/adversarial_ballistics_stance_regression.gd` prior to remediation produced 4 critical failures:
```
--- Test 6: Adversarial Rapid Stance Transitions (Stand -> Crouch -> Prone -> Stand) ---
  Phase A: Firing 10 rounds STANDING...
    After 10 Stand shots: bloom=2.4000°, spread=2.6800°
  Phase B: Transitioning to CROUCHED (shot 11)...
    Shot 11 in CROUCH: bloom=2.4000°, spread=2.6016° (crouch cap=1.7000°)
ERROR: FAIL: CRITICAL: Crouch bloom (2.4000°) EXCEEDS crouch_max_recoil_bloom_deg (1.7000°) after Stand->Crouch transition!
  Phase C: Transitioning to PRONE (shot 12)...
    Shot 12 in PRONE: bloom=2.4000°, spread=2.4616° (prone cap=1.0700°)
ERROR: FAIL: CRITICAL: Prone bloom (2.4000°) EXCEEDS 1.07° limit after transition! Prone cap (1.0700°) was bypassed!
    Comparing Prone bloom (2.4000°) vs pure Crouch bloom (1.7000°)...
ERROR: FAIL: CRITICAL: Prone bloom (2.4000°) EXCEEDS Crouch bloom (1.7000°)!
  Phase D: Transitioning back to STAND (shot 13)...
    Shot 13 in STAND: bloom=2.4000°, spread=2.6800°

--- Test 7: Rapid Per-Shot Stance Swapping (S->C->P->S cycle for 30 shots) ---
ERROR: FAIL: Per-shot cycling: shot 9 (PRONE) bloom 1.5460 EXCEEDS cap 1.0700!

=== AUDIT SUMMARY ===
Total failures: 4
```

### 1.3 Remediated Implementation
File: `scripts/weapons/weapon_ballistics.gd`

Lines 114–128:
```gdscript
func calculate_current_spread(
	posture: StringName,
	movement_speed_norm: float,
	is_airborne: bool
) -> float:
	current_posture = posture
	current_movement_speed_norm = clampf(movement_speed_norm, 0.0, 1.0)
	current_is_airborne = is_airborne
	var bloom_cap := _maximum_bloom_for(posture)
	var effective_bloom := minf(current_recoil_bloom, bloom_cap)
	current_recoil_bloom = effective_bloom
	total_current_spread_deg = _spread_for(posture, movement_speed_norm, is_airborne,
		continuous_shot_count, effective_bloom)
	return total_current_spread_deg
```

Lines 159–166:
```gdscript
func _bloom_after_shot(posture: StringName, shot_count: int) -> float:
	var bloom_cap := _maximum_bloom_for(posture)
	var bloom := minf(current_recoil_bloom, bloom_cap)
	if shot_count > 2:
		if bloom < bloom_cap:
			bloom = minf(bloom_cap, bloom + _bloom_per_shot_for(posture))
	return bloom
```

---

## 2. Logic Chain

1. **Root Cause**: In `_bloom_after_shot()`, `bloom` was initialized directly to `current_recoil_bloom`. If `current_recoil_bloom >= bloom_cap`, the branch `if bloom < bloom_cap:` was bypassed, returning the unclamped standing bloom (2.40°) directly into crouched (cap 1.70°) or prone (cap 1.07°) states (Obs. 1.1).
2. **Remediation in `_bloom_after_shot()`**: By initializing `var bloom := minf(current_recoil_bloom, bloom_cap)`, any accumulated bloom exceeding the target posture's cap is immediately clamped down to `bloom_cap` before evaluating burst increments. If `shot_count > 2` and `bloom < bloom_cap`, the increment is added and clamped to `bloom_cap`. If `bloom == bloom_cap`, it remains at `bloom_cap`.
3. **Remediation in `calculate_current_spread()`**: When stance drops without firing a shot, `calculate_current_spread()` is executed (both from `_process()` during recovery or state updates and from `update_spread_state()`). Setting `var effective_bloom := minf(current_recoil_bloom, bloom_cap)` and assigning `current_recoil_bloom = effective_bloom` guarantees that both the stored recoil bloom and the computed `total_current_spread_deg` instantly reflect the lower stance's cap.
4. **Preservation of Core Gameplay**:
   - The opening pair (shots 1 and 2) continue to produce 0.0° bloom (`if shot_count > 2:` check is intact).
   - Recovery timing, delays (0.30s delay), recovery rates (Prone 18.0, Crouch 18.0, Stand 10.0), and ISO 20/45 scaling (1.07° max prone) remain untouched.
   - All tests in `res://tools/adversarial_ballistics_stance_regression.gd`, `res://tools/weapon_stance_bloom_regression.gd`, and `res://tools/feature_contract_regression.gd` pass without warnings or regressions.

---

## 3. Caveats

- **No caveats**: The fix is minimal, self-contained within `scripts/weapons/weapon_ballistics.gd`, and strictly adheres to the single-owner architecture.

---

## 4. Conclusion

The ballistics stance transition defect has been resolved. Standing bloom no longer leaks into Crouch or Prone stances. The invariants are fully enforced:
- Crouch bloom <= 1.70° under all transition patterns.
- Prone bloom <= 1.07° under all transition patterns.
- Prone bloom <= Crouch bloom <= Stand bloom invariant is preserved at all times.
- Zero-delay firing rejection and quiet recovery delays operate according to authentic SOCOM 2 specifications.

---

## 5. Verification Method

Execute the following commands to independently verify:

1. **Adversarial Stance Regression**:
   ```bash
   /Users/kiwimango/Applications/Godot-4.7.1.app/Contents/MacOS/Godot --headless --path /Users/kiwimango/socom-141-camera-lab --script res://tools/adversarial_ballistics_stance_regression.gd
   ```
   *Expected Output*: `Total failures: 0`, `VERDICT: APPROVE (all empirical assertions passed)`, Exit code: 0.

2. **Weapon Stance Bloom Regression**:
   ```bash
   /Users/kiwimango/Applications/Godot-4.7.1.app/Contents/MacOS/Godot --headless --path /Users/kiwimango/socom-141-camera-lab --script res://tools/weapon_stance_bloom_regression.gd
   ```
   *Expected Output*: `WEAPON_STANCE_BLOOM_REGRESSION PASS ...`, Exit code: 0.

3. **Feature Contract Regression**:
   ```bash
   /Users/kiwimango/Applications/Godot-4.7.1.app/Contents/MacOS/Godot --headless --path /Users/kiwimango/socom-141-camera-lab --script res://tools/feature_contract_regression.gd
   ```
   *Expected Output*: `[FEATURE CONTRACT] PASS: 121 contract(s) form complete Godot integration graphs`, Exit code: 0.

4. **Stance Bloom Cap Regression**:
   ```bash
   /Users/kiwimango/Applications/Godot-4.7.1.app/Contents/MacOS/Godot --headless --path /Users/kiwimango/socom-141-camera-lab --script res://tools/stance_bloom_cap_regression.gd
   ```
   *Expected Output*: `STANCE_BLOOM_CAP_PASS: shared cap, baseline preserved, airborne unchanged`, Exit code: 0.

5. **Stance HUD Bloom Regression**:
   ```bash
   /Users/kiwimango/Applications/Godot-4.7.1.app/Contents/MacOS/Godot --headless --path /Users/kiwimango/socom-141-camera-lab --script res://tools/stance_hud_bloom_regression.gd
   ```
   *Expected Output*: `STANCE_HUD_BLOOM_PASS: stationary cap, moving/airborne and stance caps, matching ballistics, stance tracking and larger health/ammo`, Exit code: 0.
