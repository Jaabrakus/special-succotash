# AK/M4 right-strafe carry release

## Translation card

1. Player intent: During the full right body turn, the arms must not collapse into the chest; both palms stay on the rifle and its physical bore stays toward the reticle.
2. Acceptance: AK/M4 standing/crouched right carry uses a saved, readiness-blended forward release of the stock. Both existing palm contacts remain within 5 mm when settled, physical bore within 0.5 degrees, and both elbows remain inside the existing 42–150 degree bounds. Direction/readiness transitions must be inspected, not only endpoint poses. Left strafe and zero-ready idle receive no release. Rendering must confirm natural wrists/arms before acceptance.
3. Owner: The existing authored weapon-pose helper, through the existing weapon presentation owner. It rebuilds the authored mount each frame, places the stock pivot, aligns the physical bore and solves both fixed palm sockets.
4. Protected: Camera/reticle aim, player movement/collision, shot authority/cadence/1.2-second recovery, networking, local weapon socket positions, bone lengths, authored animation, reload/prone/air and other weapon profiles.
5. Proof: `tools/rifle_full_right_reach_probe.gd`, `tools/rifle_right_carry_release_regression.gd`, existing M4 vertical-slice and left-shoulder regressions, and parent-run rear/side canonical native captures.

## Changed constraint and saved chain

The previous full-D stock-pinned requirement was infeasible for the M4 support arm: at a true 90-degree torso target, its maximum wrist radius for any orientation was 0.196–0.199 m, below the existing 42-degree minimum radius of 0.232 m. Iteration/pole changes cannot solve this. The new bounded candidate releases the stock forward only during positive smoothed right strafe and actual ready weight. It does not move either local grip socket.

Existing posture owner final right-turn progress -> driver final `right_stock_turn_weight` argument -> `operator_weapon_pose_ready.gd` -> saved `handling_profile.dynamic_hold.strafe_carry.right_stock_release_m` -> equip-time `configure_dynamic_hold()` -> `operator_weapon_authored_stock_pose.gd` -> existing presentation owner and both palm solvers. The shared turn weight already contains readiness/activation, so the helper does not multiply readiness twice. Default saved meters is zero and re-equipping resets the value. Optional API weight -1 preserves older callers' signed-direction fallback. AK/M4 raw profiles and immutable M4 v7 carry the same value. M4 v6 remains intact. The independent parent-owned `standing_idle_square_pelvis` field is included in v7 but is not consumed by this helper.

Start the candidate at 0.20 m, measure before accepting. An offset that fixes one hand by overextending the other or distorts either wrist must be rejected. No bone stretching or threshold relaxation is permitted.

First measurement: 0.20 m passed standing but crouch uses a speed-scaled signed carry of approximately 0.759. Its 0.1519 m actual release left the M4 elbow at 41.96–42.04 degrees, failing the unchanged 42-degree bound. The saved candidate is increased to 0.22 m for both rifles, without changing the direction signal or constraints.

First actual-input transition test: **not accepted**. Settled full D passed, but deceleration/reversals could fold the support arm because the torso target used normalized direction while release used its speed-scaled magnitude. M4 D-stop had a 24.1-degree support elbow and 21.5 mm contact error. The M4 left-strafe firing state also exposed an existing 36-degree trigger elbow with zero stock release. Neither assertion was weakened.

Second candidate uses the same final turn progress as the torso. Canonical right-turn and reversal support contacts now stay below 1 mm; the M4 crouch reversal improved from 17.8 degrees /18.8 mm to at least 54.78 degrees /0.31 mm. The broad transition gate is still **FAIL**, not green: M4 A-fire trigger elbows remain 36.2–36.7 degrees with up to 9.56 mm contact error, and the first fully stopped/zero-turn frame reaches left elbow 39.54 degrees M4 /41.16 degrees AK. Those states have exactly zero release. They require a separate authored A/idle envelope correction, not another right-carry offset. Evidence: `/private/tmp/shared-turn-m4.json`, `/private/tmp/shared-turn-ak.json`. The existing strict all-directions stock gate also remains failing; its hand/angle thresholds are unchanged.

## Six-axis delta (0–5)

| Axis | Stock pinned at full D | Bounded release candidate | Evidence |
| --- | ---: | ---: | --- |
| Correctness | 1 | 3 provisional | Canonical full-D reach envelope; settled/transition physical regression still required |
| Ownership clarity | 5 | 5 | Same authored-stock and presentation owner |
| Canonical runtime parity | 5 | 5 | Raw AK, resolved immutable M4 contract, actual main scene |
| Editor usability | 4 | 4 | One named saved meter value, zero default |
| Performance | 4 | 4 | One scalar/vector offset; no new IK or frame loop |
| Regression coverage | 3 | 4 provisional | Geometry, direction/readiness guards and native physical proof |

Decision: **MERGE candidate for measurement**, not visual approval. Keep the single owner and contact contracts; replace only the infeasible full-D stock pin. Do not ship a failed candidate.

## New intent: crosswise carry in front of the turned chest

Player intent: On D the torso faces right while the rifle is held crosswise in front of the chest, not slid along its barrel. Acceptance: the release vector follows the turned chest's forward direction, while physical bore remains reticle-directed, local palms stay fixed, and the existing contact/elbow limits still pass for positive-right carry. Owner: the same authored-stock helper and weapon presentation owner. Protected: shared final turn timing, A/idle zero release, local grip contacts, camera, shot/recovery, movement, actions and other weapons. Proof: the updated release regression records the actual pocket-to-stock vector, compares it with the chest/aim frame, and requires native front/side review.

