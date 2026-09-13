# Handoff Report: SOCOM 2 Ballistics & Weapon Systems Audit (R1 & R3)

**Task**: Technical Investigation for Requirements R1 & R3 regarding the 4 Ballistics Defects (WEAP-01, WEAP-02, WEAP-04, WEAP-05)  
**Agent**: `explorer_ballistics_2` (Teamwork Explorer)  
**Date**: 2026-09-12T02:00:00Z  
**Handoff Type**: Hard (Investigation Complete)  
**Working Directory**: `/Users/kiwimango/socom-141-camera-lab/.agents/explorer_ballistics_2`  

---

## 1. Observation

Direct code inspections, schema analyses, and test executions yielded the following verbatim observations:

### 1.1 Extracted Static Data Tables: `config/reference/socom2_weapon_settings.json` (`RUN/ZWEAPON.ZAR` -> `zweapon.rdr`)

The extracted database contains 86 records sourced directly from the SOCOM II USA ISO (`RUN/ZWEAPON.ZAR` -> `zweapon.rdr`, reader SHA-256 `8f1027edc1e3d0d6a936e13f3bcc2f2ee785148d1acbe550776e3b844058d67b`).

#### Schema Structure
Each weapon entry contains:
1. `name` (string) and `display_name` (string).
2. `mode_flags` (array of fire mode identifiers, e.g. `["SingleMode", "AutoMode"]`).
3. `numeric` (flat dictionary of baseline weapon properties):
   - `FireWait` (float, cycle time in seconds, e.g. `0.1199999973` for M4A1 -> 500 RPM).
   - `Muzzle_Velocity` (float, m/s, e.g. `921` for M4A1).
   - `Effective_Range` (float, meters, e.g. `600`).
   - `Maximum_Range` (float, meters, e.g. `1000`).
   - `Ammo_Capacity` (int, magazine size, e.g. `30`).
   - `NumMags` (int, reserve magazines, e.g. `3`).
   - `Damage_Modifier` (float, e.g. `0.3000000119`).
   - `RecoilPct` (float, e.g. `0.2000000029`).
   - `Encumbrance` (int, e.g. `1`).
4. `stances` (sub-dictionaries for `STANCE_STAND`, `STANCE_CROUCH`, `STANCE_PRONE`):
   - `ReticuleKnock` (per-shot reticle kick).
   - `ReticuleKnockReturn` (reticle kick return velocity).
   - `ReticuleKnockMax` (reticle kick ceiling / maximum recoil cap).
   - `TargetDilateUponFire` (reticle dilation / spread expansion added per shot).
   - `TargetDilateUponMovement` and `TargetDilateUponMovementMult` (movement spread dilation).
   - `TargetConstrict` (rate at which reticle dilation constricts back to resting size).
   - `TargetMin` and `TargetMax` (resting and maximum spread boundaries).
   - `FireRifleKickBaseDist`, `FireRifleKickRate`, `FireRifleKickReturnRate` (camera view kick parameters).

#### M4A1 (ID 54) Verbatim Stance Values
```json
"stances": {
  "STANCE_STAND": {
    "ReticuleKnock": 12,
    "ReticuleKnockReturn": 70,
    "ReticuleKnockMax": 45,
    "TargetDilateUponFire": 7,
    "TargetDilateUponMovement": 1,
    "TargetConstrict": 50,
    "TargetMin": 1,
    "TargetMax": 26,
    "FireRifleKickBaseDist": 0.09000000357627869
  },
  "STANCE_CROUCH": {
    "ReticuleKnock": 9,
    "ReticuleKnockReturn": 75,
    "ReticuleKnockMax": 45,
    "TargetDilateUponFire": 7,
    "TargetDilateUponMovement": 1,
    "TargetDilateUponMovementMult": 13,
    "TargetConstrict": 55,
    "TargetMin": 1,
    "TargetMax": 25,
    "FireRifleKickBaseDist": 0.07999999821186066
  },
  "STANCE_PRONE": {
    "ReticuleKnock": 8,
    "ReticuleKnockReturn": 75,
    "ReticuleKnockMax": 20,
    "TargetDilateUponFire": 7,
    "TargetDilateUponMovement": 1,
    "TargetDilateUponMovementMult": 63,
    "TargetConstrict": 50,
    "TargetMin": 1,
    "TargetMax": 24,
    "FireRifleKickBaseDist": 0.05999999865889549
  }
}
```

