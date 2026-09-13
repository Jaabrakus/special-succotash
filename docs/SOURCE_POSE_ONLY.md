# Source-pose-only presentation

## Translation card, before implementation

Intent: remove the older body/weapon pose overrides from the normal game and let
the ISO-derived clips retain their own hand use. Running pistol carry and firing
run have a free left arm; stationary fire is a different source pose. Never infer
one universal two-handed grip from the gameplay family name TWO_HAND_PISTOL.

Acceptance: the saved `locomotion.source_pose_only` policy is consumed by the
existing animation and weapon presentation owners. No legacy pistol upper node,
procedural torso/shoulder/head/foot correction, arm IK, finger curl, or saved
per-frame pose correction changes the evaluated source motion. The rigid weapon
follows its authored trigger palm without moving either arm. Real canonical
forward/left/right movement, accepted shots and recovery preserve this policy.
Check rendered early/mid/late frames and state/action transitions. Passing palm
contact alone cannot certify a pose: the previous candidate passed that test
while visibly destroying the source free arm.

Owner: SocomOperatorAnimationDriver, dispatching weapon transforms through the
existing WeaponPresentationOwner. Shared contract: operator_animation_map.json.
Preserve: CharacterBody collision/root-motion ownership; camera aim; authoritative
shots, damage, reload timing; source resources; clip crossfades; supported AGLS
traversal/contact and safe placement. Disabling old corrections is not deletion
of unrelated code or original assets. False retains the previous profile path.

Proof: source hand-use FK audit; source_pose_only_main_regression through
main.tscn, source weapon non-mutation regression, cache separation, rendered
motion proof and feature contracts. An isolated fixture is not the final proof.

## System delta

REPLACE the active legacy correction path with source-owned presentation after
proof. Current scores (correctness/ownership/runtime parity/editor/performance/
tests): 2/4/2/4/3/3. Candidate: 4/5/4/4/5/4 conditional on verification.
Evidence: operator_pistol_upper_layer.gd replaces every upper-body track;
operator_seal_weapon_pose.gd locks and solves both arms even when seal_p_run and
seal_pfp_run author an independently swinging left arm. The pure mode preserves
that source arm instead of maximizing a physically irrelevant support contact.

## Explicit limits

The existing character proportions, sparse-track reconstruction, root-motion
normalization, phase blending and playback rate are not original-engine parity.
Removing procedural aim means the rendered barrel follows the source wrist;
vertical barrel-to-reticle parity is not promised without native aiming blends
and calibrated grip rotations. Camera/shot direction is unchanged. Unauthored
finger bones retain the character rest pose; no hidden procedural fist is added.
AGLS traversal is still a separate supported action path, not SOCOM ISO data.

## Verification and promotion decision

MERGE the opt-in candidate and its regression coverage; do not replace the saved
main default. The earlier conditional candidate score was too optimistic: rendered
review leaves correctness 3 and original runtime parity 3. The feature contract
records that revised score. The candidate is
`config/animation_presets/seal_source_pose_only.json`; this pass did not copy it to
`config/operator_animation_map.json`.

The implementation boundary is explicit in
`scripts/player/operator_weapon_pose_ready.gd:30`:

```gdscript
if source_pose_only:
    _present_source_pose_only(aim_yaw, aim_pitch, posture, movement_state,
```

The source-only branch stops arm IK and uses the existing rigid palm mount. This
preserves evaluated arm motion; it does not reconstruct missing original aim
processing or original weapon-socket orientation. The typed profile defaults the
flag to false, resets it before loading a legacy profile, and includes it in the
animation-library cache fingerprint.

Results from this pass:

- Done: opt-in policy through the existing main scene owners, zero measured
  post-tree body rotation/position edits over 432 checked frames per weapon for
  Mark 23 and AK-47; real queued standing/crouched movement and accepted shots.
- Done: main-scene reload commits ammunition and finishes; running Jump leaves
  the floor and lands, with the source-only arm policy retained.
- Done: profile regression covers nine pistols, 297 native route checks, three
  handling families, cache separation and loading the legacy profile afterward.
- Done: focused posture regression preserves the real source lean while disabling
  the old procedural body corrections. Historical pistol fallback regression passes.
- Done: feature integration graphs pass for 132 contracts. This is not a rendered
  animation-quality verdict.
