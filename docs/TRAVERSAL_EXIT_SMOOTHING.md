# Climb and vault exit smoothing

## Neutral-pose handoff correction (2026-09-12)

Intent: no neutral-pose pause when a climb finishes. Acceptance: recovery is
already blended over the final climb frames, and its upper-body pose remains
live during exit settling. Owner: the existing animation driver/graph and its
traversal modifier. Movement, camera, shot authority and network state stay
unchanged. Proof: traversal hand-contact, exit-pose and main-vault regressions,
plus `tools/modern_climb_visual_check.gd` through `main.tscn`.

`config/traversal_weapon_stow.json` starts recovery at traversal phase 0.82,
after hand support releases, sampling the source at phase 0.20 to omit its
neutral entry. The same draw continues across the boundary without restarting.
`operator_traversal_hand_modifier.gd::_apply_exit_pose` skips the Spine subtree
when `exit_live_upper_body` is true. The lower-body snapshot still blends out;
the existing graph remains the upper-body writer. Gun visibility still requires
both completed exit settling and evaluated hand transfer. Combat can interrupt.

MERGE delta (correctness, ownership, runtime parity, editor usability,
performance, regression coverage): sequential full-body hold (2,4,5,4,5,2) ->
overlap with live upper-body recovery (4,5,5,4,4,4). Evidence: the runtime
coordinator, saved stow profile, modifier and the three focused regressions.
The synthetic check proves that a new forearm pose survives exit weight 1 at
30/60/120 Hz. Source neutral frames remain unmodified. This does not certify
every obstacle height or perfect boot contact.

Validation checkpoint: exit-pose regression PASS; physical tall-climb contact
and live-upper-body overlap PASS; low-vault exit and equip lifecycle PASS;
134 feature contracts PASS. Rendered early/middle/late exits were inspected
from both sides. The editor scan completed without script parse errors but
sandbox restrictions prevented saving its global help cache/editor settings.
The quick integration wrapper stops at `tools/run_integration_gate.sh:18`
because this worktree is `codex/render-deployment`, not `main`.

Separate broader check: M4 vertical-slice regression still fails two saved
socket-equality assertions. `config/weapons/m4a1.json` left-hand target Y is
0.055, while both immutable v9 and cloned v10 publish 0.1008046943. This mismatch
predates the reload-only v10 change and was not overwritten. Its live bore and
support-palm checks passed; six ISO weapon/stance reload lifecycle checks passed.

## Translation card

- Intent: settle from the last rendered climb/vault pose into responsive locomotion without a body snap.
- Acceptance: capture the evaluated pose, blend it out over saved time, release all pose influence, and never restart traversal or delay movement.
- Owner: existing operator animation driver and its existing traversal SkeletonModifier3D presentation stage.
- Unchanged: CharacterBody collision/motion, camera/aim, weapon visibility/timing, reload, shots/damage, networking, traversal eligibility.
- Proof: focused exit-pose regression plus physical jump/climb and low vault through `main.tscn`, rendered exit frames from both sides, feature contract gate.

## Delta: MERGE

Current exit immediately clears wall-facing/contact corrections in `operator_animation_driver_runtime.gd::_advance_traversal_presentation`; the AnimationTree crossfade alone cannot retain that post-animation pose.
Candidate extends the existing modifier with a bounded local-bone snapshot handoff. It reads the live destination each evaluation, never world-locks the character, and cancels on new traversal or death. No second movement or animation node.

Scores (current -> candidate): correctness 2->4, ownership clarity 5->5, canonical parity 5->5, editor usability 3->4 (saved `exit_transition.seconds`), performance 5->4 (one bounded bone pass), regression coverage 2->4. Evidence: runtime coordinator, traversal modifier, shared ledge profile and `tools/traversal_exit_pose_regression.gd`.

Godot 4.7.1: the modifier snapshot is taken during evaluated skeleton processing, not from restored post-frame source poses. Existing AnimationTree crossfades remain in place. Official API references: https://docs.godotengine.org/en/latest/classes/class_skeletonmodifier3d.html and https://docs.godotengine.org/en/latest/classes/class_animationnodetransition.html .

## Added translation card: hang elbows

- Intent: supported hang elbows bend away from the head rather than folding beside it.
- Acceptance: a saved wall-relative elbow pole guides the existing analytic arm solve; fixed wrist targets remain within 3cm, authored wrist rotation and bone lengths stay intact, and the pole releases with each hand.
- Owner: the same traversal hand modifier; no new IK chain.
- Unchanged: source clips, handhold width/reach, CharacterBody, camera, weapons and traversal clocks.
- Proof: pole regression plus rendered braced and actual warehouse free-hang from both sides.
- Delta MERGE: source bend plane alone (correctness 2, ownership 5, parity 5, usability 2, performance 5, coverage 3) versus bounded saved pole in the existing solve (4,5,5,4,5,4). Evidence: `_elbow_bend` and contact regressions. The pole is presentation only and cannot expand reach or move wrists.

## Weapon recovery card (user clarification)

Rendered exit exposed a held-weapon/late-bone conflict despite passing body/contact checks. Keep the real gun hidden and the sling copy visible while the exit modifier owns the pose. Then sample the imported AGLS equip take as an upper-body layer in the existing AnimationTree, before the weapon attachment consumer. Release the left support solve while the authored equip hands reach; restore normal two-hand ownership afterward. Ready/fire/reload/new traversal cancel cosmetic recovery, never delay gameplay. No source clips overwritten, no new weapon/damage owner. Review actual transfer and wrists, not just visibility.

MERGE scores current->candidate: correctness 1->4, ownership 3->5, parity 5->5, usability 2->4, performance 5->4, coverage 2->4. Evidence: rendered climb-exit frames, traversal equip layer, existing weapon presentation owner and recovery regression. Entry unequip is separate: an airborne grab must not be delayed to finish a stow gesture.
