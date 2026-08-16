# reCOM zCamera audit

Reference reviewed: `NotEnoughPhotons/reCOM`, `src/gamez/zCamera`, main branch
at the local audit date of 2026-08-16.

## What the source establishes

- The application camera has an explicit `cam_mode_tether` state.
- Camera placement is represented by a camera aim point, a camera tie point,
  a goal position/offset, a goal tether length, and a short-tether timer.
- Camera offsets and aim points are loaded from character-dynamics camera
  parameters and transformed through the controlled entity's matrix.
- The module exposes a tether-intersection flag and saved short-tether length.
- Camera/network mode is separate from the local tether mode.

These are strong architectural clues for a player-relative desired shot whose
tether shortens when geometry intervenes. They do not support retaining an
unbounded world-space wall camera after the player has moved away.

## What the source does not establish

The current reverse-engineered bodies for `APTeatherCam`, `LookAt`, first-person
placement, transition logic, and several camera commands are empty. Therefore
the repository does not currently reveal the original collision candidate set,
smoothing constants, indoor logic, or exact SOCOM 2 framing algorithm. It cannot
be translated one-to-one into GDScript yet.

No clear reusable software license was present in the audited checkout, and the
README describes reverse-engineered work with an all-rights-reserved disclaimer.
The SOCOM-141 implementation therefore uses only high-level architectural facts
and original Godot code; it does not copy literal reCOM implementation code.

## Godot mapping

- `m_cameraTie` / player entity transform: current player-relative camera anchor.
- `m_camGoalPos` / `m_goal_t_len`: preferred virtual boom and profile distance.
- short tether/intersection state: Godot volume cast plus legal compressed boom.
- camera aim: local yaw/pitch intent, independent from collision placement.
- camera mode separation: camera recovery remains local; only validated aim
  intent is eligible for server submission.

The added world-distance tether and screen-space tether are safety invariants
around that model. They ensure smoothing cannot preserve an obsolete wall-side
lens when the controlled player has already left it.
