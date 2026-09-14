# Source locomotion controller — first integration stage

## Current follow-up (2026-09-13)

The stage report below records the earlier implementation. The shared phase
helper now combines participating spaces by normalized weighted frequency
(`period = sum(weights) / sum(weight / period)`), supported by original-code
execution, instead of the earlier arithmetic period mean. Existing pistol
directional/firing siblings also share phase; no nonexistent pistol jog tier was
added. Reader-defined idle periods are integrated separately. See
[current implementation and proof](SOURCE_ANIMATION_MATCH_PASS_20260913.md) and
[remaining runtime gaps](SOURCE_ANIMATION_RUNTIME_GAPS.md). Directional blend
weights and the current speed adapter are still not a recovered 1:1 controller.

## Translation card

Player intent: restore the SOCOM II locomotion and action feel in the canonical
game, not just in an animation preview. Stage acceptance: use the SEAL source
walk/jog/run selection, prevent gait phase drift across directional and firing
branches, make the driver consume the graph's selected tier, and route native
pistol reloads through the same family selector as the graph.

One presentation owner: `Mannequin/ProductionAnimation` in
`scenes/player/operator_player.tscn`, using the existing AnimationTree.
`CharacterBody3D` movement/collision, camera/reticle aim, weapon/server action
identity, ammunition timing, damage, networking, hand IK and retargeting remain
protected. No map/art changes belong to this stage.

Chain: canonical movement/accepted weapon input -> ProductionAnimation -> shared
`config/operator_animation_map.json` + normalized weapon contract -> existing
profile/graph/action consumers -> rendered character in `main.tscn`.
The graph builder creates resources, not a new node or transform writer.

## Source evidence and limits

Local extracted readers at
`/Users/kiwimango/Downloads/SOCOM-II-animation-extractor/output/readers/animset.rdr.json`
and `motion.rdr.json` identify the SEAL animation set: default walk is
`seal_walk_alert`, jog is `seal_jog_alert`, run is `seal_run`. Ready walk is
`seal_walk_alert02`; its alert/ready-selection semantics are not fully rebuilt
here. Existing full firing directional takes remain the firing branch.
The source A/B speed bands are also embedded in imported Animation metadata.

| Direction | Walk A/B | Jog A/B | Run A/B |
| --- | --- | --- | --- |
| Forward | 0 / 4 | 2 / 6.15 | 4.01 / 6.5 |
| Backward | 0 / 2.8 | 2 / 3.7 | 2 / 3.7 |
| Left | 0 / 2.3 | 0.9 / 4.5 | 2.5 / 6.5 |
| Right | 0 / 2.8 | 1 / 5 | 3 / 6.5 |

Backward has two distinct takes; both higher tiers resolve `seal_run_bw`.
`operator_source_locomotion_policy.gd` reads these values once at graph build.
It linearly ramps each higher tier over its source band, combining the two ramps
as walk=(1-run)*(1-jog), jog=(1-run)*jog, run=run. Cardinal contributions are
interpolated for diagonals. **This is an explicitly inferred adapter, not the
recovered original PS2 blend-weight formula.** Existing cadence scaling and
direction smoothing are still adapter behavior. Source max-speed metadata does
not change CharacterBody's movement speeds in this stage.

`operator_gait_phase_sync.gd` gives related spaces one native-length-weighted
period. Godot's AnimationTree remains the only clock; the helper neither seeks
nor advances animation. The old separate mutable cycles drifted by nearly half
a cycle in the focused engine probe despite outer Blend2 `sync=true`.
Constant shared periods remove that observed drift. Weights use the actual
locomotion ready blend, not the separate standing-idle firing fade.

Rifle gait policy is opt-in with `locomotion.source_three_tier`. Older presets
default off. Pistol gait is intentionally unchanged. Native pistol reloads are
`seal_p_reload`, `seal_p_crouch_reload`, `seal_p_prone_reload`; the authoritative
reload action still owns duration, commit and interruption. These are not three
new gameplay actions.

Preflight validates all twelve resolved ranges before building the extra tier;
missing jog clips cannot silently become an arbitrary available animation.
At full body speed, cadence uses the current source range target rather than
the lagged cross-fade weight. This avoids transient playback overspeed while
still smoothing pose weights. The unchanged grounded-cadence regression caught
that interaction and passed after this separation.

## Focused proof

Run with Godot 4.7.1, explicit `--log-file /private/tmp/<test>.log` and canonical
project `--path /Users/kiwimango/socom-141-camera-lab`:

- `tools/source_animation_coverage_audit.gd`: configured-source census only;
  never presents configuration as an evaluated or original-engine parity test.
- `tools/source_gait_phase_regression.gd`: real engine cycle-phase comparison,
  startup source cadence, firing changes, invalid weights, no new clock.
- `tools/source_locomotion_policy_regression.gd`: source bands and adapter bounds.
- `tools/source_locomotion_controller_regression.gd -- --public-training
  --require-combat-alignment`: main scene, four analog speeds, directions,
  reversals, held-weapon contact, firing, reload and action return.
- `tools/source_action_routing_regression.gd`: family/weapon/fallback agreement.
- `tools/iso_pistol_reload_regression.gd`: three canonical pistol reload stances.
- `tools/iso_rifle_reload_regression.gd`: existing six rifle stance routes.
- `tools/source_grounded_blending_regression.gd`: previous timing gate retained.
- `tools/feature_contract_regression.gd`: feature integration gate.

## System-delta decision: MERGE

Keep the established owners and runtime tree. Merge source-selected tiers and
synchronized periods in that tree; replace the driver's contradictory forced
run selection only for the enabled rifle policy. Current -> candidate scores
(0–5): correctness 2->3, ownership clarity 4->5, canonical runtime parity 5->5,
editor usability 4->4, performance 5->4, regression coverage 3->5. The small
additional jog branch is the performance cost; metadata is not loaded per frame.
Correctness is deliberately not 5: original-game comparison is still required.

## Remaining work before a 1:1 claim

Original interpolation law, state priorities and interruption matrix; complete
stance transitions (including source end-closure keys), ready/alert selection,
start/stop/turn choices, prone backward source parity, traversal, deaths and all
remaining action coverage. Camera calibration and direction-specific movement
metrics need measured original-game evidence, not guessed values. This stage
does not certify multiplayer action parity or a complete original controller.

## Verification checkpoint

The source-policy proof passed all twelve ranges and malformed/missing-source
fallbacks. The phase probe measured old maximum separation 0.499966 cycles and
new separation 0.0. Action-route resolver proof passed 121 checks. Three native
pistol reload lifecycles passed 447 frames; six existing rifle lifecycles passed
894 frames. The previous grounded timing proof passed with 612 main-scene
frames, seven accepted shots and one reload, including strict combat checks.

A rendered main-scene run passed 1,152 checked frames (540 added gait frames),
seven accepted shots and one reload. Its two captured jog views showed no
T-pose or collapsed limbs, but fine finger/fore-end fit is visibly imperfect.
Socket-distance tests do not measure finger geometry. This is a retained
limitation, not a claim of perfect hand contact or original-game foot planting.
Reports and captures: `/private/tmp/source-locomotion-controller-rendered*`.

The feature-contract gate passed 141 contracts. The wider integration quick
gate stopped before running tests because this checkout is
`codex/render-deployment`, not its required `main`. No branch switch, reset,
commit, push or promotion was performed. Headless tools also emitted environment
CA/audio warnings and some exit-time ObjectDB leak warnings; those are not
counted as animation acceptance failures or silently called fixed.
