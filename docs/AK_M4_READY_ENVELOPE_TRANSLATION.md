# AK/M4 A, near-A and stop readiness envelope

## Translation card

1. Player intent: Both hands stay naturally attached while the player enters left strafe, changes direction or stops firing/moving; no folded trigger elbow or transient support-arm collapse.
2. Acceptance: Canonical AK/M4 standing/crouch transitions and the strict stock regression pass the unchanged 5 mm palm /0.5 degree bore /42–150 degree elbow limits. Previously approved full-D chest-forward carry stays unchanged. A failing test fixture must be diagnosed from its actual state, never bypassed by relaxing limits.
3. Owner: Existing authored weapon-presentation owner and its existing socket-arm solver; no independent pose or transform writer.
4. Protected: Camera/reticle, movement/collision, shots/damage/networking, 1.2-second recovery, grip socket positions, bone lengths, anatomical limits, D chest-forward 0.33 m, other weapon families and asset mappings.
5. Proof: `tools/rifle_right_carry_release_regression.gd`, `tools/rifle_shoulder_stock_regression.gd`, existing native A/D front/side review, and the feature-contract regression.

## Initial evidence and candidate boundaries

Current M4 canonical A-fire reports trigger elbows around 36 degrees and up to 9.56 mm palm error. The first stopped frame exposes support elbows around 39.54 degrees M4 /41.16 degrees AK. These cases have zero right-stock release. Additional IK iterations can improve numerical residual but cannot change the angle implied by a fixed wrist target and fixed arm lengths.

Measure the current authored wrist basis, existing calibrated basis, arbitrary-orientation reach envelope and actual fixture torso/aim orientation before editing the solver. Any candidate must preserve the existing grip positions and natural grip orientation. Do not add a new shoulder/weapon owner, stretch bones, silently move sockets or lower the elbow threshold. If a constrained pose is mathematically infeasible, report the exact conflicting contracts and the smallest required authorization rather than force a false pass.

## Six-axis system delta (0–5)

| Axis | Current | Bounded correction candidate | Evidence |
| --- | ---: | ---: | --- |
| Correctness | 2 | 3 provisional | Recorded A/stop contact and angle failures; live reach comparison required |
| Ownership clarity | 5 | 5 | Same authored-stock and socket-arm owner |
| Canonical runtime parity | 5 | 5 | Actual main scene, saved rifle contracts and real inputs |
| Editor usability | 4 | 4 | Existing saved grip/pose contracts, no hidden preview overrides |
| Performance | 4 | 4 | Reuse bounded existing solve; no parallel pose system |
| Regression coverage | 4 | 4 | Keep both strict and input-driven gates, including failing edge cases |

Decision: **MERGE only a measured improvement**. This card authorizes inspection and the smallest existing-owner correction; it does not assert that a wrist, shoulder or pocket change is safe before the evidence is available.

## Authorized shoulder-pocket calibration candidate

Intent: A/idle shouldered carry must fit the same real hands and elbow limits. Acceptance: a small downward/inward offset may reposition the existing A pocket inside the visible high right shoulder; it must not create a forward-floating stock. Camera, square shoulders, local sockets and arm lengths remain unchanged. Owner: the existing stock constraint computes the pocket; authored stock presentation blends the correction out with the same final right-turn weight so approved full-D geometry is exactly preserved. Proof: actual A/stop contact, physical pocket position, both strict gates and native shoulder close-ups.

First measure downward/inward target-vector bounds and wrist-basis alternatives. A candidate exceeding a realistic shoulder region must stop for review. Use a saved constant and existing turn/readiness weight, never an expensive per-frame orientation search. Delta: correctness 2 -> 3 provisional; ownership 5 -> 5; parity 5 -> 5; editor usability 4 -> 4; performance 4 -> 4; coverage 4 -> 4. Decision **MERGE only after measured fit**, with a visible high-shoulder stock requirement retained.

