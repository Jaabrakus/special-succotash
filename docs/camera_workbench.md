# Camera workbench

The workbench exists to make camera behavior visible and reproducible without
turning debug values into permanent game rules.

## Controls

- `V`: show or hide the spectator camera and boom visualization.
- `P`: open or close live tuning. Mouse-look pauses while the pointer is free.
- `F9`: begin or end a CSV camera audit.
- `F10`: replay the most recent in-memory audit through the current solver.
- `H`: hide all diagnostics, including the workbench, for clean capture.

## Colors

- Dim blue: backward boom from the player anchor to the unconstrained preferred
  lens position.
- Dim yellow: backward boom to the legal collision/post-solve lens target.
- Dim green: backward boom to the lens position actually rendered after
  continuity filtering.
- Bright cyan: the rendered camera's forward optical ray.
- Bright white: the weapon's forward muzzle-to-aim ray.
- Bright red: the weapon ray is obstructed before the displayed aim point.

The three dim lines visualize camera placement and are not aim directions. Only
compare the two bright forward rays when auditing camera/weapon alignment. The
HUD `Ray audit` value reports their actual angular difference.

## Audit interpretation

`step_m` catches positional snaps. Acceleration and jerk catch a camera that
travels only a short distance but changes speed or direction abruptly. State
transitions identify mode churn. A flip means the state returned from A to B
and back to A within 15 physics frames.

The live sliders alter only the in-memory camera profile. Save preset creates a
timestamped JSON file; it does not silently rewrite the verified defaults.
Always run `tools/run_camera_regression.sh` before promoting a preset.

## Reverting

- `v2.0.5-workbench-base`: exact build before the workbench/state layer.
- `v2.0.5-continuous-wall-transition`: verified continuous wall transition.
- Saved JSON presets and CSV audits live outside the project in the Godot
  user-data `camera_audits` directory shown on screen.
