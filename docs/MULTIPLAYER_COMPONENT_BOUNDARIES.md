# Multiplayer component boundaries

Player intent: maintainable multiplayer that can evolve toward dedicated hosts
without changes to movement feel, weapon balance, or match rules.
Acceptance: transport creation, round-policy decisions, combat input ordering,
and shot presentation live in components that do not inherit the match scene
or receive it as an unrestricted service locator. Canonical adapters consume
their outputs; old duplicate logic/state is removed.
Owners: TransportFactory creates connection candidates; SceneMultiplayer remains
the sole installed transport owner. RoundPolicy decides timer/finish outcomes;
match coordinator applies transitions. CombatCommandQueue owns pending shots,
sequence and deferred reload intent. ShotPresentation owns effects only.
Protected: network RPC names/authority, movement/collision, camera, damage,
profile values, arena isolation, reload authority, browser ZIP and deployment.
Proof: component contract/unit tests, architecture tests, connected reload and
warm-up regressions, local dedicated-host proof, existing multiplayer tests.

MERGE composition at four boundaries; retain RPC scene orchestration and
incrementally reduce its inherited responsibilities. No claim that every
remaining session/lobby/arena subsystem is fully decoupled.
Scores current -> candidate: correctness 4 -> 4, ownership 2 -> 4,
runtime parity 4 -> 4, editor usability 3 -> 4, performance 4 -> 4,
regression coverage 3 -> 4. Evidence: multiplayer_session connection creation,
multiplayer_rounds clock/finish/effects, multiplayer_combat input dictionaries,
and new component tests. A behavior-preserving refactor is the objective.

Contracts remain config/network/browser_multiarena_deployment.json (resolved by the existing
DeploymentProfile), saved map round rules, and config/weapons weapon effects.
Exceptions: dedicated servers no longer create tracer/impact effects; this is
presentation-only work with no player viewer and no damage authority effect.

## Verification, 2026-09-05

PASS: component unit checks; multiplayer slice; architecture (36 RPC methods,
one reload entry); real localhost ENet and WebSocket reload/action ordering;
dedicated host with two WebSocket clients; warm-up damage/respawn/live transition;
acoustic propagation; tournament sudden death; all 44 feature contracts.
Rendered presentation check PASS (154 tracer pixels), image inspected at
`/private/tmp/socom-shot-component.png`. Initial capture missed the short-lived
tracer. Test uses existing persistent trajectory-debug mode to avoid first-frame
render latency, then disables it. Gameplay lifetime is unchanged.
`git diff --check` passes. Some headless runs report the macOS certificate-store
warning despite passing their assertions.

Integration gate BLOCKED: branch is codex/render-deployment, but gate requires
main. No branch switch, commit, push, deployment or browser export performed.
Real internet/32-player load testing remains unverified.

## Exact runtime interfaces

`scripts/network/socom_multiplayer_session.gd`, `_create_server_transport`:
```gdscript
var candidate := TransportFactory.host(transport, port, MAX_PLAYERS)
```
`scripts/network/socom_multiplayer_rounds.gd`, `_server_finish_round`:
```gdscript
var match_complete := RoundPolicy.match_complete(winner_team, team_round_wins, round_index, round_rules)
```
`scripts/network/socom_multiplayer_combat.gd`, `_advance_pending_server_shots`:
```gdscript
var packet: Dictionary = combat_commands.pop_ready(peer_id, ready)
```
`scripts/network/socom_multiplayer_session.gd`, `_ready`:
```gdscript
shot_presentation = ShotPresentation.new()
shot_presentation.name = "ShotPresentation"
add_child(shot_presentation)
```

Still not completely modular: the inherited coordinator retains session,
lobby, replication, objective and arena orchestration. Existing tracer/audio
pools remain static shared helpers, not isolated per-session effect engines.
These four extractions do not establish production-scale performance or prove
all presentation parity. No movement/pose/weapon-profile changes in this pass.
