# Source animation selection audit — 2026-09-13

**Current status: source backward crawl is NOT enabled in main.** Original
reverse selection is proven and its isolated runtime candidate passed routing,
but native renders failed knee/floor contact. The canonical flag is false and
the previous backward animation mapping has been restored. Source-height
correction alone is insufficient; details and measurements follow below.

## Translation card (read-only)

- Intent: compare canonical standing/crouching/prone rifle and pistol selection
  with original SOCOM II records and original selector instructions.
- Acceptance: preserve complete source action/mode records and source hashes;
  distinguish configured, reachable and unproven routes; execute a bounded
  original weighted-choice slice with disclosed inputs.
- Owner: offline `tools/source_animation_selection_audit.cjs` only. This audit
  neither selects an animation in the game nor adds a second animation clock.
- Protected: all runtime/config/assets, current hybrid camera and spine work,
  movement/collision, weapon/damage authority, source files, live game sessions.
- Proof: original-module SHA checks, source-reader census, original action-name
  registration table, differential weighted-choice fixtures, and an explicit
  current-config snapshot. No native game or browser launch.

System delta: **MERGE evidence only**. Existing source-controller docs correctly
label their weighting law as inferred, but no single artifact compares both
families with the original mode table. Evidence scores (0–5), current → audit:
correctness 3→4, ownership 5→5, runtime parity 3→3, editor usability 3→4,
performance 5→5, regression coverage 3→4. Runtime parity cannot rise merely
because an offline audit passes. No feature activation or gameplay contract is
added by this document.

The current explicit project root is `/Users/kiwimango/socom-141-camera-lab`;
the workflow skill's historical Documents alias is not used for this task.

## Findings

The offline audit passes 79 complete SEAL action records, 398 motion records,
72 weighted-choice fixtures and four original prone-direction fixtures. No
unknown function stubs, original game launch or native display were used.

## Bounded integration card: source backward crawl

- Intent: backward prone movement uses the original crawl pose sequence rather
  than a different Mixamo animation.
- Acceptance: canonical `main.tscn` uses the same source `seal_prone_crawl` for
  forward and backward travel; the latter AnimationNode plays backward. Actual
  queued movement produces backward displacement and returns to idle. Both
  rifle and pistol retain their existing fire/reload and physics owners.
- Owner: existing ProductionAnimation/AnimationTree, built by
  `operator_locomotion_blend_tree.gd::_prone_direction_space`.
- Saved contract: `locomotion.source_prone_backward` plus existing source clip
  mapping in `config/operator_animation_map.json`. No source animation copy or
  mutation and no secondary timeline. Invalid/off policy retains old routing.
- Protected: movement/collision, source playback/cadence calibration, aim/camera,
  spine, traversal, firing/reload layers, weapon attachments, network authority.
- Proof: original selector/sign fixtures above, focused off/invalid routing,
  and actual queued main-scene forward/backward commands for M4/Mark23.

System delta **MERGE** this one proven source rule into the existing graph.
Scores current → candidate: correctness2→4, ownership5→5, runtime parity3→5,
editor usability4→4, performance5→5, regression coverage2→4. Evidence is not a
claim of complete prone pose/foot contact or original cadence fidelity. The
broader source blend implementation is owned by a separate task.

Profile-reuse delta: **MERGE** a reset of this opt-in at `load_project_map`
entry. A workshop profile loaded first from the canonical map and then from an
older preset must not retain the first map's flag. The focused proof reloads
`seal_pistol_hybrid.json` on the same profile and checks both the flag and graph
fallback. No existing preset data is rewritten.

## Original evidence and current selection table

Pinned original ZSealEtc module:
`art_source/socom2_ballistics_reference_20260912/decoded_runtime_v1/ZSealEtc.bin`,
SHA256 `cdb3fa8e707090ac879874e3987c6b7784808a4767e85d0e19fc6909d36549b1`.
Runtime address = file offset + `0x4c5380`, as independently verified in
`docs/SOURCE_MODULE_ADDRESS_MAP.md`.

Decoded readers (JSON hashes, **not** original packed-reader byte hashes):

| Reader in extractor `output/readers/` | SHA256 |
| --- | --- |
| `animset.rdr.json` | `6462c387c3d452b19df2eddf3cbde5f7543f1e0c23070e6e8069cf554e785f64` |
| `motion.rdr.json` | `ac1a191449bb18f9c59916d516cf1ea435ab59cf6e80aa38b961995c1489d7fa` |
| `motion_range.rdr.json` | `dcf39bb12da39f6fee0a4229617624e8dea32bab146e9ce250d9f208af6f0fd3` |

