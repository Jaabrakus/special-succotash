## 2026-09-12T01:52:36Z

You are the Project Orchestrator for the SOCOM-141 camera lab project.
Your working directory is /Users/kiwimango/socom-141-camera-lab/.agents/orchestrator_2.
The authoritative user request is recorded in /Users/kiwimango/socom-141-camera-lab/ORIGINAL_REQUEST.md (and .agents/ORIGINAL_REQUEST.md).
Project workspace: /Users/kiwimango/socom-141-camera-lab.

Mission:
Investigate and verify the 8 cataloged ballistics and locomotion defects against the extracted SOCOM II USA ISO database (`RUN/ZWEAPON.ZAR` -> `zweapon.rdr`) and PS2 engine references, and fix the jump animation to include upper body/arm action motion while preserving weapon aim stability.

Key Requirements:
R1. SOCOM 2 ISO Data & Behavior Verification
Verify the 4 ballistics defects (WEAP-01, WEAP-02, WEAP-04, WEAP-05) and 4 locomotion defects (LOC-01, LOC-03, LOC-04, LOC-07) against:
1. The extracted static data tables in `config/reference/socom2_weapon_settings.json` (from `RUN/ZWEAPON.ZAR` -> `zweapon.rdr`).
2. The PS2 MIPS gameplay engine conventions (executable state machine for reloads, momentum, collision hurtbox parenting, and jump landing penalties).
Acceptance:
- Explicit distinction documented between static ISO table fields (`zweapon.rdr`) and PS2 runtime state machine behaviors.
- Stance recoil values for Prone, Crouch, and Stand in `weapon_ballistics.gd` aligned with `config/reference/socom2_weapon_settings.json`.
- Crouch bloom rate per shot (`crouch_bloom_per_shot_deg`) corrected from 1.35° to <= 0.32°.

R2. Jump Animation Upper Body & Arm Action Integration
Resolve the jump arm presentation so the arms participate in the jump action motion depicted in `art_source/jump_peak_slide/jump_forward_action_sheet.png` (`mixamorig_LeftShoulder` through `mixamorig_RightHand`), rather than remaining stiffly locked in grounded ready aim, while maintaining weapon aim/fire authority per Rule 5 of `AGENTS.md`.
Acceptance:
- Upper body arms (`mixamorig_LeftShoulder` through `mixamorig_RightHand`) visibly animate during the jump sequence in `res://main.tscn`.
- Weapon aim pitch/yaw and firing readiness remain functional mid-air without broken wrist IK.

R3. Automated Regression Verification
Update existing focused regressions or add targeted test scripts in `tools/` verifying:
1. Prone recoil uses authentic ISO reduction (`ReticuleKnockMax: 20` vs Stand `45`).
2. Crouch bloom rate per shot is less than or equal to standing bloom rate.
3. Jump upper-body arm tracks evaluate during airborne flight.
Acceptance:
- `tools/feature_contract_regression.gd` and focused regressions pass.

Strictly adhere to the project rules in `AGENTS.md` (read `docs/GAMEPLAY_INTENT_DICTIONARY.md`, write translation cards before edits, preserve single-ownership, preserve dirty worktree, run feature contract regression).
Maintain your `BRIEFING.md`, `plan.md`, and `progress.md` in `.agents/orchestrator_2/`.
When complete, notify me with your completion report and artifacts so that the Victory Audit can be initiated.
