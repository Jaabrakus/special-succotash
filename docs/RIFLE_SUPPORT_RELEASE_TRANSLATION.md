# Rifle support-hand release continuity

## Translation card

- Player intent: returning from firing to idle must not flip the support wrist or pop the elbow after the weapon has already settled.
- Acceptance: the ordinary standing/crouched authored-stock → hand-follow boundary retains the same physical grip and continuous wrist/elbow geometry; the final frame change stays within 5° wrist/elbow rotation and 15 mm elbow movement relative to the player. Every tested palm remains within the existing physical contact bounds. Fully-ready poses (readiness ≥0.98), full-D carry, grip positions and the 1.2-second recovery remain unchanged.
- One owner: `SocomOperatorWeaponPoseSolver` and its existing authored-stock/hand-follow strategies. Extract their shared saved support-wrist basis calculation into the existing contact-math helper, then blend the low-readiness authored wrist/pole toward that same fallback endpoint. Use existing readiness only, with no new timer, latch or animation route.
- Protected: camera/reticle, CharacterBody movement/collision, shot/damage/network authority, rig JSON, all sockets and scales, authored action/reload/prone paths, root's current-frame trigger-anchor finalization, full-ready wrist/pole formulas and fixed arm limits.
- Proof: canonical AK/M4/M16 `rifle_support_release_regression.gd`, existing firearm transition matrix and M16 exact-rig proof; observe native late-release wrist and elbow if the physical candidate passes. Original route-timing evidence is `/private/tmp/rifle-route-timing.timing.json`.

## Six-axis system delta (0–5)

| Axis | Current | Candidate | Evidence |
| --- | ---: | ---: | --- |
| Correctness | 2 | 4 provisional | At readiness ≤0.001, stock strategy returns false and fallback chooses a different support wrist/pole; measured elbow jump is 31–44° despite <1 mm stock movement |
| Ownership clarity | 5 | 5 | Existing weapon pose node and contact-math helper; no new process or state owner |
| Canonical parity | 5 | 5 | Same canonical driver, rig and input path for both strategies |
| Editor usability | 4 | 4 | Existing saved support-hand orientation remains the idle endpoint |
| Performance | 4 | 4 | One low-readiness quaternion interpolation and pole interpolation; no new IK chain or additional solve iterations |
| Regression coverage | 3 | 5 provisional | Add explicit owner-boundary continuity measurement to current physical gates |

Decision **MERGE conditionally**. Preserve the fully-ready authored convention and smoothly approach the already-established fallback convention only near zero readiness. Reject a candidate that fixes the numerical angle by loosening hand-contact bounds or changing gun placement. A second observed issue is that the stock path solves at IK weight1 while storing `current_weight = readiness`; the fallback resumes its existing support-weight ramp from that value. Do not change that bookkeeping/weight contract without measuring its remaining effect and recording a separate delta.

Godot 4.7.1 is the installed engine. This is presentation transform interpolation inside the existing owner, not a new SkeletonModifier or movement/animation state.

## Measured implementation result

The shared extraction is in `scripts/player/operator_weapon_contact_solver.gd`, `support_contact_basis()`:

```gdscript
socket_basis.orthonormalized()
* Basis.from_euler(rotation_degrees * (PI / 180.0), EULER_ORDER_YXZ)
```

`operator_weapon_authored_pose.gd` calls this exact old formula for its existing fallback. `operator_weapon_authored_stock_pose.gd` approaches it using only current readiness:

```gdscript
if amount < 0.25:
    var authored_support_weight: float = smoothstep(0.0, 0.25, amount)
    # Interpolate idle -> authored wrist basis and pole by this same weight.
```

The accepted low-readiness candidate does **not** change `current_weight`, IK budgets, saved rigs, full-ready formulas, or the existing 1.2-second recovery timer. Its extra work is one quaternion interpolation and one existing pole calculation only below 0.25 readiness; no iterative search was added. Exact full-ready formula identity does not imply bitwise identical iterative solver results: comparing 708 readiness ≥0.98 rows produced zero right-elbow/bore change, maximum 0.298° left-elbow change and 0.943 mm support-error change, all within original bounds.

Canonical actual-input proof, both postures of AK/M4/M16:

| Owner handoff metric | Before | Candidate maximum |
| --- | ---: | ---: |
| Support wrist frame delta | 139.62° | 0.056° |
| Support elbow-angle delta | 44.34° | 0.319° |
| Support elbow displacement relative to player | 219.31 mm | 0.869 mm |

The headless candidate and native run each pass all six real readiness-zero handoffs and 1,308 physical transition frames. Reports: `/private/tmp/rifle-release-basis-release.json`, `/private/tmp/rifle-release-final-native-release.json`, and their sibling full-matrix `.json` files. Maximum native palm error is AK 1.115 mm, M4 4.392 mm, M16 0.994 mm, below the unchanged 5 mm authored / 10 mm fallback limits. Independent evaluated-carry timing passes 872 physical frames (`/private/tmp/rifle-release-timing.json`). Pistol compressed idle/reload passes four idle cases and two reload cases. The integration graph passes 86 contracts at this checkpoint.

The legacy `weapon_contact_solver_regression.gd` still fails two source-string checks against previously modularized wrapper files (`gun_calibration_lab.gd`, `operator_weapon_pose_solver.gd`); its geometric math checks pass. This bounded change does not relabel that stale-source gate as passing.

Native review is not yet approved: initial final-run images show continuous arms across frames 97→98 but no rendered weapon meshes, despite physical socket nodes being measurable. Visibility must be diagnosed before claiming visible weapon-contact proof. This is a separate review limitation, not permission to weaken physical acceptance or change runtime visibility.

### Native fixture delta: isolate physical inputs before startup

Read-only inspection proves the native startup receives a real grenade-equip input before the matrix erases physical bindings: `_equipped_weapon_visible=false`, `weapon.visible=false`, `grenade_equipped=true`, while the same headless setup reports true/true/false. The weapon mesh itself is visible on layer 1 but inherits its hidden parent's state. Move the existing test-only InputMap isolation before main-scene instantiation, leaving canonical input actions and all game runtime logic unchanged; do not force visibility or grenade state. Acceptance is a naturally visible equipped rifle and exactly the scripted accepted shots. Delta decision **MERGE**: correctness 2→5, ownership 5→5, canonical parity 3→5, editor usability 4→4, performance 5→5, regression coverage 4→5. This eliminates external test contamination rather than adding a gameplay writer.

Code review of `scripts/main.gd:270` also proves that `_ready()` reapplies the saved mapping. Therefore the test re-isolates immediately after `root.add_child(scene)`, before its first awaited frame, retaining that canonical post-ready mapping for restoration. The intermediate startup-only run correctly failed its unrequested-shot checks when M4 received physical firing; its visual/physical approval is rejected. Do not omit the post-ready isolation.

Installed-engine minimal probe additionally proves that `Input.action_release()` unconditionally produces `is_action_just_released=true` even for a previously unpressed action. `main_equipment_selection.gd::update_switch_state()` interprets that release as a quick grenade tap. The old isolation loop itself therefore created the missing-rifle state in native captured-mouse mode. Final fixture cleanup releases only genuinely pressed actions and lets two paused startup frames retire pre-existing input flags before gameplay runs. It never forces weapon visibility or changes equipment state. The matrix now requires a naturally visible weapon with at least one visible mesh after equip stabilization and before every image. The focused release probe captures only the real frame-97/98 handoff pair; full-state imagery remains available in the parent matrix.

### Final native checkpoint — approved for the bounded release change

`/private/tmp/rifle-release-approved-native.json` passes all 1,308 physical frames and all six real owner handoffs with stable runtime source signatures. All 12 paired samples (24 rear/side images) contain naturally visible rifles, and no unrequested shot occurred. Direct side-view comparison of frames 97→98 for AK/M4/M16, standing and crouched, shows the support wrist and elbow staying continuous and attached at the transition. Native palm maxima: AK 1.157 mm, M4 4.381 mm, M16 0.995 mm. Release maxima: wrist 0.056°, elbow-angle 0.319°, relative elbow movement 0.869 mm. The M16 immutable-rig/action-field proof separately passes 436 physical frames in `/private/tmp/rifle-release-m16-strict.json`.

Decision **MERGE** for the bounded support-release correction; native review limitation above is resolved by the test-only fixture fix. This does not certify all weapon families, reload/prone/mobility behavior, model identity, or all aim elevations. Those remain independent gates. No rendered pose or test result is being used to claim the new 1212 asset assignments are complete.
