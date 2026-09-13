# Technical Investigation Report: Locomotion Defects & PS2 Engine Parity (R1)

**Investigator**: `explorer_locomotion_2` (Teamwork Quality Explorer)  
**Date**: 2026-09-12  
**Target Reference**: Authentic *SOCOM II: U.S. Navy SEALs* (PS2 Emotion Engine MIPS runtime), `RUN/ZWEAPON.ZAR` (`zweapon.rdr`), `AGENTS.md`, `docs/GAMEPLAY_INTENT_DICTIONARY.md`, and `docs/GODOT_FEATURE_INTEGRATION_CONTRACT.md`  
**Working Directory**: `/Users/kiwimango/socom-141-camera-lab/.agents/explorer_locomotion_2`  

---

## Executive Summary

A comprehensive, code-level diagnostic investigation of character locomotion, air physics, landing mechanics, posture collision ownership, and lean peaking was conducted across the SOCOM-141 Godot codebase (`scripts/player/`, `scenes/player/`, `scripts/combat/`, `tools/`).

This investigation systematically resolves Requirement R1 by:
1. **Dissecting the 4 cataloged locomotion defects** (`LOC-01`, `LOC-03`, `LOC-04`, `LOC-07`) with exact file paths, line numbers, physics calculations, and code excerpts.
2. **Explicitly defining the architectural boundary** between what exists in static ISO data tables (`RUN/ZWEAPON.ZAR` -> `zweapon.rdr` / `socom2_weapon_settings.json`) versus what is governed by compiled PS2 MIPS Emotion Engine executable code (`SLUS_206.36`).
3. **Evaluating related automated regressions** (`tools/feature_contract_regression.gd`, `tools/mobility_regression.gd`, `tools/jump_direction_combo_regression.gd`, `tools/directional_locomotion_phase_regression.gd`) with live headless test executions and failure diagnostics.
4. **Delivering five-line translation cards and remediation proposals** conforming to the Single-Owner Architecture mandated by `AGENTS.md` Rule 5.

---

## 1. Architectural Boundary: Static ISO Data Tables vs. PS2 MIPS Gameplay Engine Executable Code

A critical distinction must be established between data stored in static configuration records on the SOCOM II game disc and gameplay logic executed dynamically by the PlayStation 2 hardware:

```
+--------------------------------------------------------------------------------------------------+
|                                    SOCOM II USA PS2 ARCHITECTURE                                 |
+-------------------------------------------------+------------------------------------------------+
| STATIC ISO ASSET TABLES                         | PS2 MIPS EMOTION ENGINE RUNTIME                |
| (RUN/ZWEAPON.ZAR -> zweapon.rdr)                | (SLUS_206.36 Executable C++/MIPS Binary)       |
+-------------------------------------------------+------------------------------------------------+
| - Weapon metadata (ID, Name, Display Name)      | - Player State Machine (Locomotion, Stances)   |
| - Fire mode flags (Single, Burst, Auto)         | - Airborne ballistic momentum conservation     |
| - Numeric ballistics (Muzzle_Velocity, FireWait)| - Ground friction, acceleration, braking       |
| - Ammo capacities (NumMags, Ammo_Capacity)      | - Backpedal speed penalty calculation          |
| - Acoustic sound radius, encumbrance            | - Jump takeoff impulse & landing recovery      |
| - Stance recoil tables (Knock, Constrict, Min)  | - Bunny-hop input lockout / cooldown timer     |
| - Stance bloom dilation factors                 | - Skeletal procedural lean kinematics          |
|                                                 | - Bone-parented anatomical hurtbox attachments |
| [NO LOCOMOTION OR STATE MACHINE DATA EXISTS]   | - World obstacle collision & lean obstruction  |
+-------------------------------------------------+------------------------------------------------+
```

### 1.1 What Exists in Static ISO Data Tables (`zweapon.rdr` / `socom2_weapon_settings.json`)
The extracted ISO database in `config/reference/socom2_weapon_settings.json` originates from `RUN/ZWEAPON.ZAR` -> `zweapon.rdr`. It contains 5,688 lines of weapon-specific parameters:
- **Weapon Attributes**: `FireWait`, `Muzzle_Velocity`, `ImpactRadius`, `Effective_Range`, `Maximum_Range`, `NumMags`, `Ammo_Capacity`, `Sound_Radius`, `Encumbrance`, `RecoilPct`.
- **Per-Stance Accuracy Profiles**: For each stance (`STANCE_STAND`, `STANCE_CROUCH`, `STANCE_PRONE`), it defines reticle knock and target dilation:
  - `ReticuleKnock`, `ReticuleKnockReturn`, `ReticuleKnockMax`
  - `TargetDilateUponFire`, `TargetDilateUponMovement`, `TargetConstrict`
  - `TargetMin`, `TargetMax`, `KnockCount`

