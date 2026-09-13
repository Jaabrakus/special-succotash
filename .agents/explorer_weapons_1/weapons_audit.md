# Comprehensive Quality Audit: Weapon Handling & Ballistics

**Project**: SOCOM-141 Tactical Shooter  
**Auditor**: `explorer_weapons_1` (teamwork_preview_explorer)  
**Date**: 2026-09-12  
**Investigation Mode**: Read-Only Quality & Diagnostic Evaluation  
**Reference Contracts**:
- `AGENTS.md` (Rules 1–10)
- `docs/GAMEPLAY_INTENT_DICTIONARY.md`
- `docs/GODOT_FEATURE_INTEGRATION_CONTRACT.md`

---

## 1. Executive Summary & System Scorecard

A comprehensive audit of the weapon handling, firing logic, ballistics, dispersion/bloom, reload coordination, grenade kinematics, and network hit authority within `scripts/weapons/`, `scripts/runtime/`, `scripts/tactical/`, and related subsystems was conducted.

The weapon architecture in SOCOM-141 demonstrates strong adherence to single-owner network authority principles (Rule 5: `SocomShotAuthority` as sole damage writer) and exhibits sophisticated anatomical hit resolution (`SocomAnatomicalHitResolver`) and material penetration (`SocomBulletPenetration`). However, the runtime weapon handling exhibits critical departures from authentic SOCOM 2 tactical combat dynamics, several broken stance calculations, uncancelable reload traps that degrade player agency, and a truncated burst-fire bug.

### System Scorecard

| Subsystem Domain | Grade | Status | Key Finding / Blocker |
| :--- | :---: | :---: | :--- |
| **1. Weapon Equip & Cycle** | **C+** | Partial | Carried secondary defaults to empty; weapon swap is instant (0 ms, zero holster/draw animation delay); swapping is blocked during reloads. |
| **2. Firing Cadences & Modes** | **C** | Impaired | Burst fire truncates mid-burst on quick trigger tap, leaving orphaned round counters and violating committed burst rules. |
| **3. Spread, Bloom & Stances** | **D+** | Broken | Prone posture recoil bloom is completely omitted from posture branches (falls back to standing values); crouched 3rd-shot bloom jump is inverted (worse than standing). |
| **4. Reload Cycles & Ammo** | **C-** | Impaired | Auto-reload traps player in uncancelable 2.2s lockout; sprint/jump/dive cannot interrupt reload; weapon swap is locked out; tactical +1 chambering is absent. |
| **5. Grenades & Equipment** | **B-** | Inconsistent | Thrower claims CS:GO momentum inheritance, but grenade runtime hard-freezes operator velocity (`velocity.x = 0, z = 0`); trajectory preview ignores player velocity. |
| **6. Ballistics & Hit Authority** | **B+** | Good | Robust server shot authority and anatomical hit detection, but close-quarters convergence (<2m) fails headshot alignment against animated targets. |

---

## 2. Detailed Domain Audits

### Domain 1: Weapon Equip, Cycle & Slot Management

#### 1. Architecture & Current State
The weapon controller manages equipped weapons and carried loadouts via `scripts/weapons/socom_weapon_controller.gd`.
Slots are divided into `"primary"` and `"secondary"`:
```gdscript
# File: scripts/weapons/socom_weapon_controller.gd:17-25
var carried_loadout: Dictionary = {"primary": "", "secondary": ""}

func equip_carried_slot(slot: String) -> bool:
	var id := String(carried_loadout.get(slot, ""))
	if id.is_empty() or _reload_blocks_fire():
		return false
	if id == String(equipped_weapon_id):
		return true
	return apply_authorized_weapon_pickup("res://config/weapons/%s.json" % id)
```

#### 2. Key Findings & Discrepancies
1. **Secondary Slot Unpopulated by Default**: When the player spawns or initializes a standard loadout, `carried_loadout["secondary"]` remains empty (`""`). Pressing the secondary weapon key (`equip_secondary`, Key 2) produces no action.
2. **Instant Zero-Frame Weapon Swap**: When `apply_authorized_weapon_pickup()` executes, it immediately updates the weapon model on the mannequin in 0 frames. There is no holster delay, no draw animation, no transition state, and no input buffer for weapon switching.
3. **Weapon Swap Lockout During Reload**: Line 21 specifies `if id.is_empty() or _reload_blocks_fire(): return false`. If a player runs out of ammunition in their primary rifle in active combat and presses 2 to pull their sidearm (a fundamental tactical shooter response), the weapon switch is rejected until the full 2.2-second reload animation completes.