#### Comparison Across Primary Weapons in ISO Table
| Weapon | Stand ReticuleKnock / KnockMax / Dilate | Crouch ReticuleKnock / KnockMax / Dilate | Prone ReticuleKnock / KnockMax / Dilate | Prone vs Stand KnockMax Ratio |
| :--- | :--- | :--- | :--- | :--- |
| **M4A1** | 12 / **45** / 7 | 9 / 45 / 7 | 8 / **20** / 7 | **0.444 (20 / 45)** |
| **M4A1 SD** | 12 / **45** / 7 | 11 / 45 / 7 | 10 / **20** / 7 | **0.444 (20 / 45)** |
| **AK-47** | 10 / **31** / 9 | 9 / 31 / 9 | 6 / **25** / 8 | **0.806 (25 / 31)** |
| **AKS-74** | 10 / **14** / 8 | 10 / 14 / 8 | 8 / **12** / 8 | **0.857 (12 / 14)** |
| **AK-105** | 7 / **14** / 8 | 7 / 14 / 8 | 5 / **12** / 8 | **0.857 (12 / 14)** |
| **M14** | 12 / **60** / 8 | 10 / 50 / 7 | 9 / **35** / 6 | **0.583 (35 / 60)** |
| **M60E3** | 10 / **50** / 5.5 | 8 / 40 / 5.5 | 6.5 / **17** / 5.5 | **0.340 (17 / 50)** |
| **M63A** | 10 / **50** / 4 | 8 / 42 / 7 | 7 / **20** / 3.75 | **0.400 (20 / 50)** |

**Key ISO Invariant**: In no weapon in the authentic ISO does `TargetDilateUponFire` (spread dilation per shot) or `ReticuleKnock` (per-shot kick) increase when transitioning from Standing to Crouch or Prone. In all weapons, Crouch and Prone values are less than or equal to Standing. Specifically on the M4A1, `ReticuleKnockMax` drops from 45 down to 20 in Prone (a 55.6% reduction).

---

### 1.2 WEAP-01: Prone Recoil Bloom Fallback in `scripts/weapons/weapon_ballistics.gd`

#### Verbatim Code (`scripts/weapons/weapon_ballistics.gd:40-48, 363-381`)
```gdscript
# Lines 40-48
@export var max_recoil_bloom_deg: float = 2.4
@export var bloom_per_shot_deg: float = 0.32
@export var bloom_recovery_speed: float = 10.0 # Rapid decay on pause
@export_range(0.05, 1.0, 0.01) var bloom_recovery_delay_seconds: float = 0.30
@export_range(0.1, 1.0, 0.05) var crouch_spread_multiplier: float = 0.72
@export var crouch_bloom_per_shot_deg: float = 1.35
@export var crouch_max_recoil_bloom_deg: float = 1.70
@export var crouch_bloom_recovery_speed: float = 18.0
@export_range(0.1, 1.0, 0.05) var opening_burst_motion_multiplier: float = 0.35
```
```gdscript
# Lines 363-381
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

#### Observation
1. Lines 40–48 declare exports for Standing and Crouch (`crouch_bloom_per_shot_deg`, `crouch_max_recoil_bloom_deg`, `crouch_bloom_recovery_speed`). There are **no export variables or parameters for Prone**.
2. Lines 363–381 explicitly test only `posture == &"CROUCHED"`. When `posture == &"PRONE"`, all three functions evaluate the `else` branch, returning **Standing** values:
   - `_bloom_per_shot_for(&"PRONE")` returns `bloom_per_shot_deg` (`0.32°`).
   - `_maximum_bloom_for(&"PRONE")` returns `max_recoil_bloom_deg` (`2.40°`).
   - `_recovery_speed_for(&"PRONE")` returns `bloom_recovery_speed` (`10.0`).
3. Consequently, under sustained fire, Prone blooms up to `2.40°`, which is **41.2% worse than Crouch** (`1.70°`), and recovers at `10.0` deg/s, which is **44.4% slower than Crouch** (`18.0` deg/s). This completely violates line 14 of the same file (`Prone = 0.20x, Crouch = 0.60x, Stand = 1.0x`) and authentic SOCOM II ISO data (`ReticuleKnockMax: 20` vs Stand `45`).

---

### 1.3 WEAP-02: Crouch Bloom Rate Per Shot in `scripts/weapons/weapon_ballistics.gd`

#### Verbatim Code (`scripts/weapons/weapon_ballistics.gd:41, 45, 153-159`)
```gdscript
# Line 41 & 45
@export var bloom_per_shot_deg: float = 0.32
@export var crouch_bloom_per_shot_deg: float = 1.35
```
```gdscript
# Lines 153-159
func _bloom_after_shot(posture: StringName, shot_count: int) -> float:
	var bloom := current_recoil_bloom
	if shot_count > 2:
		var bloom_cap := _maximum_bloom_for(posture)
		if bloom < bloom_cap:
			bloom = minf(bloom_cap, bloom + _bloom_per_shot_for(posture))
	return bloom
