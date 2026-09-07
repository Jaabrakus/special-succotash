# AK/M4 directional right elbow — translation card

Player intent: Leftward strafing flares the trigger-side right elbow while the
rifle stays on its existing shoulder/hand contacts. This supplements the
asymmetric torso carry; it does not force the player to aim or fire.

Acceptance: An opted-in AK/M4 in standing or crouched locomotion receives at most
the saved left-strafe angle, plus its existing accepted-shot recoil, with a
combined 20-degree cap. The right shoulder origin, wrist transform, weapon root,
and left/support-hand endpoint remain unchanged by this swivel. Rightward,
stationary, prone, airborne, dive, roll, and action states receive no carry flare.

One owner: The existing operator weapon-pose owner applies one endpoint-preserving
right-arm-plane swivel after its existing hand/weapon solve. The recoil helper
provides reusable angle math; no new runtime node or pose writer is introduced.

Saved contract: `handling_profile.dynamic_hold.strafe_carry.left_elbow_flare_degrees`
defaults to zero. The main change opts in AK/M4 only. The animation driver passes
an optional signed, already-smoothed strafe weight into the existing pose call;
this helper does not read velocity or own a second movement clock.

Protected: CharacterBody3D, camera/reticle, shots/damage, networking, readiness,
the 1.2-second fire recovery, existing recoil envelope, reload/mobility, canonical
weapon/socket transforms, left-hand contact, other weapon profiles, and all
unrelated edits.

Focused proof: `tools/directional_elbow_swivel_regression.gd` verifies profile
reset/default, left-only guards, angle cap, fixed shoulder/wrist/support/root,
and unchanged legacy recoil API. The main integration performs real AK/M4
standing/crouch left/right fire captures before visual approval.

System delta: MERGE the existing accepted-shot endpoint-preserving operation as
one combined angle; reject a separate arm IK or weapon-root offset. Scores are
conditional on tests and visual review: correctness 3->4, ownership 5->5,
runtime parity 4->4 until driver wiring, editor usability 3->4, performance 4->4,
regression coverage 3->4. Evidence: `operator_fire_recoil_pulse.gd`,
`operator_weapon_pose_ready.gd`, `operator_weapon_pose_api.gd`, and the focused
regression. No authored animation asset is introduced.