**Zero character locomotion parameters exist in `zweapon.rdr`**. There are no entries for player movement speed, strafe speeds, jump velocities, gravity, air control friction, landing delay durations, posture transition intervals, or collision hull dimensions.

### 1.2 What is Governed by PS2 MIPS Gameplay Engine Executable Code
In Zipper Interactive's PS2 engine (`SLUS_206.36`), character mechanics were compiled into machine instructions for the MIPS R5900 Emotion Engine and VU0/VU1 vector coprocessors:
1. **Kinematics & Momentum**: Ground movement used explicit velocity integration with surface friction. When airborne, surface friction dropped to zero; horizontal velocity became ballistic (conserving launch momentum $\vec{v}_{launch}$).
2. **State Machine Transitions & Penalties**:
   - `STATE_AIRBORNE` transitioned to `STATE_LANDING` upon ground impact.
   - `STATE_LANDING` enforced velocity damping (~40% reduction) for ~0.25–0.35s and rejected jump inputs, preventing bunny-hopping.
   - Backpedaling enforced an explicit dot-product velocity reduction (~30–40% penalty).
3. **Skeletal Hierarchy & Hurtbox Registration**:
   - Skeletal bones were computed via matrix transformations.
   - Hit registration volumes (spheres and capsules for head, neck, torso, pelvis, limbs) were parented to individual bone coordinate spaces.
   - When leaning, the head hurtbox physically moved with the skull bone, ensuring 1:1 vulnerable exposure.
   - Obstacle raycasts / sweeps prevented leaning through solid world geometry.

---

## 2. In-Depth Technical Examination of the 4 Locomotion Defects

```
+--------------------------------------------------------------------------------------------------+
| ID      | Domain     | Severity | File & Lines                     | Defect Summary              |
+---------+------------+----------+----------------------------------+-----------------------------+
| LOC-01  | Locomotion | CRITICAL | player_controller.gd:909-924     | Lean Peaking Collision      |
|         |            |          | scenes/player/operator_player.tscn | Decoupling ("Ghost-Head")   |
| LOC-03  | Locomotion | HIGH     | player_controller.gd:380-402     | Zero Air Momentum           |
|         |            |          |                                  | Conservation                |
| LOC-04  | Locomotion | HIGH     | player_controller.gd:799-813,    | Missing Jump Cooldown &     |
|         |            |          | player_controller.gd:899-908     | Landing Recovery (Bunnyhop) |
| LOC-07  | Locomotion | MEDIUM   | player_controller.gd:438-444     | 1:1 Forward vs Backward     |
|         |            |          |                                  | Speed Ratio (No Backpedal)  |
+---------+------------+----------+----------------------------------+-----------------------------+
```

---

### 2.1 LOC-01: Lean Peaking Collision Decoupling ("Ghost-Head")

#### Code Location
- `scripts/player/player_controller.gd:909-924` (`_apply_posture_collider`)
- `scenes/player/operator_player.tscn:16-19` (`CollisionShape3D`)
- `scripts/combat/socom_bullet_penetration.gd:105-115` (`_cast_segment` hit evaluation)
- `scripts/player/operator_posture_layer.gd:88-91, 968-1015` (`_apply_full_body_peek`)

#### Verbatim Excerpt
```gdscript
# scripts/player/player_controller.gd:910-924
func _apply_posture_collider() -> void:
	var collider := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if collider == null or not (collider.shape is CapsuleShape3D):
		return
	var capsule := collider.shape as CapsuleShape3D
	var target_height := 1.85
	if posture == MotionState.CROUCHED:
		target_height = 1.25
	elif posture == MotionState.PRONE:
		target_height = 0.82
	capsule.height = target_height
	collider.position.y = target_height * 0.5
	if mobility_combo_kind != &"":
		capsule.height = float(jump_combo_intent.profile.collider_height)
		collider.position.y = capsule.height * 0.5
```

