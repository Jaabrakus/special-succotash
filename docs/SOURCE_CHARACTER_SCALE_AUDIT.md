# Selected character and source-world scale audit

## Implementation translation card — measured visual-scale correction

- Intent: give the current ISO-proportioned soldier the measured original
  skeleton size, without resizing other characters or gameplay collision.
- Acceptance: selected modern ISO model uses60.48790231; every other scene
  retains global64; editor displays/saves the same selected override; main
  confirms1.652060843m rest head-to-ankle span and unchanged capsules/owners.
- Owner: `SocomOperatorTuningProfile` resolves shared saved visual-scale data;
  `SocomOperatorAssetRuntime` remains the existing model transform writer.
- Scope: per-scene override in `config/operator_movement_tuning.json`, tuning
  resolver, the existing Animation Studio scale slider, focused observer/test
  and `source_character_scale` feature contract.
- Protected: original assets/skins, CharacterBody transform and capsule,
  movement/animation timings, camera/aim, weapon/damage and network owners.
- Proof: exact-scene/fallback/malformed/save-isolation tests; fresh main
  scale/capsule/rest-span and weapon contacts; multi-angle rendered poses.

System delta MERGE: current global scale scores correctness2, ownership5,
runtime parity4, editor usability3, performance5, regression2. Scoped measured
candidate scores4/5/5/4/5/4 with evidence in tuning owner, saved mapping and
focused main regression. One dictionary lookup on profile application adds no
per-frame writer. Uniform scaling is not a fix for known crouch/prone sinking,
retargeted anatomy differences or independent camera-marker offsets.

## Implemented and verified — 2026-09-13

The external merge was resolved before this implementation; the earlier
interruption section below is historical, not the current build status.
Only the selected modern ISO derivative now resolves to the measured scale.
The global fallback remains 64 for every other scene.

`config/operator_movement_tuning.json`:

```json
"operator_scale": 64.0,
"operator_scale_by_scene": {
  "res://assets/characters/modern_soldier/modern_soldier_iso.scn": 60.48790231
}
```

`scripts/runtime/operator_tuning_profile.gd` resolves the actual in-memory
`driver.model_root.scene_file_path`; it does not infer selection from a filename
suffix or a possibly stale saved selection:

```gdscript
var path := _operator_scene_path(driver)
if not path.is_empty() and overrides is Dictionary:
    var candidate: Variant = overrides.get(path)
    if _valid_operator_scale(candidate):
        return float(candidate)
return float(fallback)
```

The existing tuning application calls `driver.set_trooper_scale`, and the
unchanged asset runtime remains the model-transform writer. The Animation
Studio slider in `scripts/runtime/main_animation_studio.gd` resolves and saves
the same selected override through `TuningProfile.set_operator_scale`; it uses
a 0.00001 step so opening the editor does not round the measured value to an
integer. Other models still edit the original global value. Malformed,
non-finite and non-positive entries fall back instead of scaling a model.

The selected asset SHA-256 is unchanged. Fresh main reports global model scale
60.48790359 (engine float precision), effective source unit 0.10000000361108 m,
and an independently measured head-to-average-ankle span of 1.65206110 m. The
decoded source span is 1.65206084 m: approximately 0.00000026 m difference.
CharacterBody scale remains one, capsule radius remains 0.38 m, and the three
capsule heights remain 1.85 / 1.25 / 0.82 m.

| Settled main stance | Skin Y min..max, m | Skin height, m | HeadMarker Y, m |
| --- | --- | ---: | ---: |
| Standing | 0.0229..1.9270 | 1.9040 | 2.1410 |
| Crouch | -0.1190..1.1079 | 1.2268 | 1.5710 |
| Prone | -0.1483..0.4619 | 0.6102 | 0.5111 |

These are sampled bounds, not animation-loop extrema. The source-scaled rest
skin bounds are 0.0390..2.0006 m. Skin volume and the independently authored
camera markers are not asserted to match the original game's mesh or camera.

Verification:

