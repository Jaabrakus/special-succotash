# SOCOM-141 Commercial Production Roadmap

Status: Active production plan
Primary target: PC closed alpha, then commercial PC release
Canonical project: `main.tscn` launched through `game_launcher.tscn`

## Commercial definition of done

The game is commercially ready only when a new customer can:

1. Buy or receive the game through an approved distribution channel.
2. Install and launch it without developer assistance.
3. Configure display, audio, controls, accessibility, and networking.
4. Complete onboarding and understand the objective.
5. Join or host a match reliably.
6. Play a complete match without severe animation, networking, performance,
   objective, audio, or user-interface failures.
7. Leave, reconnect, report a problem, and receive support.
8. Trust that saved data, accounts, privacy, security, and purchases are handled
   responsibly.

Passing internal demos is not sufficient. Commercial readiness requires
repeatable external-player success.

## Product boundary

### Launch product

- One polished tactical multiplayer game.
- One canonical PS1-style operator rig, using original or properly licensed
  production assets.
- Demolition as the flagship mode.
- Suppression/team elimination as the second mode if schedule permits.
- Four to six production-quality maps.
- A focused launch weapon roster with distinct tactical roles.
- Frag, flash, and smoke grenades.
- Private matches, invite codes, server browser or matchmaking, spectators,
  team selection, ready state, complete round flow, and rematches.
- Keyboard/mouse and controller support on PC.
- Training range and concise onboarding.

### Explicitly post-launch unless already stable

- Android release.
- User-generated public map marketplace.
- Large progression economy.
- Cosmetic store.
- Motion capture from arbitrary video.
- Multiple interchangeable character skeletons.
- Additional modes that divide the initial population.

## Gate zero: intellectual property and business

- [ ] Decide whether this is an original SOCOM-inspired tactical shooter or an
  officially licensed SOCOM product.
- [ ] Do not market it as a SOCOM 2 remaster without the required rights.
- [ ] Replace or license every imported character, animation, weapon, texture,
  sound, logo, map, name, and user-interface asset.
- [x] Maintain an asset register containing source, creator, license, receipt,
  modification status, attribution requirement, and approved platforms.
- [ ] Complete company, banking, tax, accounting, insurance, and contract setup.
- [ ] Prepare an end-user license agreement, privacy policy, terms of service,
  community rules, moderation policy, copyright contact, and refund/support
  procedures with qualified professional review.
- [ ] Define age-rating and regional-release requirements before store review.
- [ ] Confirm licenses for every open-source dependency and ship required notices.

Exit criterion: the team can prove it may commercially distribute every byte
in the build and every public-facing brand element.

## Gate one: architecture freeze

### Sources of truth

| Responsibility | Sole owner |
| --- | --- |
| Movement, stance, collision | `CharacterBody3D` player controller |
| Aim intent and shared target | Camera/aim resolver |
| Shots, ammunition, damage | Authoritative weapon/server contract |
| Match, objectives, score | Authoritative match server |
| Base character appearance | Operator AnimationTree/motion selector |
| Action appearance | Presentation event router |
| Weapon mount and sockets | Gunsmith weapon profile |
| Support hand | Final foregrip IK pass |
| Foot contact | Final grounding pass |
| Audio routing | Acoustic propagation engine |
| Saved Lab output | Versioned shared profiles |

### Required cleanup

- [ ] Remove duplicate gameplay implementations from Labs.
- [ ] Reduce god files and keep focused components near 500 lines where practical.
- [ ] Remove animation systems that write the same bones in the same phase.
- [ ] Remove any second weapon parent or world-pinned rifle path.
- [ ] Consolidate player/server ammunition ownership; weapon data defines
  capacity and behavior, while player/server inventory owns current ammunition.
- [ ] Version all profiles and provide safe migration/default behavior.
- [ ] Add a feature flag and instant fallback for motion matching.
- [ ] Document every runtime event and its authoritative/presentation consumers.

Exit criterion: one diagram can explain every source of truth, and every Lab
edits the same profiles consumed by gameplay.

### Authoring-tool boundary

- [ ] Use the Godot editor as the primary production surface for scenes,
  skeleton import, AnimationTree state, collisions, navigation, materials,
  lighting, audio assignment, and versioned Resources.
- [ ] Move reusable Animation Studio, Gunsmith, and Map Lab authoring controls
  into focused `@tool` editor plugins, docks, inspectors, and 3D gizmos.
- [ ] Keep runtime tools only when they must observe the exact gameplay camera,
  reticle, networking, acoustic context, or player-facing map-authoring flow.
- [ ] Make editor tools and runtime load the same Resources. Do not maintain a
  second saved pose, animation route, weapon mount, or map state in runtime UI.
- [ ] Migrate one vertical slice at a time. Prove editor/runtime output parity
  before removing its old Lab path or changing verified playable behavior.