The tool retains all79 relevant complete records, including nested modes and
flags; it does not flatten weighted alternatives into one arbitrary name.
It also stores all398-motion-record count and all SEAL motion settings, resource
metadata and hashes, family slots, and source-code excerpts. Original source
prefix below is `seal_`; `p_` denotes the distinct pistol take and `fp/pfp` the
named source firing action. A source name is provenance, not visual parity.

| State/action | Original selection record | Current canonical selection before this bounded change |
| --- | --- | --- |
| Rifle standing idle | Stand/default=`stand` | Correct `idle_rifle` → `stand` |
| Rifle standing ready | Stand/ready=`stand_alert01` .5, `stand_alert02` .5 | Only `stand_alert02`; weighted alternative absent |
| Rifle standing fire | Fire stand=`fp_stand` | Separate `fp_stand`, correct named action |
| Rifle crouch idle | Crouch/default=`crouch` .3, `crouch_alert01` .3, `crouch_alert02` .4 | Only `crouch`; two default alternatives absent |
| Rifle crouch/prone firing | Fire crouch=`fp_crouch`, Fire prone=`fp_prone` | Corresponding ready/accepted-fire graph branches use those sources; timing is a separate adapter |
| Pistol standing/crouch/prone idle | `p_stand`, `p_crouch`, `p_prone` | Corresponding saved source-backed clips, despite historical `compressed` filenames |
| Pistol firing | `pfp_stand`, `pfp_crouch`, `pfp_prone` | Named sources present; crouch/prone partial source channels are explicitly composed, not original full-body takes |
| Rifle forward tiers | Walk/default=`walk_alert`, Walk/ready=`walk_alert02`, Jog=`jog_alert`, Run=`run` | Default walk/jog/run wired; moving ready uses firing takes, not a distinct original Walk/ready branch |
| Pistol forward tiers | `p_walk`, `p_jog`, `p_run`; firing `pfp_walk`, `pfp_jog`, `pfp_run` | Walk/run graph exists, no jog tier; sprint-only fallback targets full/run while moving |
| Rifle lateral walk/jog/run | `l/rstrafe`, `l/rstrafe_fast`, `run_90l/r` | Corresponding source cardinal takes; firing-ready run uses fast-strafe, not running90 |
| Pistol lateral walk/run | `p_l/rstrafe`, `p_l/rstrafe_fast`, `p_run_90l/r` | Source walk/run90; firing-ready uses source fast-strafe. Exact original direction/fire choice remains unproven |
| Crouch cardinal movement | Rifle and pistol crouchwalk/back/left/right actions | Source cardinals wired; no distinct source step tier |
| Prone movement | `prone_crawl`, `prone_rstrafe`, `prone_lstrafe` | 1D forward/back space; backward was Mixamo and lateral inputs choose forward crawl |
| Stand→crouch/prone | `stand2crouch`, `stand2prone`, pistol equivalents | Imported takes do not establish runtime stance entry; posture change crossfades existing base |
| Crouch→prone | `crouch2prone` | Imported and saved semantic route, no production posture-change caller found |

Table is a bounded snapshot, not a claim that configuration alone proves the
whole scene. `tools/source_locomotion_controller_regression.gd` and
`tools/source_rifle_default_idle_regression.gd` already provide actual-main
rifle gait/idle/fire proofs. The new backward-crawl tool supplies actual-main
coverage of this change. Parent tasks may change the other gaps after this
snapshot; each generated report preserves the exact files/hashes inspected.

## Verified source code: weighted variants

The fixed source action-name table starts at `0x661060`. Registration
`0x5e324c–0x5e3298` walks pointers four bytes at a time and stores the ascending
index at each named registry entry `+12`. Relevant IDs include Stand1,
Stand→Crouch17, Crouch18, Crouch→Prone19, Stand→Prone25, Prone26,
Prone crawl27, Pistol stand83, Pistol crouch84, Pistol prone85,
Pistol walk88, Pistol jog89 and Pistol run90.

Original mode choice at `0x5e5970` handles a single packed clip index or a
weighted set. The multi-choice branch invokes RNG at `0x5e59d4`, then:

```text
0x5e59e8 cvt.s.w f1,f1
0x5e59ec lui v0,0x3000        # float bits for 2^-31
0x5e59f8 mul.s f1,f0,f1
0x5e5a00 lwc1 f0,4(s1)       # saved choice weight
0x5e5a04 add.s f20,f20,f0    # cumulative weight
0x5e5a08 c.ole.s f1,f20      # random <= cumulative
0x5e5a28 lw v0,0(s1)        # selected clip index
0x5e5a44 lw v0,-8(s1)       # last-entry fallback
```

