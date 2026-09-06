# September 4 animation audit and original art delivery

## Accepted intent

The latest clarification supersedes permanent aim-ready: equip into a centered,
lowered/close-chest pistol idle; accepted shot selects the new forward firing
pose; keep existing 1.2-second recovery; return to that idle. Preserve camera,
reticle, CharacterBody3D, reload, server shots and damage. New art is original,
SOCOM 2-inspired—not copied game assets or a claim of visual parity.

## Why the browser still shows the left/up idle

`config/operator_animation_map.json:44` still contains:

```json
"pistol_idle": "res://assets/animations/mixamo/Pistol_Handgun Locomotion Pack/pistol idle.fbx"
```

`scripts/player/operator_animation_driver_pose.gd` selects configured
`idle_standing` below ready weight 0.5. The live mannequin supplies `0.0` ordinary
readiness (`scripts/player/test_mannequin.gd`, `_sync_production_animation`).
The pistol aim correction in `scripts/player/operator_weapon_pose_ready.gd`
is gated by:

```gdscript
animation_owned_aim_alignment_enabled and ready_weight > 0.001
```

Thus idle follows its authored hand frame instead of holding the shot correction.
The browser on port 8060 serves the previous export; no candidate is live there.
HTTP 200 checked September 4. The reattached 11:20 PM recording became readable
September 5; AVFoundation decoded it outside the sandbox. 62 half-second samples
were inspected across 30.96 seconds (not a claim of reviewing every source frame).
At 4.5 seconds the loaded Mark23 is beside the left side of the head; shots are
visible around 5 seconds, followed by empty-magazine/reload motion and refill by
8 seconds. At 19.485 seconds the firing frame differs; by 23.485 seconds the
empty pistol is raised beside the head again. These visual observations do not
identify code states by themselves; the selected source and runtime gate above do.

## Confirmed runtime defects and bounded changes

1. **Opposite locomotion headings could remain stuck.** Normalizing a vector lerp
   between exact opposite directions repeatedly returned the old heading.
   `scripts/player/operator_locomotion_blend_tree.gd:211` now interpolates angles:

   ```gdscript
   rendered_direction = Vector2.from_angle(lerp_angle(
       rendered_direction.angle(), target_direction.angle(), rendered_direction_alpha
   ))
   ```

   24 stance/direction/frame-rate cases fail-before/pass-after. Phase keeps
   advancing. This does not certify foot planting: broader quality budgets still
   fail (foot slip and joint discontinuities), and frozen-body preview cannot prove
   actual world foot contact.

2. **Pistol ready mount shrank the weapon 64-fold.** Applying an inverse-scaled
   local mount using a normalized world palm lost the scaled bone-parent basis.
   `scripts/player/operator_weapon_pose_kinematics.gd`,
   `_weapon_transform_on_trigger_hand`, now optionally restores the authored scale.
   Pistol ready calls opt in; world scale is 1 instead of 0.015625. Real Mark23
   trigger/support span is 40.927 mm, bore-marker length 157.800 mm. Correct size
   exposes errors previously hidden by the tiny weapon; full-family pose tests
   are not passing on the old source clips.

3. **Terminal recovery correction snapped off.** Same file,
   `_solve_pistol_trigger_hand_centerline`, fades its target and pole using
   `solve_weight = clampf(ready_weight, 0.0, 1.0)`; root rotation uses the same
   existing readiness. Static terminal palm steps fell from 24–30 cm to below
   1 mm. Entry remains instantaneous at the accepted shot, per current API;
   this is not a claim that the full transition is polished.

4. **Pistol shoulder correction aligned a different segment than it measured.**
   `scripts/player/operator_posture_layer.gd`, `_apply_square_shoulders`, now uses
   upper-arm origins for the pistol clean-ready frame, rotating only the same
   Spine2 owner. Rifle behavior retains the old branch. This is physically tested
   with the authored high-ready candidate, not a claim all old clips improve.

5. **Idle and standing ready shared one slot.** Optional `ready_standing` and
   `ready_crouched` are now distinct in the existing graph, pose selection and
   Gunsmith. Old profiles retain fallback behavior. See
   `config/feature_contracts/pistol_distinct_idle_ready_slots.json` and
   `tools/pistol_distinct_ready_slots_regression.gd`. Test confirms accepted shot,
   1.2 seconds, return to idle, no fire OneShot, and persistent editor previews.

## Authored animation status

Source: `art_source/animation_audit_20260904/pistol_square_native_candidate.blend`.
Exporter: `tools/blender/build_pistol_pose_candidate.py`. Three native-rig actions:
forward ready, low ready, optional recoil (not gameplay-routed). Each has 30
upper-body rotation channels, with original 41 bone rests unchanged.

High-ready with 0.14 m reach retraction and measured wrist calibration passes
10 Mark23 cases (standing/crouched × idle/four diagonals), sampled at frames
1/2/4/8/12/18. Physical bore errors 0.026–0.118 degrees, support contact at most
1 mm, visible shoulder height difference approximately zero, elbows within
38–155 degrees. Logs:

- `/private/tmp/socom-pistol-candidate-final-ready2.log`
- `/private/tmp/socom-pistol-distinct-entry-directions.log`

**Low-ready contact and centering now pass in memory; the pair is not accepted.**
Shortening authored low reach to 0.14m resolved unreachable support targets.
Then `tools/pistol_candidate_loader.gd` needed a LOW-only import correction:

```gdscript
var complete_scene := low_document.generate_scene(low_state, 30.0, false, false)
```

