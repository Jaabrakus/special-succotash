# Nine-file responsibility extraction

**Current status (retry): all nine extractions implemented and original file
budgets pass.** The five-file checkpoint below is historical. See the final
retry section and `PISTOL_MOVEMENT_CONTACT_RETRY.md` for current proof and limits.

## Translation card

1. Player intent: unchanged play, easier maintenance and contributor handoff.
2. Acceptance: all nine identified oversized scripts meet existing budgets;
   extracted paths preserve public calls, calculations and execution order.
3. Owner: each existing runtime coordinator retains its authority; helpers
   perform bounded construction or calculations, not independent updates.
4. Must not change: movement, aim, shot/damage authority, animation values,
   weapon attachments, mode rules, active assets, art direction and exports.
5. Proof: file budgets, feature contracts, focused map/HUD/grenade/retarget/
   locomotion/weapon-pose regressions, canonical boot, visual comparison where
   presentation is extracted. Record pre-existing failures separately.

## Planned boundaries

- Map runtime: surface materials and facade construction.
- Retarget lab: reusable skeleton inspection utilities.
- Gameplay HUD: construction separated from live updates/input.
- Grenade runtime: equipment wheel/selection separated from throw lifecycle.
- Test mannequin: procedural primitive construction utilities.
- Weapon ready: separate ownership-specific presentation paths.
- Locomotion blend tree: graph construction separated from live transitions.
- Weapon kinematics: bounded aim/contact calculations.
- Weapon placement: roll calculation separated from placement orchestration.

## System-delta review

Decision: MERGE focused extractions, not a gameplay rewrite.

Scores are architectural assessments, not completed test claims (0–5):

| Criterion | Current | Candidate | Evidence |
| --- | --- | --- | --- |
| Correctness | 4 | 4 | Same function bodies and focused runtime tests |
| Ownership clarity | 2 | 4 | Nine named scripts above retain one runtime owner |
| Canonical parity | 4 | 4 | Existing scene consumers and saved profiles unchanged |
| Editor usability | 3 | 4 | Named helper responsibilities, unchanged lab interfaces |
| Performance | 4 | 4 | No additional processing nodes or duplicated updates |
| Regression coverage | 3 | 4 | Existing behavior tests plus boundary/budget proof |

Current evidence: `tools/god_file_budget_regression.gd`, the nine source files,
and `docs/CONTRIBUTOR_BOUNDARY_PASS.md`. Candidate scores remain provisional
until extraction checks pass. Do not infer complete modularity or internet
readiness from file sizes. Ordinary Quick Match selection and remote load
testing remain separate work.

## Checkpoint: five complete, four deferred

| Coordinator | Before | After | Existing ceiling |
| --- | ---: | ---: | ---: |
| `scripts/maps/socom_map_runtime.gd` | 2008 | 1297 | 1400 |
| `scripts/labs/retarget_mapping_lab.gd` | 1036 | 989 | 1000 |
| `scripts/runtime/main_gameplay_hud.gd` | 643 | 462 | 500 |
| `scripts/runtime/main_grenade_runtime.gd` | 753 | 464 | 500 |
| `scripts/player/test_mannequin.gd` | 1001 | 968 | 1000 |

All eight extracted helpers are synchronous `RefCounted` scripts under 500
lines. They have no frame callback. The existing coordinators retain their
state, public entry points, scene parenting and update order. The grenade model
list also feeds thrown projectiles, so its runtime constant aliases the held
visual helper's list rather than duplicating it.

Exact delegation examples:

- `scripts/maps/socom_map_runtime.gd:221`:
  `return FacadeBuilder._build_favela_building(object)`
- `scripts/runtime/main_gameplay_hud.gd:130`:
  `HudBuilder._build_ui(self)`
- `scripts/runtime/main_grenade_runtime.gd:318`:
  `return EquipmentSelection.open_equipment_wheel(self)`
- `scripts/player/test_mannequin.gd:935`:
  `var part := ProxyPrimitives._box_on(parent, part_name, size, position, material)`
- `scripts/labs/retarget_mapping_lab.gd:203`:
  `target_skeleton = SkeletonInspection._find_skeleton(target_root)`

### Passed

- Construction boundary regression; unchanged size ceilings for these five.
- Map creation regression before and after extraction.
- Morro do Sol V2 full map/architecture/collision and canonical consumer check.
- Community map workflow.
- Retarget mapping regression before/after, plus rendered capture reviewed at
  `/private/tmp/socom-retarget-mapping-lab.png` (existing calibration warnings
  remain visible; this is not a claim to fix the source rig).
