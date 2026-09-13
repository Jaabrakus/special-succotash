# Warehouse awning investigation

## Render-proof translation card (before capture-only edit)

Intent: inspect the actual raised-container jump, hang and climb from two views.
Acceptance: save early/middle/late rendered frames and record visual defects
separately from physics assertions. Owner: this diagnostic's observer camera
and capture code only. Do not change runtime movement, animation, collision,
aim or weapon ownership. Proof: optional `--capture` runs only the late held
approach through `main.tscn`; default headless retains all five physical cases.

System delta: MERGE an opt-in observer capture. Correctness 4/4, ownership5/5,
runtime parity5/5, usability3/4, performance5/5 (off by default), coverage3/5.

## Translation card (2026-09-12, before bounded motor edit)

- Intent: jump from the existing blue-gray container and catch the metal awning reliably, without extending reach from the ground.
- Acceptance: real queued movement through `main.tscn` catches from the raised container, settles in hang, accepts fresh forward, and lands once. Ground remains rejected. The measured apex probe that previously selected a walkable roof normal must find the actual vertical lip or still reject safely.
- Owner: Player `CharacterBody3D`, through the existing traversal/mantle motor. Diagnostic does not move the body after each grounded starting setup.
- Must not change: jump physics, global reach, camera, weapon/damage authority, map collision, animation ownership.
- Proof: `tools/warehouse_awning_regression.gd`, existing ledge/airborne/map regressions and feature contracts. No new rendered claim without graphical inspection.

## System-delta review

Scores 0–5, old candidate-selection / bounded candidate-selection:
correctness 2/4; ownership 5/5; runtime parity 5/5; editor usability 4/4;
performance 5/4 (bounded extra rays only on fallback); regression coverage 2/4.
Decision: MERGE, subject to focused checks. Preserve all permission, face normal,
reach, five-point support, ceiling/sweep, and standing capsule checks.

Code evidence: `scripts/traversal/socom_mantle_motor.gd::probe_climb` stops
at the first nonempty horizontal ray, even when that hit is a walkable top.
The existing thin fallback uses the top height at maximum forward depth. On
this sloped awning, a ray 2cm below that deeper height still hits the slope,
not its front fascia. Candidate: skip invalid face normals; if no valid face,
locate the near top boundary within the unchanged forward reach and then ray
against the actual fascia. Do not synthesize a vertical normal from a top.

## Baseline geometry and physical results

Checked-in `config/maps/current_map.json` is explicitly selected. This is not
proof that an old browser ZIP or `user://maps/active_map.json` contains it.

- Warehouse relic_014 uses `ConcavePolygonShape3D`, not a building-sized box.
- Awning front x≈-16.17252, lip y≈3.791; slope normal (0.36693,0.930249,0).
- Existing relic_021 container top y=2.176415, near edge x=-15.03: gap≈1.14252m.
- Ground jump apex feet y=1.263113; fingertips y=3.413113 with saved 2.15m reach. Ground cannot reach the lip and remains an ordinary jump.
- Raised early launch x=-14.15 catches on descent; late launch x=-14.75 catches at frame4. Both use actual acceleration/jump, not a placed airborne character. Baseline late second tap also catches.
- Baseline apex feet (-15.79145,3.349498,1): `Not a ledge face`; fraction .25 hits slope at (-16.41597,3.886998,1), higher rays empty. This is a missed candidate, not a missing collider.

Diagnostic outputs: `/private/tmp/warehouse-awning-results.json`,
`/private/tmp/warehouse-awning-final.log`. Exit0 means diagnostic completed;
individual outcomes, not blanket traversal success, determine acceptance.

## Implemented bounded fix and verified results

`scripts/traversal/socom_mantle_motor.gd:43` now keeps searching past a
walkable-top normal; climb-permission rejection still stops immediately:

```gdscript
if not _climb_surface_allowed(candidate.collider):
    return _rejection("No climbable solid face")
if _is_ledge_face(candidate.normal, direction, body.floor_max_angle):
    wall = candidate
    break
```

The fallback at line52 performs seven bounded midpoint top rays to locate
the near top boundary, then queries the real lip 2cm below it. Line78 still
requires a valid physical face normal, and `_probe_climb_top` still applies
all reach/support/capsule/sweep checks. No collider or inferred normal is added.

After the fix, the exact old apex query returns anchor
(-16.23239,3.814584,1), actual normal (1,0,0). The early held jump catches
on ascent instead of waiting for descent. The regression also exercises a
fresh second tap at frame18 of that real early jump (apex), not only a query.