- [ ] Preserve the non-programmer workflow: direct manipulation, clear visual
  ownership, natural-language proposals, validation, undo, and one-click test.

This keeps the useful SOCOM-specific visual workflow without maintaining a
second game editor inside the game. Animation-state authoring is the first
migration target because duplicate preview/runtime animation ownership has
caused the most severe regressions.

### Godot-native authoring checkpoint — 2026-08-24

- [x] The project enables a real Godot `EditorPlugin` and `EditorDock` named
  **SOCOM Routes**, following Godot's documented editor-extension workflow.
- [x] The dock reads `config/operator_animation_map.json` directly. It does not
  create another profile, cache, pose store, or runtime animation graph.
- [x] Event, posture, and weapon-family controls show the resolved state, clip,
  body layer, presentation effects, and contextual return as a simple vertical
  flow. The Gameplay Dictionary explains what presentation may and must not do.
- [x] The dock uses the same normalized state contract and presentation router
  as the playable operator. Every event across standing, crouched, and prone
  contexts matches the runtime result in the parity regression.
- [x] `FIRE_ACCEPTED` exposes `ENTER_READY_AIM` and `RAIL_TO_BLUE_LINE` without
  gaining bullet, ammunition, aim, damage, or camera authority.
- [x] Natural-language route commands become visible proposals before any
  mutation. Clip/event compatibility validation rejects invalid mappings such
  as routing a fire event to a locomotion clip.
- [x] Approving a proposal creates an in-memory draft through Godot's native
  undo/redo history. Proposal review, approval, undo, and redo do not touch the
  profile on disk.
- [x] Explicit Save validates again, rejects concurrent disk changes, and uses
  a same-directory temporary file plus atomic rename. Runtime consumes the
  saved result without conversion or a second authoring format.
- [x] Refresh and context selection preserve the animation-map SHA-256 unless
  the user explicitly saves an approved draft.
- [x] The dock's Play button delegates to Godot's configured project main scene,
  which remains `res://game_launcher.tscn` and launches canonical gameplay.
- [x] The plugin explicitly opens and focuses **SOCOM Routes** after Godot
  restores a saved layout. A persistent **Project > Tools > SOCOM Routes**
  command recovers the dock if a user closes or moves it.

The existing runtime Animation Studio remains available during migration. The
Godot-native route slice now owns review, validation, undo/redo, conflict-safe
save, and one-click play against the shared profile. Do not remove the old route
editor until all of its remaining visual preview/edit capabilities have moved
and the playable regression remains green.

### Gameplay composition and action-ownership checkpoint — 2026-08-24

- [x] The authoritative player, collision capsule, and operator visual root now
  live in `scenes/player/operator_player.tscn`. Training gameplay instantiates
  that scene instead of rebuilding those stable children in code.
- [x] Dive and roll use a stable chest-owned rifle carry. The full-body clip
  still owns torso and legs, while final two-hand IK moves both palms to the
  rifle sockets. The animated wrist can no longer drag the rifle behind the
  pelvis.
- [x] The dive regression measures signed trigger and muzzle depth, per-frame
  rotation, chest-envelope travel, socket contact, and final prone recovery.
  Current evidence is `0.000°` maximum rotation step, `0.0643 m` maximum chest
  travel, and a minimum muzzle depth of `0.8197 m` in front of the chest.
- [x] A grenade-equipped player keeps the rifle holstered for the complete
  equip/aim/throw state. Completing a throw cannot reveal the rifle with the
  throwing hand's final transform.
- [x] Grenade trajectory preview continues through collision, uses the runtime
  gravity and bounce profile, colors post-impact travel separately, and marks
  the predicted final landing point.

This is the first scene-composition vertical slice. Camera, operator internals,
weapon sockets, world geometry, and UI still require staged scene extraction;
do not convert them in one rewrite.

## Gate two: character and animation quality

### Canonical rig

- [ ] Freeze the production skeleton and bone naming contract.
- [ ] Freeze operator scale, origin, forward axis, ground height, and root bone.
- [ ] Validate mesh skin weights and bone transforms in all extreme poses.
- [ ] Prevent head, wrist, elbow, knee, and ankle discontinuities.
- [ ] Confirm right-palm weapon attachment in every state.
- [ ] Confirm left-palm foregrip contact where the action requires two hands.

### Locomotion coverage

- [ ] Standing idle, eight-direction walk/run, starts, stops, pivots, and turns.
- [ ] Crouched idle, directional movement, starts, stops, and turns.
- [ ] Prone enter, idle, crawl forward/backward, steering, stop, and exit.
- [ ] Jump start, airborne, landing, dive, roll, and recovery.
- [ ] Peek/lean and obstruction-aware low-ready behavior.
- [ ] Stairs, slopes, ledges, moving surfaces, and uneven-ground foot locking.

### Actions

