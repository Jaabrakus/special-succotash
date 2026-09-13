# Ledges, hangs and ladders

## Current controls — hang-first revision

Airborne short-ledge correction (2026-09-12): an airborne player reaching a 2 m
ledge previously failed with `Hang position blocked`: the 2.15 m hang drop put
the feet below ground. With `airborne_floor_blocked_hang_pull_up` enabled, a
downward hang sweep blocked specifically by walkable floor selects the existing
validated pull-up motor. Wall/ceiling hits still reject. Reach, support and the
complete up/across sweep are checked before this decision. Tall unobstructed
ledges retain hang-first controls. The motor still returns velocity; only the
CharacterBody moves. `tools/airborne_short_ledge_regression.gd -- --main` verifies
the actual canonical player, physical jump/approach, landing and ceiling rejection.
`--capture` shows early/mid/late presentation; those frames still have hand-to-edge
alignment errors. This change fixes acceptance, not the full animation/contact port.

Jump taps and held Jump now grab first. Release forward after grabbing, then W pulls up; S or Crouch drops; A/D shimmy. Jump plus forward also pulls up. Holding W during entry does not skip the hang. This supersedes the direct-tap climb controls below.

Airborne input correction: holding Jump also probes with neutral or partial movement input. Neutral input uses the command's authoritative aim yaw; full-gait input is required only by automatic low vaults. Current feet position still determines reach. This does not change grounded tall-grab policy, hand alignment, animation selection, or timing. Translation card: accept reachable airborne held-Jump grabs without requiring movement/ground contact; owner remains `SocomTestPlayer`; protect geometry safety, detach cooldown, low-vault rules, camera and damage. Focused proof: `tools/airborne_ledge_input_regression.gd` checks both input cases and airborne hold/drop/cooldown. Initial baseline reproduced the partial-input miss; the neutral-input fixture needed spawn landing recovery before its Jump could launch. Keep the launch assertion so a rejected takeoff cannot be mistaken for a failed grab.

Translation card: hang before climbing, directional control while hanging, one pull-up completion. Existing CharacterBody controller owns movement; existing animation driver consumes state. Protect reach, clearance, camera, damage, jump trajectory and normal stairs. Proof: ledge regression including thin awning, A/D travel, unsupported edge, S drop and completed presentation exit.

MERGE: direct climb controls scored 2/5/5/4/4/3 for correctness/ownership/parity/editor/performance/coverage; hang-first controls score 4/5/5/4/3/5. Extra queries run only during shimmy. `forward_released` lives in the existing serialized traversal context. Reach has 1 mm rounding tolerance. Thin awnings use a top-down face probe; suitable rock collision follows the same rules, but arbitrary rock assets have not been visually verified. Pull-up closure is removed once before animation caching, not on each player instance.

## Translation card

Player intent: jump toward reachable geometry, catch a ledge, pull up, and climb or slide down ladders. Acceptance: geometry queries accept reachable supported tops, reject blocked/too-high tops, hang holds until fresh Jump or Crouch, ladders move up/down and hold-Jump slides without immediate detach. Owner: `SocomTestPlayer` CharacterBody3D, with existing `SocomTraversalRuntime` query/velocity helpers. The animation driver consumes traversal state and is presentation only. Protect normal jump impulse/gravity, low automatic vaults, aim, damage and network authority. Traversal occupies both hands, so it consumes the existing authoritative mobility fire-lock API rather than changing weapon rules independently.

## Controls and reach

- Move toward a ledge and press Jump for a standing-reach pull-up.
- For a higher ledge, jump toward it, then tap Jump again when it is reachable to climb directly. A fresh tap is not throttled by the periodic probe timer and does not require full movement input; with movement released it probes along the command's aim yaw. Reach and clearance still apply; rejected taps do not add another jump impulse.
- Alternatively keep Jump held while approaching to catch into a hang when the *current physical feet position* puts the ledge within raised-fingertip reach. A fresh Jump pulls up; Crouch drops. Detach/retry cooldowns remain enforced for both input styles.
- Face an authored ladder and press Jump to attach. Forward climbs; Back descends. Release the attach press before using Jump again. Tap Jump to detach. Hold Jump for 0.22 seconds to slide down at 3.5 m/s; release to stop/grip. Crouch detaches immediately.

`config/ledge_climb.json` is the shared tuning profile. Initial raised-fingertip reach is **2.15 m above the feet**, an explicit approximation for the current operator, not a measured SOCOM II value. Actual jump rise is already in body position, so it is never added a second time. Ordinary walking/jump physics remain unchanged.

## Map authoring

