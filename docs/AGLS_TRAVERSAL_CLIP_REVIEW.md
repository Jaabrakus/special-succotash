# AGLS traversal pose review — 2026-09-12

## Translation card

- Player intent: use the existing authored AGLS grab, hang, and pull-up poses on the current character.
- Acceptance: rendered early/middle/late poses on the canonical PS1 skin, from two angles, plus actual bone positions; identify suitable candidates rather than asserting every imported state works.
- Owner: offline `tools/agls_traversal_clip_review.gd` review harness. Runtime integration remains owned by the existing animation driver and shared profiles.
- Must not change: collision/movement, camera, weapons/damage, networking, source clips, and original Blender workbench.
- Proof: 26 `godot_*.png` sheets covering 13 clips and `godot_metrics.json` in `art_source/agls_traversal_review/`.

## Method and limits

Executed successfully using Godot 4.7.1, Compatibility renderer. Each sheet shows phases 0%, 50%, and 99% left to right. Filename `front` is the usual rear-facing player view; `side` rotates the model 90 degrees. These are **offline pose selection proofs, not a main.tscn traversal acceptance test**. There is no wall and no IK in this harness.

The review uses the same PS1 character, scale 62, Y rotation PI, existing rest-aware adapter, and standing-hip translation anchor as runtime:

```gdscript
# tools/agls_traversal_clip_review.gd:56
var model := load("res://assets/characters/ps1_dual_source_rig/ps1_dual_source_rig.scn").instantiate() as Node3D
model.scale = Vector3.ONE * 62.0
model.rotation.y = PI
var clip := Adapter.adapt_animation_rest_aware(source_player.get_animation(source_name), source_skeleton, skeleton, NodePath("."))
```

