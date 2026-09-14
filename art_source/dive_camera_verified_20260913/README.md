# Dive camera proof

Generated through `main.tscn` by `tools/main_dive_camera_regression.gd` using queued movement/dive commands from standing and crouched approach, at level and signed aim pitch. The floor is an in-memory controlled fixture; the real character, movement owner, AnimationTree, weapon and camera pipeline remain active.

`before.json` reproduces the discarded upright camera-root closing frame. `after-headless.json` verifies the corrected retained frame. Rendered early/middle/late/settled frames and `measurements.json` come from the native run when complete. No exported browser ZIP or running user game is updated by these proofs.

This covers ordinary Z/dive, not every directional AGLS combo or wall/terrain interaction. Refer to `docs/DIVE_CAMERA_TIMING_FIX.md` for scope, exact changes and test results.
