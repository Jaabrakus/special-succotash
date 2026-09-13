# Hang-only edge eligibility

## Translation card (before edit)

- Intent: grab and shimmy along a safe handhold even when the top cannot support standing; remain hanging when forward cannot safely climb.
- Acceptance: actual main-scene jump reaches a finite-width grip, settles collision-clear, refuses unsafe pull-up, allows bounded supported shimmy and drop. Removing landing support while hanging blocks a previously possible pull-up.
- Owner: canonical CharacterBody3D through SocomTraversalRuntime and SocomMantleMotor. Presentation reads hang_style/can_pull_up; does not own motion.
- Protected: jump/reach, camera, weapon/damage, map collision and narrow-ledge walking. No decorative/dynamic/no_climb exemption.
- Proof: new main-scene hang-only regression plus existing ledge, map and warehouse safety tests. Rendered free/braced poses require separate visual verification.

## System delta

Old/full-landing prerequisite versus candidate/separate grip and landing scores:
correctness2/4, ownership5/5, canonical parity5/5, usability3/4,
performance5/4, regression coverage2/4. MERGE subject to tests.
Evidence: `socom_mantle_motor.gd::_probe_climb_top` rejects before a hang can
exist if the five-point standing footprint fails. `socom_traversal_runtime.gd::pull_up`
checks sweeps but trusts stored support/landing. The candidate checks actual
finite-width/depth top grip strips, preserves clear hanging capsule/path, and
revalidates support and landing before leaving hang.

Intentional acceptance difference: insufficient standing width or clearance
can allow **hang only** when the hanging capsule is safe. It does not permit a
blocked hanging capsule, imaginary razor-edge grip, or unsafe pull-up.

## Implemented chain

`scripts/traversal/socom_mantle_motor.gd::_probe_climb_top` first retains the
existing full standing-footprint proof. If that fails, the new hang-only route
requires six measured top samples across saved hand width/depth:

```gdscript
if bool(landing.get("accepted",false)): return landing
if not _has_grip_strip(body, top_point, top.normal, top.collider, direction):
    return _rejection("Insufficient solid hand grip")
```

The accepted grip sets `can_pull_up=false` and its specific `pull_up_reason`.
The full-support path is not narrowed by the extra grip-strip test: doing so
regressed faceted rock038 by selecting unnecessarily deep anchors. Restoring
the established full-support path made the real rock regressions pass again.

`scripts/traversal/socom_traversal_runtime.gd` sweeps to a hang point and checks
the exact live capsule shape there. Existing bounded outward search remains.
A grounded target is measured against its supporting floor and moved up only
the body's safe margin to avoid rejecting submillimetre solver penetration.
No capsule is shrunk for this check.

`pull_up` now refreshes the acquired anchor's current top, all five support
points, actual capsule up/across sweeps, and standing clearance. A former valid
landing cannot survive a removed support or new blocker simply because the
old context said it was valid. Reach is measured to the acquired handhold;
the climb itself raises feet above the hold without adding a hypothetical jump.

`shimmy` rechecks grip/capsule and same-height/same-facing edge, stores current
eligibility, and can continue on hang-only surfaces. `_hang_style` queries a
real wall at the saved brace height/distance. No wall means `free`.
`scripts/player/player_controller.gd::get_traversal_presentation` passes
`hang_style`, `can_pull_up`, `pull_up_reason` and chooses `hang_free` /
`pull_up_free` when appropriate, preserving low-mantle ownership.

## Test results

`tools/main_hang_only_regression.gd` instantiates `main.tscn` and adds isolated
finite test geometry at (600,0,600). It does not claim those fixtures are map
assets. Each acquisition starts grounded and accelerates/jumps physically.

PASS, including after the parent's narrow-walk hooks were integrated:

- Free suspended beam: depth0.22m, top2.6m, real airborne grip, stable hold.
- No safe feet: fresh W remains hanging; S drops onto floor.
- Grip-only shimmy along the beam succeeds without crossing unsupported ends.
- Full-height wall beneath the same narrow top selects braced hang.
- Removing a previously wide landing while hanging blocks pull-up.
- `no_climb`, 0.025m razor-depth beam, and blocked hanging capsule all reject.
- Settled free wrist diagnostic: errors `[0.00000023841858,0]` metres,
  evaluated weights `[1,1]`, clip `traversal_hang_free`.

Logs:

- `/private/tmp/main-hang-only-contact.log`: MAIN_HANG_ONLY PASS after narrow hooks.
- `/private/tmp/hang-only-map-fixed.log`: MAP_JUMP_LEDGE PASS, rock038/040 retained;039 rejects.
- `/private/tmp/hang-only-ledge-final.log`: LEDGE_CLIMB_REGRESSION PASS.
- `/private/tmp/hang-only-warehouse.log`: WAREHOUSE_AWNING PASS, all five cases.
- `/private/tmp/awning-free-final-rendered.log`: graphical real-awning late held approach PASS.

Only intentional old-test changes: the overhead fixture now asserts a safe
hang and **failed pull-up**, then releases grip before later cases. Shimmy
stops at the hand-width margin, not the wider standing-footprint margin.
The test blocker is `no_climb` so testing its obstruction cannot accidentally
add another valid grip. Initial fixture child-name error was fixed by retaining
the actual typed CollisionShape3D reference; that failed test was terminated.

## Remaining visual limitation

Actual awning captures use the measured free style: the building wall is too
far inward to brace feet. Both midpoint views still show an upper-body/awning
intersection at pull-up phase≈0.455. Physics succeeds, but that mesh contact is
**Partial**, not hidden by the passing motion assertions. Parent owns further
presentation correction. Full-support and narrow-walk behavior are distinct;
this pass does not certify the latter.