Measured M4 A wrist target is approximately 4.8 cm inward, 6.6 cm down and 18.5 cm forward from the shoulder. Downward-only requires 6.78 cm to reach the existing minimum. Additional inward correction improves A but shortens the stopped support-arm radius. No single ±30-degree local wrist rotation reaches the minimum by itself; −15 degrees local roll increases the radius from approximately 0.201 to 0.212 m.

First saved candidate: `dynamic_hold.ready_shoulder_pocket.downward_m = 0.055`, `right_wrist_roll_degrees = -15.0`. The existing stock constraint owns its pocket marker; it accepts this bounded world offset before the authored owner blends the mount. Right wrist basis gets only the complementary readiness-weighted local roll. Both corrections fade with `1 - final_right_turn_weight`, leaving full-D geometry exact and other profiles at zero. Preserve v8; create provisional v9 with only this two-value object added. Compare native appearance with a simpler 0.07 m downward /0-degree wrist alternative; prefer natural appearance and lower complexity, not numerical pass alone.

Both candidates clear the actual canonical angle envelope and the AK transition gate. M4 keeps a numerical trigger-palm residual with the helper's three correction passes: 10.44 mm for 5.5 cm/−15 degrees, 13.60 mm for 7 cm/no wrist roll. Reuse the existing socket solver's eight-pass maximum on this scoped right-hand call, preserving its 1 mm early exit; no new solver/search/target writer. The simpler 7 cm/no-roll candidate is tested first. This is an accuracy correction after proving feasible geometry, not permission to move a grip or weaken contact assertions. Performance remains bounded by the existing eight-pass implementation, while full-D normally exits before the old limit.

## Fresh-shot system delta: align at the existing trigger contact before seating

Expanded actual-input proof confirms the strict gate was exposing a real early-entry defect, not a fixture-yaw error. At readiness 0.330 the AK stationary support wrist target exceeds total arm length (137.6 mm palm error); M4 error is 91.8 mm. The stock helper blended the still-unrotated low-ready stock toward the shoulder, then instantly aimed about that offset stock. This swings both sockets around the wrong early-entry pivot.

Candidate: within the same presentation owner, align the rigid rifle about its existing authored trigger contact first, recompute that aligned stock, then blend the aligned stock to the calibrated pocket using the same readiness. Return uses the same aim blend so the zero-readiness authored mount remains continuous. Fixed palm sockets, accepted-shot aim guarantee, full-ready A/D position and all other owners remain unchanged. Acceptance adds fresh idle/A shots and A-stop to the unchanged physical gate. Delta: correctness 2 -> 4 provisional; ownership 5 -> 5; parity 5 -> 5; editor usability 4 -> 4; performance 4 -> 4 (bounded existing rigid rotations); coverage 4 -> 5. Decision MERGE only after the fresh-entry proof.

The first trigger-aligned run removed all strict-gate palm failures. Preserve the original capped pocket target before aligning, because applying the correction cap to the newly aligned stock would change full-D's target. A second gait phase exposed a stopped support elbow of 41.89 degrees with a measured 1.23 mm downward reach deficit. The next shared pocket candidate is 0.06 m down /−15 degrees wrist roll, providing a small geometric margin rather than loosening the 42-degree limit. Full-D uses zero complementary pocket adjustment and the exact original target.

At 6 cm the strict gate passes and the expanded actual-input suite has only two finite convergence misses: M4 trigger 5.181 mm at 44.10 degrees and AK support 5.131 mm at 45.18 degrees. Use the existing eight correction-pass limit for support as well. For the compact trigger chain only, permit 64 instead of 40 existing FABRIK iterations during this helper call and immediately restore the previous budget. This does not affect reload/prone/other weapons, move a target or replace the solver. The existing distance-based early exit remains. Six-axis delta: correctness 3 -> 4 provisional, ownership/parity/editor/coverage unchanged, performance 4 -> 3 due to a bounded worst-case convergence increase; accept only if physical closure materially improves without visual distortion.

