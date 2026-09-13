# SOCOM Blender source library

## Expanded SEAL workbench (2026-09-12)

`tools/blender/workbenches/seal_full_source_library/socom_source_playback.blend`
contains **264 SEAL Actions and playback scenes**, up from the original 97 selected
dependencies. Choose an animation with Blender's Scene selector. The original
workbench is preserved. The new folder is excluded from Godot with `.gdignore`.

The builder now follows `metadata/source_asset` recursively for the coherent jump
resources and rejects dependency cycles. `--all-seal` includes every `seal_` entry
in the decoded catalog; civilians and other skeleton families are not silently
retargeted to the SEAL rig. All 6,029 decoded samples passed after reopening, with
maximum matrix-component error 0.000030517578125 (limit 0.0002). Playback preparation
preserved every source-key hash. Reports are beside the new Blend files.

These remain faithful decoded conversions on the recovered source armature,
not independently authored replacements and not the current skinned character.
Unknown/partial coverage and unattached helper tracks remain explicitly marked.
The 264 Actions are not automatically activated in gameplay. AGLS climbing also
remains a separate port: imported clips are not all wired to traversal states.

Translation card: extend the offline editable source library to the full SEAL
catalog, preserving samples and duration. Owner: the existing Blender builder.
Protect runtime maps, character skin, movement, aim, weapons and networking.
Proof: builder checks, reopened-sample validator and playback key hashes.
MERGE: old/current scores (correctness, ownership, runtime parity, editor usability,
performance, coverage) 3/5/2/4/5/3; candidate 4/5/2/5/5/4. Runtime parity stays 2
because this is an offline source workbench, not a gameplay replacement. Code:
`build_seal_source_library.py::scan`, `--all-seal`, and the existing validation tools.

## Playback audit correction

The initial file saved a single 1–18 scene range regardless of the selected Action.
That could truncate longer motions and hold short ones. Also, comparing tracked nodes
against every helper node incorrectly labeled all 97 Actions partial.
`tools/blender/prepare_seal_playback_scenes.py` creates the separate
`socom_source_playback.blend`: select clips with Blender's Scene selector, then Play.
Each of the 97 scenes has its own armature object, source frame range and frame rate.
Coverage now comes from the reference/firing manifests: 22 clips are non-full-body.
Every source key hash remains unchanged. `playback_validation.json` records the proof.
The original library is retained, not overwritten.

This fixes confirmed Blender setup problems, not an unidentified Animation Studio/game
rendering defect. No skinned character or weapon was added. Exact source samples still
do not prove original engine layering or in-game visual parity.

System delta: MERGE per-Action playback scenes. Compared with the previous workbench,
correctness rises from 4 to 4 (source unchanged), ownership remains 5, runtime parity
remains 2, editor usability rises from 4 to 5, offline performance remains 5, and
regression coverage remains 4. Evidence is the saved scene range audit, per-scene
duration assertions, and unchanged source-key hashes in the preparation script.

## Translation card

- Intent: editable one-for-one source motion samples for every SOCOM dependency in the saved game animation map.
- Acceptance: every selected source has a Blender Action; reopened Actions reconstruct all decoded skeletal samples within 0.0002 matrix-component error, with source duration and SHA-256 preserved.
- Owner: offline `tools/blender/build_seal_source_library.py`; existing runtime animation owner is unchanged.
- Protected: all game resources, player mesh, runtime mappings, movement, aim, weapon ownership, networking and other working files.
- Proof: builder sample checks plus `tools/blender/validate_seal_source_library.py` after reopening the saved file. Bone-only early/middle/end contact sheet, not skinned gameplay parity.

## Output and use

Open `tools/blender/workbenches/seal_source_library/socom_source_actions.blend`.
Select `SOCOM_Source_Actions`, open Dope Sheet > Action Editor, and select an Action.
The file contains 97 Actions, a recovered source armature and an embedded README.
No auto-generated Blender import is added to Godot: this workbench has `.gdignore`.
The saved game profile is an input to selection, not overwritten by this tool.

This includes registered references/fallbacks, not only clips observed during a play session.
The source set is resolved from the saved profile resource paths, gameplay manifest,
firing manifest and composition bases. Each Action records consumers and source hash.

## Fidelity boundaries

Native source hierarchy, local motion, horizontal root travel, source samples and durations
are retained. Blender rest-frame corrections reconstruct the source local transforms:

```python
basis = blender_local[bone].inverted() @ transform(bone, f)
assert max_error < 0.0002, (name, max_error)
```

This is not independent hand-authored motion: it is faithful conversion of the decoded data.
Exactness is verified at decoded sample times. Fractional-frame interpolation is linear
in Blender and has not been compared against the original engine. Bone display lengths are
diagnostic, not recovered skin geometry. Partial firing clips stay marked partial; absent
body channels use rest for inspection. Unknown weapon/helper parents are not invented:
their raw channels remain in `unattached_tracks_json` on each Action.
No claim is made that this fixes the current game's IK, lean or prone reload transitions.

## Reproduce

Use a fresh background Blender process with the builder's `--project`, `--source`
(decoded `output` directory), and `--output` arguments. Existing blend files are protected
from overwrite. Open the resulting blend in background mode with the validator and pass
the same source directory after `--`. The validator writes a fresh proof JSON and contact
sheet, without saving diagnostic objects into the library.

## System delta

MERGE the offline source workbench; KEEP all runtime owners and assets.
Scores (0–5): existing reference resources correctness 3, ownership 5, runtime parity 4,
editor usability 2, performance 5, regression coverage 4. Candidate source workbench:
correctness 4 (sample-exact, not interpolation-exact), ownership 5, runtime parity 2
(not a runtime replacement), editor usability 4, performance 5 (offline), regression 4.
Evidence: `tools/import_seal_reference_animations.gd` strips root X/Z and retargets;
the new builder preserves source locals; the reopened-file validator checks every sample.
This improves source editing fidelity, not game runtime parity. No promotion to gameplay.