Bone metrics use `skeleton.to_global(skeleton.get_bone_global_pose(...).origin) - model.position`, not skeleton-relative coordinates mistaken for world units. This follows the [official Skeleton3D coordinate-space contract](https://docs.godotengine.org/en/latest/classes/class_skeleton3d.html). Latest documentation was consulted cautiously; every used method executed on installed 4.7.1.

## Candidate decisions

All paths below are beneath `res://assets/external/agls_intake/imported/`.

| Clip | Source duration | Decision and observed evidence |
| --- | ---: | --- |
| `climbing/CMC_Climb_To_Standing_FreeHang.scn` | 2.333 s | **MERGE candidate** for tall hang (hold phase zero) and pull-up (one-shot). Initial arms are nearly symmetric overhead, feet extended; middle lifts a knee and folds torso; final is standing. Using the same source for held pose and pull-up avoids mismatched start poses. Must still align hands to validated edge and synchronize root-owned ascent. |
| `climbing/CMC_Climb_Hanging_Idle_Loop.scn` | 10 s | **KEEP available**, not the preferred generic tall free-hang: knees tucked onto a wall, wrists substantially forward and lower. Needs a different body-to-wall contact pose. |
| `climbing/CMC_Climb_To_Standing.scn` | 2.333 s | **KEEP available** for braced-wall hang. Begins in the same tucked-leg posture as Hanging_Idle_Loop, not the free-hang pose. |
| `climbing/CMC_Climb_Transition_Fall_To_Climb_03.scn` | 0.8 s | **MERGE candidate** for generic airborne grab. Arms start low, reach overhead by midpoint, settle into symmetric free-hang. Entry needs authoritative-state timing and contact onset; do not play as ordinary idle. |
| `climbing/CMC_Climb_Transition_Fall_To_Climb_04.scn` | 1.667 s | **KEEP available** for fast forward/falling reach. Starts with both arms forward and legs trailing, then settles into free-hang. Long source settle is not permission to lengthen gameplay lockout. |
| `climbing/CMC_Climb_Transition_Fall_To_Climb_02.scn` | 0.667 s | **KEEP available** for braced-wall grab: ends with knees tucked, not generic free-hang. |
| `climbing/CMC_Climb_Transition_Fall_To_Climb_01.scn` | 1.167 s | **KEEP available** asymmetric entry followed by braced-wall pose; not the most neutral grab. |
| `climbing/CMC_Climb_Transition_Fall_To_Climb_05.scn` | 2.333 s | **REJECT generic grab**: middle sample crosses one hand across the body while the other reaches behind it. Specialized action, not interchangeable with simple jump-to-hang. |
| `mantle_vault/ALSv2_Mantle_2m_Walking_01.scn` and `02.scn` | 1 s each | **KEEP available for ground approach**, not a tall-hang replacement. They start with hands down and feet moving, fold onto top at midpoint, then stand. Sampled poses of the two clips were effectively identical; choose based on denser review if a specific distinction matters. |
| `mantle_vault/ALSv2_N_Vault_1m_LH.scn` and `RH.scn` | See metrics | **KEEP for true low vault**, not thick-platform step-on mantle. Both rotate torso and sweep tucked legs sideways past the obstacle at midpoint. RH mirrors the body-facing side; final sample is standing. |
| `mantle_vault/ALSv2_Vault_N_2m_LH.scn` | See metrics | **KEEP for higher lateral vault**, not a neutral mantle. Lateral knee/leg sweep is apparent at midpoint. |

The six-clip `mantle_vault` family has no verified neutral 1 m mantle. Do not pretend swapping a lateral vault into `low_mantle` makes a planted-foot step-up correct. A grounded 2 m Walking mantle is semantically closer, but its hand/foot trajectory needs review against the actual low obstacle before promotion.

## Measured contact guidance

With hips anchored to standing, FreeHang initial wrist positions relative to the collision-body origin are:

```text
Left  (-0.23953, 2.28642, -0.29845) m
Right ( 0.24150, 2.28276, -0.29694) m
```

The arm chains are 0.62765 m and 0.62727 m, respectively, and retain those lengths at all three samples. Initial wrist separation is about 0.481 m. A shared wrist spacing of 0.38 m therefore requires a modest inward arm solve. For an existing hang whose edge target sits 2.17 m above body origin, this pose's wrist average is about 0.115 m too high **before** any contact correction. This is an offset measurement, not authorization to move the collision capsule. Account for body-to-wall distance as well.

By comparison, Hanging_Idle_Loop starts at wrists `(-.191,1.993,-.607)` and `(.171,1.935,-.633)`: about 0.2 m too low for the same target, with a 0.6 m forward reach. That explains why swapping only the file name will not automatically repair contact.

## System delta (scores 0–5)

Candidate scores below describe **pose suitability and selection tooling**, not completed runtime integration.

| Criterion | Existing SOCOM hang/pull-up selection | AGLS FreeHang candidate | Evidence |
| --- | ---: | ---: | --- |
| Correctness | 2 | 4 | Existing runtime contact failure reported by main task; symmetric FreeHang wrist/arm metrics and rendered skin here. |
| Ownership clarity | 5 | 5 | Shared adapter and existing animation owner; no new movement or camera writer. |
| Runtime parity | 4 | 2 | Existing clip already mapped; this harness alone does not integrate a replacement. |
| Editor usability | 3 | 4 | Exact named imported source, repeatable pose sheets, source timing recorded. |
| Performance | 5 | 5 | Existing rest-aware cache path; no added per-frame simulation by asset selection. |
| Regression coverage | 3 | 3 | Offline pose/bone proof now present; actual main-scene grab/contact/exit tests remain parent's integration gate. |

Decision: **MERGE** FreeHang/Grab03 through existing runtime profiles only after contact and state-transition tests pass. Do not replace controller or duplicate root motion.

## Confirmed runtime takeover defect

The integration task found that the correct FreeHang resource was loaded and the modern transition reported `traversal_hang`, yet hips/spine still evaluated the previous jump pose. The competing owner was a downstream AnimationTree blend, not a bad AGLS retarget.

`operator_locomotion_blend_tree.gd` publishes `jump_lower_body_weight` only in `update_locomotion()`. The traversal driver returns before this update. `request_modern_state()` marked the overlay inactive but did not zero the old weight. Despite its name, the overlay filters hips, spine, and arms as well as legs, so it replaced the selected full-body traversal pose. The parent integration added `clear_jump_overlay_for_full_body_action()` at traversal/death takeover and a real jump→hang assertion that the graph weight is zero. The parent then measured both wrists within 1 micrometre and the correct AGLS body pose.

This raises the candidate's **runtime parity from 2 to 4**, **correctness from 4 to 5 for settled hang only**, and **regression coverage from 3 to 4 for takeover/contact**, based on `tools/traversal_hand_contact_regression.gd`. Pull-up trajectory/contact is separately unfinished; those improvements do not mean all traversal is complete.

## Pull-up timing and root-motion diagnosis

`tools/agls_pullup_timing_review.gd` samples the unmodified rest-aware FreeHang and a duplicate with standing-anchored hips at 21 phases, including shoulders. Output: `art_source/agls_traversal_review/pullup_timing.json`. The test passed on Godot 4.7.1. It changes no runtime resource.

The authored root/hip rises **2.174 m** over the take. Raw retargeted left wrist world Y stays approximately **1.31–1.54 m through phases 0–0.70**, while hips rise beneath it. This is the authored hand-support relationship. Standing-anchoring all hip positions removes the motion that makes those hands stay at the edge.

The current collision motor lifts the capsule to landing height during the first 65% and only then moves it over the wall. On the 2.55 m test ledge, body-origin ascent is 2.23 m. At phase 0.50 it has already risen 1.929 m while authored hips have risen only 1.445 m. At phase 0.70 the mismatch reaches approximately **0.685 m**. This explains the floating pull-up: slowing the clip or holding IK longer alone cannot repair it.

| Phase | Authored hip rise | Physics rise (2.55 m fixture) | Raw residual Y |
| --- | ---: | ---: | ---: |
| 0.1 | 0.043 m | 0.142 m | -0.100 m |
| 0.3 | 0.855 m | 0.987 m | -0.131 m |
| 0.5 | 1.445 m | 1.929 m | -0.483 m |
| 0.7 | 1.545 m | 2.230 m | -0.685 m |
| 1.0 | 2.174 m | 2.230 m | -0.056 m |

Recommended next bounded change, **not yet implemented by this reviewer**:

1. Retain the authored root samples at import/cache time instead of discarding them entirely.
2. The existing presentation owner can apply a source-relative hip/root residual, not a second movement path: `authored_delta(phase) - actual_body_delta`, with endpoint calibration to the validated body start/end. This subtracts movement already performed by CharacterBody3D; it does not add full root motion on top.
3. Calibrate contact start to the validated edge. Keep the residual zero at entry/exit after appropriate base contact alignment. Derive it from saved source samples and authoritative traversal progress, not a new independent timer.
4. Review source-supported release around 0.72–0.90 **only after** shoulder reach and the presentation residual work. Current 0.12–0.35 release happens before the authored support ends. Extending IK alone forces unreachable shoulders and is not acceptable.
5. Render the mesh against the wall at all 11 phases and check shoulder/hand reach and feet on both sides. Residuals are as large as ~0.7 m in this fixture, so do not silently clamp them to a tiny offset or claim they are safe for every ledge. If the source path cannot pass visible wall-contact checks, retain the current protected movement owner and report that limitation.

The root residual is presentation only, but its scale requires deliberate geometry review. No physics, collision validation, jump velocity, or action-duration change is justified merely to conceal an animation mismatch.

### Per-hand support refinement

Denser sampling revises the initial suggestion of one shared release interval. The right hand stops using the original edge before the left hand:

| Source phase | Left wrist Y/Z | Right wrist Y/Z |
| --- | --- | --- |
| 0.45 | 1.298 / -0.396 m | 1.318 / -0.400 m |
| 0.55 | 1.321 / -0.359 m | 1.449 / -0.661 m |
| 0.65 | 1.300 / -0.362 m | 1.494 / -0.940 m |
| 0.75 | 1.344 / -0.388 m | 1.541 / -0.961 m |
| 0.80 | 1.601 / -0.513 m | 1.727 / -0.953 m |

**Candidate edge-lock releases:** right 0.45→0.55; left 0.75→0.82. The right hand relocates farther onto the top; retaining its original edge target at phase 0.62 is incorrect. A second top-contact target would need its own validated support check. Without that, releasing to the authored right-hand pose is preferable to forcing it back to the edge. Left-hand error must not be hidden by releasing early: it still supports the original edge through ~0.75.

Also avoid uniformly stretching source horizontal displacement to the body's complete over-wall travel. In the current fixture, source hips travel forward 0.503 m, while the body's start/end span is 0.96 m. Normalizing both to 0→1 stretches contact-phase source motion about 1.9×. At phase 0.60 the source advances 0.228 m, but the fitted curve advances about 0.435 m. Preserving source metre-scale forward displacement during support, then blending the missing endpoint displacement after left release, is a bounded calibration candidate. It requires rendered/contact verification; no runtime change is made by this report.

## Review failure discovered and isolated

The earlier Blender workbench contained an unbound visible `Icosphere` and imported bones at approximately 1/100 the direct Godot world dimensions. The first Blender-only render batch showed spheres instead of the player; it is not accepted proof. Files without the `godot_` prefix from that batch must not be used as visual acceptance. The workbench agent was notified to correct review transforms and exclude unbound helper meshes. Original source data was not overwritten by this reviewer.

## Repeat

```sh
/Users/kiwimango/Applications/Godot-4.7.1.app/Contents/MacOS/Godot \
  --path /Users/kiwimango/socom-141-camera-lab \
  --log-file /private/tmp/agls-clip-review.log \
  --script res://tools/agls_traversal_clip_review.gd
```