---

### Domain 2: Firing Cadences, Fire Mode Policy & Trigger Mechanics

#### 1. Architecture & Current State
Firing policy is governed by `scripts/weapons/weapon_fire_mode_policy.gd` and applied inside `socom_weapon_controller.gd:_physics_process()`. The policy tracks fire modes (`"semi"`, `"burst"`, `"auto"`) and checks trigger inputs (`trigger_pressed`, `trigger_held`).

#### 2. Key Findings & Discrepancies
1. **Truncated Burst-Fire on Quick Trigger Tap**:
   ```gdscript
   # File: scripts/weapons/weapon_fire_mode_policy.gd:69-80
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
   In competitive shooter design and per `docs/GAMEPLAY_INTENT_DICTIONARY.md:39`:
   > *"A three-round burst is one committed pull, not a queue of bursts. Releasing the trigger mid-burst should either finish the 3-round sequence or strictly complete the current pull as committed action, not leave orphaned round counters."*

   Under the current code:
   - If the player taps the left mouse button (held for < 100 ms, shorter than the 3-round burst duration of ~200 ms), `trigger_held` evaluates to `false` on frame 2.
   - The method immediately hits `if not trigger_held: _burst_release_required = false; return false`.
   - The burst stops immediately after 1 round!
   - Crucially, `_burst_rounds_remaining` is NOT reset to 0! It remains at `2`.
   - On the next trigger press, because `_burst_rounds_remaining > 0`, it fires the 2 leftover rounds instead of a full 3-round burst.

2. **Trigger Buffering & Lockout**: Semi-automatic fire correctly checks `trigger_pressed`, requiring a release before the next shot. However, high-frequency trigger clicking during semi-auto cadence cooldown is discarded with zero buffer window (no 50ms buffer to smooth human jitter), creating occasional "micro-stutter" in semi-auto weapons like the M9 or SR-25.

---

### Domain 3: Spread, Bloom Mechanics & Posture Dynamics

#### 1. Architecture & Current State
Ballistics and bloom calculations are performed by `scripts/weapons/weapon_ballistics.gd` using `ReticleBloomEnvelope` (`scripts/weapons/reticle_bloom_envelope.gd`).
The header docstring of `weapon_ballistics.gd` declares:
```gdscript
# File: scripts/weapons/weapon_ballistics.gd:8-16
## SOCOM II Ballistics & Burst-Fire Accuracy Model
## Implements:
## - 2-Round Burst pinpoint accuracy (shots 1 & 2 have 0 extra dispersion)
## - CS:GO Bullet Penetration through thin wood, drywall, and sheet metal
## - Continuous fire bloom escalation
## - Shot-timed bloom recovery; rapid trigger releases cannot reset accuracy
## - Stance bloom multipliers (Prone = 0.20x, Crouch = 0.60x, Stand = 1.0x)
## - Raycast hitscan with dispersion cone matching on-screen reticle
## - Visual bullet tracers and impact effects
```

#### 2. Critical Bugs & Discrepancies
1. **Missing Prone Recoil Bloom Implementation**:
   ```gdscript
   # File: scripts/weapons/weapon_ballistics.gd:363-381
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
   **Observation**: In all three posture-resolution helpers, only `&"CROUCHED"` is checked. When the player goes `&"PRONE"`, the condition evaluates to `false` and falls back to the `else` branch—which is **STANDING**!
   - Standing `max_recoil_bloom_deg`: 2.4°
   - Crouched `crouch_max_recoil_bloom_deg`: 1.7°
   - Prone `max_recoil_bloom_deg`: 2.4°!
   **Result**: Firing prone results in a substantially larger maximum bloom cone and slower recovery than firing crouched. This directly violates the declared SOCOM II stance hierarchy (Prone = 0.20x, Crouch = 0.60x, Stand = 1.0x).

2. **Inverted 3rd-Shot Bloom Jump in Crouch Stance**:
   ```gdscript
   # File: scripts/weapons/weapon_ballistics.gd:41, 45
   @export var bloom_per_shot_deg: float = 0.32
   @export var crouch_bloom_per_shot_deg: float = 1.35
   ```
   - In `weapon_ballistics.gd`, `crouch_bloom_per_shot_deg` is configured at 1.35°, whereas standing `bloom_per_shot_deg` is 0.32°!
   - In `weapon_stance_bloom_regression.gd:27-30`, the test asserted:
     ```gdscript
     _expect(
         crouched_third > standing_third,
         "crouched third shot jumps above standing base"
     )
     ```
   - Because of this inversion, a player crouching to steady their aim suffers an extreme accuracy penalty on the 3rd shot in a burst compared to firing standing. Conversely, `weapon_bloom_profile_regression.gd:57` asserts `crouched_spreads[2] < standing_spreads[2]`. This is an unresolved contradiction across the codebase.

