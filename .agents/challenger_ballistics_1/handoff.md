# Handoff Report: Empirical Adversarial Verification of Ballistics Stance Recoil & Bloom

**Verdict**: **REQUEST_CHANGES**

---

## 1. Observation

### 1.1 Implementation Code Under Review
File: `scripts/weapons/weapon_ballistics.gd`

Relevant excerpts:

Lines 40–50:
```gdscript
@export var max_recoil_bloom_deg: float = 2.4
@export var bloom_per_shot_deg: float = 0.32
@export var bloom_recovery_speed: float = 10.0 # Rapid decay on pause
@export_range(0.05, 1.0, 0.01) var bloom_recovery_delay_seconds: float = 0.30
@export_range(0.1, 1.0, 0.05) var crouch_spread_multiplier: float = 0.72
@export var crouch_bloom_per_shot_deg: float = 0.24
@export var crouch_max_recoil_bloom_deg: float = 1.70
@export var crouch_bloom_recovery_speed: float = 18.0
@export var prone_bloom_per_shot_deg: float = 0.213
@export var prone_max_recoil_bloom_deg: float = 1.07
@export var prone_bloom_recovery_speed: float = 18.0
```

Lines 156–163:
```gdscript
func _bloom_after_shot(posture: StringName, shot_count: int) -> float:
	var bloom := current_recoil_bloom
	if shot_count > 2:
		var bloom_cap := _maximum_bloom_for(posture)
		if bloom < bloom_cap:
			bloom = minf(bloom_cap, bloom + _bloom_per_shot_for(posture))
	return bloom
```

Lines 253–264:
```gdscript
func record_shot_state(posture: StringName, movement_speed_norm: float, is_airborne: bool) -> bool:
	# Shared recoil/bloom state only. No trace, damage, inventory or signal.
	if fire_cooldown > 0.0:
		return false
	fire_cooldown = fire_interval
	continuous_shot_count += 1
	is_firing_held = true
	current_posture = posture
	seconds_since_last_shot = 0.0
	current_recoil_bloom = _bloom_after_shot(posture, continuous_shot_count)
	calculate_current_spread(posture, movement_speed_norm, is_airborne)
	return true
```

Lines 376–384:
```gdscript
func _maximum_bloom_for(posture: StringName) -> float:
	match posture:
		&"PRONE":
			return prone_max_recoil_bloom_deg
		&"CROUCHED":
			return crouch_max_recoil_bloom_deg
		_:
			return max_recoil_bloom_deg
```

### 1.2 Empirical Test Execution
Command:
```bash
/Users/kiwimango/Applications/Godot-4.7.1.app/Contents/MacOS/Godot --headless --path /Users/kiwimango/socom-141-camera-lab --script res://tools/adversarial_ballistics_stance_regression.gd
```

Test Results (verbatim terminal output excerpt):
```
=== EMPIRICAL ADVERSARIAL BALLISTICS STANCE AUDIT ===

--- Test 1: Extreme Burst Lengths (1, 2, 3, 10, 50 rounds) ---
  STANDING: round 1=0.000, round 2=0.000, round 3=0.320, round 10=2.400, round 50=2.400 (cap=2.400)
  CROUCHED: round 1=0.000, round 2=0.000, round 3=0.240, round 10=1.700, round 50=1.700 (cap=1.700)
  PRONE: round 1=0.000, round 2=0.000, round 3=0.213, round 10=1.070, round 50=1.070 (cap=1.070)

--- Test 2: Zero-Delay Firing & Cooldown Rejection ---

--- Test 3: Bloom Recovery Timing & Ordering (Prone >= Crouch >= Stand) ---
  Recovery rates: Prone=18.00 deg/s, Crouch=18.00 deg/s, Stand=10.00 deg/s
  0.05s decay amount: Prone=0.9000°, Crouch=0.9000°, Stand=0.5000°

--- Test 4: ISO 20/45 Scaling & Prone Max Bloom <= 1.07° ---
  Max recoil bloom export values: Stand=2.400°, Crouch=1.700°, Prone=1.070°
  ISO 20/45 expected prone max: 1.0667°

--- Test 5: Isolated Stance Invariant (Prone <= Crouch <= Stand for isolated bursts) ---

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
  [FAIL] CRITICAL: Crouch bloom (2.4000°) EXCEEDS crouch_max_recoil_bloom_deg (1.7000°) after Stand->Crouch transition!
  [FAIL] CRITICAL: Prone bloom (2.4000°) EXCEEDS 1.07° limit after transition! Prone cap (1.0700°) was bypassed!
  [FAIL] CRITICAL: Prone bloom (2.4000°) EXCEEDS Crouch bloom (1.7000°)!
  [FAIL] Per-shot cycling: shot 9 (PRONE) bloom 1.5460 EXCEEDS cap 1.0700!
VERDICT: REQUEST_CHANGES (4 empirical assertions failed)
```

---

## 2. Logic Chain

1. **Static and isolated properties are well-formed** (Obs. 1.1, 1.2):
   - In static isolated stances, burst lengths 1 and 2 produce exactly 0.000° bloom (2-round pinpoint burst).
   - Shot 3 produces exactly 1x stance bloom (Stand 0.320°, Crouch 0.240°, Prone 0.213°).
   - Shots 10 and 50 strictly cap at their respective posture maximums (Stand 2.400°, Crouch 1.700°, Prone 1.070°).
   - `prone_max_recoil_bloom_deg = 1.07` conforms within 0.0033° to ISO 20/45 scaling: `2.40 * 20.0 / 45.0 = 1.0667°`.
   - Recovery speeds satisfy `Prone (18.0) >= Crouch (18.0) >= Stand (10.0)`.
   - Zero-delay firing is properly rejected by `fire_cooldown > 0.0` without state advancement.

