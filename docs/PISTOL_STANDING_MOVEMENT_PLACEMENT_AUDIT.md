# Standing pistol movement reuse — rejected trials, 2026-09-05

Status: **not implemented**. All gameplay edits from this pass were removed.
Existing dirty worktree work, including compressed idle and crouch movement,
was preserved. Only this report, the rejected feature record and a diagnostic
test remain from the pass. No browser export, commit or deployment was made.

## Translation card

- Intent: reuse the accepted crouch-moving pistol upper body while standing.
- Acceptance: keep standing lower body, contact within 1 cm through entry/fire,
  and acceptable rendered side/rear placement.
- Owner: existing locomotion blend graph; existing support-contact solver only
  for the rejected contact-preservation trial.
- Protected: crouch movement, stationary idle, reload, gameplay movement,
  camera, shot authority, other weapon profiles.
- Proof: canonical scene source-routing, stationary idle/reload tests, and
  tools/pistol_standing_movement_placement_regression.gd with optional --capture.

## Evidence

`config/weapons/mark_23.json` retains:

```json
"idle_standing_moving": "pistol_idle",
"ready_crouched_moving": "pistol_idle_kneeling",
"ready_standing_moving": "pistol_idle"
```

`scripts/player/operator_locomotion_blend_tree.gd` selects the actual crouch
movement from `_direction_space(&"crouch", available_clips)`. The ready clip
alone is not the relaxed movement source. `UPPER_BODY_BONES` excludes hips/legs.
Godot 4.7.1 rejects connecting the same output to two graph inputs; the failed
fan-out trial was corrected with a separate sampler, then also rejected on
contact quality. Official API consulted:
https://docs.godotengine.org/en/latest/classes/class_animationnodeblend2.html
(latest is not a substitute for the installed-engine runtime checks).

Fixed-60-Hz sampled entry support errors (frame 8, metres):

| Direction | Prior standing profile | Kneeling-ready trial | Crouch-gait sampler |
|---|---:|---:|---:|
| Forward | 0.067698 | 0.053058 | 0.091316 |
| Left | 0.062147 | 0.074594 | 0.131548 |
| Right | 0.076034 | 0.095914 | 0.129015 |

Unchanged crouch entry also fails (~0.081 m). Settled movement and sampled
fire contacts pass 1 cm. Thus the problem is not exclusive to the candidate,
but the candidate worsens standing entry and must not be presented as fixed.
The added diagnostic intentionally returns failure on these entry problems.

The full-strength support trial had no effect: runtime diagnostics showed
`current_weight=1.0` already. Do not repeat the unsupported claim that a grip
strength ramp is the cause. Investigate post-animation attachment/contact
evaluation timing with same-frame bone/marker measurements before another
runtime change. Root cause remains unverified.

Historical trial logs: /private/tmp/pistol-placement-baseline.log,
/private/tmp/pistol-placement-current-metrics.log,
/private/tmp/pistol-placement-sampler-v2.log,
/private/tmp/pistol-placement-owner.log. Temporary files may expire.

Stationary compressed idle/fire passed four aim/posture cases and two reloads.
Source routing and exact stationary blend-weight tests passed. Rendered trial
movement/contact test failed. After rollback, source routing passed again and
the structural gate passed all 37 records; this is not visual acceptance.
Integration quick
is blocked because the current branch is codex/render-deployment, not main.
