# AGLS traversal intake

This pipeline reads AGLS without modifying its Unreal project. It catalogs
traversal assets, exports only bounded batches of animation sequences, and
records progress so interrupted runs can resume safely.

The Godot `CharacterBody3D` remains authoritative for travel and collision.
Exported FBX clips use the `visual_only` root-motion policy and enter the
existing SOCOM animation retarget service after export.

Traversal families: `swimming`, `climbing`, `ladder`, `rope`, `zipline`,
`mantle_vault`, `narrow_ledge`, and `wheel_valve`.

Combat and ground-movement families: `weapon_hold`, `weapon_reload`, `weapon_recoil`,
`weapon_equip`, `weapon_pickup`, `locomotion_idle`, `locomotion_walk`,
`locomotion_run`, `locomotion_turn`, `locomotion_crouch`,
`locomotion_crawl`, `locomotion_air`, `locomotion_roll`,
`locomotion_additive`, and `grenade`.

`weapon_hold` preserves the native AGLS rifle pose sets plus standing,
crouched, and crawl aim sweeps. SOCOM owns when the weapon becomes ready;
these clips own only the visible torso, shoulder, arm, and hand pose.

`run_export_batch.sh` defaults to four swimming clips and refuses to start
below 4 GiB free disk space. Unreal runs headless with NullRHI so the full
editor and game are never open together.

`import_fbx_batch.sh` uses a disposable Godot project so importing new AGLS
clips cannot trigger reimports of unrelated Blender workbench files. It
publishes self-contained `.scn` animation scenes under `imported/<family>`.

`export_workbench.sh` exports the workbench static mesh and four source
textures without saving or modifying the Unreal assets. The Blender builder
packages those files as an editable `.blend` and emits a Godot-ready `.glb`.
Unreal Blueprint behavior is not embedded in the art file; interaction logic
belongs to the Godot runtime.
