# Current-game multiplayer parity pass

## Agreement and budget

User requests the entire current game on owning clients, the authoritative server,
and remote clients, with a $40 Astra Medium budget. This task cannot meter dollars
or change its own model. No assets generated, no agents, no paid services, no public
deployment or branch changes. A passing component test is not full online parity.

## Translation card before edits

- Intent: retain the current local game online, including its responsiveness and presentation.
- Acceptance: same canonical components/data; commands survive a bounded loss/jitter
  test without losing action edges; remote action timing remains continuous; real
  session tests prove admission, movement, combat and lifecycle. Missing feature
  chains remain explicitly incomplete, never counted as passing.
- Owners: existing CharacterBody movement; session replication for delivery;
  existing server combat/grenade owners for gameplay; canonical visual consumers.
- Protected: offline controls/speeds/animations, camera and reticle aim, damage and
  inventory authority, dirty worktree, saved maps and authoring assets.
- Proof: canonical tuning, input-loss regression, proxy animation timing,
  prediction, combo/handoff regressions, real host/client lifecycle, feature gate.

## Plan

1. Inventory input -> authority -> snapshot/event -> client presentation for every
   current feature. Compare direct multiplayer boot with `main.tscn`.
2. Repair bounded command delivery and proxy action timeline first. Keep the
   existing movement owner; do not invent movement on the server from an animation.
3. Audit and connect missing equipment/throwable/action paths with validated
   server ownership. Full prediction replay must include movement action state,
   traversal, timers, and edge history—not just coordinates.
4. Compare shared content and run actual host/client sessions, then repeat with
   injected loss/jitter. Test death/reload/respawn and blocked actions too.
5. Report every remaining gap; promotion requires the canonical main branch and
   a synchronized client/server build. Do not call an undeployed fix live.

## Initial code audit (not completion claims)

| Area | Evidence | Initial status |
| --- | --- | --- |
| Player/camera/tuning | network_operator.tscn inherits operator_player.tscn; replication `_apply_competitive_movement_profile`, `_attach_local_camera` | Baseline canonical comparison passes 197 values |
| Movement delivery | replication `submit_movement` accepts a single unreliable-ordered command; operator returns on empty queue | Lost commands/press edges are not recovered |
| Prediction | prediction_history stores position/posture/offset only | Full action/physics replay missing |
| Remote actions | operator interpolates position but selects one snapshot's action_elapsed | Action seek can visibly step between snapshots |
| Weapon feedback | canonical weapon visual controller has `_process` disabled, but its `_physics_process` remains active | Not a frozen-recoil bug; baseline feedback test passes |
| Reload | multiplayer_rounds plays local semantic reload; server combat owns timer/ammo | Remote reload timeline requires audit/integration |
| Grenades/equipment | main.gd builds MainGrenadeRuntime; no matching grenade command in multiplayer session | Missing full authority/replication chain, not just a skin difference |
| Maps/collision | shared MapRuntime and admission map document | Existing byte-for-byte transport test available; live build not verified |
| Build identity | session_compatibility compares application/config/version | Version string alone does not fingerprint current content |
| Death/respawn | network operator health/alive, respawn_revision and shared death driver | Existing tests available; actual two-client proof required |

System delta: MERGE delivery/timeline repairs into existing owners. KEEP canonical
movement/camera/weapon profiles and physics update. REJECT replacing the game with
a lightweight multiplayer player. Scores current/candidate: correctness 2/4,
ownership 5/5, runtime parity 3/4, editor usability 3/4, performance 4/4,
regression coverage 2/4. Candidate is not 5/5 while full-feature gaps remain.

Official reference: https://docs.godotengine.org/en/stable/tutorials/networking/high_level_multiplayer.html
RPCs require matching declarations on the final network script and both peers;
unreliable-ordered packets can discard late arrivals. Verify on installed 4.7.1.

## Delivered foundation (not full parity)

Movement: `scripts/network/socom_movement_delivery.gd` packs up to 11 previous
commands into 352 bytes. Session `_physics_process` sends:

```gdscript
submit_movement.rpc_id(1, movement_delivery.outgoing(packet, local_operator.received_respawn_revision))
```

