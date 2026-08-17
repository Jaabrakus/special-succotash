# Operator movement animation map

The movement controller emits travel, posture, action, and aim intent. It does not
select animation files. `SocomOperatorAnimationDriver` converts that intent into a
logical animation slot, and `default_animation_profile.tres` maps the slot to an
imported or replacement clip.

The lower body remains aim-facing during ordinary strafes and backpedals. It only
catches up after the torso reaches the exported 42-degree twist limit, matching
the visible chest rig so aim and footwork cannot disagree.

Input actions are unambiguous: Space always jumps, including while moving; Z is
the separate dive-to-prone action; X controls crouch; and Q toggles ordinary prone.

## Loop matrix

Each standing/crouched locomotion family supports eight directions:

`forward`, `forward_left`, `left`, `back_left`, `backward`, `back_right`, `right`,
and `forward_right`.

The loop families are:

- `low_ready_walk_*`
- `low_ready_run_*`
- `low_ready_crouch_*`
- `walk_*` (combat-ready)
- `run_*` (combat-ready)
- `crouch_*`
- `low_ready_prone_forward`, `backward`, `left`, and `right`
- standing, crouched, and prone idle loops for low-ready and combat-ready
- standing, crouched, and prone compressed-ready loops for close cover

## Replacing animations

Open `default_animation_profile.tres` in Godot. Add an `AnimationLibrary` to
`Loop Overrides` or `Action Overrides`, then add animations using the logical slot
names above. A same-named animation replaces the placeholder automatically.

If an imported clip must keep its original name, add an entry to `Clip Aliases`
from the logical slot name to the imported clip name.

Camera and movement code never depend on the replacement asset. This makes the
same animation profile usable by local players, remote multiplayer proxies, and
future operator skins.
