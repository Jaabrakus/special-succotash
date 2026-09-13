# Traversal animation inventory and editable character review

Audit date: 2026-09-12. Root: `/Users/kiwimango/socom-141-camera-lab`.
This is a saved-profile inventory, not proof that every listed action plays in
the current browser build. Regenerate the JSON after changing the runtime map.

## Translation card and system delta

- Player intent: use the existing AGLS traversal library on the current character
  instead of inventing replacements, and retain editable SOCOM-derived actions.
- Acceptance: inventory every relevant imported path; distinguish mapped,
  retargeted-review and unsupported actions; display the actual skinned body in
  Blender with complete action coverage and measured interchange limitations.
- Owner: offline workbench exporter and inventory audit only.
- Must not change: original source library, runtime character/controller,
  collision movement, camera/aim, server weapons/damage, or runtime clip mapping.
- Proof: generated `runtime_inventory.json`, Blender binding/deformation report,
  measured standing reference errors, and inspected character render.

Decision: **MERGE** the broader audit and corrected review artifact, not all
imported animations into gameplay. Scores (0–5), before → after: correctness
1→3, ownership clarity 5→5, runtime parity 0→0, editor usability 1→4,
performance 4→4, regression coverage 1→3. Evidence: old workbench included an
unbound `Icosphere`, omitted 137 air clips and 12 nested lean paths, and tested
only any mesh deformation. The exporter now includes the missing categories;
the Blender builder removes unbound helpers, checks the skin, measures reference
landmarks and height, and renders the character. Runtime parity remains zero
for this offline artifact: it is not a replacement for in-game tests.

## Counts and exact coverage

The imported index `config/traversal_animation_map.json` contains **1,676 entries**
across all families. This task's traversal/air subset has **409 entries**, all
present on disk:

| Family | Imported entries | Character-review actions |
| --- | ---: | ---: |
| Climbing, grabs, hangs, transfers and helpers | 181 | 181 |
| Mantle/vault | 6 | 6 |
| Ladder | 40 | 40 |
| Narrow ledge | 10 | 10 |
| Rope | 28 | 28 |
| Zipline | 7 | 7 |
| Jump/fall/landing (`locomotion_air`) | 137 | 137 |
| **Total** | **409** | **409** |

The previous “272” count was the first six rows, not the whole AGLS library.
The `locomotion_air` family includes `ALSv2_JumpSeq_Sprint_Down_01_LF`,
`MM_Jump_Sprint01_RF`, `MM_Neutral_Jump_Loop_Fall`, and forward/back/side takeoff
and landing variants. These are review candidates; the intended SOCOM
scissor-kick jump must remain the running-jump choice unless explicitly approved
otherwise. Filenames do not establish a free-flight gameplay state.

The current character workbench contains **519 editable Actions**:

- 409 AGLS retargeted review Actions.
- 110 saved SOCOM-derived slot/nested-profile Actions, resolving to 107 unique
  `.tres` paths and 94 distinct decoded source Actions after recursive
  `metadata/source_asset`/manifest dependency tracing.

There are no saved SOCOM profile paths missing from this workbench at the audit
snapshot. The nested coverage includes both rifle and pistol authored leans,
standing/crouched/prone, left/right: 12 paths under
`authored_peek.families`. Counts decreased from 112 SOCOM entries during this
task because the runtime integration changed hang and pull-up to AGLS. Counts
refer to saved entries, not 110 unique original source motions.

## Mapped does not mean visually approved

At the snapshot, `config/operator_animation_map.json` maps:

```json
"traversal_hang": "res://assets/external/agls_intake/imported/climbing/CMC_Climb_To_Standing_FreeHang.scn",
"traversal_pull_up": "res://assets/external/agls_intake/imported/climbing/CMC_Climb_To_Standing_FreeHang.scn",
"traversal_vault": "res://assets/external/agls_intake/imported/mantle_vault/ALSv2_N_Vault_1m_RH.scn",
"traversal_low_mantle": "res://assets/external/agls_intake/imported/mantle_vault/ALSv2_Mantle_2m_Walking_01.scn"
```

Ladder idle/move/slide remain `seal_ladder`, `seal_climbladder` and
`seal_ladderslide`. Four AGLS logical traversal slots currently reference three
unique imported assets. Do not describe all 409 Actions as connected gameplay.
Consult the parent task's contact/render regressions for acceptance of these
new hang/pull-up choices; the inventory alone cannot approve them.

The actual runtime chain is in
`scripts/player/operator_animation_profile.gd::load_project_map`,
`scripts/player/operator_asset_runtime.gd::_build_animation_library`, and
`scripts/player/operator_animation_driver_runtime.gd::_advance_traversal_presentation`:

```gdscript
var profile: Dictionary = actor.traversal.mantle_motor.climb_profile
var slot := str(presentation.slot)
var clip := StringName(profile.presentation_clips[slot])
```

The profile loader first checks `PlaytestStateCollector.bundled_state("animation_map")`
before falling back to `config/operator_animation_map.json`. Thus an old exported
ZIP or captured playtest bundle can still contain older mappings. Editing this
inventory or opening Blender does not update that build.

## Candidate classification and unsupported actions

Every one of the 409 paths has a machine-readable row in
`art_source/traversal_character_workbench/runtime_inventory.json`, with family,
source path, disk presence, workbench presence, mapped slots and classification.
Classification is a conservative name/owner audit, not a claim that each pose
has been visually approved.