| Check | Result |
| --- | --- |
| Ground physical jump | Correctly rejected; safe floor landing |
| Existing container early launch, hold | Hang, stable settle, fresh W, landed |
| Existing container early launch, apex second tap | Hang, stable settle, fresh W, landed |
| Existing container late launch, hold | Hang, stable settle, fresh W, landed |
| Existing container late launch, second tap | Hang, stable settle, fresh W, landed |
| All four raised-route exits | (-16.73239,4.040877,1), on floor, traversal inactive |
| `ledge_climb_regression.gd` | PASS including permissions, ceiling, reach, shimmy, ladder |
| `map_jump_ledge_regression.gd` | PASS: rocks038/040 and safe rejected039 |
| `feature_contract_regression.gd` | PASS: 124 contracts |

Final runtime log: `/private/tmp/warehouse-awning-apex-tap.log`; report:
`/private/tmp/warehouse-awning-results.json`. Regression now exits nonzero if
the exact apex query or any listed physical expectation fails.

Run the actual proof with:

```sh
/Users/kiwimango/Applications/Godot-4.7.1.app/Contents/MacOS/Godot --headless --path /Users/kiwimango/socom-141-camera-lab --log-file /private/tmp/warehouse-awning-proof.log --script res://tools/warehouse_awning_regression.gd
```

Done: bounded collision-query correction and physical gameplay proof.
Partial: rendered proof below exposes a remaining mid-pull-up mesh/slope intersection;
headless success does not establish visual quality. Existing old browser ZIPs
are not updated by these source edits. No map-save migration was performed.

## Rendered actual awning proof

**Latest rerun supersedes the braced-stage pose observations below:**
`/private/tmp/awning-free-final-rendered.log` completed exit0 after geometry
classification was added. The same16 filenames now contain measured free-hang
and free pull-up poses. Hang legs are untucked because no wall is within the
saved foot-brace query. Two-view early phase≈0.142, middle≈0.455 and late≈0.811
were inspected; midpoint upper-body/slope intersection remains Partial.
The earlier notes below describe the braced-profile baseline for comparison.

Serial graphical run on Godot4.7.1/OpenGL Compatibility completed normally,
exit0, `WAREHOUSE_AWNING PASS`, log `/private/tmp/awning-final-rendered.log`.
All16 PNGs were opened and inspected: two front-side views at launch-ready,
jump, grab-entry, settled hang, pull-up early/middle/late, and landed.
They are under `art_source/traversal_runtime_proof/`, named
`awning-<stage>-side-1.png` and `awning-<stage>-side1.png`.

| Rendered stage | Observed result |
| --- | --- |
| Launch/jump | Actual raised-container approach and airborne body; equipped weapon visible |
| Grab entry | Weapon stows; arms still blending toward the contact pose |
| Settled hang | Knees visibly tucked in both views, facing awning, no held gun |
| Pull-up early, phase0.185 | Tucked leg pose begins pulling up at the lip |
| Pull-up middle, phase0.452 | **Partial: head/upper torso visibly intersects the sloped awning surface in both views** |
| Pull-up late, phase0.801 | Body clears upward, feet still transferring across the lip |
| Landed | Standing on sloped awning, held weapon restored, traversal inactive |

Important distinction: `weapon_node.visible=false` during hang/pull-up means
the equipped hand-held instance is hidden; the separate stowed rifle on the
back remains visible intentionally. Visibility returns true after landing.
The capsule remains collision-owned and finishes supported; this does not
prove the animated skinned mesh avoided the slope at every intermediate frame.
No animation/runtime change was made during this capture-only pass.

Capture code in `tools/warehouse_awning_regression.gd::_capture` uses:

```gdscript
await create_timer(0.0).timeout
paused = true
camera.force_update_transform()
RenderingServer.force_draw(false)
```

It saves both views before restoring the prior pause state, avoiding an
occluded-window wait on `frame_post_draw` while paused. Capture is opt-in:

```sh
/Users/kiwimango/Applications/Godot-4.7.1.app/Contents/MacOS/Godot --path /Users/kiwimango/socom-141-camera-lab --log-file /private/tmp/awning-render.log --script res://tools/warehouse_awning_regression.gd -- --capture
```

This mode runs only the late held container approach. Default headless still
runs every physical case. Timing samples are captured after Node processing,
not promised to be the exact threshold phase or identical across render rates.