---

### Domain 4: Reload Cycles, Chamber Management & Mobility Cancellation

#### 1. Architecture & Current State
The reload pipeline is governed by `WeaponReloadCoordinator` (`scripts/runtime/weapon_reload_coordinator.gd`), `PlayerAmmunitionInventory` (`scripts/player/player_ammunition_inventory.gd`), and `AutoReloadPolicy` (`scripts/weapons/weapon_auto_reload_policy.gd`).

#### 2. Key Findings & Discrepancies
1. **Uncancelable Auto-Reload Trap**:
   - `AutoReloadPolicy.should_trigger_auto_reload(...)` returns true when `rounds_in_magazine <= 0`.
   - Once triggered, `WeaponReloadCoordinator.request_reload()` locks the weapon state into `pending = true`.
   - Lines 99–106 of `scripts/runtime/weapon_reload_coordinator.gd` contain empty stubs:
     ```gdscript
     func _on_mobility_action_started(state_name: StringName) -> void:
         # Reload is an upper-body timeline. Movement never cancels it.
         pass

     func _on_mobility_action_requested(state_name: StringName) -> void:
         # Reload is an upper-body timeline. Movement never cancels it.
         pass
     ```
   - In `cancel_for_fire()` (lines 165–174):
     ```gdscript
     var ammo: Dictionary = weapon_controller.call("get_ammo_snapshot")
     if int(ammo.get("rounds_in_magazine", 0)) <= 0:
         return false
     ```
     Because the magazine is empty (`rounds_in_magazine == 0`), `cancel_for_fire()` returns `false`.
   - In `equip_carried_slot()` (line 21 of `socom_weapon_controller.gd`):
     `if id.is_empty() or _reload_blocks_fire(): return false`
     Because `_reload_blocks_fire()` is true during reload, swapping to secondary is blocked.
   - **Result**: The player has zero defensive actions available for 2.2 seconds. They cannot sprint-cancel, jump-cancel, roll-cancel, or swap to their pistol.

2. **Missing Tactical Reload (+1 Chambered Round)**:
   ```gdscript
   # File: scripts/player/player_ammunition_inventory.gd:76-88
   func reload_weapon(weapon_id: StringName) -> int:
       var current := snapshot(weapon_id)
       var capacity := int(current.get("magazine_capacity", 0))
       var magazine := int(current.get("rounds_in_magazine", 0))
       var reserve := int(current.get("reserve_ammo", 0))
       var transferred := mini(maxi(0, capacity - magazine), reserve)
       if transferred <= 0:
           return 0
       current["rounds_in_magazine"] = magazine + transferred
       current["reserve_ammo"] = reserve - transferred
       _weapons[String(weapon_id)] = current
       _emit_changed(weapon_id)
       return transferred
   ```
   **Observation**: All weapon reloads clamp strictly to `magazine_capacity` (e.g., 30 rounds).
   In closed-bolt firearms (such as the M4A1, MP5, M16A2, M9), performing a tactical reload with a round remaining in the chamber retains that round, resulting in `capacity + 1` (e.g., 30 + 1 = 31 rounds). The inventory system lacks any chamber state or tactical reload flag.

---

### Domain 5: Grenade Trajectory Preview, Throw Dynamics & Physics

#### 1. Architecture & Current State
Grenade functionality is split across:
- `scripts/runtime/main_grenade_runtime.gd` (orchestration, animation timeline, player movement lock)
- `scripts/runtime/main_grenade_trajectory.gd` (parabolic preview arc)
- `scripts/tactical/tactical_grenade_thrower.gd` (velocity calculation, spawn)
- `scripts/tactical/frag_grenade.gd` (physics, bouncing, detonation, damage falloff)

#### 2. Key Findings & Discrepancies
1. **Movement Lockout Freezes Velocity Despite Momentum Code**:
   - `scripts/tactical/tactical_grenade_thrower.gd:132-134`:
     ```gdscript
     # CS:GO Momentum Inheritance: Throw carries forward momentum (running adds speed, jumping adds height)
     var momentum_carried := player_velocity * 1.25
     return base_launch_vec + momentum_carried
     ```
   - However, in `scripts/runtime/main_grenade_runtime.gd:425-433`:
     ```gdscript
     func _set_movement_locked(locked: bool) -> void:
         if player == null:
             return
         if player.has_method("set_local_input_enabled"):
             player.call("set_local_input_enabled", not locked)
         if locked and player is CharacterBody3D:
             player.velocity.x = 0.0
             player.velocity.z = 0.0
     ```
   - When the grenade throw sequence begins, `_set_movement_locked(true)` immediately sets `player.velocity.x = 0.0` and `player.velocity.z = 0.0`. By the time `launch_grenade()` executes at cue time, `player_velocity` is `Vector3.ZERO`. The momentum inheritance code is rendered completely inert.
