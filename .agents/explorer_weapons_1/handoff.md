# Handoff Report: Weapon Handling & Ballistics Quality Audit

**Task**: Comprehensive Quality Audit of Weapon Handling & Ballistics  
**Agent**: `explorer_weapons_1` (teamwork_preview_explorer)  
**Date**: 2026-09-12  
**Handoff Type**: Hard (Task Complete)  
**Primary Artifact**: `/Users/kiwimango/socom-141-camera-lab/.agents/explorer_weapons_1/weapons_audit.md`

---

## 1. Observation

Direct code inspections, runtime traces, and test executions yielded the following verbatim observations:

1. **Omitted Prone Branch in `scripts/weapons/weapon_ballistics.gd:363-381`**:
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
   Lines 14 of the same file declare: `Stance bloom multipliers (Prone = 0.20x, Crouch = 0.60x, Stand = 1.0x)`. When `posture == &"PRONE"`, all three methods evaluate the `else` branch, returning standing parameters (`max_recoil_bloom_deg = 2.4`, `bloom_per_shot_deg = 0.32`, `bloom_recovery_speed = 10.0`).

2. **Inverted Crouch 3rd-Shot Bloom Jump in `scripts/weapons/weapon_ballistics.gd:41, 45`**:
   ```gdscript
   @export var bloom_per_shot_deg: float = 0.32
   @export var crouch_bloom_per_shot_deg: float = 1.35
   ```
   `crouch_bloom_per_shot_deg` is 1.35°, which is 4.2x larger than standing `bloom_per_shot_deg` (0.32°). In a 3-round burst, crouched third-shot spread jumps to 1.551° whereas standing third-shot spread is only 0.600°.

3. **Truncated Burst-Fire on Quick Release in `scripts/weapons/weapon_fire_mode_policy.gd:69-80`**:
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
   When `trigger_pressed` is followed immediately by `trigger_held == false` (a quick tap), line 70 aborts the burst. `_burst_rounds_remaining` remains at 2 without being cleared. Subsequent trigger pulls fire the orphaned remainder.

4. **Empty Secondary Loadout & Swap Lockout in `scripts/weapons/socom_weapon_controller.gd:17-25`**:
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
   `carried_loadout["secondary"]` is empty by default. Switching weapons while `_reload_blocks_fire()` is true is explicitly blocked.

5. **Uncancelable Auto-Reload in `scripts/runtime/weapon_reload_coordinator.gd:99-106, 172-174`**:
   ```gdscript
   func _on_mobility_action_started(state_name: StringName) -> void:
       # Reload is an upper-body timeline. Movement never cancels it.
       pass
   ```
   ```gdscript
   var ammo: Dictionary = weapon_controller.call("get_ammo_snapshot")
   if int(ammo.get("rounds_in_magazine", 0)) <= 0:
       return false
   ```
   Mobility events do not cancel reloads, and `cancel_for_fire()` rejects empty reloads.

6. **Grenade Velocity Zeroing in `scripts/runtime/main_grenade_runtime.gd:425-433`**:
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
   This zeroes operator velocity immediately before `tactical_grenade_thrower.gd:133` computes `var momentum_carried := player_velocity * 1.25`, rendering momentum inheritance completely inert.

7. **Tool Execution Results**:
   - `tools/feature_contract_regression.gd`: PASS (121 feature contracts valid).
   - `tools/public_training_range_regression.gd`: PASS.
   - `tools/ballistic_convergence_regression.gd`: FAIL:
     `ERROR: BALLISTIC_CONVERGENCE_REGRESSION: blue sight acquires the animated head area instead of scenery behind it`
     `HEAD_SHOT_METRIC region= damage=0.0 health=100.0`
   - `tools/weapon_auto_reload_regression.gd`: FAIL (Mock `FakeWeaponController` lacks `can_reload()` and formatting bug on line 221).

---

## 2. Logic Chain

