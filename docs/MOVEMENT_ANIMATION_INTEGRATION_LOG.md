# SOCOM-141 Movement and Animation Integration Log

## Restore point

- Integration branch: `movement-animation-integration`
- Baseline commit: `b5510ba` (`Finish thin camera coordinator refactor`)
- Exact pre-integration working-state snapshot:
  `work/snapshots/2026-08-17_movement_animation_takeover`
- The live project at `/Users/kiwimango/socom-141-camera-lab` was not overwritten while this work was developed and tested.

The snapshot contains the relevant source/config copies, `tracked_changes.patch`, and `status.txt`. Restore individual files from that directory instead of resetting the full project, because the baseline already contained other in-progress work.

## Architecture now in place

- `operator_animation_driver.gd` is a 449-line coordinator rather than the asset loader, graph builder, transition state machine, and posture solver all at once.
- `operator_animation_profile.gd` is the single animation/config contract. It contains no sprint route: partial input is the deliberate combat shuffle and full input is the tactical run.
- `operator_asset_runtime.gd` owns the 65-bone operator, runtime clips, retargeting, weapon attachment, and root-translation cleanup.
- `operator_locomotion_blend_tree.gd` owns synchronized directional BlendSpace2D graphs, continuous shuffle/run blending, and stride-rate correction.
- `operator_transition_state_machine.gd` owns visual starts, stops, reversals, and planted turns. It never moves the CharacterBody.
- `operator_posture_layer.gd` distributes camera/reticle aim across the spine, neck, head, and shoulders while leaving lower-body locomotion independent.
- `operator_ik_contract.gd` provides stable support-hand and foot targets. Active IK is intentionally deferred until the imported clips have verified contact metadata.
- The previous discrete animation route remains available as a fallback.

`CharacterBody3D` remains authoritative. Acceleration, braking, and reversal response live in `player_controller.gd`; animation consumes the resulting velocity and does not author movement. This is the boundary required for future client prediction/server authority.

## Source SDK lessons used

Valve's Source SDK is a design reference only. The Godot implementation is independent and does not copy Source code or tuning values.

The useful confirmed boundaries are:

1. Keep view/eye yaw, feet yaw, and movement/gait yaw separate.
2. Derive directional animation from authoritative velocity relative to view/body orientation.
3. Match animation playback to actual speed and calibrated clip ground speed.
4. Turn feet only when movement or the torso twist limit requires it.
5. Keep movement/collision simulation separate from animation presentation.

Source's 8/9-way pose parameters are analogous to this project's BlendSpace2D, but they are not a drop-in implementation. SOCOM videos remain the authority for camera composition, movement timing, turn limits, and tactical feel.

## Verified regression baseline — 2026-08-17

All suites pass:

- operator configuration validation
- live 65-bone animation and locomotion graph regression
- authoritative mobility regression
- measured locomotion-quality regression
- complete camera/wall/visibility/multiplayer-contract regression

Measured locomotion baseline:

- Mean low-foot drift: `4.321 cm/frame`
- P95 low-foot drift: `5.169 cm/frame`
- P95 direction-change pose delta: `10.897 deg/frame`
- Maximum one-frame direction pose delta: `17.256 deg/frame`
- Torso-to-aim angular error: `2.400 deg`

Camera regression remained unchanged: zero unreadable frames, lost horizontal/tether frames, state flips, or view freezes in wall-entry, wall-sweep, wall-exit, and tight-interior scenarios. Wall geometry remained opaque and no camera state was added to the multiplayer input contract.

## Known remaining calibration

- The left locomotion half is currently generated as a true sagittal mirror of the approved right-side clips for walk, tactical run, and crouch. The reversible pairs live in `config/operator_animation_map.json` under `mirrored_clips`. The pre-mirror restore point is `work/snapshots/2026-08-17_pre_symmetric_locomotion`.
- Imported foot-contact metadata is still placeholder data. The current foot-slip metric uses a phase-agnostic low-foot-height sample and is a regression guard, not final foot locking.
- The IK contract currently exposes bone chains and targets only. Terrain probes, active two-bone leg solving, foot-normal rotation, pelvis compensation, contact locking, and stair/ledge limits are not implemented yet.
- Measure every accepted clip's stride length, cycle phase, left/right contact windows, and skeleton compatibility before enabling support-hand or foot IK.
- Replace a clip only through `operator_animation_profile.gd`; do not let asset imports modify camera or authoritative movement code.
- Tune SOCOM timing from the supplied reference videos, not Source movement values.

