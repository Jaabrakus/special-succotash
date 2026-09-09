# SEAL reference animation import

## Translation card

- Player intent: test the extracted third-person SEAL rifle/common, pistol and death animations on our existing character without losing our animations.
- Acceptance: all 261 selected decoded clips have distinct target-native resources, source identity/timing/loop metadata and partial/static labels; Animation Studio discovers them; existing gameplay mappings remain unchanged. The same resources can be explicitly assigned through the existing authored-animation runtime path.
- One owner: `SocomAnimationWorkshopRepository` owns catalog discovery; existing AnimationPlayer/animation driver owns presentation. The offline importer writes assets, never player state.
- Must not change: character mesh/rests, gameplay mappings, movement/collision, camera/reticle, weapon/damage, networking, existing animation files and parent-thread work.
- Focused proof: catalog completeness, finite normalized transforms, compatible target bone paths, partial track masks, source duration/loop preservation, actual AnimationPlayer seek, authored runtime consumption, feature-contract gate.

## System delta

MERGE an optional reference library into existing discovery, not a second animation controller. Reuse the existing rest-aware baking service. Keep the original decoded files and Blender review library untouched. Current: standalone decoded review only (correctness 3, ownership 5, runtime parity 1, editor usability 2, performance 5, tests 3). Candidate: native optional resources plus verified discovery (3, 5, 4, 4, 5, 4). Evidence: `scripts/labs/animation_retarget_service.gd`, `scripts/labs/animation_workshop_repository.gd`, `scripts/player/operator_asset_runtime.gd`, and the focused import regression.

## Limits

These are reference/test assets, not automatic replacements for our current actions. Retargeting transfers rotations relative to each skeleton's rest frame and scales hip displacement; it preserves target limb lengths. It does not reproduce original mesh proportions, weapon attachment transforms, game blending or missing channels. Horizontal root travel is stripped from target clips because CharacterBody3D owns movement. Original decoded samples remain in the external extraction/viewer source.

Partial clips remain partial: absent hips/legs are not filled with invented motion. Static poses are not presented as moving clips. Reader playback values are retained as metadata, not assumed to be universally valid speed multipliers. Source one-shot/loop values are retained in preview; gameplay uses its existing explicit profile loop policy when a clip is assigned. Finger animation is unavailable in the recovered source rig. Weapon contact and the previously observed raw wrist jumps still require per-clip review.

The original importer accepts the reviewed viewer `data` directory after `--` and refuses to replace an existing import directory. It excluded `seal_fp_*`, `seal_pfp_*`, guard and civilian clips. **Correction:** SOCOM's extracted animset labels the fp/pfp families as firing poses/movement, not first-person clips. The exclusion was an incorrect semantic assumption. `tools/import_seal_firing_poses.gd` recovers them separately without overwriting the original 261 resources. Nothing is published to GitHub or a browser build by these tools.

## Import result and use

261 resources are saved in `assets/animations/seal_reference`: 160 rifle/common, 79 pistol and 22 death clips. Reopen Animation Studio, select the PS1 gas-mask skin and search `SEAL`. Entries retain the original clip name and show `STATIC` or `PARTIAL` where applicable. They are unassigned candidates. Existing Studio assignment/body-layer workflows remain the explicit route into gameplay; do not assign a partial overlay as a complete locomotion state.

The current runtime can load these same `.tres` files through its authored-resource branch. The import test exercises that branch with an isolated in-memory profile, not the saved gameplay configuration. Importing is not activating or publishing.

Verified 2026-09-09: focused regression passed for 261 resources and 783 actual AnimationPlayer seeks, all 261 canonical authored loads, source duration/loop policies, finite transforms, partial-mask preservation, catalog playback keys, incompatible-name rejection, and original Studio skin/canonical target mapped-rest agreement. Workshop repository and Studio architecture regressions passed; the feature-contract gate passed all 96 contracts. `git diff --check` passed. The aggregate quick gate did not run its checks: it requires `main`, while this checkout is `codex/render-deployment`.

Reusable import lessons: source reader settings may be null (retain unknown settings instead of inventing values); visible classification labels are not playback identifiers (Godot forbids brackets in animation keys). Reference IDs now use source filenames, independently of review labels. Numeric playback checks do not certify visual weapon contact or original-game blend fidelity.