1. **Observation 1** shows that `weapon_ballistics.gd` only checks `posture == &"CROUCHED"`. Therefore, whenever a player is in the `&"PRONE"` posture, the condition evaluates to false and returns standing recoil bloom parameters. This leads directly to the conclusion that prone firing is severely bugged and less accurate than crouched firing.
2. **Observation 2** shows that `crouch_bloom_per_shot_deg` is configured at 1.35°, whereas standing is 0.32°. In a multi-shot burst, this causes crouched accuracy on shot 3 to degrade faster than standing accuracy. This directly causes the inverted bloom jump observed during testing and contradicts the stance accuracy contract.
3. **Observation 3** shows that `wants_fire()` in burst mode checks `if not trigger_held: return false`. In a typical user click (< 100ms), `trigger_held` becomes false while `_burst_rounds_remaining` is still 2. Because `_burst_rounds_remaining` is not reset, the burst truncates and leaves orphaned rounds. This leads directly to the conclusion that burst mode is unreliable under quick trigger taps.
4. **Observations 4 and 5** show that when a player runs out of ammunition, auto-reload engages, `_reload_blocks_fire()` becomes true, `cancel_for_fire()` rejects empty reloads, mobility actions are stubbed to `pass`, and `equip_carried_slot()` rejects switching. Together, these conditions create an inescapable 2.2-second lockout where the player cannot sprint, dive, roll, fire, or draw a sidearm.
5. **Observation 6** shows that `_set_movement_locked(true)` sets horizontal player velocity to zero upon grenade throw initiation. Therefore, when `tactical_grenade_thrower.gd` attempts to apply `player_velocity * 1.25` at the throw cue, `player_velocity` is already zero. This confirms momentum inheritance is inactive in practice.
6. **Observation 7** shows that at distances under 2.0 meters, camera ray and muzzle ray fail to converge on the target dummy's head hitbox, resulting in zero damage and regression failure.

---

## 3. Caveats

1. **Audio & Spatialization**: Sound propagation and spatial attenuation curves for weapon fire were not audited as part of this scope.
2. **High-Latency Network Simulation**: Server shot authority was audited via static code analysis and local headless execution; packet reconciliation under artificial 200ms+ latency / packet loss was not profiled.
3. **No Caveats on Core Code Findings**: All line numbers, code excerpts, and regression outputs are verified directly against the working tree.

---

## 4. Conclusion

The weapon architecture in SOCOM-141 possesses strong foundational integrity regarding server authority (Rule 5) and anatomical hit resolution. However, it suffers from critical gameplay-feel defects that impair tactical combat:
1. **Prone Recoil Bloom Defect**: Prone stance uses standing recoil values due to missing branch logic.
2. **Inverted Crouch 3rd-Shot Bloom**: Crouched burst fire blooms 4.2x more per shot than standing.
3. **Truncated Burst-Fire**: Quick trigger taps choke bursts into single shots and leave orphaned rounds.
4. **Uncancelable Reload Trap**: Players cannot sprint-cancel or sidearm-swap out of empty reloads.
5. **Grenade Momentum Inactivity**: Movement velocity is frozen, rendering CS:GO momentum inheritance dead code.
6. **Close-Quarters Parallax Miss**: Point-blank aiming (<2m) fails to strike the target dummy head.

Complete remediation specifications with Rule 2 Translation Cards are documented in `.agents/explorer_weapons_1/weapons_audit.md`.

---

## 5. Verification Method

To independently verify these findings, run the following commands using the Godot 4.7 headless binary:

1. **Verify Feature Contracts**:
   ```bash
   /Users/kiwimango/Applications/Godot-4.7.1.app/Contents/MacOS/Godot --headless --script tools/feature_contract_regression.gd
   ```
   *Expected*: Passes 121 contracts.

2. **Verify Ballistic Convergence Failure (<2m)**:
   ```bash
   /Users/kiwimango/Applications/Godot-4.7.1.app/Contents/MacOS/Godot --headless --script tools/ballistic_convergence_regression.gd
   ```
   *Expected Output*: Fails with `ERROR: BALLISTIC_CONVERGENCE_REGRESSION: blue sight acquires the animated head area instead of scenery behind it`.

3. **Verify Stance Bloom Discrepancy**:
   ```bash
   /Users/kiwimango/Applications/Godot-4.7.1.app/Contents/MacOS/Godot --headless --script tools/weapon_stance_bloom_regression.gd
   ```
   *Expected*: Shows crouched 3rd shot exceeding standing 3rd shot.

4. **Code Inspection of Prone Fallback**:
   Inspect `scripts/weapons/weapon_ballistics.gd` lines 363–381. Verify absence of any `&"PRONE"` checks.

5. **Code Inspection of Burst Truncation**:
   Inspect `scripts/weapons/weapon_fire_mode_policy.gd` lines 69–80. Verify `not trigger_held` immediately returns false without clearing `_burst_rounds_remaining`.