## Upper-body locomotion ownership fix — 2026-08-17

- Audited `run_right`, `run_left`, and `aim_idle` track ownership. The directional run clips each contained 43 upper-body tracks, so the locomotion clip was rotating the spine, shoulders, arms, hands, neck, and head before the aim layer was applied.
- Added a filtered standing upper-body blend. Walk/run clips now own only the hips and legs; the neutral/combat-ready rifle pose owns the spine-through-hands chain, and camera/reticle aim remains additive after that stable base pose.
- Kept the approved symmetric left/right lower-body clips unchanged. The fix therefore removes the bad right-side torso motion without regressing the good left-side leg motion.
- Added regression assertions for the upper-body filter and for retained hip/leg ownership.
- Live restore point: `work/snapshots/2026-08-17_pre_upper_body_mask`.
- Verified live results: animation, mobility, locomotion-quality, and camera suites all pass. Torso-to-aim error remains `2.400 deg`; camera/wall behavior remains unchanged.

## Torso/leg hierarchy separation — 2026-08-17

- A second rendered-pose audit found that directional pelvis yaw still propagated into the spine through the bone hierarchy, despite the upper-body track mask.
- The posture layer now measures pelvis yaw relative to the neutral rifle pose and cancels only that inherited yaw at the bottom of the spine. The directional hips and legs remain animated; reticle/camera yaw is then distributed over the upper-body chain as before.
- Added a world-space regression that compares forward, right, and left locomotion at identical aim. In the live build, the legs span `77.762 deg` while the torso spans only `0.735 deg`.
- Foot-slip, direction-pop, torso-to-aim, mobility, and complete camera regressions remain green.
- Live restore point: `work/snapshots/2026-08-17_pre_torso_leg_independence`.

## Anatomical strafe correction — 2026-08-17

- Rejected the unlimited procedural spine counter-rotation after visual testing showed an unnatural waist twist.
- Replaced the generic side-run sources with independently authored `Strafe Right.fbx` and `strafe left.fbx` takes. Their pelvis orientation is substantially closer to the neutral rifle stance than the previous right-run take.
- Bounded pelvis compensation to `18 deg`; the torso can assist naturally instead of absorbing an arbitrarily large directional correction in one spine joint.
- Live metrics: pelvis directional span `21.551 deg`, torso directional span `1.304 deg`, foot-slip and direction-pop budgets pass, and all mobility/camera tests remain green.
- The next aiming layer will reverse the current ownership: the weapon pose will solve toward the shared aim point, with right/support hands following weapon grip sockets. Weapon obstruction, muzzle ray, recoil and server shot validation remain separate from locomotion animation.
- Live restore point: `work/snapshots/2026-08-17_pre_anatomical_strafe`.

## Right-run mirror rollback — 2026-08-17

- Visual review rejected the dedicated-strafe and pelvis-compensation experiment above. Those changes were rolled back; no procedural hip counter-rotation remains in the posture layer.
- Preserved the previously accepted authored `run_left` take and added a distinct generated `run_right` state as its exact sagittal mirror.
- The upper-body replacement mask remains active, so locomotion clips do not directly overwrite the rifle-ready spine/arm pose. Camera and authoritative movement code were not changed.
- Config, track-level mirror, animation, locomotion quality, mobility, and camera regressions pass.
- Live restore point before this rollback/mirror change: `work/snapshots/2026-08-17_pre_right_from_left_mirror`.

### Mirror-direction correction

- The first rollback mistakenly reversed the requested source/target direction and generated `run_right` from `run_left`.
- Corrected immediately: the authored `run_right` is the source state and `run_left` is its generated mirror, matching the last visually acceptable setup.
- No procedural torso/pelvis correction and no dedicated-strafe substitution are active.

