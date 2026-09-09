# SOCOM II reticle presentation

## Translation card — source inspection

Player intent: replace our approximate reticle shape and unsupported extra effects with source-backed presentation. Acceptance: decode the original rifle, sidearm, shotgun and accuracy images with original palette alpha; inspect their layout before modifying runtime. Owner: existing SocomDynamicReticle; offline extraction does not own game state. Protect camera/reticle aim intent, ballistics/damage, movement, animations, other UI and live game sessions. Proof: strict bounded binary reader, source/decoded hashes, visual inspection, then focused canonical runtime and feature-contract tests for any integration.

The source is HUD2_TXR.ZED and HUD2_PAL.ZED embedded in the local USA ISO's MP51.ZDB. ZDB container and ZED archive are distinct formats. Earlier direct ZED parsing of the container correctly rejected its version. `hud.rdr` is a nested reader containing primarily HUD layout/help text, not the reticle texture payload. Source texture pixels do not establish original on-screen positioning, scale, recovery equations or update order.

## Translation card — canonical presentation integration

- Player intent: see the original weapon-family reticle artwork without an invented second kick/opening effect.
- Acceptance: all 32 source-matched saved weapon profiles select the appropriate rifle/sidearm/shotgun sprites in the existing canonical HUD, with unchanged center, authoritative bloom input, camera VRC and shot results. Unmatched profiles retain the previous renderer. Red hit X and interaction brackets remain.
- One owner: `scripts/ui/socom_dynamic_reticle.gd` owns reticle drawing; its new shared `config/reticle_presentation.json` stores the family mapping and explicitly provisional assembly settings.
- Protected: camera/VRC recovery equations, ballistics, cadence, damage, movement, animation, weapon documents, multiplayer authority, live session, exports.
- Focused proof: decoded pixel hashes, family/region validation, canonical equip and shot integration, rendered family comparison, legacy reticle regression and feature-contract gate.

Decision: MERGE. Source artwork improves verified pixel shape and alpha, not yet verified placement/timing. Current/candidate scores (0–5): correctness 2/3, ownership clarity 5/5, canonical parity 4/5, editor usability 3/4, performance 5/5, regression coverage 3/5. Evidence: existing custom draw/`shot_kick_pixels * 0.22` in `socom_dynamic_reticle.gd`, decoded sprite manifest, new focused regression. Keep the camera and ballistic owners unchanged. No claim of a completed 1:1 port.

The rifle/sidearm `_02` textures each contain a single floating bar, not a full crosshair. The shotgun `_02` contains a quarter-circle. Cropping transparent padding and assembling four rotated pieces is our documented reconstruction. Scale, spacing, color modulation and shotgun radius are editable calibration values, not recovered constants. Original `ret_accuracy` is retained as reference only; the requested red hit X stays active. Scope overlays are not changed.

Timing remains unverified: the existing camera still owns climb, cap and recovery. Source mode removes only the HUD's extra cosmetic bounce and 22% radial impulse; weapon-controlled bloom still opens the reticle. This does not replace spread equations with `TargetMin`/`TargetMax` or prove their units.

Verification lesson: canonical HUD tests must await rendered process frames as well as physics frames. Asset loading can cause several catch-up physics ticks before the HUD sees the new equip profile; a four-physics-tick-only sample failed once for 226 in the rendered test while the headless test passed. The corrected test does not bypass the HUD or manually assign its profile.

Six explicit texture preloads make the runtime artwork dependencies discoverable by scene-filtered exports. A `load()` on a path assembled only from JSON would not establish that dependency. The accuracy reference is not used by the runtime. No browser ZIP was rebuilt in this pass.

The preload check verifies literal source references and loaded `Texture2D` resources, not a completed export. A runtime `ResourceLoader.get_dependencies()` query did not enumerate those paths in the test context and was not used as an export oracle. Package-level validation remains untested.

## Verification — 2026-09-09

- PASS: `tools/socom2_reticle_reference_test.cjs` against the local ISO. Seven image hashes match fresh decoding; floating regions retain every nontransparent pixel; malformed/out-of-bounds containers are rejected.
- PASS: `tools/socom2_reticle_regression.gd`, headless and rendered. Thirty-two canonical equips and accepted shots; family selection, original alpha, unchanged aim center, no secondary impulse, real bloom, switching, interaction, hit feedback. Final headless rerun also checks the six literal preloads.
- PASS: `tools/shared_weapon_reticle_regression.gd`, `tools/vrc_armory_regression.gd`, `tools/ballistic_reference_reticle_regression.gd`, `tools/feature_contract_regression.gd` (109 contracts), `git diff --check`.
- Captures: `/private/tmp/socom2-reticle-families.png`, `/private/tmp/socom2-reticle-main.png`.
- BLOCKED: aggregate quick gate requires branch `main`; current `codex/render-deployment` was preserved. No commit, push, deployment, ZIP rebuild or live-session restart.
- Separate import-scan failures: Blender source assets under `art_source/` failed import; macOS editor settings could not be saved from the sandbox. Those files/settings were not repaired. Focused tests still booted the canonical scene. Voice-input warnings remain; initial headless runs also reported shutdown resource warnings. Final focused run had no assertion or shutdown-resource failure.

Runtime evidence: `scripts/ui/socom_dynamic_reticle.gd::notify_shot` sets `shot_gap_impulse = 0.0` and `shot_bounce_amplitude = 0.0` for source families. `_draw_source_reference` draws the decoded base and four floating pieces. `scripts/runtime/main_gameplay_hud.gd::_update_crosshair` supplies the canonical weapon's saved profile and camera-derived screen position; multiplayer consumes the same renderer through `scripts/network/socom_multiplayer_world_ui.gd::_refresh_player_state`.
