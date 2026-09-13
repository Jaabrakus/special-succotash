# Source animation coverage census

Translation card: the player wants complete SOCOM II locomotion and actions.
Acceptance for this observer is narrower: every sampled route identifies its
actual configured source, missing source provenance and available unused source
takes without confusing configuration with evaluated animation. The observer
owns the census only. Movement, aim, weapons, networking, runtime profiles and
animation behavior must not change. Proof is a headless census using the same
profile loader, weapon normalization and selection methods as the game.

Run with the installed Godot 4.7.1 executable:

```sh
/Users/kiwimango/Applications/Godot-4.7.1.app/Contents/MacOS/Godot \
  --headless --log-file /private/tmp/source-animation-coverage.log \
  --path /Users/kiwimango/socom-141-camera-lab \
  --script res://tools/source_animation_coverage_audit.gd
```

Add `-- --json` for a full machine-readable report (one line beginning
`SOURCE_ANIMATION_COVERAGE_JSON=`), or `-- --candidates` to list every source
take not referenced by the inspected contracts. The script writes no report or
project data. Godot itself writes the explicitly selected log.

## What the census proves

`tools/source_animation_coverage_audit.gd:34` loads the shared profile. At line
149 it calls the canonical action selector:

```gdscript
actions.resolve_semantic_action(action)
```

At line 135 it invokes `graph._configure_source_controller(available)`, the
same source-range preflight used before constructing the runtime topology.
Jog branches are included only if that preflight activates the three-tier
controller. At line 170 it constructs the actual cardinal blend-space resources using
`graph._direction_space(prefix, available, firing)`, then reports their selected
animation points. This avoids duplicating weapon/family/direction precedence in
an independent implementation. No player is spawned and no graph is advanced.

The report deliberately records:

```gdscript
"evidence_level": "saved_resources_and_canonical_resolvers_only",
"runtime_evaluated": false, "source_parity_verified": false,
```

`available_saved_resources` means Godot reports the mapped resources exist. It
does not prove successful retargeting, valid animation tracks on the live rig,
nonzero graph weight, correct foot contact or original-game controller timing.
Animation metadata is declared provenance, not a proof of untouched poses.
Coherent jump windows and composed firing resources report their underlying
source dependencies separately from their saved resource paths. Mirror and alias
overwrite order follows `operator_asset_runtime.gd`.

`unreferenced_source_candidates` means a native source name is absent from the
shared logical-resource provenance and the inspected lean contracts. A clip
already mapped into the shared library may still never activate in gameplay.
The report includes all logical resources and distinguishes saved transition
candidates from exercised resolver results. It samples M4A1, AK-47 and Mark 23;
it does not claim every weapon or original-game motion bank is covered.

## Initial baseline observations, before the controller rebuild

The September 12, 2026 census found 171 configured logical clips, 286 distinct
reference source names, and 243 sampled route records. Of those route records,
186 had declared source dependencies and 57 did not. The latter count includes
inactive transition candidates and intermediate event routes; it is **not** a
count of 57 broken gameplay actions. There were 188 unreferenced source names,
including 22 death, 26 traversal, 20 equipment/posture transition and 11 reload
sources. Run the observer again after changing the profile; these are baseline
counts, not an assertion about subsequent implementation.

Baseline animation-map SHA-256:
`d8ccf78e0216d4786d29bc5f7ef0f7a0a1bbea159c11787e8cbe383acf7163e0`.

The main chain is `main.tscn:15` -> instantiated operator player ->
`scenes/player/operator_player.tscn:36` `ProductionAnimation` -> canonical driver
-> shared animation map and normalized equipped-weapon profile -> graph and
posture consumers. The visible pose still requires an evaluated runtime check.

Useful baseline findings were:

- Rifle reload selection was already source-backed through
  `config/weapons/m4a1.json:77`: `"reload_crouched": "iso_rifle_reload_crouched"`.
  The standing and prone slots likewise select their dedicated native takes.
  The event map's generic `reload` name is an intermediate route; it does not
  negate the equipped source selection.
- Mark 23 had empty weapon reload slots at `config/weapons/mark_23.json:97`.
  `operator_animation_driver_actions.gd:371` checked equipped fire/reload slots
  and then returned `animation_profile.resolve_semantic_action(action_name,
  posture)`. In that baseline, the generic result was rifle `reload` or
  `prone_reload`, while the family event route named a different pistol take.
  `operator_animation_driver_presentation.gd:70` resolves the equipped reload
  again and overwrites `plan["state"]`, so the intermediate pistol event name
  alone was insufficient evidence. Native `seal_p_reload`,
  `seal_p_crouch_reload` and `seal_p_prone_reload` were available candidates.
- Backward prone travel was mapped to Mixamo in
  `config/operator_animation_map.json:161`:
  `"prone_backward": "res://assets/animations/mixamo/Moving Backward In Prone Position.fbx"`.
  The canonical prone blend space selected that mapped take directly.
- `config/operator_death.json:3` selected `"standing_clip": "death_right"`
  and the map assigned that logical clip to Mixamo. Native death resources
  exist, including `seal_reference/death_prone_chest01.tres:161`:
  `metadata/source_name = "death_prone_chest01"`.