- [ ] Fire from standing, moving, crouched, and prone contexts.
- [ ] Reload for each supported stance and weapon family.
- [ ] Grenade equip, hold, release cue, throw, and recovery.
- [ ] Hit reactions, incapacitation/death, spectator transition, and respawn.
- [ ] Weapon equip/swap and empty-magazine behavior.
- [ ] Contextual return restores the current locomotion state without snapping.

### Motion matching rollout

- [x] Pose-search scoring foundation exists in shadow mode.
- [ ] Build the offline PS1 clip sampler and database generator.
- [ ] Store velocity, predicted trajectory, facing, feet, hips, phase, contacts,
  posture, gait, and weapon-family tags.
- [ ] Add Animation Studio database review and candidate-cost visualization.
- [ ] Compare shadow selections with the current BlendSpace route.
- [ ] Enable only lower-body locomotion after approval.
- [ ] Keep fire, reload, grenade, death, and mobility actions event-driven.
- [ ] Keep weapon, aim, IK, grounding, and recoil as bounded final passes.

Exit criterion: external reviewers cannot reproduce weapon detachment, extreme
limb distortion, foot sliding that affects readability, or state snapback in
the production movement/action matrix.

## Gate three: combat quality

### Aim and weapon behavior

- [ ] One aim intent drives camera, reticle, rail visualization, and server shot.
- [ ] Muzzle obstruction prevents firing through illegal nearby geometry.
- [ ] Movement, turning, stance, sustained fire, recovery, and weapon identity
  affect authoritative accuracy.
- [ ] Reticle bloom exactly communicates gameplay spread.
- [ ] Visual kick never redirects the authoritative shot.
- [ ] Semi-auto, burst, and full-auto cadence are deterministic and validated.
- [ ] Automatic reload at zero rounds follows the approved action policy.

### Damage

- [ ] Head, neck, torso, arms, and legs use versioned hurtbox definitions.
- [ ] Hitbox shapes remain inside the visible production character.
- [ ] Weapon profiles define damage, range behavior, penetration, and headshot
  multipliers.
- [ ] Server resolves hits, damage, death, assists, and friendly-fire policy.
- [ ] Blood and impact effects communicate results without obscuring gameplay.
- [ ] No synthetic metallic hit-confirm sound remains unless deliberately chosen.

### Grenades

- [ ] Server validates inventory, release time, origin, velocity, fuse, collision,
  damage, line of sight, and replication.
- [ ] Visual arc matches the server simulation within an approved tolerance.
- [ ] Frag effect radius visually matches its damage radius.
- [ ] Flash produces exposure/visibility-based full-screen blindness and recovery.
- [ ] Smoke provides readable, performant concealment and consistent networking.

Exit criterion: combat results are predictable, explainable, authoritative,
and consistent under latency.

## Gate four: multiplayer and backend

### Match lifecycle

- [ ] Account or guest identity strategy.
- [ ] Region selection and service health reporting.
- [ ] Host/join, invite code/link, lobby, teams, ready state, loadout, spectators.
- [ ] Map/mode selection, countdown, spawn, rounds, halftime if required, victory,
  scoreboard, rematch, leave, reconnect, and host/server loss behavior.
- [ ] Dedicated-server deployment and graceful version rejection.

### Authority and replication

- [ ] Server owns transforms, stance, ammunition, cadence, aim validation,
  dispersion, hits, damage, grenades, objectives, time, score, and victory.
- [ ] Clients send input and bounded aim intent.
- [ ] Snapshot interpolation and reconciliation remain stable under tested latency,
  jitter, packet loss, and reordering.
- [ ] Lag compensation has bounded history and cannot validate impossible shots.
- [ ] Replicate animation intent/events, not full skeleton transforms.
- [ ] Interest management limits irrelevant actors, effects, and audio events.

### Security and abuse

- [ ] Validate every client request.
- [ ] Rate-limit network and backend endpoints.
- [ ] Authenticate privileged server operations.
- [ ] Protect secrets; never ship service-role credentials in the client.
- [ ] Add report, mute, block, kick/ban, evidence, appeal, and audit-log flows.
- [ ] Perform dependency, protocol, backend-policy, and basic penetration reviews.

### Load validation

- [ ] Automated soak matches.
- [ ] Maximum supported players with simultaneous fire, grenades, deaths, voice,
  joins, leaves, and spectators.
- [ ] Server CPU, memory, bandwidth, tick stability, and cost budgets.
- [ ] Recovery from service restart, network interruption, and database failure.

Exit criterion: the supported lobby size completes repeated soak matches within
latency, bandwidth, crash, and correctness budgets.

## Gate five: modes, maps, and bots

### Demolition production rules

- [x] Neutral bomb spawn and server-owned carrier state.
- [x] Pickup, drop, carrier loss, recovery, planting, cancellation, defense,
  defuse if supported, explosion, timeout, elimination, and round winner.
- [x] Both teams receive correct objectives and HUD information.
- [x] Mid-match arrivals receive the current objective and round snapshot as
  safe spectators; reconnectable player identity remains an operations task.
