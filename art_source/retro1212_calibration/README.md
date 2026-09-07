# 1212 geometry-only draft contacts

## Current canonical candidates

The original `.visual_rig.draft.json` files below remain untouched geometry baselines. The derived `.runtime_candidate.json` files now use self-contained `assets/weapons/retro_1212/{uzi_candidate,pump_candidate}.scn` models, still **unassigned**. These scenes preserve6 mesh parts each, source UV/materials and original part skeletons; runtime dependency lists are empty. `tools/retro_1212_materialize_models.gd` produces them without importing the730MB source pack. The Uzi retains its real0.0601628m barrel pair: the visual schema now rejects only numerically degenerate pairs≤0.00001m, not real short barrels.

`tools/retro_1212_prepare_rigs.gd` derives candidate mount and palm coordinates without moving the mesh. The source +X bore is converted to the previous family's +Z marker frame by a rigid pivot rotation; translation preserves the authored trigger contact:

```gdscript
var converted_basis := original_basis * Basis(Vector3.UP, -PI * 0.5)
var new_origin := original_origin - converted_basis * right
```

The pump candidate differs from its original geometry draft in two evidenced gripping locations: the support point is on the actual rear pump surface `(0.25, 0.03994815, 0)` and the trigger palm is on the forward wooden stock wrist `(-0.02, 0.055, 0.018136)`. Both are recomputed from triangle ray casts; the model, scale, stock and barrel remain exact. The candidate uses the existing maximum additional pocket drop0.07m, without increasing the runtime cap. Original center-pump placement overextended the arm; the final candidate passes the unchanged42–150degree ready arm bounds and5mm palm bound. The Uzi retains all seven original geometry points.

Focused results before the remaining shared reload/prone owner fixes:

- `tools/retro_1212_canonical_regression.gd --use-candidate`: both guns PASS872 actual-input frames (`/private/tmp/retro1212-both-final-candidates.json`), preserving protected ballistics/fire-mode fields. This test inherits real movement input, exact accepted-shot counts and native visibility assertions from the shared firearm proof. Default mode requires actual saved assignments and does not inject candidates.
- `tools/retro_1212_asset_regression.gd --runtime-models`: bundled model, skin/material, geometry and zero external dependency checks PASS.
- `tools/retro_1212_socket_review.gd --runtime-candidate`: all five surface contacts and two eight-vertex barrel rings PASS; greatest numeric surface error0.000000107m. Native marker proofs are in `/private/tmp/retro1212-runtime-calibration/`.
- `tools/weapon_short_barrel_contract_regression.gd`: long and short pairs PASS; zero,1µm,NaN,infinity and missing marker reject.
- `tools/feature_contract_regression.gd`:87 integration graphs PASS at this checkpoint. This structural gate does not override failed physical/native checks.

### Native review and reload checkpoint

Native pump captures from `/private/tmp/retro1212-pump-native-visible.json` are source-stable and pass 436 actual-input frames, exact four accepted shots and natural mesh-visibility assertions. The largest palm error is 0.999 mm. Side/rear standing and crouched A/D, idle and stop captures show the real wooden wrist and rear-pump grips without folded chest arms. The original `/private/tmp/retro1212-pump-native.json` had an invisible-mesh fixture error and is **not** appearance evidence. The corrected fixture never forces mesh visibility. Uzi captures in `/private/tmp/retro1212-uzi-native.json` likewise show its own model and contacts. Native marker views in `/private/tmp/retro1212-runtime-calibration/` read the actual saved candidate sockets.

This is a model/grip review, not whole-body animation approval. Moving crouch rises from idle head height around 1.18 m to 1.50–1.54 m; the same rise exists for prior AK/M4/M16 in `/private/tmp/rifle-release-visible-native.json`. The 1212 captures additionally expose a stop-frame 6→7 transient head drop of about 0.33 m. The gait/pose owner needs to classify that before broader visual acceptance; this asset work does not adjust body height or movement.