2. **Trajectory Preview Inconsistency**: `main_grenade_trajectory.gd` calculates the arc purely from camera angles and base speed without considering operator velocity, so if momentum inheritance were active, the preview arc would diverge from the actual grenade flight path.
3. **SOCOM 2 Mobility Feel**: In SOCOM 2, throwing a grenade allowed smooth crouch or walk transitions without a jarring full-stop physics freeze.

---

### Domain 6: Hit Detection, Convergence & Server Authority

#### 1. Architecture & Current State
The hit-detection pipeline conforms to Rule 5 of `AGENTS.md`:
- `SocomShotAuthority` (`scripts/network/socom_shot_authority.gd`) is the sole damage and shot validator.
- `SocomAnatomicalHitResolver` (`scripts/combat/socom_anatomical_hit_resolver.gd`) performs 4-zone anatomical hit resolution (Head, Neck, Torso, Limbs) with directional torso modifiers.
- `SocomBulletPenetration` (`scripts/combat/socom_bullet_penetration.gd`) evaluates surface density and thickness for wallbangs.

#### 2. Key Findings & Discrepancies
1. **Close-Quarters Dual-Ray Parallax Convergence Failure**:
   - In `tools/ballistic_convergence_regression.gd`:
     ```
     ERROR: BALLISTIC_CONVERGENCE_REGRESSION: blue sight acquires the animated head area instead of scenery behind it
     HEAD_SHOT_METRIC region= damage=0.0 health=100.0
     ```
   - The aiming reticle ray originates from the camera center. The firing ray originates from the weapon barrel muzzle (`Muzzle` marker on the weapon model).
   - At close quarters (<2m from target), parallax between camera origin and weapon barrel causes the ray from the muzzle to miss the target dummy's head hurtbox, passing behind or into the shoulder, despite the reticle resting squarely on the head.

---

## 3. Exhaustive Defect Catalog & Translation Cards

---

### Defect 1: Completely Broken / Missing Prone Recoil Bloom in `weapon_ballistics.gd`

- **Severity**: HIGH (Core Ballistics & Posture Contract Violation)
- **File & Line Numbers**: `scripts/weapons/weapon_ballistics.gd:363-381`
- **Verbatim Code Excerpt**:
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
- **Reproduction Steps**:
  1. Launch weapon ballistics or spawn player in training range.
  2. Transition player posture to `&"PRONE"`.
  3. Fire automatic bursts or inspect `_maximum_bloom_for(&"PRONE")`.
  4. Compare with `_maximum_bloom_for(&"CROUCHED")`.
  5. Observe that prone returns `max_recoil_bloom_deg` (2.4°), which is larger than crouched (1.7°).
- **Technical Explanation**:
  `weapon_ballistics.gd` line 14 documents: `Stance bloom multipliers (Prone = 0.20x, Crouch = 0.60x, Stand = 1.0x)`. However, the stance helper functions only branch on `&"CROUCHED"`. When posture is `&"PRONE"`, it falls back to the default `else` condition (standing values). Consequently, firing prone exhibits full standing recoil spread and slow recovery, punishing players for taking the most stable tactical stance.
- **Rule 2 Translation Card**:
  - **Player intent**: When the player drops into prone, sustained fire spread should have the tightest dispersion envelope (0.20x standing) and fastest recovery speed in accordance with SOCOM 2 stability.
  - **Acceptance rule**: `_maximum_bloom_for(&"PRONE")` returns `prone_max_recoil_bloom_deg` (<= 0.8°), `_bloom_per_shot_for(&"PRONE")` returns `prone_bloom_per_shot_deg` (<= 0.20 * standing), and `_recovery_speed_for(&"PRONE")` returns >= 25.0 deg/sec.
  - **One system owner**: `SocomWeaponBallistics` (`scripts/weapons/weapon_ballistics.gd`).
  - **Systems that must not change**: `ReticleBloomEnvelope`, `CameraAimResolver`, `CharacterBody3D` posture transitions.
  - **Focused proof**: Unit test verifying `_maximum_bloom_for(&"PRONE") < _maximum_bloom_for(&"CROUCHED") < _maximum_bloom_for(&"STANDING")`.

