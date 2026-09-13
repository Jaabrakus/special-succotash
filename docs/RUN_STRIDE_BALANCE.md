# Forward-run hip balance

Translation card: remove the one-sided dip during running. Acceptance: real forward commands through main.tscn keep speed/floor contact, similar left/right strides and hip step below 3cm; reduce alternating hip trough difference below 1.5cm, without support ankle moving outside -5 to +16cm. Inspect side/rear frames through a complete cycle. Owner: the existing immutable animation-library gait preparation. Protected: original source clips, leg/upper-body rotation tracks, animation duration, CharacterBody physics/speed, aim, weapon/damage and non-running routes.

Baseline: main_run_stride_regression on flat ground, 6.5m/s: hip range 14.2cm; alternate troughs approximately 88.7 and 92.0cm. Left/right foot travel 1.322/1.341m; peak ankle heights 50.8/52.6cm. Disabling foot grounding retains these values, so the stair modifier is not the cause of the measured unequal hip dip. Prior tests allowed 18cm hip range but never checked alternating trough balance.

MERGE delta, current -> candidate: correctness 2->4, ownership clarity 5->5, runtime parity 5->5, editor usability 3->4, performance 5->5 (library-time only), regression coverage 2->4. Evidence: operator_gait_alignment.gd, main_run_stride_regression.gd and run_stride_proof measurements. Candidate averages the grounded hip-height curve with its half-cycle partner for forward run only, bounded to 2.5cm correction, without changing rotations or the gait clock. Verify foot clearance after the change; reduced hip imbalance alone is not proof of a polished run.

Shared profile: `locomotion.forward_run_hip_balance` in the canonical animation map and existing hybrid preset; the library cache fingerprints the saved setting. Original assets remain untouched. Official Animation interpolation API consulted: https://docs.godotengine.org/en/latest/classes/class_animation.html (installed Godot 4.7.1).

## Hopping follow-up translation card

Player intent: grounded running rather than a repeating hop, including pistol movement. Acceptance: steady forward hip travel at most 5cm in main.tscn, unchanged speed/timing, preserved ankle paths within 1cm, no one-sided trough or floor loss. Owner: existing library-time gait preparation. Protected: source resources, upper-body tracks, CharacterBody/camera/combat, jump and non-running states. Proof: source-copy/foot-path unit checks, main rifle/pistol run with side/rear captures, gait/lean and jump regressions. This is character-specific fitting, not a claim of exact source-engine parity.

New evidence: the previous balance passes symmetry but retains about 12cm total hip travel. The source pistol run is upper-only; the existing builder explicitly fills missing tracks from seal_run. Do not re-extract identical data or mislabel the composition a full native pistol take. Browser reference https://www.youtube.com/watch?v=5kRpj3CnGi8 opened successfully; gameplay around 0:30–0:42 inspected, but camera motion/stairs prevent a calibrated metric comparison.

MERGE delta: correctness 2->4, ownership 5->5, runtime parity 5->5, editor usability 4->4, performance 5->4 (one-time bake), coverage 3->4. Candidate caps the forward-run hip-height range at saved 4cm and refits only the six leg rotations to the pre-correction ankle targets with the existing two-bone solver. No per-frame competing bone writer. Reject if foot-path preservation or rendered posture fails.

### Verified checkpoint

- Main-scene forward M4 run: hip travel 0.04097m grounding on / 0.04116m off; worst steady-frame step 0.00894m. Mark 23: 0.04106m / 0.04114m, step 0.00944m. Both retain 6.5m/s, floor contact, balanced troughs and support limits.
- Library unit check: 120 interpolated samples retain ankle trajectories within 0.00319m for rifle/pistol; source resources, upper-body keys and duration/loop unchanged. The initial unit setup ran before tree entry and produced invalid global-transform results; deferred initialization fixes that harness, not the game.
- Rendered side/rear early/middle/late poses inspected in `art_source/run_stride_low_bounce_proof` and `art_source/run_stride_low_bounce_proof_pistol`. These show the current fitted character, not a 1:1 SOCOM verification. Pistol high carry/upper-body presentation remains visibly distinct and was not changed in this pass.
- PASS: gait alignment/foot-path unit, both main run fixtures, gait/lean continuity, source jump, 129 feature contracts, focused whitespace check. Aggregate quick gate remains blocked because branch is `codex/render-deployment`, not `main`; branch preserved.
- Local project only. Start a new local `main.tscn` run to load the prepared library. No existing user game was restarted and no browser ZIP was exported. No new ISO extraction performed.

Pistol source inventory: `seal_p_run`, `seal_p_run_90l`, `seal_p_run_90r` are present as upper-only resources; `seal_p_run_bw` is full. Forward gameplay composition explicitly uses `seal_run` for absent typed tracks. `seal_pfp_run_composed` likewise records `metadata/seal_composite_base = "seal_run"`. Their presence does not establish correct source-engine blending; further work should compare decoded track coverage and original blend rules before requesting duplicate extraction.

Relevant implementation: `operator_asset_runtime.gd::_align_grounded_gaits` invokes `limit_run_bounce` only for four forward run slots. The saved `"forward_run_max_hip_travel_m": 0.04` is loaded by `operator_animation_profile.gd` and included in `operator_animation_library_cache.gd` fingerprint. The height equation is `p.y = minimum + (p.y - minimum) * maximum_travel / (maximum - minimum)`; the existing leg solver restores each pre-fit ankle target before rotations are saved to the runtime copy.
