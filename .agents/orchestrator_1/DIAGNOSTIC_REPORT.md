# SOCOM-141 Comprehensive Quality Audit & Diagnostic Report
**Authoritative Architectural & Gameplay Evaluation**

- **Project Root**: `/Users/kiwimango/socom-141-camera-lab`
- **Lead Orchestrator**: `orchestrator_1` (Teamwork Project Orchestrator)
- **Engine Binary**: `/Users/kiwimango/Applications/Godot-4.7.1.app/Contents/MacOS/Godot` (`v4.7.1.stable.official.a13da4feb`)
- **Evaluation Standards**: Authentic *SOCOM II: U.S. Navy SEALs* (PS2), `AGENTS.md`, `docs/GAMEPLAY_INTENT_DICTIONARY.md`, and `docs/GODOT_FEATURE_INTEGRATION_CONTRACT.md`
- **Date**: 2026-09-12

---

## Table of Contents
1. [Executive Summary & High-Level Matrix](#1-executive-summary--high-level-matrix)
2. [Regression Test Suite & Contract Status](#2-regression-test-suite--contract-status)
3. [Domain 1: Locomotion, Posture & Jump Mechanics (`scripts/player/`)](#3-domain-1-locomotion-posture--jump-mechanics)
4. [Domain 2: Weapon Handling & Ballistics (`scripts/weapons/`)](#4-domain-2-weapon-handling--ballistics)
5. [Domain 3: Camera & HUD Presentation (`scripts/camera/`, `scripts/runtime/`)](#5-domain-3-camera--hud-presentation)
6. [Architectural Health & Code Budget Analysis](#6-architectural-health--code-budget-analysis)
7. [Prioritized Remediation Roadmap & Translation Cards](#7-prioritized-remediation-roadmap--translation-cards)

---

## 1. Executive Summary & High-Level Matrix

A rigorous, full-depth quality audit and diagnostic evaluation was conducted across the SOCOM-141 code repository. The evaluation analyzed source scripts in `scripts/player/`, `scripts/weapons/`, `scripts/camera/`, `scripts/runtime/`, scene configurations in `scenes/`, feature contracts in `config/feature_contracts/`, and executed all 48 test and regression suites in `tools/` headlessly in Godot 4.7.1.

### Global Health Verdict
- **Single-Owner Aim-Intent Authority (Rule 5)**: **PASS**. The third-person camera rig acts strictly as an aim-intent author (`aim_yaw`, `aim_pitch`) and never modifies player body transforms.
- **Single-Owner Movement Authority (Rule 5)**: **PASS**. `CharacterBody3D` is the sole player movement and physics transform owner.
- **Core Contract Gating**:
  - `tools/feature_contract_regression.gd`: **PASS** (121/121 contracts validated statically).
  - `tools/public_training_range_regression.gd`: **PASS** (53/53 integration checks pass).
- **Headless Targeted Regression Suite**: **34 PASS / 14 FAIL (70.8% Pass Rate)**.
- **Total Verified Defects Cataloged**: **30 Verified Technical & Gameplay Defects** across Locomotion (12), Weapons/Ballistics (8), and Camera/HUD/Presentation (10).

### Executive Defect Matrix

| ID | Domain | Severity | Title | Key File & Line | Impact |
|---|---|---|---|---|---|
| **LOC-01** | Locomotion | **CRITICAL** | Lean Peaking Collision Decoupling ("Ghost-Head") | `player_controller.gd:909-924` | `CollisionShape3D` remains at `(0, y, 0)` while mesh leans; player is invulnerable behind cover. |
| **LOC-02** | Locomotion | **HIGH** | Instant Strafe Snap (Zero-Frame Velocity Teleport) | `player_controller.gd:16, 388-391` | Lateral input bypasses acceleration and teleports velocity, violating intent dictionary. |
| **LOC-03** | Locomotion | **HIGH** | Zero Air Momentum Conservation | `player_controller.gd:380-402` | Ground acceleration, braking (60 m/s²), and reversal (90 m/s²) operate in mid-air. |
| **LOC-04** | Locomotion | **HIGH** | Missing Jump Cooldown & Bunny-Hopping Exploit | `player_controller.gd:799-813` | No jump cooldown or landing velocity reduction; players chain continuous 6.5 m/s jumps. |
| **LOC-05** | Locomotion | **HIGH** | Right-Lean Peaking Asymmetry | `mobility_regression.gd:221` | Right lean displaces head +3.7mm vs Left lean -338mm; right corner peeking is broken. |
| **LOC-06** | Locomotion | **MEDIUM** | 0-Frame Instant Posture Resizing (Crouch Spam) | `player_controller.gd:925-935` | Posture and capsule height change in 0.0s, allowing 60 Hz crouch spamming. |
| **LOC-07** | Locomotion | **MEDIUM** | 1:1 Forward vs Backward Speed Ratio | `player_controller.gd:438-444` | Backpedaling moves at 100% sprint speed (6.5 m/s); lacks tactical backpedal penalty. |
| **LOC-08** | Locomotion | **MEDIUM** | Crouch Strafe Vertical Hip Bobbing Spikes | `crouch_strafe_continuity_probe.gd:83` | Direction change causes 0.517m vertical hip spike, failing continuity regression. |
| **LOC-09** | Locomotion | **MEDIUM** | Prone Crawl Knee Ground Penetration | `prone_grounding_regression.gd:118` | Knees penetrate 11–21cm below floor plane during crawl animation. |
| **LOC-10** | Locomotion | **MEDIUM** | Directional Strafe Gait Cycle Alias Mismatch | `directional_locomotion_phase.gd:33` | Left/right strafing reuses forward gait cycle clips instead of true strafe animations. |
| **LOC-11** | Locomotion | **LOW** | Turn-in-Place Threshold Hypersensitivity | `player_controller.gd:33` | 0.5° threshold immediately rotates CharacterBody, preventing seated torso twist. |
| **LOC-12** | Locomotion | **ARCH** | Local Player Hurtbox Rig Parity Deficit | `scenes/player/operator_player.tscn:16` | Local player resolves hits against raw capsule; lacks animated bone-following Area3D rig. |
| **WEAP-01** | Weapons | **CRITICAL** | Broken Prone Recoil Bloom Fallback | `weapon_ballistics.gd:363-381` | Prone stance lacks branch logic, falling back to standing recoil (2.4° max vs crouch 1.7°). |
| **WEAP-02** | Weapons | **HIGH** | Inverted Crouch 3rd-Shot Bloom Jump | `weapon_ballistics.gd:41, 45` | Crouch bloom is 1.35°/shot vs standing 0.32°; crouching severely degrades burst accuracy. |
| **WEAP-03** | Weapons | **HIGH** | Truncated Burst-Fire on Quick Trigger Tap | `weapon_fire_mode_policy.gd:69-80` | Quick release aborts burst mid-cycle without resetting counter; leaves orphaned rounds. |
| **WEAP-04** | Weapons | **HIGH** | Uncancelable Auto-Reload Trap | `weapon_reload_coordinator.gd:99, 172` | Empty magazine triggers 2.2s lockout; sprint, dive, roll, fire, or swap cannot cancel. |
| **WEAP-05** | Weapons | **HIGH** | Grenade Throw Velocity Zeroing | `main_grenade_runtime.gd:425-433` | Player velocity is set to 0 at throw start, rendering momentum inheritance inert. |
| **WEAP-06** | Weapons | **HIGH** | Point-Blank Parallax Miss (<2m) | `ballistic_convergence_regression.gd` | Camera sight ray and weapon muzzle ray fail to acquire target dummy head at close range. |
| **WEAP-07** | Weapons | **MEDIUM** | Empty Default Secondary & 0ms Swap | `socom_weapon_controller.gd:17-25` | Default secondary slot is empty string; swapping is instant (0ms) and blocked during reload. |
| **WEAP-08** | Weapons | **MEDIUM** | Missing Closed-Bolt Tactical Reload (+1) | `player_ammunition_inventory.gd:76-88` | Reloads strictly clamp to magazine size; chambered round is discarded. |
| **HUD-01** | Camera/HUD | **HIGH** | Modern Cyan Ring Overriding Authentic Reticle | `socom_dynamic_reticle.gd:332` | Contextual HUD draws neon cyan ring with orange dot; breaks `ballistic_reference_reticle`. |
| **HUD-02** | Camera/HUD | **HIGH** | 3D Floating AR Card Overriding Tactical Plate | `socom_loadout_card_hud.gd:126-130` | Floating loadout card bobbing over operator spine overrides fixed PS2 tactical HUD. |
| **HUD-03** | Camera/HUD | **HIGH** | Dynamic Reticle Shot Kick Zeroed | `socom_dynamic_reticle.gd:167-172` | Setting `source_family` zeroes `shot_bounce_amplitude`, breaking `reticle_render_integration`. |
| **HUD-04** | Camera/HUD | **MEDIUM** | Stance Indicator Overlapping Player Status | `socom_stance_indicator.gd:21-24` | Indicator coordinates directly overlap Status Panel text in bottom-left corner. |
| **HUD-05** | Camera/HUD | **MEDIUM** | Training Range Title Overlapping Compass | `main_gameplay_hud_builder.gd:192` | Title label and tactical compass share identical screen coordinates at top center. |
| **HUD-06** | Camera/HUD | **MEDIUM** | HUD Toggle Hides Its Own Toggle Button | `main_gameplay_hud_builder.gd:244-266` | Toggling HUD off hides the button on CanvasLayer, making mouse unhide impossible. |
| **HUD-07** | Camera/HUD | **MEDIUM** | Hidden HUD CPU Processing Leak | `main_gameplay_hud.gd:177-244` | Per-frame string formatting and UI mutations execute every frame even when HUD is hidden. |
| **HUD-08** | Camera/HUD | **MEDIUM** | Camera Volume Omission of Collision Mask 1 | `camera_passage_policy.gd:35-42` | Camera volume cast uses default mask, colliding with dynamic player character colliders. |
| **HUD-09** | Camera/HUD | **LOW** | 15-Pixel Mouse Aim Deadzone | `mouse_aim_model.gd:45` | Deadzone of 15px swallows fine micro-aiming for distant headshots. |
| **HUD-10** | Camera/HUD | **ARCH** | Missing Feature Contracts | `config/feature_contracts/` | Tactical grenade throwing, prone crawling, and weapon inventory cycling lack JSON contracts. |

---

## 2. Regression Test Suite & Contract Status

### 2.1 Core Architectural Gates
Both mandatory project verification gates execute cleanly:

```bash
/Users/kiwimango/Applications/Godot-4.7.1.app/Contents/MacOS/Godot --headless -s tools/feature_contract_regression.gd
```
- **Exit Code**: `0`
- **Output**: `[FEATURE CONTRACT] PASS: 121 contract(s) form complete Godot integration graphs`

```bash
/Users/kiwimango/Applications/Godot-4.7.1.app/Contents/MacOS/Godot --headless -s tools/public_training_range_regression.gd
```
- **Exit Code**: `0`
- **Output**: 53 individual checks verified across training range activation, player identity, HUD toggle key (`H`), loadout menu (`B`), dummy damage registration, and reticle targeting.

### 2.2 Targeted Gameplay Regression Results (48 Suites)
Automated execution of all targeted suites revealed **34 passing suites** and **14 failing suites**:

```
TOTAL SUITES EVALUATED : 48
PASSED                 : 34 (70.8%)
FAILED                 : 14 (29.2%)
```

#### Detailed Breakdown of Failing Suites
1. `tools/directional_locomotion_phase_regression.gd` (Exit Code 1):
   - `FAIL`: `run_left`, `run_right`, `crouch_left`, and `crouch_right` reuse forward gait cycles instead of distinct strafe cycles.
2. `tools/crouch_strafe_continuity_probe.gd` (Exit Code 1):
   - `FAIL`: Crouch direction changes exceed maximum permitted gait height variation (hip height spikes by 0.517m).
3. `tools/prone_grounding_regression.gd` (Exit Code 1):
   - `FAIL`: Forward-prone crawl knee positions dip 11–21cm below floor level (`left_knee_m = -0.0211`, `right_knee_m = -0.1228`).
4. `tools/jump_direction_combo_regression.gd` (Exit Code 1):
   - `FAIL`: Crouched dive start positions exhibit pelvis height discontinuity against crouch idle baseline.
5. `tools/weapon_fire_regression.gd` (Exit Code 1):
   - `FAIL`: Accepted fire layer fails smooth entry; firing jumps reticle away from screen center; second shot fails to retain aim center during muzzle reconvergence.
6. `tools/all_weapon_fire_recovery_regression.gd` (Exit Code 1):
   - `FAIL`: 36 long guns (shotguns, assault rifles, snipers) fail standing and crouched fire recovery checks because `weapon_solver_owned = true` breaks single-owner right-hand grip IK.
7. `tools/firearm_family_live_contact_regression.gd` (Exit Code 1):
   - `FAIL`: Shotguns and long guns fail support-hand-only IK rule during Ready Aim.
8. `tools/weapon_auto_reload_regression.gd` (Exit Code 1):
   - `FAIL`: Test harness crashes on string formatting (`%s`); test double lacks `can_reload()` implementation.
9. `tools/weapon_bloom_profile_regression.gd` (Exit Code 1):
   - `FAIL`: `config/weapons/assaultrifle_1.json` lacks `"ballistics"` block, returning `-1.0` for spread and bloom parameters.
10. `tools/ballistic_reference_reticle_regression.gd` (Exit Code 1):
    - `FAIL`: Combat reticle draws modern `draw_arc` disc instead of authentic U-shaped open brackets.
11. `tools/reticle_render_integration.gd` (Exit Code 1):
    - `FAIL`: Reference reticle shape bounce upward after shot is zeroed out for weapons with defined `source_family`.
12. `tools/ballistic_convergence_regression.gd` (Exit Code 1):
    - `FAIL`: Blue sight ray fails to acquire animated head hurtbox at close range (<2.0m) due to camera-to-muzzle parallax offset.
13. `tools/test_dynamic_reload_handoff.gd` (Exit Code 1):
    - `FAIL`: Reload coordinator rejects reload when weapon magazine is completely full, causing test assertions to stall.
14. `tools/god_file_budget_regression.gd` (Exit Code 1):
    - `FAIL`: 5 player scripts exceed 1,000 lines (up to 1,242 lines in `operator_posture_layer.gd`), breaching the 500-line architecture limit.

---

## 3. Domain 1: Locomotion, Posture & Jump Mechanics

### 3.1 Gait Velocity Bounds & Pacing
Character gaits are partitioned cleanly:
- Standing Forward: `6.5 m/s`
- Crouched Forward: `2.6 m/s` (40% of standing)
- Prone Crawl: `1.25 m/s` (19.2% of standing)

**Discrepancy (LOC-07)**: Forward and backward movement speeds are strictly 1:1 (`scripts/player/player_controller.gd:438-444`). Authentic *SOCOM 2* enforces a ~30–40% backward speed penalty (~4.0–4.5 m/s) to prevent backward sprint-kiting while firing.

### 3.2 Instant Strafe Teleportation & Competitive Burst
- **Defect LOC-02**: In `scripts/player/player_controller.gd:16, 388-391`:
```gdscript
@export var instant_strafe_response: bool = true
...
elif instant_strafe_response and absf(input.x) > 0.001:
	horizontal_response_mode = &"INSTANT_STRAFE"
	horizontal_velocity = horizontal_target
```
Whenever lateral input is pressed, horizontal velocity instantly snaps to target velocity in 0 frames. This violates `docs/GAMEPLAY_INTENT_DICTIONARY.md` (line 54: *"Movement feels like a joystick: Accelerate toward an input direction... Never teleport the body transform"*).
- Additionally, `strafe_burst_multiplier = 1.18` injects an artificial speed boost to 7.67 m/s upon strafe initiation, introducing modern CS/Valorant jiggle-peeking contrary to SOCOM's grounded analog movement.

### 3.3 Lean Peaking Collision Decoupling (Critical Defect LOC-01)
- In `scripts/player/player_controller.gd:909-924`, `_apply_posture_collider()` only adjusts `capsule.height` and `collider.position.y`:
```gdscript
collider.position.y = target_height * 0.5
```
- In `scripts/player/operator_posture_layer.gd:88-91`, the visual skeletal mesh leans laterally over 0.18s.
- In `scripts/camera/camera_preferred_shot_solver.gd:68`, camera lateral offset shifts by `peek_amount * 0.38m`.
- In `scripts/combat/socom_bullet_penetration.gd:113-115`, bullet hit detection tests `Player.CollisionShape3D`.

**Impact**: When an operator leans around a wall, their visual head and rifle model extend 38cm into the open corridor, but their physical collision capsule remains frozen at `(0, y, 0)` behind solid cover. Incoming bullets aimed at the visible head strike the wall or pass through empty space, granting the peeking player total invulnerability.

### 3.4 Directional Jump Physics & Bunny-Hopping
- **Zero Air Momentum Conservation (LOC-03)**: In `scripts/player/player_controller.gd:380-402`, while `motion_state == MotionState.AIRBORNE`, horizontal movement velocity is continuously recalculated using ground acceleration (`45.0 m/s²`), braking (`60.0 m/s²`), and reversal (`90.0 m/s²`). Releasing movement keys halts mid-air flight in 0.10s; pressing the opposite direction reverses flight in 0.14s. Neutral vertical jumps allow sprinting forward mid-flight.
- **Missing Landing Penalty & Jump Cooldown (LOC-04)**: `player_controller.gd:799` allows immediate jumping on ground contact without checking `MotionState.LANDING` or enforcing a cooldown. Players move at full 6.5 m/s during landing recovery and can bunny-hop indefinitely.

### 3.5 Posture Transitions & Crouch Spam
- **0-Frame Snap (LOC-06)**: In `scripts/player/player_controller.gd:925-935`, `_try_set_posture()` resizes capsule heights (1.85m -> 1.25m -> 0.82m) in 1 simulation tick (0.0s), allowing 60 Hz crouch spamming.
- **Hip Spiking (LOC-08)**: Direction changes in crouch strafing trigger a 0.517m vertical hip displacement (`tools/crouch_strafe_continuity_probe.gd`).
- **Prone Ground Clipping (LOC-09)**: Forward prone crawling causes knee joints to clip 11–21cm into terrain geometry (`tools/prone_grounding_regression.gd`).

---

## 4. Domain 2: Weapon Handling & Ballistics

### 4.1 Broken Prone Recoil Bloom Fallback (Critical Defect WEAP-01)
In `scripts/weapons/weapon_ballistics.gd:363-381`:
```gdscript
func _bloom_per_shot_for(posture: StringName) -> float:
	return crouch_bloom_per_shot_deg if posture == &"CROUCHED" else bloom_per_shot_deg

func _maximum_bloom_for(posture: StringName) -> float:
	return (
		crouch_max_recoil_bloom_deg
		if posture == &"CROUCHED"
		else max_recoil_bloom_deg
	)

func _recovery_speed_for(posture: StringName) -> float:
	return (
		crouch_bloom_recovery_speed
		if posture == &"CROUCHED"
		else bloom_recovery_speed
	)
```
Although line 14 documents `Prone = 0.20x, Crouch = 0.60x, Stand = 1.0x`, the methods only check `posture == &"CROUCHED"`. In the prone stance, every method falls back to standing values (`max_recoil_bloom_deg = 2.4°`, `bloom_per_shot_deg = 0.32°`, `bloom_recovery_speed = 10.0`), making firing from prone significantly less accurate than firing from a crouch.

### 4.2 Inverted Crouch 3rd-Shot Bloom Jump (WEAP-02)
In `scripts/weapons/weapon_ballistics.gd:41, 45`:
```gdscript
@export var bloom_per_shot_deg: float = 0.32
@export var crouch_bloom_per_shot_deg: float = 1.35
```
`crouch_bloom_per_shot_deg` is configured to 1.35° (4.2x standing bloom). In a 3-round burst, crouched spread expands to 1.551° on shot 3, whereas standing spread reaches only 0.600°, severely punishing players for crouching during burst fire.

### 4.3 Truncated Burst-Fire & Orphaned Rounds (WEAP-03)
In `scripts/weapons/weapon_fire_mode_policy.gd:69-80`:
```gdscript
"burst":
	if not trigger_held:
		_burst_release_required = false
		return false
	if _burst_rounds_remaining > 0:
		return true
	if _burst_release_required:
		return false
	if trigger_pressed:
		_burst_rounds_remaining = mini(burst_size, rounds_available)
	return _burst_rounds_remaining > 0
```
If a player taps and releases the trigger in under 100ms, `trigger_held` becomes false while `_burst_rounds_remaining` is still 2. The burst terminates immediately without clearing `_burst_rounds_remaining`. The next trigger pull fires the orphaned 2 rounds instead of a fresh 3-round burst.

### 4.4 Uncancelable Auto-Reload Trap (WEAP-04)
In `scripts/runtime/weapon_reload_coordinator.gd:99-106, 172-174`:
- Empty magazine automatically triggers reload.
- `_on_mobility_action_started()` is stubbed with `pass` (movement/sprinting/diving never cancels reload).
- `cancel_for_fire()` rejects empty magazines: `if int(ammo.get("rounds_in_magazine", 0)) <= 0: return false`.
- In `scripts/weapons/socom_weapon_controller.gd:65`, `equip_carried_slot()` rejects switching while `_reload_blocks_fire()` is true.

**Impact**: A player running out of ammo is locked into an inescapable 2.2-second reload animation with no ability to sprint away, dive behind cover, or switch to a sidearm.

### 4.5 Grenade Movement Freeze & Inactive Momentum (WEAP-05)
In `scripts/runtime/main_grenade_runtime.gd:425-433`:
```gdscript
func _set_movement_locked(locked: bool) -> void:
	if locked and player is CharacterBody3D:
		player.velocity.x = 0.0
		player.velocity.z = 0.0
```
This zeroes player horizontal velocity before grenade release. Consequently, `tactical_grenade_thrower.gd:133` calculating `var momentum_carried := player_velocity * 1.25` inherits `Vector3.ZERO`, rendering momentum-assisted grenade tosses completely inert.

### 4.6 Point-Blank Parallax Miss (WEAP-06)
In `tools/ballistic_convergence_regression.gd`, camera ray and weapon muzzle ray fail to converge on animated head hurtboxes at distances under 2.0 meters. The weapon barrel ray passes beneath the target head hurtbox, resulting in 0 damage.

---

## 5. Domain 3: Camera & HUD Presentation

### 5.1 Aim-Intent Ownership (Rule 5 Compliance)
The camera rig strictly complies with Rule 5 of `AGENTS.md`. It acts exclusively as an aim-intent author (`aim_yaw`, `aim_pitch`). Inspection confirms 0 occurrences of the camera rig modifying character position or rotation. `scripts/player/player_controller.gd:529-532` reads yaw/pitch passively from the `socom_camera_rig` group.

### 5.2 SOCOM 2 Feel Departures
- **Modern Cyan Ring Reticle (HUD-01)**: In `scripts/ui/socom_dynamic_reticle.gd:332`:
```gdscript
draw_arc(Vector2.ZERO, radius, 0.0, TAU, 96, tint, 1.5, true)
```
Draws a modern neon-cyan circular ring with an orange center dot (`config/contextual_hud.json`). This violates `tools/ballistic_reference_reticle_regression.gd`, which mandates authentic SOCOM 2 open U-shaped chartreuse brackets.
- **Floating 3D Holographic Loadout Card (HUD-02)**: In `scripts/ui/socom_loadout_card_hud.gd:126-130`, the loadout card unprojects the operator's animated torso spine position and floats in 3D world space. This modern AR presentation replaces authentic SOCOM 2's fixed, bottom-right tactical weapon status plate.
- **Shot Kick Suppression (HUD-03)**: In `scripts/ui/socom_dynamic_reticle.gd:167-172`, setting `source_family` zeroes `shot_bounce_amplitude = 0.0`, breaking upward reticle kick in `tools/reticle_render_integration.gd`.

### 5.3 UI Layout Overlaps
- **Stance Indicator & Status Panel Overlap (HUD-04)**:
  - `scripts/ui/socom_stance_indicator.gd:21-24`: `offset_left = 22.0`, `offset_top = -140.0`, `offset_right = 72.0`, `offset_bottom = -88.0`.
  - `scripts/runtime/main_gameplay_hud.gd:157-160`: `panel.offset_left = 18.0`, `panel.offset_right = 250.0`, `panel.offset_top = -112.0`, `panel.offset_bottom = -18.0`.
  - Bounding boxes collide at `x: 22..72` and `y: -112..-88`, superimposing stance graphics over player health/ammo text.
- **Training Range Title & Compass Overlap (HUD-05)**:
  - `scripts/runtime/main_gameplay_hud_builder.gd:192-195`: Title anchors center-top, `y: 16..48`.
  - `scripts/ui/socom_tactical_compass.gd:42`: Compass position `y: 14..46`.
  - Both elements render on top of each other at top center.

### 5.4 HUD Toggle Deficiencies (`H` Key)
- **Toggle Button Disappearance (HUD-06)**: In `main_gameplay_hud_builder.gd:244, 266`, hiding the HUD hides `hud.gameplay_layer`, which contains the toggle button itself. Non-keyboard users cannot unhide the HUD.
- **Background CPU Leak (HUD-07)**: When the HUD is hidden, `_update_player_status_ui()` in `main_frame_runtime.gd:111` continues running per-frame string allocations, and line 211 continuously resets `player_status_panel.visible = true`.
- **Camera Collision Mask (HUD-08)**: `camera_passage_policy.gd:35-42` omits `collision_mask = 1`, causing the camera arm to collide against dynamic player characters.
- **Mouse Deadzone (HUD-09)**: `mouse_aim_model.gd:45` enforces a 15-pixel deadzone that swallows subtle aim corrections.

---

## 6. Architectural Health & Code Budget Analysis

### 6.1 God File Budget Breaches
Rule inspection via `tools/god_file_budget_regression.gd` flags **10 files exceeding 500 lines**, with 5 massive monoliths exceeding 1,000 lines:
1. `scripts/player/operator_posture_layer.gd`: **1,242 lines**
2. `scripts/player/operator_locomotion_blend_tree.gd`: **1,184 lines**
3. `scripts/player/player_controller.gd`: **1,138 lines**
4. `scripts/player/operator_asset_runtime.gd`: **1,118 lines**
5. `scripts/player/test_mannequin.gd`: **1,008 lines**

These oversized classes tightly couple character movement, animation state machine playback, physics collisions, network state prediction, and procedural IK adjustments, which directly caused the lean peaking collision decoupling and hip bobbing defects.

### 6.2 Missing Feature Contracts
Under `AGENTS.md` Rule 7, three critical runtime features operate without required contracts in `config/feature_contracts/`:
1. `tactical_grenade_delivery.json` (covers `tactical_grenade_thrower.gd` and trajectory preview).
2. `prone_grounding_crawl.json` (covers prone crawl height and knee placement).
3. `weapon_inventory_cycling.json` (covers slot switching, holstering delays, and secondary equip).

---

## 7. Prioritized Remediation Roadmap & Translation Cards

### Phase 1: Critical Gameplay & Exploits (Priority 1)

#### Translation Card LOC-01: Lean Peaking Collision Coupling
- **Player Intent**: When leaning left or right, the operator's physical vulnerability shifts with the visible upper torso and head; shots passing through the visual head register damage, and the operator cannot shoot from behind cover while invulnerable.
- **Acceptance Rule**: `CollisionShape3D` horizontal offset matches visual lean offset: `collider.position.x = peek_amount * 0.38 * lean_sign`.
- **System Owner**: `CharacterBody3D` (`SocomTestPlayer`).
- **Must Not Change**: Camera aim-intent ownership, weapon muzzle convergence, posture base heights (1.85m, 1.25m, 0.82m).
- **Focused Proof**: `tools/mobility_regression.gd` and `tools/ballistic_convergence_regression.gd`.

#### Translation Card WEAP-01: Prone Recoil & Bloom Recovery
- **Player Intent**: Firing from the prone posture provides the highest accuracy and fastest bloom recovery in accordance with tactical military doctrine.
- **Acceptance Rule**: `_bloom_per_shot_for()`, `_maximum_bloom_for()`, and `_recovery_speed_for()` explicitly check `posture == &"PRONE"` and return prone multipliers (`0.20x` base bloom, `0.20x` max bloom, `2.0x` recovery speed).
- **System Owner**: `WeaponBallistics` (`scripts/weapons/weapon_ballistics.gd`).
- **Must Not Change**: Server weapon shot authority, damage curves, recoil impulse.
- **Focused Proof**: `tools/weapon_stance_bloom_regression.gd`.

#### Translation Card WEAP-02: Crouch Burst Bloom Normalization
- **Player Intent**: Crouching during burst fire provides tighter grouping than standing.
- **Acceptance Rule**: `crouch_bloom_per_shot_deg` is reduced from 1.35° to `0.20°` (matching 0.60x of standing 0.32°).
- **System Owner**: `WeaponBallistics`.
- **Must Not Change**: Standing base bloom, recovery duration.
- **Focused Proof**: `tools/weapon_bloom_profile_regression.gd`.

#### Translation Card WEAP-04: Reload Cancellation via Tactical Mobility
- **Player Intent**: An operator caught during an auto-reload can cancel the action by sprinting, diving, rolling, or drawing a sidearm.
- **Acceptance Rule**: `_on_mobility_action_started()` cancels reload; `equip_carried_slot()` allows sidearm draw during reload.
- **System Owner**: `SocomWeaponReloadCoordinator` (`scripts/runtime/weapon_reload_coordinator.gd`).
- **Must Not Change**: Completed reload ammo replenishment, server validation.
- **Focused Proof**: `tools/dedicated_reload_regression.gd` and `tools/test_dynamic_reload_handoff.gd`.

---

### Phase 2: Tactical Feel & SOCOM 2 Parity (Priority 2)

#### Translation Card LOC-03: Ballistic Air Momentum Conservation
- **Player Intent**: Jumping is a committed tactical leap; mid-air steering, instant mid-air stops, and air reversals are eliminated.
- **Acceptance Rule**: When `motion_state == MotionState.AIRBORNE`, horizontal velocity is locked to launch velocity; ground acceleration, braking, and instant strafe are disabled.
- **System Owner**: `CharacterBody3D` (`SocomTestPlayer`).
- **Must Not Change**: Jump impulse, gravity, ceiling collision handling.
- **Focused Proof**: `tools/source_jump_regression.gd` and `tools/jump_direction_combo_regression.gd`.

#### Translation Card LOC-04: Jump Cooldown & Landing Recovery
- **Player Intent**: Landing from a jump incurs a brief recovery penalty; bunny-hopping is prevented.
- **Acceptance Rule**: Jumping is blocked during `MotionState.LANDING` and for `0.35s` post-landing; movement speed is reduced to `3.5 m/s` during recovery.
- **System Owner**: `CharacterBody3D` (`SocomTestPlayer`).
- **Must Not Change**: Normal standing run speed (6.5 m/s).
- **Focused Proof**: `tools/mobility_regression.gd`.

#### Translation Card LOC-07: Tactical Backpedal Speed Penalty
- **Player Intent**: Moving backward is slower than moving forward, discouraging backward sprint-firing.
- **Acceptance Rule**: Backward movement (`move_axis.y > 0`) applies a `0.65x` multiplier, capping backward speed at `4.225 m/s`.
- **System Owner**: `CharacterBody3D` (`SocomTestPlayer`).
- **Must Not Change**: Forward move speed, strafe move speed.
- **Focused Proof**: `tools/directional_locomotion_phase_regression.gd`.

#### Translation Card HUD-01: Authentic Chartreuse SOCOM 2 Reticle
- **Player Intent**: Crosshairs display authentic SOCOM 2 open chartreuse brackets that expand with recoil bloom, eliminating modern circular rings.
- **Acceptance Rule**: Remove `draw_arc` disc rendering from `socom_dynamic_reticle.gd:332`; restore four-corner brackets; preserve upward bounce on shot.
- **System Owner**: `SocomDynamicReticle` (`scripts/ui/socom_dynamic_reticle.gd`).
- **Must Not Change**: Ballistic aim resolver, hit registration.
- **Focused Proof**: `tools/ballistic_reference_reticle_regression.gd` and `tools/reticle_render_integration.gd`.

---

### Phase 3: Animation Fidelity, HUD & Architecture (Priority 3)

#### Translation Card LOC-08 & LOC-10: Crouch Strafe & Directional Gait Blending
- **Player Intent**: Strafing left and right uses dedicated lateral footwork animations without vertical hip bobbing.
- **Acceptance Rule**: Assign unique lateral gait cycles in `operator_locomotion_blend_tree.gd`; clamp hip vertical deviation to `<= 0.05m`.
- **System Owner**: `OperatorLocomotionBlendTree`.
- **Must Not Change**: Foot-step sound event triggers.
- **Focused Proof**: `tools/directional_locomotion_phase_regression.gd` and `tools/crouch_strafe_continuity_probe.gd`.

#### Translation Card HUD-04 & HUD-05: UI Coordinate Collision Resolution
- **Player Intent**: Stance indicator, status panel, compass, and training range title render cleanly without overlapping text.
- **Acceptance Rule**: Reposition Stance Indicator to `offset_left = 18.0, offset_top = -170.0, offset_bottom = -118.0`; lower Training Range Title to `y: 52..84`.
- **System Owner**: `MainGameplayHUDBuilder` (`scripts/runtime/main_gameplay_hud_builder.gd`).
- **Must Not Change**: HUD toggle visibility layering.
- **Focused Proof**: `tools/public_training_range_regression.gd`.

#### Translation Card HUD-06 & HUD-07: Robust HUD Toggle Management
- **Player Intent**: Toggling HUD hides in-game elements while retaining access to the toggle button, and disables unnecessary UI processing.
- **Acceptance Rule**: Move toggle button to a persistent control overlay; halt `_update_player_status_ui()` when `not hud_mechanics_visible`.
- **System Owner**: `MainGameplayHUD` (`scripts/runtime/main_gameplay_hud.gd`).
- **Must Not Change**: `H` key input mapping.
- **Focused Proof**: `tools/public_training_range_regression.gd`.

---

## 8. Verification & Handoff Summary

The audit artifacts, logs, and reproduction scripts are structured and indexed in the repository:
- Master Diagnostic Report: `/Users/kiwimango/socom-141-camera-lab/.agents/orchestrator_1/DIAGNOSTIC_REPORT.md`
- Locomotion Audit & Logs: `/Users/kiwimango/socom-141-camera-lab/.agents/explorer_locomotion_1/locomotion_audit.md`
- Weapons Audit & Logs: `/Users/kiwimango/socom-141-camera-lab/.agents/explorer_weapons_1/weapons_audit.md`
- Camera & HUD Audit & Logs: `/Users/kiwimango/socom-141-camera-lab/.agents/explorer_camera_hud_1/camera_hud_audit.md`
- Regression Execution Report & 48 Test Logs: `/Users/kiwimango/socom-141-camera-lab/.agents/worker_regression_1/regression_report.md`
- Regression JSON Database: `/Users/kiwimango/socom-141-camera-lab/.agents/worker_regression_1/test_run_summary.json`

This report provides a complete, verified baseline and concrete roadmap for all subsequent refactoring and polish milestones.
