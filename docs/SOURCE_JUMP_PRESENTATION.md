# Source jump presentation

## Moving jump revision

Player intent: use the decoded SOCOM II running jump, not a partial launch followed by standing air. Acceptance: moving jumps select the copied running launch, running air and matched landing through the canonical driver; standing jumps remain unchanged. Owner: SocomOperatorAnimationDriver. Protect physics, camera, weapons, networking and traversal rules. Focused proof: provenance/rotation samples, phase seams and canonical AK/M4/Mark23 renders.

The project has no separate sprint command. Moving takeoff copies `seal_runningjump_launch` via `jump_up.tres` at source seconds 0–0.8 into `jump_coherent_run.tres`. Descent copies `seal_runningjump_in_air` via `jump_loop.tres` at 0–0.43333333 into `jump_running_air.tres`. Its first 20% blends from the launch endpoint. `jump_running_land.tres` copies `seal_land_soft` at 0–0.6, blending its first half from running air. Closure samples are excluded. Standing takeoff/air/landing remain separate, including pistols. Both saved animation maps match. Original source takes, body trajectory and grip owner remain unchanged. This is adapted source motion, not exact original timing.

REPLACE the partial running/standing-air mix. Scores correctness/ownership/runtime parity/editor usability/performance/coverage: previous 2/5/5/4/4/3, copied running sequence 4/5/5/4/4/5. Evidence: builder source windows, timeline's latched running route, both saved maps and source-jump regression.

Verification: `source_jump_regression` and all 121 feature contracts pass. Canonical rendered AK/M4/Mark23 standing/running fixture passes (`/private/tmp/running-copy-visual.json`); sampled running side poses were inspected. An initial rotation-copy assertion compared unnormalized interpolated quaternions and failed; comparing normalized saved keys to normalized source samples passes without changing assets or tolerance. Original-game timing parity remains unverified. Browser ZIP was not rebuilt. Aggregate integration is still blocked by the main-only gate on `codex/render-deployment`.

## Coherent source copy — September 11

Player intent: replace the visibly mismatched running launch/air/landing poses,
not only fix jump input or hip translation. Owner: existing animation driver.
Protect movement, aim, weapons, climb controls and networking. Proof: copied
phase seams, main-scene standing/running AK/M4/Mark23 renders and grip checks.

`tools/build_coherent_source_jump.gd` copies decoded `seal_jump` through the
existing `jump_up_standing.tres`: takeoff 0.23333333–0.4s, air 0.4–0.6333333s.
This earlier revision used those segments for both routes; the moving revision above supersedes it. Standing landing copies `seal_land_soft` 0–0.6s and blends its first half from
the preceding air endpoint. Originals remain untouched. Generated assets keep
source provenance and non-looping metadata; otherwise the loader's looping
hip-yaw sanitizer would change the seam. Body physics still drives normalized
phase time. This is an adapted source copy, not original SOCOM timing parity.

REPLACE phase assets: old mixed source phases score 2/5/5/4/4/3 for correctness,
ownership, runtime parity, editor usability, performance and regression coverage.
Contiguous copied phases with tested rotation seams score 4/5/5/4/4/5. Evidence:
the builder, both saved animation maps and `tools/source_jump_regression.gd`.
Existing takeoff hip anchor and support-hand contact policy remain in place.

## Translation card

Player intent: a coherent takeoff, airborne and landing sequence with a stable held weapon, without manual clip debugging. Acceptance: one takeoff selection per jump; source playheads follow the actual airborne/landing phases rather than clipping a long take at a velocity threshold; no artificial closing-frame rewind; no support arm stretching or ownership pop during main AK/M4/pistol jump entry and recovery. Animation remains presentation only. Owner: existing SocomOperatorAnimationDriver and its AnimationTree/weapon presentation pass. Protect CharacterBody trajectory/collision and recovery permissions, camera/reticle, server shots/damage, networking, standing ready/fire, normal pistol hybrid, dive/roll/reload/grenade. Proof: focused main-scene jump probe, timeline regression, existing ready/fire/pistol/mobility regressions and feature contract gate. No user game restart or browser export.

## System delta — investigate, then MERGE only with proof

Current code: operator_animation_driver_pose.gd selects takeoff while vertical_speed > 1, reevaluating running versus standing every frame. player_controller.gd supplies jump velocity 5, gravity 22, and landing recovery 0.18s. Source launch is 0.833s and landing 0.667s. Native source clips include a final loop-closing sample. Jump arms still enter the ordinary weapon contact strategy; this must be measured before changing ownership.

