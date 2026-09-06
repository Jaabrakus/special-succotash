# Pistol movement contact and remaining refactor

## Translation card

- Intent: keep the support palm on the pistol through idle-to-movement blends;
  then finish the four deferred responsibility extractions.
- Acceptance: physical palm/socket error stays within the existing 1 cm gate
  without stretching bones or moving camera/body/weapon authority.
- Owner: existing post-animation weapon-pose/socket solver.
- Protected: shot aim, damage, movement, reload release, art assets, timing and
  shoulder/spine ownership; no second runtime modifier or processing loop.
- Proof: per-frame entry diagnostic, existing standing movement placement,
  pistol idle/recovery and family regressions, rendered transitions, file budget
  and feature contracts. Keep baseline failures separate from new regressions.

## Delta review

MERGE only a bounded contact repair supported by measurement. Current versus
candidate scores (0–5): correctness 2/4, ownership 4/4, canonical parity 5/5,
editor usability 4/4, performance 4/4, regression coverage 3/4. Candidate scores
remain provisional until proof. Evidence: `operator_weapon_socket_ik.gd`,
`operator_weapon_pose_ready.gd`, `pistol_standing_movement_placement_regression.gd`.

Godot 4.7.1 is installed. Official latest SkeletonIK3D and Skeleton3D references
were consulted for one-shot solve, overrides and skeleton/world pose spaces;
latest documentation is advisory and behavior is verified on the installed
engine. This pass does not migrate the deprecated IK API.

## Measured diagnosis and bounded repair

1. The solver's sub-millimetre result disagreed with physical end-of-frame
   contact by up to several centimetres. The support target/socket gap grew
   after solving: `BoneAttachment3D` resampled the trigger wrist and moved the
   gun after the support palm had been solved.
2. Finalizing the existing detached presentation anchor eliminated that gap,
   but crouched-left entry still requested 0.69955 m from a 0.64791 m arm chain.
   More IK weight cannot make that pose reachable without stretching.

`scripts/player/operator_weapon_authored_pose.gd:75` now keeps the authored
pistol mount finalized before the support solve:

```gdscript
pose._set_weapon_solver_owned(pose.animation_owned_aim_alignment_enabled)
if pose.animation_owned_aim_alignment_enabled and not use_animation_aim_anchor:
    pose._weapon_transform_on_trigger_hand(pose._right_hand_grip_world_transform(), true)
```

Idle carry still follows the authored trigger palm, not reticle alignment.
For an unreachable idle support target only, `operator_pistol_carry_reach.gd`
uses the existing right-arm solver to bring the paired grip inward, capped at
0.10 m. Maximum support reach is the measured chain length times 0.965. It does
not scale bones or write shoulder/spine transforms. The final support palm is
then solved against the final physical socket. The failing crouched-left
sample became approximately 0.00076 m error with 0.62537 m wrist demand and an
unchanged 0.64791 m chain.

The fixed pose implementation was verified before its ownership-specific
branches were extracted. `operator_weapon_pose_ready.gd` still chooses the
owner and calls the synchronous helper; the helper is not a second node.

## Proof and known exclusions

- `/private/tmp/retry-contact-final-proof.log`: PASS, full six-direction/stance
  cases including entry, fire and stop; physical contacts <=1 cm, completed
  movement-frame target/socket gap <=1 mm.
- `/private/tmp/retry-final-idle.log`: PASS, four compressed idle/fire/recovery
  cycles and two reload cases after extraction.
- `/private/tmp/retry-family.log`: PASS, 42 weapons / 84 standing+crouched cases.
- `/private/tmp/retry-directional_locomotion_phase_regression.log`: PASS.
- Hybrid locomotion/action and playback cadence regressions: PASS.
- `/private/tmp/retry-nine-boundaries.log`: PASS all nine extraction boundaries.
- `/private/tmp/retry-god_file_budget_regression.log`: PASS 380 scripts, with
  the four original ceilings unchanged.
- `/private/tmp/retry-contracts-final.log`: PASS all 62 contracts.
- `/private/tmp/retry-canonical-boot.log`: `main.tscn` exits successfully after
  the bounded boot; existing certificate lookup warning remains.
- `/private/tmp/retry-render-final.log`: display-backed six-case standing /
  crouched movement-entry, firing and stopped contact regression PASS. Reviewed
  side/rear captures of entry, movement and fire under
  `/private/tmp/pistol-placement-*.png`; hands stay paired on the grip and the
  existing bent-arm carry / extended firing silhouettes remain. These captures
  are scoped contact/presentation proof, not a complete locomotion art review.
  An earlier display test stalled during capture and was stopped by its exact
  process ID; the fresh final run exited successfully. Its inherited final
  `cases=4 reloads=2` label belongs to the base test and does not describe this
  six-case movement test; the separate idle/reload result is listed above.
- `/private/tmp/retry-editor-final.log`: editor import/parse exits 0 without
  script/parse errors. Existing M16A2 duplicate UID, SubMachineGun filename case,
  editor-settings permissions and ADB warnings are not fixed by this pass.

### Independent dive baseline

The broad dive regression after extraction reported crouched dive support
error 0.04012 m and prone recovery trigger error 0.39471 m. A temporary fixture
reinstated the pre-extraction kinematics, placement, ready and locomotion graph
source; it also removed both new pistol-contact changes. Its driver uses those
original components in the same canonical scene. No live source was swapped.

- Before: `/private/tmp/retry-dive-before.log`; crouched support 0.04092 m,
  recovered-prone trigger 0.39367 m. Both fail the same assertions. Standing
  dive support also failed in that run (0.04376 m).
- After: `/private/tmp/retry-dive.log`; the two crouched failures above.
- Fixture: `/private/tmp/socom-refactor-before/dive.gd` and adjacent original
  component copies; original dive test body apart from driver substitution.

These are isolated pre-existing dive failures, not a passing dive gate and not
part of this repair. No dive tuning or weakened assertions were introduced.

The SOCOM/Godot workflow's failure isolation requirement caused this extra
baseline check before completing the refactor. Decision remains **MERGE** for
the measured pistol repair and bounded extractions; unrelated dive changes
are deferred. Six scores above apply to this scoped change, not whole-game
readiness. Aggregate integration remains blocked by its `main` branch policy;
the dirty `codex/render-deployment` branch and browser export are preserved.