Decision **REJECT** the 64-iteration candidate: its M4 result is bit-for-bit identical to 40 (5.181176 mm on the same transition frame), with no correctness benefit. Restored the original 40-iteration budget. The support eight-pass change removes AK's actual transition failures and the strict stock suite remains passing. Inspect outer-loop residual convergence before any further runtime change.

Keep the existing IK stack unchanged. The final M4 miss occurs at the compressed near-A frame (44.10-degree actual trigger elbow). A 5 mm additional shoulder-pocket shift (0.065 m total, still below the authorized 0.07 m comparison bound) tests a larger anatomical margin with the same −15-degree wrist rather than raising solver budgets. Add optional test-only gait phase offsets and report all failures and minimum angles; a single fortunate phase is not acceptance.

## Final headless physical acceptance

Saved v9 candidate: `ready_shoulder_pocket = {downward_m: 0.065, right_wrist_roll_degrees: -15}`. Both sides use the existing eight outer correction passes with 1 mm early exit; internal FABRIK budget remains the original 40. No generic socket helper, socket positions, bone lengths, camera, movement, damage or networking code changed.

Actual main-scene input suites passed at gait-phase offsets 0, 13 and 29 for both AK/M4: 4,536 measured rows, including relaxed idle shot, relaxed A shot, A-stop, D-to-A, A-to-D and D-stop/recovery. AK worst palm 1.165 mm; M4 4.442 mm. Fully-ready elbow minima: AK left 43.846/right 58.729 degrees, M4 left 42.583/right 44.107 degrees. No stock, bore, release, scope or joint-limit failures. Final `rifle_shoulder_stock_regression.gd` passes unchanged, and all 83 feature contracts pass. Native appearance review remains a separate requirement; these figures do not claim all weapons or 32-player load acceptance.

Reproducible runs: `--headless --fixed-fps 60 --path /Users/kiwimango/Documents/SOCOM-141 --script res://tools/rifle_right_carry_release_regression.gd -- --weapon=m4a1 --output-prefix=/private/tmp/pocket65-m4 --phase-offset=0`, repeated for `ak-47` and offsets 13/29. Reports `/private/tmp/pocket65-{m4,ak}{,-phase13,-phase29}.json`; strict log `/private/tmp/pocket65-stock-output.log`.

The exact [Godot 4.7.1 SkeletonIK implementation](https://raw.githubusercontent.com/godotengine/godot/4.7.1-stable/scene/3d/skeleton_ik_3d.cpp) confirms that its inner iteration loop also has a fixed local-space progress cutoff and its task budget is copied on chain reload. This supports rejecting a per-frame budget tweak/rebuild; this feature retains the established solver and bounded outer correction instead.

### Bounded CPU comparison

An isolated, process-only instrumented copy of the same canonical M4 input sequence compared the prior three outer correction passes with the final eight-pass maximum. No saved runtime source was modified by instrumentation. Each run measured 1,072 active stock-helper calls and 3,087 socket calls. Three-pass control: stock median 40 μs /p95 46 μs; socket mean 4.654 μs. Final: stock median 39 μs /p95 52 μs; socket mean 5.075 μs. The final stock p95 increased 6 μs in this run, while median difference was within timing noise. Outer passes average 2.20, median 1, p95 7 and maximum 8; early exit remains effective. The control fails seven physical transition checks; final fails none.

Reports: `/private/tmp/pocket-cost3-cost.json` and `/private/tmp/pocket-cost8-cost.json`; isolated diagnostic `/private/tmp/rifle_pose_cost_probe.gd`. Inner FABRIK iteration counts are not exposed by Godot and were not inferred. These are CPU microbenchmarks on this Mac, not browser frame-time or 32-player load evidence. Keep a real multiplayer profiling gate before making a capacity claim.
