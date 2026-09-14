# Source-backed standing rifle idle

## Translation card — 2026-09-13

- Player intent: an idle standing rifle uses the original relaxed Stand pose,
  with separate ready and accepted-fire poses, and returns to idle afterward.
- Acceptance: the live main graph selects the preserved `seal_stand` conversion
  for unready standing idle, `seal_stand_alert02` for ready, and `seal_fp_stand`
  for accepted fire. Idle/fire/return samples remain finite with the current
  selected character and no movement/camera/scale changes.
- Owner: existing `SocomOperatorAnimationDriver` and its AnimationTree route;
  the shared family animation-slot mapping is the authored decision.
- Scope: only the rifle standing idle family slot, its existing focused
  regression/contract, and a main-scene regression/render observer.
- Protected: character assets and measured scale, camera/aim, movement,
  crouch/prone, reload/lean, source weapon files/catalog, server shot/damage,
  source clip originals and all existing wrist/weapon correction ownership.
- Proof: original animset mode tags, live graph selection and weighted ready
  transition, real accepted shots in `main.tscn`, early/middle/late rendered
  idle/fire/return from rear and side. Socket proximity is not full pose parity.

System delta MERGE: source mode evidence reveals that the previous profile
forced a ready variant into unready idle. Current scores (0–5): correctness2,
ownership5, runtime parity5, editor usability4, performance5, regression3.
Candidate: correctness4, ownership5, runtime parity5, editor usability4,
performance5, regression4. Evidence: saved family slots and original mode tags,
`operator_locomotion_route_builder.gd` already has separate idle/ready branches;
only their source selection changes, with no extra per-frame code or writer.
This is a bounded semantic correction, not approval of all target-rig poses.

## Source evidence and diagnosis

Original extracted
[animset.rdr.json](/Users/kiwimango/Downloads/SOCOM-II-animation-extractor/output/readers/animset.rdr.json:2368):

```text
Seal anim set / Stand / modes:
  default: seal_stand
  ready: seal_stand_alert01 (0.5), seal_stand_alert02 (0.5)
Seal anim set / Fire stand: seal_fp_stand
```

The previous `config/operator_animation_map.json` mapped both `idle_standing`
and `ready_standing` to `seal_stand_alert02`. The graph therefore never selected
the source default Stand when readiness was zero. The existing resource
`assets/animations/seal_gameplay/idle_rifle.tres` is already the preserved
`seal_stand` conversion; it does not need to be rebaked or copied again.

The original runtime decision to select default versus ready in every original
combat context is not recovered by these mode tags. This correction restores
the meaning of this project's unready input; it does not prove SOCOM II always
chooses default Stand whenever its player is stationary.

The existing graph explicitly excludes its legacy idle upper-body overlay when
source firing locomotion is enabled. It blends `standing_idle_base` toward the
ready/fire branch according to readiness, so changing only the saved idle slot
is sufficient to restore distinct default/ready source selection. The family
mapping takes precedence over individual weapon animation slots.

The existing source-specific weapon pass still adjusts roll/reach and solves
both grips after the source body pose. This task does not blanket-disable those
layers: the modern derivative and weapon meshes are not original source meshes,
and removing grip fitting without proof previously left visible contact gaps.
The chosen source clip is exact provenance; the final skinned pose is retargeted
and contact-adapted, not a proven one-for-one original rendering.

