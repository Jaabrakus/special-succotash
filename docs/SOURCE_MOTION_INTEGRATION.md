# Source-motion integration pass

## Translation card

Intent: expose the extracted player animation rather than hide it behind an older
pistol upper-body override. Acceptance: source slots reach the actual canonical
AnimationTree; standing/crouched forward/left/right motion and accepted shots keep
floor contact, palm contacts within 1.5 cm and firing bore within 6 degrees of aim.
Inspect early/mid/late poses from two angles before promoting saved data. These
checks are safety/integration checks, not a claim of original-engine equivalence.
Owner: SocomOperatorAnimationDriver with its existing shared animation profile.
Must not change: CharacterBody movement and collision, camera input/aim, server
shots/reload/damage, original source assets and unrelated animation families.
Proof: tools/main_source_motion_proof.gd (main.tscn, real queued movement and shots),
source pose audit, source rifle/legacy fallback regressions, feature contract gate.

The candidate is first supplied with --profile=PATH to the canonical proof process.
Only passing candidates may be promoted to config/operator_animation_map.json.
The current root/branch stays unchanged; source copies remain available for comparison.

## System delta before editing

Current canonical pistol layer replaces the entire authored upper body while
standing/crouched (operator_pistol_upper_layer.gd:21). Candidate lets the authored
source route own that region and keeps weapon contact solving downstream.
MERGE if measured source contribution improves without contact regressions.
Scores correctness/ownership/canonical parity/editor usability/performance/tests:
current 2/5/5/4/5/4; candidate 3/5/5/4/5/4 (conditional on focused proof).
Evidence: operator_pistol_upper_layer.gd, operator_animation_driver_runtime.gd,
config/operator_animation_map.json and tools/main_source_motion_proof.gd.

## Review outcome: original candidate rejected

The first candidate preserved the downstream two-hand solve. It passed numerical
contact checks but visibly changed the free left arm in the source forward pistol
run. It was not promoted. Two palm-distance checks are the wrong acceptance rule
for a clip that does not author a support grip.

The subsequent source-only experiment is recorded in `docs/SOURCE_POSE_ONLY.md`.
Its non-mutation checks pass, but native directional aiming, grip orientation and
finger closure remain unfinished. Neither candidate establishes one-for-one
original-engine behavior. Forward-running hand-use evidence must not be generalized
to the separate right-strafe clip.