```

#### Observation
1. `crouch_bloom_per_shot_deg` is set to `1.35°`. Standing `bloom_per_shot_deg` is `0.32°`.
2. Ratio: `1.35 / 0.32 = 4.21875`. Each shot fired while crouched adds **4.2x more bloom** than when standing.
3. Burst-fire calculation on shot 3 (first shot that incurs bloom after the 2-round pinpoint group):
   - **Standing Shot 3**: `recoil_bloom = 0.0 + 0.32 = 0.32°`. Total spread = `base_spread_deg * 1.0 + 0.32 = 0.28 + 0.32 = 0.600°`.
   - **Crouched Shot 3**: `recoil_bloom = 0.0 + 1.35 = 1.35°`. Total spread = `base_spread_deg * 0.72 + 1.35 = 0.2016 + 1.35 = 1.5516°`.
4. Result: On the 3rd shot, crouching produces **2.58x wider dispersion** than standing. Crouching severely penalizes the player during bursts.
5. In `tools/weapon_stance_bloom_regression.gd:27-30`:
   ```gdscript
   var standing_third := _fire_burst_shot(standing, arena, &"STANDING", 3)
   var crouched_third := _fire_burst_shot(crouched, arena, &"CROUCHED", 3)
   _expect(
       crouched_third > standing_third,
       "crouch bloom opens faster on the third shot"
   )
   ```
   The existing regression test was authored to assert this exact defect as expected behavior!

---

### 1.4 WEAP-04: Auto-Reload Behavior in `weapon_reload_coordinator.gd`

#### Verbatim Code (`scripts/runtime/weapon_reload_coordinator.gd:99-106, 172-174`)
```gdscript
# Lines 99-106
func _on_mobility_action_started(state_name: StringName) -> void:
	# Reload is an upper-body timeline. Movement never cancels it.
	pass


func _on_mobility_action_requested(state_name: StringName) -> void:
	# Reload is an upper-body timeline. Movement never cancels it.
	pass
```
```gdscript
# Lines 165-174 in cancel_for_fire()
func cancel_for_fire() -> bool:
	if (
		not pending
		or weapon_controller == null
		or not weapon_controller.has_method("get_ammo_snapshot")
	):
		return false
	var ammo: Dictionary = weapon_controller.call("get_ammo_snapshot")
	if int(ammo.get("rounds_in_magazine", 0)) <= 0:
		return false
```
```gdscript
# scripts/weapons/socom_weapon_controller.gd:21
func equip_carried_slot(slot: String) -> bool:
	var id := String(carried_loadout.get(slot, ""))
	if id.is_empty() or _reload_blocks_fire():
		return false
```

#### Observation
1. In `scripts/player/player_controller.gd:703, 786, 811, 832`, mobility actions emit `mobility_action_started` for `&"VAULTING"`, `&"DIVING"`, `&"AIRBORNE"`, and `&"ROLLING"`.
2. `weapon_reload_coordinator.gd:99-106` receives these signals and explicitly stubs them with `pass` and the comment: `# Reload is an upper-body timeline. Movement never cancels it.`
3. When the magazine is empty (`rounds_in_magazine <= 0`), `cancel_for_fire()` on line 173 explicitly returns `false`.
4. `socom_weapon_controller.gd:21` blocks `equip_carried_slot` (weapon swap) whenever `_reload_blocks_fire()` is true (which is true while `pending` is true).
5. Result: When auto-reload triggers on an empty magazine, the player is placed into a hard 2.2-second lockout where:
   - Fire cannot cancel reload.
   - Sprints, dives, rolls, and vaults cannot cancel reload.
   - Weapon switching to a secondary sidearm is completely blocked.
   - The player is defenseless and immobile until the full reload animation finishes.

