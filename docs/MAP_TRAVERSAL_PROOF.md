# Actual Relic Depot traversal proof

## Translation card

- Player intent: Jump toward reachable rock edges and catch them without passing through their lower faces.
- Acceptance: Real commands begin on the map floor, accelerate, jump, catch in air, hang, then finish a single pull-up on supported ground. Unsafe/unreachable surfaces remain rejected.
- Owner: `SocomTraversalRuntime` chooses a bounded hanging target; the existing player `CharacterBody3D` alone moves/collides.
- Unchanged: Jump velocity/gravity, camera aim, combat authority, loaded map geometry, normal pull-up clearance and support checks.
- Proof: `tools/map_jump_ledge_regression.gd` enters `main.tscn` with the checked-in map, plus `tools/ledge_climb_regression.gd` and `tools/agls_auto_vault_regression.gd`.

## Runtime fix

`scripts/traversal/socom_traversal_runtime.gd`, `try_begin_automatic_vault`:

```gdscript
for distance in mantle_motor.climb_profile.get("hang_outward_search_m", [0.0]):
    var extra := clampf(float(distance), 0.0, 0.24)
    if extra <= 0.0: continue
    var candidate := hang_point + outward * extra
    if Vector2(candidate.x - anchor.x, candidate.z - anchor.z).length() > capsule_radius + float(mantle_motor.climb_profile.forward_reach_m): continue
    if body.test_move(body.global_transform, candidate - body.global_position): continue
```

Each candidate also tests the exact player collision shape at its destination.
The saved search `[0, 0.08, 0.16, 0.24]` does not increase vertical reach and
cannot pass through a wall or ceiling. It only runs when the original hanging
target is blocked. Original floor-blocked short-ledge fallback stays intact.

Before this change, rock `relic_038` accepted its top but computed a hanging
target inside the protruding lower face. At feet `(22.0861, 0.6092, 18.86165)`,
the target `(22.04261, 0.395, 19.02705)` hit wall normal
`(-0.094883, 0, -0.995488)`. Disabling collision was not a safe fix.

## System-delta review

Decision: **MERGE**, bounded hanging target search into the existing owner.

| Criterion | Prior | Candidate | Evidence |
| --- | ---: | ---: | --- |
| Correctness | 2 | 4 | `socom_traversal_runtime.gd`: accepted rock top no longer rejects solely because its lower face protrudes; exact shape remains clear. |
| Ownership clarity | 5 | 5 | Runtime computes targets; `player_controller.gd::_advance_automatic_vault` still owns collision movement. |
| Canonical runtime parity | 3 | 5 | `map_jump_ledge_regression.gd` uses `main.tscn`, actual map geometry and commands. |
| Editor usability | 3 | 4 | Search distances saved in `config/ledge_climb.json`; no map-specific IDs in runtime. |
| Performance | 5 | 4 | Up to three additional sweeps/overlap queries only after a blocked hang attempt; not per-frame active-hang work. |
| Regression coverage | 2 | 4 | Actual map rock approaches added beside existing fixture safety, shimmy, ladder, and vault tests. |

## Results

Headless baseline after bounded hang fix:

- `relic_040` west: **PASS**, held Jump catches during physical running jump; lands at `(22.40447, 1.505254, 2.66629)`.
- `relic_038` north: **PASS**, held Jump catches in air and fresh W pulls up; lands at `(22.09629, 2.545567, 19.98582)`.
- `relic_039` north: **SAFE REJECTION**, no validated capsule-width walkable ledge from this approach. Ordinary physical jump completes without a forced grip. This does not prove every other face of this asset ungrabbable.
- Existing `ledge_climb_regression.gd`: **PASS**, including second tap, hold, release-before-W, shimmy, opt-out, tag policy, overhead, out-of-reach, thin awning, ladder, and no repeated climb.
- Existing `agls_auto_vault_regression.gd`: **PASS**, low obstacle vault and too-tall wall rejection.
- `relic_038` north second tap: **PASS**, physical jump with Jump released, then second tap catches and finishes on rock.
- Rendered multi-angle run: **PHYSICS PASS / CONTACT PARTIAL**. Paused capture pairs preserve one pose across two camera angles. The real hang is visible outside the rock, and traversal ends on top with the weapon restored. At pull-up phase `0.3408`, however, the hands have released into a chest-height pose while the body is still beside the rock. The low-rock fallback at phase `0.2794` also lacks convincing surface hand contact. Presentation timing/pose needs further work; do not label these fully polished.

Inspected render examples:

- `/private/tmp/map-ledge-relic_038_north_hold-grab-angle0.png` — stable hang.
- `/private/tmp/map-ledge-relic_038_north_hold-pullup-12-angle0.png` — phase `0.3408`, premature hand release remains.
- `/private/tmp/map-ledge-relic_038_north_hold-pullup-30-angle1.png` — phase `0.7436`, body crossing top.
- `/private/tmp/map-ledge-relic_038_north_hold-landing-angle0.png` — supported finish, weapon restored.
- `/private/tmp/map-ledge-relic_040_west_hold-grab-angle1.png` — phase `0.2794`, low-rock contact still needs pose work.

## Why the pictured awning can still fail

Two different map documents were found. Disabling the active playtest bundle
alone does not select the checked-in map: `scripts/runtime/playtest_state_collector.gd`
prefers `user://maps/active_map.json` when no session selection is provided.

