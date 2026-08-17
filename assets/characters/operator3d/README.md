# SOCOM-141 runtime operator

This folder contains the Godot-ready GLB and the generated clip manifest.

- 65-bone Mixamo-compatible humanoid skeleton
- separate gameplay root and weapon controls (67 total skeleton nodes)
- separate Mixamo Beta skinned body with its native bind skeleton
- project-authored rifle retained on the separate weapon control
- 122 project-authored fallback actions at 30 FPS
- 23 curated Mixamo rifle clips retargeted and baked offline
- low-ready walk, run and crouch locomotion in eight directions
- low-ready prone locomotion, weapon raise/lower, combat-ready recoil,
  compressed-ready wall poses, and jump/dive/roll recoveries
- Mixamo character and animation data are embedded only in the runtime GLB;
  source FBX files remain outside the Godot project

The 65 humanoid names match the Mixamo convention so licensed source clips can
be retargeted in the offline build pipeline. Character movement, collision,
camera anchors and multiplayer authority remain outside the visual skeleton.
Godot safely imports the canonical `mixamorig:` prefix as `mixamorig_`; the
runtime animation driver accounts for that normalization explicitly.

The reference pose sheets under `assets/animation_reference/` are visual
direction only. The GLB in this folder is the actual runtime animation data.

The curated bake replaces standing idle/walk/run presentation while retaining
the authored actions as instant fallbacks. Horizontal FBX root motion is
stripped; `CharacterBody3D` remains the only movement authority.

The rendered Beta body is visual-only. At runtime the final global pose of each
humanoid bone is mirrored from the authoritative animation rig to the native
skin skeleton. It does not own collision, camera anchors, weapon traces, or
multiplayer state. Re-run `tools/run_mixamo_retarget.sh` to rebuild both the
clips and visible skin.