Any suitable **static collidable** ledge is eligible by default. Place `no_climb` on a collider or its ancestor to block it. To require an allowlist, enable `require_climbable_group` and add `climbable` to permitted geometry. Tops need a walkable normal, support beneath the footprint, a collision-free upward/across sweep, and standing clearance. Players, rigid bodies and moving platforms are excluded. Decorative noncollidable meshes do not count.

Instance `scenes/traversal/climbable_ladder.tscn` beside a ladder mesh in Godot. Edit its Bottom, Top and Exit markers as **player foot positions**. Keep the body path outside the wall; put Exit over a real top platform, high enough to clear its edge. The editor updates the detection volume from the endpoints. The volume uses layer 128 and does not add solid collision. The script creates no ladder art and existing maps are not automatically populated with these markers.

Dedicated retargeted clips now present hang, pull-up, ladder idle, ladder movement and ladder slide; their names live in `config/ledge_climb.json`, and paths in the canonical animation map and active pistol-hybrid preset. The equipped gun is hidden while both hands are occupied. Runtime library copies have hip translation anchored to standing height, so the clip cannot add another body lift on top of CharacterBody movement. Hanging/slide hold a pose; ladder stepping is keyed to distance, and pull-up to motor progress. Exact fingertip-to-ledge contact remains unpolished; this is not contact IK. Ladder art and map placements are still required.

Presentation uses `player_controller.gd::get_traversal_presentation()`. Snapshot encoding sends that small visual contract to remote proxies; it does not give animation authority over movement.

## Runtime chain and code evidence

Movement command Jump/held movement -> `player_controller.gd::_try_begin_automatic_vault(..., true)` -> shared ledge profile -> `socom_mantle_motor.gd::probe_climb` -> traversal context -> controller velocity -> `move_and_slide()` -> animation driver traversal branch. Ladder scene supplies world endpoints, not a second movement motor.

```gdscript
var foot := body.global_position
var reach := float(climb_profile.raised_hand_reach_m)
```

Grounded reach plus current jump height is thus a world-space test. The `CLIMBING`, `LADDER`, `MANTLE` context and existing motor fields are already serialized by `SocomMovementState`; ladder hold timers are stored in that context, not in local Input or an unsynchronized visual timer.

## System delta

MERGE (fresh-tap input): periodic-only probing, full-gait gating and airborne hang-first behavior scored 2/5/5/4/4/3 for correctness/ownership/parity/editor/performance/coverage. Explicit tap probing with direct mantle scores 4/5/5/4/4/5. Evidence: `player_controller.gd::_try_begin_automatic_vault` and second-tap regression cases with zero, partial and full movement while the periodic probe timer is active. Geometry safety and network command ownership remain unchanged; no new input timer or unsynchronized state is introduced.

MERGE: the old motor only accepted a landing *behind* low cover, and the controller required ground/speed. Extend it with deliberate ledge probes, held states and authored ladder endpoints rather than adding a competing body mover. Scores (correctness, ownership, canonical parity, editor usability, performance, coverage): old 2/5/5/2/4/3; candidate 4/5/5/4/4/4. Evidence: controller, traversal runtime/motor, ladder scene and `tools/ledge_climb_regression.gd`.

REPLACE (presentation only, following visual feedback): generic Mixamo climb used for all traversal states scored 2/5/4/2/4/3; dedicated retargeted state clips with anchored hips and replicated presentation score 3/5/5/4/4/4. Evidence: `operator_asset_runtime.gd::_anchor_traversal_hips`, `operator_animation_driver_runtime.gd::_advance_traversal_presentation`, rendered ledge regression and proxy state checks. Remaining contact gaps prevent a higher correctness score. Source animation files remain untouched.

## Verification and limits

Focused regression covers standing pull-up, reach gained by jumping, hang stability/pull-up/drop, unreachable height, overhead obstruction, opt-out/allowlist policy, ladder ascent/descent/top exit/tap detach/hold slide/release grip, and traversal context round-trip through the movement codec. Run with the installed Godot 4.7.1 executable and `--script tools/ledge_climb_regression.gd`; `-- --capture` produces rendered fixture images in `/private/tmp/ledge-*.png`.

Official API references: [CharacterBody3D](https://docs.godotengine.org/en/latest/classes/class_characterbody3d.html) and [PhysicsDirectSpaceState3D](https://docs.godotengine.org/en/latest/classes/class_physicsdirectspacestate3d.html). Latest documentation has an unstable-version warning; APIs are exercised with installed 4.7.1. Shape motion queries do not detect initial overlap by themselves; the existing standing-space overlap check supplements the sweeps. No real internet multiplayer session or map-wide ladder placement is claimed by these fixture tests.
