# SOCOM-141 gameplay north star

This document defines the gameplay direction for SOCOM-141. Use it to review
new code, tuning, tools, maps, and multiplayer features.

The goal is not to copy hidden SOCOM code or undocumented formulas. The goal is
to preserve the clear tactical relationships described by the original manuals
and express them through SOCOM-141's own systems.

## Source boundary

The primary reference is the
[SOCOM II: U.S. Navy SEALs manual](https://www.videogamemanual.com/PS2/SOCOM-%20U.S.%20Navy%20SEALs%20II%20%28USA%29.pdf).
The manual confirms these player-facing behaviors:

- Crosshairs aim weapons and identify friendly or hostile targets.
- Crouched and prone operators are steadier with scoped rifles.
- Movement, aiming, stance changes, peeking, diving, firing, and reloading are
  separate controls.
- Grenade input controls the throw trajectory and distance.
- Demolition uses a neutral bomb, an enemy base target, planting, defense, and
  detonation.
- Suppression is a timed team-elimination mode.
- A lobby supports team selection, ready and not-ready state, loadout changes,
  spectators, connection quality, and match settings.
- The match HUD shows the reticle, health, ammunition, tactical information,
  and a countdown timer.
- Team communication, map knowledge, stealth, accuracy, and objective play are
  core tactical concerns.

The
[SOCOM 3 controls manual](https://manualsdump.com/en/manuals/sony-socom_3/284375/4)
also confirms direct movement and aim controls, stance changes, diving,
peeking, firing, and configurable controls.

The manuals describe behavior. They do not publish spread equations, recoil
curves, damage numbers, animation layers, networking code, or server rules.
All such values in SOCOM-141 are original implementation choices. Tune them by
playtesting and keep them in shared profiles.

## The player promise

SOCOM-141 is a readable third-person tactical shooter. The operator, weapon,
reticle, map, and objective must tell one consistent story.

The player must always understand:

1. Where the player intends to aim.
2. Where the authoritative shot can travel.
3. Why the current shot is more or less accurate.
4. What action the operator is performing.
5. What the team must do to win the round.

If a feature makes any of these answers less clear, revise the feature.

## Non-negotiable system rules

The [SOCOM-141 and AGLS integration boundary](AGLS_INTEGRATION_BOUNDARY.md)
defines which SOCOM systems remain authoritative when AGLS content is imported.
Treat that ownership table and its acceptance checklist as part of these
non-negotiable rules.

### One aim intent

The camera aim resolver owns yaw, pitch, and the shared target. The weapon fires
from the authoritative muzzle toward that intent. Muzzle obstruction can block
the shot.

The camera, blue placement line, weapon rail, animation, IK, and visible
reticle may display the intent. They must not create another shot destination.

### Real accuracy with matching feedback

Accuracy is gameplay. Reticle motion is feedback.

Use this event chain:

`trigger -> authoritative spread state -> validated shot -> visual response`

Firing must affect later shots through gameplay recoil or bloom. Movement,
turning, stance, sustained fire, and recovery may modify that state. The
reticle must display the same state in a readable form.

The short upward reticle bounce is presentation only. It may show the firing
impulse and recovery. It must not drag the authoritative center or redirect a
shot. The real shot cone must come from the ballistics and composure systems.

Expected relationship:

- A settled first shot is the most precise.
- Short controlled fire is more precise than an uncontrolled long burst.
- Sustained fire increases real dispersion.
- Releasing the trigger lets dispersion recover.
- Moving or turning reduces precision.
- Crouching improves stability.
- Prone provides the strongest stability when the weapon has a legal line.
- The reticle opens, extends, or settles to communicate those changes.
- Weapon and upper-body recoil reinforce the shot without moving the body or
  changing shot authority.

Do not make a bullet follow the temporary visual reticle bounce. Do not apply
the same recoil twice through ballistics and animation.

### Movement stays immediate

`CharacterBody3D` owns position, velocity, stance, and collision. Input must
affect movement authority immediately. Animation can blend after that change,
but it must not delay or replace movement.

Standing, crouched, and prone locomotion must preserve the selected stance.
Upper-body actions such as firing and reloading must not reset the legs to a
standing pose.

### Animation consumes gameplay state

Authored animation is the base. Procedural layers correct it afterward.

Use this order:

1. Authored locomotion or action animation.
2. Stance posture.
3. Spine aim.
4. Weapon socket and rail solve.
5. Two-hand IK.
6. Joint-limit and elbow correction.
7. Obstruction and terrain response.
8. Additive visual recoil.

Animation and IK must not move the authoritative body, alter collision, spend
ammunition, apply damage, or redirect aim.

### The server owns match truth

The server owns player transforms, stance, ammunition, fire cadence, accepted
aim intent, authoritative muzzle state, dispersion, collision, damage,
elimination, objectives, round time, team score, and match state.

Clients send input and bounded aim intent. Clients display predicted local
feedback. Clients do not decide hits, damage, bomb results, or round winners.

Replicate intent and gameplay state. Do not replicate camera transforms or all
skeleton bone transforms.

### Labs edit the game

Gunsmith, Composure, Rig and Hands, Keyboard Mapping, Map Lab, and Training
Range must edit or consume shared profiles. They must not implement duplicate
runtime systems.

A Save and Apply action must update the shared profile used by `main.tscn`.
The next playtest must load that same state.

## Combat model

### Shot lifecycle

1. Read the player's aim intent.
2. Resolve the server muzzle from the equipped weapon and current pose.
3. Reject stale, impossible, or obstructed requests.
4. Read movement, turning, stance, airborne state, composure, and burst state.
5. Calculate the deterministic shot cone.
6. Trace from the authoritative muzzle.
7. Resolve hurtbox, damage, ammunition, and objective effects on the server.
8. Broadcast the confirmed shot.
9. Play muzzle flash, sound, reticle response, weapon recoil, shoulder response,
   tracer, impact, and hit feedback as visual or audio consumers.

### Reticle contract

The reticle has two centers:

- The authoritative center represents aim intent.
- The visual center may move briefly for shot feedback.

The spread display must be driven by the same normalized gameplay spread used
for shot dispersion. Color changes may communicate friendly, hostile, blocked,
or interactable targets. Color must not replace a server validation check.

The reticle must recover when the weapon recovers. A visual response must never
remain stuck after firing, stance changes, reload, death, respawn, or weapon
swap.

### Weapon identity

Each weapon profile should eventually define:

- Damage and headshot behavior.
- Magazine and reserve ammunition.
- Fire rate and supported fire modes.
- Base spread.
- Movement and airborne spread.
- Per-shot bloom and bloom cap.
- Recovery speed.
- Stance multipliers.
- Muzzle velocity or hitscan presentation velocity.
- Reticle response.
- Composure response.
- Reload timing and commit point.
- Muzzle, optic, trigger-hand, and support-hand sockets.
- Sound, flash, tracer, impact, and animation set.

The weapon profile is data. The weapon controller and server contract interpret
that data.

### Reload contract

Reloading is a timed gameplay action. The server commits ammunition at a named
animation event, not at button press. Interrupt rules must be explicit.

Standing reload uses an upper-body action while the legs remain available for
movement. Crouched reload keeps crouched legs. Prone reload keeps prone body
support and a legal muzzle relationship to the ground.

### Grenade contract

The player selects a grenade, previews a readable trajectory, controls throw
strength within human limits, and releases to throw. The server validates the
release, inventory, origin, velocity, collision, fuse, and effects.

The preview arc is presentation. The server simulation is authoritative.

## Tactical match model

### Demolition

The default competitive mode uses two teams and no mid-round respawn.

A team wins a round by eliminating the opposing team or detonating the bomb at
the opposing base. The server owns bomb pickup, drop, plant progress, defuse
progress, fuse time, elimination, timeout, and score.

Every demolition map needs:

- At least one Alpha spawn group.
- At least one Bravo spawn group.
- A neutral bomb pickup.
- An Alpha base target.
- A Bravo base target.
- Legal approach routes for both teams.
- Defensible positions that still have counterplay.
- A round time limit.
- A maximum round count and rounds-to-win value.
- A declared timeout result.

### Suppression and team deathmatch

Suppression is the SOCOM reference for a timed elimination fight. SOCOM-141 may
offer a respawn variant, but it must name that rule clearly. Do not silently mix
round-elimination and respawn scoring.

### Lobby and round flow

Use this state flow:

`host or join -> choose map -> choose team -> choose loadout -> ready -> countdown -> round -> round result -> next round or match result -> lobby`

Changing team, loadout, or map must clear ready state. The match starts only
when both teams have players and all required players are ready. The server
owns the selected map document and sends it to clients before spawning.

The lobby should expose team rosters, ready state, selected map, mode, rounds,
time limit, connection quality, and spectator state.

## Map and objective rules

Maps are tactical systems, not decorative arenas.

Each map must provide:

- Readable team territories and objective locations.
- Multiple useful routes with different risk.
- Cover that supports peeking without hiding the whole fight.
- Sightlines with deliberate range and interruption.
- Traversal that matches operator collision and camera limits.
- Lighting that preserves silhouettes and target readability.
- Ambience that gives location and threat information without masking critical
  gameplay audio.
- Valid spawns that prevent immediate sightline kills.
- Navigation and objective markers suitable for a tactical map.

Map Lab saves a versioned map document. Hosting selects a saved document. The
server validates the schema, supported objects, objective markers, round rules,
and safe bounds before it distributes the map.

## HUD and information rules

The public build should show only information needed to play:

- Reticle or weapon sight.
- Health state.
- Current weapon and ammunition.
- Grenade or equipment state.
- Round timer and score.
- Objective state.
- Team identity.
- Necessary interaction prompts.

Debug bones, camera labs, aim lines, hurtboxes, solver values, and authority
diagnostics belong in developer tools. They do not belong in the player build.

## Where each feature belongs

| Feature | Runtime owner | Shared data or tool |
|---|---|---|
| Movement and stance | `scripts/player/player_controller.gd` | `config/operator_movement_tuning.json` and Keyboard Mapping Lab |
| Aim intent | `scripts/camera/camera_aim_resolver.gd` | Camera Lab and shared camera profiles |
| Weapon validation and ammunition | `scripts/weapons/socom_weapon_controller.gd` and multiplayer server | Gunsmith weapon profile |
| Spread and recoil bloom | `scripts/weapons/weapon_ballistics.gd` and `scripts/weapons/operator_composure.gd` | `config/weapons/*.json` and Composure Lab |
| Reticle feedback | `scripts/ui/socom_dynamic_reticle.gd` | Weapon reticle profile in `config/weapons/*.json` |
| Operator visuals | `scripts/player/operator_animation_driver.gd` and pose solvers | Rig and Hands plus animation profiles |
| Hurtboxes and damage regions | Server combat resolver | Composure hitbox profile |
| Map geometry and ambience | Map runtime | Map Lab and versioned map documents |
| Lobby, teams, rounds, and objectives | `scripts/network/socom_multiplayer_slice.gd` | Selected map gameplay rules |
| Player settings | Input and settings services | Keyboard Mapping Lab and in-game Options |

If a tool needs a new behavior, add the behavior to the runtime owner first.
Then make the tool edit its shared data.

## Current implementation baseline

The repository currently contains these foundations:

- Deterministic muzzle-origin shot dispersion.
- Movement, stance, airborne, composure, and burst inputs to gameplay spread.
- A reticle that reads gameplay spread and adds presentation-only shot bounce.
- Separate authoritative and visual reticle centers.
- Stance-aware animation, weapon placement, and two-hand visual solving.
- Shared weapon profiles for ballistics, reticle response, and composure.
- Server-side multiplayer shot, ammunition, health, elimination, and respawn
  paths.
- Saved map documents, a map library, runtime map loading, ambience, objective
  markers, training dummies, and demolition rule data.
- Lobby teams, ready states, countdown, team spawns, round timer, round score,
  and demolition objective state.

Treat this list as a baseline, not a release claim. A feature is complete only
after its focused regression passes in the current build and it passes a real
host/client playtest.

## Build next

### Priority 0: prove one complete browser match

- Finish the public browser host and join service.
- Validate and distribute the selected saved map before match start.
- Test two real clients through lobby, team choice, ready state, countdown,
  demolition, round end, next round, and return to lobby.
- Make bomb defuse a complete server-owned action with interruption rules.
- Move reload ammunition transfer to a server-owned animation commit event.
- Verify death, spectating, round reset, and reconnect behavior.
- Verify that every saved Gunsmith, Composure, Rig and Hands, input, and map
  profile reaches the public player build.

### Priority 1: complete the competitive loop

- Add explicit fire-mode profiles and server validation.
- Add weapon swap and map-specific loadout persistence.
- Complete spectator flow and dead-player restrictions.
- Add Suppression as a distinct timed elimination mode.
- Add clear team colors, round results, match results, and objective HUD.
- Add map validation for spawns, objective markers, playable bounds, and common
  camera or collision traps.
- Add browser-safe persistence for maps, settings, and loadouts.

### Priority 2: deepen tactical play

- Add a tactical map with team, objective, and navigation information.
- Add team communication channels and concise tactical callouts.
- Add doors, ladders, pickups, mounted weapons, and other explicit interaction
  contracts only when the server can validate them.
- Add Escort, Extraction, and Breach as separate objective contracts.
- Add stealth and sound propagation as readable gameplay systems.

### Priority 3: content and polish

- Build several weapon archetypes with distinct, tested handling.
- Author complete stance-aware animation sets for each weapon family.
- Improve muzzle flash, audio, impacts, tracers, and recoil presentation without
  changing shot authority.
- Build map texture, lighting, ambience, and optimization pipelines.
- Add accessibility options for controls, color, reticle, audio, and motion.

## Review checklist

Before accepting a combat or multiplayer change, answer yes to each applicable
question:

- Does one system own the authoritative value?
- Does the server own match-changing results?
- Does the reticle communicate the actual gameplay state?
- Does visual recoil leave the shot direction unchanged?
- Does stance affect both gameplay and presentation coherently?
- Do arms and weapon follow the shared target without moving the camera?
- Does reload preserve the lower-body stance and movement contract?
- Does the map provide fair spawns, routes, cover, and objective access?
- Does Save and Apply reach `main.tscn` and the public player build?
- Is there a focused regression for the contract?
- Has the feature passed a real host/client test?

If any required answer is no, the feature is not finished.

## Verification map

Use focused regressions during development:

- Reticle and aim separation: `tools/reticle_render_integration.gd`
- Weapon fire and dispersion: `tools/weapon_fire_regression.gd`
- Stance bloom: `tools/weapon_stance_bloom_regression.gd`
- Shared aim chain: `tools/shared_aim_chain_regression.gd`
- Weapon pose: `tools/operator_weapon_pose_regression.gd`
- Reload input and animation: `tools/reload_input_regression.gd`
- Hurtboxes: `tools/run_hurtbox_regression.gd`
- Map creation and persistence: `tools/map_creation_lab_regression.gd`
- Multiplayer lobby and match slice: `tools/multiplayer_slice_regression.gd`

Run `tools/run_integration_gate.sh quick` at an integration checkpoint. Run the
full clean gate only when preparing a promoted build.
