# Lobby, replication and arena boundary pass

Player intent: preserve playable multiplayer while reducing coupled match code.
Acceptance: ordinary and tournament countdowns share one decision policy;
snapshot encoding is shared; arena roster and deployment plans come from a
bounded component, not duplicated loops in the RPC coordinator.
Owners: LobbyCountdownPolicy decisions; SnapshotEncoder wire packaging;
ArenaRuntimePlan roster/deployment plans. Existing lobby and tournament session
remain their sole state owners. Coordinator applies decisions and sends RPCs.
Protected: movement, damage, poses, recoil/reticle tuning, protocol signatures,
browser ZIP, deployment and existing dirty worktree.
Proof: boundary unit tests, architecture, tournament scope/pods/session,
warm-up connected test, dedicated host and feature-contract gate.

System delta MERGE. Scores current -> candidate: correctness 4->4, ownership
2->4, runtime parity 4->4, editor usability 3->3, performance 4->4, coverage 3->4.
Evidence: multiplayer_session countdown, tournament_runtime countdown/roster/
snapshot/deployment loops, new independent components and focused tests.
This is bounded extraction, not a claim that every inherited adapter is gone.
Internet 32-player testing requires an accessible endpoint and distributed
clients; local simulations cannot prove internet readiness.

## Results

PASS: architecture/RPC compatibility; boundary unit test with 32 domain players
across eight arenas; tournament roster isolation, complete bracket progression,
map pods and sudden death; real localhost ENet warm-up shooting/respawn/live
start; dedicated host with two WebSocket clients; all 45 feature contracts.
The original sudden-death manifest referenced relocated implementation text;
updated it to require the deployment-plan call and eligibility consumer.
Some successful headless tests emit the macOS certificate-store warning.

Integration gate remains blocked by codex/render-deployment versus required
main. No branch switch, push, public deployment or browser ZIP replacement.
This is not a completed 32-client internet load test or full coordinator removal.
Snapshot receiving, RPC dispatch and lifecycle side effects remain adapters.

Runtime excerpts:
`scripts/network/socom_multiplayer_session.gd:324` calls
`LobbyCountdownPolicy.advance(...)` for the ordinary lobby; tournament uses the
same policy at `socom_multiplayer_tournament_runtime.gd:121`.
`scripts/network/socom_multiplayer_combat.gd:379`:
```gdscript
var snapshot := SnapshotEncoder.capture(operators, peer_ids)
```
`scripts/network/socom_multiplayer_tournament_runtime.gd:603`:
```gdscript
for entry: Dictionary in ArenaRuntimePlan.deployment(tournament_session, arena_id):
```

Recoil findings are recorded separately in `docs/ZWEAPON_RECOIL_AUDIT.md`;
no weapon/importer/camera/reticle code was changed in this pass.
