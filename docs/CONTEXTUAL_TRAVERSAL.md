# Contextual traversal

Translation card: short edges use a continuous low mantle; high edges hang first; a real forward running start increases jump height; timed jumps pass actual window openings. CharacterBody owns movement, existing animation driver owns visual pose. Protect aim, server damage, stairs, standing hop and map dimensions. Proof: contextual traversal, ledge, vault, replay and rendered fixtures.

Shared settings are in `config/ledge_climb.json`: low-mantle limit 1.35 m, running launch 7 m/s, minimum run speed 4.5 m/s. Full forward command is also required. Running does not add a second jump or permit airborne relaunch. The standing impulse stays 5 m/s. Recorded 60 Hz fixture peaks were approximately 0.61 m standing and 1.17 m running (discrete integration, not exact continuous-time ballistic peaks).

Input -> `player_controller.gd::_try_begin_mobility_action` / traversal probe -> saved ledge contract -> CharacterBody velocity -> `move_and_slide` -> animation phase. `active_jump_launch_speed` records the actual impulse, so the animation does not use standing-jump timing for the higher run. Replay codec version 4 includes this field; snapshots carry `jump_launch_speed`. Server and clients must be updated together. No deployment was performed.

Short grounded climbs carry `presentation_slot=low_mantle` in existing serialized traversal context. High/airborne grabs retain hang-first W/S/A/D controls. Thin vault-over actions use the RH one-meter AGLS clip; low mantle uses LH one-meter clip. Native rest-aware adapter retargets both. The 2 m mantle was rejected after rendered inspection showed an excessive reach on a 1 m crate. Original AGLS sources are unchanged. Hip anchoring prevents duplicate body motion; exact hand contact still needs pose/contact fitting.

Window policy is ordinary collision, not a teleport or a capsule exception: fixture sill 0.65 m, opening top 3.15 m, width 1.6 m. A running jump timed before the sill passes; a late jump hits the sill; adding a solid pane blocks it. Smaller windows may need crouch or a separately designed compact traversal posture. No such posture or glass breaking was added.

The warehouse in current_map.json and relic_depot.json used a single bounding-box collider. Detailed mesh collision now preserves its actual visual surfaces. Its textured windows are not automatically open holes. Rocks already had detailed mesh collision. Arbitrary rocks may still be too steep, too narrow or lack standing clearance; the safety checks remain. Container sizes remain unchanged.

MERGE scores (correctness/ownership/parity/editor/performance/coverage): previous 2/5/5/3/4/3; candidate 3/5/5/4/3/5. Mesh collision costs more than a box; it is scoped to one warehouse. Remaining contact and map-specific geometry limitations keep correctness at 3.

Godot collision queries follow [PhysicsBody3D.test_move](https://docs.godotengine.org/en/stable/classes/class_physicsbody3d.html#class-physicsbody3d-method-test-move): query-only collision checks, while CharacterBody applies movement. Tested with installed Godot 4.7.1.