Saved field: `strafe_carry.right_stock_release_frame = "chest_forward"`. Its default is `"aim_forward"` for compatibility. The existing final right-turn weight determines the intended chest yaw, so no second angle clock or driver binding is introduced. Project the camera-owned aim to the horizontal plane, turn it right by the same final torso angle, and use that chest-forward vector for translation only. The following bore alignment and fixed-palm solve remain unchanged. Preserve M4 v7; publish v8 with only this new saved field.

Delta review (current -> candidate, 0–5): correctness 2 -> 3 provisional (prior release cleared folds but moved along the barrel rather than in front of the chest); ownership 5 -> 5 (same owner); runtime parity 5 -> 5 (same raw/resolved contract); editor usability 4 -> 4 (explicit saved frame); performance 4 -> 4 (one bounded basis rotation, no extra solve); regression coverage 4 -> 4 (physical vector plus unchanged hand/bore/angle checks). **MERGE for measured comparison**, subject to contact geometry and rendered review. Start at the existing 0.22 m, do not shift hand sockets or lower bounds to force a pass.

Measured chest-frame update: 0.22 m correctly places every rifle ahead of the physical chest plane (nearest rigid-mesh bounds approximately 0.199–0.236 m forward) but support elbows remain 29–31 degrees. Actual target-vector envelopes require at least 0.2916 m for M4 and 0.31583 m for AK to reach 42 degrees. The existing 150-degree maximum allows at least 0.518 m. Test the smallest shared value with a modest margin, **0.33 m**, and raise the implementation-only clamp from 0.25 to 0.40 m. This changes no anatomical limit. V8 now differs from preserved v7 in exactly the release frame and its scalar value. The frame and scalar are still provisional until physical/native acceptance; v8 has not been promoted as a restore point.

V8 0.33 m measured result: settled full D passes both postures. M4 support elbows are at least 49.06 degrees, trigger elbows 80.57–81.70 degrees, palms at most 0.84 mm. AK support elbows are at least 44.26 degrees, trigger elbows 96.13–96.32 degrees, palms at most 2.86 mm. Physical bore error is below 0.034 degrees. The nearest visible rigid-mesh bounds are 0.309–0.346 m in front of the measured chest plane, with all four stock/hand/muzzle contacts at least 0.337 m ahead. This is an in-front-of-torso clearance result, not just an elbow-angle assertion.

AK positive-turn transitions also pass (at most 4.46 mm palms, elbows 44.3–123.7 degrees). M4 near-A transitions still expose the existing trigger-arm envelope: 38.4 degrees and 6.08 mm as it approaches its zero-release A state around 36 degrees. The complete transition gate remains **FAIL**; no limits were loosened and no A/idle correction was added. Latest reports: `/private/tmp/chest33-m4.json`, `/private/tmp/chest33-ak.json`. The native front/side review remains required.

## Final local review, 2026-09-06

The latest requested endpoint is implemented: **in front of the torso** during rightward firing/recovery, crosswise to the turned body. This supersedes the earlier along-barrel release candidate above. Native canonical `res://main.tscn` captures were generated with actual right-movement input, accepted shots, both stances, and the current saved .33 m chest-forward frame. Rear/side review confirms the stock is off the shoulder and the gun/forearms are ahead of the torso at settled D. This is scoped endpoint approval, not approval of every transition or a claim of exact reference-game parity.

Exact saved contract: `config/weapons/ak-47.json:105` and `config/weapon_visual_rigs/m4a1_agls_v8.json:88`:

```json
"right_stock_release_m": 0.33,
"right_stock_release_frame": "chest_forward"
```

The existing presentation owner applies that translation at `scripts/player/operator_weapon_authored_stock_pose.gd:61`, then aligns the physical bore at line 70:

```gdscript
release_direction = flat_aim.normalized().rotated(Vector3.UP, -PI * 0.5 * turn_weight)
```

Focused native probe: `tools/rifle_right_carry_visual_probe.gd`. Reports: `/private/tmp/torso-front-m4.json`, `/private/tmp/torso-front-ak.json`. Both completed without script/parse errors. Representative reviewed captures:

- `/private/tmp/torso-front-m4-standing_move_right_fire_settled-side.png`
- `/private/tmp/torso-front-m4-standing_move_right_fire_settled-rear.png`
- `/private/tmp/torso-front-m4-crouched_move_right_fire_settled-side.png`
- `/private/tmp/torso-front-ak-standing_move_right_fire_settled-side.png`
- `/private/tmp/torso-front-ak-crouched_move_right_fire_settled-rear.png`

The measurement regression remains the stronger numerical check: `/private/tmp/chest33-final-m4.json` and `/private/tmp/chest33-final-ak.json` retain all hand, bore, anatomical-limit and chest-clearance assertions. Their 48 settled full-D samples per rifle pass. **Their overall transition result is still FAIL** for M4 near-A/zero-release trigger-arm limits and stopped-frame support-arm limits; these are not waived by the passing endpoint or feature graph.

Related requested changes verified in this pass: standing idle pelvis alignment (`tools/rifle_idle_pelvis_regression.gd`, PASS), distributed waist correction (`tools/rifle_articulated_spine_regression.gd`, PASS), and forward-jump leg source alignment (`tools/jump_forward_legs_regression.gd`, PASS; native `/private/tmp/jump-source-frame-verified.json`). Natural head bob is retained. No mesh topology/weights, camera aim, player collision or shot timing changed.

Final structural validation: `tools/feature_contract_regression.gd` PASS, 81 contracts; M4 v8 immutable-profile/canonical-equipment regression PASS; `git diff --check` PASS. The structural graph is not a substitute for the failing physical transition gate. No browser ZIP rebuild, packaged-animation-cache refresh, commit, push or deployment was performed in this pass. This is not a verified restore point or release candidate.
