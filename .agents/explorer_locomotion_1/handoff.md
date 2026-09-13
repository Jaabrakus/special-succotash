# Handoff Report: Locomotion, Posture & Jump Mechanics Quality Audit

**Agent**: `explorer_locomotion_1`  
**Working Directory**: `/Users/kiwimango/socom-141-camera-lab/.agents/explorer_locomotion_1`  
**Primary Deliverable**: `locomotion_audit.md`  
**Handoff Type**: Hard (Audit Task Complete)  

---

## 1. Observation

Direct observations from script inspection, scene tree inspection, and test execution:

1. **Lean Collision Hull**:
   - In `scripts/player/player_controller.gd:909-924`, `_apply_posture_collider()` modifies `capsule.height` and `collider.position.y`. `collider.position.x` and `collider.position.z` are untouched (`0.0`).
   - In `scripts/camera/camera_preferred_shot_solver.gd:68`, camera lateral offset shifts by `peek_amount * 0.38m`.
   - In `scripts/player/operator_posture_layer.gd:88-91`, visual mesh leans over `blend_seconds = 0.18`.
   - In `scripts/combat/socom_bullet_penetration.gd:113-115`, hit detection queries `hit_collider.has_method("apply_damage")`, which hits `Player.CollisionShape3D` directly on `scenes/player/operator_player.tscn`. The collision capsule remains static at `(0, y, 0)` while the mesh leans out.

2. **Mid-Air Physics & Momentum**:
   - In `scripts/player/player_controller.gd:380-402`, while `motion_state == MotionState.AIRBORNE`, horizontal movement velocity is continuously recalculated using ground acceleration (`45.0`), braking (`60.0`), reversal (`90.0`), and instant strafe (`instant_strafe_response: bool = true` at lines 16, 388-391).
   - Releasing movement mid-air drops horizontal velocity to 0 in ~0.10s. Pressing reverse direction mid-air reverses velocity in ~0.14s.

3. **Jump Cooldown & Landing Penalty**:
   - In `scripts/player/player_controller.gd:50, 799-813, 899-908`, `landing_recovery = 0.18` is defined, but `_movement_speed()` (line 584) returns full `move_speed = 6.5 m/s` during `MotionState.LANDING`.
   - In `scripts/player/player_controller.gd:799`, `_try_begin_mobility_action()` allows jumping during `MotionState.LANDING` because `_movement_floor_contact()` is true and `LANDING` is not excluded. There is zero jump cooldown.

4. **Posture Transitions**:
   - In `scripts/player/player_controller.gd:925-935`, `_try_set_posture()` changes `posture` and calls `_apply_posture_collider()` in a single physics tick (0.0s). There is no transition duration or cooldown, enabling 60 Hz crouch-spamming.

5. **Locomotion Ratios & Turn Thresholds**:
   - In `scripts/player/player_controller.gd:438-444`, `_directional_movement_speed()` only checks `move_axis.x`. Backward travel (`move_axis.y > 0`) returns 100% of forward speed (6.5 m/s).
   - In `scripts/player/player_controller.gd:27`, `strafe_burst_multiplier = 1.18` boosts lateral speed to 7.67 m/s for 2 frames.
   - In `scripts/player/player_controller.gd:33`, `torso_turn_in_place_limit_deg = 0.5`, rotating the entire `CharacterBody3D` for any aim error over 0.5°.

6. **Regression Test Suite Results**:
   - `tools/feature_contract_regression.gd`: **PASS** (121 contracts).
   - `tools/public_training_range_regression.gd`: **PASS**.
   - `tools/jump_direction_combo_regression.gd`: **FAIL** with exit code 1:
     `JUMP_DIRECTION_COMBO_REGRESSION FAIL ["Crouched dive starts at actual crouch pelvis 2", "Crouched dive starts at actual crouch pelvis 4", "Crouched dive starts at actual crouch pelvis 8"]`.
   - `tools/crouch_strafe_continuity_probe.gd`: **FAIL** with exit code 1:
     `CROUCH_STRAFE_CONTINUITY FAIL phase_travel=2.821 failures=["direction changes remain within normal gait height variation"]`.
   - `tools/lean_movement_latch_regression.gd`: **PASS**.
   - `tools/source_jump_regression.gd`: **PASS**.
   - `tools/gait_lean_continuity_regression.gd`: **PASS**.
   - `tools/stair_playability_regression.gd`: **PASS**.
   - `tools/jump_forward_legs_regression.gd`: **PASS**.
   - `tools/crouched_fire_blue_line_regression.gd`: **PASS**.

7. **Hurtbox Rig Parity**:
   - `scenes/player/operator_player.tscn:13-19` has only one `CollisionShape3D` capsule.
   - `scripts/network/socom_network_operator.gd:578-592` binds `SocomAnimatedHurtboxRig` with 10+ bone-following `Area3D` capsules, which is absent from `operator_player.tscn`.

---

## 2. Logic Chain

1. **Lean Hitbox Disconnect**:
   - Observation: `player_controller.gd:909` keeps capsule at `(0, y, 0)`; `operator_posture_layer.gd:88` offsets visual bones; `socom_bullet_penetration.gd:113` tests `Player.CollisionShape3D`.
   - Deduction: When a player leans behind cover, the visual mesh extends past cover into line of sight, but the collision capsule remains entirely behind cover. Raycast bullets aimed at the visible head hit the wall or miss the capsule, rendering the player invincible while peeking. Conversely, shooting the empty air where the player was previously standing registers a hit.