- [ ] Tie, simultaneous event, and final-frame edge cases are deterministic.

### Production map requirements

- [ ] Four to six maps with distinct scale, sightlines, routes, objectives,
  interiors, verticality, and team identities.
- [ ] Valid spawns, protected initial routes, objective placement, boundaries,
  collision, stairs, slopes, cover, peeks, grenade behavior, and spectator views.
- [ ] Acoustic rooms/portals, ambience, lighting, fog, particles, and materials.
- [ ] Navigation data for training dummies/bots if included.
- [ ] Performance/visibility budgets and no unintended out-of-bounds access.
- [ ] Automated map package validation and deterministic multiplayer loading.

### Map Lab

- [ ] Undo/redo, selection, duplication, grouping, snapping, transforms, materials,
  lighting, ambience, objectives, spawns, dummies, boundaries, validation, save,
  versioning, and playtest.
- [ ] Human and LLM operations use the same explicit command/data contract.
- [ ] Community maps remain private/experimental until moderation, security,
  compatibility, distribution, and legal workflows are complete.

Exit criterion: every launch map passes design, exploit, performance, audio,
lighting, objective, networking, and accessibility reviews.

## Gate six: audio, visual effects, and presentation

### Audio

- [x] Shared acoustic propagation foundation exists.
- [ ] Production-quality licensed gunshots, tails, impacts, footsteps, foley,
  grenades, objectives, UI, ambience, and voice lines.
- [ ] Indoor/outdoor, obstruction, portals, distance, material response, and
  concurrent-voice budgets verified in real maps.
- [ ] Mix remains readable with a full lobby.
- [ ] Dynamic range, master/music/effects/voice sliders, mute behavior, device
  changes, and accessibility options.

### Visual presentation

- [ ] Production materials, lighting, post-processing, particles, decals,
  weather/ambience if included, and consistent art direction.
- [ ] Clear team identification without creating unfair visibility.
- [ ] Effects scale by graphics preset and do not change gameplay truth.
- [ ] HUD readability at supported resolutions, aspect ratios, and UI scales.

Exit criterion: a full-lobby match remains readable, performant, stylistically
consistent, and free of placeholder presentation in customer-facing paths.

### Gate-six presentation-foundation checkpoint — 2026-08-24

- [x] One persistent client-local contract now owns master, music, effects, and
  voice volume; master mute; wide, balanced, and night dynamic range; output
  device selection and fallback; graphics preset; UI scale; reduced flashes;
  and camera-shake strength.
- [x] Music, effects, voice, UI, ambience, and acoustic routes use distinct
  buses. Flashbang ducking changes the effects route without overwriting the
  saved master level.
- [x] The acoustic runtime has a 24-voice total pool, a 14-event frame budget,
  event-class limits, range culling, and priority-based replacement. Normal
  operator foley uses this shared pool instead of allocating 20 fallback voices
  for every operator.
- [x] Low through ultra presets scale flash, smoke, fuse-spark, impact-spark,
  and muzzle-light presentation. Presets do not change smoke radius, smoke
  density state, hit detection, damage, or other gameplay truth.
- [x] Player settings expose every new presentation control from both the
  launcher and in-game controls panel. The focused regression checks 42 mix,
  routing, budget, UI, quality-scaling, and accessibility conditions.

This checkpoint does not close Gate Six. Runtime gunshots, impacts, footsteps,
foley, and UI confirmations still include synthesized reference sounds rather
than licensed production assets. Real-map indoor/outdoor review, hardware audio
device hot-plug testing, a measured full-lobby mix, production materials and
lighting, team-identification fairness, and supported-resolution/aspect-ratio
HUD review remain open.

## Gate seven: user experience and accessibility

- [ ] First launch, safe defaults, brightness, audio, display, input selection.
- [ ] Main menu, play, training, settings, credits, legal, support, and exit.
- [ ] Complete keyboard/mouse and controller remapping with conflict detection.
- [ ] Mouse sensitivity, inversion, dead zones, aim sensitivity, hold/toggle
  options, vibration, and controller glyphs.
- [ ] Subtitles/captions where applicable, color-safe UI, scalable text, readable
  contrast, reduced flashes/shake, and independent audio controls.
- [ ] Training explains movement, stance, aiming, accuracy, reload, grenades,
  objectives, team identification, and communication.
- [ ] Clear errors for version mismatch, lost connection, full server, ban,
  maintenance, corrupted settings, and unavailable services.

Exit criterion: an uninstructed external player can configure the game and
complete a match objective.

## Gate eight: performance and platform engineering

### PC targets

- [ ] Define minimum, recommended, and development hardware.
- [ ] Define resolution, frame-rate, frame-time, memory, loading, server-tick,
  bandwidth, and disk-size budgets.
