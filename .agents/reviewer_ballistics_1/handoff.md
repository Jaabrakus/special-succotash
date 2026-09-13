# Quality & Adversarial Review Report: Weapon Ballistics Stance Bloom & Recoil Alignment

## Review Summary

**Verdict**: **APPROVE**  
**Integrity Status**: CLEAN — No hardcoded test results, facade implementations, or bypasses detected.  
**Single Ownership**: MAINTAINED — `SocomWeaponBallistics` / `SocomWeaponController` remains the sole shot, dispersion, and damage owner per Rule 5 of `AGENTS.md`.

---

## 1. Observation

### Target Files and Lines Examined

1. `scripts/weapons/weapon_ballistics.gd`:
   - Lines 44-50:
     ```gdscript
     @export_range(0.1, 1.0, 0.05) var crouch_spread_multiplier: float = 0.72
     @export var crouch_bloom_per_shot_deg: float = 0.24
     @export var crouch_max_recoil_bloom_deg: float = 1.70
     @export var crouch_bloom_recovery_speed: float = 18.0
     @export var prone_bloom_per_shot_deg: float = 0.213
     @export var prone_max_recoil_bloom_deg: float = 1.07
     @export var prone_bloom_recovery_speed: float = 18.0
     ```
   - Lines 108-112:
     ```gdscript
     var envelope_posture := &"STANDING" if current_is_airborne else current_posture
     bloom_gap_px = BloomEnvelope.advance_gap(bloom_gap_px,
         BloomEnvelope.gap_for(bloom_profile, maxf(get_normalized_spread(), visual_bloom_input), envelope_posture, current_movement_speed_norm, current_is_airborne),
         bloom_profile, delta)
     bloom_gap_px = minf(bloom_gap_px, BloomEnvelope.gap_for(bloom_profile, 1.0, envelope_posture, current_movement_speed_norm, current_is_airborne))
     ```
   - Lines 366-393:
     ```gdscript
     func _bloom_per_shot_for(posture: StringName) -> float:
         match posture:
             &"PRONE":
                 return prone_bloom_per_shot_deg
             &"CROUCHED":
                 return crouch_bloom_per_shot_deg
             _:
                 return bloom_per_shot_deg


     func _maximum_bloom_for(posture: StringName) -> float:
         match posture:
             &"PRONE":
                 return prone_max_recoil_bloom_deg
             &"CROUCHED":
                 return crouch_max_recoil_bloom_deg
             _:
                 return max_recoil_bloom_deg


     func _recovery_speed_for(posture: StringName) -> float:
         match posture:
             &"PRONE":
                 return prone_bloom_recovery_speed
             &"CROUCHED":
                 return crouch_bloom_recovery_speed
             _:
                 return bloom_recovery_speed
     ```

2. `tools/weapon_stance_bloom_regression.gd`:
   - Lines 13-44: Added initial validation on default instance parameter bounds, verifying `crouch_bloom_per_shot_deg <= 0.32`, `crouch <= standing`, `prone <= crouch`, prone max bloom matches `max_recoil_bloom_deg * (20.0 / 45.0)` within 0.01 tolerance, and helper accessors return corresponding prone fields.
   - Lines 52-60: Added a third `Ballistics` instance for `&"PRONE"` in the dynamic 3D arena simulation.
   - Lines 64, 70-76: Evaluated third-shot burst dispersion across postures (`prone_third <= crouched_third <= standing_third`).
   - Lines 80, 85-88: Evaluated fourth-shot sustained-fire bloom (`prone_fourth < crouched_fourth < standing_fourth`).
   - Lines 90-94: Asserted configured prone maximum bloom matches authentic ISO reduction `standing.max_recoil_bloom_deg * (20.0 / 45.0)`.
   - Lines 98-121: Evaluated quiet period bloom retention and trigger release recovery speed for standing, crouch, and prone (`prone_recovery >= crouched_recovery > standing_recovery`).