2. **Arcade Air Physics vs Tactical SOCOM 2**:
   - Observation: In `player_controller.gd:380`, `horizontal_velocity` in `AIRBORNE` state is calculated identically to grounded movement with 45 m/s² accel, 60 m/s² braking, and 90 m/s² reversal.
   - Deduction: Characters can instantly change direction mid-air or halt mid-flight. In SOCOM 2, jump is a committed tactical leap where launch velocity is conserved ballistically, preventing mid-air steering exploits.

3. **Bunny-Hopping Exploit**:
   - Observation: `player_controller.gd:799` allows jump execution whenever `_movement_floor_contact()` is true without checking `LANDING` or a cooldown timer; `landing_recovery = 0.18` does not reduce velocity.
   - Deduction: Players can chain jump commands continuously upon ground contact at full 6.5 m/s speed, completely subverting tactical pacing.

4. **Regression Failures Confirm Animation Pipeline Issues**:
   - Observation: `jump_direction_combo_regression.gd:350` fails because initial hip position tracks of crouched dive clips differ from crouch idle by >= 0.0001m.
   - Observation: `crouch_strafe_continuity_probe.gd:83` fails because head height variance during crouch direction change reaches 0.0648m (cap is 0.060m).
   - Deduction: Directional transitions in crouch suffer from vertical snapping and head bobbing that require asset re-alignment in `tools/build_jump_direction_dives.gd` and blend curve adjustment in `operator_locomotion_blend_tree.gd`.

---

## 3. Caveats

- **Network Replication**: Detailed network packet sync was evaluated through `socom_network_operator.gd` and regression mocks; real multi-client latency / packet loss scenarios under high jitter were not live-tested.
- **Weapon Ballistics Scope**: Hit-detection evaluation was focused on character collision hulls and hurtbox interaction; weapon cycle timings, bloom expansion, and reload coordination are delegated to the weapons audit specialist.
- **Camera Scope**: Camera lateral offsets and stance interpolation were evaluated as coupled to locomotion; camera obstruction raycasting and pitch/yaw limits are delegated to the camera specialist.

---

## 4. Conclusion

The SOCOM-141 locomotion system possesses solid foundational infrastructure (clean single-owner CharacterBody movement, robust stair probing, and sophisticated procedural IK integration). However, it currently diverges from authentic SOCOM 2 tactical feel and project integration rules in several key areas:
1. **Critical Defect**: Lean peaking is purely cosmetic, creating a game-breaking "ghost-head" invulnerability bug where the physical collision hull does not lean with the operator.
2. **Core Physics**: Mid-air physics lacks momentum conservation, functioning like an arcade shooter with instant air-braking and air-reversal.
3. **Pacing & Exploits**: Missing jump cooldown, missing landing penalty, 0-frame posture snapping, and 1:1 backward run speed permit bunny-hopping, crouch-spamming, and backward sprinting.
4. **Active Regressions**: Two test regressions (`jump_direction_combo_regression.gd` and `crouch_strafe_continuity_probe.gd`) currently fail and require pipeline remediation.

All 12 defects have been documented in detail with verbatim excerpts, reproduction steps, and actionable Translation Cards in `locomotion_audit.md`.

---

## 5. Verification Method

To independently verify these findings:

1. **Run Failing Regressions**:
   ```sh
   /Users/kiwimango/Applications/Godot-4.7.1.app/Contents/MacOS/Godot \
     --headless --path /Users/kiwimango/socom-141-camera-lab \
     --script res://tools/jump_direction_combo_regression.gd
   ```
   *Expected result*: Fails with exit code 1 (`JUMP_DIRECTION_COMBO_REGRESSION FAIL ["Crouched dive starts at actual crouch pelvis 2", ...]`).

   ```sh
   /Users/kiwimango/Applications/Godot-4.7.1.app/Contents/MacOS/Godot \
     --headless --path /Users/kiwimango/socom-141-camera-lab \
     --script res://tools/crouch_strafe_continuity_probe.gd
   ```
   *Expected result*: Fails with exit code 1 (`CROUCH_STRAFE_CONTINUITY FAIL ... ["direction changes remain within normal gait height variation"]`).

2. **Inspect Lean Collision Hull Decoupling**:
   - Inspect `scripts/player/player_controller.gd:909-924` (`_apply_posture_collider()`): verify absence of lateral position or rotation adjustments on `CollisionShape3D`.
   - Inspect `scenes/player/operator_player.tscn:16-18`: verify that only a single vertical capsule exists on the canonical player without child hurtboxes.

3. **Inspect Air Momentum Execution**:
   - Inspect `scripts/player/player_controller.gd:380-417`: verify that `AIRBORNE` state applies standard ground acceleration, braking, and reversal formulas without momentum conservation or velocity latching.

4. **Verify Passing Gates**:
   ```sh
   /Users/kiwimango/Applications/Godot-4.7.1.app/Contents/MacOS/Godot \
     --headless --path /Users/kiwimango/socom-141-camera-lab \
     --script res://tools/feature_contract_regression.gd
   ```
   *Expected result*: PASS (121 contracts).
