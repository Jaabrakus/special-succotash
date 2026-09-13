# BRIEFING — 2026-09-12T01:57:30Z

## Mission
Technical investigation of Requirement R1 locomotion defects (LOC-01, LOC-03, LOC-04, LOC-07) against PS2 MIPS gameplay engine conventions and Godot implementation.

## 🔒 My Identity
- Archetype: explorer
- Roles: investigator, synthesizer
- Working directory: /Users/kiwimango/socom-141-camera-lab/.agents/explorer_locomotion_2
- Original parent: 69c1c26a-eb38-4153-8e60-987729cf55ef
- Milestone: Locomotion Technical Investigation (R1)

## 🔒 Key Constraints
- Read-only investigation — do NOT implement
- Preserve dirty worktree
- Every claim must be backed by exact file paths, line numbers, and verified code/behavior
- Adhere to AGENTS.md, GAMEPLAY_INTENT_DICTIONARY.md, and GODOT_FEATURE_INTEGRATION_CONTRACT.md

## Current Parent
- Conversation ID: 69c1c26a-eb38-4153-8e60-987729cf55ef
- Updated: not yet

## Investigation State
- **Explored paths**:
  - `scripts/player/player_controller.gd`: lines 16, 50-52, 94, 187-203, 368-417, 438-444, 584-615, 793-836, 890-950.
  - `scenes/player/operator_player.tscn`: lines 13-41 (sole CollisionShape3D, missing hurtbox rig).
  - `scripts/combat/socom_animated_hurtbox_rig.gd`: lines 1-100 (bone-bound Area3D hurtboxes).
  - `scripts/network/socom_network_operator.gd`: lines 578-592 (`_bind_animated_hurtboxes`).
  - `scripts/combat/socom_bullet_penetration.gd`: lines 105-135 (hitscan target resolution).
  - `scripts/player/operator_posture_layer.gd`: lines 88-91, 968-1015 (`_apply_full_body_peek`).
  - `config/reference/socom2_weapon_settings.json`: lines 1-50 (extracted `zweapon.rdr` ISO table fields).
  - Executed regressions: `tools/feature_contract_regression.gd`, `tools/mobility_regression.gd`, `tools/jump_direction_combo_regression.gd`, `tools/directional_locomotion_phase_regression.gd`, `tools/crouch_strafe_continuity_probe.gd`, `tools/lean_movement_latch_regression.gd`.
- **Key findings**:
  1. LOC-01: `CollisionShape3D` is static at `(0, height/2, 0)`. Mesh leans -33.9cm. `operator_player.tscn` lacks `SocomAnimatedHurtboxRig`. Bullet penetration tests `Player.CollisionShape3D`, granting complete "ghost-head" invulnerability when leaning out of cover, and visual geometry clips through walls.
  2. LOC-03: `player_controller.gd:380-402` applies ground acceleration (45 m/s²), braking (60 m/s²), reversal (90 m/s²), and 0-frame strafe snaps in mid-air. Zero ballistic momentum conservation.
  3. LOC-04: `MotionState.LANDING` does not dampen velocity in `_movement_speed()`, and `_try_begin_mobility_action()` does not check `LANDING` or cooldown, allowing unhindered bunny-hopping.
  4. LOC-07: `_directional_movement_speed()` returns 1:1 speed forward and backward; missing ~30-40% authentic backpedal reduction.
  5. ISO vs Executable Code Boundary: `zweapon.rdr` contains only weapon stats/ammo/gear/stances. Locomotion, state machine, jump physics, collision/hurtbox parenting, and landing recovery are pure PS2 MIPS engine executable code (`SLUS_206.36`).
- **Unexplored areas**: None for R1 locomotion scope.

## Key Decisions Made
- All four defects verified with exact line numbers, code excerpts, and runtime test data.
- Documenting five-component handoff in `handoff.md` with translation cards and remediation designs.

## Artifact Index
- DISPATCH.md — incoming dispatch instructions
- progress.md — liveness heartbeat
- BRIEFING.md — persistent working memory
- handoff.md — authoritative R1 locomotion investigation report
