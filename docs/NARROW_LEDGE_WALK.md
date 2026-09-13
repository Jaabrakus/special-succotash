# Narrow ledge walk: bounded solver

## Translation card

- Player intent: after a validated climb, shuffle along a supported narrow top without stepping into a gap.
- Acceptance: retain the existing five-point 0.85-radius support footprint; reject unsafe/forbidden/dynamic/steep tops; return only bounded tangent velocity, stop at obstructions, and exit on broad support.
- Owner: `SocomNarrowLedgeMotor` computes a solution; the existing `CharacterBody3D` alone applies movement and collision.
- Must not change: existing climb acceptance, capsule size, aim, camera, weapon/damage authority, and networking.
- Focused proof: `tools/narrow_ledge_motor_regression.gd`. This fixture does not replace canonical `main.tscn` integration/render proof.

## System delta before implementation

Decision: **MERGE**, add a query-only solver under the existing movement owner. Current code declares `NARROW_LEDGE` but has no solver (`scripts/traversal/socom_traversal_contract.gd`, `socom_traversal_runtime.gd`). Existing source clips are assets, not a working runtime state.

| Criterion | Existing | Candidate target | Evidence |
| --- | ---: | ---: | --- |
| Correctness | 0 | 4 | Candidate revalidates five-point support and actual capsule queries before returning motion. |
| Ownership clarity | 5 | 5 | Neither solver nor animation writes the body transform. |
| Canonical runtime parity | 0 | 0 | Parent runtime integration and main-scene verification remain required. |
| Editor usability | 1 | 4 | Saved `config/narrow_ledge.json`, with shared climb policy read from `config/ledge_climb.json`. |
| Performance | 5 | 4 | Bounded ray/shape queries per small movement step; no independent process loop. |
| Regression coverage | 0 | 4 | Focused supported/unsupported, end, obstruction and invalid-input fixtures. |

The focused fixture passed on Godot 4.7.1. Candidate correctness and coverage are limited to the query-only solver; canonical runtime parity remains zero until integration and main-scene proof.

## API and boundaries

`classify(body, landing, normal, capsule_height, capsule_radius)` returns an accepted context containing `anchor`, `travel_axis`, `surface_normal`, and capsule dimensions. It is intended only after the caller has validated the climb. It does not infer jump reach or create a climb.

`solve(body, world_desired, context, delta)` returns `velocity`, `finished`, and `progress_delta`. The latter is the approved proposed displacement along the travel axis, not a measured body displacement. The controller must still call `move_and_slide()` and may measure its actual travel for presentation.

Narrow classification requires all five existing-radius samples to support the body. Both farther normal-side samples must find an edge. Support continuing on either side means ordinary broad locomotion, including a normal climb landing near the edge of a large container. Broad support is rejected for entry and ends an active narrow state. This is not razor-thin-beam balancing and does not reduce the player capsule.

The current validated pull-up remains the narrow-ledge entry animation until `CMC_NarrowFloor_Hang_To_Stand_01` has its different timing/contact calibrated. `CMC_NarrowFloor_IdlePoses` needs a selected held pose, not a looping pose bank. `Walk_L/R` are wall-facing lateral shuffles; their root translation must not independently move the body.

## Integration status

This bounded task adds the solver, profile, and fixture only. Runtime state handoff, input dispatch, animation slots, feature manifest, canonical boot and rendered gameplay proof are handled separately. Do not label this module alone as playable integration.

## Focused result

`NARROW_LEDGE_MOTOR PASS []`, Godot 4.7.1 headless, log `/private/tmp/narrow-ledge-motor-regression.log`.

Coverage: narrow and broad tops (including an ordinary near-edge climb landing), razor-thin/steep/forbidden/stair/dynamic rejection, shared tag-required policy, capped/reversed/tangent-only motion, large-delta step bound, edge and capsule-wall stop, ceiling rejection, broad exit, support loss, nonfinite input, and rejection of fabricated smaller capsule dimensions. Existing body transforms remain unchanged by query and solve calls.

