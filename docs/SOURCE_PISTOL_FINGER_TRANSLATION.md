# Source pistol finger-only contact

## Translation card

- Player intent: retain authored source pistol arms and wrist trajectories while
  the visible trigger fingers grip the pistol instead of remaining open.
- Acceptance: positive rest-relative right finger curl; optional left closure
  only when explicitly requested; no wrist, arm, other bone or weapon change;
  repeated application does not accumulate; hidden weapon releases this pass.
- Owner: `SocomOperatorWeaponGripContact.apply_source_pistol`.
- Protected: source clips, character selection/assets, wrist and arm IK,
  CharacterBody movement, camera, aim and server weapon/damage ownership.
- Proof: `tools/source_pistol_finger_regression.gd` exercises the actual selected
  model and canonical fallback. This numerical test is not visual validation.

System delta: MERGE the existing canonical +X rest-relative finger shape through
an explicit pistol API; REJECT re-enabling legacy right-hand negative curl or
inferring support closure from a missing owner-snapshot field. Scores in order
correctness/ownership/runtime parity/editor usability/performance/regression:
existing missing/legacy branch 1/4/2/3/5/2; explicit candidate 4/5/3/3/5/4.
Runtime parity remains partial until the coordinating driver change wires the
saved profile into this public API and passes its canonical-game check.

The driver owns when to call this method and supplies weapon visibility and
whether the support hand is intentionally closed. Existing weapon metadata
`support_hand_pose.finger_curl` / `thumb_wrap` supplies saved shape controls;
zero values use pistol defaults 0.72 / 0.64. No animation resource is changed.

## Focused results

`source_pistol_finger_regression.gd`: PASS on selected
`modern_soldier_iso.scn` and canonical `ps1_dual_source_rig.scn`. It checks
15 right finger bones / 30 explicitly requested both-hand bones, positive curl,
trigger index shaping, 60 repeated applications without accumulation, unchanged
arms/wrists/non-finger bones and weapon transform, support release, hidden/stowed
release, and zero-control defaults.

`rifle_finger_regression.gd`: PASS after the coordinating task fixed a driver
type-inference parse error on `visible_pistol`. The first attempt could not
instantiate the driver and was terminated; that was not a passing boot.
The new finger helper itself passed independently before that driver fix.
Scoped `git diff --check`: PASS. Rendered selected-character contact and complete
main-game behavior remain the coordinating task's separate acceptance checks.