## Legs-only lateral symmetry and immediate A/D — 2026-08-17

- Replaced the full-body `run_left <- run_right` mirror with a legs-only mirror. Left/right upper-leg, lower-leg, foot, and toe tracks are swapped and reflected; hips, spine, head, shoulders, arms, and hands remain identical to the authored `run_right` source.
- Kept the approved upper-body replacement mask. The rifle-ready pose and reticle-driven torso layer therefore remain independent from lateral footwork.
- Pure A or D input now selects the corresponding lateral BlendSpace position on the first animation frame. Diagonal input still uses the existing continuous 2D blend, so forward-left is visited only when the player actually supplies forward-left input.
- Normalized locomotion phase remains shared, preventing the immediate logical selection from restarting the foot cycle.
- Isolated verification passed: configuration, track ownership, frame-one A/D selection, locomotion quality, mobility, and complete camera regressions. Direction-change P95 is `10.861 deg/frame`, maximum is `23.053 deg/frame`, torso-to-aim error is `2.400 deg`, and no one-frame pose snap was detected.
- Live restore point before installation: `work/snapshots/2026-08-17_pre_leg_only_mirror`.

## Hierarchy-correct upper/lower-body separation — 2026-08-17

- Confirmed that the filtered animation tracks were correct but the Mixamo hierarchy still propagated the directional hip rotation into every spine child. With centered aim, the uncorrected right strafe moved the rendered spine from roughly `-30 deg` to `-75 deg`.
- Added a waist-boundary correction that extracts only the hip's vertical heading difference from the neutral rifle pose, conjugates it through the Mixamo spine rest basis, and applies it once at the bottom of the spine. It does not apply a raw world-axis twist, change the hips, alter CharacterBody movement, or affect camera aim.
- Directional pitch, roll, gait bounce, leg motion, recoil, and reticle-driven upper-body aim remain intact. The separation is disabled for crouch, prone, dive, roll, airborne, and landing actions.
- Post-correction orientation audit: forward/right/left spine headings are approximately `-39.92`, `-39.42`, and `-38.51 deg`, while the hips remain free at approximately `-29.96`, `-74.72`, and `-62.49 deg`.
- Added mobility assertions proving A and D can rotate the lateral lower body by more than `20 deg` without dragging the spine.
- Isolated animation, locomotion-quality, mobility, and camera suites pass with no one-frame pose snap. Restore point before live installation: `work/snapshots/2026-08-17_pre_upper_lower_hierarchy_split`.

## Forward-left A state and forward rifle brace — 2026-08-17

- Replaced the generated `run_left` state with an exact runtime alias of `run_forward_left`, as requested. The BlendSpace still selects pure left immediately, but the animation data at that point is now identical to the approved forward-left take.
- Expanded the hierarchy-space waist correction from hip heading only to hip heading plus pitch. Lateral gait roll remains authored, while inherited backward hip pitch can no longer pull the torso out of its forward rifle brace.
- Orientation audit before the pitch correction measured standing right/left spine pitch at approximately `+3.56/+1.42 deg`, compared with approximately `-7.35 deg` forward. After correction, idle/forward/right/left spine pitch remains approximately `-13.22/-13.02/-13.38/-13.46 deg`.
- The torso remains reticle-authoritative; movement and camera authority are unchanged. Configuration, exact-alias, animation, foot-slip, direction-pop, torso-target, mobility, and camera regressions pass.
- Restore point before live installation: `work/snapshots/2026-08-17_pre_forward_left_alias_and_brace`.

## Animated body-stack plumb overlay — 2026-08-17

- Added an on-screen diagnostic drawn from the production skeleton's actual animated hips, spine, chest, neck, and head—not the camera-framing proxy markers.
- Green is a world-vertical plumb pole rooted at the animated hips. Cyan is the real animated bone stack. Orange connectors expose displacement from vertical at every sampled joint.
- The overlay starts visible for visual calibration, toggles with `K`, and follows `H` clean-HUD visibility so screenshots can hide all implementation diagnostics.
- The overlay is presentation-only: it does not modify bones, animation, CharacterBody movement, camera collision, aim, or multiplayer input state.
- Editor parse, visual capture, mobility, clean-HUD, and complete camera regressions pass. Restore point before live installation: `work/snapshots/2026-08-17_pre_body_stack_overlay`.