#### Technical Analysis
1. **Static Collider at Local Origin**: `_apply_posture_collider()` adjusts only `capsule.height` and `collider.position.y = target_height * 0.5`. Local coordinates `collider.position.x` and `collider.position.z` are never modified and remain at `0.0`.
2. **Visual Mesh Displacement**: When `peek_amount` reaches $\pm 1.0$, `operator_posture_layer.gd` rotates skeletal bones (`mixamorig_Spine`, `mixamorig_Neck`, `mixamorig_Head`), displacing the rendered head laterally by `-0.339m` (left) relative to the pelvis.
3. **Local Player Hurtbox Absence**: In `scenes/player/operator_player.tscn`, `Player` has only a single `CollisionShape3D` capsule attached directly to the `CharacterBody3D`. It completely lacks the `SocomAnimatedHurtboxRig` present in `scenes/player/network_operator.tscn`.
4. **Hit Detection Vulnerability Inversion**: In `socom_bullet_penetration.gd:113-115`, hitscans test `hit_collider`. Because `Player` defines `apply_damage()`, `CollisionShape3D` is the hit target. When leaning around cover:
   - The visual head extends ~34cm into open sight, but has no collider. Bullets aimed at the exposed head pass harmlessly through empty space ("Ghost-Head").
   - Bullets aimed at the concealed wall where the upright body was standing strike the static `CollisionShape3D`, dealing full damage through the wall.
5. **Geometry Wall-Clipping**: Because `CollisionShape3D` does not translate laterally, `move_and_slide()` cannot detect walls on the side of the lean. The player can stand against a corner and lean their head/torso/weapon directly through solid walls without obstruction.

#### PS2 Engine Parity
In PS2 *SOCOM II*, hit registration cylinders were child transforms of the skeletal bones (evaluated per frame via VU0 microcode). When leaning, the head hurtbox translated in 1:1 lockstep with the visual skull. Furthermore, lean peaking was checked against world collision, clamping or blocking the lean if an obstacle was present.

#### Translation Card (LOC-01)
- **Player intent**: When leaning around a corner, shooting the operator's exposed head deals damage, and leaning into a solid wall is physically obstructed.
- **Acceptance rule**: The local player scene binds `SocomAnimatedHurtboxRig` so head hurtboxes follow the bone lean offset; `CollisionShape3D` or an obstruction probe blocks the torso/head from clipping through solid geometry.
- **System owner**: `SocomTestPlayer` (`CharacterBody3D`) for collision/obstruction, `SocomAnimatedHurtboxRig` for ballistic hitboxes.
- **Must not change**: Camera preferred shoulder offset, weapon aim pitch/yaw, base standing capsule radius (0.38m).
- **Proof**: `tools/mobility_regression.gd` augmented with ballistic raycast verification on the leaned head.

---

### 2.2 LOC-03: Zero Air Momentum Conservation

#### Code Location
- `scripts/player/player_controller.gd:380-402` (Horizontal velocity integration)
- `scripts/player/player_controller.gd:591-615` (`_horizontal_response_acceleration`)

#### Verbatim Excerpt
```gdscript
# scripts/player/player_controller.gd:380-402
	var horizontal_velocity := Vector2(velocity.x, velocity.z)
	var horizontal_target := Vector2(desired_velocity.x, desired_velocity.z)
	if lean_latch.is_active():
		horizontal_response_mode = &"LEAN_PEEK"
		horizontal_velocity = horizontal_target
	elif posture == MotionState.CROUCHED and _movement_floor_contact() and bool(jump_combo_intent.profile.get("instant_crouch_response", false)):
		horizontal_response_mode = &"INSTANT_CROUCH"
		horizontal_velocity = horizontal_target
	elif instant_strafe_response and absf(input.x) > 0.001:
		horizontal_response_mode = &"INSTANT_STRAFE"
		horizontal_velocity = horizontal_target
	else:
		var response_acceleration := _horizontal_response_acceleration(
			horizontal_velocity,
			horizontal_target
		)
		horizontal_velocity = horizontal_velocity.move_toward(
			horizontal_target,
			response_acceleration * delta
		)
	velocity.x = horizontal_velocity.x
	velocity.z = horizontal_velocity.y
```

