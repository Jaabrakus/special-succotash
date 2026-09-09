# Grounded gait and lean continuity

## Translation card

Player intent: run without the recurring sinking/limp, and make standing/crouch
lean microsteps without restarting a gait or popping off the floor.

Acceptance: both rifle and pistol paths retain a single moving-state entry
through repeated short taps, freeze the gait clock while stopped, return to idle
after a deliberate stop, retain floor contact and keep hip discontinuities below
8 cm/frame at 60 Hz. Grounded support ankle stays within -5 to +16 cm during
entry/blending and steady running hip range stays below 18 cm.

Owner: ProductionAnimation / AnimationTree. The asset runtime prepares the
immutable animation library; it does not write live skeleton transforms.

Protected: CharacterBody movement and jump physics, stair probing, camera/aim,
weapon damage/timing, network authority, original extracted animation assets,
prone/action/traversal animation routes.

## Evidence and correction

`assets/animations/seal_gameplay/run_forward.tres`, track 1: hip Y rises from
0.013270169 to 0.017112698 then closes at 0.013270169. At model scale 62 that is
a 23.8 cm closure drop. The baseline run showed a 9.9 cm single-frame hip step;
disabling foot IK did not remove it. Baseline rifle crouch taps reached a 30 cm
single-frame hip step and the support foot reached 41 cm above body origin.

`operator_asset_runtime.gd::_align_grounded_gaits` bakes a support-height
correction into duplicated continuous grounded clips. The helper evaluates the
existing bone hierarchy/rotations and aligns the lower ankle to the saved 5 cm
support height. It changes only hip position keys; it preserves rotations,
durations and authored assets. All samples are evaluated before modifying keys.
Jump, dive, reload and traversal clips are not normalized. No new per-frame IK
or body transform writer is added. Cache schema 6 and height-setting fingerprints
invalidate old processed libraries.

`operator_animation_driver_pose.gd::_update_locomotion_latch` retains a moving
route across stops shorter than the saved 0.28 s. Posture and mobility changes
are not delayed. `operator_locomotion_blend_tree.gd::update_locomotion` scales
sub-0.8 m/s gait playback toward zero, so the retained route does not jog in
place. Existing no-reset transitions and cyclic directional spaces remain.

`operator_posture_layer.gd::_apply_authored_peek` preserves grounded hip/leg
rotations instead of replacing them with a held full-body lean sampled without
its corresponding root translation. Authored shoulder/arm lean remains; prone
lean retains the existing full-body policy.

The two saved animation profiles carry the same settings. Animation Studio
continues to edit the canonical profile; Lab Play enters `main.tscn`.

## Proof and limits

Run `tools/gait_lean_continuity_regression.gd` with `--fixed-fps 60`; append
`-- --capture` for a separate rendered fixture. It uses the real operator scene,
normal command/physics route and normal animation evaluation, not forced poses.
It covers AK-47/Mark 23 run, standing lean, crouch lean and repeated A/D taps.
Camera capture does not reload or manipulate the user's running game.

After alignment, the measured forward run hip step is about 3 cm/frame, and
crouch tap entry about 4.8 cm/frame. Repeated taps each have only one initial
moving-state entry. Actual body contact is checked independently: no missing
floor frames, tolerance 1.2 cm for capsule recovery on the test box.

The source crouch idle is kneeling; its transition into crouch walking still
raises the hips as the grounded legs unfold. This work removes the discontinuity
and repeated reset, not that intentional posture difference. It does not certify
every authored clip, every terrain surface, or multiplayer under internet load.

System delta: MERGE. The existing graph has clear ownership but source root
drift and instantaneous tap route changes. Library-time alignment and a bounded
visual stop grace improve continuity without modifying protected owners.

Verified this pass: gait continuity, immutable clip alignment, lean latch/network
command checks, source jump, stair foot grounding, playback cadence, cache
fingerprinting, and 114 feature contracts. The stair test now waits for the
fire-recovery owner to release protection rather than assuming eight render
frames are sufficient. No runtime fire/IK protection was weakened.

Aggregate quick integration remains blocked by its existing main-branch guard
on `codex/render-deployment`; no branch change, push or browser export is included.