- `operator_animation_driver_actions.gd:45` returned immediately from
  `_consider_cosmetic_transition()` when `preserve_source_locomotion` was true.
  Mapped start/stop/turn clips were therefore candidates, not evidence of an
  active source transition controller. Source stance and equipment transitions
  require intentional routing and interruption rules.
- Lean already used native sources for both weapon families in all three
  stances, through `config/operator_animation_map.json` `authored_peek` and
  `operator_posture_layer.gd:110` `configure_authored_peek(profile)`.
- The traversal contract mixed native ladder clips with AGLS vault/hang/climb
  scenes. Native `seal_climbcrate`, `seal_climb_medium`, `seal_hang` and
  `seal_hang2climbup` were unreferenced candidates; their availability alone
  does not establish suitability for the current contact/movement solver.

## After the first controller integration stage

The next census, still dated September 12, 2026, used animation-map SHA-256
`540888c9ff14b6ecae3614b7379c53f73e9bc2794026962f2afb102658dc294d`.
This is a new snapshot; the initial baseline above is retained for comparison.

| Census observation | Initial baseline | After first stage |
| --- | ---: | ---: |
| Configured logical clips | 171 | 179 |
| Distinct reference source names | 286 | 286 |
| Sampled route records | 243 | 259 |
| Routes with source provenance | 186 | 205 |
| Routes without source provenance | 57 | 54 |
| Unreferenced source names | 188 | 183 |

The adapted census calls the same graph preflight as the canonical runtime.
Both M4A1 and AK-47 register all twelve native walk/jog/run cardinal ranges.
Mark 23 retains its separate pistol locomotion topology; rifle three-tier
preflight is inactive for that family. The 16 additional sampled records are
the four base and four ready/firing jog directions for each of the two rifles.
`configured_graph_policies` records those decisions but still reports
`runtime_evaluated: false`.

The census also initializes `actions.equipped_weapon_family` from the normalized
weapon profile. This matters because the canonical semantic selector now uses
family slots before weapon slots. All three Mark 23 semantic reloads resolve to
native source takes:

| Posture | Logical clip | Source take |
| --- | --- | --- |
| Standing | `iso_pistol_reload_standing` | `seal_p_reload` |
| Crouched | `iso_pistol_reload_crouched` | `seal_p_crouch_reload` |
| Prone | `iso_pistol_reload_prone` | `seal_p_prone_reload` |

The remaining unreferenced categories are 22 death, 26 traversal, 20 transitions,
8 reload, 7 lean, 6 throw and 94 other locomotion/action sources. Intermediate
event-route names and inactive transition candidates still contribute to the
54 records lacking source provenance; that number is not a live failure count.

Separate real-main proof is implemented in
`tools/source_locomotion_controller_regression.gd`. It submits canonical movement
commands to the actual `CharacterBody3D`, exercises four forward analog bands,
cardinals, diagonals and rapid reversals, and checks all six source gait spaces
share their published cycle period. It verifies both the driver's source result
and its agreement with the policy evaluated at the rendered blend heading.
It then retains the inherited accepted-fire and committed-reload checks.

The final headless run with `--public-training --require-combat-alignment`
passed after the cadence, invalid-preflight fallback and rendered-heading fixes:
1,152 checked main frames, including 540 source-controller frames, seven accepted
shots and one completed reload. Both action/pose and combat-alignment failure
lists were empty. The report is
`/private/tmp/source-locomotion-controller-final.json`, with analog/controller
measurements in `/private/tmp/source-locomotion-controller-final.controller.json`.
Maximum measured trigger-marker error was 0.001110m, hand span 0.349492m and
contiguous character-relative wrist displacement 0.111648m.

The standalone census remains an inventory. Neither these counts nor the live
test's passing assertions establish original SOCOM II controller execution,
perfect finger placement, or foot contact throughout every source cycle.

## System delta: MERGE

This observer complements the binary timing audit; it does not replace runtime
tests or change a gameplay owner. Scores compare coverage tooling before this
observer with the combined tools, from 0 through 5.

| Criterion | Before | With census | Evidence |
| --- | ---: | ---: | --- |
| Correctness | 3 | 4 | Canonical action selectors and blend-space construction are called directly; no evaluated-pose claim. |
| Ownership clarity | 5 | 5 | Observer owns no player node, transform, shot or saved profile. |
| Runtime parity | 3 | 4 | `source_animation_coverage_audit.gd` uses `Profile`, `Graph`, `Actions` and `WeaponContract`; live evaluation remains separate. |
| Editor usability | 2 | 4 | Repeatable summary, complete JSON and candidate listing use project assets only; no private temporary extraction folder is required. |
| Performance | 4 | 4 | Offline resource metadata is cached; no per-frame cost is added. |
| Regression coverage | 2 | 3 | Runnable census detects malformed provenance and reports gaps, but intentionally does not stand in for action/pose regressions. |

The timing observer `tools/source_animation_timing_audit.gd` remains the source
for binary frame intervals and native durations. Source fidelity requires both
provenance/timing evidence and focused evaluated runtime comparisons.

The observer uses standard resource loading documented by Godot's
[ResourceLoader reference](https://docs.godotengine.org/en/latest/classes/class_resourceloader.html)
and metadata inherited by
[Resource](https://docs.godotengine.org/en/latest/classes/class_resource.html).
Those documentation pages are marked `latest`; executable checks here were run
against the installed `4.7.1.stable.official.a13da4feb` engine, not an assumed
stable web version.