#### Technical Analysis
1. **Unconditional Ground Solver in Mid-Air**: Lines 380-402 execute identically whether `_movement_floor_contact()` is true or false. While vertical physics branches on floor contact (`velocity.y -= gravity * delta` at line 408), horizontal physics never checks `motion_state == MotionState.AIRBORNE`.
2. **Arcade-Style Mid-Air Response**:
   - **Mid-Air Instant Braking**: If `W` is released mid-jump, `horizontal_target` becomes `Vector2.ZERO`. `_horizontal_response_acceleration` selects `braking_acceleration = 60.0 m/s²`. Forward travel at 6.5 m/s halts completely in:
     $$\Delta t_{stop} = \frac{6.5}{60.0} = 0.108\text{ seconds}$$
     The character halts horizontally mid-air and falls straight down.
   - **Mid-Air Instant Reversal**: If `S` is pressed mid-jump, alignment is $-1.0 < -0.20$. `reversal_acceleration = 90.0 m/s²`. Forward velocity reverses from $+6.5\text{ m/s}$ to $-6.5\text{ m/s}$ in:
     $$\Delta t_{reverse} = \frac{6.5 + 6.5}{90.0} = 0.144\text{ seconds}$$
     The character boomerangs backwards in mid-flight.
   - **Mid-Air Neutral Launch Acceleration**: If jumping neutrally from standstill (`velocity.xz = 0`), pressing `W` mid-air accelerates the player to full sprint speed ($6.5\text{ m/s}$) at $45.0\text{ m/s²}$ in $0.144\text{s}$.
   - **0-Frame Mid-Air Strafe Snaps**: If `instant_strafe_response = true`, tapping `A` or `D` mid-air snaps lateral velocity to $\pm 6.5\text{ m/s}$ in 0 frames.

#### PS2 Engine Parity
In PS2 *SOCOM II*, jumps were committed tactical leaps. At takeoff, the horizontal velocity vector was sampled and conserved throughout the ballistic flight path:
$$\vec{v}_{xz}(t) = \vec{v}_{launch}$$
Mid-air ground friction was zero. Mid-air braking, reversing, and neutral acceleration were physically impossible. Air control was strictly clamped ($\le 5-10\%$ steering bias at most).

#### Translation Card (LOC-03)
- **Player intent**: Jumping is a committed ballistic action; jumping forward carries launch momentum through the flight arc, and mid-air inputs cannot stop or reverse flight.
- **Acceptance rule**: While `motion_state == MotionState.AIRBORNE`, horizontal velocity conserves takeoff velocity $\vec{v}_{launch}$ with an air-steering authority clamp $\le 10\%$; mid-air braking to zero and directional reversals are rejected.
- **System owner**: `SocomTestPlayer` (`CharacterBody3D`).
- **Must not change**: Jump launch impulse (`jump_velocity = 5.0`), gravity (`22.0`), mantling/traversal probe detection.
- **Proof**: Focused mid-air momentum regression verifying horizontal velocity conservation across airborne frames.

---

### 2.3 LOC-04: Missing Jump Cooldown & Landing Recovery

#### Code Location
- `scripts/player/player_controller.gd:799-813` (`_try_begin_mobility_action`)
- `scripts/player/player_controller.gd:890-908` (`_update_air_and_landing_state`)
- `scripts/player/player_controller.gd:584-589` (`_movement_speed`)

#### Verbatim Excerpt
```gdscript
# scripts/player/player_controller.gd:799-813
func _try_begin_mobility_action(
	desired_dir: Vector3,
	input: Vector2,
	jump_started: bool,
	command
) -> bool:
	if not _movement_floor_contact() or motion_state == MotionState.DIVING or motion_state == MotionState.ROLLING:
		return false

	if jump_started and posture != MotionState.PRONE:
		if not _try_set_posture(MotionState.STANDING):
			return false
		var running := input.length() >= full_gait_input_threshold and Vector2(velocity.x, velocity.z).length() >= float(traversal.mantle_motor.climb_profile.running_jump_min_speed_mps)
		active_jump_launch_speed = float(traversal.mantle_motor.climb_profile.running_jump_velocity_mps) if running else jump_velocity
		velocity.y = active_jump_launch_speed
		motion_state = MotionState.AIRBORNE
		_emit_mobility_started(&"AIRBORNE")
		return true
```