- Equipment wheel regression before/after: selection, cancellation, rifle
  restoration, camera yaw, inventory, committed-throw protection.
- HUD/scorecard regression before/after.
- Grenade throw visual-state regression: hand attachment scale, pre-release
  visibility, physical release, authored motion and final-frame completion.
- 61 feature contracts, including updated construction source locations.
- Editor parse (no script errors), canonical `main.tscn` headless boot and
  whitespace check.

### Not passed / not completed

- `tools/pistol_standing_movement_placement_regression.gd:47` failed **before
  gameplay edits** in twelve standing/crouched movement-entry samples. Its
  `_expect_contacts` path requires physical palm contact within 1 cm; one
  standing sample measured 0.076035 m support-hand error. Settled and firing
  samples passed. The SOCOM workflow hard-stop requires resolving or isolating
  this owner before changing the affected animation system. Therefore these
  four files remain unchanged by this pass: weapon pose ready (660), locomotion
  blend tree (1144), weapon kinematics (770), weapon placement (513).
- Full file-budget gate still fails those four; no ceilings were raised.
- Separate grenade timeline regression fails because
  `scripts/tactical/grenade_animation_release_timeline.gd:13` declares recovery
  fractions `1.0`, while `tools/grenade_animation_release_timeline_regression.gd:19`
  rejects `recovery >= 0.95`. Neither source was modified by this pass. Do not
  change timing or relax the assertion merely to obtain a green result.
- Integration quick gate stops at `codex/render-deployment`; it requires
  `main`. Branch/worktree preserved. No commit, push or browser export.
- Existing environment warnings: macOS certificate lookup, editor-settings
  permissions/ADB, duplicate M16A2 UID and SubMachineGun filename case.
- No internet/32-player capacity proof was performed.

The next required choice is a bounded repair of the pistol movement-entry
contact failure before refactoring the four dependent animation files. This
checkpoint is **not** completion of the requested nine-file refactor.

## Retry: remaining four extracted

| Coordinator | Before | After | Unchanged ceiling |
| --- | ---: | ---: | ---: |
| `scripts/player/operator_weapon_pose_ready.gd` | 660 | 473 | 500 |
| `scripts/player/operator_weapon_pose_kinematics.gd` | 770 | 490 | 500 |
| `scripts/player/operator_weapon_pose_placement.gd` | 513 | 479 | 500 |
| `scripts/player/operator_locomotion_blend_tree.gd` | 1144 | 871 | 1000 |

The pistol movement-entry blocker was repaired first, with completed-frame
physical contact measurements. See the linked retry report for the two causes.
The four extractions then delegate existing calculations/construction without
adding processing nodes or altering scene ownership:

- Ready: `AuthoredPose.apply_hand_follow(self, ...)` at line 101; the action
  route immediately above delegates separately to `apply_action`.
- Kinematics: `AimAlignment._align_weapon_to_aim(self, ...)` at line 360.
- Placement: `return AimAlignment._measure_gunsmith_weapon_roll_error(self, ...)`
  at line 253.
- Locomotion: `ModernRouteBuilder.build(self, root, available_clips)` at line 766.

Helper sources are `operator_weapon_authored_pose.gd`,
`operator_weapon_aim_alignment.gd`, and `operator_locomotion_route_builder.gd`
under `scripts/player/`. They extend `RefCounted`, have no independent frame
callback, and remain below 500 lines. The existing pose node and graph retain
all live state and update order. Construction-boundary regression now checks
all nine coordinators and all extracted construction/calculation helpers.

Retry proof: full file budgets (380 scripts), construction boundaries, all 62
feature contracts, completed-frame pistol entry/fire/stop contacts, compressed
pistol idle/recovery/reload, 42-weapon/84-case live contact, directional phase,
hybrid action graph and playback cadence pass. Canonical `main.tscn` boots.

Broader dive checks still fail on quick crouched-dive support contact and prone
recovery. A separate fixture using the pre-change four sources and original
pistol mount reproduced both failures (and a timing-sensitive standing-dive
support failure). This refactor did not fix dive behavior. The fixture lives
at `/private/tmp/socom-refactor-before/`, with before/after logs listed in the
retry report. No assertions or gameplay timing were relaxed.

This completes the nine-file separation, **not** all game QA, all architecture
work, or internet capacity testing. The aggregate gate still requires `main`;
the existing branch was preserved. No browser export, commit, push, or art
change was made.
