# Character Presentation Simplification Plan

Status: Active plan
Created: 2026-08-23
Scope: Playable operator animation, weapon attachment, aim presentation, and Lab previews

## Goal

Make the character presentation system smaller, easier to tune, and harder to regress while preserving the SOCOM-141 vision.

The target behavior is:

1. Authored animation moves the body, arms, hands, and attached rifle.
2. The rifle stays attached to the animated right hand.
3. A ready transition brings the rifle from low carry to eyesight.
4. The blue sight line supplies the desired aim target.
5. Bounded torso and arm correction brings the hand-attached rifle rail toward that target.
6. The left hand follows the weapon foregrip after the right-hand pose is complete.
7. Gameplay aim, muzzle validation, shots, damage, and multiplayer authority remain separate from visual animation.

## Protected Behavior

These features must continue to work throughout the cleanup:

- [ ] Standing reload remains visually correct.
- [ ] Reload timing remains synchronized with ammunition transfer.
- [ ] Eight-direction rifle locomotion moves the complete body and both hands.
- [ ] The rifle follows the right hand in every locomotion direction.
- [ ] Low carry blends smoothly into ready aim.
- [ ] Ready aim brings the rifle and muzzle toward eyesight.
- [ ] The blue sight line remains directed toward the reticle target.
- [ ] Fire remains a temporary action and returns to the correct current movement state.
- [ ] Crouch and prone retain their own body posture and locomotion.
- [ ] Jump, dive, grenade, and mobility actions retain their approved full-body behavior.
- [ ] Reticle kick, bloom, composure, and recoil behavior remain unchanged.
- [ ] Visual animation never redirects the authoritative shot.
- [ ] Multiplayer replicates intent and gameplay state, not individual bone transforms.

## Authority Boundaries

| Responsibility | Source of truth |
| --- | --- |
| Position, velocity, stance, and collision | `CharacterBody3D` player controller |
| Camera yaw, pitch, and reticle target | Camera and aim resolver |
| Shot validation, muzzle, ballistics, and damage | Weapon and server authority |
| Base locomotion and action appearance | Operator AnimationTree |
| Weapon mount and weapon sockets | Gunsmith weapon profile |
| Blue-line aim correction | Bounded visual presentation modifier |
| Left-hand foregrip contact | Final support-hand IK pass |
| Foot contact and uneven terrain | Final grounding pass |

No presentation system may move the authoritative character body or change the accepted shot direction.

## Current Root Problems

### Multiple weapon owners

The rifle starts correctly under a `BoneAttachment3D` on the right hand. The current pose solver can later reparent it to `WeaponSolverAnchor` and write its world transform. That creates competing ownership between animation, the hand attachment, and the solver.

Relevant files:

- `scripts/player/operator_asset_runtime.gd`
- `scripts/player/operator_weapon_pose_solver.gd`
- `scripts/player/weapon_ownership_contract.gd`

### Directional animation is partially hidden

Ready aim currently overlays Aim Idle on directional locomotion and retains only a small amount of moving upper-body animation. The legs move more than the hands and rifle, so the weapon can look pinned.

Relevant file:

- `scripts/player/operator_locomotion_blend_tree.gd`

### Runtime frame correction is too powerful

Saved frame keys can alter joints, hands, elbows, and the weapon while gameplay is running. These corrections can fight the animation graph and IK. Approved corrections should be baked into animation data when possible.

Relevant files:

- `scripts/player/operator_animation_frame_pose_runtime.gd`
- `scripts/labs/animation_correction_overlay.gd`
- `scripts/labs/animation_studio/animation_studio_pose_authoring.gd`

### Labs reproduce runtime behavior

Gunsmith and Animation Studio contain independent weapon, animation, IK, and ownership preview logic. A Lab can therefore look correct while the playable character uses different rules.

Relevant files:

- `scripts/labs/gun_calibration_lab.gd`
- `scripts/labs/animation_studio/animation_studio_weapon.gd`
- `scripts/labs/animation_studio_arm_ik_preview.gd`
- `scripts/labs/animation_studio_weapon_ownership_preview.gd`

## Target Runtime

```text
Accepted gameplay state and events
                |
                v
      Operator Presentation Router
                |
                v
       One AnimationTree graph
        |                 |
        |                 +-- Fire / reload / grenade one-shots
        |
        +-- Eight-direction low-carry locomotion
        +-- Raise-rifle transition
        +-- Eight-direction ready locomotion
                |
                v
       Bounded posture and aim pass
                |
                v
     Right hand carries attached rifle
                |
                v
         Left-hand foregrip IK
                |
                v
          Foot grounding pass
```

## Components to Keep

- Player movement, collision, and stance controller.
- Camera aim resolver and reticle.
- Weapon controller, ballistics, muzzle validation, and damage.
- Gameplay event dictionary and presentation router.
- One canonical operator AnimationTree.
- Right-hand `BoneAttachment3D` and saved Gunsmith mount transform.
- Weapon muzzle, barrel base, optic, ejection, trigger, and foregrip sockets.
- Working reload behavior and reload timing coordinator.
- Bounded posture, obstruction, support-hand IK, and grounding.
- Multiplayer server authority and intent replication.
- Focused regression tests for protected behavior.

