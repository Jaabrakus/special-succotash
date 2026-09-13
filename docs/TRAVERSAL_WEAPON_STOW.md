# Equipped weapon stow during traversal

## Translation card

- Intent: free both hands during traversal without making the equipped gun vanish.
- Acceptance: a cosmetic copy follows the spine for primaries or hip for pistols;
  the helper never mutates the real firearm; its existing owner uses the canonical
  animation mount during traversal and resumes its normal mount selection on exit.
- Owner: `SocomOperatorTraversalStow` owns only the cosmetic copy. The existing
  animation driver owns real-weapon visibility and traversal lifetime.
- Must not change: ammo/inventory, sockets, shot/damage authority, movement, aim,
  source weapon transforms, bone poses, backpack/objective ownership.
- Proof: `tools/traversal_weapon_stow_regression.gd`, the feature contract gate,
  and rendered main-scene traversal inspection.

## Runtime chain

`Player.get_traversal_presentation()` →
`operator_animation_driver_runtime.gd::_advance_traversal_presentation()` →
`config/traversal_weapon_stow.json` → `SocomOperatorTraversalStow.begin()` →
`Skeleton3D/TraversalStowedWeaponAttachment/TraversalStowedWeaponVisual`.

```gdscript
traversal_stow.begin(skeleton, weapon_node, equipped_weapon_family)
# The existing driver, not the helper, hides the actual weapon.
traversal_stow.end() # exit or death
```

The attachment has `override_pose = false`: it follows the named bone and never
writes a skeleton pose. All copied children are newly constructed plain
`MeshInstance3D` nodes. Only immutable mesh and active material resources are
shared. No source scripts, physics bodies, sockets, sounds, particles, timers,
animation players, skins or gameplay state are duplicated.

The helper recentres the visible geometry and aligns its muzzle-to-stock axis
upwards, then applies the profile's bone-local metre offsets and rotation.
The profile has separate `primary` and `pistol` settings. Native Spine2 **negative
Z** is the reviewed back side; the first positive-Z trial placed the rifle on the
chest and was rejected. Whole-character scale is cancelled at the visual child,
matching the existing bone-attachment convention.

`begin()` is idempotent for the same skeleton, weapon and mesh/material identity.
Changing weapons or replacing geometry beneath an unchanged weapon root rebuilds
the cosmetic copy. Animated transforms are deliberately excluded from that
fingerprint: pose updates must not allocate a new cosmetic weapon each frame.
`end()` hides immediately and queues the copy for deletion; it also clears local
references. It is safe after skeleton destruction and on repeated calls. The
driver must call `end()` on its lifecycle exit; the skeleton itself owns the
attachment's node lifetime. Do not call script methods from this RefCounted
helper's `NOTIFICATION_PREDELETE`: that produced a null-instance shutdown error
and was removed.

## Limits and checks

- This displays the **currently equipped** firearm only, not every unequipped
  inventory item. It is not a persistent second-primary or backpack feature.
- There is no authored hand-to-sling animation or physical sling strap. The
  presentation switches to its stowed attachment when traversal starts.
- Pistol and primary defaults are shared family settings. Unusual long weapons
  may require per-weapon offsets later; no such overrides are claimed here.
- Skinned weapon meshes are shown as rigid static geometry without copying their
  source skeleton. A magazine/bolt skin animation is not replayed on the stowed
  copy. The reviewed rifle is rendered correctly; inspect other unusual rigs.
- The regression uses `main.tscn`, checks source parent/local transform/visibility
  unchanged by the helper, verifies plain geometry-only children, idempotence,
  same-root mesh replacement, real Mark 23 visual support, and clean/freed-skeleton
  exit. It does not claim multiplayer traversal acceptance by itself.

Run the focused regression with the installed Godot executable and
`--script res://tools/traversal_weapon_stow_regression.gd`. Add `-- --capture`
in a rendered process to write
`art_source/traversal_runtime_proof/stow-rifle.png`.

Godot API references: [BoneAttachment3D](https://docs.godotengine.org/en/latest/classes/class_boneattachment3d.html)
and [MeshInstance3D](https://docs.godotengine.org/en/latest/classes/class_meshinstance3d.html).
Only APIs checked on installed Godot 4.7.1 are used; latest documentation is not
assumed to describe arbitrary older engine versions.
