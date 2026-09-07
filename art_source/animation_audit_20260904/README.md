# Native pistol pose study — 2026-09-04

Review candidate; not a runtime feature or a claim that the game is fixed.

## Sources and outputs

- Source character: `assets/characters/ps1_gas_mask_soldier/trooper_rigged.fbx`.
- Source texture: `assets/characters/ps1_gas_mask_soldier/trooper.png`.
- Initial pose reference: `assets/animations/mixamo/Pistol_Handgun Locomotion Pack/pistol idle.fbx`.
- Reproducible authoring script: `tools/blender/build_pistol_pose_candidate.py`.
- Editable source: `pistol_square_native_candidate.blend`.
- Interchange candidate: `pistol_square_native_candidate.glb`.
- Measurements and original rest matrices: `pistol_square_candidate_report.json`.
- Twelve front/side/rear-three-quarter renders compare the mapped source frame,
  new ready pose, low/chest idle pose, and recoil peak. They use the game's
  current PS1 trooper mesh.

## Rig and animation contract

The original FBX contains 41 authored bones. The canonical game expands its
runtime skeleton to 65; this study does not invent or move those 41 original
rest bones. Every original rest matrix is checked unchanged before export.
Names remain `mixamorig:BoneName`; Godot normalizes these to
`mixamorig_BoneName`.

The source armature's 0.01 object scale and axis transform are retained in GLB.
The Blender review scene has a separate `ReviewOnly62xGamePresentation` parent
for metric inspection. The gameplay instance can use a runtime scale override
(currently observed at 64 by the canonical audit); this parent is not exported.
Blender forward is -Y, up +Z; glTF exports +Y up.

The GLB carries three baked upper-body rotation actions. The export script removes
automatically sampled rest translation/scale tracks and lower-body tracks:

- `PistolReadySquare_Candidate`: 1.2-second static pose, shoulders square,
  forward two-hand cluster, balanced soft elbow bends.
- `PistolLowReady_Candidate`: 1.2-second static close-chest carry, elbows down,
  calibrated firing wrist frame pitched down 25°. This is a distinct idle pose;
  the runtime remains responsible for fire, 1.2-second hold, and return timing.
- `PistolRecoilSquare_Candidate`: 0.4-second return, 2cm back/1.2cm up/3° peak.

`PistolIdle_SourceReference` remains in the Blender file as a diagnostic. It is
generic Mixamo local deltas copied onto the trooper, not a recorded canonical
runtime pose. Its measured comparison must not be presented as an in-game
before/after result.

No new continuous IK, root motion, movement, weapon authority, reload behavior,
or networking system is exported. Baked bone rotations are the only candidate.

## Review limits

Measured authored ready geometry is square within 0.13°, with elbow inner angles
near 92° and both wrists approximately 40cm forward of the shoulders at 62x
scale. The low/chest pose places the trigger wrist 14cm forward and 24cm below
the shoulder midpoint, with elbow angles near 65° before canonical adaptation.
These measurements check geometry, not skin appearance or weapon contacts.

The first canonical runtime comparison passed rest matching (reported maximum
0.0396°), but failed weapon presentation: standing bore error 9.784° and support
gap 3.11cm; crouch bore error 21.4° and support gap 2.85cm. This exposes a wrist
orientation calibration requirement. The candidate must stay out of the live
animation map until wrist orientation, socket contact, reticle pitch/yaw,
standing/crouched/prone transitions, and movement pass in the canonical scene.

The next revision bakes the standing wrist orientation measured against the
canonical physical pistol sockets. The exact quaternion is stored in
`wrist_calibration.json` and copied into the report; the current GLB, Blender
file, and renders include it. Full runtime revalidation remains separate.
The parallel audit also found a ready-state weapon-scale error, so contact
acceptance must use the corrected physical weapon scale.

With full weapon scale restored, the calibrated revision passed bore alignment
(0.073° standing/0.144° crouched), but support reach failed (77.2mm/56.9mm gaps).
The final authored firing revision retracts the common hand cluster 14cm. This
is stored in `pose_design.json`; the script validates its 0–15cm adjustment
range. A final wrist calibration was measured after the canonical shoulder
leveling correction; `wrist_calibration.json` records it exactly.

The parent audit reports that the resulting high-ready candidate passes ten
Mark 23 canonical cases (two stances, five directions, six transition frames
each): bore error 0.027–0.118°, contact error at or below 1mm, level shoulders,
and elbows within 38–155°. This was in-memory candidate testing. It does not
establish live profile integration, all pistol models, or low-ready acceptance.
The low/chest action and the transition into/out of it still require the parent
audit's canonical runtime check.

The low/chest target was subsequently brought 16cm closer to the chest after
the full-size support socket exceeded anatomical arm reach. At 14cm authored
forward reach, the canonical diagnostic reports support contact within 1mm
and support elbow angles near 122° standing/127° crouched. Lateral placement
and final idle/fire transition presentation remain under review. Existing low
PNG previews must be refreshed after the final source placement is selected.

The apparent remaining lateral error was traced to import/composition, not
missing source channels. The raw GLB includes all 30 low-ready rotation
channels, including `RightShoulder`, `Spine1`, `Spine2`, `Neck`, and `Head`.
Godot's `GLTFDocument.generate_scene` defaults `remove_immutable_tracks=true`;
when those rest-valued parent tracks are omitted, composition can retain old
generic-idle parent rotations. The low-ready import must preserve those explicit
tracks with `generate_scene(state, 30.0, false, false)`, or equivalently restore
them at its import boundary. The builder now asserts source completeness and
records each exported rotation-channel name. Do not move the low hand cluster
sideways to compensate for missing parent tracks.

Runtime ownership remains in `operator_animation_driver` and
`operator_weapon_pose`; this file is authoring evidence only. The game remains
the visual acceptance authority.

## Rebuild

```sh
/Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup \
  --python tools/blender/build_pistol_pose_candidate.py -- \
  /Users/kiwimango/socom-141-camera-lab \
  /Users/kiwimango/socom-141-camera-lab/art_source/animation_audit_20260904
```