Scores correctness/ownership/runtime parity/editor usability/performance/coverage: current 2/4/5/3/5/2; candidate phase-bound presentation 4/5/5/4/5/4, contingent on focused proof. Candidate consumes saved presentation metadata and existing movement state, never drives physics. Exact original SOCOM gameplay timing is not recovered and is not claimed.

## Implementation and measured findings

The baseline main fixture kept contacts within 2 mm; a detached support hand was not reproduced. Code did reveal the standing ready-arm overlay on jump_up/jump_loop/jump_down during accepted-shot grace. Source-configured jump nodes now keep their native torso/arms and retain the existing source-aware contact pass; no extra hand solver or relaxed grip was added. Other action owners are unchanged.

`source_jump` in the main map and hybrid preset supplies end times one 30 Hz sample before each decoded closure, plus a 0.055s crossfade. The raw animation assets are untouched. `operator_source_jump_timeline.gd` derives ascent/descent progress from existing vertical speed and launch speed, and landing progress from existing action elapsed/duration. Steering cannot reselect takeoff; falling from a ledge does not play launch. `AnimationNodeTimeSeek` publishes to the existing AnimationTree. `AnimationNodeAnimation` custom timelines clamp outgoing playback before the closure. The profile loader clears the optional section on reload, so legacy presets remain opt-in.

Godot API references: https://docs.godotengine.org/en/latest/classes/class_animationnodetimeseek.html and https://docs.godotengine.org/en/latest/classes/class_animationnodeanimation.html . Latest docs warn of unstable APIs; exercised against installed 4.7.1. TimeSeek resets its request after evaluation. Saved frame-pose keys read the evaluated playhead rather than the next queued request.

Main headless before/after fixture recorded identical body heights and velocities over all 390 sampled frames, six standing/running AK/M4/Mark23 jumps. Unit checks verify phase projection at 30/60/144 samples/sec, ledge entry, steering latch, closure samples, equip rebuild, and absence of standing-ready overlays. Separate accepted-shot jump run passed physical palm and bone-length checks. Its initial immediate exit emitted ObjectDB/resource cleanup warnings; fixture teardown now waits for transient effects and deferred scene deletion. Rendered proof and final regression results follow below.

Rendered finding: despite contact passing, the decoded jump wrist could fold over the handguard. The existing pose owner now caches the last solved grounded, weapon-relative support-wrist basis and holds that orientation during source jump/landing; the usual arm IK retains palm contact. Cache resets on bind/re-equip. Source transition weight releases the hold into ordinary rifle locomotion. This is a target-orientation policy inside the same solver, not an additional bone writer.

Rejected variant: delaying the legacy pistol upper-body return until the jump crossfade finished caused a 0.171m support gap on Mark23 running/accepted-shot landing recovery at frame45 (target span .819m versus .648m arm). Retain the already verified pistol layer handoff instead. Scope stays presentation; no bone length or physics changes. Exit resource warnings persisted after delayed fixture teardown; they are not counted as failed contact/timing checks or claimed fixed.

## Final verification — 2026-09-09

Final headless standing/running AK-47, M4A1 and Mark 23 checks passed both without firing and with an accepted shot before jumping: `/private/tmp/source-jump-grip2-idle.json` and `/private/tmp/source-jump-grip2.json`. All 390 baseline/updated idle samples retained identical player height and vertical velocity. Palm gaps stayed below 2 mm; held support-wrist entry error stayed below 0.04 degrees. This verifies contact and phase behavior in the tested cases, not every weapon or exact original-game timing.

Separate rendered canonical-main proof passed six firing-entry cases, capturing 36 poses from rear and side (72 images): `/private/tmp/source-jump-final-render.json`, `/private/tmp/source-jump-final-render-timeline.json`, and `/private/tmp/source-jump-final-render.log`. Selected takeoff, airborne, landing and recovery images were inspected. No final rendered-run resource cleanup warning was emitted; earlier warning observations above remain part of the investigation record.

`source_jump_regression`, `source_ready_fire_regression`, pistol hybrid (nine pistols), mobility fire lock, and all 105 feature contracts passed. Logs: `/private/tmp/source-jump-final-unit.log`, `/private/tmp/source-jump-final-ready.log`, `/private/tmp/source-jump-final-pistol.log`, `/private/tmp/source-jump-mobility.log`, and `/private/tmp/source-jump-final-contract.log`. Headless runs still emit the environment's macOS certificate-store warning. The aggregate `tools/run_integration_gate.sh quick` is blocked by its main-branch requirement: this checkout is `codex/render-deployment`. No branch change, push, browser ZIP rebuild, or restart of the user's game was performed. Exact original SOCOM controller timing and broader skin/finger fidelity remain unverified.