Official API references consulted: Godot's AnimationTree documentation assigns
playback/transitions to the tree (not simultaneous AnimationPlayer playback),
and AnimationNodeBlend2 blends its two inputs by a scalar weight. Existing
4.7.1-supported APIs are retained:
[AnimationTree](https://docs.godotengine.org/en/stable/classes/class_animationtree.html),
[AnimationNodeBlend2](https://docs.godotengine.org/en/stable/classes/class_animationnodeblend2.html).

## Implementation and verification

The sole runtime change is the saved key in
[operator_animation_map.json](/Users/kiwimango/socom-141-camera-lab/config/operator_animation_map.json:418):

```json
"TWO_HAND_RIFLE": {
  "firing_standing": "seal_fp_stand",
  "idle_standing": "idle_rifle"
}
```

The separate existing `ready_standing: seal_stand_alert02` remains unchanged.
[operator_locomotion_route_builder.gd](/Users/kiwimango/socom-141-camera-lab/scripts/player/operator_locomotion_route_builder.gd:203)
consumes the saved selection with its existing graph:

```gdscript
root.add_node(&"standing_idle_base", graph._animation_node(equipped_idle), Vector2(-300.0, -90.0))
root.add_node(&"source_standing_alert", graph._animation_node(equipped_ready))
root.add_node(&"source_standing_fire", graph._animation_node(standing_fire))
```

No new pose writer, override, clip rebake, rate change, camera/scale change,
weapon configuration or physics change was required. The workflow skills kept
this correction in the shared saved profile and required a main-scene proof.

Changed supporting files:

- [source_rifle_ready_fire_regression.gd](/Users/kiwimango/socom-141-camera-lab/tools/source_rifle_ready_fire_regression.gd:25):
  default node plus source metadata assertions; existing ready/fire and pistol
  assertions retained.
- [source_rifle_default_idle_regression.gd](/Users/kiwimango/socom-141-camera-lab/tools/source_rifle_default_idle_regression.gd:47):
  actual `main.tscn`, canonical M4/AK equip and accepted shots, continuous
  contact checks, preserved character/capsule, state-boundary return captures.
- [source_rifle_ready_fire_split.json](/Users/kiwimango/socom-141-camera-lab/config/feature_contracts/source_rifle_ready_fire_split.json:1):
  saved acceptance and main proof added; exact-source limitation explicit.
- This document and the new proof folder below. Original animation resources
  and original character/weapon meshes are untouched.

Verification results:

- Focused source ready/fire regression: PASS (includes Mark23 unchanged path).
- Main headless v2: PASS 2275 checks; trigger maximum0.642mm,
  support maximum0.999mm. Dynamic frame-count differs with process cadence.
- Main native v2: PASS 1943 checks; trigger maximum0.542mm,
  support maximum0.970mm. Forty rendered images across20 samples; all20
  synchronous capture invariants preserve source pose/frame state.
- Natural M4 return readiness:0.854 →0.448 →0.0. AK:0.851 →0.439 →0.0.
  The source fire clip remains a separate accepted-shot branch and the1.2s
  grace timer is unchanged. The original game’s grace duration is not claimed.
- Feature-contract gate: PASS148 contracts. Scoped `git diff --check`: PASS.
- First main run failed two exact float equality assertions for1.85m capsule;
  the fixture was corrected to approximate equality, with no gameplay change.
  First render return labels sampled too late; v2 samples actual state/weight
  boundaries instead. Known platform certificate/audio-capture warnings are
  distinct from gameplay assertions; native v2 has no script error.

Durable [proof folder](/Users/kiwimango/socom-141-camera-lab/art_source/source_rifle_idle_verified_20260913/README.md),
[main report](/Users/kiwimango/socom-141-camera-lab/art_source/source_rifle_idle_verified_20260913/rifle-idle-v2.json),
[per-frame transition report](/Users/kiwimango/socom-141-camera-lab/art_source/source_rifle_idle_verified_20260913/rifle-idle-v2-transitions.json).

Rendered review inspected idle early/middle/late, fire early/middle/held, and
return early/middle/late from side and rear, plus separately labeled ready API:

- [M4 idle](/Users/kiwimango/socom-141-camera-lab/art_source/source_rifle_idle_verified_20260913/rifle-idle-v2-m4a1_idle_middle-side.png)
- [M4 ready API only](/Users/kiwimango/socom-141-camera-lab/art_source/source_rifle_idle_verified_20260913/rifle-idle-v2-m4a1_ready_api-side.png)
- [M4 firing](/Users/kiwimango/socom-141-camera-lab/art_source/source_rifle_idle_verified_20260913/rifle-idle-v2-m4a1_fire_held-side.png)
- [M4 halfway return](/Users/kiwimango/socom-141-camera-lab/art_source/source_rifle_idle_verified_20260913/rifle-idle-v2-m4a1_fire_return_middle-rear.png)
- [AK halfway return](/Users/kiwimango/socom-141-camera-lab/art_source/source_rifle_idle_verified_20260913/rifle-idle-v2-ak-47_fire_return_middle-side.png)

Done: separate source default/ready/fire mapping and real main transition proof.
Partial: full visual parity. The support fingers remain claw-like in M4
ready/fire, and the forward foot has a visible ground gap in side views.
Palm-contact and grounded CharacterBody checks do not prove correct finger or
sole contact. Current post-source socket fitting still writes hand targets and
solves both arms in
[operator_seal_weapon_pose.gd](/Users/kiwimango/socom-141-camera-lab/scripts/player/operator_seal_weapon_pose.gd:120):

```gdscript
SocketIK.solve(pose.skeleton, pose.bone_indices, pose.right_hand_ik, pose.trigger_hand_target,
    pose.right_elbow_pole, &"mixamorig_RightHand", pose.right_palm_anchor_local, true, 1.0, ik_iterations)
SocketIK.solve(pose.skeleton, pose.bone_indices, pose.left_hand_ik, pose.support_hand_target,
    pose.left_elbow_pole, &"mixamorig_LeftHand", pose.left_palm_anchor_local, true, 1.0, ik_iterations)
Wrist.apply(pose)
```

Not done by this pass: original armed-alertness controller semantics, random
ready01/02 selection, final original weapon/hand mesh fitting, camera parity,
all-arsenal visual verification, browser export. The proof uses the current
modern ISO derivative at60.48790231, not the original SOCOM skinned mesh.

Play the updated native project by opening this exact project and running
`main.tscn`. Existing running processes keep their loaded profiles until
restarted; no user session was reloaded. An older browser ZIP does not contain
this saved mapping until rebuilt and uploaded.
