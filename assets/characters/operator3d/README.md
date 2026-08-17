# SOCOM-141 runtime operator

This folder contains the Godot-ready GLB and the generated clip manifest.

- 65-bone Mixamo-compatible humanoid skeleton
- separate gameplay root and weapon controls (67 total skeleton nodes)
- rigid-weighted low-poly body and tactical equipment
- 122 named actions at 30 FPS
- low-ready walk, run and crouch locomotion in eight directions
- low-ready prone locomotion, weapon raise/lower, combat-ready recoil,
  compressed-ready wall poses, and jump/dive/roll recoveries
- original project asset; no third-party character or animation data

The 65 humanoid names match the Mixamo convention so licensed source clips can
be retargeted in the offline build pipeline. Character movement, collision,
camera anchors and multiplayer authority remain outside the visual skeleton.
Godot safely imports the canonical `mixamorig:` prefix as `mixamorig_`; the
runtime animation driver accounts for that normalization explicitly.

The reference pose sheets under `assets/animation_reference/` are visual
direction only. The GLB in this folder is the actual runtime animation data.
