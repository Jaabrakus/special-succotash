# Mark 23 compressed idle — 2026-09-05

## Current handoff after resuming

Core idle/fire/return is implemented in the canonical local project. This is
not a claim that all locomotion is fixed or a release promotion. The user
explicitly likes the current crouch-moving pistol placement; preserve its
`ready_crouched_moving: pistol_idle_kneeling` source, grip and offsets.

Current implementation: the graph reads the evaluated stationary source weight;
the posture owner blends its native hip reference with the existing moving
neutral instead of toggling or weakening pelvis compensation. Same-stance
Mark23 ready crossfades finish before reversing (saved 0.24 seconds, no new
clock). Ready Mark23 skips only the two full-body cosmetic crouch starts/stops;
continuous crouch base still owns legs. Other profiles, reload, mobility and
stance changes are not fenced. The fire hold remains 1.2 seconds.

- PASS rendered canonical core: four standing/crouched neutral/offset cases,
  two reloads; side/rear idle, held fire and returned-idle captures inspected.
  Log `/private/tmp/pistol-resume-rendered-core.log`.
- PASS headless normal forward/backward ready start/stop, both stances, unchanged
  3.5 cm / 6 degree per-frame bounds and 1 cm contact limit.
- PASS forward rapid reversals and crouched backward rapid reversals. All
  firing contacts across the stress runs stay within 1.405 mm.
- FAIL remaining strict backward standing rapid-reversal position check:
  5.0115 cm, limit 3.5 cm; shoulder angle and grips pass. Upper bones translate
  together, without the former shoulder twist. The reconstructed old slot path
  also fails this stress case at 11.434 cm (41.057 cm crouched). This comparison
  swaps handling/graph in memory with the current solver; it is not a full
  historical checkout. Lower-body source edits were deliberately not attempted.
- PASS exact source-weight reader (215 actual animation samples), handoff fence,
  and 20 synthetic hip-reference/rest-space cases. Hip transforms are unchanged.
- PASS recovery exit, pose ownership, gameplay reload and all 24 muzzle-effect
  unit checks. Earlier canonical first-three-draw-frame VFX proof remains the
  historical evidence below; that separate GUI proof was not rerun this pass.
- INCOMPLETE current rendered movement review: capture stopped advancing after
  the first relaxed phase while another game window was active. Only the owned
  test process was terminated; user game/editor were left running. Do not call
  this a rendered movement PASS. Relaxed movement diagnostics also expose
  existing contact/pose issues outside the ready-only acceptance scope.
- BLOCKED broad integration checkpoint: `FAIL: this is codex/render-deployment;
  canonical integration is main`. No branch change, commit or deployment.
- Browser ZIP/PCK are still the earlier 08:40 build, not this resumed fix.
  No fresh browser-server or package claim is made. Relaunching the canonical
  native project loads the current source.

Some isolated test exits report 2–3 ObjectDB instances, also present in the
reconstructed legacy run. This is not evidence of a growing gameplay leak.
The macOS headless CA warning is separate from animation assertions.

Reproduce strict stress proof (the backward standing case intentionally remains
a failure, with no relaxed thresholds):

```sh
/Users/kiwimango/Applications/Godot-4.7.1.app/Contents/MacOS/Godot \
  --headless --fixed-fps 60 --path /Users/kiwimango/Documents/SOCOM-141 \
  --script res://tools/pistol_compressed_movement_visual_probe.gd \
  --log-file /private/tmp/pistol-backward-stress.log \
  -- --enforce --backward --rapid-reversals
```

## Translation card (before runtime edit)

- Player intent: keep the accepted squared firing shape; in standing/crouched
  idle retract the hands toward the chest with the pistol still forward. Fire
  extends that same shape, holds for the existing 1.2 seconds, then retracts.
- Acceptance: distinct live saved idle/ready clips; centered, closer hands;
  physical grips stay connected; no head/shoulder pop on entry or return;
  existing reload and fire ownership survive. First-shot local muzzle effects
  use the displayed muzzle, without changing the authoritative shot.
- One pose owner: the existing operator AnimationTree/post-animation pipeline.
  Existing pooled tracer presentation owns its optional local emitter tracking.
- Must not change: camera/reticle, CharacterBody3D movement/collision, shot and
  damage authority, timer length, reload, weapon dimensions/sockets, other guns.
- Focused proof: `pistol_compressed_idle_regression.gd`,
  `pistol_presented_muzzle_effect_regression.gd`, existing ready-slot/recovery
  tests, feature-contract gate, canonical rendered idle/fire/full-return check.