The user's currently saved map spawned this physics owner:

```text
/root/SOCOM141CameraLab/AuthoredMap/Shuttered depot warehouse/CollisionShape3D
BoxShape3D — full height 6.751655 m
```

The checked-in `config/maps/current_map.json` / `relic_depot.json` explicitly
select `detailed_mesh`, producing:

```text
.../Shuttered depot warehouse/ImportedContent/PSX Old Warehouse_Texture_0/
PSX Old Warehouse_Texture_0_col/CollisionShape3D
ConcavePolygonShape3D
```

The actual front awning at `x=-16.2,z=0` is about `y=3.80181`. From nearby floor
`y=0.09`, a running jump (about 1.17 m rise) plus saved raised-hand reach 2.15 m
is about 3.41 m: not enough for this edge. A suitable raised approach is needed.
The side awning query accepted anchor `(-17.538,4.32958,8.47209)` from feet
`(-17.538,2.35,9.5)`, but this is a **query only**, not a proven physical route.

No user map was overwritten. Select the updated bundled Relic Depot map or
deliberately update the saved warehouse collision setting in Map Lab. Do not
claim a stale browser ZIP or existing saved custom map automatically changed.

## Commands and outputs

```sh
/Users/kiwimango/Applications/Godot-4.7.1.app/Contents/MacOS/Godot --headless --path /Users/kiwimango/socom-141-camera-lab --log-file /private/tmp/map-jump-ledge.log --script res://tools/map_jump_ledge_regression.gd
/Users/kiwimango/Applications/Godot-4.7.1.app/Contents/MacOS/Godot --path /Users/kiwimango/socom-141-camera-lab --log-file /private/tmp/map-jump-rendered.log --script res://tools/map_jump_ledge_regression.gd -- --capture
```

Default tests explicitly select the checked-in map for this process only.
Add `--user-map` after `--` to inspect the saved user map instead.
Result rows: `/private/tmp/map-jump-ledge-results.json`.
Geometry samples: `/private/tmp/map-ledge-geometry.json`.
Rendered frames: `/private/tmp/map-ledge-*-angle0.png` and `angle1.png`.

## Canonical main low-vault proof

`tools/main_vault_presentation_regression.gd` instantiates `main.tscn`, then
places a 0.9 m high, 0.6 m deep obstacle on an isolated collision floor at
`(500,0,500)`. The current player starts grounded and receives ordinary forward
movement commands. No staged airborne pose or forced traversal start is used.

Headless result: **PASS**. The runtime enters the `vault` slot; the equipped
weapon hides after the presentation consumer processes the new physics state.
Early/middle/late progress samples occur at approximately 0.055, 0.465 and
0.821. The body lands beyond the obstacle at `(500,0.000156,499.274)`, exits
traversal without replay, and restores the weapon.

Visual status: **PARTIAL / HAND CONTACT FAIL** for the current 1m RH vault.
It resembles the authored sideways knee-tuck vault, but the supporting hand
does not plant on the obstacle. The right wrist at phase 0.465 is
`(499.6953,1.966944,499.8661)`, approximately **1.067 m above the 0.9 m top**.
This is a presentation problem; collision completion does not establish hand
contact. Do not call this a finished planted-hand vault.

Final serial run: **PASS** gameplay checks and all eight image writes, exit
code 0. Both camera angles were inspected at all three stages and after landing.
Weapon hiding/restoration and the supported finish are visible. The hand-contact
failure above remains visible in the final images; it is not a capture artifact.

Captured two-angle frames (all under `art_source/traversal_runtime_proof/`):

- `vault-stage0-side-1.png`, `vault-stage0-side1.png` — early.
- `vault-stage1-side-1.png`, `vault-stage1-side1.png` — middle; supporting wrist misses the top.
- `vault-stage2-side-1.png`, `vault-stage2-side1.png` — late.
- `vault-landed-side-1.png`, `vault-landed-side1.png` — floor landing, rifle restored.

An earlier concurrent fullscreen attempt stalled in `frame_post_draw` while
paused/obscured. Its three automated processes were stopped. The final capture
now waits for a zero-duration SceneTree timer after node processing, pauses,
flushes the camera transform with `force_update_transform`, and calls
`RenderingServer.force_draw(false)` explicitly. It no longer waits for a paused
window to schedule another render. Run graphical proofs serially. Final log:
`/private/tmp/main-vault-final-rendered.log`.

API references: [SceneTree timer processing order](https://docs.godotengine.org/en/stable/classes/class_scenetree.html#class-scenetree-method-create-timer),
[RenderingServer explicit draw](https://docs.godotengine.org/en/stable/classes/class_renderingserver.html#class-renderingserver-method-force-draw).

```sh
/Users/kiwimango/Applications/Godot-4.7.1.app/Contents/MacOS/Godot --headless --path /Users/kiwimango/socom-141-camera-lab --log-file /private/tmp/main-vault-headless.log --script res://tools/main_vault_presentation_regression.gd
/Users/kiwimango/Applications/Godot-4.7.1.app/Contents/MacOS/Godot --path /Users/kiwimango/socom-141-camera-lab --log-file /private/tmp/main-vault-rendered.log --script res://tools/main_vault_presentation_regression.gd -- --capture
```
