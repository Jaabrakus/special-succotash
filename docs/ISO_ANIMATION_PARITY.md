# Source animation parity audit

Translation card: preserve and account for every primary-archive animation before
replacing runtime actions. Acceptance: re-extract all MOTION_P entries directly
from the ISO, validate complete motion decoding/quaternions, hash original bytes,
inventory retarget files and saved-profile dependencies separately. Owner: offline
audit_iso_motion_coverage.cjs. Must not change movement, camera, server combat,
original assets or current animation mappings in this audit. Proof: direct-source
decode and comparison with existing library/Blender manifests; no visual parity claim.

System delta: KEEP current runtime pending per-state proof; MERGE verified source
inventory. Scores correctness/ownership/parity/editor/performance/regressions:
current 2/5/3/3/5/3; audited candidate 2/5/3/4/5/4. Evidence: importer, runtime
library builder, source gait adapter and the reproducible coverage tool below.
The inventory improves traceability, not pose correctness by itself.

## Confirmed current pipeline

- `tools/import_seal_reference_animations.gd` retargets rest-aware, omits helper
  channels without a known parent, and clears position X/Z. This is deliberately
  not raw 1:1 playback of the original skeleton.
- `tools/build_seal_gameplay_candidate.gd` fills missing pistol leg tracks from
  rifle clips and phase-normalizes their key times. This is a composition, not
  evidence of the original engine's blend function.
- `scripts/player/operator_asset_runtime.gd::_align_grounded_gaits` and
  `scripts/player/operator_gait_alignment.gd` modify runtime copies to ground feet
  and limit forward-run hip travel. Those adjustments intentionally differ from
  source motion. Removing them without a tested replacement risks restoring the hop.
- `tools/blender/build_seal_source_library.py --all-seal` produced 264 editable
  source-skeleton actions in the existing workbench. This is not 264 finished,
  skinned-character/runtime replacements.

## Scope and next acceptance gates

The primary archive has 334 clips: 264 seal_ actions, 22 additional retargeted death
actions and 48 civilian/guard actions not yet retargeted. Mission-specific banks
are outside that count; do not call it every animation on the entire disc.

For each runtime action family, compare source and target at identical normalized
times, show the actual skinned character, and isolate base pose versus each modifier.
Record timing as source duration, source playback setting (uninterpreted until its
consumer is verified), runtime duration and blend time. Prove partial-track masks,
weapon attachment and aim layers before changing the saved operator profile.

Do not bind NPC restraint/torture/menu actions to player locomotion merely to increase
the number of imported clips. Unsupported gameplay states stay explicitly unbound.

Audit command (NEW_OUTPUT_DIR must not exist):

```sh
node tools/audit_iso_motion_coverage.cjs ISO DECODER_DIR PROJECT NEW_OUTPUT_DIR
```

Output preserves raw clips and decoded tracks alongside coverage.json. It refuses
to overwrite an existing directory and never edits the ISO or runtime assets.

## Results, 2026-09-12

Fresh output: /private/tmp/socom-iso-motion-audit-20260912/coverage.json and motion/.
334/334 motions decoded; 286 already have retarget resources; 94 source names are
resolved from saved-profile paths and source metadata. Programmatic runtime clip
creation is not exhaustively traced by that offline dependency count.
No animation runtime mappings were changed by this audit, and no new identical-
in-game replacement is claimed. All 264 seal_ actions exist in the prior editable
workbench /private/tmp/socom-full-seal-library-20260912/socom_source_actions.blend;
its validation.json records 6029 source samples, not skinned-runtime verification.

The initial MPZANIM archive probe failed the existing extractor's unsafe-name
guard. Read-only name-table inspection found dialog paths and control commands
(e.g. MENUFADER/CLEARGAMESTATE), not evidence of another motion bank. The guard
was preserved; no filenames from these tables were written to disk.

Still partial: source blending/playback interpretation, all per-state skinned
runtime comparisons, 48 NPC retargets, mission-specific motion bank inventory,
and new approved runtime replacements. The useful next pass is the 94 referenced
source actions, beginning with rifle/pistol locomotion and stance/fire transitions.
