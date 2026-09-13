# Canonical PS1 fallback source-retarget workbench

## Scope correction: selected character is a separate asset

This six-clip workbench contains
`assets/characters/ps1_dual_source_rig/ps1_dual_source_rig.scn`, the canonical
PS1 fallback. It does **not** contain the separately selected modern soldier
mesh, and it must not be used as proof that the selected `main.tscn` character
deforms correctly. `tools/source_rig_workbench_export.gd` uses that explicit
`MODEL` constant; it does not invoke `SocomOperatorCharacterSelection.apply`.
The earlier description of it as the actual current character was too broad.
The measured six-clip interchange result remains valid for this fallback only.

See [the selected-rig audit](SOURCE_RIG_SELECTED_ASSET_AUDIT.md) for the measured
rest-joint distortion in the separate ISO-proportion modern candidate. Neither
the existing `.blend` nor any original character asset was rewritten for that
audit. A README beside the `.blend` repeats this corrected scope.

## Translation card

- Player intent: editable SOCOM-derived actions on the canonical skinned PS1
  fallback, without adding a Blender interchange error to the existing retarget.
- Acceptance: six named actions preserve their Godot resource duration and key
  times; all 65 bone landmarks agree within 3 mm at authored keys and unbaked
  between-key checks; the existing skin visibly deforms.
- Owner: offline `tools/source_rig_workbench_export.gd` and
  `tools/source_rig_workbench_build.py`.
- Must not change: original assets, character rig, saved runtime mappings,
  movement/collision, camera, combat, or networking.
- Proof: fresh six-action export, Blender landmark checks, and twelve early,
  middle, late run/pistol views. This is not a new gameplay implementation.

System delta decision: MERGE the stricter offline verification; KEEP runtime
retargets pending the separate canonical-game review. Scores in order correctness,
ownership, runtime parity, editor usability, performance, regression coverage:
previous review 2/5/2/3/5/2; new review 4/5/3/4/5/4. Evidence: prior
`tools/blender/build_traversal_character_workbench.py` calibrates four standing
landmarks; the new exporter samples every bone at every resource key and midpoint,
and the new builder tests the actual imported armature. Runtime parity remains 3:
this consumes saved source-derived retarget resources before gameplay modifiers,
not the complete playable animation state machine.

## What was already present

`art_source/traversal_character_workbench/traversal_character_actions.blend`
already contains the canonical 65-bone skinned PS1 character and 519 review actions.
It is not merely a bone-only library. Its validation explicitly reports
`standing_exact_runtime_pose_parity: false` and a left-hand standing error of
0.0223169 m after a four-landmark fitted display parent. No existing workbench
or source library was overwritten.

## Corrected interchange and proof

Verified final output, preserved inside the project:

`art_source/source_rig_verified_20260912/`

Open [the editable workbench](../art_source/source_rig_verified_20260912/source_rig_six_clips.blend).
The original temporary build remains unchanged at
`/private/tmp/source-rig-workbench-20260913-v2/`. The persistent folder contains
byte-for-byte copies and `.gdignore`, so Godot does not import these review assets
into runtime. Its copied validation retains original build-time render paths;
the same render basenames now live next to the persistent workbench.

- `source_rig_six_clips.blend`: canonical PS1 BaseBody mesh, existing 65-bone armature,
  six editable actions, packed texture, camera and lights.
- `rest_character.glb`: neutral export of the canonical PS1 fallback character.
- `pose_samples.json`: resource/rig hashes, Godot version, duration, source
  metadata, every saved key time, and separate midpoint reference samples.
- `validation.json`: actual numerical checks and render inventory.
- `run_rear_0..2.png`, `run_side_0..2.png`, `pistol_run_rear_0..2.png`,
  `pistol_run_side_0..2.png`: rendered 10%, 50%, 90% views, inspected.

Godot 4.7.1's exported neutral rig retains an import basis and 0.01 scale. The
new workbench calibrates units from the REST skeleton and verifies the result
against every rest bone, instead of fitting an animated pose. The key operation
in `tools/source_rig_workbench_build.py` is:

```python
target = (convert @ Matrix(sample['bones'][name]) @ godot_rest[name].inverted() @
          convert.inverted() @ blender_rest[name])
pb.matrix = rig.matrix_world.inverted() @ target
```

This applies the measured Godot rest-relative world delta to Blender's own rest
bone orientation. It preserves Blender's skin and bone display-axis convention.
Only the saved Godot key times are baked. Midpoints are independent checks.

| Action | Source duration | Key + midpoint bone checks | Maximum error |
| --- | ---: | ---: | ---: |
| stand (`seal_stand_alert02`) | 1.033333 s | 4,225 | 0.034 mm |
| run (`seal_run`) | 0.633333 s | 2,665 | 0.034 mm |
| walk (`seal_walk`) | 0.833333 s | 3,445 | 0.034 mm |
| strafe_left (`seal_lstrafe`) | 0.733333 s | 3,055 | 0.034 mm |
| strafe_right (`seal_rstrafe`) | 0.766667 s | 3,185 | 0.034 mm |
| pistol_run (composed resource) | 0.600000 s | 4,875 | 0.034 mm |

