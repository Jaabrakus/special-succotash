# Handoff Report: Stance Ballistics Alignment & Jump Arm Animation Integration

## 1. Observation

### Code and Configuration Modifications
- `scripts/weapons/weapon_ballistics.gd`:
  - Lines 18-20: Added prone parameters:
    ```gdscript
    @export var prone_bloom_per_shot_deg: float = 0.213
    @export var prone_max_recoil_bloom_deg: float = 1.07
    @export var prone_bloom_recovery_speed: float = 18.0
    ```
  - Line 25: Corrected `crouch_bloom_per_shot_deg` from `1.35` to `0.24` (4 spaces indentation matching file format).
  - Lines 86-90: Added `&"PRONE"` branching in `_bloom_per_shot_for`:
    ```gdscript
    func _bloom_per_shot_for(posture: StringName) -> float:
        if posture == &"PRONE":
            return prone_bloom_per_shot_deg
        if posture == &"CROUCHED":
            return crouch_bloom_per_shot_deg
        return bloom_per_shot_deg
    ```
  - Lines 93-97: Added `&"PRONE"` branching in `_maximum_bloom_for`:
    ```gdscript
    func _maximum_bloom_for(posture: StringName) -> float:
        if posture == &"PRONE":
            return prone_max_recoil_bloom_deg
        if posture == &"CROUCHED":
            return crouch_max_recoil_bloom_deg
        return max_recoil_bloom_deg
    ```
  - Lines 100-104: Added `&"PRONE"` branching in `_recovery_speed_for`:
    ```gdscript
    func _recovery_speed_for(posture: StringName) -> float:
        if posture == &"PRONE":
            return prone_bloom_recovery_speed
        if posture == &"CROUCHED":
            return crouch_bloom_recovery_speed
        return bloom_recovery_speed
    ```

- `scripts/player/operator_locomotion_blend_tree.gd`:
  - Lines 23-32: Defined `JUMP_ARM_BONES` containing 8 arm tracks:
    ```gdscript
    const JUMP_ARM_BONES: Array[StringName] = [
        &"mixamorig_LeftShoulder",
        &"mixamorig_LeftArm",
        &"mixamorig_LeftForeArm",
        &"mixamorig_LeftHand",
        &"mixamorig_RightShoulder",
        &"mixamorig_RightArm",
        &"mixamorig_RightForeArm",
        &"mixamorig_RightHand",
    ]
    ```
  - Lines 130-132: Initialized `jump_lower_body_clip` early in `build()` to prevent race condition with `_build_modern_route`:
    ```gdscript
    var jump_lower_body_config: Dictionary = profile.get("jump_lower_body", {})
    jump_lower_body_clip = StringName(jump_lower_body_config.get("clip", &""))
    ```
  - Lines 606-613: Added `JUMP_ARM_BONES` to `legs` blend node filter in `_build_jump_lower_body_layer`:
    ```gdscript
    for bone: StringName in JUMP_ARM_BONES:
        var path := "Armature/GeneralSkeleton:" + String(bone)
        legs.set_filter_path(path, true)
        filter_paths.append(path)
    ```
  - Lines 634-638: Bypassed upper body ready layer for jump clips in `_uses_upper_body_ready_layer`:
    ```gdscript
    func _uses_upper_body_ready_layer(clip_name: StringName) -> bool:
        if source_jump_clip(clip_name) or clip_name == jump_lower_body_clip:
            return false
        return true
    ```

- `config/feature_contracts/jump_forward_legs.json`:
  - Updated `symbols` to document `JUMP_ARM_BONES`, hand contact gaps (<= 0.015m trigger, <= 0.020m support), and fire bore alignment (<= 6.0°).
  - Added `tools/jump_action_arm_regression.gd` to `proof_scenes_and_scripts`.
  - Updated `system_delta` with rationale for arm articulation and aim/fire preservation under Rule 5.

- `tools/weapon_stance_bloom_regression.gd`:
  - Added assertions for default instance parameters: `crouch_bloom_per_shot_deg <= 0.32`, `crouch <= standing`, `prone <= crouch`, and ISO max bloom ratio `20 / 45`.
  - Updated dynamic burst firing assertion to `crouched_third <= standing_third` and `prone_third <= crouched_third`.
  - Added prone sustained-fire and recovery assertions.

- `tools/jump_forward_legs_regression.gd`:
  - Updated filter verification to assert all `JUMP_ARM_BONES` are included in `legs` filter while `AIM_FRAME_BONES` remain excluded.
  - Updated `_check_pose_mask` to verify `AIM_FRAME_BONES` error < 0.0001 while `arm_difference_rad > 0.10` radians.
  - Added live jump airborne verification checking `arm_delta > 0.10 rad`, `trigger_gap <= 0.015m`, `support_gap <= 0.020m`, and `bore_error_deg <= 6.0°`.