---

### Defect 2: Inverted 3rd-Shot Bloom Jump for Crouched Stance

- **Severity**: HIGH (Tactical Gameplay Feel Discrepancy)
- **File & Line Numbers**: `scripts/weapons/weapon_ballistics.gd:41, 45` & `tools/weapon_stance_bloom_regression.gd:27-30`
- **Verbatim Code Excerpt**:
  ```gdscript
  # scripts/weapons/weapon_ballistics.gd:41, 45
  @export var bloom_per_shot_deg: float = 0.32
  @export var crouch_bloom_per_shot_deg: float = 1.35
  ```
- **Reproduction Steps**:
  1. Fire a 3-round burst standing: Shot 1 (0.28°), Shot 2 (0.28°), Shot 3 (0.28° + 0.32° = 0.60°).
  2. Fire a 3-round burst crouching: Shot 1 (0.201°), Shot 2 (0.201°), Shot 3 (0.201° + 1.35° = 1.551°).
  3. Observe that the crouched third shot spread is over 2.5x wider than the standing third shot!
- **Technical Explanation**:
  `crouch_bloom_per_shot_deg` was set to 1.35° while standing `bloom_per_shot_deg` was set to 0.32°. This inverted the tactical benefit of crouching on the 3rd shot of any burst. In authentic SOCOM 2, crouching always tightens the dispersion envelope relative to standing for every shot in the sequence.
- **Rule 2 Translation Card**:
  - **Player intent**: Crouching must consistently yield tighter reticle bloom and smaller spread per shot than standing.
  - **Acceptance rule**: For any shot index $N \ge 1$, `crouch_spread(N) < standing_spread(N)`. `crouch_bloom_per_shot_deg` must be less than or equal to `bloom_per_shot_deg * 0.70`.
  - **One system owner**: `SocomWeaponBallistics` (`scripts/weapons/weapon_ballistics.gd`).
  - **Systems that must not change**: `ReticleBloomEnvelope`, HUD reticle drawing.
  - **Focused proof**: `tools/weapon_stance_bloom_regression.gd` updated and asserting `crouched_third < standing_third`.

---

### Defect 3: Truncated / Choked Burst-Fire on Quick Trigger Tap

- **Severity**: HIGH (Firing Cadence Defect & Dictionary Violation)
- **File & Line Numbers**: `scripts/weapons/weapon_fire_mode_policy.gd:69-80, 86-93`
- **Verbatim Code Excerpt**:
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
- **Reproduction Steps**:
  1. Select a burst-fire weapon (e.g. M16A2).
  2. Tap the fire trigger quickly (< 80 ms click duration).
  3. Observe that only 1 bullet fires instead of the full 3-round burst.
  4. Press the fire trigger a second time.
  5. Observe that exactly 2 bullets fire (the remainder of the previous burst) instead of 3.
- **Technical Explanation**:
  `wants_fire()` checks `if not trigger_held: return false`. When tapping the trigger, `trigger_held` drops to false after one frame. The policy aborts firing immediately and leaves `_burst_rounds_remaining` in an orphaned state (`_burst_rounds_remaining = 2`). The next trigger pull consumes this orphaned counter. Per `docs/GAMEPLAY_INTENT_DICTIONARY.md:39`, a 3-round burst is a committed pull that should complete its cycle.
- **Rule 2 Translation Card**:
  - **Player intent**: A single trigger tap in burst mode fires a complete, committed 3-round burst without truncation.
  - **Acceptance rule**: Once initiated by `trigger_pressed`, `wants_fire()` returns `true` for all remaining burst rounds (`_burst_rounds_remaining > 0`) regardless of `trigger_held` state, until the burst is exhausted or the magazine is empty.
  - **One system owner**: `WeaponFireModePolicy` (`scripts/weapons/weapon_fire_mode_policy.gd`).
  - **Systems that must not change**: Weapon controller cadence interval timing, ammunition inventory.
  - **Focused proof**: Test in `tools/weapon_fire_regression.gd` simulating `trigger_pressed=true`, followed by `trigger_held=false`, verifying all 3 rounds fire sequentially.

---

### Defect 4: Zero-Delay Instant Weapon Swap & Empty Default Secondary Slot

