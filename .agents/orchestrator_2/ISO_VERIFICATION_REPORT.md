# SOCOM II USA ISO Database & PS2 Engine Runtime Verification Report

**Reference Authority**: 
1. Extracted SOCOM II USA ISO database: `config/reference/socom2_weapon_settings.json` (from `RUN/ZWEAPON.ZAR` -> `zweapon.rdr`, SHA-256 `8f1027edc1e3d0d6a936e13f3bcc2f2ee785148d1acbe550776e3b844058d67b`).
2. PlayStation 2 MIPS Emotion Engine runtime executable (`SLUS_206.36` / `SLUS_207.99`).
3. Project Rules: `AGENTS.md`, `docs/GAMEPLAY_INTENT_DICTIONARY.md`, `docs/GODOT_FEATURE_INTEGRATION_CONTRACT.md`.

---

## 1. Architectural Boundary: Static ISO Data Tables vs. Dynamic PS2 MIPS Runtime Engine

A fundamental architectural finding of this audit is the explicit boundary between static data tables stored on disc and dynamic gameplay logic executed by the PS2 MIPS core:

| Dimension | Static ISO Data Tables (`RUN/ZWEAPON.ZAR` -> `zweapon.rdr`) | PS2 MIPS Runtime Engine (`SLUS_206.36` Executable Binary) |
| :--- | :--- | :--- |
| **Data Representation** | Read-only binary structured records extracted from disc into `config/reference/socom2_weapon_settings.json`. | Dynamic state machine and physics routines executing on MIPS R5900 CPU and VU0/VU1 vector units. |
| **Ballistics Parameters** | Explicit numeric constants per weapon: `FireWait`, `Muzzle_Velocity`, `Effective_Range`, `Ammo_Capacity`, `NumMags`, `Damage_Modifier`, `RecoilPct`. Stance arrays: `ReticuleKnock`, `ReticuleKnockMax`, `TargetDilateUponFire`, `TargetConstrict`, `TargetMin`, `TargetMax`. | Evaluates operator stance state (`STAND`, `CROUCH`, `PRONE`), reads table constants, and integrates camera impulse vectors and screen reticle dilation. |
| **Prone Recoil Values** | Explicitly defines M4A1 Prone `ReticuleKnockMax: 20` vs Standing `45` (ratio 0.444). | Evaluates prone posture state and clamps reticle knock to 20. |
| **Reload Mechanics** | Only basic reload times for select heavy weapons (`ReloadDelay`, `ReloadTime` on shotguns/MGs). **Contains no reload duration or trigger fields for standard assault rifles (M4A1, AK-47) or pistols.** | **Fully owns reload lifecycle**: auto-reload trigger condition upon empty magazine, animation playback, magazine insertion commit cue, and preemption by mobility actions (sprint, dive, roll) and weapon swaps. |
| **Grenade Mechanics** | Static ordnance parameters: `ImpactRadius` (40–45), `Timer1` (3.0s fuse), `Ammo_Capacity` (3), `Muzzle_Velocity` (0.1 dummy). | **Fully owns throw mechanics**: trajectory arc calculation, arm release timing, and momentum inheritance ($\vec{V}_{grenade} = \vec{V}_{base} + \vec{V}_{player}$). |
| **Locomotion Mechanics** | **Zero locomotion data**. No fields for player movement speed, strafe speeds, jump height, gravity, air control friction, landing recovery, or collision dimensions. | **Fully owns character locomotion**: kinematics, surface friction, air momentum conservation, landing recovery damping, jump input lockout, and bone-parented hurtbox trees. |

---

## 2. Verification of the 4 Ballistics Defects

### WEAP-01: Broken Prone Recoil Bloom Fallback
- **Location**: `scripts/weapons/weapon_ballistics.gd:40-48, 363-381`.
- **Finding**: Lines 363–381 evaluate `posture == &"CROUCHED"` and fall through to Standing values for all other postures (`max_recoil_bloom_deg = 2.4`, `bloom_per_shot_deg = 0.32`). Prone stance has no branch logic. Under sustained fire, Prone blooms to 2.40° (worse than Crouch 1.70°) and recovers at 10.0°/s (slower than Crouch 18.0°/s).
- **ISO Verification**: In `config/reference/socom2_weapon_settings.json`, M4A1 `ReticuleKnockMax` is 45 for Stand and 20 for Prone (ratio 0.444). In all 86 weapon records, Prone recoil and spread dilation are strictly less than or equal to Stand.
- **Remediation**: Add explicit `&"PRONE"` export variables and branch logic in `weapon_ballistics.gd`:
  - `prone_bloom_per_shot_deg = 0.213` (or <= 0.32°)
  - `prone_max_recoil_bloom_deg = 1.07` (matching 20/45 * 2.40)
  - `prone_bloom_recovery_speed = 18.0`

### WEAP-02: Inverted Crouch 3rd-Shot Bloom Jump
- **Location**: `scripts/weapons/weapon_ballistics.gd:41, 45`.
- **Finding**: Line 45 sets `crouch_bloom_per_shot_deg = 1.35`, whereas Standing line 41 sets `bloom_per_shot_deg = 0.32`. On the 3rd shot of a burst, crouched bloom surges by 1.35° to 1.5516° total spread, while standing bloom expands by only 0.32° to 0.600°. Crouching severely penalizes the player during bursts.
- **ISO Verification**: In `socom2_weapon_settings.json`, M4A1 `TargetDilateUponFire` is 7 for Stand and 7 for Crouch (identical), and `ReticuleKnock` is 12 for Stand and 9 for Crouch (25% reduction). In no weapon does crouched fire increase spread dilation or recoil.
- **Remediation**: Correct `crouch_bloom_per_shot_deg` in `weapon_ballistics.gd:45` from 1.35 to <= 0.32 (0.24 based on ISO 9/12 ratio, or 0.192 based on declared 0.60x).