- `tools/jump_action_arm_regression.gd`:
  - Newly created standalone regression tool testing blend graph filtering, airborne arm rotational delta (measured 1.9528 rad > 0.10 rad), trigger contact (0.0000m <= 0.015m), support contact (0.0016m <= 0.020m), and mid-air fire bore error (0.00° <= 6.0°).

### Tool Commands and Verbatim Output
1. `/Users/kiwimango/Applications/Godot-4.7.1.app/Contents/MacOS/Godot --headless -s tools/feature_contract_regression.gd`
   - Exit Code: 0
   - Verbatim Output:
     `[FEATURE CONTRACT] PASS: 121 contract(s) form complete Godot integration graphs`

2. `/Users/kiwimango/Applications/Godot-4.7.1.app/Contents/MacOS/Godot --headless -s tools/weapon_stance_bloom_regression.gd`
   - Exit Code: 0
   - Verbatim Output:
     ```
     STANCE_BLOOM_CHECK PASS default crouch bloom rate per shot is <= 0.32
     STANCE_BLOOM_CHECK PASS default crouch bloom rate per shot is less than or equal to standing bloom rate
     STANCE_BLOOM_CHECK PASS default prone bloom rate per shot is less than or equal to crouch bloom rate
     STANCE_BLOOM_CHECK PASS prone maximum bloom reduction matches authentic ISO reduction (ReticuleKnockMax: 20 vs Stand 45)
     STANCE_BLOOM_CHECK PASS prone bloom per shot helper returns prone parameter
     STANCE_BLOOM_CHECK PASS prone maximum bloom helper returns prone parameter
     STANCE_BLOOM_CHECK PASS prone recovery speed helper returns prone parameter
     STANCE_BLOOM_CHECK PASS crouch bloom rate per shot is less than or equal to standing bloom rate
     STANCE_BLOOM_CHECK PASS prone third shot spread <= crouched third shot spread
     STANCE_BLOOM_CHECK PASS prone third shot spread <= standing third shot spread
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

3. `/Users/kiwimango/Applications/Godot-4.7.1.app/Contents/MacOS/Godot --headless -s tools/jump_forward_legs_regression.gd`
   - Exit Code: 0
   - Verbatim Output:
     ```
     JUMP_FORWARD_LEGS_METRIC rise_m=0.61121818982065 source_seconds=0.8333333 single_playhead_seconds=0.45138888888889 arm_delta=1.95311224460602 trigger_gap=0.0 support_gap=0.00170280586462 bore_error_deg=0.00073648602261
     JUMP_FORWARD_MASK_METRIC normal jump aim_frame_error=0.0 leg_difference_rad=1.60018765926361 arm_difference_rad=1.59044528007507
     JUMP_FORWARD_LEGS_REGRESSION PASS []
     ```

4. `/Users/kiwimango/Applications/Godot-4.7.1.app/Contents/MacOS/Godot --headless -s tools/jump_action_arm_regression.gd`
   - Exit Code: 0
   - Verbatim Output:
     ```
     JUMP_ACTION_ARM_REGRESSION PASS max_arm_delta=1.9528 trigger_contact=0.0000 support_contact=0.0016 fire_bore_deg=0.00
     ```

5. `/Users/kiwimango/Applications/Godot-4.7.1.app/Contents/MacOS/Godot --headless -s tools/source_jump_regression.gd`
   - Exit Code: 0
   - Verbatim Output:
     `SOURCE_JUMP_REGRESSION PASS []`

6. `/Users/kiwimango/Applications/Godot-4.7.1.app/Contents/MacOS/Godot --headless -s tools/running_jump_direction_regression.gd`
   - Exit Code: 0
   - Verbatim Output:
     `RUNNING_JUMP_DIRECTION_REGRESSION PASS []`

---

## 2. Logic Chain

1. **Recoil & Bloom Alignment (R1)**:
   - Observation: ISO `zweapon.rdr` specifies `ReticuleKnock` ratio 9/12 (0.75) for crouch and 8/12 (0.667) for prone relative to standing, and `ReticuleKnockMax` 20 for prone vs 45 for standing (ratio 0.444). Previously, `crouch_bloom_per_shot_deg` was inverted at `1.35°` (higher than standing `0.32°`), and `&"PRONE"` lacked branching, falling back to standing values.
   - Deduction: Correcting `crouch_bloom_per_shot_deg` to `0.24°` (0.75 * 0.32°) ensures crouched bloom per shot <= standing bloom per shot. Adding prone parameters (`prone_bloom_per_shot_deg = 0.213°`, `prone_max_recoil_bloom_deg = 1.07°`, `prone_bloom_recovery_speed = 18.0`) and explicit `&"PRONE"` branching in `_bloom_per_shot_for`, `_maximum_bloom_for`, and `_recovery_speed_for` establishes authentic SOCOM 2 progression: standing (1.600° / 2.800°) > crouched (1.188° / 1.988°) > prone (0.888° / 1.158°).
   - Validation: `weapon_stance_bloom_regression.gd` confirms all assertions pass with exit code 0.

2. **Jump Arm Animation Integration (R2)**:
   - Observation: In `operator_locomotion_blend_tree.gd`, the `legs` blend node previously filtered only `JUMP_LEG_BONES`, leaving arm tracks omitted. Furthermore, `_uses_upper_body_ready_layer` routed clips through `rifle_ready_pose`, which overwrote arm tracks with static grounded low-ready poses.
   - Deduction: Adding `JUMP_ARM_BONES` (`mixamorig_LeftShoulder` through `mixamorig_RightHand`) to the `legs` filter allows jump clip arm motion through to the output skeleton. Bypassing `_uses_upper_body_ready_layer` for jump clips ensures the dynamic arm animation plays unmasked while airborne.
   - Aim Authority Preservation (Rule 5): `AIM_FRAME_BONES` (`mixamorig_Spine`, `mixamorig_Spine1`, `mixamorig_Spine2`, `mixamorig_Neck`, `mixamorig_Head`) and `mixamorig_Hips` remain strictly unfiltered (`filter_path = false`), keeping camera aim tracking and pelvis movement unperturbed. When the operator aims/fires mid-air, `SocomOperatorWeaponPoseSolver` presentation IK actively locks hands to weapon contact sockets and weapon bore to camera reticle (measured at 0.0007° and 0.00° error, well within the 6.0° tolerance).
   - Validation: `jump_forward_legs_regression.gd` and `jump_action_arm_regression.gd` verify arm delta = 1.9528 rad (> 0.10 rad), trigger contact = 0.0000m (<= 0.015m), support contact = 0.0016m (<= 0.020m), and mid-air bore-to-reticle error = 0.00° (<= 6.0°).

3. **Contract & Regression Integrity (R3)**:
   - Observation: `config/feature_contracts/jump_forward_legs.json` required updating to declare `JUMP_ARM_BONES` and link proof scripts.
   - Deduction: Running `feature_contract_regression.gd` verifies 121/121 contracts without broken nodes, missing scenes, or syntax errors.

---

## 3. Caveats

- **Scope Boundary**: Edits were strictly bounded to the 6 owned files. No files outside the declared list were touched.
- **Dirty Worktree Preservation**: Pre-existing uncommitted changes in unrelated directories (`art_source/`, `assets/`, `scripts/items/`, etc.) were left untouched per Rule 9.
- **Indentation Conventions**: `scripts/weapons/weapon_ballistics.gd` uses 4 spaces for indentation, while `scripts/player/operator_locomotion_blend_tree.gd` uses tabs. Code additions strictly followed each file's established format to avoid GDScript mixed-indentation parse errors.

---

## 4. Conclusion

Requirements R1, R2, and R3 are fully implemented, verified, and ready for handoff:
1. **R1**: Stance recoil and bloom rates in `weapon_ballistics.gd` genuinely reflect authentic PS2 ISO ratios (`zweapon.rdr`), resolving the crouch bloom inversion and adding dedicated prone handling.
2. **R2**: Forward jump arm animations (`mixamorig_LeftShoulder` through `mixamorig_RightHand`) articulate visibly with >1.95 rad delta during jump, while preserving strict aim authority, hand contacts (<0.002m), and bore alignment (<0.01°) under Rule 5.
3. **R3**: All automated regressions (`feature_contract_regression.gd`, `weapon_stance_bloom_regression.gd`, `jump_forward_legs_regression.gd`, `jump_action_arm_regression.gd`, `source_jump_regression.gd`, `running_jump_direction_regression.gd`) pass with exit code 0.

---

## 5. Verification Method

To independently reproduce and verify all results:

```bash
export GODOT_BIN="/Users/kiwimango/Applications/Godot-4.7.1.app/Contents/MacOS/Godot"

# 1. Feature Contract Gate (121 contracts)
"$GODOT_BIN" --headless -s tools/feature_contract_regression.gd

# 2. Weapon Stance Recoil & Bloom Regression
"$GODOT_BIN" --headless -s tools/weapon_stance_bloom_regression.gd

# 3. Jump Forward Legs & Mask Regression
"$GODOT_BIN" --headless -s tools/jump_forward_legs_regression.gd

# 4. Jump Action Arm & Aim Authority Regression
"$GODOT_BIN" --headless -s tools/jump_action_arm_regression.gd

# 5. Source Jump Regression
"$GODOT_BIN" --headless -s tools/source_jump_regression.gd

# 6. Running Jump Direction Regression
"$GODOT_BIN" --headless -s tools/running_jump_direction_regression.gd
```

**Invalidation Conditions**:
- Any regression script exits with non-zero status.
- `crouch_bloom_per_shot_deg` exceeds `0.32°`.
- `prone_max_recoil_bloom_deg` deviates from ISO ratio (`2.40 * (20/45) = 1.07°`).
- Airborne arm rotational delta drops below `0.10` radians.
- Hand contact gap exceeds `0.015m` (trigger) or `0.020m` (support).
- Mid-air fire bore error exceeds `6.0°`.
