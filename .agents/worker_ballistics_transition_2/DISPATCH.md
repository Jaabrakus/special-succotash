## 2026-09-12T02:27:04Z

Read /Users/kiwimango/socom-141-camera-lab/ORIGINAL_REQUEST.md.
Your working directory is /Users/kiwimango/socom-141-camera-lab/.agents/worker_ballistics_transition_2.
Read docs/GAMEPLAY_INTENT_DICTIONARY.md and AGENTS.md.
Read the adversarial challenge report from challenger_ballistics_1 at /Users/kiwimango/socom-141-camera-lab/.agents/challenger_ballistics_1/handoff.md.

MANDATORY INTEGRITY WARNING:
DO NOT CHEAT. All implementations must be genuine. DO NOT hardcode test results, create dummy/facade implementations, or circumvent the intended task. A teamwork_preview_auditor will independently verify your work. Integrity violations WILL be detected and your work WILL be rejected.

You own the following file exclusively:
- `scripts/weapons/weapon_ballistics.gd`

Defect to remediate:
Under rapid stance transitions (e.g. firing 10 rounds Standing to reach 2.40° bloom, then dropping to Crouch or Prone mid-burst), `_bloom_after_shot()` fails to clamp existing bloom to the target posture cap because `if bloom < bloom_cap:` is skipped when `bloom >= bloom_cap`. The higher bloom leaks into the lower stance, violating the invariant that Prone bloom never exceeds 1.07° and Crouch bloom never exceeds 1.70°.

Tasks:
1. In `scripts/weapons/weapon_ballistics.gd`:
   In `_bloom_after_shot(posture: StringName, shot_count: int) -> float`:
   Clamp incoming bloom to `bloom_cap`:
   ```gdscript
   func _bloom_after_shot(posture: StringName, shot_count: int) -> float:
       var bloom_cap := _maximum_bloom_for(posture)
       var bloom := minf(current_recoil_bloom, bloom_cap)
       if shot_count > 2:
           if bloom < bloom_cap:
               bloom = minf(bloom_cap, bloom + _bloom_per_shot_for(posture))
       return bloom
   ```
   In `calculate_current_spread(posture: StringName, movement_speed_norm: float, is_airborne: bool)`:
   Ensure `effective_bloom = minf(current_recoil_bloom, _maximum_bloom_for(posture))` is used for calculating `current_spread_deg` so that dropping posture also immediately reflects the lower stance cap.
2. Run the adversarial regression test and all existing test suites:
   - `/Users/kiwimango/Applications/Godot-4.7.1.app/Contents/MacOS/Godot --headless --path /Users/kiwimango/socom-141-camera-lab --script res://tools/adversarial_ballistics_stance_regression.gd`
   - `/Users/kiwimango/Applications/Godot-4.7.1.app/Contents/MacOS/Godot --headless --path /Users/kiwimango/socom-141-camera-lab --script res://tools/weapon_stance_bloom_regression.gd`
   - `/Users/kiwimango/Applications/Godot-4.7.1.app/Contents/MacOS/Godot --headless --path /Users/kiwimango/socom-141-camera-lab --script res://tools/feature_contract_regression.gd`
3. Write your complete handoff report to `/Users/kiwimango/socom-141-camera-lab/.agents/worker_ballistics_transition_2/handoff.md` and send a message when complete.
