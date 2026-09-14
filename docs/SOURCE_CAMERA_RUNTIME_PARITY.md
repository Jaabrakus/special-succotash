# Original gameplay camera runtime audit

Current implementation update (2026-09-13): the user subsequently chose “both
hybrid”. The saved default combines the source lens/level shot with bounded
existing pitch framing, lean-follow and collision/trailing. It retains source
root channels and original ordinary X/Z preprocessing, but deliberately differs
from original pitch framing. See `docs/CAMERA_HYBRID_TRANSLATION_CARD.md`.
See `docs/SOURCE_CAMERA_ANCHOR_INTEGRATION.md` and
`docs/SOURCE_CAMERA_ROOT_MOTION.md`. The lens-only rejection below remains valid
historical evidence; it no longer describes the complete current camera.

## Translation card — 2026-09-13

- Player intent: match the original gameplay camera, not an arbitrary partial blend.
- Acceptance: connect decoded original camera settings to their instruction-backed consumers, identify active state selection and projection equations, and execute bounded original-instruction fixtures before proposing saved camera changes.
- System owner: offline `tools/source_camera_runtime_audit.cjs`; eventual presentation remains owned by `SocomCameraRig`.
- Must not change in this audit: live camera settings, canonical movement/collision, animations, aim or server weapon authority, running game processes, or source files.
- Focused proof: checksum-verified source ranges, numeric fixtures, exact current-runtime mapping and explicit unresolved state mappings. Imported reader values alone are not active-camera proof.
- System delta: MERGE source evidence; do not promote the existing optional 20% hypothesis as parity.

## Verified result and boundary

**Done:** decoded S2 world loader overrides the stored map half-horizontal FOV
to approximately 35 degrees (full horizontal 70 degrees). The camera setup
selects `back`, not `full`, from five reader-created presets. Twenty-nine bounded
original-instruction fixtures pass with no unknown external-call stubs.

**Done within the clear-path domain:** default algorithm-2 root-height bonus,
lean input offset, pitch quaternion sign and radius collapse are decoded and
numerically cross-checked. **Partial:** independent source-root integration,
original collision/recovery/trailing, effective zoom/projection scale and raster.
The lens-only runtime candidate fails native framing and is NOT the default.
This audit does not make the canonical camera 1:1.

The earlier optional 20% distance trial is not an original camera algorithm.
Its `cam_full_dist = 30` is real reader data, but that is not the default preset
selected by the verified source code. Do not simply enable that trial.

## Original source provenance

Both decoded original modules retain their MWo3 header and declared base; source
PCs below map to file offsets by subtracting that base. The observer verifies
the bytes before interpreting them:

- `FTSCore.bin`, base `0x1e7000`, SHA-256
  `cf09a7fabaf59a1d68f01411bd1db9e859af054df1f2fbc4775d8c221785f836`.
- `ZSealEtc.bin`, base `0x4c5380`, SHA-256
  `cdb3fa8e707090ac879874e3987c6b7784808a4767e85d0e19fc6909d36549b1`.

The files are in
`art_source/socom2_ballistics_reference_20260912/decoded_runtime_v1/`.
The observer reads `RUN/READERC.ZAR` directly from the user's ISO through the
existing read-only parser and verifies `dynamics.rdr` SHA-256
`c09f0b84bd8b612d69b24df678a7b5ce8c1fb72a79706445939b7f6d0e6db0bc`.
No source binary, reader, camera profile or running process is changed.

## Default lens: original S2 executable proof, not reconstruction inference

The world loader reads a 144-byte camera record at `FTSCore:0x3191e0`. It then
loads this explicit constant, overriding the record's horizontal angle:

```text
3191ec lui v0,0x3f1c
3191f0 ori v0,v0,0x61aa
319200 mtc1 v0,f12
319204 addiu a1,zero,1
...
319268 jal 0x291490
```

