# Online gameplay parity

## Fire input and HUD

1. Player intent: the equipped gun responds and displays its state exactly as in main.tscn.
2. Acceptance: all public weapons use the same semi/burst/auto policy, allowed modes, slot and authored cadence; reload/menu/death cannot leave a burst firing.
3. Owner: SocomWeaponFireModePolicy decides trigger requests; the existing multiplayer adapter submits them to the server weapon.
4. Protected: weapon data, camera aim, animation assets, server shot validation/damage and tournament assignment.
5. Proof: network_fire_mode_parity_regression.gd compares canonical and network policy/state, then browser input exercises the packaged build.

## Movement reconciliation

1. Player intent: online WASD, crouch and traversal remain responsive like the canonical CharacterBody.
2. Acceptance: delayed snapshots compare against the corresponding acknowledged input, not today's predicted position; no correction for a matching past state, real errors still correct, and new local stance changes are not overwritten by older snapshots.
3. Owner: SocomNetworkOperator, extending the canonical CharacterBody movement owner. A bounded history only computes correction; it is not a movement motor.
4. Protected: authored speeds/acceleration, camera, weapon authority, collision and remote interpolation delay.
5. Proof: network_prediction_regression.gd with delayed acknowledgements, direction changes, stance changes, duplicates and real errors; real two-peer play and browser build.

System delta: MERGE shared trigger policy and input-acknowledged correction. Current correctness/runtime parity 2/2, ownership 5, editor usability 4, performance 4, coverage 2; candidate target 5/5/5/4/4/5. Evidence: canonical weapon_fire_mode_policy.gd and player_controller.gd versus multiplayer_combat.gd and network_operator.gd. Do not change authored presentation to mask networking faults.

## Shared player scene, not a copied multiplayer character

1. Player intent: online is the same playable character as main, not a second approximation.
2. Acceptance: instantiate an inherited instance of main's operator_player.tscn and the exact socom_camera_rig.tscn; both have the same visual nodes, traversal probes, collider and saved tuning.
3. Owner: canonical operator_player.tscn; SocomNetworkOperator only extends CharacterBody with identity, authoritative damage and synchronization.
4. Protected: animation assets/poses, camera aim, server authority, secrets and all concurrent art changes. The browser never gains database/admin credentials or local damage authority.
5. Proof: network_canonical_tuning_regression.gd and network_operator_animation_regression.gd in source and exported PCK, plus rendered browser play.

Delta MERGE: replace procedural network actor construction with scene inheritance. The existing factory duplicated the main node setup (parity 2); inheritance shares the authored subtree (parity 5), preserving all other owners. Diagnostic lightweight probe clients can omit the visual subtree before entering the scene tree; normal gameplay cannot.

## Remote presentation intent

1. Intent: other players aim and move like their own local character, including on a headless server.
2. Acceptance: the shared mannequin consumes that actor's bounded aim and motion intent, not the observer's camera; it updates with no camera present. Dive/roll, desired movement, peek and aim pitch survive snapshots.
3. Owner: the existing mannequin/animation driver consumes presentation intent supplied by SocomNetworkOperator.
4. Protected: no replicated bones, no new camera, no client damage, no weapon-placement or animation-asset edits.
5. Proof: network_remote_animation_intent_regression.gd plus rendered local and remote actors.

## Immediate local firing feedback

1. Intent: pulling the trigger feels immediate like main, not a round-trip later.
2. Acceptance: a locally scheduled shot immediately triggers the shared recoil, sound and reticle once; its numbered server event cannot play them twice. Only server events display impacts/hits and change authoritative ammo/health.
3. Owner: SocomShotPresentation and the existing animation/reticle consumers. The network adapter only correlates sequence IDs.
4. Protected: server shot cadence/validation, damage, projectile paths, private credentials, rig poses.
5. Proof: network_shot_feedback_regression.gd, multiplayer warm-up test, packaged browser firing and sound.

The local multiplayer presentation reuses SocomWeaponController's existing configured composure/spread update with its input process disabled. A shared Ballistics.record_shot_state method advances recoil state without tracing projectiles. This presenter is never connected to a damage or ammo authority. Main and network use the same saved weapon values and bloom math. Muzzle flash and casing use the existing TracerSystem and canonical markers.

## Packaged scene closure

Intent: the browser contains the same inherited runtime scene that passed source tests. Acceptance: the exported PCK directory contains network_operator.tscn.remap and a fresh browser can load multiplayer with no source fallback. Owner: restricted web export preset and actual-PCK release audit. Protected: private keys/source art and unrelated ongoing animation edits. Proof: fresh Chrome join/fire, archive inspection and privacy audit. Delta MERGE: explicitly include the new inherited scene and require it in the packaging gate; native tests launched beside source files alone cannot prove export completeness.

The matching Docker allowlist must also include main's scene/AnimationTree and the AK/M4 runtime models and particle textures. Otherwise the server uses fallback gun geometry while the browser uses authored geometry. Keep other external/source folders excluded. The focused Render deployment regression checks those selected dependencies; this does not claim a Linux Docker build was run locally.