- [ ] Profile CPU, GPU, physics, animation, IK, audio, networking, UI, shaders,
  particles, maps, and asset streaming.
- [ ] Remove startup compilation/load spikes from customer-critical paths.
- [ ] Add graphics presets and an auto-detect baseline.
- [ ] Validate windowed, borderless, fullscreen, multiple monitors, focus loss,
  alt-tab, high-refresh displays, and common aspect ratios.

### Build engineering

- [ ] Reproducible release exports with version, commit, channel, and content hash.
- [ ] Development, staging, playtest, and production environments.
- [ ] Signed builds where required.
- [ ] Crash dumps, structured logs, privacy-safe diagnostics, and symbol storage.
- [ ] Delta/update behavior, save/config migration, rollback, and previous-version
  compatibility policy.

Exit criterion: release builds meet published requirements on a representative
hardware matrix and can be reproduced from a tagged commit.

## Gate nine: quality assurance

### Automated coverage

- [ ] Unit tests for profiles, state resolution, ammunition, ballistics, damage,
  grenades, objectives, map validation, serialization, and pose search.
- [ ] Integration tests for every stance/action/weapon ownership transition.
- [ ] Network tests for join, reconnect, fire, reload, grenade, death, objective,
  round end, rematch, and version mismatch.
- [ ] Performance tests for startup, map load, full lobby, effects, and long soak.
- [ ] Release smoke test on every supported platform/configuration.

### Manual matrices

- [ ] Every action from standing, crouched, prone, moving, airborne, obstructed,
  reloading, empty, damaged, spectating, high latency, and packet loss contexts.
- [ ] Every weapon on every operator/map combination included at launch.
- [ ] Every map with both teams, every objective state, and maximum players.
- [ ] Accessibility, localization, controller, audio-device, resolution, and
  graphics-preset passes.

### Defect policy

- Block release for crashes, data loss, security defects, match deadlocks,
  objective failures, severe cheating paths, broken purchases, severe animation
  corruption, inaccessible onboarding, or unsupported-hardware claims.
- Maintain severity, owner, reproduction, affected build, fix, regression test,
  verification, and release-note fields for every tracked defect.

Exit criterion: zero unresolved release blockers and an explicitly accepted
list of lower-severity known issues.

## Gate ten: telemetry, operations, and support

- [ ] Privacy-reviewed events for launch, crash, matchmaking, lobby, match start,
  disconnect, match completion, map/mode, performance bucket, and errors.
- [ ] Do not collect sensitive information without a defined need and policy.
- [ ] Dashboards for crash-free sessions, match completion, disconnects, latency,
  server health, queue health, concurrency, retention, and support volume.
- [ ] Alerts and on-call ownership for production services.
- [ ] Incident response, maintenance, status communication, rollback, ban waves,
  backup, and disaster-recovery procedures.
- [ ] In-game support/reporting and a staffed external support channel.

Exit criterion: the team can detect, diagnose, communicate, mitigate, and repair
a live production incident.

## Gate eleven: store and launch

- [ ] Final name, logo, capsule/key art, screenshots, trailer, description,
  feature list, system requirements, supported languages, content disclosures,
  privacy links, support links, and legal notices.
- [ ] Store integration for achievements/cloud/controller/overlay only if stable.
- [ ] Separate internal, closed alpha, closed beta, release candidate, and public
  release branches/channels.
- [ ] Recruit representative external players rather than only project followers.
- [ ] Prepare press/influencer keys, embargo process, community channels,
  moderation coverage, launch FAQ, known issues, and patch schedule.
- [ ] Complete store/platform review using the current official requirements.

Exit criterion: approved store build, tested backend capacity, support coverage,
rollback plan, launch communications, and signed release decision.

## Delivery sequence

### Milestone A — Vertical slice

- One PS1 operator.
- One rifle family.
- Frag and flash.
- One complete Demolition map.
- Private match with invite code.
- Complete lobby-to-rematch loop.
- Stable animation ownership and acoustic presentation.

### Milestone B — Closed alpha

- Two maps.
- Core launch weapon roles.
- Dedicated authoritative server.
- 8–16-player soak testing.
- Training and settings.
- Crash/performance/network diagnostics.
- No severe character or weapon attachment failures.

### Milestone C — Closed beta

- Launch feature set and all launch maps.
- Production assets and audio.
- Moderation, reporting, support, telemetry, and store integration.
- Balance, accessibility, hardware, latency, and exploit testing.
- Save/config/content migration and patch pipeline.

### Milestone D — Release candidate

- Content lock.
- Only blocker fixes.
- Full regression and certification/store checks.
- Capacity test, disaster rehearsal, rollback build, and launch runbook.
- Formal go/no-go review.

### Milestone E — Commercial release

- Monitor services and crash-free sessions continuously.
- Publish known issues and first hotfix expectations.
- Prioritize match completion, security, crashes, exploits, and severe balance
  problems before adding content.

## Immediate execution backlog