Bits `0x3f1c61aa` represent `0.6108652353286743` radians: a half-horizontal
angle giving `69.99999967119774` degrees full horizontal FOV. Unlike the earlier
related reCOM excerpt, this is verified in **SOCOM II's decoded executable**.
The observer executes the constant-loading slice and pins the actual setter
call opcode. The constructor separately supplies 70 degrees to `0x2913f0` at
`0x293a98–0x293ac0`, and 49 degrees to the vertical setter at `0x293ac8`.

Setter `0x291490` saves the supplied half angle at camera `+224`, evaluates
original sine/cosine, then sets:

```text
camera[448] = sin(half_horizontal_angle)
camera[456] = cos(half_horizontal_angle)
camera[472] = 1 / (camera[448] / camera[456])
camera[656] = camera[1200] * camera[472]
```

`0x293e0c–0x293e40` establishes camera `+1200 = float(W >> 1)`; the earlier
`tools/source_projection_factor_audit.cjs` executes that path. Thus `+656`
(`0x290`) is a projection-distance value, not an angle. The degree setter at
`0x2913f0` explicitly computes `float32((degrees * 0.5) * 0.01745329238474369)`.
This audit executes that prelude for 70, 49 and 90 degrees. It does not rerun
the full trigonometric setter; the earlier tangent audit remains separate.

The source can also scale projection through camera `+1136/+1140`. This means
70-degree default initialization is not proof that effective gameplay FOV
remains constant during every scope, zoom or special state. Do not equate
the constructor's 49-degree vertical field directly to Godot `KEEP_HEIGHT`
without the final projection/raster mapping.

## Presets actually built and selected

`ZSealEtc:0x555110` calls the dynamics reader at `0x59ba80` with the global
structure at `0x44c250`. Its vector at `+432` has count `+436` and data pointer
`+440` (`0x44c408`). `0x59c760–0x59cce0` appends five 24-byte records in this
order; each contains a three-float camera offset and three-float aim point:

| Index | Reader prefix | Offset in source units | Aim in source units |
| --- | --- | --- | --- |
| 0 | `cam_back` | `(0, 20.5, 13)` | `(0, 20.5, -2)` |
| 1 | `cam_side` | `(5, 19, 8)` | `(5, 19, -2)` |
| 2 | `cam_first` | `(0, 20.5, 13)` | `(0, 20.5, -2)` |
| 3 | `cam_peekl` | `(-70, 0, 0)` | `(-30, 0, 0)` |
| 4 | `cam_peekr` | `(70, 0, 0)` | `(30, 0, 0)` |

For example, `0x59c798/0x59c7c0/0x59c7e8` load the back side/height/distance;
`0x59c800–0x59c80c` assemble the offset; `0x59c880` appends its 24-byte record.
The source reader contains `cam_full_*` values, but the verified append path
does not include them, and neither decoded module contains that key string.
This is evidence about these modules/reader path, not a claim that every
possible source overlay has been searched.

Camera setup at `FTSCore:0x29b3c0` explicitly resets to preset zero:

```text
29b3e0 sb zero,321(s0)
29b3e4 sb zero,228(s0)       # preset index = back
29b3e8 addiu v0,zero,2
29b3ec sb v0,320(s0)
29b3fc lw v0,-15352(at)     # 0x44c408 record pointer
29b400 sll v1,a3,1
29b404 addu v1,v1,a3
29b40c sll v1,v1,3          # 24 bytes per preset
29b410 addu v0,v0,v1
29b414 lwc1 f0,0(v0)
29b418 swc1 f0,28(s0)       # offset X
```

The following instructions copy the offset to owner `+28/+32/+36` and aim to
`+4/+8/+12`. The change handler at `0x29bdf0` performs the same indexed copy.
The observer executes setup with an initially different index to prove the
reset, then executes all five indexed copies with the original source records.

Using the verified world scale `0.10000000149011612 m/source-unit`, the back
record's raw dimensions are approximately 1.3 m behind and 2.05 m high. These
are **local input offsets**, not proven final camera-to-player distances:
setup transforms both vectors through the followed node's matrix at
`0x29b4d4/0x29b514`, then constructs the camera matrix at `0x29b530`.
Large peek values especially must not be copied directly to metre offsets.