## Evidence and system delta

Baseline executable test reproduces 19 cm standing / 10 cm crouched lateral
idle error and 9–14 cm upper-body entry jumps. `mark_23.json` previously mapped
idle and ready to the same old Mixamo pose; driver runtime suppressed old
procedural corrections only during readiness, then restored them in idle.

Decision: MERGE native upper-body assets into existing saved slots and keep the
authored stationary baseline free of those additional idle corrections. Do not
replace the movement graph, add a skeleton writer, or increase IK limits.

Scores (0–5): correctness 2→4, ownership clarity 5→5, canonical parity 3→5,
editor usability 3→4, performance 5→5, regression coverage 2→5. Evidence:
`config/weapons/mark_23.json`, `operator_animation_driver_runtime.gd`,
`operator_animation_driver_api.gd`, `bake_pistol_compressed_idle.gd`, and the
focused regressions above. Candidate scores are provisional until tests and
rendered checks pass; source-capture success alone is not integration proof.

The baker preserves original lower-body tracks and derives both arm endpoints
from the same accepted recovery frame. Mark 23 alone opts into the new idle
baseline and displayed-muzzle effects. The fire latch still decides recovery;
its bounded blend is presentation, not an alternative fire state or timer.

## Implementation

### Resumed movement-handoff correction card

- Intent: preserve the accepted stationary pair without a shoulder/head snap
  when movement begins or stops during recovery.
- Acceptance: remove the reproduced 12–23 cm single-frame upper-body jumps;
  keep both grip contacts within 1 cm and retain stationary/reload proofs.
- Owner: existing AnimationTree/posture coordinator only. Blend the suppression
  of baked corrections through the same route transition, not an extra IK pass.
- Protected: movement/collision, camera, shot authority, 1.2-second latch,
  weapon geometry, other profiles and lower-body clips remain unchanged.
- Proof: physical movement probe, stationary pose regression, reload/ownership
  checks and rendered transition review. Source-routing checks alone missed this.

New-information delta: the earlier candidate fails moving recovery boundaries
because `authored_idle_baseline` flips before the graph finishes crossfading.
REPLACE that binary correction suppression with continuous presentation weight
in the same owner. Scores pending proof: correctness 2→4, ownership 5→5,
runtime parity 5→5, editor usability 4→4, performance 5→5, coverage 3→5.
Evidence: `operator_animation_driver_runtime.gd`, `operator_posture_layer.gd`,
`pistol_compressed_movement_visual_probe.gd`. The prior package is not accepted
as fully movement-verified. The temporary pre-turn backup no longer exists after
interruption; a fresh source checkpoint was made before this correction.

Follow-up delta from physical tests: exact source weighting fixes standing
recovery, but applying it to relaxed cleanup regresses standing stop. Keep the
previous relaxed policy and weight only ready/recovery corrections. Crouch
start/stop are cosmetic full-body rifle clips with no pistol ready upper layer;
their action gate also disables the accepted posture immediately. MERGE the
existing filtered aim-frame/arm graph pattern for Mark23 crouch start/stop only.
The same clips still own hips/legs and keep their duration/phase; at readiness
zero the new filters contribute zero. Preserve clean-ready posture through
those cosmetic actions, never through reload, grenade or mobility. Same owner,
protected systems and tests as above; include source-filter proof and enforce
physical firing boundaries. No other weapon opts into this change.

Rapid-reversal result: REJECT that crouch-overlay candidate. Its torso filters
cannot remove the full-body crouch-stop clip's 31 cm pelvis-height restart.
The smaller replacement keeps Mark23 ready/recovery on continuous crouch
locomotion instead of those two cosmetic start/stop actions. Idle/standing and
idle_crouch/crouch base crossfades finish before accepting a reverse request;
the next driver pass submits the latest intent, with no queue or extra clock.
The saved Mark23 presentation blend is 0.24 seconds. Reload, mobility, stance
changes and every other profile bypass the fence. This changes only Mark23
presentation routing during readiness; CharacterBody3D decisions/speeds stay
unchanged. Existing lower-body base clips and their playheads are retained.
Re-run unchanged firing limits, rapid reversals, stationary/reload and actual
rendered checks. Candidate scores stay provisional until those pass.

