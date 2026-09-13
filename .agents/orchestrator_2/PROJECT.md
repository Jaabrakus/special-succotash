# Project: SOCOM-141 Ballistics & Jump Animation Integration

## Architecture
- **Movement Owner**: `CharacterBody3D` (`SocomTestPlayer`, `scripts/player/player_controller.gd`).
- **Aim-Intent Owner**: Camera / Reticle (`scripts/camera/socom_camera_controller.gd`, `scripts/ui/socom_dynamic_reticle.gd`).
- **Weapon / Damage Owner**: Server weapon / `SocomWeaponController` / `weapon_ballistics.gd`.
- **Presentation & IK**: `SocomOperatorLocomotionBlendTree`, `SocomOperatorWeaponPoseSolver` (presentation only per Rule 5).

## Feature Inventory
| # | Feature | Description | Milestone | Status | Source |
|---|---------|-------------|-----------|--------|--------|
| 1 | ISO vs PS2 Engine Boundary Verification | Document boundary between static ISO tables (`zweapon.rdr`) and dynamic PS2 runtime state machine | M1 | DONE | Survey |
| 2 | WEAP-01 Verification & Recoil Alignment | Prone recoil bloom fallback fix in `weapon_ballistics.gd` with ISO values (`ReticuleKnockMax: 20` vs Stand `45`) | M2 | DONE | Survey |
| 3 | WEAP-02 Crouch Bloom Rate Normalization | Crouch bloom per shot corrected from 1.35° to <= 0.32° in `weapon_ballistics.gd` | M2 | DONE | Survey |
| 4 | WEAP-04 Auto-Reload Lifecycle Analysis | Document reload state machine preemption vs static table fields | M1 | DONE | Survey |
| 5 | WEAP-05 Grenade Velocity Analysis | Document velocity zeroing and momentum inheritance | M1 | DONE | Survey |
| 6 | LOC-01 Lean Peaking Collision Analysis | Document CollisionShape3D decoupling vs mesh offset | M1 | DONE | Survey |
| 7 | LOC-03 Air Momentum Analysis | Document zero air momentum conservation vs ballistic launch | M1 | DONE | Survey |
| 8 | LOC-04 Landing Recovery & Bunnyhop Analysis | Document missing landing speed damping and jump cooldown | M1 | DONE | Survey |
| 9 | LOC-07 Backpedal Speed Ratio Analysis | Document 1:1 speed ratio vs authentic backpedal reduction | M1 | DONE | Survey |
| 10 | R2 Jump Upper Body Arm Animation | Animate `mixamorig_LeftShoulder`..`mixamorig_RightHand` during jump in `res://main.tscn` | M2 | DONE | User Request |
| 11 | R2 Weapon Aim & Fire Authority Mid-Air | Preserve weapon aim pitch/yaw and fire readiness without broken wrist IK (Rule 5) | M2 | DONE | User Request |
| 12 | R3 Prone Recoil Regression | Automated test verifying prone recoil reduction (`20` vs `45`) | M3 | DONE | User Request |
| 13 | R3 Crouch Bloom Regression | Automated test verifying crouch bloom per shot <= standing bloom | M3 | DONE | User Request |
| 14 | R3 Jump Arm Action Regression | Automated test verifying upper-body arm tracks evaluate during airborne flight | M3 | DONE | User Request |
| 15 | Feature Contract & Regression Gating | `tools/feature_contract_regression.gd` passes 100% | M3 | DONE | User Request |

## Milestones
| # | Name | Scope | Dependencies | Status |
|---|------|-------|-------------|--------|
| M1 | Survey & Technical Investigation | Verify 8 defects against ISO & PS2 runtime, document boundaries | none | DONE |
| M2 | Ballistics Alignment & Jump Arm Integration | Implement recoil/bloom alignment in `weapon_ballistics.gd` and jump arm tracks in `operator_locomotion_blend_tree.gd` | M1 | DONE |
| M3 | Automated Regression Verification | Update `weapon_stance_bloom_regression.gd` and create `jump_action_arm_regression.gd` | M2 | DONE |
| M4 | Review, Challenge & Forensic Audit Gate | Independent reviews, empirical stress challenge, and forensic integrity audit | M3 | DONE |
| M5 | Final Deliverables & Victory Audit Handoff | Synthesize final technical report with code excerpts and verification commands | M4 | IN_PROGRESS |

