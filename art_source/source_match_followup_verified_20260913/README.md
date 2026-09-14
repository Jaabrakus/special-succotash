# Follow-up source matching proof — 2026-09-13

All renders use the actual current skinned character in canonical `main.tscn`.
The separate test camera does not change the saved gameplay camera.

## Idle phase transfer

`phase-native.json`, `phase-native-phase.json`, `phase-native.log`:
fresh saved-policy graph, no candidate rebuild. Seven actual grounded arrivals
verified, both standing and crouch. First destination clock matches outgoing
phase; seek requests consumed once. PASS58 checks. Six inspected PNGs show
early/middle/late target weights0,0.3739166,0.8530681 in rear/side views.
Capture invariants preserved. The figure transitions out of its previous gait
pose into idle without a bind pose in these samples. Existing transient foot
float in the outgoing gait/held blend is still a parity limitation.

The final malformed-metadata fail-closed guard was added after this native
process loaded; it does not change these complete six-leaf source routes.
Final unit and saved-policy headless runs cover the final on-disk helper.

## Physical support wrist

`wrist-native.json`: M4/AK, standing/crouch, movement and early/middle/late fire.
20 observations/40 captures. All inspected by the wrist subtask; root also
inspected M4 standing idle/fire and AK standing idle/crouch fire close-ups.
Contact≤0.807mm, bend≤55.001°, settled aim≤0.038°. Source weapon-up is now
derived from calibrated sockets rather than the unrelated parent mount Y.

**Visual grip remains partial:** M4 thumb protrudes away, AK thumb intersects
the fore-end, existing right-hand receiver clipping remains. Those are not
resolved by correcting the support wrist's reference frame. Source rig contains
no finger animation channels.

## Other proof

Standing diagonal movement's12 captures and logs are in
`../source_direction_verified_20260913/`. Its native test predates the wrist
correction; the phase set here includes the new wrist correction as well.
Original instruction fixtures are in `../source_gait_weight_audit_20260913/`.

This is local Godot proof, not an updated browser ZIP or a certified one-to-one
reproduction of all original movement, state selection and procedural poses.