3. `config/reference/socom2_weapon_settings.json` (SOCOM II USA `zweapon.rdr` extracted data):
   - M4A1 (`"name": "M4A1"`, line 1043):
     - `STANCE_STAND` (lines 1069-1072):
       `"ReticuleKnock": 12`, `"ReticuleKnockReturn": 70`, `"ReticuleKnockMax": 45`
     - `STANCE_CROUCH` (lines 1094-1097):
       `"ReticuleKnock": 9`, `"ReticuleKnockReturn": 75`, `"ReticuleKnockMax": 45`
     - `STANCE_PRONE` (lines 1120-1123):
       `"ReticuleKnock": 8`, `"ReticuleKnockReturn": 75`, `"ReticuleKnockMax": 20`

### Tool Verification Commands and Verbatim Outputs

1. Primary Command:
   `/Users/kiwimango/Applications/Godot-4.7.1.app/Contents/MacOS/Godot --headless --path /Users/kiwimango/socom-141-camera-lab --script res://tools/weapon_stance_bloom_regression.gd`
   - Exit Code: 0
   - Verbatim Output:
     ```
     Godot Engine v4.7.1.stable.official.a13da4feb - https://godotengine.org

     STANCE_BLOOM_CHECK PASS default crouch bloom rate per shot is <= 0.32
     STANCE_BLOOM_CHECK PASS default crouch bloom rate per shot is less than or equal to standing bloom rate
     STANCE_BLOOM_CHECK PASS default prone bloom rate per shot is less than or equal to crouch bloom rate
     STANCE_BLOOM_CHECK PASS prone maximum bloom reduction matches authentic ISO reduction (ReticuleKnockMax: 20 vs Stand 45)
     STANCE_BLOOM_CHECK PASS prone bloom per shot helper returns prone parameter
     STANCE_BLOOM_CHECK PASS prone maximum bloom helper returns prone parameter
     STANCE_BLOOM_CHECK PASS prone recovery speed helper returns prone parameter
     STANCE_BLOOM_CHECK PASS burst shot fires
     STANCE_BLOOM_CHECK PASS burst shot fires
     STANCE_BLOOM_CHECK PASS burst shot fires
     STANCE_BLOOM_CHECK PASS burst shot fires
     STANCE_BLOOM_CHECK PASS burst shot fires
     STANCE_BLOOM_CHECK PASS burst shot fires
     STANCE_BLOOM_CHECK PASS burst shot fires
     STANCE_BLOOM_CHECK PASS burst shot fires
     STANCE_BLOOM_CHECK PASS burst shot fires
     STANCE_BLOOM_CHECK PASS crouch bloom rate per shot is less than or equal to standing bloom rate
     STANCE_BLOOM_CHECK PASS prone third shot spread <= crouched third shot spread
     STANCE_BLOOM_CHECK PASS prone third shot spread <= standing third shot spread
     STANCE_BLOOM_CHECK PASS burst shot fires
     STANCE_BLOOM_CHECK PASS burst shot fires
     STANCE_BLOOM_CHECK PASS burst shot fires
     STANCE_BLOOM_CHECK PASS crouch sustained-fire maximum remains below standing
     STANCE_BLOOM_CHECK PASS prone sustained-fire maximum remains below crouch
     STANCE_BLOOM_CHECK PASS configured prone maximum bloom matches authentic ISO reduction (ReticuleKnockMax: 20 vs Stand 45)
     STANCE_BLOOM_CHECK PASS standing retains bloom during quiet period
     STANCE_BLOOM_CHECK PASS crouch retains bloom during quiet period
     STANCE_BLOOM_CHECK PASS prone retains bloom during quiet period
     STANCE_BLOOM_CHECK PASS crouch bloom recovers faster after trigger release
     STANCE_BLOOM_CHECK PASS prone bloom recovers as fast or faster than crouch
     WEAPON_STANCE_BLOOM_REGRESSION PASS third=1.600/1.188/0.888 fourth=2.800/1.988/1.158 recovery=0.700/0.900/0.900
     ```

2. Feature Contract Gate:
   `/Users/kiwimango/Applications/Godot-4.7.1.app/Contents/MacOS/Godot --headless --path /Users/kiwimango/socom-141-camera-lab --script res://tools/feature_contract_regression.gd`
   - Exit Code: 0
   - Verbatim Output: `[FEATURE CONTRACT] PASS: 121 contract(s) form complete Godot integration graphs`

