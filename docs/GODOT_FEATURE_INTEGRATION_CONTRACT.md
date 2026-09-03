# Godot feature integration contract

This is the permanent setup guide and completion gate for SOCOM-141 features.
It prevents a tool, lab, scene, or script from looking correct while the
canonical game uses a different system.

## What Godot is in this project

- A **project** is configured by `project.godot`.
- A **scene** (`.tscn`) is a saved tree of nodes.
- A **node** is one bounded object in that tree: `CharacterBody3D` owns player
  motion, `Camera3D` renders a view, `Skeleton3D` owns a bone pose, `Marker3D`
  stores an editable 3D contact, and `Control` owns UI presentation.
- A **script** (`.gd`) extends a node with behavior. The node is the object; the
  script is its behavior.
- A **resource/profile** stores shared authored data. Tools write it and the
  canonical runtime reads it. A lab-only variable is not shared data.
- A **signal** reports an event. It does not transfer ownership of a gameplay
  decision.
- A **system owner** is the only code allowed to decide or write a domain. Other
  nodes may read the result for presentation.

## Canonical SOCOM setup

| Domain | Required owner | Forbidden duplicate |
| --- | --- | --- |
| Player motion and collision | the canonical `CharacterBody3D` controller | another movement motor or direct body teleport |
| Aim intent | SOCOM camera/reticle chain | IK, animation, or weapon editor steering the camera |
| Shot and damage | authoritative server weapon | preview/lab/client applying damage |
| Weapon presentation | the active weapon-pose ownership contract | two nodes writing the rifle transform |
| Bones | base animation, then one declared post-animation modifier per region | two IK/procedural writers on the same bone |
| Authored weapon data | `config/weapons/<weapon>.json` through the Gunsmith repository | a second hidden lab profile |

The canonical playable scene is `res://main.tscn`. `project.godot` may boot a
launcher, but a tool's Play action must ultimately enter the canonical scene.

## Required feature graph

Every feature must be traceable through this exact graph:

```text
player input or editor control
    -> one owner node/script
    -> named output contract
    -> shared saved profile (when authored)
    -> canonical runtime consumer
    -> visible result
    -> focused executable regression
```

If one arrow is missing, the feature is incomplete.

## Required JSON manifest

Add `config/feature_contracts/<feature_id>.json` with these fields:

```json
{
  "schema_version": 1,
  "feature_id": "example_feature",
  "player_intent": "What the player sees or feels.",
  "acceptance_rule": "A binary observable pass condition.",
  "canonical_scene": "res://main.tscn",
  "editor_scene": "res://some_lab.tscn",
  "ownership": {
    "example_domain": "ExactOwnerClass"
  },
  "nodes": [
    {
      "id": "editable_target",
      "type": "Marker3D",
      "role": "Stores the authored 3D contact.",
      "owner": "ExactOwnerClass",
      "source_script": "res://scripts/example.gd",
      "code_symbols": ["Marker3D.new()", "EditableTarget"]
    }
  ],
  "data_contracts": [
    {
      "path": "res://config/example.json",
      "writer": "res://scripts/tool_writer.gd",
      "readers": ["res://scripts/runtime_reader.gd"]
    }
  ],
  "must_not_change": ["movement", "camera", "shot_authority"],
  "proof_scripts": ["res://tools/example_regression.gd"],
  "visual_check": "The exact in-game observation still requiring a human eye."
}
```

For nodes saved directly in a scene, use `scene_path` and `node_path` instead of
`source_script` and `code_symbols`. For nodes created in code, every listed code
symbol must literally exist in the source file. This makes the architecture
claim machine-checkable.

## Feature checklist

1. Translate the request into the five-line translation card.
2. Find the current owner before adding code.
3. Name every node and its type.
4. Name inputs and outputs.
5. Name the saved profile, one writer, and all runtime readers.
6. Declare unchanged systems and duplicate owners that are forbidden.
7. Build the editor against the shared profile—not a preview-only copy.
8. Connect the canonical runtime consumer.
9. Add a focused regression and update the feature manifest.
10. Run the contract gate, focused regression, and canonical boot.
11. Perform a live visual check for camera framing, hands, weapon contact,
    animation, and collisions when those are affected.
12. Report exact files, relevant code excerpts, test output, and any remaining
    visual limitation.

## New-information system delta

Every new reference, discovery, or design idea must be compared against the
current implementation. Each feature manifest records six evidence-based scores
from 0 through 5:

| Criterion | Meaning |
| --- | --- |
| `correctness` | Produces the intended result without hidden mismatch |
| `ownership_clarity` | Keeps one writer/decision owner per domain |
| `runtime_parity` | The canonical game uses what the tool or reference proves |
| `editor_usability` | A designer can understand, edit, save, and restore it |
| `performance` | Avoids unnecessary per-frame work and duplicate processing |
| `regression_coverage` | Executable tests cover the claimed path |

Each score needs code-evidence paths. The decision must be `KEEP`, `MERGE`,
`REPLACE`, or `REJECT` with a reason. A higher candidate score is not permission
to violate a protected owner; merge only the winning bounded system when that is
the safer result.

## Command

Run with the installed Godot executable:

```sh
/Users/kiwimango/Applications/Godot-4.7.1.app/Contents/MacOS/Godot \
  --headless --path /Users/kiwimango/Documents/SOCOM-141 \
  --script res://tools/feature_contract_regression.gd
```