- **Severity**: MEDIUM (Loadout & Presentation Defect)
- **File & Line Numbers**: `scripts/weapons/socom_weapon_controller.gd:17-25, 224-256`
- **Verbatim Code Excerpt**:
  ```gdscript
  var carried_loadout: Dictionary = {"primary": "", "secondary": ""}

  func equip_carried_slot(slot: String) -> bool:
      var id := String(carried_loadout.get(slot, ""))
      if id.is_empty() or _reload_blocks_fire():
          return false
      if id == String(equipped_weapon_id):
          return true
      return apply_authorized_weapon_pickup("res://config/weapons/%s.json" % id)
  ```
- **Reproduction Steps**:
  1. Start standard play in `res://main.tscn`.
  2. Press key 2 (`equip_secondary`).
  3. Observe nothing happens because `carried_loadout["secondary"]` is `""`.
  4. Call `equip_carried_slot("primary")` with a new weapon.
  5. Observe the weapon switches instantaneously (0 ms) with no holster/draw transition.
- **Technical Explanation**:
  `carried_loadout` is initialized without a default sidearm (e.g. `m9`), leaving key 2 unresponsive. When a weapon is equipped, `apply_authorized_weapon_pickup()` executes instantly without any transition timing or animation synchronization, bypassing authentic tactical weapon transition mechanics.
- **Rule 2 Translation Card**:
  - **Player intent**: Pressing key 2 switches to the secondary sidearm with an authentic holster/draw animation and delay.
  - **Acceptance rule**: Default loadout equips a secondary sidearm (e.g. `m9`). `equip_carried_slot` triggers a dedicated swap state with appropriate holster/draw delay before the new weapon can fire.
  - **One system owner**: `SocomWeaponController` (`scripts/weapons/socom_weapon_controller.gd`).
  - **Systems that must not change**: `SocomShotAuthority`, `PlayerAmmunitionInventory`.
  - **Focused proof**: Regression test verifying default secondary slot presence and swap delay > 0.0s before firing is enabled.

---

### Defect 5: Uncancelable Auto-Reload Lockout & Weapon Swap Suppression

- **Severity**: HIGH (Combat Responsiveness & Player Agency Violation)
- **File & Line Numbers**:
  - `scripts/weapons/weapon_auto_reload_policy.gd:8-9`
  - `scripts/runtime/weapon_reload_coordinator.gd:99-106, 165-174`
  - `scripts/weapons/socom_weapon_controller.gd:21`
- **Verbatim Code Excerpt**:
  ```gdscript
  # scripts/runtime/weapon_reload_coordinator.gd:99-106
  func _on_mobility_action_started(state_name: StringName) -> void:
      # Reload is an upper-body timeline. Movement never cancels it.
      pass

  func _on_mobility_action_requested(state_name: StringName) -> void:
      # Reload is an upper-body timeline. Movement never cancels it.
      pass

  # scripts/weapons/socom_weapon_controller.gd:21
  if id.is_empty() or _reload_blocks_fire():
      return false
  ```
- **Reproduction Steps**:
  1. Deplete primary weapon magazine to 0 rounds.
  2. Auto-reload triggers automatically.
  3. Attempt to sprint (`sprint`), dive (`dive`), or switch to secondary sidearm (`equip_secondary`).
  4. Observe that the reload continues uninterrupted and weapon swap is rejected.
- **Technical Explanation**:
  Auto-reload forces the player into a 2.2-second timeline. `_on_mobility_action_started` is an empty stub. `cancel_for_fire()` rejects cancellation when `rounds_in_magazine <= 0`. `equip_carried_slot` rejects switching while `_reload_blocks_fire()` is true. The operator is completely trapped without any defensive recourse.
- **Rule 2 Translation Card**:
  - **Player intent**: When trapped in an empty reload under fire, the player can immediately swap to their sidearm or execute an evasive dive/sprint to abort the reload.
  - **Acceptance rule**: `equip_carried_slot()` cancels any in-progress reload and initiates sidearm draw. Evasive actions (`dive`, `roll`) abort the reload timer.
  - **One system owner**: `WeaponReloadCoordinator` (`scripts/runtime/weapon_reload_coordinator.gd`).
  - **Systems that must not change**: `PlayerAmmunitionInventory` ammo snapshot values, `CharacterBody3D` movement kinematics.
  - **Focused proof**: Regression test verifying that calling `equip_carried_slot()` during an active empty reload successfully cancels the reload and switches weapons.

---

### Defect 6: Missing Tactical Reload (+1 Chambered Round)

