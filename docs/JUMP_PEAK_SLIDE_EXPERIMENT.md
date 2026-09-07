# Jump-peak slide animation experiment

## Revision translation card — right knee down (before editing)

Player intent: anatomical right knee on the floor during the slide; preserve the
previous reclined pose for a possible backward dive. Acceptance: right knee joint
within 0.13m of the floor throughout the held pose, left foot ahead, old key data
preserved as a separately discoverable backward-dive pose candidate. This is not
a backward-dive gameplay ability. Existing AnimationPlayer remains the sole
animation owner; offline fitting only writes saved keys. Protected: body movement,
collision, camera/aim, weapons, controls, original character, jump/dive and map.
Proof: canonical contact-height/action regression, rendered hold/entry/recovery,
normal jump regression, feature-contract gate. Preserve the previous preview GIF.

System delta: MERGE. Previous feet-first slide / right-knee candidate scores:
correctness 2/4 (candidate provisional pending proof), ownership 5/5, canonical
parity 5/5, editor usability 4/4, performance 5/5, regression coverage 3/5.
Evidence: offline `_fit_slide_leg` used an UP knee pole for both legs; replace
only right-side authoring with explicit knee contact in `build_jump_peak_slide.gd`.
Add contact assertions in `jump_peak_slide_regression.gd`; do not add runtime IK.

## Right-knee revision result

Changed `tools/build_jump_peak_slide.gd:66`:

```gdscript
_fit_kneeling_right_leg(pose, start)
_fit_slide_leg(pose, "Left", float(recipe.left_foot_forward_m), start)
```

`_fit_kneeling_right_leg` at line 153 chooses pelvis height from the fixed thigh
length and right-knee target, then places the shin behind the knee. `_level_foot`
at line 178 corrects the jump-start pointed toes before grounding. Initial check
failed with `Canonical right knee not grounded: 0.264m`: the toe proxy was below
floor and whole-body grounding lifted the knee. Fixing foot orientation, not
relaxing the test, resolved it. Lesson: solve ankle/toe contact together with knee
contact; a knee target alone does not survive a whole-pose grounding pass.

Separate entries in `config/operator_animation_map.json:49`:

```json
"jump_peak_slide_candidate": "res://assets/animations/authored/jump_peak_slide_candidate.tres",
"backward_dive_pose_candidate": "res://assets/animations/authored/backward_dive_pose_candidate.tres"
```

The previous resource was moved to the backward-dive path, changing only display
name and source-recipe metadata; its bone keys are preserved. Its recipe snapshot
is `config/backward_dive_pose_recipe.json`. Both resources are discovered in
Animation Studio and loaded through the existing canonical authored-clip consumer.
This does not implement backward movement, a new dive action, or a slide collider.

Final focused regression PASS in headless and rendered main.tscn playback.
Rendered canonical right-knee joint height: 0.061637m relative to body ground
reference; visible knee contacts floor. Head: 1.880691m standing, 1.208719m held.
Stationary body drift: 0.000m. All 23 held samples (0.30–1.033s) pass saved-pose
contact/left-foot-ahead checks. Recovery releases the action. 65-bone rig and
normal jump/dive assignments unchanged. `jump_forward_legs_regression.gd` PASS;
`feature_contract_regression.gd` PASS, 82 contracts. No full promotion gate or
commit. Environmental macOS certificate warning persists in headless runs.

Actual game render: `art_source/jump_peak_slide/right_knee_slide_preview.gif`.
Grounded hold and entry/recovery inspected in rendered frames and the right-side
contact sheet. This is a rough knee-slide animation candidate; entry/get-up still
reuse the original jump transition, not a polished bespoke slide. Preview travel
uses existing forward input, not a newly implemented sliding mechanic.
Previous `art_source/jump_peak_slide/jump_peak_slide_preview.gif` is preserved.

## Previous iteration (history; superseded pose)

