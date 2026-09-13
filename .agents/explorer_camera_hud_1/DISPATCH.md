# Dispatch for explorer_camera_hud_1

## Task
Audit Camera & HUD Presentation (scripts/camera/, scripts/runtime/).
Working directory: /Users/kiwimango/socom-141-camera-lab/.agents/explorer_camera_hud_1
Project root: /Users/kiwimango/socom-141-camera-lab

## 2026-09-12T01:28:39Z
You are explorer_camera_hud_1, a teamwork_preview_explorer assigned to conduct a comprehensive quality audit of Camera & HUD Presentation for the SOCOM-141 tactical shooter project.

Working Directory: /Users/kiwimango/socom-141-camera-lab/.agents/explorer_camera_hud_1
Project Root: /Users/kiwimango/socom-141-camera-lab
Original Request: /Users/kiwimango/socom-141-camera-lab/.agents/ORIGINAL_REQUEST.md
Project Rules: /Users/kiwimango/socom-141-camera-lab/AGENTS.md

Your Tasks:
1. Read /Users/kiwimango/socom-141-camera-lab/.agents/ORIGINAL_REQUEST.md and /Users/kiwimango/socom-141-camera-lab/AGENTS.md. Also read `docs/GAMEPLAY_INTENT_DICTIONARY.md` and `docs/GODOT_FEATURE_INTEGRATION_CONTRACT.md` if present.
2. Deeply audit all scripts in `scripts/camera/` and `scripts/runtime/`, as well as relevant UI/HUD scripts and scenes in `scenes/` (camera rig, reticle, loadout card, status panels, HUD manager).
3. Systematically evaluate:
   - SOCOM third-person camera rig: framing, camera distance, field of view, right-shoulder offset, pitch and yaw limits, rotation smoothing/deadzones.
   - Obstruction avoidance: SpringArm3D or raycast collision detection against geometry, wall clipping, pop vs smooth zoom, collision mask filtering.
   - Reticle aim tracking: screen center projection vs world aim target, aim-intent ownership (Rule 5: SOCOM camera/reticle remains sole aim-intent owner), does camera illegally write to character transforms?
   - HUD layout & elements: loadout card display (active weapon, secondary, grenade, ammo counters), status panels (health, armor, stance icon), compass/radar.
   - Reticle dynamics: dynamic spread visualization matching weapon bloom, target coloring/identification, reticle styling vs authentic SOCOM 2.
   - HUD toggle functionality: verify the `H` key toggle logic. Does it hide all HUD elements cleanly? Does it disable UI update overhead or leave active elements? Is state restored properly?
4. For every identified defect, feel discrepancy against authentic SOCOM 2, or contract violation:
   - Provide a clear title and severity.
   - Step-by-step reproduction steps.
   - Exact file path and line numbers.
   - Verbatim code excerpt.
   - Detailed technical explanation of the issue and why it departs from SOCOM 2 feel or violates project architecture.
   - Actionable remediation recommendation formatted as an explicit Translation Card (Player intent, Acceptance rule, One system owner, Systems that must not change, Focused proof) per Rule 2 of AGENTS.md.
5. Write your complete findings to `/Users/kiwimango/socom-141-camera-lab/.agents/explorer_camera_hud_1/camera_hud_audit.md`.
6. Write your handoff to `/Users/kiwimango/socom-141-camera-lab/.agents/explorer_camera_hud_1/handoff.md`.
7. Send a message to your parent orchestrator (conversation ID: f65421c8-95ea-4753-89f3-5c067645d740) when complete.