Final fractional-blend correction: fading the whole pelvis correction by
`1 - native_weight` also leaves that fraction of the moving pelvis turn in the
upper body. Instead, the existing posture owner caches the fully native hip
reference and blends its target hip frame with the existing moving neutral.
It then applies the ordinary separation weight toward that blended reference.
At native weight one the correction is identity; at zero it is the unchanged
moving correction. This removes double-baking without retaining stray gait
rotation in the mixed pose. No body translation, IK limit, input response or
test threshold changes are permitted. Re-run rapid reversal and core proofs.

The saved Mark 23 slots in `config/weapons/mark_23.json:89` now contain:

```json
"idle_standing": "pistol_compressed_idle_standing",
"ready_standing": "pistol_recovery_reference_standing"
```

Crouched has its own equivalent pair. The saved `fire_hold_seconds` remains
1.2. `compressed_enter_response: 8.0` applies only to this stationary pair;
the accepted-shot muzzle correction is immediate while the arms extend.
Existing moving/start-stop/jump upper sources are separately preserved in the
optional `*_moving` slots; absent/unavailable slots retain prior fallbacks.

`operator_animation_driver_runtime.gd:183` suppresses the old idle corrections
for the authored stationary baseline. It also skips the already-baked
pelvis-to-spine compensation and shoulder squaring. No extra skeleton owner is
added. `align_pistol_compressed_wrist.gd` bakes the missing mounted-wrist
orientation into the four resources without changing weapon sockets or scale.

## Earlier verification before interruption — superseded by current handoff above

- PASS native asset reload: physical bore and roll below 0.0001 degrees;
  upper-body frame unchanged; lower-body tracks preserved.
- PASS `pistol_compressed_idle_regression.gd`: 4 standing/crouched neutral and
  offset-aim cases, both reload transactions. Display-backed run also passes;
  side/rear idle, firing and complete-return images inspected. Largest measured
  offset head/shoulder step was 8.14 mm / 4.563 degrees in that rendered run.
  Both contacts stay within the unchanged 1 cm bound. There is no fire OneShot.
- PASS `pistol_recovery_exit_regression.gd`: settled held pose, dimensions and
  terminal return. Fixture now waits for blended readiness instead of requiring
  immediate weight 1.0; physical tolerances are unchanged.
- PASS `pistol_compressed_movement_source_regression.gd`: explicit, absent and
  unavailable overrides; original moving/action sources; move/fire/stop routing.
- PASS distinct-ready-slots, pose-ownership and gameplay-reload-completion gates.
- PASS `pistol_presented_muzzle_effect_regression.gd`: 24 isolated checks,
  including pool reuse, opt-out, expiration and deleted scene/weapon handling.
- PASS `pistol_canonical_muzzle_effect_visual_check.gd`: actual canonical
  accepted shot and first three rendered frames, no manually invoked sync.
  Active flash/emitter position error is zero; shot/tracer snapshots unchanged.
  Emitted smoke stays world-space rather than following the pistol rigidly.
- PASS feature manifest gate: 36 contracts; scoped whitespace check.
- PASS animation-cache rebuild: 92 animations, fingerprint
  `9991823cd414b4cf26a254f5f9c8de1e1f8c9bae8e1de1fa7ec5472f6c0b4247`.
- PASS restricted browser export and checksums. The 76,028,142-byte ZIP is
  `builds/SOCOM-141-browser-tournament.zip`; localhost port 8060 returns HTTP 200
  for the new 70,946,468-byte PCK. Proof images/raw authoring references are
  excluded from this export. This is package delivery, not a new multiplayer
  connectivity test or a claim that every weapon was changed.
- NOT RUN beyond its branch guard: `tools/run_integration_gate.sh quick`
  returns `FAIL: this is codex/render-deployment; canonical integration is main`.
  The branch and dirty worktree were preserved. No commit or deployment.

The export completed with macOS sandbox editor-settings-save/ADB warnings and
pre-existing duplicate/reference warnings, but no GDScript parse failure. An
initial sandboxed localhost request could not connect; the same read-only check
outside that restriction returned HTTP 200 with the matching PCK size/date.

Capture-fixture lesson: PNG encoding and a stale review-camera readback caused
a misleading variable-delta visual failure. Capture after real pre/post-draw
signals, then drain normal frames before measuring the next shot. Do not relax
pose tolerances to compensate for screenshot I/O.

Official API references used: Godot Skeleton3D global poses are skeleton-space;
AnimationTree owns clip blending; RenderingServer frame_pre_draw/frame_post_draw
bracket the rendered pose; CPUParticles3D local_coords=false preserves emitted
particles in world space. Validated against installed Godot 4.7.1.