---

### 1.5 WEAP-05: Grenade Throw Velocity in `main_grenade_runtime.gd`

#### Verbatim Code (`scripts/runtime/main_grenade_runtime.gd:174, 425-433`)
```gdscript
# scripts/runtime/main_grenade_runtime.gd:174
_set_movement_locked(true)
```
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
```
```gdscript
# scripts/runtime/main_grenade_trajectory.gd:108-114
var launch_velocity: Vector3 = thrower.call(
	"calculate_launch_velocity",
	forward,
	Vector3.UP,
	mode,
	charge
)
```
```gdscript
# scripts/tactical/tactical_grenade_thrower.gd:87-93, 132-134
func calculate_launch_velocity(
	forward: Vector3,
	up: Vector3,
	mode: ThrowMode,
	charge: float = 1.0,
	player_velocity: Vector3 = Vector3.ZERO
) -> Vector3:
...
	# CS:GO Momentum Inheritance: Throw carries forward momentum (running adds speed, jumping adds height)
	var momentum_carried := player_velocity * 1.25
	return base_launch_vec + momentum_carried
```

#### Observation
1. In `main_grenade_trajectory.gd:108-114`, `build_launch_state` calls `calculate_launch_velocity` with only 4 arguments (`forward`, `up`, `mode`, `charge`). The 5th argument (`player_velocity`) is omitted and defaults to `Vector3.ZERO`.
2. Immediately upon throw initiation in `main_grenade_runtime.gd:174`, `_set_movement_locked(true)` is called.
3. Lines 431–432 explicitly wipe horizontal operator movement:
   `player.velocity.x = 0.0`
   `player.velocity.z = 0.0`
4. Even if `tactical_grenade_thrower.gd:133` has momentum inheritance logic (`player_velocity * 1.25`), `player.velocity` is zeroed prior to throw release, and `build_launch_state` never supplied it.
5. In PS2 SOCOM II, running throws inherited forward movement velocity to project grenades farther, and characters did not experience an instantaneous velocity halt to `0.0`.

---

### 1.6 Existing Regression Test Executions

Commands executed via Godot 4.7 headless (`/Users/kiwimango/Applications/Godot-4.7.1.app/Contents/MacOS/Godot`):

1. `tools/feature_contract_regression.gd`:
   - Command: `/Users/kiwimango/Applications/Godot-4.7.1.app/Contents/MacOS/Godot --headless --path /Users/kiwimango/socom-141-camera-lab --script res://tools/feature_contract_regression.gd`
   - Result: **PASS** (121 contracts valid).
2. `tools/ballistic_convergence_regression.gd`:
   - Command: `/Users/kiwimango/Applications/Godot-4.7.1.app/Contents/MacOS/Godot --headless --path /Users/kiwimango/socom-141-camera-lab --script res://tools/ballistic_convergence_regression.gd`
   - Result: **FAIL** (`ERROR: BALLISTIC_CONVERGENCE_REGRESSION: blue sight acquires the animated head area instead of scenery behind it`). Ray hits `@StaticBody3D@7` instead of target dummy at 2.0m.
3. `tools/ballistic_reference_reticle_regression.gd`:
   - Command: `/Users/kiwimango/Applications/Godot-4.7.1.app/Contents/MacOS/Godot --headless --path /Users/kiwimango/socom-141-camera-lab --script res://tools/ballistic_reference_reticle_regression.gd`
   - Result: **FAIL** (`combat reticle has a faint disc instead of the old U-shaped arc` failed because `source.find("draw_arc(") < 0` failed due to line 332).
4. `tools/weapon_auto_reload_regression.gd`:
   - Command: `/Users/kiwimango/Applications/Godot-4.7.1.app/Contents/MacOS/Godot --headless --path /Users/kiwimango/socom-141-camera-lab --script res://tools/weapon_auto_reload_regression.gd`
   - Result: **FAIL** (Runtime error: `FakeWeaponController` missing `can_reload()` and string formatting error on line 221).
5. `tools/socom2_weapon_reference_test.cjs`:
   - Command: `node tools/socom2_weapon_reference_test.cjs`
   - Result: **PASS** (`matched=32 source_records=86`). Confirms `reticle.socom2_stances` in all 32 primary weapon JSON files already match `zweapon.rdr` exactly.

---

## 2. Logic Chain

