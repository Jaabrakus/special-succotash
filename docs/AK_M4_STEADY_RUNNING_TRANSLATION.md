# AK/M4 steady running and firing — latest translation

LATEST OVERRIDE: the user subsequently said to KEEP head bob. Vertical
suppression was removed completely, including mean-height sampling and Spine
position writes. Keep natural hip-driven head motion; the remaining steadiness
request concerns side-to-side shoulder sway and direction, not vertical motion.
The user also clarified full A/D LEG turning, and explicitly retained barrel
aim at the reticle. See RIFLE_LATERAL_LEGS_TRANSLATION.md. The text below records
the prior diagnostic intent, not permission to restore removed bob suppression.

Player intent: remove shoulder sway and head bob. Running without firing keeps
the shoulders square in every direction. Only accepted-fire/recovery enters the
asymmetric firing stance: A stays square with right-elbow flare; D turns toward
the right while the head and rifle retain the reticle direction. Arms must not
fold into the chest. This supersedes activating the D torso turn before fire.

Acceptance: quantify head/chest height and rotation over complete movement
cycles, then suppress the gait-induced upper-body drift through the existing
pose owner. Legs continue their existing phase; camera and player body motion
are unchanged. Transition into/out of the firing stance uses existing readiness
and 1.2-second recovery, not a new timer or animation restart. Keep palm, bore,
stock, and elbow checks; a folded arm is a failure even when endpoints align.

One owner: the existing animation driver/posture layer owns upper-body
stabilization and directional stance selection; the existing weapon pose owner
owns gun and hand contact. No new update loop or competing skeleton writer.

Chain: movement/accepted fire -> existing animation-driver input -> shared
weapon handling profile -> posture and weapon presentation consumers -> stable,
square un-fired running and directional firing in canonical main.tscn.

Protected: CharacterBody3D and collision, camera/reticle, authoritative shots,
gait phase, reload/prone/mobility, other weapons, saved contact points and bone
lengths, unrelated work. Do not flatten the entire gait to remove head motion.

Initial code evidence: `operator_animation_driver_state.gd` retains0.18 gait
roll; `operator_posture_layer.gd` cancels hip rotation but not translation. The
ready mask begins at Spine, so hip movement can still propagate to head and
shoulders. `locomotion_weapon_shoulder_sway_gain` is already0, so changing it
would not fix the observed motion. Full-cycle measurement is required before
choosing any additional translation correction.

Focused proof: before/after canonical per-cycle head/chest ranges; signed A/D
shoulder direction before fire and during recovery; source gait phase and lower
bones unchanged; physical gun/hand measurements; no accumulation or posture
entry snap; rendered rear/side review; existing recoil, pistol, continuity and
feature-contract gates. Keep the failed full-D build unpublished.

System delta (0–5), conditional MERGE after proof: correctness2->4 (the new
un-fired running rule and sway suppression), ownership5->5 (existing writers),
runtime parity5->5 (canonical graph), editor usability4->4 (saved scoped data),
performance4->4 (bounded pose math), regression coverage2->4 (cycle geometry and
before-fire/firing transitions). Reject fixes that hide arm collapse or move
camera/player physics to make the measurements pass.
