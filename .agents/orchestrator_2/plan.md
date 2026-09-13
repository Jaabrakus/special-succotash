# Execution Plan: SOCOM-141 ISO Verification & Jump Arm Action Integration

## Objective
Fulfill Requirements R1, R2, and R3 from user request:
1. Verify 8 cataloged defects (WEAP-01, WEAP-02, WEAP-04, WEAP-05, LOC-01, LOC-03, LOC-04, LOC-07) against SOCOM 2 USA ISO database (`config/reference/socom2_weapon_settings.json` from `RUN/ZWEAPON.ZAR` -> `zweapon.rdr`) and PS2 runtime state machine conventions. Document explicit distinctions.
2. Align stance recoil values for Prone, Crouch, Stand in `scripts/weapons/weapon_ballistics.gd` with ISO tables, and correct crouch bloom rate per shot to <= 0.32°.
3. Integrate jump upper body & arm action motion (`mixamorig_LeftShoulder` through `mixamorig_RightHand`) during jump sequence in `res://main.tscn`, preserving aim pitch/yaw and fire authority (Rule 5).
4. Verify all changes via automated regression suite (`tools/feature_contract_regression.gd`, focused regressions for prone recoil, crouch bloom, jump arm tracks) and pass full review, challenge, and forensic integrity audit.

## Milestones
- **M1: Survey & Technical Investigation** (3 Parallel Explorers)
  - Explorer 1: Ballistics ISO Data vs Runtime State Machine (WEAP-01, 02, 04, 05)
  - Explorer 2: Locomotion Defects vs PS2 Engine Conventions (LOC-01, 03, 04, 07)
  - Explorer 3: Jump Arm Action Animation Rig & Aim Decoupling Architecture
- **M2: Synthesis & Translation Cards**
  - Synthesize reports into authoritative ISO Parity & Defect Verification Document
  - Formulate Rule 2 Translation Cards for Ballistics and Jump Arm Integration
- **M3: Implementation & Dual-Track Verification**
  - Worker 1: Stance Recoil & Crouch Bloom Alignment (`weapon_ballistics.gd`) + Regression Tests
  - Worker 2 / Sequential: Jump Upper Body / Arm Action Integration + Presentation Parity
- **M4: Review, Challenge & Forensic Audit Gate**
  - Reviewers (2 independent code and architecture reviews)
  - Challengers (2 empirical behavioral and stress verifications)
  - Forensic Auditor (Integrity verification against cheating / hardcoding / facade)
- **M5: Automated Regression Battery & Final Deliverables**
  - Run `tools/feature_contract_regression.gd` and focused regressions
  - Deliver comprehensive report to user and prepare for Victory Audit
