# Reload trigger-hand attachment continuity

## Translation card

- Player intent: the weapon remains attached to the trigger hand throughout reload, interruption and completion; magazine/support-hand animation remains free to perform the reload.
- Acceptance: actual trigger-socket to anatomical palm separation stays ≤10 mm through the canonical standing, crouched and prone reload lifecycle; visible weapon/mesh remain present. Reload duration, commit/recovery locks, ammunition conservation and accepted-shot count retain their existing contracts. Non-reload firing retains its current aim/contact bounds.
- One owner: the existing `SocomOperatorWeaponPoseSolver`, through `SocomOperatorWeaponPresentationOwner`, copies the current authored hand mount to its existing presentation anchor; animation continues to own the right arm and orientation. No new process, IK chain, animation take or timer.
- Protected: saved sockets/model transforms, weapon mechanics/reload rates, camera/reticle, movement/collision/network/damage, authored support-hand action path, standing/crouched ready carry and the completed low-readiness release blend.
- Focused proof: canonical reload entry, interrupt-to-fire, restart, ammunition commit, recovery and completion in `tools/reload_trigger_attachment_regression.gd`; physical and diagnostic contact are both recorded. Existing pistol reload and rifle firing/release regressions are negative controls. Native reload review follows a physical pass.

## Existing evidence and candidate

`operator_weapon_pose_actions.gd::_attach_reload_weapon_to_right_hand()` restores the animation parent, then translates by current anatomical palm minus trigger socket. `operator_weapon_authored_pose.gd::apply_action()` subsequently updates support-arm bones, and the engine can resample BoneAttachment transforms after the already-applied local correction. Original and current M16 profiles both show approximately 381/281/32 mm standing/crouched/prone trigger gaps in the independent canonical negative-control probe, despite unchanged reload mechanics.

Before changing runtime, the focused proof must confirm that the reported immediate contact and actual late-frame socket differ. The candidate uses the already-existing world presentation anchor and `_weapon_transform_on_trigger_hand(..., true)` to reconstruct the immutable mount from the current authored right palm each frame. The logical owner stays `RELOAD_RIGHT_HAND`; `weapon_solver_owned` remains false, because this is animation-owned presentation, not right-arm aim IK. The existing presentation boundary remains the only transform writer.

## System delta (0–5)

| Axis | Existing | Candidate | Evidence |
| --- | ---: | ---: | --- |
| Correctness | 2 | 4 provisional | Actual reload trigger contact differs from immediate local correction |
| Ownership clarity | 4 | 5 | Existing explicit presentation boundary; authored arm remains sole motion source |
| Canonical parity | 5 | 5 | Same saved mount and canonical driver/reload coordinator |
| Editor usability | 4 | 4 | No new fields or calibration workflow |
| Performance | 5 | 5 | One rigid mount reconstruction, no IK/search/timer |
| Regression coverage | 3 | 5 provisional | Actual lifecycle contacts, lock/commit/ammo and accepted-shot assertions |

Decision **MERGE conditionally**, only after current-frame physical contact evidence and unchanged gameplay lifecycle pass. Do not move socket coordinates, change reload timing, clamp the hand to a convenient target, or add a second transform owner to satisfy the test.

The focused baseline reproduced470 canonical frames: actual maximum trigger errors379.95/280.19/32.03mm versus immediate reported errors below0.101mm. This confirms a final-frame attachment mismatch rather than an inaccurate contact reader. The candidate now reconstructs the existing saved mount on the presentation anchor with `weapon_solver_owned=false`; right-arm animation remains the source. `tools/retro_1212_reload_regression.gd` extends the same lifecycle proof using each unassigned model's normal equipment-presentation handoff, without changing saved assignments. Native verification remains required.

## Verified trigger-attachment result

### Completion-frame source ownership — bounded follow-up

The 1212 pump's last prone reload source remains evaluated when `_update_requested_action()` clears the logical action at priority 100. An immediate support solve requests an unreachable 177.88-degree elbow and leaves a 45.44 mm gap; even full weight cannot solve that geometry. Intent: finish reload without prematurely treating its final authored pose as idle. Acceptance: the existing weapon presentation call retains the evaluated reload action/regrip on that completion frame only, then follows the next actual idle-source frame with support contact ≤10 mm. Interrupt-to-fire must not retain reload ownership. One owner: existing animation driver forwards its already-evaluated source to the existing weapon solver. Protected: logical action completion, ammo/locks/timers, input acceptance, source animations, bones/sockets, camera/movement/network and unrelated driver changes. No new timer, tree evaluation or delayed gameplay event. Focused proof: priority-99 source observer plus all three canonical candidate reload lifecycles and exact interruption shot count. Six-axis delta: correctness2→4 conditional, ownership5→5, canonical parity5→5, editor4→4, performance5→5 (two local values), regression coverage4→5. **MERGE only if source, contact and unchanged lifecycle checks pass.**

The isolated native run `/private/tmp/reload-attachment-reviewed-native-reload.json` passed 1,410 measured frames and all nine standing/crouched/prone lifecycles for M16A2, M4A1 and Mark 23. Runtime source hashes stayed identical from start to finish; the gun and its mesh remained visible, and exactly the requested interrupt shots were accepted. Maximum actual trigger separation across the full lifecycle was 0.795 mm for M16, 0.788 mm for M4 and effectively zero for Mark 23. During active reload it was at most 0.031 mm. The existing resolved durations (1.75 s standing/crouched and 2.1333 s prone for these fixtures), commit/recovery locks and ammunition conservation passed unchanged. Native pre-interrupt side views were reviewed for all nine cases.

The independent post-change firing negative control `/private/tmp/resumed-fire-negative.json` passed 2,180 frames across AK, M4, M16, M40 and Mark 23. The unassigned 1212 Uzi/pump reload extension also passed 1,412 frames/six lifecycles for trigger attachment, with maxima of 0.375/0.448 mm.

Completion-source follow-up PASS: `/private/tmp/reload-source-final-reload.json` measured 1,412 frames/six lifecycles for the unassigned pump/Uzi. Exactly six final evaluated reload frames retained authored ownership, then 180 actual idle-source frames had support contact within 0.746 mm. Interruptions retained their exact shot/ammunition behavior. Native pump proof `/private/tmp/reload-source-native-reload.json` passed 942 frames/three lifecycles, with actual idle support within 0.547 mm. All six synchronous captures preserved their CPU source, restored the camera and showed the correct visible model after render-resource flushing; standing reload and completed-prone side views were inspected. This fixes the one-frame **ownership misclassification**, not the separate prone barrel/floor pose. M16/Mark 23 negative controls subsequently passed 940 frames/six lifecycles in `/private/tmp/reload-source-controls-reload.json`. The earlier all-eight-pistol reload check passed 3,588 frames/24 lifecycles before this follow-up. Structural feature gate passes all 89 contracts. The aggregate quick integration gate refuses `codex/render-deployment` because it requires `main`; branch and unrelated work were preserved.

Decision: **MERGE the trigger-attachment correction**. This approves the physical trigger mount, not new magazine choreography or all support-hand transitions. Mark 23 still uses its shared reload action; the 1212 pump has a separately tracked 45.442 mm support-hand regrip gap on its first post-action prone frame. Its model remains unassigned until that and its prone-aim gate pass. Preserve `/private/tmp/reload-attachment-baseline-reload.json` as the failing original, not as candidate proof.