Reusable lesson: standalone regression scripts should type newly added helpers through their explicit preloaded resource (`var motor: Motor`), not assume the editor has already refreshed its global script-class cache. A parser failure can still exit Godot with code zero; check the log and final PASS marker.

## Main-scene proof translation card

Intent: prove a real airborne approach flows through stable hang and the existing calibrated pull-up into narrow idle/shuffle. Acceptance: actual A/D movement is tangent-only and at most 0.6m/s, idle does not advance the pose bank, ledge ends retain support, rifle stays stowed with fire/ammo rejection, overhead hang IK is inactive, and fresh Jump returns to ordinary airborne motion. Owner remains the canonical controller/runtime; the test only queues normal movement commands after fixture setup.

`tools/main_narrow_ledge_regression.gd` instantiates `res://main.tscn` and builds a static 5m-wide, 1.15m-deep, 2.55m-high ledge away from the map at world (500,0,500). Optional `--capture` saves two paused rendered angles for jump approach, hang, pull-up, idle, both shuffles, edge stop, and jump exit. This proof must run after runtime integration; its existence is not a passing result. Source foot/hand contacts remain unverified on arbitrary map geometry.

The shared profile adds `stride_metres: 0.495` from measured CMC shuffle displacement and `idle_pose_seconds: 0.0` to select a single idle pose. The canonical animation consumer must use actual controller travel rather than proposed solver displacement.

First main headless pass verified traversal handoff, tangent movement, 0.6m/s cap, edge stop, weapon stow/fire lock and jump exit. The subsequent graphical run added foot landmarks and **failed**: the visible pose remained a combat/run-like pose rather than the intended arms-out CMC shuffle, with toe landmarks up to 20.3cm below the top. That failed capture is not accepted visual proof. The presentation route owner must be corrected and both tests rerun before reporting completion.

The main fixture now continuously feeds held inputs on each physics tick; one-shot Jump presses are consumed once. Queuing one command per rendered frame created artificial neutral-input gaps during capture and invalidated the original graphical held-forward test. The fixture change does not change controller input behavior.

## Integrated main-scene result

The runtime owner subsequently integrated the solver and corrected the presentation routing. Narrow traversal deliberately retains grounded movement, so a route that admitted traversal clips only for `VAULTING` silently evaluated ordinary locomotion instead. The canonical pose selector now admits active traversal presentation as well (`scripts/player/operator_animation_driver_pose.gd`, `_modern_state_for_clip`):

```gdscript
if String(clip_name).begins_with("traversal_") and (movement_state == &"VAULTING" or bool(get("traversal_presentation_active"))):
    return clip_name
```

Both main-scene runs subsequently completed with `MAIN_NARROW_LEDGE PASS []`: `/private/tmp/main-narrow-ledge-headless.log` and `/private/tmp/main-narrow-ledge-render.log`. The fixture also asserts the evaluated modern graph state equals the selected traversal clip, guarding the previously misleading clip-name-only result. Canonical runtime parity is now demonstrated for this main-scene fixture, not asserted for every map surface.

The successful graphical run produced two angles each of approach, hang, pull-up, idle, left/right shuffle, edge stop and jump exit under `art_source/traversal_runtime_proof/narrow-*.png`. Inspection showed the authored arms-out wall-facing narrow pose, visibly stowed rifle, supported idle/stance feet and ordinary jump exit. Measured idle toe landmarks were −4.2mm and −2.3mm relative to the platform top. Right/left shuffle support toes were +0.5mm and −2.4mm; swing toes were +69mm and +52mm. These are bone landmarks, not exact mesh-sole contact tolerances.

The existing calibrated `CMC_Climb_To_Standing` remains the pull-up; the imported `CMC_NarrowFloor_Hang_To_Stand_01` has **not** become a runtime replacement. This proof does not validate arbitrary rock/awning geometry, razor-thin beams, full per-frame foot contact, or network prediction. Review narrow captures separately from the main task's other traversal captures and gates.