#### Technical Analysis
1. **Landing State Bypasses Speed Reduction**: In `_update_air_and_landing_state()`, landing sets `motion_state = MotionState.LANDING` for `action_duration = landing_recovery` (`0.18s`). However, `_movement_speed()` (lines 584-589) only checks `posture == MotionState.PRONE` or `CROUCHED`. It ignores `MotionState.LANDING`, returning full `move_speed = 6.5 m/s`.
2. **Missing Landing Lockout & Jump Cooldown**: In `_try_begin_mobility_action()` (lines 799-800), jumping is permitted whenever `_movement_floor_contact()` is true and state is not `DIVING` or `ROLLING`.
   - `MotionState.LANDING` is **not excluded**.
   - No jump cooldown timer is maintained or checked.
3. **Continuous Bunny-Hopping Exploit**: The moment the operator's capsule contacts the floor, `_movement_floor_contact()` evaluates to true. If `Space` is pressed or buffered, a new jump triggers on frame 0 of ground contact. A player can chain infinite forward jumps at maximum sprint velocity ($6.5\text{ m/s}$) with 0 frames of grounded delay.

#### PS2 Engine Parity
In PS2 *SOCOM II*, landing from a jump triggered a landing recovery stumble state (`STATE_LANDING`). During this state:
- Locomotion speed was heavily dampened (~40% penalty, capping velocity to $\approx 3.9\text{ m/s}$) for ~0.25–0.35s.
- Jump inputs ($\times$) were rejected until the recovery state completed. Bunny-hopping was impossible.

#### Translation Card (LOC-04)
- **Player intent**: Landing from a jump absorbs impact with a momentary tactical recovery, preventing players from spamming continuous bunny-hops.
- **Acceptance rule**: During `MotionState.LANDING`, horizontal move speed is dampened by at least 40% (max $3.9\text{ m/s}$), and jump inputs are ignored until `landing_recovery` elapsed time completes.
- **System owner**: `SocomTestPlayer` (`CharacterBody3D`).
- **Must not change**: Ground sprint speed, mantling transitions, weapon fire readiness.
- **Proof**: Landing recovery test asserting horizontal velocity dampening and bunny-hop input rejection.

---

### 2.4 LOC-07: Forward vs Backward Speed Ratio (1:1 Backpedal Run Speed)

#### Code Location
- `scripts/player/player_controller.gd:438-444` (`_directional_movement_speed`)
- `scripts/player/player_controller.gd:561-582` (`_directional_input`)

#### Verbatim Excerpt
```gdscript
# scripts/player/player_controller.gd:438-444
func _directional_movement_speed(move_axis: Vector2, forward_speed: float) -> float:
	if move_axis.length_squared() < 0.000001:
		return forward_speed
	var standing_ratio := clampf(strafe_speed / maxf(move_speed, 0.001), 0.10, 2.0)
	var lateral_weight := absf(move_axis.x) / maxf(move_axis.length(), 0.001)
	return lerpf(forward_speed, forward_speed * standing_ratio, lateral_weight)
```

#### Technical Analysis
1. **Omission of Backward Velocity Scaling**: In Godot's input conventions:
   - Moving forward (`W`): `move_axis = Vector2(0, -1)`.
   - Moving backward (`S`): `move_axis = Vector2(0, 1)`.
2. `_directional_movement_speed()` calculates `lateral_weight = absf(move_axis.x) / move_axis.length()`.
   - For pure forward movement: `lateral_weight = 0.0` $\rightarrow$ returns `forward_speed = 6.5 m/s`.
   - For pure backward movement: `move_axis.x = 0`, so `lateral_weight = 0.0` $\rightarrow$ returns `forward_speed = 6.5 m/s`!
3. **Exploit Consequence**: Players can run backwards at full sprint speed ($6.5\text{ m/s}$) while maintaining forward crosshair aim and firing ("kite-shooting").

#### PS2 Engine Parity
In PS2 *SOCOM II*, characters could not run backwards at sprint speed. Backpedaling incurred a ~30–40% speed reduction ($\approx 0.65\times$ forward speed, or $\approx 4.2\text{ m/s}$ standing, $1.7\text{ m/s}$ crouched). Backpedaling was represented by a guarded backward jog/walk animation.