1. Freeze the PS1 rig as the canonical production operator.
2. Characterize and fix standing, prone elbow, jump, turn, and weapon-follow
   failures without changing working reload behavior.
3. Finish the offline motion-matching database builder and Studio review UI.
4. ~~Consolidate player/server ammunition ownership.~~ Completed 2026-08-23:
   mutable local ammunition is player-owned per weapon identity, while the
   multiplayer server remains authoritative per peer.
5. Complete one Demolition map and its full round state machine.
6. ~~Run an automated lobby-to-rematch match with multiple clients.~~ Real ENet
   processes now complete repeated lobby, spawn, snapshot, match, teardown, and
   rematch cycles with 2, 4, 8, and the advertised 16 peers. Four full visual
   clients passed three cycles. The 16-peer host test uses lightweight network
   bots so one workstation does not create 256 animation rigs. All 16 peers also
   completed two cycles of simultaneous fire and reload validation. A designated
   client also disconnects and rejoins a 16-player live round as a safe spectator,
   then regains normal operator authority after the rematch. Long-duration,
   packet-loss, and adverse-network soak remain open.
7. ~~Profile startup and an initial maximum-player firefight.~~ The current local
   debug baseline covers 16 peers firing five authoritative rounds each per cycle,
   player-owned ammunition transfer, reload, and bounded server processing. Repeat
   this on target hardware with effects, real remote clients, and sustained combat
   before setting a shipping requirement.
8. Build training, settings, complete remapping, and failure messages.
9. Perform the asset/license audit and replace unapproved content.
10. Produce the first reproducible closed-alpha build.

Current asset register: `config/commercial_asset_register.json`. Its existence
is complete; five included packages remain explicitly blocked pending evidence
or replacement. A valid register is not the same as asset clearance.

## Verified production baseline — 2026-08-23

- [x] The canonical project parses on `main`.
- [x] The complete quick integration gate passes.
- [x] The complete full integration gate passes, including deterministic camera
  regression, commercial asset-register validation, release-protection checks,
  and startup performance regression.
- [x] Standing, crouched, and prone Ready Aim share the reticle target.
- [x] The right palm remains attached to the rifle trigger socket and the left
  palm remains on the support grip during dynamic yaw/pitch.
- [x] Standing locomotion carries the rifle with the animated chest while its
  authored motion remains bounded below one centimetre.
- [x] Reload owns the complete rifle motion, transfers the magazine to the left
  hand, reaches two-hand regrip, and has no one-frame teleport.
- [x] Stance, jump, dive, prone crawl, instant reversal, and aim-relative strafe
  pass the current gameplay-control contract.
- [x] Forward prone keeps an alternating support leg grounded and preserves a
  straight pelvis-to-head travel axis.
- [x] Launcher resource warmup is verified: 11 large resources warmed, with a
  measured playable instantiation near 132 ms on the development machine.
- [x] Mutable ammunition is player-owned and persists by weapon identity;
  weapon profiles supply capacity and initial-loadout defaults only.
- [x] A 16-peer local ENet lifecycle test completes two match/rematch cycles.
  On the development Mac, the warmed listen-server sample used 174.44 MB and
  measured 15.685 ms mean / 20.915 ms p95 wall-frame intervals. This is a debug
  engineering measurement, not a published hardware requirement or firefight
  performance claim.

## Network combat-load milestone — 2026-08-24

- [x] Sixteen real ENet peers complete two match/rematch cycles while each peer
  fires five rounds and reloads in every cycle: 160 server-authorized shots total.
- [x] The server verifies every peer's player-owned total ammunition decrease and
  subsequent magazine/reserve transfer instead of trusting client counters.
- [x] Reliable shot requests are queued per player and drained at the authoritative
  weapon cadence; duplicate sequences and queues beyond eight entries are rejected.
- [x] Sixteen-entity world state is divided into four-entity packets. The regression
  serializes representative packets and keeps them below 1,200 bytes, avoiding the
  observed ENet MTU overflow.
- [x] The warmed local listen-server sample used 174.65 MB and measured 16.312 ms
  mean / 21.435 ms p95 wall-frame intervals during the two-cycle combat probe.

This milestone validates transport, cadence, ammunition, reload, and lifecycle
under simultaneous local load. Its shots were intentionally directed into safe
space; the controlled-damage milestone below closes the separate local hit and
elimination gate.

## Controlled network-damage milestone — 2026-08-24

- [x] Sixteen real ENet peers complete two match/rematch cycles with eight paired
  Alpha shooters and Bravo targets after the simultaneous fire/reload phase.
- [x] Each target receives three authoritative torso hits with the configured
  `34 + 34 + 34` damage progression and reaches elimination; every shooter remains
  alive and undamaged.
- [x] Match teardown restores the complete roster, health, ammunition, and damage
  state before the second cycle repeats the same result.