There is a separate camera algorithm state at owner byte `+313`; its
constructor default is 2 (`0x29b6a0/0x29b6e4`). The update at `0x2998f0`
dispatches default state 2 through `0x296f10` (`0x299aa8`). This is distinct
from preset index `+228`: do not conflate the two enums.

## Pivot, stance and zoom findings still needing full connection

- Default updater `0x296f10` calls `0x29a950` for the target/offset inputs,
  `0x297410` for an adjustment, `0x29bf70` for geometric handling and
  `0x29bc90` for the resulting camera matrix. The complete chain has not been
  executed in the offline fixtures.
- Target helper `0x29ae50` uses a followed entity animation-node transform via
  `0x2869d0` when available. It has a distinct base-stance-2/prone path at
  `0x29aed0–0x29af40`, and different aim-node offsets otherwise. Therefore a
  guessed constant crouch/prone height is not established by `cam_back_height`.
- `init_aim_pitch` is multiplied by radians-per-degree at
  `ZSealEtc:0x59bdf0–0x59be08`, stored at dynamics `+84` and copied into input
  owner `+304` at `0x597e88–0x597e90`. Its source value is approximately
  -9.167 degrees. The quaternion sign is now verified below; initialization is
  not copied into the player's current aim angle because that would reset input.
- `zoom_factor` and `zoom_rate` are parsed into dynamics `+292/+296` at
  `0x59c734/0x59c75c`. Their raw 5500/14000 values are not camera metres or
  degrees. The original effective scale and scope-state consumers remain to
  be completed before integration.

## Canonical mapping proposal

The current canonical owner is `SocomCameraRig` in
`scripts/camera/socom_camera.gd`, instanced by
`scenes/camera/socom_camera_rig.tscn` and `main.tscn:18`.
`_ready()` creates the single `Camera3D`, currently setting
`camera.keep_aspect = Camera3D.KEEP_HEIGHT`. Profile `vertical_fov` currently
defaults to 68 degrees in `scripts/camera/camera_profile.gd`.

`scripts/camera/camera_preferred_shot_solver.gd:preferred_position()` currently
does this before framing/collision corrections:

```gdscript
const ANCHOR_HEIGHT := 1.05
var anchor = rig.target.global_position + rig.movement_lead + Vector3.UP * ANCHOR_HEIGHT
# ... existing interpolation ...
return anchor + back * shot_distance + Vector3.UP * shot_height # ...
```

Consequently, copying source height 2.05 m to the existing profile height adds
another 1.05 m before the current composition solver. A source-camera mode
must replace the *bounded preferred-shot calculation* and its applicable
framing assumptions inside this owner, not add a second camera or multiply
source offsets into the existing anchor. Lens conversion must preserve the
verified horizontal-angle meaning and original raster/projection-scale policy.
No source preferred-position replacement is activated. The independent lens
plumbing is available only as an explicit unpromoted candidate.

An external merge interrupted the audit, then was resolved by the other client
at checkpoint `5340bb8b`. No conflicts were resolved by this audit. Subsequent
Godot tests run against the cleanly parsing current branch, preserving other work.

## Default algorithm 2: actual clear-path preferred pose

The algorithm state byte `+313` is separate from the five presets. Default state
2 dispatches `0x296f10`, which calls `0x29a950`. In the ordinary self-follow path,
that helper reads the followed character's `+744` node. The source node lookup
at `ZSealEtc:0x554408 -> FTSCore:0x28e7b0` uses the exact string `skel_root`
at `0x65c4c0`, then stores the node pointer at character `+744` (`0x554414`).

`0x29a9cc -> 0x2869d0` resolves that node's hierarchical **model-local** position.
It is not the head marker, entity origin, or hips child. The hierarchy helper
walks parent translations/rotations; the entity world matrix is applied later.
For raw root `(x,y,z)` and already-filtered source lean `l`, original scalar order is:

```text
t = y >= float32(0x40b33333) ? 1 :
    clamp(float32((y - float32(0x400ad36f)) * float32(0x3e953c00)), 0, 1)
bonus = y == 0 ? 10 : float32(5.5 + float32(4.5*t))
x = float32(x + float32(l * (l < 0 ? 2.5 : float32(0x40333333))))
pivot = (x, float32(y+bonus), 0)
back = (x, 0, float32(z+28))
r0 = length(back)
u = normalize(Qpitch * back)
pivot.z = u.y * (u.y < 0 ? -3 : -8)       # ordinary clear-path branch
r = float32(r0 + float32(abs(u.y) * float32(14-r0)))
cameraLocal = pivot + u*r
farAimLocal = pivot + Qpitch * (0,0,-1000)
```

Source constants decode to 5.599999904632568, 2.1691548824310303,
0.291473388671875 and 2.799999952316284. `0x29aa08–0x29ab78` supplies root/lean
and radius inputs; `0x29ad28–0x29ad4c` supplies collapse. The saved Godot pure
helper uses corresponding constants and operation order, but Godot scalar/Basis
arithmetic is checked to tolerance, NOT described as bit-identical PS2 FPU/VU.

The source pitch writer `ZSealEtc:0x5af470 -> FTSCore:0x3075e0` constructs
`Qpitch=(sin(pitch/2),0,0,cos(pitch/2))`. Executing original scalar quaternion-to-
matrix `0x307170` for five signed angles proves its positive-Z basis has
`Y=-sin(pitch)`: positive pitch looks up, matching the existing Godot X-axis
convention. This does not emulate the entire original VU vector helper.

There are unported branches: positive `u.y` can use `-5` for special character
conditions and can receive collision correction through `0x29cbb0`.
`0x297410` transforms the local camera and far aim through the entity matrix;
the near aim subsequently computed at `0x296fd0–0x297020` lies on the same
camera-to-far-aim direction. `0x29bc90` constructs the final view matrix.
Original collision, transition interpolation, filtered lean and scope paths
are not represented as implemented by the pure helper.

The verified scale is `0.10000000149011612m/source-unit`, not the older arbitrary
64x character scale. Source posture changes arrive through animated root Y,
not guessed separate crouch/prone height constants.

## Why exact source position cannot yet be activated

The selected 65-bone rig has `mixamorig_Hips`, but not `skel_root`.
`tools/import_seal_reference_animations.gd:ALIASES` maps source `hips` only;
its bake folds ancestor transformations into mapped bones and then zeros the
horizontal translation tracks. `tools/modern_iso_proportion_builder.gd` likewise
retains canonical bone names/parents. The original root and hips are independent:

```text
seal_run: skel_root position [41,2638,7233]/256 at first sample
          hips local position [0,0,-12]/256, then [7,23,-25]/256, [12,43,-59]/256
seal_prone: skel_root position [170,555,-298]/256; hips local position [0,0,0]
```

These are original decoded channel values in
`/private/tmp/socom-iso-motion-audit-20260912/motion/` and hierarchy in
`/Users/kiwimango/Downloads/SOCOM-II-animation-extractor/output/seal-skeleton.json`.
No exact inverse recovers independent root movement from the folded/stripped hips.
`observe_native_root()` intentionally refuses a hips fallback and never writes a
bone. It accepts a real native `skel_root` and an explicitly supplied proven
model-space conversion only; current canonical rig returns no sample.

A future independent observer node/AnimationTree channel could retain the root
without changing 65-bone skin indices, but this requires the importer, animation
library/cache, layer-mask and clip-derivative paths to preserve synchronized
root samples. Original runtime root-motion extraction must also be traced:
copying the raw locomotion travel into the camera may introduce camera drift.
This was not performed as an unverified broad repair in this pass.

## Runtime lens candidate and failed rendered promotion

`config/camera_source_match.json` is saved with `enabled=false` and
`preferred_position_enabled=false`. Explicit `--source-camera-match` enables
the verified default lens through the existing rig/composition owner:

```gdscript
if rig.source_camera_match.lens_enabled():
    rig.current_fov = rig.source_camera_match.lens_vertical_degrees(
        rig.get_viewport().get_visible_rect().size)
    rig.camera.fov = rig.current_fov
    return
```