## Player-relative body-stack measurements — 2026-08-17

- Extended the cyan/green body-stack diagnostic with numeric lean angle, signed head-back displacement, signed head-side displacement, and chest-back displacement.
- Measurements use the player's facing basis rather than global X/Z, so the signs remain valid while the operator turns: positive `back` is behind the hips, negative `back` is forward, and positive `side` is player-right.
- The standing samples currently measure approximately: idle `6.0 deg`, forward `8.3 deg`, right `9.8 deg`, and left `11.1 deg` total head-stack lean. The data shows the visible separation is a combined forward/lateral position offset rather than an unmeasured camera illusion.
- This remains diagnostic-only and does not alter the pose, camera, aim, movement, or multiplayer-authoritative state. Editor parsing, smoke, and full mobility regression pass.

## Continuous upper/lower split and rifle-brace stabilization — 2026-08-17

- The body-stack segment audit showed that retaining animated pelvis roll allowed locomotion to pull the chest, neck, and head away from the rifle brace even after pelvis yaw/pitch had been cancelled. Standing upper-body separation now cancels the complete animated pelvis rotation at the waist while preserving all authored hip and leg motion below the spine.
- Standing start, stop, reversal, run-to-stop, and planted-turn clips now pass through the same filtered upper-body replacement used by continuous locomotion. Those clips retain hip/leg authority but can no longer replace the spine, arms, neck, or head for several frames.
- Runtime animation assets are not destructively cut into separate files. The `AnimationTree` applies semantic bone masks: locomotion and its standing transitions own the lower body; rifle readiness and reticle aim own the upper body. Dive, roll, jump, prone transitions, and future vault/climb actions remain intentionally full-body.
- The previous transition audit reached approximately `25.1 deg` maximum head-stack lean during a left reversal. With continuous transition masking it remains approximately `10.1 deg` during the complete reversal and settles to a measured steady-locomotion maximum of `5.65 deg` in the regression scene.
- Added structural tests for every standing transition mask and a measured body-stack lean budget. Animation, locomotion-quality, mobility, and complete camera/multiplayer regressions pass; torso-to-aim error remains `2.4 deg`, direction-pop p95 is approximately `11.0 deg/frame`, and no one-frame pose snap is introduced.

## Crouch-turn ownership, restrained bob, and reticle-facing torso — 2026-08-17

- Crouched idle turning can no longer select the standing 90-degree planted-turn clips. Crouched reversals use `crouch_stop`, and entering crouch immediately cancels any standing-only transition already in progress, preventing the rendered operator from briefly standing up.
- Reintroduced `18%` of authored pelvis roll into the upper-body chain. Pelvis yaw and pitch remain fully isolated; most roll is still cancelled, preserving the rifle brace while restoring a restrained tactical bob.
- Rebalanced procedural aim so the three spine bones consume the complete reticle yaw/pitch. Neck and head now add only the residual beyond the torso limit, and shoulder pitch no longer double-applies the camera pitch. Because the arms inherit `Spine2`, they remain connected to the reticle-facing chest.
- Rendered-bone audit: a `30.0 deg` reticle yaw changed the actual `Spine2` yaw by approximately `30.4 deg`. Logic-layer torso error is `0.0 deg`; steady body-stack maximum is approximately `5.27 deg`.
- Added crouch transition and cancellation regressions and tightened the torso-to-aim budget to one degree. Animation, locomotion-quality, mobility, camera, visibility, and multiplayer-contract suites pass.

## Stance-aware joint diagnostic and prone camera pivot — 2026-08-17

