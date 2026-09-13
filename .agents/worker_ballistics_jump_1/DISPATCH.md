## 2026-09-12T02:00:55Z

Read /Users/kiwimango/socom-141-camera-lab/ORIGINAL_REQUEST.md.
Your working directory is /Users/kiwimango/socom-141-camera-lab/.agents/worker_ballistics_jump_1.
Read docs/GAMEPLAY_INTENT_DICTIONARY.md, docs/GODOT_FEATURE_INTEGRATION_CONTRACT.md, AGENTS.md, and /Users/kiwimango/socom-141-camera-lab/.agents/orchestrator_2/PROJECT.md.

MANDATORY INTEGRITY WARNING:
DO NOT CHEAT. All implementations must be genuine. DO NOT hardcode test results, create dummy/facade implementations, or circumvent the intended task. A teamwork_preview_auditor will independently verify your work. Integrity violations WILL be detected and your work WILL be rejected.

You own the following files exclusively:
- `scripts/weapons/weapon_ballistics.gd`
- `scripts/player/operator_locomotion_blend_tree.gd`
- `config/feature_contracts/jump_forward_legs.json`
- `tools/weapon_stance_bloom_regression.gd`
- `tools/jump_forward_legs_regression.gd`
- `tools/jump_action_arm_regression.gd` (if creating new)

Tasks:
1. Implement Requirement R1 & Translation Card 1: Stance Recoil & Crouch Bloom in `scripts/weapons/weapon_ballistics.gd`:
   - Add prone parameters:
     `@export var prone_bloom_per_shot_deg: float = 0.213` (or 0.192)
     `@export var prone_max_recoil_bloom_deg: float = 1.07` (aligned with ISO `ReticuleKnockMax: 20` vs Stand `45`, ratio 0.444 -> `2.40 * 20 / 45 = 1.0667`)
     `@export var prone_bloom_recovery_speed: float = 18.0`
   - Correct `crouch_bloom_per_shot_deg: float = 1.35` -> change to `<= 0.32` (e.g. `0.24` matching ISO `9/12` ratio, or `0.192` matching `0.60x`).
   - Implement explicit `&"PRONE"` branching in `_bloom_per_shot_for`, `_maximum_bloom_for`, and `_recovery_speed_for`.
2. Implement Requirement R2 & Translation Card 2: Jump Upper Body & Arm Action Integration in `scripts/player/operator_locomotion_blend_tree.gd`:
   - Define `const JUMP_ARM_BONES: Array[StringName] = [ &"mixamorig_LeftShoulder", &"mixamorig_LeftArm", &"mixamorig_LeftForeArm", &"mixamorig_LeftHand", &"mixamorig_RightShoulder", &"mixamorig_RightArm", &"mixamorig_RightForeArm", &"mixamorig_RightHand" ]`
   - In `_build_jump_lower_body_layer()`, add `JUMP_ARM_BONES` to the blend filter alongside `JUMP_LEG_BONES`.
   - In `_uses_upper_body_ready_layer(clip_name)`, ensure `source_jump_clip(clip_name)` and `clip_name == jump_lower_body_clip` return `false` so the grounded ready layer does not overwrite jump action arm tracks.
   - Update `config/feature_contracts/jump_forward_legs.json` to reflect that the forward jump motion evaluates thigh-to-toe and shoulder-to-hand tracks while preserving aim stability and IK contact tolerances.
3. Update/Create Regression Tests for Requirement R3:
   - In `tools/weapon_stance_bloom_regression.gd`:
     - Change line 28 assertion to `crouched_third <= standing_third` ("crouch bloom rate per shot is less than or equal to standing bloom rate").
     - Add Prone tests verifying prone third shot spread <= crouched third shot spread and <= standing third shot spread.
     - Add assertion verifying prone maximum bloom reduction matches authentic ISO reduction (`ReticuleKnockMax: 20` vs Stand `45`).
   - In `tools/jump_forward_legs_regression.gd` and/or `tools/jump_action_arm_regression.gd`:
     - Verify upper-body arm tracks (`mixamorig_LeftShoulder` through `mixamorig_RightHand`) visibly animate during airborne flight (rotational delta > 0.10 rad).
     - Verify trigger hand contact <= 0.015m and support hand contact <= 0.020m.
     - Verify bore to reticle degrees <= 6.0° (camera reticle sole aim authority preserved per Rule 5).
4. Run the test suite:
   - `/Users/kiwimango/Applications/Godot-4.7.1.app/Contents/MacOS/Godot --headless --path /Users/kiwimango/socom-141-camera-lab --script res://tools/feature_contract_regression.gd`
   - `/Users/kiwimango/Applications/Godot-4.7.1.app/Contents/MacOS/Godot --headless --path /Users/kiwimango/socom-141-camera-lab --script res://tools/weapon_stance_bloom_regression.gd`
   - `/Users/kiwimango/Applications/Godot-4.7.1.app/Contents/MacOS/Godot --headless --path /Users/kiwimango/socom-141-camera-lab --script res://tools/jump_forward_legs_regression.gd`
   - `/Users/kiwimango/Applications/Godot-4.7.1.app/Contents/MacOS/Godot --headless --path /Users/kiwimango/socom-141-camera-lab --script res://tools/source_jump_regression.gd`
   - `/Users/kiwimango/Applications/Godot-4.7.1.app/Contents/MacOS/Godot --headless --path /Users/kiwimango/socom-141-camera-lab --script res://tools/public_training_range_regression.gd`
5. Write your complete handoff report to `/Users/kiwimango/socom-141-camera-lab/.agents/worker_ballistics_jump_1/handoff.md` and send a message when complete.