- `tools/source_character_scale_regression.gd`: PASS, 72 checks, both headless
  and display-backed through a fresh `main.tscn`. Exact scene scope, invalid
  input fallback, saved-data clone isolation, editor round trip, unchanged
  capsules, original rest span, and M4A1/Mark23 trigger contact at early/middle/
  late firing frames are covered. Trigger socket error remains below 0.025 m.
- `tools/feature_contract_regression.gd`: PASS, 145 contracts including
  `config/feature_contracts/source_character_scale.json`.
- `tools/source_character_scale_audit.gd`: PASS, CPU skinning of 102651 vertices
  across 14 sections in the actual selected main character.
- Native OpenGL/Metal capture: 24 images, standing/crouch/prone idle and settled
  fire for both weapons, rear and side views. Every capture preserved its
  sampled bone pose; no post-capture advancement was substituted for proof.

Durable proof: `art_source/source_character_scale_verified_20260913/` contains
the numerical reports, focused-test logs and all 24 images. Representative
views are `source-scale-native-v1-m4a1_0_idle-side.png`,
`source-scale-native-v1-m4a1_1_idle-side.png`,
`source-scale-native-v1-m4a1_2_fire_settled-side.png` and
`source-scale-native-v1-mark_23_0_fire_settled-side.png` in that directory.

Rendered limitations: the rifle support fingers still curl awkwardly over the
fore-end; tight socket distance does not prove a correct palm/finger surface
grip. Mark23 prone has a raised free support hand and a low firing hand near
the ground. Crouch knees/toes and prone skin still intersect the floor, as the
negative bounds show. The source-derived size is corrected, but these are not
approved one-for-one poses, fixed contacts or proof of all traversal actions.
No claim of a newly exported browser ZIP is made: this proof is the current
native project loaded from `main.tscn`.

## Translation card — 2026-09-13

- Intent: distinguish selected-character size from camera framing before any
  user-authorized model resizing is implemented.
- Acceptance: measure selected main-game model/skeleton transforms, current
  standing/crouch/prone skinned bounds, capsule and camera marker points; compare
  homologous rest landmarks with preserved decoded source values.
- Owner: read-only `tools/source_character_scale_audit.gd` observer/report only.
- Protected: all saved models, skins, animation profiles, capsule/movement,
  camera configuration and runtime scripts. Test-only posture changes exercise
  the existing owner; they do not persist or override a saved implementation.
- Proof: fresh headless `main.tscn`, CPU skinning of selected mesh/binds,
  source metadata/hash, explicit transform scales and source-world unit factor.

System delta: KEEP current assets until dimensions are measured; MERGE numerical
evidence into camera work. Correctness and integration coverage improve without
new runtime writers or runtime cost. A measurement is not rendered proof or
permission to infer guessed human dimensions.

## Fresh main measurement

Successful capture is preserved as
`art_source/modern_soldier/current_scale_audit_20260913.json` (14 skin sections,
102651 weighted vertices). The selected in-memory asset was
`assets/characters/modern_soldier/modern_soldier_iso.scn`, SHA-256
`3f774bc1c52555842eb663d3ec67b70d1d5437e1a76354cfba9bb8045f1daa43`,
matching saved `config/operator_character.json`. The skinned surface is still a
modern derivative, not the original ISO mesh.

`scenes/player/operator_player.tscn` declares scale62 and a 180-degree Y turn.
However the actual main runtime model and skeleton global scales were64;
CharacterBody, Mannequin and ProductionAnimation scales were1 and their local
origins zero (model origin also zero). The path is:

```text
config/operator_movement_tuning.json animation.operator_scale = 64
-> scripts/runtime/operator_tuning_profile.gd:179
-> driver.set_trooper_scale
-> scripts/player/operator_asset_runtime.gd:129 model_root.scale = ONE * scale
```

Skeleton local scale100 has a compensating imported ancestor; its measured
global scale is64, not6400. Multiplying only displayed local scales without
their full hierarchy would give a wrong answer.

### Current bounds and framing points

