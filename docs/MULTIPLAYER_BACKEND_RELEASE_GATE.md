# Gate Four multiplayer and backend evidence

Status: **not ready for commercial promotion**. The local authoritative match
slice and backend policy are testable. Internet impairment, production hosting,
moderation operations, voice load, disaster recovery, and target-hardware cost
proof remain open. Do not interpret a local pass as the Gate Four exit criterion.

## Implemented and verified

| Requirement | Evidence |
| --- | --- |
| Guest identity | `SocomSupabaseClient` creates and refreshes an anonymous Supabase account, stores the session under `user://`, and creates a unique player handle. No login form is required for a guest. Account upgrade/linking and cross-device recovery remain open. |
| Host, join, invite, lobby, team, ready | The ENet slice accepts direct addresses and checksummed invite codes. The lobby owns team assignment and ready state. The focused regression covers the UI and invite decoder. |
| Map, countdown, spawn, rounds, victory, scoreboard, rematch, leave | The server distributes the selected map, owns the countdown and Demolition rounds, and returns all peers to a cleared lobby. The real lifecycle probe completes this loop. |
| Spectator and reconnect safety | A mid-round arrival or reconnected transient peer receives state as a spectator and gains an operator only after the next lobby. Durable identity, reserved slots, and reconnect-to-the-same-operator remain open. |
| Graceful version rejection | A transport peer receives a server challenge and does not enter the lobby until protocol and complete build match. Invalid and silent peers receive a bounded reason and disconnect. |
| Dedicated server registration | The headless bootstrap opens the authoritative scene. The server backend reads its privileged key only from the process environment, registers build/protocol/region/capacity, sends heartbeats, and supports drain-before-offline state. The pinned Linux production image, Render Blueprint, and real WebSocket handshake are verified locally; authenticated Render rollout and public soak proof remain open. |
| Region and health policy | `service_regions` exposes operational, degraded, maintenance, and offline state. Selection rejects unhealthy regions and stale, full, draining, or incompatible servers. UI latency probes and live status-page integration remain open. |
| Server authority | The server owns movement simulation, stance, ammunition, cadence, shot validation, dispersion, hits, damage, objectives, time, score, and victory. Clients send bounded movement and aim intent. Camera and animation presentation do not cross the authority boundary. Multiplayer grenade authority is not complete. |
| Snapshot and lag bounds | Authoritative snapshots use MTU-safe four-entity chunks, owner reconciliation, and a shared 130 ms remote presentation buffer. Server rewind history is 0.50 seconds and measured transport compensation is capped at 80 ms. Internet latency, jitter, loss, and reordering proof remains open. |
| Abuse and least privilege | Row-level security gives players only self-owned block, mute, report, sanction-read, and appeal access. Evidence, sanctions, health writes, and the append-only audit log are service-only. A private atomic rate-limit function bounds authenticated backend routes. Operational moderation UI, policy review, retention approval, and penetration review remain open. |
| Local supported-lobby load | Sixteen real ENet peers previously completed repeated lifecycle, simultaneous fire/reload, controlled torso damage/elimination, and reconnect probes. The current admission change also passes a fresh two-peer lifecycle probe. Voice, grenades, long duration, remote networks, and target-hardware cost validation remain open. |

## Current local budgets and proof

The supported local engineering lobby is 16 peers. Existing two-cycle evidence
records 160 server-authorized shots, controlled elimination, rematch cleanup,
and approximately 175 MB host memory. These are debug workstation measurements,
not shipping requirements.

The fresh admission lifecycle sample on 2026-08-24 completed one two-peer cycle:

- Host memory: 96.69 MB.
- Mean frame interval: 16.410 ms.
- P95 frame interval: 21.357 ms.
- Crash or correctness failure: none.

Focused checks:

```text
BACKEND_OPERATIONS_REGRESSION PASS
MULTIPLAYER_SLICE_ARCHITECTURE_REGRESSION PASS
MULTIPLAYER_SLICE_REGRESSION PASS
MULTIPLAYER_LIFECYCLE_PROBE PASS peers=2 cycles=1
```

## Production operating contract

Apply both ordered Supabase migrations before enabling discovery. Keep the
publishable client key in `config/supabase.json`. Inject
`SOCOM_SUPABASE_SERVER_KEY` into the dedicated server process only. Never place
that value in a project resource, export preset, log, crash attachment, or client
environment.

The dedicated process also needs:

- `SOCOM_SERVER_PUBLIC_ADDRESS`
- `SOCOM_RULESET_ID`
- `SOCOM_SERVER_REGION`
- `SOCOM_SERVER_NAME`
- `SOCOM_GAME_BUILD` only when it exactly matches the exported game build

Before planned shutdown, set the server to `draining`, stop new admissions,
complete or evacuate the active match, then mark it `offline`. Discovery excludes
draining servers and heartbeats older than 45 seconds.

## Blocking promotion tests

Gate Four remains open until all of the following have reproducible reports and
approved budgets:

1. Run repeated 16-peer soak matches through latency, jitter, packet loss, and
   packet reordering matrices on representative Internet routes.
2. Exercise simultaneous movement, fire, all grenade types, deaths, voice,
   spectators, joins, leaves, and durable reconnects.
3. Set server CPU, memory, ingress, egress, tick-stability, crash, completion,
   and per-match cost budgets on target hosting hardware.
4. Rehearse process restart, region loss, database unavailability, stale
   discovery, ruleset rollback, and result-write retry without duplicating a
   match result.
5. Complete dependency, protocol, row-level-policy, retention/privacy, abuse,
   and basic penetration reviews.
6. Operate report, evidence, sanction, appeal, and audit workflows with named
   owners and response targets.

The exit criterion is met only when the supported 16-player lobby repeatedly
finishes inside those approved latency, bandwidth, crash, cost, and correctness
budgets.
