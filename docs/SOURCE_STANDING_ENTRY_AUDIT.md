# Independent standing-entry audit — 2026-09-13

## Translation card

- Player intent: original SOCOM II relaxed rifle movement-entry blending.
- Acceptance: trace original default Walk selection, clip BlendTime decoding,
  timer assignment and ordinary quadratic blending with explicit evidence.
- Owner: offline `tools/source_standing_entry_audit.cjs`; the existing
  ProductionAnimation/AnimationTree remains the runtime animation owner.
- Must not change: runtime code, profiles, movement/collision, camera/aim,
  weapon/shot authority, networking, source assets and current user sessions.
- Proof: hash-pinned original instruction slices, decoded original action set,
  current selected source resource, and disclosed synthetic fixture inputs.

System delta: **MERGE evidence**. Scores current → audited candidate (0–5):
correctness 3→4, ownership clarity 5→5, runtime parity 3→3, editor usability 3→4,
performance 5→5, regression coverage 3→4. Evidence: original-reader and entry
fixtures in `tools/source_standing_entry_audit.cjs`; selected source provenance
in `assets/animations/seal_reference/seal_walk_alert.tres:164`; current runtime
restriction in `operator_locomotion_blend_tree.gd::source_grounded_blend_seconds`.
Evidence alone does not raise canonical runtime parity or activate a feature.

## Confirmed mismatch before integration

The current graph applies source duration/curve only when its destination has
an entry in `source_idle_blend_times`. The route builder populates `idle` and
`idle_crouch`, but not `standing`. Thus an ordinary relaxed rifle idle→standing
entry keeps the project duration and linear curve. The relevant pre-patch code:

```gdscript
# scripts/player/operator_locomotion_blend_tree.gd:587
var seconds := float(source_idle_blend_times.get(to_state, -1.0))
return seconds if seconds >= 0.0 else fallback
```

`operator_animation_driver_pose.gd:286–309` passes the profile transition
duration into this graph. Driver defaults are 0.12 seconds for general
transitions and 0.075 seconds for locomotion→locomotion. No engine limitation
requires these particular values or a linear curve.

Correction to an early audit hypothesis: the actual `seal_crouch` idle resource
has an explicit `BlendTime=0.5`; the absent crouch field in an existing test is a
synthetic fallback case. It is **not** a current crouch-idle missing-default bug.

## Original chain

The source action table at `ZSealEtc 0x661068` identifies action2 as Walk.
The pinned `Seal anim set` reader maps Walk/default to `seal_walk_alert`.
The current rifle family slot `locomotion/walk_forward` selects
`source_walk_alert`, whose source settings lack `BlendTime`.

1. `ZSealEtc 0x586ae8–0x586b14` tests whether Walk2, Jog3 or Run4 is active.
   When none is active, `0x586b24–0x586b34` requests Walk2 via `0x588bc0`.
   Other retained callers repeat this at `0x5855fc` and `0x5868ac`.
2. `0x588cf4–0x588d28` resolves the active mode then default mode if needed.
3. `0x5894f0–0x589500` forwards that selected clip to `FTSCore 0x28dc90`.
4. `FTSCore 0x28df74–0x28df7c` copies destination clip+32 into actor+376/+380.
5. The ordinary actor timer decrements remaining seconds before evaluating
   `FTSCore 0x2874f0`, the quadratic easing function already independently tested.

The reader assigns its default **before** looking for an override:

```text
FTSCore 0x287f28 lui v0,0x3ecc
FTSCore 0x287f2c ori v1,v0,0xcccd   # float32 0.4000000059604645
FTSCore 0x287f44 sw v1,32(v0)      # lookup call's delay slot
FTSCore 0x287f48 beq v0,zero,0x287fd0
```

Explicit numeric overrides, including zero, replace that value. The source
field parser accepts float and integer scalar types. The runtime adapter may
still reject malformed data; absent and malformed are different cases.

```text
FTSCore 0x28df74 lwc1 f0,32(s5)    # destination clip BlendTime
FTSCore 0x28df78 swc1 f0,8(s6)     # actor+376 remaining
FTSCore 0x28df7c swc1 f0,12(s6)    # actor+380 total
```

## Verification and limits

Run `node tools/source_standing_entry_audit.cjs`. It checks five original
reader/default/override/timer-copy cases, three movement-entry request slices,
and seven original ordinary timer/curve cases. Original module and decoded
reader hashes are pinned in the script. It can write a new report only under
`/private/tmp/` via `--output=...`.

The parser lookup result, actor records and scalar fields are disclosed fixture
inputs. No unknown function is stubbed. The full reader lookup, allocator,
controller gates and full playable actor frame are not executed; their call
chain is static original-code evidence. This proves a bounded default-mode
standing-entry duration/curve, not all animation behavior.

The source snapshot and loop-phase inheritance are separate semantics. A
duration/curve-only integration must not inadvertently enable the existing
idle-only snapshot or phase-transfer helpers for standing entry. Firing,
nonzero readiness, pistol, stance changes and action exits need their own
guards and source proof. No broad movement-start, speed-tier, readiness timer
or action-state reconstruction is justified by this audit.

Godot supports both seconds-based `xfade_time` and a custom unit `xfade_curve`
on the existing transition resource. An unset curve is linear; these are
supported mechanisms, not an engine blocker. See the official
[AnimationNodeTransition reference](https://docs.godotengine.org/en/stable/classes/class_animationnodetransition.html).
Moving extracted meshes/clips to another engine does not supply the missing
source controller rules; this comparison identifies reconstruction work, not
evidence that Unreal is required.