- Expanded the production-skeleton overlay from a five-point body pole to the full diagnostic chain: hips, all three spine joints, neck, head, shoulders, elbows, hands, hips, knees, and feet. Green remains the intended stance axis; cyan now represents every actual animated spine and limb joint, with short hand/foot motion trails.
- The reference axis is stance-aware. Standing and crouched operators compare against vertical; prone, dive, and roll compare against the player's forward body axis, so a correct horizontal prone pose is no longer reported as a 70–90 degree standing lean error.
- The extra `Spine1` sample makes the cyan torso visibly articulate toward reticle aim instead of skipping the middle of the bend. The overlay remains a read-only diagnostic: it never invents a pose or changes gameplay bones.
- Added a prone-only preferred-shot drop and stance aim-origin height. The blend is driven continuously by the real head marker, so crouch is unaffected and dive-to-prone lowers the camera smoothly instead of snapping.
- Automated prone framing now measures head screen Y near `0.68`, camera height near `1.27 m`, centered camera/weapon aim, and a visible operator. The previous broken sample placed the head at approximately `1.22`—entirely below the frame.

## Anatomically constrained weapon-pose solver — 2026-08-17

- Added a post-animation, visual-only two-arm solve driven by the camera's existing shared world aim target. The reticle, ballistic ray, CharacterBody movement, and multiplayer command contract remain authoritative and unchanged.
- The three spine bones continue to distribute reticle yaw/pitch; the new layer solves the right hand to the trigger position, the left hand to the support grip, and both elbow planes around that same rifle line. The attached rifle's visual barrel is then aligned to the shared reticle ray.
- Added a compact anatomical profile rather than an AI model in every bone: minimum/maximum elbow angles, minimum forward shoulder reach, outward elbow poles, bounded wrist correction, and a torso-assist threshold. Close-wall tucking can shorten the pose but cannot fold a hand behind the shoulder plane or hyperextend an elbow.
- Fixed an imported-scale bug in the analytic solver. A world-sized elbow epsilon had been interpreted in the skeleton's pre-scale units and forced the arms nearly straight. The corrected epsilon is relative to measured arm length.
- Extended the `K` body-rig diagnostic with trigger/support targets, hand-to-target error lines, the rendered weapon ray, elbow angles, and aim error. Orange/yellow rings are diagnostic targets; the red segment is the weapon direction; all remain presentation-only and disappear with the HUD.
- Added `operator_weapon_pose_regression.gd`. Standing, lateral/downward aim, crouched, and prone poses keep each hand within `0.5 cm`, the rendered rifle within `0.1 deg` of shared aim, elbows within `40–152 deg`, and wrist correction below `72.1 deg`. The test also proves the layer cannot move the authoritative player, change velocity, or rewrite the shared aim point.
- Animation, mobility, locomotion-quality, complete camera/wall visibility, and multiplayer contract suites pass. The first parallel camera run produced one `0.179 m` wall-step outlier; an isolated rerun returned the established `0.147 m` maximum with zero unreadable, tether-lost, state-flip, or view-freeze frames.
- Restore point before implementation: `work/snapshots/2026-08-17_pre_weapon_pose_solver`.

## Continuous prone steering and body-axis correction — 2026-08-17

- Replaced the moving-prone `forward/left/right` clip switching with one synchronized forward/backward blend rail. A/D now steers CharacterBody travel while retaining the existing forward-crawl playhead; the dedicated prone-turn clips remain mapped for a future stationary-turn state.
- Backward prone still uses the authored Mixamo backward crawl. Forward/backward changes crossfade at matching normalized time inside the same modern `prone` state instead of replacing the animation state.
- Added a smoothed prone-forward spine correction at the base of the animated spine. It preserves the low stance and authored limb cycle while reducing the hips-to-head crawl-axis error from roughly `22 deg` to `6.7–14.0 deg` across the sampled cycle.
- Added a dedicated prone continuity regression. Forward → left → right → forward steering remains on `prone_forward`, stays in the `prone` blend state, and measures less than `0.8 deg/frame` at each steering transition after entry.
- Animation, mobility, weapon-pose, locomotion-quality, camera, wall-visibility, and multiplayer-contract regressions pass. Camera maximum step remains `0.147 m`, with zero unreadable, tether-lost, state-flip, or view-freeze frames.
- Restore point before implementation: `work/snapshots/2026-08-17_pre_prone_locomotion_continuity`.