- Partial: rendered early/middle/late motion, firing, reload and jump samples were
  captured through `main.tscn`. The right-strafe firing hand/grip is visibly wrong;
  no visual acceptance or source-exact claim is made.
- Partial: six editable skinned clips have verified Godot-to-Blender interchange,
  but the workbench uses the canonical PS1 fallback, not the separately selected
  modern soldier. See `docs/SOURCE_RIG_WORKBENCH.md`.
- Not done: original directional aiming code, original gun mount/finger handling,
  all-animation original-engine equivalence, and promotion of this candidate.

Logs: `/private/tmp/source-only-render-v2.log`, `/private/tmp/source-only-ak.log`,
`/private/tmp/source-only-profile-final.log`, and
`/private/tmp/source-only-contract-final.log`. Render/report inventory:
`/private/tmp/source-only-render-v2/mark23.json`.

The full quick integration script requires branch `main`; it rejected the current
`codex/render-deployment` branch. The branch and unrelated dirty work were preserved.
Its checks must not be reported as having run successfully.

## What the failed rendered right-strafe pose means

The original forward-running `seal_p_run` and firing-run `seal_pfp_run` demonstrate
an independent left arm. That is not evidence that every pistol direction is
one-handed. The subsequent original-skeleton FK audit confirmed direction-specific
hand use: `seal_p_rstrafe_fast` keeps the wrists 0.137–0.162 arm lengths apart,
whereas `seal_p_lstrafe_fast` separates them 1.927–2.065 arm lengths. Both use raw
source frames, not the retarget or any IK. Right-strafe close hands are therefore
not themselves a bug; the visible hand shape and weapon attachment still fail.
The main ready-right slot uses a different source clip:

```json
"locomotion_ready/run_right": "seal_p_rstrafe_fast"
```

The extracted animation table calls this "Pistol strafe right fast". The reviewed
source settings also contain `aimnodes`, `max_aim_yaw` and `NoPitchtwist`; their
presence supports investigating original runtime aiming but does not supply its
bone masks, equations, coordinate space or composition order. The original motion
records also have different right/left speed-transition thresholds, but no
strafe-specific firing callback or aim mask was found in those records. See
`docs/SOURCE_POSE_AUDIT.md` for source FK metrics and
`docs/SOURCE_RIGHT_STRAFE_AUDIT.md` for complete original motion records. Neither
finding authorizes changing player physics to match an unverified unit scale.

There is also a concrete weapon-specific omission: all three inspected movement
takes have a detached `pistol` helper, and its local rotation differs in right
strafe. `tools/import_seal_reference_animations.gd:160` excludes it because its
parent was not recovered. This is a candidate cause of the attachment mismatch,
not proof: a local quaternion cannot be applied correctly until its parent and
reference frame are established. Recover that relationship before inventing an
arm correction or applying the helper as a world-space gun rotation.

The shown source-only rendering has open fingers and an incorrect hand/weapon
fit. The inspected pistol run resources have no finger tracks, so removing our
finger correction cannot reveal a missing original finger pose. No global
two-handed solver should be restored just to hide this missing input.

Character selection also changed concurrently during these checks. The separately
selected ISO-proportion modern asset has collapsed anatomical joint spacing,
despite internally valid inverse binds. The later normal-body render and earlier
distorted-body render must not be conflated. This pass did not edit that selection
or either character asset. Measurements, captured binary hashes and the suspected
builder mechanism are in `docs/SOURCE_RIG_SELECTED_ASSET_AUDIT.md`.

## Running the candidate safely

Ordinary Play still loads the existing saved main profile; it does not automatically
enable this experimental policy. To reproduce the main-scene observer in a separate
process without altering the saved profile:

```sh
/Users/kiwimango/Applications/Godot-4.7.1.app/Contents/MacOS/Godot \
  --headless --path /Users/kiwimango/socom-141-camera-lab \
  --log-file /private/tmp/source-only-review.log \
  --script res://tools/source_pose_only_main_regression.gd -- \
  --profile=res://config/animation_presets/seal_source_pose_only.json
```

This is an automated main-scene proof, not interactive play. Do not use
`--automated-test`, which disables the gameplay input path being tested. No browser
ZIP, emulator build, network deployment or character replacement was made here.
