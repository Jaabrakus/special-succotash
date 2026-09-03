# SOCOM-141 project rules

These rules apply to every feature change in this repository.

1. Read `docs/GAMEPLAY_INTENT_DICTIONARY.md` and
   `docs/GODOT_FEATURE_INTEGRATION_CONTRACT.md` before editing gameplay or a
   gameplay tool.
2. Write a translation card before the edit: player intent, acceptance rule,
   one system owner, systems that must not change, and focused proof.
3. Godot behavior must be connected as a complete chain:
   input/tool -> node owner -> shared saved contract -> canonical runtime
   consumer -> visible result.
4. A scene is a tree of nodes. Every runtime node has one responsibility and
   one transform/state writer. Scripts extend nodes; they do not create a
   second owner for camera, movement, weapon, damage, animation, or networking.
5. `CharacterBody3D` remains the sole player movement/collision owner. The
   SOCOM camera/reticle remains the sole aim-intent owner. The server weapon
   remains the sole shot/damage owner. IK and animation are presentation only.
6. Labs must edit the same data consumed by the canonical game. A preview-only
   feature is not integrated. Lab Play actions must enter `res://main.tscn`.
7. Add or update a JSON contract in `config/feature_contracts/` for every new
   feature. Run `tools/feature_contract_regression.gd`; the feature is not done
   while that gate or its focused regression fails.
8. Every technical report to the user must include exact code/scene locations
   and the relevant code excerpt. Do not claim a behavior based only on a video,
   screenshot, node name, or prose document; verify it in code or a runnable
   scene.
9. Preserve the dirty worktree. Never reset, clean, or delete unrelated user
   work. Keep edits bounded to the declared translation card.
10. New information triggers a system-delta review. Score the current system
    and candidate from code evidence for correctness, ownership clarity,
    canonical runtime parity, editor usability, performance, and regression
    coverage. Record `KEEP`, `MERGE`, `REPLACE`, or `REJECT`. If the candidate
    scores better without breaking protected owners, update the implementation;
    do not defend the older design merely because it already exists.