`socom_multiplayer_replication.gd:submit_movement` validates the life epoch,
decodes bounded history and queues unseen ticks through the existing body:

```gdscript
if command_tick <= int(last_command_tick.get(sender, -1)): continue
operator.queue_movement_command(NetworkProtocol.packet_to_movement(entry))
```

This preserves short-loss press/release edges, not arbitrary outages. Loss longer
than the history window and long-term server queue pacing remain limitations.
Protocol is now 3, so old peers cannot silently use the old wire behavior.

Remote presentation: `socom_network_operator.gd:update_proxy_interpolation`
interpolates action_elapsed only within matching monotonic action segments.
Bounded extrapolation cannot invent a side get-up; roll_side, action_direction and
combo_recovering now survive projection in `socom_snapshot_encoder.gd`.

Packet size: `socom_network_protocol.gd:chunk_snapshot_entities` additionally
splits by serialized bytes (`SNAPSHOT_ENTITY_BYTE_BUDGET := 1000`). Standard
session sends only each chunk's scores; receiver merges those partial scores.
This removes the observed 1548-byte snapshot above ENet's 1392-byte MTU. A 32-actor
projection test retains explicit envelope/RPC/score headroom.

Slide follow-up: `player_controller.gd:_advance_jump_combo` uses the shared
`slide_move_unlock_seconds` value (0.75). Grounded held movement hands off to
crouch in that tick. No input and an explicit prone exit preserve full playback.
Early exit retains first_bit/armed/tap_age, preserving a new side double-tap.

## Evidence and failures retained

- Canonical local/online tuning: 197 comparisons PASS.
- `network_movement_loss_regression.gd`: 540 ticks, injected jitter/reordering and
  six-packet bursts, zero matching-tick error; input/action/crouch state, bounded
  payload, malformed input, respawn history clearing and remote timing PASS.
- Existing prediction 228 delayed comparisons PASS; component and multiplayer
  slice regressions PASS; existing combo/camera/stance/network regression PASS.
- `mobility_movement_handoff_regression.gd`: headless and corrected rendered
  runs PASS. Render diagnostic: slide exits at elapsed=0.75 with velocity.z=-2.6;
  back exits at 1.65, side exits after recovery. An earlier rendered run disagreed;
  diagnostic rerun passed without a runtime change. Do not hide this transient
  result or claim it proves every visual transition is perfect.
- Actual separate ENet host/client: peers=2, cycles=1, combat_shots=2,
  controlled_hits=1 PASS (admission, movement, shots, reload, elimination, lobby).
  This is loopback, not an internet soak or a 32-player performance certification.
- WebSocket map transport: 82,108 bytes received byte-for-byte PASS.
- Feature gate: 93 graphs PASS, after clean session parse. The first gate emitted
  a session parse error while still printing graph PASS; always pair it with the
  runtime boot/parse check. Cross-layer state belongs in socom_multiplayer_state.gd:
  declaring movement_delivery in a derived layer made session fail to resolve it.
- Controlled damage probe assumed every gun kills in three shots. Current
  round-selected weapon dealt 22; test now permits up to 12 attempts and stops on
  confirmed death. It still requires zero health and unharmed friendly shooters.
- Lifecycle probe expected no actors in WAITING. Current warmup deliberately
  respawns actors there; test now requires the full roster alive at full health.
- Quick integration gate remains blocked on codex/render-deployment; requires
  main. No branch change, commit, asset download or deployment performed.

## Explicit remaining work for "everything"

1. Reuse local grenade/equipment interaction and release cues, but send validated
   requests to a server inventory/throw owner; replicate projectile lifecycle,
   frag damage, flash exposure and smoke. No client-created damaging grenades.
2. Replicate remote reload/equip/throw state and reconcile cancellation/death.
3. Complete authoritative movement-state restoration and replay (including
   traversal, timer/edge state and prediction-safe signals). Positional correction
   alone remains in place in this foundation pass.
4. Fingerprint packaged gameplay/content and prove export parity. Current build
   admission checks version/protocol, not every asset. User/local saved bundles
   and server export must also be compared.
5. Exercise the actual browser/server transport, two rendered remote clients,
   reconnect/late join, packet loss and realistic load for the full feature list.

No claim is made that the entire requested current game works online yet.
