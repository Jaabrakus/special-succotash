# DE .50 support-palm orientation calibration

## Translation card — 2026-09-06

- **Player intent:** Preserve the approved two-hand pistol carry while preventing the DE .50 support arm from overextending during right-strafe recovery.
- **Acceptance:** The actual canonical standing/crouched A/D/reversal/stop matrix keeps both elbows within the existing pistol 38–155° range, physical palms within 1 cm and ready bore within 1°. First-shot timing, recovery duration, weapon dimensions and every socket position remain unchanged. Idle, stop and crouch are negative controls, not exemptions.
- **One owner:** The existing weapon pose owner consumes the existing saved `support_hand_pose` wrist orientation. Only a model-specific immutable visual-rig revision and the DE .50 assignment may change; no second runtime IK, angle-limit change, or global pistol policy is allowed.
- **Protected:** CharacterBody movement, camera/reticle and shot authority, the accepted-event ready-mask fix, all other weapon profiles/assignments, animation clocks/poses, socket positions, gun mesh/scale, trigger-hand mounting, recoil and ammunition/damage/reload statistics.
- **Focused proof:** First reproduce DE .50 using `firearm_family_transition_regression.gd --weapons=de__50`, including ready-stop elbow assertions. A bounded authoring probe may compare small support-wrist rotations against the unchanged physical contact. Publish/assign only a promising saved candidate, rerun the same canonical matrix and a native first/settled/return view, then validate immutable-rig and gameplay-data parity.

## Code evidence and decision

The existing family rig `family_pistol_4_v3` uses zero support-palm pitch/yaw/roll.
`operator_weapon_authored_pose.gd` composes that basis with the physical support
socket before the existing one-shot support solve. Rotating the wrist about the
same palm contact changes shoulder-to-wrist reach without moving that contact or
the gun. The exact direction/magnitude must be measured; no new socket position
or anatomical tolerance is justified by a small overextension.

Baseline eight-pistol proof reports DE .50 standing D-fire frames 13–18 at
155.655° decreasing to 155.027°, with bore ≤0.0573° and palms ≤1.765 mm. The current
matrix also measures readiness during stop; the fresh single-weapon baseline
must determine whether its cycle phase exposes additional failures.

**Conditional MERGE only for a proven per-model saved orientation improvement.**
Current scores: correctness 3, ownership 5, runtime parity 5, editor usability 5,
performance 5, coverage 4. Candidate targets: correctness 4, all other scores
unchanged except coverage 5. Reject socket movement, weapon scaling, global
runtime corrections, or looser elbow limits to hide this defect.

## Bounded candidate selected

Fresh canonical baseline reproduced standing D-fire at 155.632°; no ready-stop
failure appeared. Same-contact reach math predicts that +2° support-palm pitch
shortens shoulder-to-wrist reach approximately 2.54 mm at the worst frame.
The +3° authoring candidate supplies margin and passes all 436 actual input
frames: maximum left elbow 153.127°, right 146.323°, palm error 1.109 mm,
and ready bore 0.0573°. See `/private/tmp/de50-palm-pitch3-source.json`.

Only `visual.support_hand_pose.palm_pitch_deg` changes from 0° to +3° in a new
`family_pistol_4_v5` immutable revision, assigned explicitly to `de__50`.
Every physical socket, gun dimension/mount, hand contact position and other
presentation field stays identical to v3. This translation card records the
proof; it is not a gameplay configuration.

The first serialized v4 candidate passed canonical movement but failed an exact
saved-data reader comparison: reformatting a scientific-notation socket scalar
changed Godot's parsed double by approximately 9e−18 m. No tolerance was added
to hide the difference. V4 remains immutable and unassigned; v5 preserves v3's
original numeric text, changing only revision/id and the intended +3° palm pitch.
Its recursive reader comparison confirms every other visual value is identical.

## Assigned canonical and native proof — MERGE

`tools/de50_support_rotation_probe.gd` loads the assigned v5 without an in-memory
candidate override and checks the real `res://main.tscn` input path. The final
native run, `/private/tmp/de50-v5-native.json`, passes all 436 standing/crouched
A-entry, accepted A-fire, A-to-D reversal, accepted D-fire and ready-to-idle stop
frames. Its runtime source hashes stay unchanged throughout the run, and the
gameplay-contract hash exactly matches the pre-calibration baseline.

During firing, left elbow angle is 115.512–153.129° and right elbow angle is
107.859–146.323°. Across the whole input matrix, maximum palm error is 1.092 mm;
maximum firing bore error is 0.05182°. The unchanged pistol limits remain
38–155°, 1 cm contact error and 1° ready bore. Low-readiness relaxed return is
not misreported as fully aimed; its existing bore weighting is unchanged.

Rear/side native views were inspected at standing/crouched D-fire frame 13 and
standing return-to-idle, alongside the saved early/settled A/D views. Both hands
remain visibly on the pistol and the slight wrist rotation introduces no new
gun placement or hand separation. The inherited high-ready asymmetric arm shape
is still present; this calibration is not a claim that all pistol poses now
look natural. Example reviewed views:

- `/private/tmp/de50-v5-native-de__50_standing_D_fire_frame13-side.png`
- `/private/tmp/de50-v5-native-de__50_standing_D_fire_frame13-rear.png`
- `/private/tmp/de50-v5-native-de__50_crouched_D_fire_frame13-side.png`
- `/private/tmp/de50-v5-native-de__50_standing_returned_idle-side.png`

The complete saved-to-runtime path is `config/weapons/de__50.json:51`
(`"visual_rig_id": "family_pistol_4_v5"`) ->
`config/weapon_visual_rigs/family_pistol_4_v5.json:108`
(`"palm_pitch_deg": 3.0`) -> the existing authored weapon support-palm consumer
in `scripts/player/operator_weapon_authored_pose.gd:163–173`, which composes
`support_socket.global_basis.orthonormalized() * Basis.from_euler(...)` before
the existing support-arm solve. No runtime file was changed for this DE .50
calibration.

## Whole-pistol-family negative controls

The independent final canonical run,
`/private/tmp/pistol-all-eight-final-v5.json`, passes all eight real pistols:
3,488 actual input frames, including 2,032 fully ready frames, 32 accepted-shot
entries and ready-stop recovery. Maximum palm error is 1.142 mm; maximum fully
ready bore error is 0.07064°. Fully ready elbows range from 105.546° to 153.128°.
All eight remain free of rifle-stock ownership/release, and all four observed
runtime source hashes match at start and finish. DE .50 resolves v5; no other
weapon assignment changed.

The shared feature gate currently reports 84 passing contracts and one separate
stale source-literal reference in `pistol_carry_contact_and_pose_boundaries.json`
after the main task's authored-stock fallback edit. The DE .50 feature contract
passes; the aggregate gate must still be rerun after that owning manifest is
updated. Do not report the aggregate gate as passed from the individual results.

Later integration rerun after the owning manifest update:
`/private/tmp/generic-feature-contract-output.log` passes all87 current feature
contracts and exits0. This closes the stale-literal structural-gate issue; it
does not promote the separate generic weapon candidates that fail anatomy.