The shared reload-anchor correction now passes `tools/retro_1212_reload_regression.gd --weapons=9mm_sub,870`: **1,412 frames / six lifecycles**, source signatures unchanged during the run, `/private/tmp/retro1212-reload-candidate-reload.json`. Right palm errors remain below 0.375 mm (Uzi) and 0.448 mm (pump). Reload interruption consumes exactly one round and ammo commit/recovery remains unchanged: Uzi 1.75 s standing/crouched and 2.1333 s prone because of the existing animation-speed cap; pump 4.5 s in all three postures. The existing owner in `scripts/player/operator_weapon_pose_actions.gd` now finalizes the authored palm on its existing transform anchor, without acquiring right-arm aim IK:

```gdscript
weapon_presentation_owner.use_solver_parent(true)
weapon_solver_owned = false
_weapon_transform_on_trigger_hand(_right_hand_grip_world_transform(), true)
```

Publication remains held for prone aiming and one pump support regrip frame. At `870_prone_reload` frame 270 the action and reload lock have cleared, the right palm remains attached, but the support gap is 45.442 mm; subsequent completion frames are below 0.547 mm. The focused reload gate checks right-palm ownership, so its PASS does **not** certify this support endpoint. Prone firing still needs the parent task's canonical aim correction and all-state proof. No weapon profile, roster entry or family assignment points to these candidates yet. The earlier on-disk/schema blockers described below are historical and resolved by the selected-model conversion/numerical-direction check.

These are **unassigned drafts**, not published or character-fit-certified rigs. Only the original two family visual documents were used as provisional handling/mount/action baselines. No M4 contacts were copied. Canonical profile/config pointers remain unchanged.

Drafts: `9mm_sub.visual_rig.draft.json` and `870.visual_rig.draft.json`. Both use the existing `GunsLab2VisualRigContract` schema, `status: draft`, meter-scale GLBs, `normalized_scale: 1`, `user_scale_multiplier: 1` and zero model rotation. +X is forward, +Y is up, +Z is the weapon's right side. Socket coordinates are siblings of the model under the weapon pivot, as implemented in `scripts/player/operator_asset_runtime.gd:404`:

```gdscript
_add_weapon_socket(calibrated_pivot, "Socket_RightHand", right_position, true)
```

## Exact saved socket positions (meters)

| Socket | Uzi / `9mm_sub` (X, Y, Z) | Pump / `870` (X, Y, Z) |
| --- | --- | --- |
| Right palm | (-0.0150000, 0.1020000, 0.0159273) | (-0.0400000, 0.0550000, 0.0181360) |
| Left palm | (0.1200000, 0.1370419, 0) | (0.3500000, 0.0399482, 0) |
| Muzzle | (0.24973985, 0.1660831, 0) | (0.6446690, 0.0892346, 0) |
| Barrel root | (0.18957705, 0.1660831, 0) | (0.1886877, 0.0892346, 0) |
| Buttstock | (-0.3569365, 0.0950000, 0) | (-0.2951829, 0.0060000, 0) |
| Sight / optic-up reference | (-0.0100000, 0.1991911, 0) | (0.0600000, 0.1040098, 0) |
| Ejection | (0, 0.1817062, 0.0176181) | (0.1350000, 0.0890000, 0.0163113) |

The hand targets are actual surface points, not weapon-space bounding-box ratios: the Uzi right grip panel and forward molded handguard underside; the shotgun's wooden stock wrist and wood pump underside. Each draft saves the selected mesh, ray, direction and visible landmark rationale. Source part bones establish the trigger/forearm/ejection neighborhoods, but their pivots are **not** falsely used as palm centers.