Godot 4.7.1's default immutable-track removal discarded ten static channels
already present in the GLB, including RightShoulder, Spine1 and Spine2. The
compositor retained those parents from the old idle underneath the new arms.
The unchanged high action retains its previous import path. Official reference:
https://docs.godotengine.org/en/latest/classes/class_gltfdocument.html#class-gltfdocument-method-generate-scene

Controlled parent-only restoration moved chest-relative wrist offset from
9.91/9.68cm standing/crouched to 2.55cm. Native position reset changed under
0.003mm, ruling out translation tracks. Final canonical low checks (neutral and
18-degree camera yaw, equip and final return) pass all eight cases: palm
centering 2.22cm standing/4.45cm crouched, contact error below 0.2mm, muzzle
about 8–10 degrees downward. Centering uses the actual shoulder span, not root
X, because crouched torso yaw changes that frame. Root-X remains diagnostic.

**New neutral crouched FIRE failure remains:** bore error 3.686–3.702 degrees
at frames 8–32. Required rigid correction 35.90 degrees exceeds Mark23's saved
32-degree limit (`config/weapons/mark_23.json:107`). The same existing owner
clamps it in `scripts/player/operator_weapon_pose_kinematics.gd:593`:

```gdscript
var applied := minf(error, deg_to_rad(maximum_wrist_correction_deg))
```

Ready and clean weights are 1, target mismatch is zero, and both contacts stay
below 0.3mm: not a transient/fixture issue. The other three aim/stance cases
pass. Log `/private/tmp/socom-pistol-low-neutral-fire-diagnostic.log` remains
overall **FAIL**. Do not raise the limit to label the authored pose complete.
No shared clip mapping, canonical character selection, or browser export was
changed to promote the pair. Family candidate run also remains mixed (44 failed
assertions, including four rejected-shot cases); not an all-pistols pass.

Final offset-aim canonical rendered before/recovery/after check passes after
correcting its chest-frame measurement. Log:
`/private/tmp/socom-pistol-complete-low-render.log`. This does not cancel the
neutral crouched firing failure. September 5 feature-contract graph gate passes
35 manifests (`/private/tmp/socom-sept5-contracts.log`); `git diff --check` passes.

### Import correction translation and delta

Intent: centered relaxed carry independent of the old idle's shoulder pose.
Acceptance: complete authored upper parents, chest-relative centering and real
hand contacts in both stances before and after fire. Owner: existing animation
asset import/composition boundary. Protected: high-ready action, runtime
movement/aim/shot/IK ownership, saved sockets. Proof: low contact regression,
parent isolation and canonical rendered before/recovery/after captures.

| Criterion | Old candidate import | LOW-preserving import | Evidence |
| --- | ---: | ---: | --- |
| Correctness | 1 | 4 | Explicit parent restoration; neutral firing still fails. |
| Ownership clarity | 5 | 5 | Only loader changes, no runtime writer. |
| Runtime parity | 1 | 1 | In-memory canonical test only, not saved selection. |
| Editor usability | 3 | 4 | Reproducible Blender source and complete LOW import. |
| Performance | 4 | 4 | Extra import at test/build time, no per-frame work. |
| Regression coverage | 2 | 4 | Neutral/offset stance equip/return contacts plus firing. |

Decision: **MERGE** LOW import correction into candidate tooling; **REJECT**
runtime promotion until neutral firing and broader acceptance pass. Evidence:
`tools/pistol_candidate_loader.gd`, `tools/pistol_low_ready_contact_regression.gd`,
`/private/tmp/socom-pistol-low-ready-parent-isolation.log`.

## Original environment and character assets

- `art_source/tactical_courtyard_kit/tactical_courtyard_kit.blend` and five GLBs
  under `assets/environment/tactical_courtyard_kit/`: weathered plaster wall,
  doorway, concrete stairs, crate, corrugated barricade. 6,535 unique triangles,
  one mesh/material per module. Prefab `scenes/props/tactical_courtyard_kit.tscn`
  owns static collision. Godot import/render and collision-ray test pass:
  `tools/tactical_courtyard_asset_regression.gd`. Actual player stair traversal
  and canonical map placement are not yet integrated.
- **REJECTED by user:** `art_source/field_operator_20260904/field_operator.blend`,
  the standalone primitive-built character. Retained, not installed or deleted.
- Replacement direction: `art_source/canonical_military_variant/` uses the exact
  current PS1 character with muted olive fatigues/hood and warmer webbing.
  `tools/blender/build_canonical_military_variant.py:112` asserts unchanged
  vertices, triangles, UVs, skin weights, hierarchy and rest matrices:
  `assert before==after,'Canonical geometry/rest/UV/weight invariant changed'`.
  Preserved 371 vertices, 680 triangles, 41 bones; no added geometry. Godot import
  passes with three material surfaces and eight influence slots retaining the
  original maximum five weights. No source texture pixels changed. GLB under
  `assets/characters/canonical_military_variant/`; current-vs-variant comparison
  and Blender source in its art_source folder. Material study only, not live.
  Its README records the six-score delta and keeps the current runtime character.

## Validation boundaries

Focused slot, direction continuity, feature graph and rifle ready/recovery parity
tests are distinct from visual asset acceptance. Do not summarize the mixed
animation audit as passing. No git commit/push, public deployment, weapon purchase,
network authority, shutdown, camera, reticle, or multiplayer change was made by
this pass. Preserve pre-existing dirty work. The quick integration script's main
branch requirement is not met on the current dirty render-deployment branch; no
full promotion is claimed.