- **Severity**: MEDIUM (Tactical Shooter Parity)
- **File & Line Numbers**: `scripts/player/player_ammunition_inventory.gd:76-88`
- **Verbatim Code Excerpt**:
  ```gdscript
  func reload_weapon(weapon_id: StringName) -> int:
      var current := snapshot(weapon_id)
      var capacity := int(current.get("magazine_capacity", 0))
      var magazine := int(current.get("rounds_in_magazine", 0))
      var reserve := int(current.get("reserve_ammo", 0))
      var transferred := mini(maxi(0, capacity - magazine), reserve)
      if transferred <= 0:
          return 0
      current["rounds_in_magazine"] = magazine + transferred
      current["reserve_ammo"] = reserve - transferred
      _weapons[String(weapon_id)] = current
      _emit_changed(weapon_id)
      return transferred
  ```
- **Reproduction Steps**:
  1. Equip a closed-bolt rifle (e.g. M4A1, 30-round capacity).
  2. Fire 5 rounds (`rounds_in_magazine = 25`).
  3. Press reload (`request_reload`).
  4. Inspect final `rounds_in_magazine`.
  5. Observe `rounds_in_magazine` is 30, rather than 31 (30 in magazine + 1 in chamber).
- **Technical Explanation**:
  `PlayerAmmunitionInventory` treats capacity as a flat integer without accounting for closed-bolt chamber retention. In tactical shooters, tactical reloads with rounds in the chamber yield `capacity + 1` rounds.
- **Rule 2 Translation Card**:
  - **Player intent**: Reloading a partially depleted magazine retains the chambered round, giving full magazine + 1.
  - **Acceptance rule**: For weapons with `closed_bolt: true` in their config, if `rounds_in_magazine > 0`, the reload target capacity is `magazine_capacity + 1`.
  - **One system owner**: `PlayerAmmunitionInventory` (`scripts/player/player_ammunition_inventory.gd`).
  - **Systems that must not change**: Ammo change signal contracts (`ammo_changed(magazine, reserve)`).
  - **Focused proof**: Unit test verifying that reloading an M4A1 with 25 rounds remaining and sufficient reserve yields 31 rounds in magazine.

---

### Defect 7: Grenade Movement Lockout & CS:GO Momentum Discrepancy

- **Severity**: MEDIUM (Grenade Lifecycle & Feel)
- **File & Line Numbers**:
  - `scripts/runtime/main_grenade_runtime.gd:425-433`
  - `scripts/tactical/tactical_grenade_thrower.gd:132-134`
- **Verbatim Code Excerpt**:
  ```gdscript
  # scripts/runtime/main_grenade_runtime.gd:425-433
  func _set_movement_locked(locked: bool) -> void:
      if player == null:
          return
      if player.has_method("set_local_input_enabled"):
          player.call("set_local_input_enabled", not locked)
      if locked and player is CharacterBody3D:
          player.velocity.x = 0.0
          player.velocity.z = 0.0

  # scripts/tactical/tactical_grenade_thrower.gd:132-134
  var momentum_carried := player_velocity * 1.25
  return base_launch_vec + momentum_carried
  ```
- **Reproduction Steps**:
  1. Sprint forward with player.
  2. Initiate grenade throw.
  3. Observe player abruptly comes to a complete dead stop (`velocity.x = 0, velocity.z = 0`).
  4. Observe grenade launches without momentum inheritance because velocity was zeroed.
- **Technical Explanation**:
  `tactical_grenade_thrower.gd` was designed to inherit 1.25x player velocity, but `main_grenade_runtime.gd` hard-resets horizontal velocity to 0.0 at the moment throw begins. This produces a jarring freeze and breaks the trajectory calculation.
- **Rule 2 Translation Card**:
  - **Player intent**: Throwing a grenade during movement allows natural forward deceleration and imparts forward momentum to the grenade throw.
  - **Acceptance rule**: Operator velocity is smoothly clamped or preserved rather than zeroed; `tactical_grenade_thrower.gd` receives active player velocity at launch cue; trajectory preview incorporates current player velocity.
  - **One system owner**: `MainGrenadeRuntime` (`scripts/runtime/main_grenade_runtime.gd`).
  - **Systems that must not change**: `FragGrenade` physics simulation, collision layers.
  - **Focused proof**: Verification that throwing while moving results in greater throw distance than throwing while stationary.

---

### Defect 8: Close-Quarters Ballistic Convergence Failure

- **Severity**: HIGH (Ballistics & Hit Authority Consistency)
- **File & Line Numbers**: `scripts/camera/camera_aim_resolver.gd` & `tools/ballistic_convergence_regression.gd`
- **Verbatim Error Output**:
  ```
  ERROR: BALLISTIC_CONVERGENCE_REGRESSION: blue sight acquires the animated head area instead of scenery behind it
  HEAD_SHOT_METRIC region= damage=0.0 health=100.0
  ```