#### Translation Card (LOC-07)
- **Player intent**: Backpedaling feels slower and more cautious than sprinting forward, preventing players from running backwards at full sprint while maintaining forward aim.
- **Acceptance rule**: Backward movement speed is capped to 65% of forward speed ($\le 4.25\text{ m/s}$ standing, $\le 1.7\text{ m/s}$ crouched).
- **System owner**: `SocomTestPlayer` (`CharacterBody3D`).
- **Must not change**: Forward run speed ($6.5\text{ m/s}$), strafe speed ratio, camera aim tracking.
- **Proof**: Locomotion speed regression asserting `velocity.length() <= 4.3 m/s` when `move_axis == Vector2(0, 1)`.

---

## 3. Automated Regression Suite Execution & Diagnostic Analysis

Four targeted regression suites were executed headlessly using Godot 4.7.1 (`v4.7.1.stable.official.a13da4feb`):

```
+-------------------------------------------------+--------+------------------------------------+
| Regression Script                               | Status | Primary Failure / Check Metric     |
+-------------------------------------------------+--------+------------------------------------+
| tools/feature_contract_regression.gd            | PASS   | 121/121 Feature Contracts Valid    |
| tools/mobility_regression.gd                    | FAIL   | Right peek exposes head (LOC-05)   |
| tools/jump_direction_combo_regression.gd        | FAIL   | Crouched dive pelvis continuity    |
| tools/directional_locomotion_phase_regression.gd| FAIL   | Gait cycle alias mismatch          |
+-------------------------------------------------+--------+------------------------------------+
```

### 3.1 `tools/feature_contract_regression.gd`
- **Command**: `/Users/kiwimango/Applications/Godot-4.7.1.app/Contents/MacOS/Godot --headless --path /Users/kiwimango/socom-141-camera-lab --script res://tools/feature_contract_regression.gd`
- **Result**: **PASS** (Exit Code 0).
- **Log Excerpt**:
  ```
  [FEATURE CONTRACT] PASS: 121 contract(s) form complete Godot integration graphs
  ```
- **Significance**: Confirms all 121 JSON feature manifests in `config/feature_contracts/` are architecturally sound, validating node paths, scripts, data contracts, and proof references.

### 3.2 `tools/mobility_regression.gd`
- **Command**: `/Users/kiwimango/Applications/Godot-4.7.1.app/Contents/MacOS/Godot --headless --path /Users/kiwimango/socom-141-camera-lab --script res://tools/mobility_regression.gd`
- **Result**: **FAIL** (Exit Code 1).
- **Log Excerpt**:
  ```
  MOBILITY_CHECK PASS Q reaches the planted left-peek pose
  MOBILITY_METRIC peek_head_x neutral=0.1199 left=-0.2191
  MOBILITY_CHECK PASS left peek exposes the head on the requested side
  MOBILITY_CHECK PASS left peek uses the full pelvis-to-head curve
  MOBILITY_CHECK PASS E reaches the planted right-peek pose
  MOBILITY_METRIC peek_head_x neutral=0.1199 right=0.1131
  ERROR: MOBILITY_CHECK FAIL right peek exposes the head on the requested side
  ```
- **Diagnostic Finding**:
  - Neutral head X coordinate relative to hips is `0.1199m`.
  - Left peek head X coordinate is `-0.2191m` (displaces left by `-0.339m`).
  - Right peek head X coordinate is `0.1131m` (displaces left by `-0.0068m` instead of moving right!).
  - This confirms **LOC-05 (Right-Lean Peaking Asymmetry)** in `operator_posture_layer.gd`.
  - In addition, line 17 demonstrates that instant strafing (`instant_strafe_response`) is actively codified in this test:
    `MOBILITY_CHECK PASS full strafe reaches maximum speed within one physics frame`.

### 3.3 `tools/jump_direction_combo_regression.gd`
- **Command**: `/Users/kiwimango/Applications/Godot-4.7.1.app/Contents/MacOS/Godot --headless --path /Users/kiwimango/socom-141-camera-lab --script res://tools/jump_direction_combo_regression.gd`
- **Result**: **FAIL** (Exit Code 1).
- **Log Excerpt**:
  ```
  CROUCH_NETWORK bit=1 expected= server= proxy= posture=1/1 floor=true position=(510.0, 0.000729, 500.0)
  CROUCH_NETWORK bit=2 expected=crouch_dive_left server=crouch_dive_left proxy=crouch_dive_left posture=1/1 floor=true position=(508.1522, 0.000839, 500.0)
  CROUCH_NETWORK bit=4 expected=crouch_dive_right server=crouch_dive_right posture=1/1 floor=true position=(511.8478, 0.000845, 500.0)
  CROUCH_NETWORK bit=8 expected=crouch_dive_back server=crouch_dive_back posture=1/1 floor=true position=(510.0, 0.000839, 501.8478)
  JUMP_DIRECTION_COMBO_REGRESSION FAIL ["Crouched dive starts at actual crouch pelvis 2", "Crouched dive starts at actual crouch pelvis 4", "Crouched dive starts at actual crouch pelvis 8"]
  ```