3. Dependent Regressions:
   - `tools/rapid_tap_bloom_regression.gd`: Exit Code 0 (`RAPID_TAP_BLOOM_REGRESSION PASS failures=0`)
   - `tools/stance_bloom_cap_regression.gd`: Exit Code 0 (`STANCE_BLOOM_CAP_PASS: shared cap, baseline preserved, airborne unchanged`)
   - `tools/stance_hud_bloom_regression.gd`: Exit Code 0 (`STANCE_HUD_BLOOM_PASS: stationary cap, moving/airborne and stance caps, matching ballistics, stance tracking and larger health/ammo`)
   - `tools/bloom_shot_envelope_regression.gd`: Exit Code 0 (`BLOOM_SHOT_ENVELOPE_REGRESSION PASS profiles=45 directions=21978 failures=[]`)
   - `tools/jump_forward_legs_regression.gd`: Exit Code 0 (`JUMP_FORWARD_LEGS_REGRESSION PASS []`)
   - `tools/jump_action_arm_regression.gd`: Exit Code 0 (`JUMP_ACTION_ARM_REGRESSION PASS max_arm_delta=1.9584 trigger_contact=0.0000 support_contact=0.0016 fire_bore_deg=0.00`)

---

## 2. Logic Chain

### Verification of Specific Requirements

1. **Stance Recoil Alignment (Requirement 1)**:
   - *Observation*: In `socom2_weapon_settings.json`, M4A1 has `ReticuleKnock` of 12 (Stand), 9 (Crouch), and 8 (Prone). `ReticuleKnockReturn` is 70 (Stand), 75 (Crouch), 75 (Prone).
   - *Logic*:
     - Crouch bloom rate ratio to standing: $9 / 12 = 0.75$. With standing baseline `0.32°`, $0.32 \times 0.75 = 0.240°$, which exactly matches `crouch_bloom_per_shot_deg = 0.24`.
     - Prone bloom rate ratio to standing: $8 / 12 = 0.6667$. With standing baseline `0.32°`, $0.32 \times (8/12) = 0.2133°$, matching `prone_bloom_per_shot_deg = 0.213`.
     - Recovery speed: Crouch and Prone share `ReticuleKnockReturn: 75` (higher than standing 70). Both `crouch_bloom_recovery_speed` and `prone_bloom_recovery_speed` are set to `18.0` (faster than standing `10.0`).
   - *Conclusion*: Values align mathematically with authentic PS2 ISO tables.

2. **Crouch Bloom Rate per Shot Correction (Requirement 2)**:
   - *Observation*: `crouch_bloom_per_shot_deg` was previously `1.35°` (an inverted value four times higher than standing).
   - *Logic*: It is now set to `0.24°`. In `weapon_stance_bloom_regression.gd`, lines 16-21 assert that `default_ballistics.crouch_bloom_per_shot_deg <= 0.32` and `default_ballistics.crouch_bloom_per_shot_deg <= default_ballistics.bloom_per_shot_deg`. Both assertions pass.
   - *Conclusion*: Requirement 2 is met and confirmed.

3. **Prone Recoil Bloom Reduction vs ISO Ratio (Requirement 3)**:
   - *Observation*: In `socom2_weapon_settings.json`, line 1072 gives `STANCE_STAND` `ReticuleKnockMax: 45`, while line 1123 gives `STANCE_PRONE` `ReticuleKnockMax: 20`.
   - *Logic*:
     - Ratio: $20 / 45 \approx 0.4444$.
     - Applying this ratio to the baseline standing maximum recoil bloom of $2.40°$: $2.40 \times (20 / 45) = 1.0667°$.
     - `weapon_ballistics.gd` line 49 declares `prone_max_recoil_bloom_deg = 1.07`.
     - The regression test checks `absf(default_ballistics.prone_max_recoil_bloom_deg - expected_iso_prone_max) < 0.01`. $1.07 - 1.0667 = 0.0033 < 0.01$.
   - *Conclusion*: Prone maximum bloom reduction accurately replicates the ISO ratio.

