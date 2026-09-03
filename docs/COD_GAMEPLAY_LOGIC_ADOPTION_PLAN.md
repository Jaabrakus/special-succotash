# COD Gameplay Logic Adoption Plan

This plan adopts useful gameplay behavior from KisakCOD without trying to transplant its engine architecture. SOCOM-141 keeps authority in its existing Godot controllers and treats animation as authored timing and presentation.

## Phase 1: animation-timed reload commit (implemented)

Player result: ammunition becomes usable when the replacement magazine visibly seats, while the weapon remains unable to fire until the reload recovery ends.

Runtime flow:

1. The weapon configuration supplies reload visual event frames, including magazine_in.
2. The operator animation driver emits reload_commit_cue once when that frame is reached.
3. SocomWeaponReloadCoordinator validates the active reload generation and asks the existing SocomWeaponController to transfer ammunition.
4. The coordinator keeps reload_locked active until action_completed, so magazine seating and trigger recovery remain separate phases.
5. Cancellation before magazine_in leaves ammunition untouched. Cancellation after magazine_in keeps the already loaded ammunition.

The coordinator owns transaction timing. SocomWeaponController remains the only ammunition writer. Drivers without the new cue use action completion as a compatibility fallback.

## How to use it

1. In Gunsmith, author the reload_visual event frames for the weapon. Place magazine_in on the exact frame where the replacement magazine seats.
2. Save the weapon configuration and equip it normally. The current M4A1 configuration is already a valid reader path for the feature contract.
3. Play res://main.tscn and reload from a partially filled magazine. The HUD ammunition count should change at magazine_in, while firing should still report RELOADING through recovery.
4. Tune only the event frame to adjust commit timing. Do not add ammo writes to animation code.
5. Verify the focused behavior with:

       Godot --headless --path /Users/kiwimango/Documents/SOCOM-141 --script res://tools/weapon_auto_reload_regression.gd
       Godot --headless --path /Users/kiwimango/Documents/SOCOM-141 --script res://tools/gameplay_reload_completion_regression.gd

## Phase 2: explicit weapon action states

Model fire, rechamber, reload, interruption, and recovery as explicit weapon action phases. This gives animation, audio, reticle response, and fire gating one shared semantic state without moving shot authority out of the weapon controller.

## Phase 3: locomotion continuity

Adopt COD-style cycle continuity for direction and speed changes: preserve gait phase, blend directional changes, and reserve hard resets for true state boundaries. Keep SOCOM movement speeds, posture rules, and camera behavior.

## Phase 4: multiplayer correction presentation

Separate authoritative correction from visual smoothing. Preserve server truth immediately while easing only the rendered operator and weapon presentation where safe.

## Source and licensing boundary

KisakCOD is GPLv3. Use it to study behavior, state boundaries, and ordering, then implement those ideas independently in SOCOM-141. Do not copy its C++ implementation verbatim unless the receiving project and distribution are intentionally made GPL-compatible.