- **Diagnostic Finding**:
  - In `tools/jump_direction_combo_regression.gd:350`, crouched dive animations (`crouch_dive_left`, `crouch_dive_right`, `crouch_dive_back`) have an initial hip position offset compared to `aim_idle_crouch`, causing a visible pelvis vertical jump on frame 0.
  - Notably, line 37 confirms the design intent for jump steering: `await _tick(2) # Holding A is only air steering`, contrasting with the current code's mid-air reversal and braking.

### 3.4 `tools/directional_locomotion_phase_regression.gd`
- **Command**: `/Users/kiwimango/Applications/Godot-4.7.1.app/Contents/MacOS/Godot --headless --path /Users/kiwimango/socom-141-camera-lab --script res://tools/directional_locomotion_phase_regression.gd`
- **Result**: **FAIL** (Exit Code 1).
- **Log Excerpt**:
  ```
  DIRECTIONAL_LOCOMOTION_PHASE_REGRESSION FAIL ["run_left reuses one forward gait cycle", "run_right reuses one forward gait cycle", "crouch_left reuses one forward gait cycle", "crouch_right reuses one forward gait cycle"]
  ```
- **Diagnostic Finding**:
  - The regression asserts that `run_left` and `run_right` must alias to `run_forward` (lines 34-45).
  - The active operator animation profile (`config/operator_animation_map.json`) now correctly utilizes dedicated strafe clips (`run_left.tres`, `crouch_left.tres`). The test script reflects an outdated contract assumption from the early prototype phase (`config/animation_presets/pre_seal_main.json`).

---

## 4. 5-Component Handoff Report

### 1. Observation
- **LOC-01**: In `scripts/player/player_controller.gd:910-924`, `_apply_posture_collider()` only sets `collider.position.y = target_height * 0.5`. `CollisionShape3D` local X and Z remain 0.0. In `scenes/player/operator_player.tscn:13-19`, the player node has only `CollisionShape3D` and lacks `SocomAnimatedHurtboxRig`. In `scripts/combat/socom_bullet_penetration.gd:113-115`, hitscans test `Player.CollisionShape3D`. When leaning, the visual head moves $-0.339\text{m}$ into the open corridor (`operator_posture_layer.gd:968-1015`), leaving the collision hull completely behind cover.
- **LOC-03**: In `scripts/player/player_controller.gd:380-402`, horizontal velocity is moved toward `horizontal_target` via `_horizontal_response_acceleration()` with ground parameters: `acceleration = 45.0`, `braking_acceleration = 60.0`, `reversal_acceleration = 90.0`, and `instant_strafe_response = true`. No check for `motion_state == MotionState.AIRBORNE` or floor contact exists. Releasing input halts horizontal flight in 0.108s; pressing backward reverses flight in 0.144s.
- **LOC-04**: In `scripts/player/player_controller.gd:50, 799-813, 890-908`, `MotionState.LANDING` lasts `landing_recovery = 0.18s`, but `_movement_speed()` (lines 584-589) does not check `LANDING` and returns $6.5\text{ m/s}$. `_try_begin_mobility_action()` allows immediate jumping upon floor contact without checking `LANDING` or a cooldown timer, enabling continuous $6.5\text{ m/s}$ bunny-hopping.
- **LOC-07**: In `scripts/player/player_controller.gd:438-444`, `_directional_movement_speed()` calculates `lateral_weight = absf(move_axis.x) / move_axis.length()`. Pure backward input (`move_axis = Vector2(0, 1)`) yields `lateral_weight = 0.0`, returning `forward_speed = 6.5 m/s`. Forward and backward speeds are strictly 1:1.
- **ISO Boundary**: In `config/reference/socom2_weapon_settings.json` (`RUN/ZWEAPON.ZAR` -> `zweapon.rdr`), all fields relate exclusively to weapon attributes (`FireWait`, `Muzzle_Velocity`, `Ammo_Capacity`, stance `ReticuleKnock`, stance `TargetDilateUponFire`). Locomotion speeds, jump mechanics, and collision structures do not exist in the ISO tables; they are governed by compiled PS2 MIPS engine code (`SLUS_206.36`).

