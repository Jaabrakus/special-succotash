# Original User Request

## 2026-09-12T01:27:17Z

Execute a comprehensive quality audit and diagnostic evaluation of the SOCOM-141 tactical shooter project, focusing on core gameplay mechanics, locomotion feel, combat systems, camera behavior, and HUD presentation against authentic SOCOM 2 standards.

Working directory: /Users/kiwimango/socom-141-camera-lab
Integrity mode: demo

## Requirements

### R1. Locomotion, Posture & Jump Mechanics
Audit character locomotion across all gaits (standing, crouched, prone), directional strafing, acceleration/braking responsiveness, lean peaking, and directional jump behavior (W, A, S, D). Evaluate transition smoothness, velocity bounds, and lower-body animation fidelity.

### R2. Weapon Handling & Ballistics
Audit weapon equip/cycle behavior, firing cadences, spread/bloom expansion and recovery, reload trigger cycles, grenade trajectory preview/launch, and hit-detection consistency through the canonical weapon controller.

### R3. Camera & HUD Presentation
Audit the SOCOM third-person camera rig (framing, obstruction avoidance, pitch/yaw limits), reticle aim tracking, HUD layout (loadout card, status panels, compass), and HUD toggle functionality (`H` key).

### R4. Actionable Diagnostic Report
Deliver a structured technical audit report detailing every verified defect, feel discrepancy against authentic SOCOM 2 references, and contract failure, complete with exact code/scene locations, excerpts, and remediation recommendations following the `AGENTS.md` project rules.

## Acceptance Criteria

### Gameplay Systems Audit
- [ ] Locomotion, posture transitions, and jumping (forward and lateral) are systematically evaluated with exact script references in `scripts/player/`.
- [ ] Weapon firing, reload, and grenade lifecycles are evaluated with exact script references in `scripts/weapons/`.
- [ ] Camera framing and HUD element lifecycles are evaluated with exact script references in `scripts/camera/` and `scripts/runtime/`.

### Rigor & Verification Standards
- [ ] Every reported defect includes reproduction steps, exact file paths, line numbers, and relevant code excerpts.
- [ ] Regression test suite status (`tools/feature_contract_regression.gd`, `tools/public_training_range_regression.gd`) is documented with pass/fail logs.
- [ ] Report provides prioritized, actionable fix recommendations adhering to the project's single-owner architecture and translation card principles.

## 2026-09-12T01:51:48Z

Investigate and verify the 8 cataloged ballistics and locomotion defects against the extracted SOCOM II USA ISO database (`RUN/ZWEAPON.ZAR` -> `zweapon.rdr`) and PS2 engine references, and fix the jump animation to include upper body/arm action motion while preserving weapon aim stability.

Working directory: /Users/kiwimango/socom-141-camera-lab

## Requirements

### R1. SOCOM 2 ISO Data & Behavior Verification
Verify the 4 ballistics defects (`WEAP-01`, `WEAP-02`, `WEAP-04`, `WEAP-05`) and 4 locomotion defects (`LOC-01`, `LOC-03`, `LOC-04`, `LOC-07`) against:
1. The extracted static data tables in `config/reference/socom2_weapon_settings.json` (from `RUN/ZWEAPON.ZAR` -> `zweapon.rdr`).
2. The PS2 MIPS gameplay engine conventions (executable state machine for reloads, momentum, collision hurtbox parenting, and jump landing penalties).

### R2. Jump Animation Upper Body & Arm Action Integration
Resolve the jump arm presentation so the arms participate in the jump action motion depicted in `art_source/jump_peak_slide/jump_forward_action_sheet.png` (`mixamorig_LeftShoulder` through `mixamorig_RightHand`), rather than remaining stiffly locked in grounded ready aim, while maintaining weapon aim/fire authority per Rule 5 of `AGENTS.md`.

### R3. Automated Regression Verification
Update existing focused regressions or add targeted test scripts in `tools/` verifying:
1. Prone recoil uses authentic ISO reduction (`ReticuleKnockMax: 20` vs Stand `45`).
2. Crouch bloom rate per shot is less than or equal to standing bloom rate.
3. Jump upper-body arm tracks evaluate during airborne flight.

## Acceptance Criteria

### ISO Parity Verification
- [ ] Explicit distinction documented between static ISO table fields (`zweapon.rdr`) and PS2 runtime state machine behaviors.
- [ ] Stance recoil values for Prone, Crouch, and Stand in `weapon_ballistics.gd` aligned with `config/reference/socom2_weapon_settings.json`.
- [ ] Crouch bloom rate per shot (`crouch_bloom_per_shot_deg`) corrected from 1.35° to <= 0.32°.

### Jump Presentation Fidelity
- [ ] Upper body arms (`mixamorig_LeftShoulder` through `mixamorig_RightHand`) visibly animate during the jump sequence in `res://main.tscn`.
- [ ] Weapon aim pitch/yaw and firing readiness remain functional mid-air without broken wrist IK.
- [ ] `tools/feature_contract_regression.gd` and focused regressions pass.