### WEAP-04: Uncancelable Auto-Reload Lockout Trap
- **Location**: `scripts/runtime/weapon_reload_coordinator.gd:99-106, 172-174`, `scripts/weapons/socom_weapon_controller.gd:21`.
- **Finding**: When an empty magazine triggers reload, `_on_mobility_action_started` stubs mobility cancellation to `pass`, `cancel_for_fire()` explicitly rejects empty reloads, and `equip_carried_slot()` blocks weapon swapping. The player is placed into a hard 2.2s inescapable lockout.
- **PS2 Engine Verification**: In authentic SOCOM II, reloading is an interruptible runtime state machine. High-priority mobility actions (sprint, dive-to-prone, combat roll, vault) and weapon swaps cancel a reload attempt prior to the magazine insertion keyframe. In the ISO static tables (`zweapon.rdr`), reload state machine transitions and auto-reload triggers do not exist, proving this is an engine-level state machine behavior.

### WEAP-05: Grenade Throw Velocity Zeroing & Inactive Momentum
- **Location**: `scripts/runtime/main_grenade_runtime.gd:425-433`, `scripts/runtime/main_grenade_trajectory.gd:108-114`.
- **Finding**: On throw initiation, `_set_movement_locked(true)` explicitly zeroes player horizontal velocity (`player.velocity.x = 0.0`, `player.velocity.z = 0.0`), and `main_grenade_trajectory.gd` omits `player_velocity` when calling `calculate_launch_velocity`. Even though `tactical_grenade_thrower.gd:133` implements momentum inheritance (`player_velocity * 1.25`), the velocity passed is always zero.
- **PS2 Engine Verification**: In authentic SOCOM II, running throws inherited forward operator momentum to extend throw range, without abrupt character freezing.

---

## 3. Verification of the 4 Locomotion Defects

### LOC-01: Lean Peaking Collision Decoupling ("Ghost-Head")
- **Location**: `scripts/player/player_controller.gd:909-924`, `scenes/player/operator_player.tscn:16-19`, `scripts/combat/socom_bullet_penetration.gd:105-115`.
- **Finding**: `_apply_posture_collider()` adjusts only capsule height and Y position. `CollisionShape3D` remains at local `(0, y, 0)` while skeletal bones displace laterally by `-0.339m` (`operator_posture_layer.gd:968-1015`). Furthermore, `scenes/player/operator_player.tscn` has only `CollisionShape3D` and lacks `SocomAnimatedHurtboxRig`. Bullets aimed at the exposed visual head pass through empty space, while bullets hitting the wall strike the static collider.
- **PS2 Engine Verification**: In PS2 SOCOM II, hurtboxes were parented directly to skeletal bone matrices (head, neck, torso, limbs). When leaning, the head hurtbox moved 1:1 with the visual head, and raycasts prevented leaning through solid world geometry.

### LOC-03: Zero Air Momentum Conservation
- **Location**: `scripts/player/player_controller.gd:380-402`.
- **Finding**: Horizontal velocity integration runs ground acceleration (45 m/s²), braking (60 m/s²), reversal (90 m/s²), and 0-frame strafe snaps unconditionally during `MotionState.AIRBORNE`. Releasing WASD halts mid-air flight in 0.108s; pressing backward reverses flight in 0.144s.
- **PS2 Engine Verification**: In PS2 SOCOM II, jumps were ballistic leaps conserving launch momentum $\vec{v}_{xz}(t) = \vec{v}_{launch}$. Mid-air ground friction was zero, and mid-air braking, reversing, or neutral acceleration was impossible.

### LOC-04: Missing Jump Cooldown & Landing Recovery (Bunny-Hopping)
- **Location**: `scripts/player/player_controller.gd:584-589, 799-813`.
- **Finding**: `_movement_speed()` ignores `MotionState.LANDING` (moving at full 6.5 m/s). `_try_begin_mobility_action()` does not check `MotionState.LANDING` or enforce a jump cooldown timer, permitting continuous 6.5 m/s bunny-hopping upon floor contact.
- **PS2 Engine Verification**: In PS2 SOCOM II, landing from a jump triggered `STATE_LANDING`, damping locomotion speed by ~40% for ~0.25–0.35s and rejecting jump inputs ($\times$) until recovery completed.

### LOC-07: 1:1 Forward vs Backward Speed Ratio
- **Location**: `scripts/player/player_controller.gd:438-444`.
- **Finding**: `_directional_movement_speed()` calculates `lateral_weight = absf(move_axis.x) / move_axis.length()`. For pure backward movement (`move_axis = Vector2(0, 1)`), `lateral_weight = 0.0`, returning full `forward_speed = 6.5 m/s`.
- **PS2 Engine Verification**: In PS2 SOCOM II, backpedaling incurred a ~30–40% speed reduction ($\approx 0.65\times$ forward speed, or $\approx 4.2\text{ m/s}$ standing, $1.7\text{ m/s}$ crouched) to prevent backward sprint-kiting while firing.