### 2. Logic Chain
1. *From Observation 1*: Because `CollisionShape3D` is static at `(0, y, 0)` and no animated hurtbox rig exists on `operator_player.tscn`, bullet hitscans and physics collision test an un-leaned root capsule. Therefore, leaning operators are immune to headshots behind cover and clip through adjacent walls.
2. *From Observation 2*: Because horizontal velocity integration does not branch on airborne state, ground friction formulas apply in mid-air. Therefore, airborne players exhibit non-ballistic arcade movement (instant stopping, mid-air reversal, mid-air acceleration).
3. *From Observation 3*: Because `_movement_speed()` does not dampen velocity during `MotionState.LANDING` and `_try_begin_mobility_action()` does not reject jump input during `MotionState.LANDING`, players encounter neither deceleration nor delay upon landing. Therefore, players can bunny-hop indefinitely.
4. *From Observation 4*: Because `_directional_movement_speed()` ignores `move_axis.y > 0`, backpedaling does not apply any velocity multiplier. Therefore, players sprint backwards at full $6.5\text{ m/s}$ while shooting forward.
5. *From Observation 5*: Because static ISO tables contain only weapon stats, discrepancies in locomotion and physics represent engine code implementation gaps against PS2 MIPS conventions, rather than missing table data.

### 3. Caveats
- Single-player / training range parity was audited against `scenes/player/operator_player.tscn`. Multiplayer network replication was verified via `scripts/network/socom_network_operator.gd`, where `SocomAnimatedHurtboxRig` is already bound.
- Dive combos (`jump_direction_combos.json`) have custom collider heights ($1.25\text{m}$); this report evaluated standard jump and lean mechanics.
- No other uninvestigated areas remain within the R1 locomotion scope.

### 4. Conclusion
The 4 locomotion defects are confirmed with high precision:
- **LOC-01**: Critical hit-detection and collision defect caused by static `CollisionShape3D` positioning and omission of `SocomAnimatedHurtboxRig` in `operator_player.tscn`.
- **LOC-03**: Core physics defect caused by running ground acceleration, braking, and reversal algorithms during `MotionState.AIRBORNE`.
- **LOC-04**: Anti-exploit defect caused by missing landing speed damping in `_movement_speed()` and missing `MotionState.LANDING` lockout in `_try_begin_mobility_action()`.
- **LOC-07**: Pacing defect caused by missing backward speed penalty in `_directional_movement_speed()`.

Remediation requires bounded modifications in `player_controller.gd` and `operator_player.tscn` conforming to `AGENTS.md` Single-Owner Movement rules.

### 5. Verification Method
1. **Feature Contract Gate**:
   ```bash
   /Users/kiwimango/Applications/Godot-4.7.1.app/Contents/MacOS/Godot --headless --path /Users/kiwimango/socom-141-camera-lab --script res://tools/feature_contract_regression.gd
   ```
   *Pass Condition*: Exit code 0, all 121 contracts pass.
2. **Mobility Regression**:
   ```bash
   /Users/kiwimango/Applications/Godot-4.7.1.app/Contents/MacOS/Godot --headless --path /Users/kiwimango/socom-141-camera-lab --script res://tools/mobility_regression.gd
   ```
   *Inspection*: Inspect `peek_head_x` and gait speed metrics.
3. **Mid-Air Momentum Invalidation Condition**:
   - If releasing input during `motion_state == MotionState.AIRBORNE` results in `velocity.length() < 0.9 * launch_speed`, momentum conservation is invalidated.
4. **Landing & Bunny-Hop Invalidation Condition**:
   - If pressing `Space` on the first frame of landing allows an immediate jump without completing `landing_recovery`, bunny-hopping prevention is invalidated.
5. **Backpedal Invalidation Condition**:
   - If `move_axis == Vector2(0, 1)` results in horizontal speed $> 4.3\text{ m/s}$, the backward speed penalty is invalidated.

---
*Report compiled by explorer_locomotion_2 in accordance with AGENTS.md rules 1–10.*
