# Native rifle presentation integration

## Translation card — before edit

Player intent: play the extracted SOCOM II rifle locomotion and firing poses in
the main Godot game without the old hand/shoulder corrections replacing them.
Acceptance: the selected native clip reaches the current skinned character;
relative source arm/elbow/wrist geometry survives the presentation pass; the
weapon remains held and accepted-fire bore aims at the reticle. Inspect rendered
forward/left/right movement, ready/fire, reload and jump. Do not call a resource
inventory or a numeric contact check visual parity.
Owner: the existing SocomOperatorAnimationDriver and its declared single weapon
presentation consumer; no replacement controller or animation owner.
Preserve: CharacterBody movement/collision, camera/reticle aim, server weapon and
reload duration, source assets, character selection, AGLS traversal states.
Proof: main_rifle_source_pose_audit.gd baseline/candidate comparison, rendered
multiple-angle captures, source classification regression and feature gate.

## Evidence and candidate decision

The current decoded archive set already has all 264 SEAL source names imported.
The saved main map references 82 unique source names. This does not prove that
every mission archive is decoded, or that all imported actions have runtime
states. No re-extraction or unsupported-state wiring is needed for normal rifle
walk/run/crouch/ready/fire.

Current: processed gait grounding/bounce and the source weapon solver still
modify extracted poses. A global source_pose_only switch also removes required
weapon aiming and finger presentation, so it cannot be enabled blindly.
Candidate MERGE: a rifle-scoped native-pose policy, rigid palm attachment and
one bounded upper-body aiming transform. No arm IK or elbow transport. The aim
adaptation and target-rig finger closure are explicitly not original-engine data.

Six scores (correctness/ownership/runtime parity/editor/performance/regression):
current 2/4/3/4/3/3; candidate provisional 3/5/4/4/4/4, pending physical/rendered
acceptance. Main activation is conditional on that evidence; source-pure bone
preservation alone is insufficient if the weapon cannot be held or aimed.

The source clock and Godot body speed are different contracts. No claim of
original-engine movement/camera/blending parity follows from using these clips.

## Verification decision: do not promote the rifle trial

`tools/main_rifle_source_pose_audit.gd` runs real commands through main. Baseline
and isolated global-source-only runs each checked 612 frames, seven accepted
shots and one completed reload. Global-source-only preserved all 65 evaluated
bone transforms but failed 13 combat/contact checks. It is not a playable fix.

The bounded `source_rifle_attachment` trial then fixed the M4 firing bore:
forward/left/right samples 0.0079/0.0022/0.0279 degrees. However support gaps
remained 6.33/12.73/11.16 cm. Rendered side/rear captures showed palm/receiver
overlap and a floating support hand. REJECT promotion: the main profile does not
enable this flag. Existing rifle contact stays in place while native gun geometry
and attachment are investigated. The candidate can be reproduced with a separate
profile, not by overwriting the main profile.

Code: `operator_animation_driver_runtime.gd` consumes the optional rifle flag;
`operator_weapon_pose_ready.gd` delegates `SourceAttachmentAim.apply(...)` without
arm IK; `operator_animation_library_cache.gd` fingerprints processed-source mode.
The generic aim helper is also used by the active pistol path; its main regression
passed after this extraction into a shared module.

Reports: `/private/tmp/rifle-source-baseline-m4-v1.json`,
`/private/tmp/rifle-source-pure-m4-v1.json`,
`/private/tmp/rifle-native-short-m4-v1.json`. Aiming/contact measurements are not
claimed to prove original engine behavior, timing or pixel-perfect anatomy.
