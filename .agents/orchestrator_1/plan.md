# Project Quality Audit Plan: SOCOM-141

## Objective
Deliver a comprehensive, rigorous, and actionable quality audit and diagnostic evaluation of the SOCOM-141 tactical shooter project, covering Locomotion/Posture/Jump, Weapon Handling & Ballistics, Camera & HUD Presentation, and Regression Test Suite execution.

## Audit Tracks & Scope Breakdown

### Track 1: Test & Regression Execution (Worker: worker_regression_1)
- **Target**: Execute `tools/feature_contract_regression.gd` and `tools/public_training_range_regression.gd` via Godot engine runner (headless).
- **Deliverables**: Verbatim test output, pass/fail status, contract evaluations, failure logs.

### Track 2: Locomotion, Posture & Jump Mechanics (Explorer: explorer_locomotion_1)
- **Target**: `scripts/player/` (e.g. player_controller.gd, movement logic, posture logic, jump handling), `scenes/player/`
- **Requirements**:
  - Audit standing, crouched, prone gaits.
  - Directional strafing, acceleration/braking responsiveness.
  - Lean peaking mechanics and camera/collision coupling.
  - Directional jump behavior (W, A, S, D), momentum retention/kill, air control.
  - Transition smoothness, velocity bounds, lower-body animation fidelity vs authentic SOCOM 2 standards.
  - Exact code references (file, line number, code excerpts).
  - Defects with reproduction steps and translation cards for remediation.

### Track 3: Weapon Handling & Ballistics (Explorer: explorer_weapons_1)
- **Target**: `scripts/weapons/` (e.g. weapon controllers, inventory, ballistics, projectiles), `scenes/weapons/`
- **Requirements**:
  - Weapon equip/cycle behavior, holstering, switching delays.
  - Firing cadences, semi/burst/auto modes.
  - Spread/bloom expansion per shot and recovery rates across postures (stand, crouch, prone, moving).
  - Reload trigger cycles (empty reload vs tactical reload, animation cancel, ammo state updates).
  - Grenade trajectory preview and launch physics/mechanics.
  - Hit-detection consistency, raycast vs projectile, server weapon ownership contract.
  - Exact code references (file, line number, code excerpts).
  - Defects with reproduction steps and translation cards for remediation.

### Track 4: Camera & HUD Presentation (Explorer: explorer_camera_hud_1)
- **Target**: `scripts/camera/`, `scripts/runtime/`, `scenes/camera/`, `scenes/ui/`
- **Requirements**:
  - SOCOM third-person camera rig: framing, distance, shoulder offset, obstruction avoidance/spring arm collision, pitch/yaw limits.
  - Reticle aim tracking, screen-center vs projectile collision projection, aim-intent ownership.
  - HUD layout: loadout card, status panels (health, stance, fire mode), compass, crosshair visuals.
  - HUD toggle functionality (`H` key) and state persistence.
  - Exact code references (file, line number, code excerpts).
  - Defects with reproduction steps and translation cards for remediation.

### Track 5: Report Synthesis & Verification Gate
- Synthesize all findings into a structured, publication-ready Diagnostic Audit Report (`AUDIT_REPORT.md` or `.agents/orchestrator_1/DIAGNOSTIC_REPORT.md`).
- Ensure all acceptance criteria are met:
  1. Systematic evaluation with exact script references in `scripts/player/`, `scripts/weapons/`, `scripts/camera/`, `scripts/runtime/`.
  2. Reproduction steps, exact file paths, line numbers, and code excerpts for every defect.
  3. Regression test suite status documented with verbatim pass/fail logs.
  4. Prioritized, actionable fix recommendations adhering to single-owner architecture and translation card principles in `AGENTS.md`.
- Reviewer verification gate to validate audit accuracy and completeness.

## Schedule & Milestones
- [ ] Milestone 1: Dispatch Track 1 (Worker), Track 2 (Explorer), Track 3 (Explorer), Track 4 (Explorer).
- [ ] Milestone 2: Monitor and collect reports from all 4 subagents.
- [ ] Milestone 3: Synthesize Comprehensive Diagnostic Report.
- [ ] Milestone 4: Independent Review / Quality Gate verification.
- [ ] Milestone 5: Delivery and completion notification to parent.