The72 fixtures execute this actual code with disclosed integer RNG results,
original ready/crouch weights and an underfilled-CDF fallback fixture. They
include float32-rounding boundary neighbors. This proves weighted selection,
not when the playable controller requests ready or reselects an idle. Do not
choose a new random clip each frame. The existing1.2s accepted-fire grace is
still project policy, **not** decoded original alertness timing.

Original mode change `0x57d710` stores actor mode at+4918, re-resolves active
actions through `0x5e3c20`, falls back to mode0, and requests a transition
snapshot using the new clip's+32 blend-time field. The precise blend equation
belongs to `docs/SOURCE_BLEND_RUNTIME_AUDIT.md` / its corresponding audit, not this
selection report. No weighted randomness is added to gameplay in this pass.

## Verified source code: reverse crawl and genuine lateral actions

The original caller at `0x584680–0x58469c` forwards actor control fields576/580
to local temporary input channels. `0x5858a0` classifies their dominant direction.
For the longitudinal-dominant branch, `0x585944–0x585994` assigns direction1 for
positive input or3 for negative input while retaining analog magnitude.
The prone controller takes that same input at `0x584abc–0x584acc` → `0x583500`.

```text
0x583530 mov.s f24,f12       # original longitudinal control
0x58359c beq v1,v0,0x5835d8 # direction3
0x5835a8 beq v1,v0,0x5835d8 # direction1
0x5835e0 mov.s f23,f20      # suppress lateral for those directions
0x583724 addiu a1,zero,27   # SAME Prone crawl action
0x583730 jal 0x588bc0
0x583900 c.olt.s f24,f20    # f20 is zero here
0x58390c neg.s f22,f22      # backing up reverses speed
0x583920 lwc1 f0,28(v1)
0x583924 jal 0x28d570       # original playback-factor setter
0x583928 mul.s f12,f22,f0
```

Four fixtures (+1,+.4,−.4,−1) execute classification, action-request and signed
playback slices with no unknown stubs. They deliberately do not execute full
list allocation, actor collision or a live frame. Independently,
`tools/source_blend_runtime_audit.cjs` executes the original clock and proves
instance+36 is signed playback: `FTS0x28c594` loads it and `0x28c5ac` consumes
it; negative looping time wraps backward. Thus the negative sign is not merely
a heading flag.

Source lateral actions are also real controller branches: original
`0x5e24b4–0x5e24ec` registers strings `Prone rstrafe` at`0x6619e0` and
`Prone lstrafe` at`0x661a08` into globals`0x3decc0`/`0x3decd0`.
`0x5837e0` and`0x583898` request those actions based on lateral sign.
They are **not implemented** by the current 1D prone graph. This pass only
replaces backward crawl; it does not mislabel current lateral steering as
source lateral-animation integration.

## Current runtime excerpts and prioritized remaining deltas

1. **Pistol gait tier gap:** `operator_locomotion_blend_tree.gd` function
   `_configure_source_controller` still rejects families other than
   `TWO_HAND_RIFLE`. `update` only bypasses `standing_sprint_only` when that
   controller is active. Pistol phase synchronization was added concurrently;
   shared phase does not add its missing jog branch. Source pistol forward A/B
   bands are walk0/2.8, jog2/4.6, run3.8/6.5. These are speed-band data, not
   seconds and not permission to change movement speeds.
2. **Prone lateral routing gap:** source left/right are real registered and
   selected actions; current `_prone_direction_space` has only forward/back.
   Add a separately tested source2D route, not arbitrary mesh/hip yaw.
3. **Stance transition caller gap:**
   `operator_animation_driver_runtime.gd:287` currently only updates
   `_previous_posture`; line302 selects the new base. Saved
   `posture_to_prone`/`posture_to_standing` are not production calls. Do not
   activate them blindly: incoming/outgoing timing, reverse direction and
   NoFire/NoInterrupt ownership require source/controller proof.
4. **Mode variant gap:** default crouch's weighted3-way set and ready stand's
   weighted2-way set are proven; the graph currently hard-selects one. First
   preserve selection across an action lifecycle, then test changing modes.
5. **Unknown moving-ready semantics:** source Walk/ready=`walk_alert02` is
   distinct from Fire walk=`fp_walk`, but current moving-ready blending uses
   firing branches. The original playable awareness→ready transition and
   right-only fast-strafe firing rule are still not fully recovered.

Important correction to old audits: saved Mixamo start/stop/turn clips do NOT
currently interrupt the gait when `preserve_source_locomotion=true`:

```gdscript
# scripts/player/operator_animation_driver_actions.gd:44
func _consider_cosmetic_transition() -> void:
    if bool(animation_profile.locomotion.get("preserve_source_locomotion", false)):
        return
```

The preserved legacy `prone_backward` animation file has not been deleted.
The canonical map now points that logical key at the existing source crawl so
diagnostics and presentation consumers no longer see stale Mixamo provenance;
the graph backward point uses `prone_forward` with BACKWARD play mode. Older
profiles default the new flag off and retain their own saved clip mapping.
Godot's supported API defines
[AnimationNodeAnimation.play_mode](https://docs.godotengine.org/en/stable/classes/class_animationnodeanimation.html)
as the node's playback direction; no animation resource reversal or second
clock is necessary.

The bounded runtime seam is
`scripts/player/operator_locomotion_blend_tree.gd:1315`:

```gdscript
var source_backward: Variant = profile.locomotion.get("source_prone_backward", false)
if source_backward is bool and source_backward:
    var source_path := String(profile.clip_paths.get(forward_clip, ""))
    if is_source_clip(source_path):
        var source_animation := load(source_path) as Animation
        if source_animation != null and source_animation.get_meta("source_name", "") == "seal_prone_crawl":
            backward_node = _animation_node(forward_clip)
            backward_node.play_mode = AnimationNodeAnimation.PLAY_MODE_BACKWARD
```

`scripts/player/operator_animation_profile.gd:250` defaults the opt-in off;
`load_project_map` at line300 resets it before loading another profile.
`config/operator_animation_map.json:462` now disables it after visual rejection.
The logical backward clip is restored to `Moving Backward In Prone Position.fbx`.
An explicit `--source-prone-candidate` test option installs the source map only
in that isolated process; its AnimationTree supplies the playback direction.

## Verification history

- Offline source audit v1/v2: PASS79 actions/398 motion rows/72 weighted-choice
  fixtures; v2 adds PASS4 original prone direction/sign fixtures.
- New main tool parse: PASS with installed Godot4.7.1.
- First main v1: route/finite/body gates passed; overall FAILED because the
  fixture used nonexistent `mark-23.json` instead of `mark_23.json`, and default
  downward aim caused genuine `MUZZLE_OBSTRUCTED` rejection at the fixture
  floor. The test now supplies level camera aim; muzzle security is untouched.
- The same v1 exposed stale logical `prone_backward` Mixamo metadata even though
  the graph sampled the source. Fixed the saved logical map as described above.
- Final offline v3: PASS79 actions,398 motion records,72 weighted choices and
  4 original direction/sign fixtures with zero unknown stubs. Saved snapshot:
  `/private/tmp/source-animation-selection-20260913-v3.json`.
- Main v2: PASS13,297 checks/192 movement frames. Main v3 adds same-profile
  canonical→older-preset reset coverage: **PASS13,300 checks/192 movement
  frames**, M4+Mark23, actual forward/backward movement at unchanged1.25m/s,
  accepted backward-moving shots and idle release. Result:
  `/private/tmp/source-prone-backward-main-v3.json`; log uses the same prefix.
- Feature gate: **PASS155 contracts**, including `source_prone_backward`.
  `/private/tmp/source-prone-backward-contract-v1.log`.
- `git diff --check` passed for this task's scoped files. Known macOS CA and
  disabled voice-capture project-setting warnings remain, not GDScript errors.
- No native render was launched by this subtask. Finite transforms and node
  playback do not prove visual quality, foot contact, original cadence or all
  source-controller parity. Existing Mark23 support-socket distance during
  firing was approximately0.389m; this change does not alter weapon attachment
  and does not claim that measurement is corrected.

Reproduce the headless main proof (do not pass `--automated-test`):

```sh
/Users/kiwimango/Applications/Godot-4.7.1.app/Contents/MacOS/Godot --headless --path /Users/kiwimango/socom-141-camera-lab --script res://tools/source_animation_selection_audit_prone_main.gd --log-file /private/tmp/source-prone-backward-repeat.log -- --output-prefix=/private/tmp/source-prone-backward-repeat
```

For a separate display-backed proof, omit `--headless` and append `--capture
--whole-body-proof` after `--`. The default now tests restored canonical routing;
append `--source-prone-candidate` only to reproduce the rejected candidate.
Never restart the user's current game to run it.
Local main-scene changes do not rebuild any previously exported browser ZIP.

## Rendered rejection and bounded recovery card

Parent native inspection rejected the enabled candidate: the M4 backward
middle-frame render places knees/shins well below the floor. Forward also shows
some contact error. The numeric routing gate is not visual acceptance.

- Intent: prevent shipping visibly ground-penetrating backward crawl.
- Acceptance: compare original `seal_prone_crawl` FK, current built take and
  former Mixamo backward take at identical normalized phases. A correction must
  derive from source hip height, preserve rotations/timing/XZ/65 bones/physics
  and pass actual main plus rendered floor contact. Otherwise disable the new
  canonical opt-in and restore only the former backward map.
- Owner: existing build-time source-height resource adapter, if original-data
  comparison proves a correction; no additional runtime transform writer.
- Protected: CharacterBody, camera/spine, aim/weapon owners, source assets,
  animation timing, jump/traversal and all unrelated edits.
- Focused proof: new read-only pose observer, independent original Y-handler
  audit, same-phase bone/skin floor measurements, then actual main renders.

System delta **REJECT current visual activation pending recovery**. Numeric
selection correctness remains proven, but rendered acceptance failed. A
source-backed height correction can be merged only if its independent evidence
and skin/contact result improve the candidate. Arbitrary upward camera/body
offsets are not allowed by this card.

### Diagnosis and safe final disposition

Same-phase offline comparison in
`tools/source_animation_selection_audit_prone_pose.gd` samples all27 original
crawl keys against the built current clip and former Mixamo backward clip.
Original source root Y is586/256=2.2890625 units; hips also have their own
animated local translation. The existing proportion conversion leaves current
pelvis Y 56.1658–116.0207mm below original FK depending on phase. This is a real
height discrepancy, not an animation-node reverse-playback defect.

At phase0.5, all values relative to the observer's model/actor origin:

| Landmark | Original FK Y | Current source take Y | Source hip-Y-only candidate | Previous backward take Y |
| --- | ---: | ---: | ---: | ---: |
| Hips | 0.272656m | 0.180743m | 0.272656m | 0.326165m |
| Left knee | −0.081498m | −0.174684m | −0.082771m | 0.078791m |
| Right knee | 0.116411m | 0.031765m | 0.123678m | 0.223660m |

Therefore matching the source pelvis alone still leaves a knee ~8.3cm below
the assumed floor. Original instruction audit confirms no crawl-specific root-Y
rewrite: ordinary handler `0x59b870–0x59ba78` only writes rootY for Ladderslide;
action46 is Climb off ladder, crawl is27; the other special global is
`dive_to_prone`. Crawl omits `UseVelY`. Actor+740 baseline compensation and
original terrain/pose correction remain insufficiently decoded. The raw FK
origin is not proof of the original world's floor contact.

No source-height adapter/profile/asset change was made. Adding an arbitrary
extra lift would hide the unresolved world-baseline problem, so the canonical
reverse flag was disabled and only its backward clip path restored. The native
failed proofs remain preserved under
`art_source/source_animation_match_verified_20260913/prone-*`.

Observer v1 emitted a duplicate AnimationLibrary setup error while reusing its
offline model. The v2 tool explicitly removes its previous library before the
second build. Its per-phase comparisons remain observers, not accepted native
visual results. Forward crawl already has floor-contact issues; this rollback
does not claim to fix them or the Mark23 attachment gap.

Final recovery checks:

- Offline same-phase observer v2: **PASS665 checks**,27 samples, no duplicate
  library error. `/private/tmp/prone-pose-audit-v2.json`. Across the full cycle,
  original and hip-Y-corrected knee minima are −88.469mm and −89.566mm; prior
  backward knee minimum is −0.578mm. These are bone measurements, not skin
  clearance guarantees.
- Restored canonical main: **PASS13,300 checks/192 movement frames**, backward
  metadata=`mixamo_com`, `source_candidate=false`;
  `/private/tmp/source-prone-backward-main-disabled-v1.json`.
- Explicit isolated candidate: **PASS13,301 routing/finite checks/192 frames**,
  `source_candidate=true`, visual acceptance explicitly not claimed;
  `/private/tmp/source-prone-backward-main-isolated-v1.json`. Three ObjectDB
  shutdown instances were reported for this bundled-state test; no script
  exception occurred. This is not permission to enable the failed visual pose.
- Feature gate after disabling: **PASS155**, log
  `/private/tmp/source-prone-backward-contract-disabled-v1.log`.
- Final original audit snapshot v4: PASS79/398/72/4;
  `/private/tmp/source-animation-selection-20260913-v4.json`.
- All owned processes exited. No source-height/runtime camera/movement edit or
  browser ZIP export occurred during recovery.