- [x] Ballistic queries pass through an operator's broad movement capsule and use
  the animated anatomical areas for HEAD/TORSO/PELVIS/LIMB classification. Static
  world collision still blocks bullets.
- [x] Multiplayer aim now sends a bounded reticle convergence distance. The server
  reconstructs that point from its stable player anchor and traces from its own
  muzzle, preventing client/server animation phase differences from moving the
  authoritative shot away from the intended reticle target.
- [x] Convergence above 250 metres is rejected, sequence replay remains rejected,
  and the client never supplies the authoritative muzzle origin.
- [x] The second-cycle warmed listen-server sample used 174.76 MB and measured
  16.147 ms mean / 26.266 ms p95 / 36.060 ms maximum wall-frame intervals. These
  are local debug engineering measurements, not shipping requirements.

This closes the local maximum-lobby fire/reload/torso-damage/elimination/rematch
gate. Headshot, limb, and anatomical overlap classification remain covered by
focused deterministic regressions. Internet latency, packet loss, long-duration
soak, exploit testing, and target-hardware capacity remain open.

## Reconnect lifecycle milestone — 2026-08-24

- [x] Four and sixteen real ENet peers complete two match/rematch cycles while
  one designated client deliberately disconnects during the first live round.
- [x] The returning client receives a new transient ENet peer identity and the
  server keeps it as a spectator: the lobby contains it, the active operator
  roster does not, and it receives no local gameplay authority.
- [x] The complete lobby returns safely after cycle one. Every player readies
  again, and the returning peer receives a normal authoritative operator in
  cycle two.
- [x] The ordinary two-peer lifecycle path still passes with reconnect mode off.
- [x] The second-cycle maximum-lobby sample used 174.71 MB and measured 15.823 ms
  mean / 21.374 ms p95 / 21.693 ms maximum wall-frame intervals on the local
  debug workstation.

This closes local transport reconnect and safe mid-round spectator behavior.
It does not provide durable account/session identity, reserved slots, recovery
after host loss, or proof under Internet latency, jitter, packet loss, and
reordering. Those remain commercial operations and adverse-network gates.

## Weapon-presentation refactor checkpoint — 2026-08-24

- [x] The 2,218-line weapon-pose god file is gone. The compatibility solver is
  2 lines and retains the public `SocomOperatorWeaponPoseSolver` type.
- [x] State, IK/kinematics, action ownership/follow, Gunsmith placement, Ready
  Aim, and public API are separate layers between 205 and 452 lines. Mobility
  grip, socket mechanics, geometry, and diagnostics remain focused services.
- [x] The god-file budget now enforces a 500-line ceiling for every weapon-pose
  implementation layer and a 50-line ceiling for the compatibility entry point.
- [x] Focused weapon-pose, weapon-anchor, dive-hand attachment, reload-input,
  and pose-ownership regressions pass after extraction.
- [x] The complete quick integration gate passes after the refactor, including
  weapon rigs, dynamic hand ownership, reload handoff, mobility, and multiplayer.
- [x] The god-file budget gate no longer reports any weapon-pose component. The
  operator animation driver, Animation Studio pose authoring, and multiplayer
  authority controller have since been extracted too. Gun calibration and map
  creation remain explicit large-file debt.
- [x] Prone Ready Aim now applies its calculated clearance to the right-hand IK
  path. The focused regression measures `9.95 cm` muzzle clearance and `9.88 cm`
  minimum hand/forearm clearance while keeping the rendered barrel within
  `0.002°` of the shared reticle target.

This is a technical baseline, not a commercial-release claim. Legal clearance,
external playtesting, multiplayer soak, production content, accessibility,
platform packaging, and operations remain open gates.

## Grenade throw recovery checkpoint — 2026-08-24

- [x] Full and quick grenade throws now read their playback speeds from the one
  shared Grenade Lab profile (`1.15x` full, `2.05x` quick).
- [x] Full throw power builds in `0.78 s`, and saved overhand/underhand launch
  speeds are `16.0 m/s` and `6.4 m/s`, preserving their distinct arcs while
  making grenade flight approximately five percent faster.
- [x] Grenade release remains tied to the authored hand-release cue rather than
  a detached gameplay timer.
- [x] A separate recovery cue begins during the final `14–16%` of each stance's
  throw. It starts the `0.12 s` full-body-to-locomotion blend while translation
  remains locked. The action-complete cue restores movement only after the base
  locomotion route has visual control, preventing the throw pose from gliding.
- [x] Grenade Lab exposes full/quick playback speed and movement-recovery blend
  controls, and Save continues feeding the playable build through the shared profile.
- [x] Grenade release-timeline, tactical-grenade, shared-profile, project parse,
  and gameplay input/recovery regressions pass after the final timing pass.

## Operator-animation refactor checkpoint — 2026-08-24

- [x] The 1,393-line operator-animation driver is now a 10-line compatibility
  entry point that retains the public `SocomOperatorAnimationDriver` type.
