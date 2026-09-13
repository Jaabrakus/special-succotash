# BRIEFING — 2026-09-12T02:00:00Z

## Mission
Technical investigation for Requirements R1 & R3 regarding the 4 ballistics defects (WEAP-01, WEAP-02, WEAP-04, WEAP-05).

## 🔒 My Identity
- Archetype: explorer
- Roles: investigation, synthesis
- Working directory: /Users/kiwimango/socom-141-camera-lab/.agents/explorer_ballistics_2
- Original parent: 69c1c26a-eb38-4153-8e60-987729cf55ef
- Milestone: ballistics-investigation-r1-r3

## 🔒 Key Constraints
- Read-only investigation — do NOT implement
- Base findings on verifiable code, data, and ISO evidence
- Provide exact file paths and line numbers
- Document distinction between static ISO data tables and PS2 MIPS runtime state machine

## Current Parent
- Conversation ID: 69c1c26a-eb38-4153-8e60-987729cf55ef
- Updated: 2026-09-12T01:53:24Z

## Investigation State
- **Explored paths**:
  - `config/reference/socom2_weapon_settings.json`
  - `config/weapons/m4a1.json`
  - `scripts/weapons/weapon_ballistics.gd`
  - `scripts/weapons/weapon_fire_mode_policy.gd`
  - `scripts/runtime/weapon_reload_coordinator.gd`
  - `scripts/runtime/main_grenade_runtime.gd`
  - `scripts/runtime/main_grenade_trajectory.gd`
  - `scripts/tactical/tactical_grenade_thrower.gd`
  - `scripts/weapons/socom_weapon_controller.gd`
  - `tools/weapon_stance_bloom_regression.gd`
  - `tools/weapon_auto_reload_regression.gd`
  - `tools/ballistic_convergence_regression.gd`
  - `tools/ballistic_reference_reticle_regression.gd`
  - `tools/socom2_weapon_reference_test.cjs`
  - `tools/feature_contract_regression.gd`
- **Key findings**:
  - WEAP-01: `weapon_ballistics.gd:363-381` completely omits `&"PRONE"` checks, falling through to standing values (`max_recoil_bloom_deg = 2.4`, `bloom_per_shot_deg = 0.32`). In ISO (`zweapon.rdr`), Prone `ReticuleKnockMax` is 20 vs Stand 45 (55.6% reduction; ratio 0.444).
  - WEAP-02: `weapon_ballistics.gd:45` hardcodes `crouch_bloom_per_shot_deg = 1.35`, 4.2x larger than standing (0.32°), causing crouch 3rd shot bloom to jump to 1.551° vs 0.600° standing. ISO data shows crouch `ReticuleKnock` is 9 vs stand 12 (0.75x) and dilation is identical (7 vs 7). It must be <= 0.32°.
  - WEAP-04: `weapon_reload_coordinator.gd:99-106, 172-174` ignores mobility actions (`pass`), blocks fire cancellation when empty, and locks weapon swapping, trapping the player for 2.2s. PS2 engine handles reload as a pre-emptible MIPS executable state machine where sprint, dive, roll, and weapon swap cancel reload before commit. Static ISO tables only contain numeric timing constants.
  - WEAP-05: `main_grenade_runtime.gd:431-432` zeroes player velocity on throw start, and `main_grenade_trajectory.gd:108-114` fails to pass `player_velocity` to `calculate_launch_velocity`, rendering `tactical_grenade_thrower.gd:133` momentum inheritance dead code. PS2 engine inherited character movement vectors.
  - ISO vs Runtime distinction: `zweapon.rdr` contains static numerical constants; runtime state transitions, interruptibility, and physics integration are owned by MIPS executable state machines.
  - Test suites: `weapon_stance_bloom_regression.gd` currently codifies the crouch bloom bug; `weapon_auto_reload_regression.gd` has runtime errors and codifies mobility lockout.
- **Unexplored areas**: None. All requested investigation items fully explored and verified.

## Key Decisions Made
- Fully documented all 4 defects with exact lines, schemas, equations, and PS2 engine conventions.
- Formulated clear regression test plans and implementation guidance for downstream implementer agents.

## Artifact Index
- DISPATCH.md — incoming instructions
- BRIEFING.md — persistent memory
- progress.md — liveness heartbeat
- handoff.md — final 5-component report