For `Camera3D.KEEP_HEIGHT`, the helper returns
`2*atan(tan(horizontalFov/2)/aspect)` in degrees. This preserves the camera's
existing vertical projection convention, used by `camera_subject_projector.gd`
and VRC (`socom_camera.gd`), instead of incorrectly setting vertical FOV to70.
The workbench labels the source-fixed lens only when enabled and otherwise
retains its functional authored vertical slider. Settings reject wrong types,
non-finite values and invalid viewport inputs.

The lens-only candidate passed numerical projection/ownership checks but failed
native skinned-character framing: standing head approaches the bottom edge and
crouched character drops out at level aim; positive pitch loses the subject.
Evidence: `/private/tmp/source-gameplay-camera-main-native/standing-pitch0-yaw0.png`
and `/private/tmp/source-gameplay-camera-main-native/crouched-pitch0-yaw0.png`.
The first capture run's terminal PASS meant numerical checks only; the regression
was then extended with actual skeleton head/chest visibility checks to record
this real acceptance failure. Default activation was rejected, not hidden by
moving the camera to an invented hips anchor. Existing authored lens/position,
composition and collision/trailing remain default. Candidate source lens disables
the authored close-wall lens widening; physical collision safety remains intact.

## Reproduce

```sh
node tools/source_camera_runtime_audit.cjs /private/tmp/source-camera-runtime-NEW.json
```

The output uses new-file-only creation. Last result:

```text
SOURCE_CAMERA_RUNTIME_AUDIT PASS original_cases=29 presets=5 unknown_stubs=0
```

Report: `/private/tmp/source-camera-runtime-20260913-v2.json`. Cases cover setup,
five presets, world angle override, three degree-setter inputs, eight root/lean
inputs, five quaternion matrices and six radius collapses. This is bounded
numerical source-path proof, not full rendered camera parity.

Focused Godot regression: `tools/source_gameplay_camera_regression.gd`.
Actual main: `tools/main_source_gameplay_camera_regression.gd`; use `--candidate`
for the unpromoted lens, `--capture` for rendered proof and
`--output=/private/tmp/NEW-DIRECTORY` to keep runs separate. No browser ZIP has
been rebuilt or existing game process restarted by this work.

## Final verification / remaining failures

- Original-instruction observer: **PASS,29 cases**, zero unknown call stubs.
- Pure Godot policy/validation/observer: **PASS,52 checks**;
  `/private/tmp/source-gameplay-camera-unit-final.log`.
- Feature graph: **PASS,147 contracts** at the time of the run;
  `/private/tmp/source-camera-contracts.log`. This structural gate does not
  override failed rendered acceptance.
- Candidate main: **FAIL,4 visibility assertions** (standing and crouched
  skinned head/chest). Numerical70HFOV, aspect resize, active camera ownership,
  finite positions, real stance commands and reticle projection checks passed.
  `/private/tmp/source-gameplay-camera-candidate-rejection/measurements.json`.
- Restored default main: **FAIL,1 existing crouched chest visibility assertion**;
  authored vertical68 lens preserved, standing/prone level-aim subject checks
  and all projection/ownership tests passed. This existing baseline framing
  issue is retained for follow-up, not weakened to produce a green test.
  `/private/tmp/source-gameplay-camera-default-native/measurements.json`.

At level aim/yaw0 the **actual posed skeleton** normalized head/chest Y is:

| Stance | Authored default head/chest | Source-lens-only candidate head/chest |
| --- | --- | --- |
| Standing | 0.825 /0.950 | 1.000 /1.194 |
| Crouched | 0.930 /1.054 | 1.166 /1.359 |
| Prone | 0.728 /0.785 | 0.757 /0.832 |

Values>1 fall below the viewport. Rendered default comparisons were inspected
at `/private/tmp/source-gameplay-camera-default-native/{standing,crouched}-pitch0-yaw0.png`
and `prone-pitch0-yaw65.png`; both native runs captured18 stance/pitch/yaw views.
This is why neither source camera position nor source lens was promoted.