- [x] State (`147` lines), API (`149`), pose/locomotion (`365`), actions (`354`),
  presentation (`135`), diagnostics (`47`), and runtime (`219`) have distinct
  ownership layers, each below the enforced 500-line ceiling.
- [x] Every function from the prior driver remains present exactly once. The
  only additions are the grenade recovery cue and its saved blend-time reader.
- [x] Operator-animation, pose-ownership, player-scene composition, weapon-pose,
  mobility, grenade release/profile, and complete quick integration regressions
  pass after extraction.
- [x] Standing, crouched, prone, jump, dive, reload, fire, grenade, directional
  locomotion, weapon sockets, and contextual return behavior remain covered by
  deterministic tests.

This removes a major ownership bottleneck without changing the canonical PS1
operator or making animation authoritative over movement, ballistics, or damage.
Animation Studio pose authoring and the multiplayer authority controller have
since been extracted. Gun calibration and map creation remain explicit
large-file refactor targets; this checkpoint does not close those gates.

## Animation Studio pose-authoring refactor checkpoint — 2026-08-24

- [x] The 1,027-line pose-authoring module is now a four-line compatibility
  path. Pointer/joint input (`427` lines), pose-strip authoring (`128`), and
  saved correction overlays (`475`) have separate ownership under the enforced
  500-line ceiling.
- [x] All 48 prior pose-authoring functions remain present exactly once. The
  split does not change the Gunsmith profile schema, correction-key format, or
  runtime animation route.
- [x] The generated cross-layer contract now follows the complete real Studio
  inheritance chain, including Rig & Hands, timeline, and Casting. It resolves
  70 forward dependencies without duplicating the state's intentional hooks.
- [x] The architecture regression now requires every module to parse and be
  instantiable. It no longer reports a false pass when `load()` returns an
  invalid Script resource.
- [x] Project parse, Studio architecture, editor/runtime authoring parity,
  pose-strip, correction-overlay, Rig & Hands UI, state preview, Gunsmith clip
  catalog, operator-animation, player-composition, weapon-rig, and Studio
  navigation regressions pass after extraction.
- [ ] Direct left-elbow pointer isolation remains open. The focused regression
  measures `1.49 cm` of opposite-arm motion and `11.47 cm` of rifle relocation
  after the preceding support-hand edit. This is an existing visual-authoring
  defect; the refactor preserves it rather than hiding it or weakening the test.

The complete quick integration gate and god-file budget pass on `main` after
the split. This checkpoint does not claim that the separate map branch or the
broader architecture-freeze gate is complete.

## Multiplayer authority refactor checkpoint — 2026-08-24

- [x] The former `2,142`-line multiplayer controller is now a `109`-line
  concrete RPC boundary. State (`292` lines), session/lobby (`430`), movement
  replication (`475`), combat (`257`), round lifecycle (`302`), demolition
  objectives (`227`), and world/UI integration (`309`) have separate owners.
- [x] Every authority layer is below the enforced `500`-line ceiling. The
  concrete RPC boundary remains below its `300`-line ceiling.
- [x] The generated cross-layer contract resolves `46` inherited dependencies.
  All `118` original authority methods remain implemented exactly once.
- [x] Godot runtime metadata registers exactly the original `22` RPC methods on
  `SocomMultiplayerSlice`, including their concrete authority and transfer-mode
  annotations. The public scene and class name remain unchanged.
- [x] Source-owner regressions now inspect acoustic replication and shared input
  setup in their new round and world/UI owners instead of the removed monolith.
- [x] A real four-peer ENet probe completed two demolition cycles with three
  combat shots per client and controlled damage. The final sample measured
  `16.385 ms` mean frame time, `20.536 ms` p95, and `109.58 MB` host memory.
- [x] A separate four-peer, two-cycle probe disconnected one client during the
  live round, restored it as a safe spectator, and admitted it to the next full
  round. The final sample measured `14.087 ms` mean frame time and `21.160 ms`
  p95.
- [x] Project parse, multiplayer architecture, demolition/authority behavior,
  acoustic propagation, file budgets, controlled-hit lifecycle, reconnect, and
  the complete quick integration gate pass after extraction.

This proves the local authority split and four-peer lifecycle path. It does not
replace the existing maximum-lobby soak evidence, adverse-network testing,
dedicated-server operations, security review, or external closed-alpha proof.

## Weekly production scorecard

Track only measurable outcomes:

- Match completion rate.
- Crash-free session rate.
- Median and worst-case client frame time.
- Server tick stability and bandwidth per player.
- Join success and reconnect success.
- Severe animation/weapon ownership failures per match.
- Objective deadlocks per match.
- Automated regression pass rate.
- Open blockers by age and owner.
- External-player onboarding completion.

Do not measure progress by number of Labs, scripts, animations, weapons, or
ideas added. Measure whether external players can reliably complete enjoyable
matches.