- **Reproduction Steps**:
  1. Run `tools/ballistic_convergence_regression.gd`.
  2. Place target dummy at 1.8m distance directly in front of operator.
  3. Aim camera reticle directly at dummy head.
  4. Fire weapon.
  5. Observe ray misses head hurtbox and hits background scenery.
- **Technical Explanation**:
  At distances under 2.0 meters, the lateral parallax between the third-person camera ray and the muzzle ray does not converge cleanly onto the animated mannequin head hitbox. The ray from the muzzle either clips past the ear or hits the upper shoulder because the convergence distance is clamped too far out.
- **Rule 2 Translation Card**:
  - **Player intent**: At point-blank and close quarters (<2m), bullets must strike the target hurtbox aligned with the center reticle.
  - **Acceptance rule**: Raycast convergence dynamically casts a sight ray from the camera, and if a valid hurtbox is intersected within 2m, the muzzle convergence point locks to that intersection point.
  - **One system owner**: `CameraAimResolver` (`scripts/camera/camera_aim_resolver.gd`).
  - **Systems that must not change**: `SocomShotAuthority`, `SocomAnatomicalHitResolver`.
  - **Focused proof**: `tools/ballistic_convergence_regression.gd` passes with `damage > 0.0` and `region == "HEAD"`.

---

### Defect 9: Regression Suite Test Harness Flaws & Stale Assertions

- **Severity**: MEDIUM (Tooling & Continuous Verification)
- **Affected Files**:
  - `tools/weapon_auto_reload_regression.gd:221` (Format string syntax error `%s` on array)
  - `tools/weapon_auto_reload_regression.gd:112` (`FakeWeaponController` lacks `can_reload()`)
  - `tools/weapon_fire_regression.gd:61` (Instant weight snap to 1.0 failing smooth transition assertion)
  - `tools/ballistic_reference_reticle_regression.gd:43` (Stale U-shaped arc assertion vs circular reticle)
  - `tools/mixed_weapon_roster_regression.gd:48` (`12_gauge_pump` missing from public roster)
- **Technical Explanation**:
  Several test scripts in `tools/` fail not because runtime features are broken, but because the test harness either:
  1. Contains mock object API mismatches (`FakeWeaponController` missing `can_reload()` which `WeaponReloadCoordinator:112` requires).
  2. Asserts legacy visual representations (e.g. asserting `draw_arc` is absent when the design contract explicitly reinstated the SOCOM arc reticle).
  3. Has a syntax formatting error when printing test failure arrays in Godot 4.7.
- **Remediation**:
  Update the test harness mocks to accurately match current node interfaces and align test assertions with the canonical gameplay contracts.

---

## 4. Implementation & Remediation Roadmap

For downstream implementation agents, the fixes should proceed in the following order:

1. **Phase 1: Core Ballistics & Posture Parity (`weapon_ballistics.gd`)**
   - Implement prone branches in `_bloom_per_shot_for()`, `_maximum_bloom_for()`, and `_recovery_speed_for()`.
   - Correct `crouch_bloom_per_shot_deg` to ensure crouch spread is strictly tighter than standing spread across all shots in a burst.
   - Update `tools/weapon_stance_bloom_regression.gd` to verify monotonic stance accuracy: `Prone < Crouch < Stand`.

2. **Phase 2: Firing Policy & Burst Commitment (`weapon_fire_mode_policy.gd`)**
   - Refactor burst mode in `weapon_fire_mode_policy.gd` so that initiating a burst sets a committed state that runs to completion regardless of brief trigger releases.
   - Ensure `cancel_pending_burst()` is called on weapon swap or reload, but not on premature trigger release.

3. **Phase 3: Reload & Mobility Agency (`weapon_reload_coordinator.gd`, `player_ammunition_inventory.gd`)**
   - Enable weapon swap (`equip_carried_slot`) during reload by canceling the reload action and switching immediately to sidearm.
   - Wire mobility interrupts (sprint, dive, roll) into `WeaponReloadCoordinator` so player agency is never locked for 2.2s.
   - Add closed-bolt +1 chambering support to `PlayerAmmunitionInventory.reload_weapon()`.

4. **Phase 4: Close-Quarters Convergence & Grenade Kinematics**
   - Adjust `CameraAimResolver` close-quarters convergence point to resolve hurtbox collisions within 2m.
   - Refactor grenade throw sequence in `main_grenade_runtime.gd` to decelerate rather than instantly zero operator velocity, enabling momentum inheritance in `tactical_grenade_thrower.gd`.
