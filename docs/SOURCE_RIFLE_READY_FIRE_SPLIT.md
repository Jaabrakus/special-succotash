# Standing rifle ready / fire separation

## Translation card

Intent: show the extracted ready shoulders/torso before shooting, a distinct firing stance on an accepted shot, then smoothly recover. Acceptance: main standing rifle ready uses seal_stand_alert02; accepted-shot grace blends seal_fp_stand in and recovers to ready while aim remains held; ready and fire cannot alias; physical hands stay within 1 cm through transition. Owner: SocomOperatorAnimationDriver / its existing AnimationTree. Protect CharacterBody, camera/reticle, server weapon, pistol hybrid, moving gaits, crouch/prone, reload, lean and mobility. Proof: source_rifle_ready_fire_regression.gd; ready_fire_visual_probe.gd loads main.tscn and tests actual aim/shot; pistol_hybrid_main_regression.gd; feature_contract_regression.gd.

## Delta — MERGE

Canonical input finding: test_mannequin.gd supplies requested readiness 0.0. Therefore also route rifle idle_standing to the native alert02 hold and make the existing rifle idle builder honor that family slot. This is the standing equipped carry the user means, not a new aim button. No input changes. Accepted shots still own the temporary firing selection and existing weapon-ready scalar. Moving ready source remains seal_fp_stand through ready_standing_moving, so no strafe replacement.

Source animset Seal anim set explicitly distinguishes Stand/modes/ready (seal_stand_alert01/02) from Fire stand (seal_fp_stand). Choose existing variant02 as a deterministic chest-level ready hold, not random idle switching. Existing map aliases ready_standing to seal_fp_stand; moving and pistol routes remain unchanged. Add firing_standing as a separate saved rifle-family slot. One Blend2 in the stationary ready source consumes the existing accepted-shot latch; exponential bounded blend weights only, no new animation/bone writer. The preceding rejected lateral delta experiment is not reintroduced.

Scores correctness/ownership/parity/usability/performance/coverage: old alias 2/5/5/4/5/3; native split 4/5/5/4/5/4. Evidence: operator_animation_map.json, operator_locomotion_route_builder.gd, operator_animation_driver_runtime.gd, source_rifle_ready_fire_regression.gd.

Godot 4.7.1 uses AnimationNodeBlend2 with input0 ready/input1 firing and sync=true; the blend value stays in [0,1]. API reference: https://docs.godotengine.org/en/latest/classes/class_animationnodeblend2.html (latest warns unstable; verified against installed 4.7.1). Default profiles without firing_standing retain the previous graph.

## Verification / failure lesson

Initial visual test exposed a source-classification gap: the logical alert02 clip was in seal_reference, while is_source_clip recognized only processed source folders. This reactivated legacy wrist/roll fitting as readiness crossed its logical threshold. Explicitly recognize the selected reference clip; do not broadly change other reference/action clips. Corrected rendered main AK/M4 test passed equip, early shot, held fire and recovery with continuous contacts below 1 cm and unchanged arm lengths. Settled shot bore errors below 0.04 degrees in that run. Source-ready-fire, pistol hybrid (nine normalized pistol configs) and source-fire policy regressions passed; 104 feature contracts passed. The quick aggregate gate is blocked by existing codex/render-deployment branch versus required main, not treated as passing. No user game restart, git push, or browser ZIP rebuild.
