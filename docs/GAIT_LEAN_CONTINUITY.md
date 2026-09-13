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

`operator_posture_layer.gd::_apply_authored_peek` preserves gait hip/leg rotations
during movement and crouch lean. Stationary standing instead uses the coordinated
authored pelvis/leg pose, with visual pelvis-height compensation that retains
the pre-layer support ankle height. Prone retains its existing timing/policy.

### Lean-direction regression correction

The first correction kept gait hips for every grounded lean. Without compensating
the upper-body local frame this introduced
a 50.65-degree standing-left head orientation error. The authored upper tracks
assume the authored hip rotation. `_apply_authored_peek` now transfers the missing
hip rotation into its direct-child Spine (`gait_hips.inverse() * leaned_hips`),
leaving moving/crouched hip and leg transforms untouched. For stationary standing,
that correction alone left a visibly mismatched pelvis. The current policy blends
the authored hips and legs in together, rather than concentrating the whole turn
at Spine. The residual hip-frame correction is identity at a full stationary
lean and grows only as gait ownership takes back the legs. Input signs, camera
aim, movement, and the existing pose-layer ownership remain unchanged.

Focused acceptance: rifle/pistol, standing/crouched, both half and full left/right
leans match a single blend to the authored held upper-frame orientation within
0.1 degree. Moving/crouched lower-body local transforms remain unchanged;
stationary standing hips match the authored blend and support height is unchanged. Run
`tools/lean_upper_frame_regression.gd` for that isolated check and the rendered
gait fixture for final composed poses. The latter now captures both settled
lean directions as well as movement taps and fire -> same-button exit.

### Fire and lean exit

The old `sample(abs(amount) * clip.length)` plus `slerp(..., abs(amount))`
scrubbed the entry animation backward while also blending toward a changing
fire-ready base. The rendered baseline reached 22.9 degrees/frame for rifle left
and 27.8 for pistol right. Grounded lean now blends once toward the held endpoint.
Saved `authored_peek.blend_seconds = 0.18` limits presentation lean travel; both
posture and weapon presentation consume the same visual amount. The input latch,
fire-recovery duration, shot cadence, camera and damage are not changed.
The regression checks both same-button exits select no unrelated action and
clear their lean source. Observed maximum upper steps became 7–12 degrees/frame.

Saved `standing_full_body = true` and the blend duration exist in both canonical
animation map and SEAL hybrid preset. Standing leg ownership follows the existing
locomotion latch (including stop grace), not instantaneous speed, so repeated
microsteps do not repeatedly restart the stationary leg pose.

This pass's parse check first caught an untyped dynamic return for `visual_peek`;
declaring it `float` fixed compilation before runtime tests resumed.

Delta review: MERGE the upper-frame compensation into the existing posture layer.
On a 1–5 scale, current/candidate scores are correctness 2/4, ownership clarity
5/5, canonical runtime parity 5/5, editor usability 4/4, performance 5/5,
regression coverage 3/5. Evidence is the failing-before/passing-after upper-frame
regression and unchanged grounded-gait checks; no new transform writer is added.

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

## Subsequent prone report (not fixed by this lean change)

The prone reload keeps its upper-body playhead on stance change:
`operator_animation_driver_actions.gd::_cancel_reload_for_posture_change` returns
without cancelling or replacing it. The existing attachment guard limits barrel
rotation but does not retarget the torso. A September 11 rerun of
`tools/prone_reload_transition_smoothing_regression.gd` failed its position bound
(0.2135 m outward / 0.2124 m return versus 0.17 m) and return rotation bound
(13.006 degrees versus 12). This covers prone/crouch, not standing. The user's
prone firing elbow oscillation remains undiagnosed; source poses bypass the
extra procedural elbow pulse in `operator_weapon_pose_ready.gd`.
Do not count the passing lean checks as proof that either prone issue is fixed.