## Components to Remove or Reduce

### Weapon ownership and placement

- [ ] Stop `READY_SOLVER` from becoming a second rifle parent.
- [ ] Remove ready-state rifle world-transform writes.
- [ ] Remove ready-state ownership-return interpolation.
- [ ] Remove duplicate trigger-hand contact corrections after permanent attachment is verified.
- [ ] Keep the current reload path unchanged until its characterization test passes against the simplified attachment.
- [ ] After verification, determine whether reload can use the permanent hand attachment without its current follow bridge.
- [ ] Reduce the ownership contract to action and body-layer policy instead of rifle parenting policy.
- [ ] Remove the unused compatibility wrapper `scripts/player/operator_weapon_ownership_contract.gd` after updating its regression test.

### Locomotion and state graph

- [ ] Keep one locomotion route. Remove the legacy/modern dual route after parity verification.
- [ ] Build one low-carry eight-direction blend space.
- [ ] Build one ready-aim eight-direction blend space.
- [ ] Add a short raise-rifle transition between them.
- [x] Remove the `ready_locomotion_inheritance` percentage workaround; bounded gait carry now comes from the weapon-pose solver.
- [ ] Keep fire as a filtered one-shot overlay.
- [ ] Keep reload posture-aware and preserve its current correct standing behavior.
- [ ] Return actions to the current base state instead of a hard-coded idle.

### Procedural presentation

- [ ] Replace the large weapon pose solver with bounded responsibilities:
  - Aim/raise modifier.
  - Support-hand IK.
  - Obstruction modifier.
- [ ] Apply procedural work after the authored animation sample.
- [ ] Use one ordered skeleton modification pass per rendered frame.
- [ ] Remove repeated clear/force-update cycles when the final modifier order is stable.
- [ ] Cache bone indices and socket references.
- [ ] Avoid per-frame dictionary duplication and configuration parsing.

### Animation corrections

- [ ] Keep frame editing in Animation Studio.
- [ ] Add an approval and bake step.
- [ ] Save baked clips to the shared AnimationLibrary.
- [ ] Stop reading detailed frame-correction JSON during normal gameplay.
- [ ] Remove runtime weapon position corrections that bypass hand attachment.
- [ ] Retain only small named additive corrections that cannot be represented in a baked clip.

### Gunsmith

Gunsmith should own only:

- Weapon dimensions, mesh, and skin.
- Right-hand local mount transform.
- Left-hand foregrip socket.
- Muzzle and barrel-base sockets.
- Optic/rail and ejection sockets.
- Blue-line calibration offsets.
- Weapon statistics and composure links.

Remove or relocate from Gunsmith:

- [ ] Animation browsing and state routing.
- [ ] Animation frame correction authoring.
- [ ] Independent arm IK implementation.
- [ ] Independent weapon ownership implementation.
- [ ] Bone restructuring and posture correction.
- [ ] Duplicate playtest behavior.

### Animation Studio and previews

- [ ] Instantiate the same operator presentation runtime used by gameplay.
- [ ] Send preview events through the shared presentation router.
- [ ] Remove separate preview-only arm and weapon ownership solvers.
- [ ] Make Preview Fire, Reload, Jump, and Grenade use the same runtime routes as playtest.
- [ ] Keep editing controls separate from playback ownership.

### Configuration

Consolidate overlapping animation configuration into three clear profiles:

1. `CharacterPresentationProfile`
   - Animation slots.
   - Event routes.
   - Body layers.
   - Transition times.
   - Retargeted/baked clips.
2. `WeaponRigProfile`
   - Mount transform.
   - Weapon sockets.
   - Blue-line offsets.
   - Bounded support-hand calibration.
3. Gameplay profiles
   - Weapon statistics.
   - Composure and reticle tuning.
   - Reload timing.
   - Damage and ballistics.

- [ ] Retire duplicate or superseded animation routing documents after migration.
- [ ] Keep gameplay tuning separate from visual presentation tuning.
- [ ] Validate every saved Lab profile before it becomes the current playable profile.

## Large-File Targets

Line count is not the only measure, but these targets prevent ownership from collecting in one file again.

| File | Current approximate size | Target |
| --- | ---: | ---: |
| `scripts/player/operator_weapon_pose_solver.gd` | 2,045 | Replace with focused components under 500 lines each |
| `scripts/player/operator_animation_driver.gd` | 1,347 | Under 500 lines |
| `scripts/player/operator_locomotion_blend_tree.gd` | 718 | Under 500 lines |
| `scripts/player/operator_posture_layer.gd` | 736 | Under 500 lines |
| `scripts/player/operator_asset_runtime.gd` | 940 | Under 500 lines |
| `scripts/labs/gun_calibration_lab.gd` | 6,664 | Thin controller plus focused UI/services |

Do not split a large file only to satisfy a line limit. First remove duplicate behavior and define one owner. Then extract cohesive components.

## Migration Phases

### Phase 0 — Protect the current game

