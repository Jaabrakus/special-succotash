# Two-hand rifle support wrist

Translation card: hold the foregrip without a folded wrist. Acceptance: M4/AK standing, crouch and prone carry/aim maintain palm contact under 2cm and wrist bend at most 57 degrees, with aim under 0.1 degrees when ready. Owner: existing SEAL weapon-pose strategy, with a stateless constraint helper. Protected: source clips, gun sockets/transform, right hand, CharacterBody, camera, shot/damage and action timing. Proof: `tools/main_support_wrist_regression.gd` through main.tscn, rendered close-ups, geometry regression and feature gate.

MERGE: existing preserved world hand basis yields 120–128-degree standing wrist bends despite sub-millimetre contact. Constrain the palm's long axis against the solved forearm, then re-solve the same contact to account for the rotated palm anchor. Skip pistols, mobility and authored actions. No additional node or independent bone writer.

Scores current -> candidate: correctness 1->4, ownership 5->5, runtime parity 5->5, editor usability 2->4 (shared saved limit), performance 5->4 (up to four bounded refinements), coverage 2->4. Evidence: `operator_seal_weapon_pose.gd`, `operator_support_wrist.gd`, `config/support_wrist.json`, `tools/main_support_wrist_regression.gd`. Candidate visual approval is still required; a measured bend is not a skinning-quality guarantee.

Godot 4.7.1. Skeleton-global transforms are converted to world space before comparison with the world-space contact target; see https://docs.godotengine.org/en/latest/classes/class_skeleton3d.html . No imports or rest poses are rewritten.

## User clarification: support underneath the fore-end

Existing `operator_weapon_grip_contact.gd` remains the finger owner. Its left source-rifle branch consumes saved curl/wrap from the same profile while support IK owns the hand; equip/reload free-hand gestures are excluded. Right-hand settings remain unchanged. The first underhand render had open fingers because source curl was zero; this is why socket and wrist tests alone are insufficient.

Translation card: palm beneath the fore-end, facing up and wrapping rather than an overhand grip. Acceptance: inspect both sides of M4/AK; palm normal faces weapon-up, support contact stays below the bore and within 2cm, existing wrist and aim checks pass. Owner unchanged. Scope now includes only the M4/AK saved left-hand contact markers, not muzzle/trigger/buttstock. Proof remains canonical main wrist render/regression. MERGE (same scores): a bend limit alone cannot fix a source overhand roll or M4 target above barrel height. Add palm roll to the existing wrist helper and lower/center the two saved support markers; retain weapon geometry and all other sockets.
