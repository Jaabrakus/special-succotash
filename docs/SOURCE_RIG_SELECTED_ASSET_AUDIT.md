# Read-only selected-character rest and binding audit

## Translation card

- Intent: identify why source-only main-game poses can have stretched neck,
  collapsed waist, and open fingers despite no post-AnimationTree bone edits.
- Acceptance: inspect actual selected asset, compare canonical/ordinary modern/
  ISO-proportion binary rests and inverse binds, and inspect pistol channels.
- Owner: offline observer `tools/source_rig_workbench_selected_audit.gd`.
- Protected: no character selection changes, source asset regeneration, new
  pose correction, movement, camera, weapon solver, or runtime edits.
- Proof: headless numerical audit of all three actual binaries and recorded
  SHA-256 values in `art_source/source_rig_verified_20260912/selected_rig_audit.json`.

System delta: KEEP existing anatomical target joint spacing; REJECT promotion
of unvalidated source-control origins to target deform joints. Scores in order
correctness, ownership, canonical runtime parity, editor usability, performance,
regression coverage: current numerical-only candidate gate 2/5/3/3/5/2;
candidate anatomical audit 4/5/3/4/5/4. This is an audit decision, not authority
to change the selected character. Visual validation remains required.

## What actually selected the mesh

`scripts/player/operator_character_selection.gd:6` reads the saved scene and
replaces `TrooperModel` at initialization:

```gdscript
var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
var previous := owner_node.get_node_or_null("TrooperModel") as Node3D
if previous != null and previous.get_meta("socom_modern_character", false):
    return
var scene := load(String(data.get("scene", ""))) as PackedScene
```

The configuration changed during this parallel audit. At the numerical capture
it selected `modern_soldier_iso.scn`; an earlier read selected ordinary
`modern_soldier.scn`. The report records the snapshot, not a promise of the
current file. An already initialized modern character is not hot-replaced by
changing this JSON. Therefore verify the in-memory scene and start a fresh
test process before attributing a render to a later on-disk selection.

## Actual binary measurements

Measured at the canonical runtime model scale of 62. All three have 65 bones.
Ordinary modern local rests match canonical PS1 exactly. ISO changes 22 local
rest transforms, but preserves every local rest orientation.

| Rest landmark span | Canonical / ordinary modern | ISO-proportion candidate |
| --- | ---: | ---: |
| Hips to lower spine | 107.78150 mm | 0.00266 mm |
| Left/right clavicle origins | 138.20887 mm | 0.06296 mm |
| Upper spine to neck | 161.67219 mm | 284.42696 mm |
| Neck to head | 126.94943 mm | 93.58536 mm |
| Shoulder joints | 424.61446 mm | 409.94236 mm |
| Hips to head | 665.55423 mm | 612.15073 mm |

Each modern asset's 14 sections have 910 inverse binds in total. Ordinary
modern maximum rest/bind cancellation translation residual is 0.000290 mm;
ISO candidate maximum is 0.000308 mm. Maximum basis residual is below
0.000000184 in both. These bindings are internally consistent with their own
rest skeletons. A binding-consistency pass is not an anatomical correctness
pass, and rebinding the same collapsed target skeleton will not fix its shape.

## Mechanism in code

`tools/modern_iso_proportion_builder.gd:3` aliases source controls directly to
target deform joints (`hips` → `Hips`, `spinelo` → `Spine`, `lscap/rscap` →
the two shoulders). Its target placement is:

```gdscript
targets[rig.find_bone(canonical)] = old_ankle + facing * (source_point - source_ankle) * uniform_scale
...
rest.origin = parent_global.affine_inverse() * resolved[bone].origin
rig.set_bone_rest(bone, rest)
```

The recovered source hips/lower-spine origins are nearly coincident, as are
the two scapular control origins. Those are not equivalent landmarks to the
distinct anatomical deform joints on this modern mesh. Direct substitution
therefore collapses its pelvis/spine spacing and changes the chest/neck shape.
This is a concrete deformation mechanism consistent with the failed render;
the audit does not establish that it is the only visual defect.

`tools/build_modern_soldier.gd:223` bakes these changed target transforms into
each weighted vertex and generates matching inverse binds at line 255:

```gdscript
var transform: Transform3D = to_local * transforms[key] * source_binds[bind]
point += (transform * vertices[v]) * weights[offset]
...
instance.skin.add_named_bind(target_rig.get_bone_name(bone), target_rig.get_bone_global_rest(bone).affine_inverse())
```

Consequently this is not repaired merely by clearing runtime overrides.
`operator_proportion_animation_adapter.gd` rebases animated position tracks to
the changed rests; it does not reconstruct anatomical joints or repair a mesh
baked against collapsed target landmarks.

## Fingers are a separate missing-input problem

The audit found zero Thumb/Index/Middle/Ring/Pinky channels in each of:

- `assets/animations/seal_reference/seal_p_run.tres`
- `assets/animations/seal_firing_reference/seal_pfp_run.tres`
- `assets/animations/seal_gameplay/pistol_run_forward.tres`

Removing procedural grip corrections cannot reveal finger keyframes that are
not present. The unchanged source-only channel set leaves those target fingers
without authored pistol closure. It does not prove what original SOCOM hand
geometry looked like. A proper hand fix needs an explicitly authored/retargeted
grip pose or verified original hand data, not a claim that those source clips
already contain the missing finger animation.

## Minimal safe next implementation, not performed by this audit

1. Re-test the ordinary modern asset in a fresh `main.tscn` process to separate
   existing retarget behavior from the failed ISO anatomical deformation.
   Its rest is canonical and its inverse binds already match; no rebind is
   needed simply to test that existing asset.
2. If source proportions are still required, establish homologous anatomical
   landmarks rather than using coincident source control pivots as deform
   joints. Preserve native joint spacing where that mapping is unsupported.
3. Create a new candidate from the untouched native skinned source, rebuild
   mesh rest/binds together only after validating the target anatomy, and
   retarget motion to that rest. Do not overwrite either existing binary.
4. Inspect rest plus early/middle/late source motion from multiple angles;
   test pelvis/chest/neck surfaces, section seams, fingers and weapon contact
   separately. Numerical bone parity alone is insufficient.

No character, skin, selection, or animation was changed by this audit.

## Reproduction

```sh
/Users/kiwimango/Applications/Godot-4.7.1.app/Contents/MacOS/Godot \
  --headless --path /Users/kiwimango/socom-141-camera-lab \
  --log-file /private/tmp/source-rig-selected-audit.log \
  --script res://tools/source_rig_workbench_selected_audit.gd
```

The tool emits `SOURCE_RIG_SELECTION_AUDIT` JSON and does not write any assets.
The first launch had an extra parenthesis in its report initializer and did
not execute; after that audit-only typo was fixed the run exited 0. Godot's
macOS certificate warning is unrelated to this local asset inspection.
