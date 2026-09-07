# Jump direction combos

## Latest local result — crouch and rightward torso lean

Implemented: crouched AA/DD/SS, no crouched WW; dedicated low-entry clips;
full-body mobility wins over crouch idle; camera starts at its actual pre-action
height; baked rifle torso removes the source chest curl and adds 8 degrees of
character-right lean. This is a reviewed candidate, not user-approved final art.

Exact implementation evidence:

- `scripts/player/player_controller.gd:907`: crouched admission checks
  `String(choice) not in jump_combo_intent.profile.crouch_allowed_kinds` and returns.
  `:897` selects `profile.crouch_clips` from the existing replicated posture.
- `scripts/player/operator_animation_driver_pose.gd:468`: mobility states return
  `clip_name` before the `posture == &"CROUCHED"` idle mapping.
- `scripts/player/test_mannequin.gd:347`:
  `combo_camera_entry_height = head_marker.position.y`; at `:355`:
  `lerpf(combo_camera_entry_height, rest_height, entry_weight)`.
  Only anchor position changes; the camera rotation owner is unchanged.
- `tools/build_jump_direction_dives.gd:141`:
  `roll += deg_to_rad(float(combo_profile.torso_right_lean_degrees))`.
  At `:145`, `Basis(Vector3.BACK, roll) * rifle_globals[spine].basis`
  defines the baked chest frame; the original pelvis/legs stay authored.
- `config/jump_direction_combos.json`: `"torso_right_lean_degrees": 8.0`,
  `"crouch_allowed_kinds": ["left", "right", "back"]`, entry blend 0.30s.
  `tools/build_jump_direction_dives.gd:148` saves the crouched-entry variants
  referenced by `config/operator_animation_map.json`. Both graph routes seek them.

PASS: full combo regression after runtime changes; expanded crouch-only local
and server/proxy regression after fixture isolation; normal jump/upper-body
regression; standing/crouched/prone death regression; 89 feature contracts;
`git diff --check`. Flat-fixture recovery maximum downward marker/lens step was
0.0m. Crouched entries pass the actual graph selection, crouch pelvis first key,
upright camera and no upward standing-height pop checks.

Rendered early/rest/recovery left, right and backward poses and the actual SS
gameplay camera. Final clean SS capture disables live mouse fire in the test only:
`art_source/jump_direction_combos/gameplay/crouched/jump_direction_combos.gif`.
Torso/arm silhouette still needs the user's aesthetic approval, especially the
right-side view. Flat-ground fixture is not proof for every terrain/obstruction.

Failures retained: test `stamp` required explicit float typing; fixed and rerun.
Initial server DD fixture overlapped its own proxy, lifting the server into air
and correctly rejecting grounded input. Test now excludes only that duplicate
from server collision and resets each case to the flat fixture; actual gameplay
collision was not relaxed. The exact same expected clips then passed.

