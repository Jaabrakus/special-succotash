# Rifle lateral readiness

## Rejected experiment — not active

User clarified that aim-ready must be distinguished from firing. The derived lateral-delta experiment below was removed, including its generated resources and six main/hybrid route assignments. Rendered AK right recovery also failed continuous hand contact (0.33575 m), despite the saved-data test passing. Do not reactivate this recipe as a fix. Keep prior source routes while reviewing actual source ready-mode clips.

Recovered source evidence: extracted animset.rdr.json, Seal anim set, Stand/modes/ready names seal_stand_alert01 and seal_stand_alert02 with equal weights; Fire stand separately names seal_fp_stand. Step/ready is seal_alert_step; Walk/ready is seal_walk_alert02. Source semantic labels alone are not proof of the user-intended in-game silhouette: inspect animation samples before assigning.

## Translation card

Player intent: ready rifle movement visibly adopts the extracted firing posture instead of keeping the relaxed shoulders/torso. Acceptance: six walk/run/crouch left/right ready clips differ in upper-body rotation while keeping every lateral hip/leg track, duration and loop unchanged; canonical AK/M4 retain physical contacts below 1 cm and settled bore error below 6 degrees. Owner: existing SocomOperatorAnimationDriver reading operator_animation_map.json. Protect CharacterBody movement/collision, camera/reticle aim, server weapon, pistol hybrid, reload, jump, lean and grenade routes. Proof: source_rifle_ready_regression.gd, canonical rendered seal_locomotion_visual_probe.gd, pistol_hybrid_main_regression.gd, feature_contract_regression.gd.

## System delta — MERGE

Evidence: operator_animation_map.json rifle locomotion_ready lateral slots reuse normal strafe clips; import_seal_firing_poses.gd imports all fp/pfp catalog entries, none is a dedicated lateral firing clip. The extracted animset separately names Fire walk/run/backwards and normal left/right strafes. The twist/pitch resource is a nine-pose sample grid, not a looping locomotion take; its original runtime grid mapping is not established, so do not play it as locomotion.

Scores (correctness, ownership, canonical parity, usability, performance, coverage): current reused lateral readiness 2/5/5/4/5/3; derived saved ready variants 3/5/5/4/5/4. MERGE phase-matched local upper-body rotation deltas from the same gait's extracted relaxed/ready forward pair into each original lateral take. No new per-frame modifier or owner. Keep every lower-body track verbatim. The derived clips are explicitly adaptations, not recovered original lateral firing animations or proof of exact SOCOM runtime blending.

Build: tools/build_rifle_lateral_ready.gd writes only its six derived Animation resources. Saved rifle-family slots in the canonical map consume these through the existing firing directional spaces and ready blend. Relaxed slots and other families are unchanged. The source assets and pre_seal_main backup are untouched.
