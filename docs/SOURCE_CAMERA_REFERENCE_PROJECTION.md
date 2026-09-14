# Source camera landmark reference

## Translation card (2026-09-13)

- Player intent: reproduce the original camera framing without changing the selected character or inventing a source-root normalization.
- Acceptance: independently decode original stationary skeleton samples, project their exact joints through the verified ordinary preferred-camera equation and 70-degree horizontal lens, and quantify the current modern character's **rest-space** offset. Explicitly distinguish conditional raw-channel fixtures from original runtime camera output.
- Owner: the new offline `tools/source_camera_reference_projection.gd` observer. The canonical camera remains the only runtime camera writer.
- Must not change: camera/profile/scale, character assets, animations, movement, combat, networking, and any open game process.
- Focused proof: fresh headless Godot invocation; source file hashes, first/middle/last sample FK, independent pinhole versus Camera3D projection, exact known first-key camera positions, and current-model rest correspondence. No screenshot or skinned-original parity claim.

## System delta

Scores are 0–2 (higher is better): correctness / ownership / runtime parity / editor usability / cost / coverage.

| Observer candidate | Scores | Decision |
| --- | --- | --- |
| Infer source framing from modern overall mesh height | 0 / 2 / 0 / 1 / 2 / 0 | REJECT |
| Original-joint projection plus explicit modern rest-offset measurement | 2 / 2 / 1 / 1 / 2 / 2 | MERGE as an offline proof only |

The candidate does not activate settings. Source motion extraction can alter `skel_root` before the camera reads the current model-space body-part wrapper; therefore feeding a raw animation key to the recovered camera equation is a conditional input/output fixture, not proof of the original gameplay framing.

## Available reference assets

`tools/blender/build_seal_source_library.py` creates the original armature and actions from `seal-skeleton.json` and decoded motion tracks. `tools/blender/prepare_seal_playback_scenes.py` explicitly identifies these as source bones, not a skinned character. The `seal_source_library` / `seal_full_source_library` workbenches therefore provide original editable **skeletal** references, not a recovered original SEAL skin.

The existing extractor pilot `/Users/kiwimango/Downloads/SOCOM-II-animation-extractor/output/pilot/seal_walk.glb` has 28 nodes, one skeleton/skin definition and one animation, but **zero meshes**. A glTF skin entry alone does not constitute a skinned original character.

`assets/characters/modern_soldier/modern_soldier_iso.scn` is the selected modern character with source-proportioned body landmarks. `tools/modern_iso_proportion_builder.gd` deliberately retains the old target's ankle anchor:

```gdscript
targets[canonical] = old_ankle + facing * (source_point - source_ankle) * uniform_scale
```

Consequently matching source head-to-ankle distance does not establish identical absolute origin, silhouette, face volume, or animated framing. The tool measures the resulting rest translation rather than silently removing it.

## Evidence limits

- Original skeleton: `/Users/kiwimango/Downloads/SOCOM-II-animation-extractor/output/seal-skeleton.json`, SHA-256 `26e991e38bb09147c54ce3062116466fef3225e76b5e6771da619d56e625c551`.
- Original clips: adjacent `motion/seal_stand.json`, `seal_stand_alert02.json`, `seal_crouch.json`, and `seal_prone.json`; each run records their hashes.
- Source sample positions are divided by 256; quaternion integer vectors are normalized. Missing channels retain recovered local rest transforms. The observer never zeroes `skel_root.x/z`, folds root into hips, or derives camera anchors from `HeadMarker`.
- Metres per source world unit: `0.10000000149011612`. Horizontal FOV: `69.99999967119774` degrees. The recovered helper is `scripts/camera/source_gameplay_camera.gd::source_preferred_pose`; original executable provenance is in `docs/SOURCE_CAMERA_RUNTIME_PARITY.md`.
- The current asset's rest measurement is fresh. Historical main stance observations are not reused as time-matched source poses. The second pass independently samples the saved current canonical clip library at matching first/middle/last source times; live blend/aim/IK layers are not present in this clone. Original and modern animated poses must not be called identical from a successful measurement run.
- No original skinned SEAL reference was found in the bounded existing workbench/character-asset inventory. No original ground-plane/sole contact contract is inferred from ankle or toe bone height.

## Running the proof

```sh
/Users/kiwimango/Applications/Godot-4.7.1.app/Contents/MacOS/Godot --headless --path /Users/kiwimango/socom-141-camera-lab --script res://tools/source_camera_reference_projection.gd -- --out=/private/tmp/source-camera-reference-projection-next.json
```

The output path must be fresh and below `/private/tmp/`. This launches an isolated observer, not `main.tscn`, and does not interact with an open game. Headless projection is numerical proof, not rendered proof. A new gameplay feature contract is not added for this observer; runtime integration remains under the existing source-camera feature contract owned by the camera change.

## Results

First observer run: **PASS 926 checks**, 12 original first/middle/last sample poses; `/private/tmp/source-camera-reference-projection-v1.json`. No script/runtime failures; the installed macOS headless engine emitted its existing certificate-store warning. Neither runtime camera parity nor original skinned-character framing is claimed.

## Follow-up translation card: original root processing / same-time target comparison