The muzzle and barrel root are centers of the actual eight-sided mesh rings. The pump bore lies at Y=0.0892346, above its lower magazine tube around Y=0.060. The Uzi barrel root is the visible bare-barrel start / original silencer bone head; unmodeled hidden chamber internals are not invented. Both optic points are on the actual receiver top; neither model is claimed to contain a physical scope rail. Projecting optic-minus-barrel-root perpendicular to the bore yields exact +Y up.

## Reproducible proof

`tools/retro_1212_socket_review.gd` loads only these two GLBs using `GLTFDocument`, reads saved draft sockets, and checks five mesh-surface rays plus both eight-sided bore ring centers. It also checks preserved family handling/mount data, meter scale and sight-up orientation. Exact implementation:

```gdscript
var arrays := mesh.mesh.surface_get_arrays(surface)
var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
var hit: Variant = Geometry3D.segment_intersects_triangle(from, to, triangles[index], triangles[index+1], triangles[index+2])
var error := wanted.distance_to(closest)
_expect(error < 0.00002, id + " actual surface " + String(witness.socket))
```

The source-side witness measurements were independently obtained with Blender5.2.1 GLB re-import and mesh ray casts (`/private/tmp/retro1212_geometry_landmarks.py` and `.log`). Godot4.7.1 headless and native geometry checks **PASS**, with greatest surface disagreement 0.000000107 m (numeric agreement, not a real-world accuracy claim). Both bore roots/muzzles have eight unique ring vertices and center error below0.0000001 m. The initial probe used `Mesh.get_faces()`, whose rounded triangle-cache coordinates lost precision; switching the inspection to original surface arrays fixed the measurement, without moving any contact point or relaxing tolerances.

Native marker overlays reviewed:

- `/private/tmp/retro1212-calibration/9mm_sub-right.png`, `9mm_sub-left.png`, `9mm_sub-top.png`, `9mm_sub-grip.png`.
- `/private/tmp/retro1212-calibration/870-right.png`, `870-left.png`, `870-top.png`, `870-grip.png`.
- Every color marker/leader reads the draft itself. Markers render over occluding geometry deliberately; a marker visible from the opposite side is not a second contact surface.
- JSON proof: `/private/tmp/retro1212-calibration/{9mm_sub,870}-geometry-proof.json`.
- Native log: `/private/tmp/retro1212-socket-review-native.log`.

Run the inspection with Godot `--path PROJECT --script res://tools/retro_1212_socket_review.gd -- --capture`. Omit `--capture` and use `--headless` for geometry checks without images. The review tool has no gameplay entry point and writes only temporary proof outputs.

## Publication blockers, intentionally not bypassed

1. No editor resource import has been performed on these GLBs. The raw on-disk visual-rig validator reports the model as unavailable to `ResourceLoader`, while direct GLTF loading succeeds. The inspection packs the actual generated model into an in-memory `PackedScene` and reruns the unchanged schema validator; no resource/import file is saved. This distinguishes geometry/schema validity from on-disk runtime readiness.
2. In-memory **870 draft schema PASS**. In-memory **Uzi draft schema BLOCKED** by `scripts/labs/gunsmith2/weapon_visual_rig_contract.gd:225`:

```gdscript
if muzzle.distance_to(barrel_base) < 0.15:
    errors.append("muzzle and barrel base do not define a usable bore")
```

The measured Uzi bore pair is0.0601628 m, a valid nonzero direction. The draft preserves that real root. A separately scoped short-barrel/zero-length validator review belongs to the root task; no fictitious longer barrel or root relocation was introduced here.

3. The retained family mount/grip offsets and support-hand rotations are **provisional**. They were authored for the previous model and must undergo canonical operator fitting; geometric markers alone do not prove a human palm, finger, elbow or shoulder fit. Standing/crouch/prone, idle/movement, firing/recovery and reload still require the parent's existing physical-pose gate before publication or assignment.

Delta: **MERGE** these geometry-authored offline drafts; **REJECT** premature runtime publication. No weapon stats, actions, animation policy, network authority, source mesh, existing AK/M4 rig or character pose was edited.
