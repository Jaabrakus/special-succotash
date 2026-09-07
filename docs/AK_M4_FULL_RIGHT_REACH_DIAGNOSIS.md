# Full-right rifle reach diagnosis

## Read-only audit card

Intent: explain the support-arm collapse at the actual full-right torso target. Acceptance: measure canonical shoulder/elbow/wrist/socket endpoints over both postures, distinguish measurement completion from pose acceptance, and derive reachable-radius bounds without modifying contacts. Owner: the existing canonical presentation chain; the probe only reads its result. Protected: all runtime profiles, sockets, bone lengths, movement, camera, aim and shot ownership. Proof: `tools/rifle_full_right_reach_probe.gd`, using `res://main.tscn`, actual move-right input and an accepted shot.

## Fixed-stock baseline

At the real 89.955–90 degree torso target with zero directional-target residual, 24 settled frames per posture gave:

| Weapon/posture | Actual left elbow | Maximum wrist radius with any wrist orientation | Radius needed for 42 degrees |
| --- | ---: | ---: | ---: |
| M4 standing | 17.11–17.19 degrees | 0.19541–0.19555 m | approximately 0.2322 m |
| M4 crouched | 17.06–17.22 degrees | 0.19865–0.19890 m | approximately 0.2322 m |
| AK standing | 29.48–29.56 degrees | 0.25229–0.25266 m | approximately 0.2322 m |
| AK crouched | 29.95–30.09 degrees | 0.25570–0.25612 m | approximately 0.2322 m |

The M4 cannot reach the unchanged 42-degree minimum with a fixed shoulder root and fixed stock/palm socket, even with an arbitrary wrist rotation. The AK's arbitrary-orientation envelope admits a possible radius, but neither its current authored wrist basis nor the existing calibrated support basis reaches that minimum. Feasibility is not an authored-pose solution.

Code evidence:

- `scripts/player/operator_weapon_contact_solver.gd`, `wrist_target_for_contact()`: `contact_transform.origin - desired_basis * scaled_anchor` fixes the wrist target from the fixed palm contact and wrist basis.
- `scripts/player/operator_arm_kinematics.gd`, `_distance_for_elbow_angle()`: `sqrt(upper*upper + lower*lower - 2.0*upper*lower*cos(angle))` gives the minimum shoulder–wrist distance.
- `scripts/player/operator_weapon_authored_stock_pose.gd`, `apply()`: reconstructs the authored weapon, rotates about the stock pivot, supplies the final physical palm sockets, then solves both arms.
- `scripts/player/operator_weapon_socket_ik.gd`, `solve()`: a pole changes the bend plane; extra correction passes reduce wrist residual. Neither changes bone lengths or the required shoulder–wrist radius.

The helper's old unrestricted socket solve did not enforce its exported minimum elbow angle. Enforcing that minimum alone would break contact, not solve this geometry. A solver convergence tweak cannot fix the contradictory constraints.

## Necessary, not sufficient, shoulder-root bounds

For fixed M4 stock and palm contact, the triangle inequality requires at least 3.3–3.7 cm root displacement allowing **any** wrist orientation; 13.4–13.7 cm preserving the current authored wrist orientation; or 8.66–8.90 cm using the existing calibrated wrist orientation. These are necessary lower bounds only. They do not establish a valid displacement direction, joint limits, hand orientation, torso appearance or a safe authored pose.

The measured clavicle-to-upper-arm-root lever is 15.34 cm: even an unconstrained 20-degree rotation moves its endpoint by at most 5.33 cm, and 30 degrees by at most 7.94 cm. A small clavicle correction alone therefore cannot solve the current/canonical M4 wrist configuration. No bone/socket mutation was made by this audit.

Baseline evidence: `/private/tmp/m4a1-full-d-envelope-output.log`, `/private/tmp/ak-47-full-d-envelope-output.log`, and the independently reviewed native `/private/tmp/rifle-cleanup-m4-standing_move_right_fire-side.png`.

## Superseding candidate: release the stock during right carry

The later authorized constraint change is documented in `AK_M4_RIGHT_CARRY_RELEASE_TRANSLATION.md`: release the rigid rifle forward during right carry rather than hold an infeasible full-right shoulder pin. Fixed local grip sockets, reticle bore, left stock contact and bone lengths remain protected.

At a saved 0.22 m release, canonical settled tests gave M4 left angles 54.06 degrees standing /44.73 degrees crouched, and AK 66.57/57.18 degrees. All palms were below 0.60 mm and physical bore below 0.037 degrees. These results do not approve native appearance or every transition. See the focused regression and current native review.

Run the repeatable read-only audit:

```sh
/Users/kiwimango/Applications/Godot-4.7.1.app/Contents/MacOS/Godot --headless --fixed-fps 60 --path /Users/kiwimango/Documents/SOCOM-141 --script res://tools/rifle_full_right_reach_probe.gd --log-file /private/tmp/full-right.log -- --weapon=m4a1 --output-prefix=/private/tmp/full-right
```

It measures the **currently saved** profile; it does not restore the old fixed-stock baseline or alter runtime values. `measurement_complete` means the fixture produced all 48 valid input-driven samples, not that all poses satisfy human bounds. The separate release regression turns the geometry limits into assertions.

Decision: **REJECT** a pole/iteration-only fix (correctness 1, ownership 5, runtime parity 5, editor usability 3, performance 3, coverage 3). **KEEP** the read-only audit (correctness 5, ownership 5, parity 5, usability 4, performance 4, coverage 5). Evaluate the new release candidate separately.