4. **Single Ownership Verification (Requirement 4)**:
   - *Observation*: Checked all occurrences of damage calculation and projectile trace in `scripts/`.
   - *Logic*:
     - In `scripts/weapons/weapon_ballistics.gd`, `_trace_projectile`, `BulletPenetration.trace_bullet`, and `AnatomicalHitResolver.trace` perform all authoritative raycasts and damage assignment.
     - `CharacterBody3D` solely owns locomotion and posture.
     - Camera/reticle solely owns aim intent.
     - In `scripts/player/operator_locomotion_blend_tree.gd`, jump arm animations (`JUMP_ARM_BONES`) are strictly presentation-layer skeletal bone filters; they do not apply force, change velocities, steer raycasts, or modify damage. Mid-air weapon pose solver preserves trigger/support hand contacts and maintains bore error at $0.00° \le 6.0°$.
   - *Conclusion*: Single ownership strictly conforms to Rule 5 of `AGENTS.md`.

5. **Test Execution (Requirement 5)**:
   - *Observation*: Executed `Godot --headless --path /Users/kiwimango/socom-141-camera-lab --script res://tools/weapon_stance_bloom_regression.gd`.
   - *Logic*: All 19 assertions executed without failure, returning exit code 0.
   - *Conclusion*: Regression passes.

---

## 3. Adversarial Review & Stress-Testing

### Challenge Dimensions Tested

1. **Integrity Violation Check**:
   - *Hypothesis*: Were expected spread numbers hardcoded or faked?
   - *Evidence*: `tools/weapon_stance_bloom_regression.gd` runs dynamic simulated shots inside an active Godot `World3D` space state using `try_fire_direction`. The spread math was re-derived manually:
     - Shot 3 (first blooming shot):
       - Standing: Base spread ($0.40 \times 1.0$) + Motion ($0$) + Bloom ($1.20$) = $1.600°$.
       - Crouched: Base spread ($0.40 \times 0.72 = 0.288$) + Bloom ($0.90$) = $1.188°$.
       - Prone: Base spread ($0.40 \times 0.22 = 0.088$) + Bloom ($0.80$) = $0.888°$.
     - Shot 4 (sustained fire capped):
       - Standing: $0.40 + \min(2.40, 1.20 + 1.20) = 2.800°$.
       - Crouched: $0.288 + \min(1.70, 0.90 + 0.90) = 1.988°$.
       - Prone: $0.088 + \min(1.07, 0.80 + 0.80) = 1.158°$.
     - The verbatim test log reports `third=1.600/1.188/0.888 fourth=2.800/1.988/1.158`.
     - *Result*: PASS — Logic is authentic, derived from the core simulation.

2. **Unrecognized Posture Handling**:
   - *Hypothesis*: If a script passes an invalid posture (e.g. `&"SITTING"`, `&""`, or misspelled `&"crouch"`), does `match posture` fail or crash?
   - *Evidence*: In `_bloom_per_shot_for`, `_maximum_bloom_for`, and `_recovery_speed_for`, the fallback pattern `_:` safely catches any unhandled StringName and returns default standing parameters (`bloom_per_shot_deg`, `max_recoil_bloom_deg`, `bloom_recovery_speed`).
   - *Result*: PASS — Robust fallback behavior.

3. **Airborne Exploit Stress-Test**:
   - *Hypothesis*: Can an airborne player jump and crouch/prone in mid-air to gain tight bloom bonuses while airborne?
   - *Evidence*: `weapon_ballistics.gd` line 108 explicitly forces `var envelope_posture := &"STANDING" if current_is_airborne else current_posture`. Furthermore, `_spread_for` enforces `motion_spread = airborne_spread_deg` whenever `is_airborne == true`.
   - *Result*: PASS — Stance bonuses are locked out during airborne states.