New original-code evidence from the parallel root-motion audit: ordinary pose update `0x57b1d0` / `0x57b1e0` clears source root X/Z after storing the raw root. Therefore the raw-input rows must not be promoted to native gameplay camera goldens. The observer will add **separately labeled** XZ-cleared source fixtures, retain root Y pending the original vertical-handler audit, and compare first/middle/last current saved clip samples on an isolated clone of the selected character. The original FK and the current canonical library's build-time proportion adaptation remain separate paths. No visual corrections, camera/profile activation, motion-controller edits, or original-asset overwrites are authorized.

System delta: raw-only observer scores `1/2/0/1/2/2`; separate original-processing fixtures plus same-time current-asset samples score `2/2/1/1/2/2`: **MERGE** into the offline observer. A measured animated mismatch is reported, not corrected by guessing an offset. The canonical-library clone omits live AnimationTree blends, aim/weapon modifications and collision, so this is a per-clip comparison, not real-main presentation proof.

### Completed original processing check

`docs/SOURCE_CAMERA_ROOT_MOTION.md` now verifies ordinary root X/Z clearing and Y preservation. The only root-Y write in `0x59b870–0x59ba78` is the named `Ladderslide` branch (`0x59b9ac`), which is not one of these static stances. The parallel original-machine proof passed 74 keys across eight clips and three vertical-handler slices. The processed rows therefore retain source Y deliberately, not heuristically.

### Final measured result

**PASS 1,010 observer checks**, 12 first/middle/last source poses. Report: `/private/tmp/source-camera-reference-projection-v3.json`; log: `/private/tmp/source-camera-reference-projection-v3.log`. Independent pinhole versus installed Godot Camera3D projection differs by at most `0.000252` pixels. All same-time current clip source names/hashes match. The existing macOS certificate warning remains; there were no script errors or object leaks. No display-backed process was launched.

Ordinary source-root first keys and preferred camera at pitch=0, lean=0 (before camera trailing/collision and actor world transform):

| Source take | Processed root, source units | Camera position, metres |
| --- | --- | --- |
| `seal_stand` | `(0, 11.484375, 0)` | `(0, 2.1484375, 2.8)` |
| `seal_stand_alert02` | `(0, 11.22265625, 0)` | `(0, 2.1222656, 2.8)` |
| `seal_crouch` | `(0, 5.50390625, 0)` | `(0, 1.5377867, 2.8)` |
| `seal_prone` | `(0, 2.16796875, 0)` | `(0, 0.7667969, 2.8)` |

The source rest head-to-average-ankle span is **1.652060846 m**, versus **1.652061090 m** on the current selected model at saved scale `60.48790231`. Across 13 corresponding rest landmarks, a single measured translation of `(0.000270368, 0.020181410, -0.073148325)` metres leaves a maximum residual of **0.000000287 m**. That proves consistent rest scale/landmark placement, **not** animated equivalence or an offset to apply to the camera. Original rest ankle Y is `0.110885881 m`; current rest ankle Y is `0.131067291 m`. Neither ankle is declared the floor contact.

First-sample comparison at the same original-processed camera, 70-degree HFOV, 1280×800 viewport, with no original actor-level vertical correction or current live aim layers:

| Take | Original head UV | Current head UV | Current minus original head height |
| --- | --- | --- | --- |
| `seal_stand` | `(0.513703, 0.662451)` | `(0.518601, 0.651827)` | `+0.027452 m` |
| `seal_stand_alert02` | `(0.532670, 0.664634)` | `(0.534878, 0.658235)` | `+0.016802 m` |
| `seal_crouch` | `(0.541949, 0.691426)` | `(0.545485, 0.733658)` | `-0.114855 m` |
| `seal_prone` | `(0.528966, 0.637388)` | `(0.531969, 0.670692)` | `-0.097376 m` |

Chest UV (original → current), same conditions: standing `(0.502500,0.812378) → (0.504537,0.801174)`; crouch `(0.513917,0.811836) → (0.515390,0.856149)`; prone `(0.507277,0.684686) → (0.508868,0.721282)`.

These differences are **not 1:1 pose parity**. Each JSON row separately reports `animated_landmark_parity_within_1mm`; the successful observer run only means the comparisons executed and their source contracts matched. In particular, the crouch/prone discrepancy exists in the canonical library's built per-clip poses before live IK/aim modifiers. Do not tune camera distance or rescale the whole model to hide it. A targeted animation/retarget correction needs its own translation card and rendered main proof.

Relevant code exercised by this comparison:

```gdscript
# Current canonical library, isolated clone (operator_asset_runtime.gd).
current_asset_runtime._build_animation_library()
# Same saved source time, no remade animation or original-file write.
current_skeleton.set_bone_pose_position(bone, animation.position_track_interpolate(track, time))
current_skeleton.set_bone_pose_rotation(bone, animation.rotation_track_interpolate(track, time))
```

Camera3D projection conventions were checked against the [official Camera3D reference](https://docs.godotengine.org/en/stable/classes/class_camera3d.html); model-space bone poses against the [official Skeleton3D reference](https://docs.godotengine.org/en/stable/classes/class_skeleton3d.html). The installed Godot 4.7.1 projection comparison is the version-specific numeric check.