## Forward-diagonal lateral footwork — 2026-08-17

- Pure A/D gameplay movement remains camera-relative lateral translation; it does not arc around the aim point or add forward velocity.
- Full-gait A now renders the `run_forward_left` take and D renders `run_forward_right`. Crouched A/D use `crouch_forward_left` and `crouch_forward_right` through the same animation alias mechanism.
- Kept the logical left/right BlendSpace points, normalized phase synchronization, reticle-facing torso layer, and multiplayer-authoritative CharacterBody movement. Only the animation data assigned to those lateral points changed.
- Runtime tests verify all four lateral points are exact aliases of their requested forward-diagonal takes. D retains approximately `12.4 deg` of leg/torso separation while the torso stays centered on aim.
- Configuration, animation, movement, locomotion-quality, prone-continuity, camera, visibility, and multiplayer regressions pass. Camera maximum step remains `0.147 m` with zero unreadable, tether-lost, state-flip, or view-freeze frames.
- Restore point before implementation: `work/snapshots/2026-08-17_pre_forward_diagonal_lateral_mapping`.

## Tunable lateral angle and animation-tree studio — 2026-08-17

- Added a data-driven hip-yaw offset for the pure A/D animation points. Standing and crouched A/D still use the approved forward-left/right takes, but the legs now angle another `6 deg` into the requested side while CharacterBody travel remains purely lateral and the torso stays reticle-authoritative.
- The measured D leg/torso separation increased from approximately `12.4 deg` to `17.9 deg`; no movement, aim, camera, or multiplayer authority moved into the animation layer.
- Upgraded the animation library lab from a flat slot picker to a visible runtime tree grouped by standing locomotion, crouch, prone, mobility, combat, and transitions. Each leaf displays its assigned clip and accepts clip drag/drop directly from the searchable inventory.
- Added conservative best-match suggestions and an auto-build action for known runtime states. Unknown clips remain preview-only or manually assignable; the studio does not silently invent collision, input, or network behavior from an animation filename.
- Fixed the animation-map save path so editing a slot preserves aliases, mirrored clips, pose angles, locomotion calibration, transitions, and all other configuration sections.
- Editor parse, animation-studio smoke, configuration, animation, pose-tool, movement, and locomotion-quality regressions pass. Restore point before implementation: `work/snapshots/2026-08-17_pre_lateral_angle_and_dragdrop`.

## Connected animation-route graph and reliable drag/drop — 2026-08-17

- Replaced the compact hierarchical list with a scrollable node-and-branch graph. A root operator-animation card connects to standing locomotion, crouch, prone, mobility, combat, and transition branches; every runtime state is a bordered card displaying its assigned animation.
- Clip rows now explicitly begin a drag after a six-pixel pointer movement instead of depending only on the platform's implicit Button drag threshold. The dragged clip has a visible floating label, and valid state cards highlight yellow before release.
- Dropping on a card selects that exact runtime state, updates only its clip mapping, refreshes the graph, and reports the binding in the studio status bar.
- Added a headless interaction regression that creates a real clip payload, hit-tests the target route card, executes the drop, and verifies that the exact target state and FBX path are emitted.
- Animation-studio parse, scene smoke, and drag/drop interaction tests pass. Restore point before implementation: `work/snapshots/2026-08-17_pre_visual_animation_route_graph`.

## Highlight-first animation proposals — 2026-08-17

- Removed drag/drop as a requirement. Every animation inventory row now has a star toggle; highlighted clips preview immediately and appear as purple candidate nodes in the connected route graph.
- Candidate cards show their conservative best-match runtime state. Clicking a purple candidate selects it again, and `Approve Selected Suggestion` performs the explicit authoritative binding. Multiple favorite takes can remain highlighted for comparison before approval.
- Unknown clips remain useful graph proposals without silently creating movement, collision, transition, or replication rules. `Clear Highlighted Clips` resets the temporary proposal palette without modifying runtime mappings.
- Kept direct card drag/drop as an optional secondary interaction, but the complete selection-and-approval workflow now works with ordinary clicks.
- Added regressions proving a highlighted candidate produces a graph card and that the card is independently selectable without drag/drop. Restore point before implementation: `work/snapshots/2026-08-17_pre_highlighted_animation_candidates`.