- [ ] Create a restore-point commit.
- [ ] Record the approved standing reload.
- [ ] Add a focused standing reload attachment regression.
- [ ] Add an eight-direction hand/rifle-follow regression.
- [ ] Add a low-carry-to-ready regression.
- [ ] Add a muzzle/reticle authority regression.
- [ ] Add crouch, prone, jump, and dive presentation checks.

Exit condition: tests describe the behavior we must preserve before ownership code changes.

### Phase 1 — One rifle attachment

- [ ] Keep the rifle under the right-hand `BoneAttachment3D` during ordinary locomotion.
- [ ] Remove ready-state reparenting.
- [ ] Remove ready-state direct weapon transform writes.
- [ ] Preserve the current reload route.
- [ ] Verify all eight locomotion directions.

Exit condition: the rifle follows the animated right hand in every ordinary movement state and reload remains correct.

### Phase 2 — Two authored locomotion families

- [ ] Connect the low-carry eight-direction clips.
- [ ] Connect the ready-aim eight-direction clips.
- [ ] Add the raise-rifle transition.
- [ ] Remove the percentage inheritance workaround.
- [ ] Verify direction changes and contextual action returns.

Exit condition: the complete body remains alive during low carry and ready movement.

### Phase 3 — Blue-line body solve

- [ ] Convert the blue sight target into a bounded torso/right-arm target.
- [ ] Keep the rifle attached to the right hand throughout the solve.
- [ ] Apply left-hand foregrip IK after the right arm.
- [ ] Add joint limits and unreachable-target handling.
- [ ] Verify standing, crouched, and prone aim.

Exit condition: the body brings the rifle toward eyesight without detaching the weapon or twisting the arms.

### Phase 4 — One preview and runtime

- [ ] Make Animation Studio instantiate the gameplay presentation rig.
- [ ] Make Gunsmith use the same rig for preview.
- [ ] Remove preview-only ownership and IK solvers.
- [ ] Verify Lab-to-play parity.

Exit condition: the same event and profile produce the same pose in every Lab and in `main.tscn`.

### Phase 5 — Bake corrections

- [ ] Add review and approval for animation corrections.
- [ ] Bake approved corrections into playable clips.
- [ ] Remove runtime frame correction paths that are no longer needed.
- [ ] Validate transitions and reload after baking.

Exit condition: ordinary gameplay does not interpret detailed editor correction keys every frame.

### Phase 6 — Delete replaced code

- [ ] Remove obsolete ownership modes and compatibility wrappers.
- [ ] Remove legacy locomotion routing.
- [ ] Remove duplicate preview solvers.
- [ ] Remove superseded configuration fields and migrations.
- [ ] Update the integration manifest and regression suite.
- [ ] Run the quick integration gate.
- [ ] Create a verified restore-point commit.

Exit condition: no dead route can regain control of the rifle, arms, or animation state.

## Verification Matrix

| Scenario | Body/animation owner | Rifle owner | Required result |
| --- | --- | --- | --- |
| Standing idle, low carry | Low-carry base animation | Right hand | Natural idle motion |
| Eight-direction run | Directional base animation | Right hand | Rifle follows animated hands |
| Enter ready aim | Raise transition | Right hand | Rifle rises smoothly toward eyesight |
| Eight-direction ready movement | Ready directional animation plus bounded aim | Right hand | Aim stays useful without a pinned torso |
| Fire | Upper-body one-shot | Right hand | Temporary fire action, contextual return |
| Standing reload | Working reload action | Current verified reload path | No regression |
| Crouched reload | Crouched base plus reload layer | Verified action path | Legs remain crouched |
| Prone locomotion | Prone base animation | Right hand | Rifle respects floor and body |
| Jump/dive | Full-body mobility action | Right hand/action path | Weapon stays connected |
| Obstruction | Bounded upper-body modifier | Right hand | Visual tuck without redirecting shot |

## Definition of Done

- [ ] One system selects character presentation states.
- [ ] One AnimationTree plays the base and action layers.
- [ ] The right hand is the normal rifle owner.
- [ ] Eight-direction motion reaches the hands and rifle.
- [ ] The blue line brings the connected upper body and rifle toward eyesight.
- [ ] The left hand remains on the foregrip without extreme elbow deformation.
- [ ] Reload remains correct.
- [ ] Labs and playtest show the same result.
- [ ] Animation remains visual only.
- [ ] No removed compatibility path can write the rifle world transform.
- [ ] Focused regressions and the quick integration gate pass.

## Decision Log

| Date | Decision | Reason |
| --- | --- | --- |
| 2026-08-23 | Preserve the current standing reload during the cleanup. | The reload is already visually correct. |
| 2026-08-23 | Keep the rifle attached to the animated right hand during ordinary locomotion. | The eight-direction animations must move the weapon naturally. |
| 2026-08-23 | Use the blue line as a target for the connected torso/arm chain. | The operator must bring the rifle and muzzle toward eyesight realistically. |
| 2026-08-23 | Keep gameplay aim and shot authority independent from presentation. | Visual correction must never change accepted gameplay results. |
