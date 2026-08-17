# SOCOM-141 operator source

`socom_141_operator_animation_source.blend` is the editable Blender 4.5 LTS
source for the original project operator, its 122 fallback actions, and the 23
curated Mixamo rifle clips baked by the offline retarget pipeline. The rebuild
also exports the local Mixamo Beta skin with its native bind skeleton. Godot
mirrors the final animation pose onto that visual-only skeleton while retaining
the project-authored rifle.

Godot ignores this folder intentionally. The runtime export lives at:

`assets/characters/operator3d/socom_141_operator_animated.glb`

Rebuild the base with `tools/build_operator_animation_library.py`, then run
`tools/run_mixamo_retarget.sh` to bake the curated local FBX set and export the
145-clip runtime GLB with the visible Mixamo skin. The FBX files remain outside
the Godot project.
