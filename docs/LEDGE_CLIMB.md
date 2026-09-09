# Ledges, hangs and ladders

## Translation card

Player intent: jump toward reachable geometry, catch a ledge, pull up, and climb or slide down ladders. Acceptance: geometry queries accept reachable supported tops, reject blocked/too-high tops, hang holds until fresh Jump or Crouch, ladders move up/down and hold-Jump slides without immediate detach. Owner: `SocomTestPlayer` CharacterBody3D, with existing `SocomTraversalRuntime` query/velocity helpers. The animation driver consumes traversal state and is presentation only. Protect normal jump impulse/gravity, low automatic vaults, aim, damage and network authority. Traversal occupies both hands, so it consumes the existing authoritative mobility fire-lock API rather than changing weapon rules independently.

## Controls and reach

- Move toward a ledge and press Jump for a standing-reach pull-up.
- For a higher ledge, jump and keep Jump held while approaching. Catch it when the *current physical feet position* puts it within raised-fingertip reach. A fresh Jump pulls up; Crouch drops.
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

MERGE: the old motor only accepted a landing *behind* low cover, and the controller required ground/speed. Extend it with deliberate ledge probes, held states and authored ladder endpoints rather than adding a competing body mover. Scores (correctness, ownership, canonical parity, editor usability, performance, coverage): old 2/5/5/2/4/3; candidate 4/5/5/4/4/4. Evidence: controller, traversal runtime/motor, ladder scene and `tools/ledge_climb_regression.gd`.

REPLACE (presentation only, following visual feedback): generic Mixamo climb used for all traversal states scored 2/5/4/2/4/3; dedicated retargeted state clips with anchored hips and replicated presentation score 3/5/5/4/4/4. Evidence: `operator_asset_runtime.gd::_anchor_traversal_hips`, `operator_animation_driver_runtime.gd::_advance_traversal_presentation`, rendered ledge regression and proxy state checks. Remaining contact gaps prevent a higher correctness score. Source animation files remain untouched.

## Verification and limits

Focused regression covers standing pull-up, reach gained by jumping, hang stability/pull-up/drop, unreachable height, overhead obstruction, opt-out/allowlist policy, ladder ascent/descent/top exit/tap detach/hold slide/release grip, and traversal context round-trip through the movement codec. Run with the installed Godot 4.7.1 executable and `--script tools/ledge_climb_regression.gd`; `-- --capture` produces rendered fixture images in `/private/tmp/ledge-*.png`.

Official API references: [CharacterBody3D](https://docs.godotengine.org/en/latest/classes/class_characterbody3d.html) and [PhysicsDirectSpaceState3D](https://docs.godotengine.org/en/latest/classes/class_physicsdirectspacestate3d.html). Latest documentation has an unstable-version warning; APIs are exercised with installed 4.7.1. Shape motion queries do not detect initial overlap by themselves; the existing standing-space overlap check supplements the sweeps. No real internet multiplayer session or map-wide ladder placement is claimed by these fixture tests.
