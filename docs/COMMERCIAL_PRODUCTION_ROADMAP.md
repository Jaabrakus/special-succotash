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
   bots so one workstation does not create 256 animation rigs. Long-duration,
   reconnect, packet-loss, and simultaneous-fire soak remain open.
7. Profile startup and a maximum-player firefight.
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

This is a technical baseline, not a commercial-release claim. Legal clearance,
external playtesting, multiplayer soak, production content, accessibility,
platform packaging, and operations remain open gates.

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
