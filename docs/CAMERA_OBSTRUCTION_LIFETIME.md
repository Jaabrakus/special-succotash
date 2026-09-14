# Retained camera obstruction lifetime

## Translation card — 2026-09-13

- Player intent: removing a wall must not interrupt camera updates during the
  existing short obstruction-release guard.
- Acceptance: applying a retained collision result after its wall is freed
  clears only dead node references, completes the remaining state update, and
  preserves the legal camera endpoint, release duration and aim values.
- Owner: `SocomCameraStateController.apply_collision_result`, the existing
  consumer of the canonical camera collision result.
- Protected: collision detection and validation, obstruction timing, framing,
  source camera math, movement, animation, aim and shot/damage ownership.
- Proof: extend `tools/camera_obstruction_guard_regression.gd` with real freed
  and queued-free nodes, valid/missing/wrong-type references, and the same held
  result replay used by `main.tscn`; root reruns the native main wall-removal
  proof. No source scene or user session is replaced.

## System delta

Decision: **MERGE** a validity gate at the existing state-consumer seam.
Current scores (0–5): correctness2, ownership5, runtime parity5, editor
usability4, performance5, regression3. Candidate: correctness5, ownership5,
runtime parity5, editor usability4, performance5, regression5.

Evidence: `scripts/camera/camera_frame_pipeline.gd` intentionally retains a
collision-result dictionary during `_stabilize_obstruction_release`; its
Object references can outlive the collided wall. The native proof log
`/private/tmp/camera-hybrid-native-v2.log` records `Trying to cast a freed
object` at `scripts/camera/camera_state_controller.gd:21`. The same retained
dictionary also carries `cutout_node`, which must use the same lifetime gate.
This failure proves stale-reference handling is unsafe, not that the physical
collision endpoint or source camera formula is wrong.

## Implementation and verification

The state consumer now uses `_live_node_3d` for both retained object fields:

```gdscript
if typeof(value) != TYPE_OBJECT or not is_instance_valid(value):
    return null
return value as Node3D if value is Node3D else null
```

Files changed:

- `scripts/camera/camera_state_controller.gd`: only lifetime validation of
  `collider_node` and `cutout_node`; all physical result fields are unchanged.
- `tools/camera_obstruction_guard_regression.gd`: existing five checks retained
  plus queued-free/immediate-free result replay, subtype/missing input cases,
  completed state update, unchanged aim, endpoint and normal release.
- `config/feature_contracts/camera_obstruction_guard.json`: explicit existing
  owner/profile/runtime/main proof chain and this scoped system delta.
- This document, written before the runtime edit.

Focused regression: **PASS19 checks**, Godot4.7.1, exit0;
`/private/tmp/camera-obstruction-lifetime.log`. No script error. The platform
CA-certificate warning is unrelated to collision and remains present. The
first patch failed its surrounding-line match and made no runtime edit; the
narrower patch applied successfully. The main native wall-removal rerun is
owned by the parent task and is not claimed passing here before its result.
Feature-contract gate: **PASS151 contracts** including the new lifecycle
contract; `/private/tmp/camera-obstruction-contracts.log`. Scoped
`git diff --check` also passes.

The two named workflow skills confined this fix to the canonical state
consumer and required an executable ownership/lifecycle regression. Godot's
[is_instance_valid contract](https://docs.godotengine.org/en/stable/classes/class_%40globalscope.html#class-globalscope-method-is-instance-valid)
is the API basis for checking a retained reference before subtype casting.
Original failure logs are preserved.
