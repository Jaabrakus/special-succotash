# Server action boundary — first modularization pass

Player intent: the same reload rules on a player host and a dedicated host,
without trusting a client's animation completion to grant ammunition.
Acceptance: reload starts on input; only the server clock can finish it;
repeated start/early completion cannot shorten it; fresh fire cancels it;
death, weapon reset, disconnect and round changes discard stale work.
Owner: SocomReloadAuthority owns reload deadlines. Existing combat owner alone
commits reload ammo. Scene RPC methods forward intent using the actual sender.
Shared saved timing: config/weapons/<id>.json ballistics.reload_duration_seconds
(legacy handling_profile fallback). Component has no camera, animation or transport dependency.
Protected: movement, poses, damage, cadence, match rules, solo reload behavior.
Proof: isolated deadline tests (including 32 simultaneous ledgers), real two-peer
reload RPC regression, existing warm-up/combat and architecture/contract regressions.
No public deployment, push, or replacement of tonight's browser ZIP in this pass.

System delta: MERGE composition into current host, remove duplicate reload and
ammo reset methods from objectives (the per-peer round-loadout implementation wins).
Scores old -> candidate: correctness 1 -> 4, ownership 2 -> 4,
runtime parity 3 -> 4, editor usability 4 -> 4, performance 4 -> 4,
regression coverage 1 -> 4. Evidence: multiplayer_replication submit_reload,
multiplayer_objectives and multiplayer_round_loadout duplicate refill methods,
multiplayer_rounds client completion callback, and new focused proofs.
This does not claim all 15 inheritance layers have become independent modules.

Performance boundary: active reloads check only actor eligibility and an integer
deadline each tick. Weapon JSON is resolved at start and completion, not every
physics frame. Repeated active starts return before loading a profile.

The wire contract changes from completion notification to start/cancel intent;
bump build compatibility. Matched versions are mandatory.
Remote WAN loss/latency and 32-player process load remain a separate deployment
test; 32 deadline entries are not 32 networked players.

Official RPC sender/reliability reference:
https://docs.godotengine.org/en/stable/tutorials/networking/high_level_multiplayer.html

## Verification — 2026-09-05

- PASS: deadline policy, early completion/repeat/replay/cancel/context invalidation,
  and 32 independent deadline entries (not a 32-player load test).
- PASS: real localhost ENet and WebSocket clients: independent shotgun/M60
  clocks, forged presentation completion, repeated start RPCs, movement commands,
  per-peer magazine capacity, fire cancellation, death/reset/disconnect cleanup.
- PASS: reliable ordering: an earlier queued shot drains before the later reload
  starts, rather than silently cancelling that reload.
- PASS: actual headless dedicated host, two WebSocket clients, no host player,
  remote reload input and replicated ammo. The test disables only cloud
  registration before its deferred call; no Supabase service write occurs.
- PASS: existing warm-up test (two-way shooting, pellets, respawn, no practice
  score, live match reset), multiplayer slice regression, architecture and
  43 feature-contract graphs. git diff --check passes.
- Initial architecture test failed its old 165-function count after duplicate
  removal; it now verifies 164 layer functions AND exactly one server reload
  implementation, excluding the base declaration.
- Aggregate integration gate BLOCKED: branch codex/render-deployment, requires
  main. No reset, branch switch, commit, push, public deploy, or browser re-export.

## Runtime excerpt

scripts/network/socom_multiplayer_combat.gd:35:

```gdscript
if not reload_authority.consume_ready(peer_id, context, Time.get_ticks_msec()):
    continue
```

Only after this gate does the combat owner transfer reserve ammo to the
player's own magazine. objectives no longer overrides reload/reset ownership.
Client completion only ends local presentation; submit_reload carries
start/cancel intent. New source build is 0.1.2-server-actions; existing browser
ZIP stays unchanged and cannot join a new-source server because admission
requires matching builds.

Remaining work: broader separation of transport/session/presentation, server
validation of other action timelines, rendered network UX, and staged WAN
latency/loss/32-player load testing. Passing local authority tests does not
establish public deployment readiness or visual parity.