| Category | Count | Action required |
| --- | ---: | --- |
| Existing mantle/vault candidates | 6 | Review hand contact and choose obstacle-appropriate action |
| Grab/hang/pull-up candidates | 8 | Review fall entry, stable hang and one-shot pull-up |
| Horizontal shimmy candidates | 4 | Connect movement-distance phase and validate contact |
| Ladder candidates | 29 | Match rung geometry and supported entry/exit phases |
| Jump/fall/landing candidates | 137 | Review optional states; preserve running scissor kick |
| Additive/pose/stride helpers | 30 | Need declared blend-layer ownership, not standalone playback |
| Rope/zipline/narrow-ledge families | 45 | Contract vocabulary exists; no current ledge presentation slots |
| Corners | 7 | Need safe corner-transfer probing and motion phase |
| Hanging swing transitions | 8 | Need hanging swing/transfer implementation |
| Ladder side/jump transfers | 8 | Need corresponding transfer validation and state routing |
| Narrow-floor transitions inside climbing family | 13 | Need narrow-floor action routing |
| Paired climbing finishers | 2 | Need two-character synchronization; outside traversal request |
| Pickaxe climbing | 35 | Need equipment and specific traversal mechanics |
| Other unmapped actions | 77 | Individual action/pose review still required |

Useful exact candidate names include `CMC_Climb_Transition_Fall_To_Climb_01`
through `_05`, `CMC_Climb_Hanging_Idle_Loop`,
`CMC_Climb_To_Standing_FreeHang`, `ALSv2_Mantle_2m_Walking_01`,
`ALS_Ladder_SlideDownLoop`, and `LMv2_Jump_To_Ladder_01`.
`SocomTraversalContract` declares `ROPE_SWING`, `ZIPLINE`, and `NARROW_LEDGE`
with required context, but that declaration does not create their end-to-end
input, collision and presentation integration. “Unsupported” here means that
specific action path is not proven integrated, not that its file is missing.

## Three distinct animation stages

1. **Decoded-source reconstruction:**
   `tools/blender/workbenches/seal_full_source_library/socom_source_actions.blend`
   and `socom_source_playback.blend`: 264 editable decoded `seal_` Actions on a
   source bone rig. Existing reopen validation passes 6,029 samples with maximum
   matrix error `0.000030517578125`. It explicitly does not prove original-engine
   interpolation, recovered weapon/helper parents, or character skinning.
2. **Current-character retarget review:**
   `art_source/traversal_character_workbench/traversal_character_actions.blend`:
   519 Actions, 65-bone rig, bound `BaseBody` mesh. GLTF baked keys are editable,
   but are not claimed identical to decoded source key timing/interpolation.
   A display-only parent corrects interchange scale/up-axis from measured Godot
   standing landmarks; it does not modify rests, bone keys or runtime files.
3. **Approved runtime replacement:** only a saved runtime mapping plus successful
   real-game contact/state/render checks qualifies. The workbench generator
   promotes **zero** replacements by itself. This remains distinct from the
   separate runtime integration edits in the parent task.

## Workbench verification and known limit

Rebuilt in Blender 5.2.1 with `--factory-startup --background
--python-exit-code 1`. 485 Actions showed midpoint mesh deformation; 34 static
poses/loops did not exceed the movement threshold and remain marked for review.
Those 34 are not automatically failures: equal sampled frames do not prove a
loop is inactive. Nor do the 485 measurements prove every frame is attractive.

Standing body bounds are approximately 0.669 × 0.812 × **2.007 metres**.
The unbound `Icosphere` was removed. The resulting render was inspected and shows
the current blue military character, not a helper sphere:

![Current skinned character workbench](/Users/kiwimango/socom-141-camera-lab/art_source/traversal_character_workbench/current_character_review.png)

**Known limit:** exact 3 mm Godot/Blender standing contact parity failed:
left-hand error 22.3 mm, right-hand error 16.0 mm; head/hips below 0.001 mm after
display calibration. The artifact passes an explicitly recorded 30 mm review
threshold, not exact runtime pose parity. Keep `standing_exact_runtime_pose_parity`
false and use the actual Godot character for final contact approval. Source-key
parity is also false for this GLTF-baked workbench. Do not overwrite the exact
decoded-source library with this review.

## Reproduce and open

```sh
python3 tools/audit_traversal_animation_inventory.py \
  --output art_source/traversal_character_workbench/runtime_inventory.json
/Users/kiwimango/Applications/Godot-4.7.1.app/Contents/MacOS/Godot \
  --headless --path /Users/kiwimango/socom-141-camera-lab \
  --log-file /private/tmp/traversal-workbench-export.log \
  --script res://tools/export_character_animation_workbench.gd
/Applications/Blender.app/Contents/MacOS/Blender \
  --factory-startup --background --python-exit-code 1 \
  --python tools/blender/build_traversal_character_workbench.py \
  -- /Users/kiwimango/socom-141-camera-lab
```

Open the `.blend`, select the armature, and choose an Action in Dope Sheet →
Action Editor. Set playback range to that Action's range at 30 FPS. The imported
NLA tracks are muted to avoid multiple actions competing. `START HERE` inside
the file repeats these instructions. The fitted camera and named lights are
review objects only. The original source libraries and runtime scene were not
modified by the workbench builder.

## Checklist for this bounded audit

- **Done:** imported traversal/air inventory, disk presence, nested SOCOM paths,
  recursive source dependencies, explicit unsupported-action classification.
- **Done:** current-character Blender review extended and unbound helper removed;
  519 Actions, mesh binding/deformation, world-size and one rendered-body proof.
- **Partial:** exact Godot/Blender pose parity; measured hand differences remain.
- **Not established here:** per-action early/middle/late visual acceptance,
  obstacle contact, authoritative traversal timing, main-scene gameplay proofs,
  and browser export delivery. These belong to the runtime task, not this audit.