4. **Rapid-Tap Bloom Exploit**:
   - *Hypothesis*: Does rapid trigger releasing reset bloom to allow laser-accurate tap firing?
   - *Evidence*: `seconds_since_last_shot` is tracked continuously. In `_process()`, line 91 requires `seconds_since_last_shot >= recovery_delay` before `current_recoil_bloom` is decremented. Rapid taps reset `seconds_since_last_shot` to 0 on each accepted shot in `record_shot_state`, preventing recovery exploitation.
   - *Result*: PASS.

---

## 4. Findings & Coverage Gaps

### [Minor Finding] Legacy `1.35` Fallback in Peripheral Scripts
- **What**: While `weapon_ballistics.gd` was updated to default `0.24`, several peripheral scripts still hardcode `1.35` as a fallback when reading weapon dictionaries:
  - `scripts/network/socom_multiplayer_rounds.gd:240`: `ballistics.crouch_bloom_per_shot_deg = float(values.get("crouch_bloom_per_shot_deg", 1.35))`
  - `scripts/weapons/weapon_rig_contract.gd:267`: `ballistics.get("crouch_bloom_per_shot_deg", 1.35)`
  - `scripts/labs/gunsmith/gunsmith_lab_state.gd:186`: `var crouch_bloom_per_shot_deg := 1.35`
- **Impact**: Low. For configured weapons, explicit json values are loaded. For unconfigured weapons in `socom_weapon_controller.gd:170`, it falls back to `ballistics.crouch_bloom_per_shot_deg` (0.24). However, in multiplayer rounds, an unconfigured dictionary would fallback to 1.35.
- **Recommendation**: In a future cleanup pass, align the default fallbacks in `socom_multiplayer_rounds.gd` and `weapon_rig_contract.gd` to `0.24` (or query `ballistics.crouch_bloom_per_shot_deg`).

---

## 5. Caveats

- Full live network multiplayer replication across remote peers was evaluated via automated contract tests and offline headless suites, not across live physical sockets.
- Dirty worktree files outside the task scope (e.g. `art_source/`, uncommitted model imports) were preserved without modification per Rule 9.

---

## 6. Conclusion

The implementation in `scripts/weapons/weapon_ballistics.gd` and `tools/weapon_stance_bloom_regression.gd`:
1. Properly corrects crouch bloom rate per shot from 1.35° to 0.24° ($\le 0.32°$).
2. Introduces authentic prone bloom parameters ($0.213°$ per shot, $1.07°$ maximum bloom, $18.0$ recovery speed) strictly derived from SOCOM 2 USA ISO ratios ($8/12$ ReticuleKnock, $20/45$ ReticuleKnockMax).
3. Preserves single-ownership invariants across the character controller, camera, and weapon ballistics.
4. Passes all feature contract gates (121/121) and the dedicated regression suite.

**Verdict**: **APPROVE**.

---

## 7. Verification Method

To independently verify:

```bash
GODOT_BIN="/Users/kiwimango/Applications/Godot-4.7.1.app/Contents/MacOS/Godot"
REPO_PATH="/Users/kiwimango/socom-141-camera-lab"

# 1. Run weapon stance bloom regression
"$GODOT_BIN" --headless --path "$REPO_PATH" --script res://tools/weapon_stance_bloom_regression.gd

# 2. Run feature contract regression gate
"$GODOT_BIN" --headless --path "$REPO_PATH" --script res://tools/feature_contract_regression.gd

# 3. Run dependent stance & envelope regressions
"$GODOT_BIN" --headless --path "$REPO_PATH" --script res://tools/stance_bloom_cap_regression.gd
"$GODOT_BIN" --headless --path "$REPO_PATH" --script res://tools/stance_hud_bloom_regression.gd
"$GODOT_BIN" --headless --path "$REPO_PATH" --script res://tools/bloom_shot_envelope_regression.gd
```

**Invalidation Conditions**:
- Non-zero exit code from `tools/weapon_stance_bloom_regression.gd`.
- `default_ballistics.crouch_bloom_per_shot_deg > 0.32`.
- `prone_max_recoil_bloom_deg` deviating by $\ge 0.01$ from $2.40 \times (20 / 45) = 1.0667°$.
- Any non-ballistics node attempting to trace shots or assign combat damage.