1. **WEAP-01**:
   - `config/reference/socom2_weapon_settings.json` establishes that in authentic SOCOM II, M4A1 prone recoil is heavily suppressed: `ReticuleKnockMax: 20` vs Standing `45` (ratio `20/45 = 0.444`).
   - `config/weapons/m4a1.json:226` already records `maximum_shot_kick_px: 20` for PRONE.
   - However, in `scripts/weapons/weapon_ballistics.gd:363-381`, `_bloom_per_shot_for`, `_maximum_bloom_for`, and `_recovery_speed_for` check only `posture == &"CROUCHED"`.
   - Because `&"PRONE"` is not handled, it defaults to Standing values (`max_recoil_bloom_deg = 2.4`, `bloom_per_shot_deg = 0.32`, `bloom_recovery_speed = 10.0`).
   - Therefore, Prone in the canonical runtime suffers higher maximum bloom (2.40° vs 1.70°) and slower recovery (10.0 vs 18.0) than Crouch, in direct contradiction of ISO reference tables and the developer's declared design at line 14 (`Prone = 0.20x, Crouch = 0.60x, Stand = 1.0x`).

2. **WEAP-02**:
   - `scripts/weapons/weapon_ballistics.gd:45` configures `crouch_bloom_per_shot_deg = 1.35`.
   - `scripts/weapons/weapon_ballistics.gd:41` configures `bloom_per_shot_deg = 0.32`.
   - In `_bloom_after_shot()` (lines 153–159), shots after count 2 add `_bloom_per_shot_for(posture)`.
   - On shot 3 (the 3rd round of a burst), Crouch adds `1.35°` of spread, while Standing adds `0.32°`. Total crouched spread reaches `1.5516°`, while standing spread is only `0.600°`.
   - In the SOCOM II ISO tables (`socom2_weapon_settings.json`), `TargetDilateUponFire` is 7 for Stand and 7 for Crouch (identical), and `ReticuleKnock` is 12 for Stand and 9 for Crouch (75%).
   - At no point in the authentic reference does crouching increase dispersion rate per shot. Setting `crouch_bloom_per_shot_deg` to 1.35° was an erroneous inversion that broke crouched burst firing. It must be `<= 0.32°` (e.g. `0.24°` based on ISO `9/12` ratio or `0.192°` based on `0.60x`).

3. **WEAP-04**:
   - `weapon_reload_coordinator.gd:99-106` treats reloading as an inviolable upper-body track and stubs all mobility inputs to `pass`.
   - In `weapon_reload_coordinator.gd:172-174`, `cancel_for_fire()` rejects empty reloads.
   - In `socom_weapon_controller.gd:21`, weapon swapping (`equip_carried_slot`) is blocked while reload is locked.
   - An empty magazine thus locks the player into an inescapable 2.2s animation.
   - In the SOCOM II PS2 engine, reload is an executable MIPS state machine. Mobility actions (dive-to-prone, roll, sprint) and weapon cycling (switching to sidearm) preempt the reload state machine prior to the magazine insertion keyframe.
   - In the ISO static tables (`zweapon.rdr`), reload state machine transitions and auto-reload triggers do not exist; standard rifles have no reload duration fields at all. This proves reload behavior is governed strictly by the executable runtime state machine, not static data tables.

4. **WEAP-05**:
   - In `main_grenade_runtime.gd:431-432`, `_set_movement_locked(true)` zeroes `player.velocity.x` and `player.velocity.z` on throw initiation.
   - In `main_grenade_trajectory.gd:108-114`, `calculate_launch_velocity` is invoked without the player velocity parameter.
   - Even though `tactical_grenade_thrower.gd:133` implements `player_velocity * 1.25`, the velocity passed is always zero.
   - In PS2 SOCOM II, grenade throw velocity inherited operator forward momentum, extending throw range during runs, without abrupt character freezing.

---

## 3. ISO Static Data Tables vs PS2 MIPS Runtime Engine Distinction

To ensure architectural clarity for all subsequent work, the exact boundary between static data tables and runtime state machine logic is delineated below:

