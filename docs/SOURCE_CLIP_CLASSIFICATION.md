# Source clip classification

## Translation card

- Intent: selecting an already-imported original jog, alert or reload clip must
  keep its source-animation policy instead of silently falling back to legacy
  presentation because it is not the one hard-coded alert filename.
- Acceptance: canonical `is_source_clip` accepts valid native reference
  Animation resources with source metadata, retains existing derived gameplay
  and firing resources (including jump windows without `source_name`), rejects
  foreign/invalid resources, and caches classification within the process.
- Owner: `SocomOperatorLocomotionBlendTree.is_source_clip` only. No new node,
  animation sampler or bone writer.
- Must not change: saved mappings/activation, source resources, gameplay clocks,
  movement/collision, camera/aim, weapon/damage, or existing animation layers.
- Proof: `tools/source_clip_classification_regression.gd` checks original
  jog/alert/reload, every saved processed source clip, invalid names/metadata,
  project path boundaries and repeated cached queries. Feature contract gate
  checks the same production reader. Main rendered proof remains separate.

System delta: MERGE metadata classification into the existing owner. Filename
special-case scores correctness 2, ownership 5, runtime parity 5, editor usability
2, performance 5, coverage 2; cached resource/metadata validation scores
4/5/5/4/5/4. Evidence: existing importer writes `seal_reference`/`source_name`,
derived jump resources retain `source_asset` instead, and the production graph
calls this shared classifier. Classification is provenance routing, not a claim
of original-engine blend parity or a security boundary against repository edits.

The cache is process-local: identical saved paths do not reload resources during
frame processing. After reimporting/replacing metadata at the same path, start a
new play session. Editing a clip's motion does not change its classification.

Godot API reference: [ResourceLoader.exists/load](https://docs.godotengine.org/en/stable/classes/class_resourceloader.html)
and [Resource.take_over_path](https://docs.godotengine.org/en/stable/classes/class_resource.html).
The regression uses unsaved, process-local fixture resources for invalid
metadata; no source files are overwritten. API behavior is checked against the
installed Godot 4.7.1 executable rather than inferred from documentation version.

## Implementation and focused result

`operator_locomotion_blend_tree.gd::is_source_clip` now restricts canonical
project-owned `.tres` paths, checks an Animation resource exists, and validates
native reference metadata rather than accepting only one alert filename:

```gdscript
accepted = marker is bool and marker \
    and source_name == path.get_file().get_basename() \
    and (source_name.begins_with("seal_") or source_name.begins_with("death_"))
```

Processed gameplay/firing clips retain their existing classification. Their
derived jump resources can use `source_asset`/`source_window` metadata without
`source_name`; the reference-only metadata condition must not reject them.
Existing invalid/nonexistent source-looking paths no longer pass the prefix test.

Godot 4.7.1 headless parse/focused execution: PASS, 94 saved processed routes,
native jog/alert/reload fixtures, foreign/invalid paths and metadata checks, and
1000 repeated cached classifications. The log is
`/private/tmp/source-clip-classification-check.log`; no GDScript errors, only the
existing macOS certificate-store warning. No saved mappings were changed and
no new gait was activated. Rendered source-only rifle proof is a separate task.

`feature_contract_regression.gd`: PASS, 137 contracts at this checkpoint;
`/private/tmp/source-clip-classification-contract.log`. Focused diff whitespace
check also passed. Invalid fixture coverage includes a non-Animation resource
with otherwise plausible source metadata, which is correctly rejected.
