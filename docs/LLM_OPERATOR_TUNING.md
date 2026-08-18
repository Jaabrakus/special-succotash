# LLM operator tuning contract

An LLM may edit two data files. It must not edit camera, collision, networking,
weapon authority, skeleton poses, or animation-controller code for a tuning task.

- `config/operator_movement_tuning.json` controls speeds, state blending, the
  torso-to-legs handoff, mobility timing, operator scale, and optional adaptive
  intent cadence.
- `config/operator_animation_map.json` maps logical gameplay slots to imported
  FBX resources. Empty obstacle slots are allowed until that gameplay exists.

After editing, run `tools/run_operator_config_validation.sh`. The edit is valid
only when it prints `OPERATOR_CONFIG_VALIDATION PASS`. In the running lab, press
F5 and choose `Reload movement tuning JSON` to apply movement/animation timing
edits without changing gameplay code. Animation clip-map edits are applied on
the next project launch so imported resources remain deterministic.

## Adaptive operator boundary

A small model may produce low-frequency intent only:

- `attention_target`
- `desired_stance`
- `movement_style`
- `cover_side`
- `urgency`
- `look_interest`

The model must never write bone rotations, camera transforms, collision results,
shot destinations, damage, or replicated authority. One intent planner may run
per NPC, or one shared model may batch many NPCs. The deterministic animation
state machine, IK solvers, physics, and server remain authoritative.

This hierarchy allows adaptive behavior without creating unstable anatomy or
different multiplayer outcomes on different clients.