2. **Flaw mechanism in `_bloom_after_shot`** (Obs. 1.1):
   - In `scripts/weapons/weapon_ballistics.gd:156-163`:
     ```gdscript
     func _bloom_after_shot(posture: StringName, shot_count: int) -> float:
         var bloom := current_recoil_bloom
         if shot_count > 2:
             var bloom_cap := _maximum_bloom_for(posture)
             if bloom < bloom_cap:
                 bloom = minf(bloom_cap, bloom + _bloom_per_shot_for(posture))
         return bloom
     ```
   - The conditional `if bloom < bloom_cap:` guards only the *increment* branch.
   - If `current_recoil_bloom` already exceeds `bloom_cap` (because the weapon accumulated bloom in a higher stance such as `STANDING` where cap is 2.40°), `bloom < bloom_cap` evaluates to `false`.
   - The function returns `bloom` unmodified, leaving `current_recoil_bloom = 2.40°`.
   - Neither `record_shot_state`, `calculate_current_spread`, nor `_process` performs any downward clamping to `_maximum_bloom_for(posture)`.

3. **Violation of Mandated Invariants under Transition** (Obs. 1.2):
   - When firing 10 rounds Standing (`bloom = 2.40°`) and transitioning to Crouch:
     - Crouch bloom becomes 2.40°, exceeding `crouch_max_recoil_bloom_deg` (1.70°) by +41.2%.
   - When transitioning from Standing (or high Crouch) to Prone mid-burst:
     - Prone bloom becomes 2.40°, exceeding the required 1.07° maximum bloom cap by +124.3%.
     - Prone bloom (2.40°) exceeds Crouch bloom (1.70°), violating the invariant that prone bloom never exceeds crouch bloom under any circumstance.
   - During per-shot stance cycling (Stand -> Crouch -> Prone), by shot 9 (in Prone), bloom reaches 1.5460°, which exceeds the 1.07° cap.

---

## 3. Caveats

- In isolated single-stance play without mid-burst stance transitions, all stance parameters, burst lengths, ISO scalings, and recovery rates pass all checks.
- Movement multipliers (`moving_spread_deg = 0.95`, `full_gait_spread_deg = 1.55`) and airborne multipliers (`airborne_spread_deg = 4.8`) were verified to add linearly to base spread and do not alter the underlying `current_recoil_bloom` variable itself.
- Reticle presentation (`reticle_bloom_envelope.gd`) correctly caps visual gap expansion per posture (`STANDING`: 50px, `CROUCHED`: 40px, `PRONE`: 32px), creating a presentation/ballistics divergence where the physical bullet dispersion cone remains 2.40° while the reticle graphics believe the weapon is capped at prone limits.

---

## 4. Conclusion

The weapon ballistics implementation fails 2 out of the 4 specified acceptance invariants under dynamic stance transition conditions:
1. **FAILED**: Under rapid stance transitions, crouch bloom exceeds `crouch_max_recoil_bloom_deg`, and prone bloom (2.40°) exceeds crouch bloom (1.70°).
2. **FAILED**: Prone maximum bloom reaches 2.40° upon transition from Stand, directly violating the 1.07° maximum limit (ISO 20/45 scaling of 2.40°).
3. **PASSED**: Extreme burst lengths (1, 2, 3, 10, 50 rounds) in isolated stances behave strictly according to spec.
4. **PASSED**: Zero-delay cadence rejection prevents trigger-mashing exploits.
5. **PASSED**: Bloom recovery rates satisfy Prone (18.0) >= Crouch (18.0) >= Stand (10.0) with an exact 0.30s quiet period.

**Remediation Recommendation**:
In `scripts/weapons/weapon_ballistics.gd`:
1. In `_bloom_after_shot(posture: StringName, shot_count: int) -> float`:
   Clamp incoming bloom to `bloom_cap`:
   ```gdscript
   func _bloom_after_shot(posture: StringName, shot_count: int) -> float:
       var bloom_cap := _maximum_bloom_for(posture)
       var bloom := minf(current_recoil_bloom, bloom_cap)
       if shot_count > 2:
           if bloom < bloom_cap:
               bloom = minf(bloom_cap, bloom + _bloom_per_shot_for(posture))
       return bloom
   ```
2. In `calculate_current_spread(posture: StringName, movement_speed_norm: float, is_airborne: bool)`:
   Ensure `effective_bloom = minf(current_recoil_bloom, _maximum_bloom_for(posture))` is used so the reticle spread and preview cone also immediately reflect the lower stance cap when dropping posture without firing.

**Verdict**: **REQUEST_CHANGES**

---

## 5. Verification Method

To independently verify the defect:

1. Run the headless regression test suite:
   ```bash
   /Users/kiwimango/Applications/Godot-4.7.1.app/Contents/MacOS/Godot --headless --path /Users/kiwimango/socom-141-camera-lab --script res://tools/adversarial_ballistics_stance_regression.gd
   ```
2. Expected exit code: `1` (until remediation is applied).
3. Inspect lines 305–360 in `tools/adversarial_ballistics_stance_regression.gd` for the exact test harness reproducing the Stand (10 shots) -> Crouch (shot 11) -> Prone (shot 12) transition.
4. Invalidation condition: The test will exit with code `0` and print `VERDICT: APPROVE (all empirical assertions passed)` once `_bloom_after_shot` and spread calculation enforce stance caps on transition.