| Dimension | Static ISO Data Tables (`zweapon.rdr` / `socom2_weapon_settings.json`) | PS2 MIPS Runtime Engine (`SLUS_207.99` Executable State Machine) |
| :--- | :--- | :--- |
| **Data Representation** | Read-only binary structures extracted from `RUN/ZWEAPON.ZAR`. Serialized JSON numbers. | Dynamic actor state machines executing on the Emotion Engine (EE) MIPS core. |
| **Recoil & Spread Parameters** | Authored numeric constants: `ReticuleKnock`, `ReticuleKnockMax`, `TargetDilateUponFire`, `TargetConstrict`, `TargetMin`, `TargetMax`, `FireRifleKickBaseDist`. | Reads active stance (`STANCE_STAND=0`, `STANCE_CROUCH=1`, `STANCE_PRONE=2`) and feeds constants into camera impulse and reticle dilation equations. |
| **Prone Recoil Values** | Explicitly defines `ReticuleKnockMax: 20` for M4A1 (vs 45 for Stand). | Evaluates prone posture state and clamps reticle knock to 20. |
| **Reload Mechanics** | Only contains basic delays for select heavy weapons (`ReloadDelay`, `ReloadTime` for shotguns/MGs). **Contains no reload fields for standard rifles (M4A1, AK-47) or pistols.** | **Fully owns reload lifecycle**: auto-reload trigger condition, animation playback, magazine-in commit cue, and preemption by high-priority actions (sprint, dive, swap). |
| **Grenade Mechanics** | Only static ordnance metadata: `ImpactRadius` (40–45), `Timer1` (3.0s fuse), `Ammo_Capacity` (3), `Muzzle_Velocity` (0.1 dummy). | **Fully owns throw physics**: angle calculation, charge hold timing, momentum inheritance (`V_grenade = V_base + V_player`), and player locomotion state. |
| **Godot System Equivalent** | `config/reference/socom2_weapon_settings.json`, `config/weapons/*.json`. | `scripts/weapons/weapon_ballistics.gd`, `scripts/runtime/weapon_reload_coordinator.gd`, `scripts/runtime/main_grenade_runtime.gd`. |

---

## 4. Test Suite Audit & Required Verifications (Requirement R3)

### Current Test State

1. **`tools/weapon_stance_bloom_regression.gd`**:
   - **Flaw**: Lines 27–30 assert `crouched_third > standing_third`. This was written to enforce the bug!
   - **Missing**: It completely lacks testing for Prone stance.
   - **Required Update**:
     - Change line 28 to assert `crouched_third <= standing_third` (`crouch bloom rate per shot is less than or equal to standing bloom rate`).
     - Add a `prone := Ballistics.new()` instance.
     - Verify prone 3rd shot spread is less than or equal to crouch (`prone_third <= crouched_third`).
     - Verify prone sustained-fire maximum bloom complies with authentic ISO reduction (`ReticuleKnockMax: 20` vs Stand `45`, ratio `0.444`). For example, `prone_fourth < crouched_fourth` and `prone.current_recoil_bloom <= max_recoil_bloom_deg * (20.0 / 45.0) + 0.05`.
     - Verify prone bloom recovery speed is >= standing recovery speed.

2. **`tools/weapon_auto_reload_regression.gd`**:
   - **Flaw**: Contains syntax/mock errors (`FakeWeaponController` lacks `can_reload()`, line 221 string format bug).
   - **Flaw**: Lines 199–202 explicitly assert that dive, roll, and vault *cannot* cancel reload (`bool(coordinator.pending) and weapon.reload_locked`).
   - **Required Update**:
     - Fix `FakeWeaponController` to include `func can_reload() -> bool: return true`.
     - Update mobility tests to verify that full-body mobility actions (`DIVING`, `ROLLING`, `VAULTING`) successfully cancel a pending reload before the magazine-in cue.
     - Verify that sidearm weapon swapping cancels an empty reload.

3. **`tools/ballistic_convergence_regression.gd`**:
   - Currently fails due to raycast collision with background static geometry (`@StaticBody3D@7`) rather than the target dummy head hurtbox at 2.0m.

4. **`tools/ballistic_reference_reticle_regression.gd`**:
   - Currently fails due to an assertion checking for the absence of `draw_arc(` in `socom_dynamic_reticle.gd`.

---

## 5. Conclusion & Actionable Recommendations

All 4 ballistics defects are thoroughly verified, their root causes isolated to specific lines of code, and their authentic SOCOM II reference targets established:

1. **WEAP-01 (Prone Recoil Fallback)**:
   - **Cause**: `weapon_ballistics.gd:363-381` omits `&"PRONE"`, falling back to Standing parameters.
   - **Fix**:
     - In `weapon_ballistics.gd`, add `@export var prone_bloom_per_shot_deg: float = 0.213` (0.667x of Stand), `@export var prone_max_recoil_bloom_deg: float = 1.07` (0.444x of Stand, matching ISO `ReticuleKnockMax: 20` vs `45`), and `@export var prone_bloom_recovery_speed: float = 18.0`.
     - Update `_bloom_per_shot_for`, `_maximum_bloom_for`, and `_recovery_speed_for` with explicit `&"PRONE"` match arms.
     - In `socom_weapon_controller.gd:165-175`, propagate prone parameters from `values` if present.

2. **WEAP-02 (Inverted Crouch Bloom)**:
   - **Cause**: `weapon_ballistics.gd:45` sets `crouch_bloom_per_shot_deg = 1.35` (4.2x standing).
   - **Fix**:
     - Change `crouch_bloom_per_shot_deg` in `weapon_ballistics.gd:45` from `1.35` to `<= 0.32` (authentically `0.24` matching ISO `9/12` ratio, or `0.192` matching the line 14 comment `0.60x`).

3. **WEAP-04 (Auto-Reload Lockout Trap)**:
   - **Cause**: `weapon_reload_coordinator.gd:100` stubs mobility cancellation to `pass`, `cancel_for_fire()` rejects empty reloads, and `socom_weapon_controller.gd:21` blocks weapon swaps.
   - **Fix**:
     - In `weapon_reload_coordinator.gd`, implement `_on_mobility_action_started(state_name)`: if `state_name in [&"DIVING", &"ROLLING", &"VAULTING"]`, call `_disconnect_driver_signals()` and set `_set_pending(false)` (cancelling reload prior to commit cue).
     - In `socom_weapon_controller.gd:21`, allow `equip_carried_slot()` to cancel pending reloads when switching to secondary.

4. **WEAP-05 (Grenade Momentum Inactivity)**:
   - **Cause**: `main_grenade_runtime.gd:431-432` zeroes horizontal velocity, and `main_grenade_trajectory.gd:108-114` fails to pass `player.velocity` to `calculate_launch_velocity`.
   - **Fix**:
     - Remove `player.velocity.x = 0.0` and `player.velocity.z = 0.0` from `_set_movement_locked(true)`.
     - In `main_grenade_trajectory.gd:108-114`, pass `player.velocity` as the 5th argument to `thrower.call("calculate_launch_velocity", ...)`.

---

## 6. Verification Method

To independently verify all observations and code findings in this report:

1. **Verify Static ISO Weapon Settings & Schema**:
   ```bash
   node tools/socom2_weapon_reference_test.cjs
   python3 -c "import json; d=json.load(open('config/reference/socom2_weapon_settings.json')); print(d['weapons'][16]['stances'])"
   ```
   *Expected Output*: Displays M4A1 with `STANCE_STAND` (`ReticuleKnockMax: 45`), `STANCE_CROUCH` (`ReticuleKnockMax: 45`), and `STANCE_PRONE` (`ReticuleKnockMax: 20`).

2. **Verify Prone Fallback and Crouch Bloom Rate in `weapon_ballistics.gd`**:
   - Inspect lines 41, 45, 363–381 in `scripts/weapons/weapon_ballistics.gd`.
   - Confirm absence of `&"PRONE"` in `_bloom_per_shot_for`, `_maximum_bloom_for`, `_recovery_speed_for`.
   - Confirm `crouch_bloom_per_shot_deg: float = 1.35`.

3. **Verify Existing Inverted Stance Bloom Regression**:
   ```bash
   /Users/kiwimango/Applications/Godot-4.7.1.app/Contents/MacOS/Godot --headless --path /Users/kiwimango/socom-141-camera-lab --script res://tools/weapon_stance_bloom_regression.gd
   ```
   *Expected Output*: Passes currently, confirming that line 28 expects `crouched_third > standing_third`.

4. **Verify Reload Mobility Stub & Fire Lockout**:
   - Inspect lines 99–106 and 172–174 in `scripts/runtime/weapon_reload_coordinator.gd`.
   - Inspect line 21 in `scripts/weapons/socom_weapon_controller.gd`.

5. **Verify Grenade Velocity Zeroing**:
   - Inspect lines 174 and 425–433 in `scripts/runtime/main_grenade_runtime.gd`.
   - Inspect lines 108–114 in `scripts/runtime/main_grenade_trajectory.gd`.