CPU skinning uses current bone transforms and actual inverse binds, excluding
unskinned weapon/gear. Every measured skin mesh shared the skeleton's global
origin. These are settled sample frames, not whole-loop extrema or screenshots.
All three samples used the real posture owner and were grounded.

| Main stance / logical clip | Skin Y min..max | Skin height | Head joint Y | Camera HeadMarker Y | Capsule height |
| --- | --- | ---: | ---: | ---: | ---: |
| Standing / seal_stand_alert02 | .0240..2.0380 | 2.0139 | 1.8146 | 2.1410 | 1.85 |
| Crouch / idle_crouch | -.1258..1.1722 | 1.2980 | .9510 | 1.5710 | 1.25 |
| Prone / idle_prone | -.1569...4887 | .6457 | .2818 | .5111 | .82 |

Standing/crouch/prone capsule centers are .925/.625/.41m, radius .38m;
`scripts/player/player_controller.gd:957` owns that collision shape change.
Rest skin Y extent is .0413..2.1167m (height2.0754m). Root-relative negative skin
Y in crouch/prone is actual measured presentation penetration below the player's
ground origin; shrinking the whole model cannot by itself remove it.

HeadMarker is a camera reference, not an eye bone. It deliberately follows
stable stance coordinates plus filtered pose deltas. In
`scripts/player/test_mannequin.gd:369` the targets are:

```gdscript
var standing_head := Vector3(0.0, 2.15, 0.0)
var crouched_head := Vector3(0.0, 1.58, 0.0)
var prone_head := Vector3(0.0, 0.52, -0.18)
```

Thus crouch framing reference is .3988m above the measured visible head/top.
The camera agent must compare the source camera's true anchor semantics before
replacing these values; scaling the character alone leaves these independent
stance targets unchanged.

### Original scale comparison and bounded recommendation

The preserved source skeleton metadata identifies `seal_A_arc`, SHA-256
`26e991e38bb09147c54ce3062116466fef3225e76b5e6771da619d56e625c551`.
`tools/modern_iso_proportion_builder.gd:26` normalizes source control landmarks
to the former target's head-to-ankle height, rather than original world units:

```gdscript
var uniform_scale = (old_head.y - old_ankle.y) / (source_head.y - source_ankle.y)
# Reported metres_per_source_unit = uniform_scale * 62.0
```

That metadata reports .102499836420227m/sourceunit **at outer scale62**.
Actual main scale64 makes it .105806282756363m/sourceunit. The independently
verified world `MetersPerUnit` is .10000000149011612 (see
`docs/CAMERA_SOURCE_CALIBRATION.md`, all34 original world archives).

```text
candidate uniform factor = .10000000149011612 / .105806282756363 = .94512347
candidate runtime outer scale = 64 * factor = 60.48790231
```

Independent homologous landmark check: original rest head-to-average-ankle
span16.520608 source units =1.6520608433m; current main span1.7479842901m.
Their ratio gives outer scale60.4878972 (about5e-6 difference from metadata).
This supports a **roughly5.49% reduction from current64**, not a guessed1.8m
human-size normalization. Current spans are5.81% larger than source spans.

This candidate addresses relative skeleton dimensions only. The builder anchors
the source to the former target ankle origin; absolute foot/pivot alignment and
the modern mesh's retained head/body volume are not proven source-equivalent.
Any scale change needs separate floor/contact, weapon grip, traversal and
hurtbox checks before promotion. No asset, pose, scale, camera or capsule was
changed by this audit.

## Verification limit: shared merge interruption

The first fresh main capture completed without observer errors. Its initial
derived scale omitted the live64/build62 factor; the preserved report above
corrects that arithmetic using the captured transforms and independently
checks the landmark ratio. A new main capture then failed because unrelated
shared files acquired unresolved merge-conflict markers, including
`scripts/main.gd:289` and `scripts/network/socom_supabase_client.gd:99`, with
cascading animation/input parse errors. The observer process was stopped;
conflicts were not edited. The corrected observer cannot be called freshly
runtime-verified until that shared merge is resolved. Prior capture evidence
is not a claim the current conflicted worktree is playable.