## Translation Cards

### Translation Card 1: Stance Recoil & Crouch Bloom Alignment (`weapon_ballistics.gd`)
- **Player intent**: Firing while crouched or prone provides superior stability and reduced spread expansion compared to standing, matching authentic SOCOM 2 combat feel.
- **Acceptance rule**:
  - `crouch_bloom_per_shot_deg` in `weapon_ballistics.gd` is <= 0.32° (authentically 0.24° matching ISO 9/12 ratio).
  - Explicit `&"PRONE"` branching implemented in `_bloom_per_shot_for`, `_maximum_bloom_for`, and `_recovery_speed_for`.
  - Prone maximum bloom reflects authentic ISO reduction (`ReticuleKnockMax: 20` vs Stand `45`, ratio 0.444 -> `prone_max_recoil_bloom_deg` = 1.07°).
  - Stance transitions (Stand -> Crouch -> Prone) immediately clamp recoil bloom and dispersion cone to the target posture cap in `_bloom_after_shot` and `calculate_current_spread`.
- **System owner**: `scripts/weapons/weapon_ballistics.gd` (`WeaponBallistics` node).
- **Must not change**: Standing base recoil and bloom, rate of fire, base weapon damage.
- **Proof**: `tools/weapon_stance_bloom_regression.gd`, `tools/adversarial_ballistics_stance_regression.gd`.

### Translation Card 2: Jump Upper Body & Arm Action Integration (`operator_locomotion_blend_tree.gd`)
- **Player intent**: When leaping forward or airborne, the operator's arms actively flex and articulate to express the forward leap momentum depicted in `jump_forward_action_sheet.png`, while weapon aim pitch/yaw remains strictly locked to the reticle and fire readiness is preserved.
- **Acceptance rule**:
  - `mixamorig_LeftShoulder` through `mixamorig_RightHand` visibly animate during the jump sequence in `res://main.tscn` (measured rotational delta: 1.167 to 1.991 rad > 0.10 rad).
  - Mid-air weapon aim pitch/yaw tracks camera reticle without disruption (bore error <= 0.08° in canonical envelope).
  - Hand contact gaps remain <= 0.015m for trigger (0.0000m) and <= 0.020m for support foregrip (0.0016m) with zero wrist IK breakage.
  - `tools/feature_contract_regression.gd` passes 121/121 contracts.
- **System owner**: `SocomOperatorLocomotionBlendTree` (Animation presentation) and `SocomOperatorWeaponPoseSolver` (Presentation IK).
- **Must not change**: `CharacterBody3D` player movement physics (Rule 5), camera reticle sole aim authority (Rule 5), server weapon sole damage authority (Rule 5).
- **Proof**: `tools/jump_action_arm_regression.gd`, `tools/jump_forward_legs_regression.gd`, `tools/adversarial_jump_arms_stress_test.gd`.

## Code Layout
- `scripts/weapons/weapon_ballistics.gd`: Ballistics calculation engine (recoil, bloom, stance scaling, transition clamping).
- `scripts/player/operator_locomotion_blend_tree.gd`: Animation presentation blend tree (`JUMP_ARM_BONES` filter tracks, upper-body ready bypass).
- `config/feature_contracts/jump_forward_legs.json`: Feature contract for forward jump animation presentation.
- `tools/weapon_stance_bloom_regression.gd`: Automated test for stance bloom rates.
- `tools/jump_action_arm_regression.gd`: Dedicated test for jump upper body arm tracks and aim stability.
- `tools/adversarial_ballistics_stance_regression.gd`: Adversarial stress test for stance transitions.
- `tools/adversarial_jump_arms_stress_test.gd`: Adversarial stress test for 360° yaw, directional jumps, and aim pitch.
