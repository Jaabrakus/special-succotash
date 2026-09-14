# Source gameplay camera integration card

## Translation card — 2026-09-13

- Player intent: use the verified original ordinary third-person camera framing and lens through the playable game's existing camera.
- Acceptance: source state-2 preferred-pose equations reproduce bounded original-instruction fixtures; the horizontal lens is 70 degrees at every viewport aspect; canonical main remains the sole camera/aim writer and retains physical collision validation. Render standing/crouch/prone and signed pitch cases before claiming visual parity.
- Owner: `SocomCameraRig`; `SourceGameplayCamera` is a pure policy/anchor reader, never a node or transform writer.
- Saved contract: `config/camera_source_match.json`, consumed by the canonical FOV seam only. Source position and aim-point integration remain inactive pending the independent source root; the pure solver is not represented as integrated.
- Must not change: movement/collision ownership, character scale/assets, weapon/damage/server authority, user input angles, unrelated profiles or running user game.
- Focused proof: `tools/source_camera_runtime_audit.cjs`, `tools/source_gameplay_camera_regression.gd`, `tools/main_source_gameplay_camera_regression.gd`, feature-contract gate and rendered main samples.
- Boundary: original collision, trailing, lean filter, special states and zoom have not been ported. Current safety/trailing remain explicit adaptations. Source `skel_root` is independently animated and is absent from the canonical skeleton; source-root reconstruction must not be claimed from its child hips.
- Bounded UI seam: camera workbench labels the source-fixed horizontal lens instead of offering an ineffective authored-vertical slider. It does not change the saved source policy or camera ownership.
- Narrowed candidate: lens only, then REJECTED default activation after native rendered framing failed. Both default lens and position remain authored (`enabled=false`, `preferred_position_enabled=false`). Explicit candidate uses `--source-camera-match`. It removes authored close-wall FOV widening but preserves physical collision recovery.

## System delta

MERGE verified state-2 scalar math and opt-in 70-degree horizontal lens plumbing. REJECT default lens activation because the old preferred position with the new lens crops the skinned character. KEEP one camera owner, existing default lens/position and collision safety. Do not claim full original camera parity or confuse the five preset records with algorithm state 2.

| Dimension (0–5) | Current authored preference | Source-backed policy |
| --- | ---: | ---: |
| Correctness against original clear-path math | 1 | 5 for verified math; anchor integration must be separately classified |
| Ownership clarity | 5 | 5 |
| Canonical runtime parity | 5 | pending main proof |
| Editor usability | 4 | 4 (saved JSON) |
| Performance | 5 | 5 (cached settings/skeleton lookup, constant-time pose read) |
| Regression coverage | 4 | pending focused and main proof |

Code evidence: `scripts/camera/camera_preferred_shot_solver.gd` currently adds an authored 1.05m anchor and 2.05m preferred height; `tools/import_seal_reference_animations.gd` maps source hips but not its independently animated `skel_root` ancestor. Original `FTSCore:0x29a950` derives the default camera from that ancestor; original `0x319268 -> 0x291490` establishes the 70-degree horizontal lens.
