# Rifle source-pose runtime audit

2026-09-12. Bounded observation, not a runtime promotion.

## Translation card and system delta

- Intent: retain the imported SOCOM rifle poses without silently breaking the
  playable rifle's aim or hand attachment.
- Acceptance: real `main.tscn` movement and accepted fire/reload; measure the
  completed pre/post-presentation pose pair, trigger/support contact and bore.
- Owner: `tools/main_rifle_source_pose_audit.gd`, an observer extending the
  existing input-driven `tools/main_source_motion_proof.gd`.
- Protected: all runtime/profile/asset writers; CharacterBody movement,
  camera/aim intent, weapon authority and action durations.
- Proof: M4 baseline and a process-local profile differing only by
  `locomotion.source_pose_only=true`; optional rendered captures use the same
  inherited frozen-frame cameras. This pass was headless, not a visual approval.

Decision: **MERGE** the observer; **REJECT** promotion of the global toggle alone.
Scores (0–5, current / unmodified global-source candidate): correctness for
playable rifle 4/1; ownership clarity 4/5; canonical runtime parity 5/5; editor
usability 3/3; presentation performance 3/5; regression coverage 4/4. Evidence is
the two reports below and the runtime branches quoted here. The candidate
eliminates bone corrections but fails measured combat presentation.

## What the toggle actually does

At the audited revision,
`scripts/player/operator_animation_driver_runtime.gd:136` forwards the saved
global flag to posture and weapon consumers. It also clears saved frame-pose
corrections, suppresses spine/lean/head correction, and bypasses foot locking.
`scripts/player/operator_weapon_pose_ready.gd:62` executes:

```gdscript
_stop_socket_ik()
skeleton.clear_bones_global_pose_override()
skeleton.force_update_all_bone_transforms()
present_traversal_equip() # rigid right-palm mount
if source_pistol_attachment and action == &"":
    SourcePistolAttachment.aim_upper_body(...)
```

That branch has no equivalent rifle aim adaptation in the tested revision.
It explicitly sets `animation_owned_aim_alignment_active=false` and
`authored_shoulder_stock_active=false`. It measures the free support gap rather
than solving it. `operator_animation_driver_runtime.gd:476` also skips normal
rifle finger grip presentation when `source_pose_only` is true. The flag is
therefore not merely a way to turn off old gait offsets.

## Results from the actual main scene

Both tests used the selected
`res://assets/characters/modern_soldier/modern_soldier_iso.scn`, M4A1, commanded
standing/crouched forward/left/right movement, six directional accepted shots,
one standing idle accepted shot and one committed reload. Each checked 612
presentation samples across the physical actions.

| Measurement | Saved baseline | Global source-only trial |
| --- | ---: | ---: |
| Post-tree bone displacement maximum | 0.31708 m | 0 m |
| Post-tree basis-column difference maximum | 1.86101 | 0 |
| Trigger, finite-transform, grounded/action gates | PASS | PASS |
| Settled rifle combat geometry | PASS | FAIL: 13 findings |

Basis-column difference is dimensionless, **not degrees**. The observer compares
the same completed presentation pass before/after the driver; it does not
compare final skin deformation against an emulated original-game render.

The following are matched *action labels*, not identical original source-phase
timestamps, sampled 21 physics ticks after accepted fire:

| Standing direction | Baseline support / bore | Source-only support / bore |
| --- | --- | --- |
| Forward | 0.041 cm / 0.036° | 6.34 cm / 17.36° |
| Left | 0.042 cm / 0.015° | 14.18 cm / 25.55° |
| Right | 0.003 cm / 0.028° | 11.53 cm / 6.34° |

The trial's crouched support gaps were 6.30–9.15 cm in corresponding late-fire
samples. Source-only settled standing-left bore error reached 25.80°. A rigid
whole-upper-body rotation can address aim while preserving relative arm pose,
but cannot by itself change a support gap when gun and arms rotate together.
Rifle-specific mount/contact calibration is a distinct integration requirement.

Reports:

- `/private/tmp/rifle-source-baseline-m4-v1.json`; saved profile SHA-256
  `226290c623793afde7e4737c38541e65ce5ab02ace0d16df23d98d4156f992c8`.
- `/private/tmp/rifle-source-pure-m4-v1.json`; candidate profile SHA-256
  `6a6052a97188eceb79c6c204e3449c12a6576a5c8fe1d544ec70b2e08bfe4b2d`.
- Same-name `.log` files: no script errors, only the known macOS CA warning.

The JSON `pass` describes observer/contact/action assertions; inspect the
separate `combat_failures` and `safe_for_gameplay_promotion` fields. Use
`--require-combat-alignment` to make those geometry findings a failing exit code.

## Native route evidence and limitations

The audited runtime graph resolves rifle carry forward/left/right to
`seal_run`, `seal_run_90l`, `seal_run_90r`; ready/fire resolves to
`seal_fp_run`, `seal_lstrafe_fast`, `seal_rstrafe_fast`. These actual Animation
resources carry `seal_reference=true`, `source_name` and `source_sha256`.
The report stores metadata for 24 walk/run/crouch cardinal carry/fire routes.
Generic `current_clip` debug aliases can differ from the equipped-family route;
neither the alias nor a source filename proves the final mixed pose is 1:1.

Not covered by this bounded pass: prone movement, jump/climb/vault, every weapon,
original-game speed thresholds, source-vs-retarget skin deformation, original
camera composition, or rendered visual approval. A zero post-tree delta does
not prove any of these. Root owns the separate native-rifle adaptation and its
subsequent validation; this report records the unmodified-toggle comparison.

## Reproduction

Use the installed Godot 4.7.1 executable with `--headless --path` set to this
project and `--script res://tools/main_rifle_source_pose_audit.gd`. After `--`:

```text
--write-toggle-candidate=/private/tmp/rifle-source-toggle-only-20260912.json
```

This writes an offline candidate only; it does not activate it. Then run:

```text
--profile=/private/tmp/rifle-source-toggle-only-20260912.json --require-source-only --output-prefix=/private/tmp/rifle-source-pure-m4-v1
```

Omit `--profile` and `--require-source-only` for saved baseline. Add
`--require-combat-alignment` for promotion checks. `--weapon=ak-47` selects the
other bounded rifle. Optional `--capture` requires a display-backed run. Never
use `--automated-test`; it disables the movement path under test.