All 21,450 bone-landmark checks passed; all six actions deform the real skinned
mesh with finite vertex positions. Standing height is checked in the range
1.3–2.4 m. The first sandboxed Blender launch crashed before Python ran; the same
bounded background build succeeded outside that sandbox. The final run uses
`--factory-startup`, avoiding installed add-on initialization errors. A Blender
6.0 `World.use_nodes` deprecation warning is unrelated to this Blender 5.2.1 run.
Godot's macOS certificate warning did not prevent the export PASS.

## Usage and reproduction

Open the final `.blend`, select Armature, and choose an action in Dope Sheet >
Action Editor. Set playback range to that action. The file opens with run active.
Do not apply the display parent or export these actions back into gameplay
without a separately tested round trip.

Use a NEW output directory (exporter and builder refuse to overwrite):

```sh
/Users/kiwimango/Applications/Godot-4.7.1.app/Contents/MacOS/Godot \
  --headless --path /Users/kiwimango/socom-141-camera-lab \
  --log-file /private/tmp/source-rig-review.log \
  --script res://tools/source_rig_workbench_export.gd -- NEW_OUTPUT_DIRECTORY
/Applications/Blender.app/Contents/MacOS/Blender \
  --background --factory-startup --python tools/source_rig_workbench_build.py \
  -- NEW_OUTPUT_DIRECTORY
```

## Limits

This proves the six Godot retarget poses survive editable Blender interchange.
It does not prove identical original SOCOM character proportions, muscle/mesh
deformation, gameplay blend rules, runtime IK, weapon contact, root motion, or
camera framing. The canonical PS1 character is proportionally different from the ISO
skeleton. Saved source retargets deliberately remove horizontal root motion.

`pistol_run` is explicitly the existing phase-normalized missing-leg-track
composition of `seal_p_run` and `seal_run`, not proof of SOCOM's blend algorithm.
No rifle or pistol prop is attached in this rig-only interchange review, so
the renders cannot establish weapon-grip contact. The original decoded Blender
library, retarget resources, this skinned workbench, and approved runtime clips
remain distinct artifacts. These are not six new runtime replacements, and
the other 258 SEAL clips were not rebaked in this bounded pass.

API reference inspected: official Godot `GLTFDocument.append_from_scene`,
`write_to_filesystem`, root-node handling, and `AnimationPlayer` seek/advance:
https://docs.godotengine.org/en/stable/classes/class_gltfdocument.html
https://docs.godotengine.org/en/stable/classes/class_animationplayer.html

## Follow-up translation card: source-only runtime presentation

Player intent: remove old procedural pose overlays from the source-animation
route, including the two-handed pistol repair. Acceptance: saved
`locomotion.source_pose_only` selects authored bone poses without frame-key
corrections, posture/head/CCDIK/grounding/extra-yaw changes; false keeps existing
branches. Owner: existing `operator_animation_driver_runtime.gd` delegates to
the same posture and asset owners. Must not change physics, camera/aim, shot
authority, action clocks, original resources, or AGLS traversal contact. Proof:
headless parse plus root-owned source-only regression and canonical rendered
comparison. The weapons owner handles its corresponding source-only attachment
branch independently.

Delta decision: MERGE a saved opt-in bypass instead of deleting legacy code.
Current/candidate scores (correctness, ownership, parity, editor, performance,
regression) are 2/5/2/3/3/3 and 4/5/4/4/5/4, conditioned on the source-only
regression passing. The prior `preserve_authored_body` bypass still ran torso aim
at ready weight, head correction, saved Gunsmith keys, and foot grounding.

Layers deliberately retained: canonical AnimationTree selection/crossfades,
real source lean endpoint blends (including authored position tracks), reload
and action timing, sparse-clip compositions/mirrors, native model facing/rest
retarget, root-motion sanitizer, CharacterBody-owned jump hip anchoring, AGLS
traversal hand contact/exit/equip, and existing item attachment/visibility. Extra
saved per-clip yaw corrections and procedural gait support/hip balancing are
bypassed. These retained systems must not be called original SOCOM engine
semantics; they remain declared integration boundaries.

Focused follow-up results: all three changed runtime owners passed Godot
`--headless --check-only`. `tools/source_pose_posture_regression.gd` passed
65-bone invariance with aim, recoil, saved frame keys, head-level and legacy-pistol
inputs asserted on the canonical PS1 fallback, not the selected modern mesh;
an unavailable lean leaves the source pose unchanged; a real
`seal_stand2llean` still blends; false restores the existing aim path. Broader
canonical-game/source-only checks are maintained by the coordinating task.

The persisted focused regression uses explicit failure collection and `quit(1)`,
not development assertions that could disappear or leave a quiet success exit.