## Persistent user animation shortlist — 2026-08-17

- The screenshot audit showed that long Mixamo names consumed the left row width and pushed the trailing star controls offscreen. Each star now occupies a fixed-width leading column before the clip name, so `☆/★` remains visible at every horizontal scroll position.
- Highlighted clip names render purple in the inventory and continue to appear as purple proposal cards in the route graph.
- Highlights now persist immediately to `config/highlighted_animation_candidates.json`. The file records the selected display name, FBX path, stable key, and conservative suggested runtime state, giving Codex a direct project-local shortlist to review and assemble on the user's behalf.
- Switching skins or reopening the studio restores the shortlist. Clearing highlights updates the file without changing any authoritative runtime mapping.
- Scene smoke and regression checks verify graph candidates and the exact Codex handoff payload. Restore point before implementation: `work/snapshots/2026-08-17_pre_persistent_animation_shortlist`.

## Frame trim and authored clip assembly — 2026-08-17

- Upgraded the animation-library timer to a frame-accurate 30 FPS editor. The timeline now reports frame and time together, snaps scrubbing to individual frames, and provides previous/next-frame controls.
- Added non-destructive trim-in and trim-out markers. A selected frame range can be queued as a segment without changing its imported FBX source.
- Added a sequential assembly queue. Trimmed ranges from different source animations can be added, removed, reordered by rebuilding the queue, and baked into one new Godot `Animation` resource.
- Authored clips save under `assets/animations/authored/` with unique filenames, reappear in the studio's `AUTHORED` category immediately, and can be previewed or assigned to runtime animation slots through the existing graph workflow.
- Extended the runtime asset loader to accept authored `.tres` Animation resources in addition to FBX scene imports. CharacterBody movement, camera aim, ballistic authority, and multiplayer boundaries remain unchanged.
- Added a synthetic regression covering exact trim poses, source immutability, segment seams, 30 FPS timing, resource save/reload, and authored timing preservation. Restore point before implementation: `work/snapshots/2026-08-17_pre_frame_trim_combine_editor`.

## Non-overlapping frame-editor dock — 2026-08-17

- Fixed the studio layout defect that placed the frame editor over the lower `116–150 px` of both the clip library and runtime route graph. The two side panels now end above a dedicated bottom dock, so their scroll and drag targets remain interactive.
- Added an explicit assembly drop zone. Dragging a library clip into it appends that clip's complete frame range; selecting a clip and pressing `+ Add Range` still appends only the current trim.
- Added a direct `Save Trim` path independent of the assembly queue, plus `In ±1` and `Out ±1` controls for growing or shrinking a range one 30 FPS frame at a time.
- Added `Undo Range` and `Clear` queue controls and moved the runtime graph into its own scroll container so the shorter non-overlapping panel retains every mapping control.
- Extended studio regressions to verify drag payload delivery, direct editing controls, and geometric non-overlap of both side panels with the editor dock. Parse, authored-clip, studio, and complete operator-animation suites pass. Restore point before implementation: `work/snapshots/2026-08-17_pre_animation_editor_ui_dock`.

## Explicit clip-drag destination feedback — 2026-08-17

- A dragged animation now becomes a large cyan clip card that follows the pointer and tells the user to release over a glowing destination. The source library row turns yellow for the duration of the drag and restores its prior highlighted/unhighlighted color afterward.
- The assembly drop zone glows cyan as soon as a clip drag begins, turns yellow, thickens its border, and displays `RELEASE NOW` while the payload is actually over the valid release area.
- Runtime animation state cards glow cyan during clip dragging and the exact hovered state turns yellow. A graph banner explains that the state cards are active destinations.
- Added `+ Add Full Clip` beside the assembly destination as an equivalent no-drag action for the currently selected library clip. Frame-range assembly remains available through `+ Add Range`.
- Studio regressions verify ready/hover feedback state emission, payload delivery, and the no-drag fallback. Restore point before implementation: `work/snapshots/2026-08-17_pre_drag_destination_feedback`.