Quick integration still blocks at `tools/run_integration_gate.sh:18`:
`FAIL: this is codex/render-deployment; canonical integration is main`.
No branch change, commit or deployment. Skills kept all changes in existing
owners and shared baked profiles. Official transform/time-seek references:
[Skeleton3D](https://docs.godotengine.org/en/stable/classes/class_skeleton3d.html),
[AnimationNodeTimeSeek](https://docs.godotengine.org/en/stable/classes/class_animationnodetimeseek.html).
Runtime verified on installed Godot 4.7.1.

## Crouched actions / torso revision card — 2026-09-06

User refinement: a slight character-right torso lean, interpreted as an 8-degree
chest bank while the rifle stays forward, not a body/camera translation. Apply
offline to the same saved clips. Rendered crouched entry exposed standing-start
keys, so add three crouched-entry variants selected by the existing posture
contract. No extra replicated field or pose writer. Shared entry duration 0.30s.

Player intent: crouched AA/DD/SS work, crouched WW does not; dive torso remains
a rifle-ready form rather than death-source curl; crouched SS camera stays low.
Acceptance: actual modern graph and held bones show each allowed crouched dive,
WW stays ordinary crouched travel, SS camera never rises toward standing height
on entry and exits smoothly crouched; torso/rifle point forward with side roll.
One owner per domain: CharacterBody controller admits actions; existing animation
graph consumes baked source keys; mannequin owns position-only camera anchors.
Protected: distances/speeds, aim/reticle rotations, authoritative shots/damage,
death behavior, authored source FBX/rig, unrelated dirty work and normal jumping.
Proof: expanded combo regression, captured crouched SS gameplay camera and
left/right torso entry/rest/get-up, death and normal-jump regressions, contract gate.

System delta MERGE: current `_modern_state_for_clip` tests CROUCHED before DIVING,
so valid crouched actions can display idle. Camera entry hard-codes 2.15m. Side
bake copies shoulders but retains death/goalkeeper spine rotation. Replace those
bounded decisions in the same owners; no new runtime IK or camera controller.
Current/candidate scores (0–5, candidate provisional): correctness 2/4, ownership
5/5, canonical parity 3/5, editor usability 3/4, performance 5/5, coverage 3/5.
Evidence: player_controller.gd `_update_jump_combo`, test_mannequin.gd
`_update_camera_markers`, operator_animation_driver_pose.gd `_modern_state_for_clip`,
tools/build_jump_direction_dives.gd shoulder-only copy and authored spine frame.

## Latest source replacement result — 2026-09-06

The approved source replacement below is now baked and used by canonical play.
The earlier audit stating no substitution was made is historical, not current.
`tools/build_jump_direction_dives.gd` samples Death from Right at 2.64 seconds,
mirrors its counterpart and uses Rifle Prone To Kneel for recovery. The invented
offline leg-fitting function was removed. Slide-to-prone now samples Rifle Kneel
To Prone. Shared clip selection remains `config/jump_direction_combos.json`.

Full `tools/jump_direction_combo_regression.gd` passed after rebaking, including
held rest, fresh-input recovery, no-Space inputs, chains, prone/crouch exits,
collisions and replicated selection. Side boot joint heights are now
0.092–0.194m; maximum camera recovery downward step was 0.0m in the flat fixture.
Rendered left/right rest and recovery were reviewed. Legs no longer use the
invented scissor-rest pose; weapon/arm silhouette and action blends still need
the user's visual approval. Do not claim the whole animation art is finished.

## Approved source replacement card — user “ok”

Use the rendered Death from Right grounded sample as the side-rest base (mirrored
for its counterpart). Remove the offline invented leg target solve. Preserve the
goalkeeper's launch, blend into the authored floor contact, then use the existing
Rifle Prone To Kneel recovery and a short standing handoff. Slide prone exit uses
the actual Rifle Kneel To Prone progression instead of pose-to-pose interpolation.
Only offline source keys change; existing movement/aim/weapon/network owners stay.
Acceptance: no scissor kick frozen at rest, no invented knee pole/ankle twist,
grounded source pose at the held phase, smooth recovery, existing controls pass.
Proof: rebake shared resources, full combo regression and rendered side/rest/get-up
plus slide-to-prone. The earlier source-preview score is provisional until these
canonical consumers pass. Do not claim the user approved the resulting mesh pose
merely because the source-selection proposal was approved.

## Current handoff / animation-source audit — 2026-09-06

Controls implemented and focused checks passed: direction double-taps without
Space; WW/SS->AA/DD chains; slide->prone via Z or hold-C; WW/SS crouch exits;
released-then-fresh-movement side recovery. User still rejects the leg art.
Do not call the side-pose work visually accepted or finished.

Runtime evidence: `scripts/player/player_controller.gd:888`:
`var choice: StringName = jump_combo_intent.step(command.direction_held_mask, eligible, delta)`.
At `:924`, `movement_input_strength > 0.1 and combo_rest_input_released` gates get-up.
At `:947`, `posture = MotionState.PRONE if finish_prone else MotionState.CROUCHED`;
only side recoveries attempt standing. `scripts/player/test_mannequin.gd:356`
resets both presentation stance blends so the old prone amount cannot pull the
camera down on handoff. The F3 guide at `scripts/ui/socom_controls_guide.gd:306`
reads the same enabled profile and shows the new actions.

PASS: final combo regression, separated single-press mobility regression, normal
jump/upper-body regression, remote animation intent, 87 feature contracts and
diff whitespace check. The first broad mobility run failed because independent
single-press cases generated DD within 0.30 seconds. Test cases now wait past the
shared window without disabling the feature. Recovery measurements: maximum
per-frame downward marker/lens step 0.0m in flat-ground tests. Current authored
side boot joint heights 0.113–0.182m, but numeric contact is NOT visual approval.
Quick integration gate still stops at `tools/run_integration_gate.sh:18` because
the current branch is codex/render-deployment, not main. No commit or deployment.

Latest user asks whether an existing animation can help. Read-only source previews
used `tools/jump_peak_slide_preview.gd` with `--source=res://...`; no candidate
below has been substituted into gameplay:

- `assets/animations/mixamo/Pro Rifle Pack/death from right.fbx`: 3.30s; rendered
  samples at 1.98–3.30s show a low side/back fall with bent, settled legs. Candidate
  for the landing/rest only, not death logic. Preserve the aiming upper body and
  validate the bridge/mirror before adoption.
- `assets/animations/mixamo/Rifle Kneel To Prone.fbx`: 1.967s; visibly transitions
  kneeling to belly-down. Existing map excerpt:
  `"crouch_to_prone": "res://assets/animations/mixamo/Rifle Kneel To Prone.fbx"`.
- `assets/animations/mixamo/Rifle Prone To Kneel.fbx`: 1.967s; visibly reverses the
  contact progression into kneeling. A promising get-up source, not automatically
  a side-lying-to-stand clip.

Preview sheets are under `art_source/jump_peak_slide/`:
`death_from_right_sheet.png`, `Rifle_Kneel_To_Prone_side_sheet.png`, and
`Rifle_Prone_To_Kneel_side_sheet.png`. They are source/retarget previews, not a
claim of integrated runtime parity. System delta decision: REPLACE the rejected
side-rest source if the candidate is selected and passes blending/contact checks.
Source candidate scores old/new: correctness 2/4, ownership 5/5, parity 5/2
(candidate not integrated), usability 3/4, performance 5/5, coverage 5/2. Do not
promote provisional scores until the canonical chain is verified.

Official API checks used for this work:
[AnimationNodeTimeSeek](https://docs.godotengine.org/en/stable/classes/class_animationnodetimeseek.html)
and [Skeleton3D](https://docs.godotengine.org/en/stable/classes/class_skeleton3d.html).
The Godot/SOCOM workflow skills kept motion, animation presentation, marker
positions and camera rotation under their existing owners.

## Input/chaining delta — user update during landing correction

Replace Space-armed detection with fresh direction double-taps on the ground.
Space alone remains normal jump. WW slide, SS backward dive, AA/DD side dive;
WW->AA/DD and SS->AA/DD may replace the current longitudinal action with a side
dive. No recursive side-to-side chains. Slide + existing Z/prone or hold-C request
exits into prone; normal slide/back exits crouch. No new input action required.
Movement owner alone accepts transitions; command packets still carry raw intent.
Score delta MERGE: correctness 2/4, ownership 5/5, parity 5/5, usability 3/4,
performance 5/5, coverage 3/5 pending double-tap/chain/prone/Space regressions.
The helper `jump_direction_combo_intent.gd` and saved profile retain their names
for compatibility, but Space is no longer a prerequisite. Existing normal jump
and old dive-to-prone controls remain available. Test held taps, expired/mixed
taps, ground eligibility, four chain pairs and prone exit in canonical main.
The existing F3 controls guide will describe this same profile and current bound
direction/prone controls; it does not introduce another input handler.

## Landing correction translation card — 2026-09-06, user recording

Player intent: grounded, readable side-rest legs; stay down until fresh movement;
WW slide and SS back dive end crouched; no camera dip during recovery.
Acceptance: keeping the second combo tap held must not auto-recover. Side rest
requires a released input after rest, then fresh movement to get up. The saved
side floor pose has both boots below the pelvis with modest knee bend, not the
goalkeeper's airborne scissor legs. WW/SS blend to the canonical crouch pose and
remain in CROUCHED. Combo camera targets follow a smooth phase envelope and never
inherit animated get-up head dips or the generic DIVING-to-prone curve.
Owners: existing CharacterBody3D for state/collision; offline asset builder for
leg keys; existing mannequin markers for camera target positions. No new runtime
bone writer, camera rotation writer or weapon authority.
Protected: ordinary Space, Z/hold-C, aim/reticle, weapon solving, networking
authority, original mesh/rig, and unrelated dirty work.
Proof: expanded canonical combo test holds the second tap through landing,
checks release/repress, low boots, crouch exit, and camera recovery height over
every frame; render landing/rest/recovery from both sides and gameplay camera.
System delta MERGE/REPLACE: keep goalkeeper launch and source get-up, replace its
held scissor-leg sample with an authored grounded rest. Correctness old/candidate
2/4, ownership 5/5, parity 4/5, usability 3/4, performance 5/5, coverage 3/5
(candidate provisional). Evidence: player_controller.gd _advance_jump_combo uses
held movement rather than fresh intent; _finish_jump_combo unconditionally calls
_try_set_posture(STANDING). test_mannequin.gd _update_camera_markers follows raw
side get-up head motion and applies a generic prone descent to WW/SS. The previous
test released inputs before rest and checked camera roll, not vertical dipping.

The older verified section below records the previous acceptance, now superseded.

## Verified behavior — 2026-09-06

Left/right dives hold the side-rest pose while movement is released. Movement
resumes the goalkeeper animation's get-up; releasing movement after recovery
starts does not cancel it. Holding movement through the dive starts recovery at
the rest boundary. WW and SS still recover automatically. Low overhead clearance
leaves the player crouched.

`scripts/player/player_controller.gd:907` owns the hold/recovery decision:

```gdscript
if mobility_combo_kind in [&"left", &"right"] and action_elapsed >= 1.05 and not combo_recovering:
	if movement_input_strength > 0.1:
		combo_recovering = true
	else:
		action_elapsed = 1.05 # Rest on the side until movement resumes.
```

`scripts/player/operator_locomotion_blend_tree.gd:942` drives both animation routes:

```gdscript
func sync_jump_combo(clip_name: StringName, elapsed: float) -> void:
	if combo_seek_paths.has(clip_name):
		for path: StringName in combo_seek_paths[clip_name]:
			animation_tree.set(path, maxf(elapsed, 0.0))
```

The modern route registers its seek node in
`scripts/player/operator_locomotion_route_builder.gd:194`. Previously only the
legacy route froze, so a correct logical clip name hid the active pose getting up.
The regression now compares actual pelvis rotation to the saved floor pose.

`scripts/player/test_mannequin.gd:344` changes marker position only:
`marker.position = marker.position.lerp(target, alpha)`.
The unchanged camera owner at `scripts/camera/socom_camera.gd:704` uses
`return Basis.looking_at(direction, Vector3.UP, false)`.
Weapon presentation in `scripts/player/operator_weapon_pose_ready.gd` uses
`movement_state = &"JUMP_COMBO"` as a presentation-only tag for the existing ready
solver. It does not change gameplay DIVING state or grant shooting permission.

Verification on Godot 4.7.1:

- PASS: `tools/jump_direction_combo_regression.gd`: four canonical combos, actual
  keyboard input, tap rejection, walls/headroom, held pelvis pose, move-to-get-up,
  head anchor, upright camera, server/proxy state, death/respawn reset. Held head
  heights: left 0.605m, right 0.576m; pelvis error below 0.08 radians.
- PASS: `tools/mobility_regression.gd -- --camera-regression-map` (existing jump,
  Z/hold-C dive, stance clearance and aim ownership).
- PASS earlier in this change: jump-forward legs, slide-knee/foot regression,
  remote animation intent and 228 delayed network-prediction checks.
- Rendered launch/rest/get-up checks used the canonical player and an external
  review camera. Actual gameplay-camera roll was checked separately.
- PASS: this feature's entry in `tools/feature_contract_regression.gd`.
  Overall gate FAIL: separate pistol contract at
  `config/feature_contracts/pistol_carry_contact_and_pose_boundaries.json:21` expects
  `_set_weapon_solver_owned(pose.animation_owned_aim_alignment_enabled)` but source
  `scripts/player/operator_weapon_pose_ready.gd:187` / `:241` uses false / true.
  Preserve the concurrent pistol work; its owner must resolve the mismatch.
- Integration quick gate BLOCKED at `tools/run_integration_gate.sh:18`:
  `this is codex/render-deployment; canonical integration is main`.
- PASS: `git diff --check`. No branch switch, commit or deployment.

Limits: no live internet multiplayer test; gun contact was visually reviewed,
not quantified across all weapons. The collider remains an upright 1.25m capsule,
not a sideways body silhouette. Overall integration is not complete while the
broader gates fail or remain blocked. Workflow skills preserved the existing
movement, camera rotation and shot-authority owners.

## Translation card (before editing)

## Visual delta — user rejected tilted jumps; requested goalkeeper dives

The first runtime render was rejected: rotated jump legs kicked apart and the
generic DIVING chest-carry weapon curve raised the rifle above the slide's head.
New acceptance: actual Goalkeeper Diving Save source for lateral body movement,
mirrored only for the opposite side; existing ready/shooting-form weapon solver
keeps the rifle pointing at aim. No chest-carry trajectory for these new combos.
Owner remains existing weapon presentation solver for weapon and hands. No new
shot permission, camera writer, movement owner or runtime bone writer. Existing
Z/hold-C dives retain their chest carry. Add muzzle/hand stability proof to the
combo test. REPLACE the new tilted-jump lateral assets and MERGE combo-specific
ready presentation. Correctness previous/candidate 1/4, ownership 5/5, parity 5/5,
usability 3/4, performance 5/5, coverage 3/5, provisional until rendered checks.
Evidence: build_jump_direction_dives.gd sampled jump peak; weapon_ownership_contract
routes DIVING to MOBILITY_CHEST_CARRY; operator_weapon_pose_actions.gd carries the
entry rifle transform along a stand-to-prone curve rather than the combo pose.

## Original implementation card

## Side-rest / camera delta (user clarification before editing)

Acceptance extended: release directional movement after a lateral dive to remain
lying on that side; movement resumes the authored get-up. Existing head-marker
owner follows the animated head position only for lateral combos. Camera rig still
owns yaw/pitch, obstruction, and upright orientation; no bone rotation copied.
System delta MERGE: automatic get-up -> lateral idle hold plus positional head
follow. Correctness 2/4, ownership 5/5, parity 5/5, usability 3/4, performance 5/5,
coverage 3/5; verify grounded rest, move-to-recover, head proximity and zero camera
roll. Other slide/backward actions still auto-recover. No camera-angle writer added.

Player intent: Space then two fresh W/A/D/S presses selects a knee slide on
landing or an airborne left/right/backward dive. Space alone remains a jump.
Acceptance: 0.30s maximum between matching presses during a successful jump;
holding, pre-jump taps, expired/mixed taps and further combos cannot trigger it.
WW waits for ground; lateral/back dives add no second upward impulse. All actions
decelerate, collide, recover with headroom checks and reset on death/respawn.
Owner: existing SocomTestPlayer CharacterBody3D. A pure input recognizer supplies
intent; existing animation graph presents saved clips. Network commands carry
held directions, never client-selected speed, clip, or duration.
Protected: Space-alone jump, Z/stance dive, camera/aim authority, weapons/damage,
character rig/mesh, normal locomotion and active map. No slow motion or new
shoot-while-diving permission. Right-foot correction is offline animation only.
Proof: canonical main input/physics/render tests, packet round-trip and independent
server/proxy tests, wall/headroom/reset tests, existing jump and network tests,
feature-contract gate and integration quick gate (report any baseline blocker).

System delta MERGE: preview clips alone -> command-owned combo mobility.
Scores current/candidate: correctness 1/4, ownership 5/5, canonical parity 2/5,
editor usability 3/4, performance 5/5, regression coverage 2/5. Candidate scores
are provisional pending tests. Evidence: player_controller.gd movement owner,
socom_movement_command.gd / socom_network_protocol.gd command boundary,
operator_animation_driver_pose.gd currently selects one dive clip for all travel.
The shared JSON profile is editable in the existing Godot Inspector/file editor;
Animation Studio edits the same saved clips and its Play enters main.tscn.

Target Godot 4.7.1 Compatibility. API references:
[CharacterBody3D](https://docs.godotengine.org/en/stable/classes/class_characterbody3d.html),
[Input](https://docs.godotengine.org/en/stable/classes/class_input.html).
