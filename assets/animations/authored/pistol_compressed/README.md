# Native compressed pistol idle

The source is the existing accepted Mark 23 `FIRE_RECOVERY` frame in canonical
`main.tscn`, not the rejected low-ready Blender candidate. Standing and crouched
source references are saved separately from their compressed idle versions.

`tools/bake_pistol_compressed_idle.gd` is an isolated authoring capture. It:

1. Equips Mark 23 through the canonical pickup owner, freezes player movement,
   accepts a shot, and targets 25 m forward at physical muzzle height.
2. Requires both physical hand contacts within 1 cm and bore error below 1°.
3. Converts final skeleton-space poses (including one-shot IK) into parent-local
   rotations; this preserves the already accepted shoulder, chest, and head frame.
4. Retracts both palms 14 cm along the same backward direction while preserving
   both wrist orientations, the weapon scale, and its original socket spacing.
5. Saves 54 upper rotation tracks over each original stance's lower-body clip.
   Hips and leg tracks, their timestamps, and their values remain unchanged.

The `pistol_recovery_reference_*.tres` files contain the uncompressed accepted
source frame. The `pistol_compressed_idle_*.tres` files contain the retracted arms.
Both use canonical expanded `mixamorig_` bone names and `.:BoneName` track paths.

## Immutable mount alignment

The original capture's final weapon direction came partly from a detached
weapon-root rotation, not its wrist bone. Capturing bones alone therefore did
not preserve the physical muzzle direction once the immutable hand mount resumed.
The integration check caught a 24° standing / 29.5° crouched missing wrist rotation.

`tools/align_pistol_compressed_wrist.gd` closes that authoring gap. It always starts
from the immutable `captured_raw/` references, applies the missing rotation to the
right wrist around the same palm, and solves the two arms back onto the original
physical grip contacts. It changes only Arm, ForeArm, and Hand rotation tracks;
chest, shoulders, head, lower body, and all weapon configuration remain unchanged.

The final resources in this folder include this wrist correction. Its acceptance
test saves and reloads each resource, evaluates it directly with NO runtime aim or
IK modifiers, and verifies the canonical raw hand mount: bore/roll within 0.2°,
both contact errors within 2 mm, and trigger palm movement below 2 mm.
`wrist_alignment_report.json` contains the actual measurements and `*_mounted.png`
shows these reloaded, modifier-free poses. This is the correct repeatable rebuild
step once the original capture references exist; do not recapture changed runtime
profiles simply to rebuild the wrist-corrected assets.

`report.json` records measured capture results. The four PNGs compare the isolated
canonical source/compressed poses. These are asset-authoring results, not proof
of runtime integration: the game must separately load the resources, avoid adding
old shoulder/head corrections twice, retain the physical weapon mount and aim
solve, and test settled states plus animation transitions.

Official transform convention: Godot's `Skeleton3D.get_bone_global_pose()` is
skeleton-space, not world-space. The baker uses parent-inverse multiplication
before writing local animation rotations.
https://docs.godotengine.org/en/latest/classes/class_skeleton3d.html

Do not blindly rebake after changing the selected pistol presentation profile.
The tool intentionally captures the currently selected canonical recovery; a
future author must verify the source images and report before replacing these
reference assets. Existing runtime or profile files are never written by the tool.
