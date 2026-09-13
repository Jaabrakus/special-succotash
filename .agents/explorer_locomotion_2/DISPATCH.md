## 2026-09-12T01:53:24Z
Read /Users/kiwimango/socom-141-camera-lab/ORIGINAL_REQUEST.md.
Your working directory is /Users/kiwimango/socom-141-camera-lab/.agents/explorer_locomotion_2.
Read docs/GAMEPLAY_INTENT_DICTIONARY.md, docs/GODOT_FEATURE_INTEGRATION_CONTRACT.md, and AGENTS.md.

Your mission is technical investigation for Requirement R1 regarding the 4 locomotion defects (LOC-01, LOC-03, LOC-04, LOC-07) against PS2 MIPS gameplay engine conventions and the Godot implementation:
1. Examine `scripts/player/player_controller.gd` and related locomotion scripts (`scenes/player/operator_player.tscn`, `scripts/player/operator_posture_layer.gd` etc.):
   - LOC-01: Lean peaking collision decoupling ("Ghost-Head") in `player_controller.gd:909-924`. Check how `CollisionShape3D` relates to mesh lean offset, how hurtbox parenting works in PS2 engine conventions vs Godot.
   - LOC-03: Zero air momentum conservation in `player_controller.gd:380-402`. Check airborne movement physics, ground acceleration/braking/reversal operating mid-air vs ballistic air momentum conservation in PS2 engine.
   - LOC-04: Missing jump cooldown & landing recovery in `player_controller.gd:799-813`. Check landing state machine and jump input buffering / bunny hopping prevention in PS2 engine conventions.
   - LOC-07: Forward vs backward speed ratio in `player_controller.gd:438-444`. Check 1:1 speed vs authentic backpedal speed reduction (~30-40% penalty).
2. Explicitly analyze and document the distinction between:
   - What data exists in static ISO data tables (`zweapon.rdr` / `socom2_weapon_settings.json` — which focus on weapon properties, ammo, gear slots)
   - What behaviors are governed by PS2 MIPS gameplay engine executable code (player state machine: locomotion states, jump physics, collision hurtbox parenting, lean kinematics, landing penalties).
3. Investigate related regression tests: `tools/jump_direction_combo_regression.gd`, `tools/directional_locomotion_phase_regression.gd`, `tools/mobility_regression.gd`, `tools/feature_contract_regression.gd`.
4. Produce a detailed report in `/Users/kiwimango/socom-141-camera-lab/.agents/explorer_locomotion_2/handoff.md` and send a message when complete.