## Translation card — before editing

Player intent: try the forward jump's peak pose as a low feet-first slide.
Acceptance: show entry, held low pose and recovery on the original character;
save a separate authored clip readable by Animation Studio and canonical runtime.
One animation owner: existing SocomOperatorAssetRuntime / AnimationPlayer path;
the offline builder writes animation data, never a competing runtime bone writer.
Protected: current jump/dive assignments, CharacterBody3D movement and collisions,
camera/aim, server weapons/damage, animation sources, original body/rig and map.
Proof: source contact sheet, candidate motion render, saved-resource checks,
canonical library/action playback and feature contract gate.

This is an animation candidate for review, not a new sliding gameplay ability.
No new input binding or movement state is authorized in this experiment.

System delta: MERGE a separately named authored clip after visual review.
Current/candidate scores: correctness 2/3, ownership clarity 5/5, runtime parity
5/5, editor usability 4/4, performance 5/5, regression coverage 3/4. Candidate
correctness remains provisional until the render is inspected. Evidence:
`config/operator_animation_map.json` jump_forward_action; existing authored
resource loading in `scripts/player/operator_asset_runtime.gd`; existing authored
clip playback in `scripts/labs/animation_studio/animation_studio_playback.gd`.

Official API references: [Animation](https://docs.godotengine.org/en/stable/classes/class_animation.html)
and [AnimationPlayer](https://docs.godotengine.org/en/stable/classes/class_animationplayer.html).
Installed target: Godot 4.7.1, Compatibility renderer.

## Result and scope

Saved `assets/animations/authored/jump_peak_slide_candidate.tres` (1.65 seconds),
registered separately in `config/operator_animation_map.json`:

```json
"jump_peak_slide_candidate": "res://assets/animations/authored/jump_peak_slide_candidate.tres"
```

Existing canonical consumer: `scripts/player/operator_asset_runtime.gd:657`:

```gdscript
if resource is Animation:
    var authored := (resource as Animation).duplicate() as Animation
```

Existing action entry: `scripts/player/operator_animation_driver_actions.gd:199`,
`play_action(clip_name, blend_seconds, playback_speed)`. The review calls
`play_action("jump_peak_slide_candidate", 0.05)`, using the actual main.tscn
player and animation graph. In Animation Studio (`animation_library_lab.tscn`),
the authored library scanner discovers **Jump Peak Slide Candidate**.

The recipe starts from forward jump at 0.24s, holds a low variant, then blends
back to the starting pose. Simply tilting the original peak failed visually
(high kicking foot and floating pelvis), so the builder adds offline leg fitting
and existing rifle upper-body pose. This is no longer an untouched jump sample.
All edits are baked bone keys; no new per-frame bone writer is installed.

Canonical playback regression PASS: standing head 1.881m, low head 1.038m,
stationary collision-body drift 0.000m, action releases after recovery, 65 bones,
valid rotation keys and no horizontal hips travel. Normal forward-jump regression
PASS (including upper-body ownership). Parse PASS after fixing a preview-tool
type declaration. Initial feature gate found the wrong editor path and missing
system labels; these were corrected before rerunning.
Final feature contract gate PASS (82 contracts). Final canonical regression PASS,
including Animation Studio discovery. The macOS `get_system_ca_certificates`
warning remains environmental; no parse, animation or contract assertion failed
in these final runs. No full promotion gate, commit or deployment was requested.

Visual review: useful feet-first silhouette, but the tucked leg/sole contact and
recovery remain rough. Do not call it final animation or completed slide gameplay.
The moving GIF explicitly uses existing forward movement underneath the candidate;
it does not demonstrate a new slide motor, reduced collider, or shoot-while-sliding
mechanic. No weapon firing is tested in the clip. No goalie clip changed.

Current controls, jump, dive, camera, shot authority and active map were untouched.
Revert the candidate by removing its single clips-map entry; original files remain.
