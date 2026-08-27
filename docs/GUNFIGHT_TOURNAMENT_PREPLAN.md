# Gunfight tournament pre-plan — 2v2 competitive, expanding to 8v8

Status: Pre-plan for review (2026-08-27). No code in this document is merged;
every sketch maps onto systems that already exist in this repository.

## 1. Goal

A COD-Gunfight-style competitive mode and tournament infrastructure:

- **Match format:** 2v2, short rounds (~40 s), no mid-round respawn, rotating
  loadouts, first team to N round wins, overtime flag on timeout.
- **Tournament format:** single-elimination brackets of 16 teams (32 players),
  later 32-team brackets; seeded, rated, self-serve.
- **Expansion:** the identical architecture carries 8v8 (16 players per
  match). Only the ruleset document and server sizing change.

Key structural insight: a 32-player tournament is sixteen concurrent 2v2
matches, never 34 players in one simulation. Per-match netcode at 2v2 is
trivial; the engineering work is orchestration and result integrity.

## 2. Open-source survey and what we adopt

| Project | Status (2026) | What it is | Verdict for 141 |
| --- | --- | --- | --- |
| [Agones](https://agones.dev/) | Active (K8s 1.32–1.34 support) | Kubernetes fleet orchestration for dedicated game servers | **Adopt the concepts, not the software.** Its GameServer lifecycle (Scheduled → Ready → Allocated → Released, health ping) becomes our lightweight match-server supervisor. K8s is overkill for ≤32 concurrent small matches. |
| [Open Match](https://open-match.dev/) | Dormant; reference-grade | Google's matchmaking framework (tickets, match functions, director) | **Do not adopt.** Borrow its architecture shape: client match requests are *tickets*; a small director pairs them; match servers report outcomes. |
| [Nakama](https://heroiclabs.com/nakama/) | Very active (Apache 2.0, official Godot SDK) | Full game backend: accounts, matchmaker, tournaments, leaderboards | **Fallback path, not the base.** We already run Supabase with auth. If the custom bracket/matchmaker grows painful, Nakama's tournaments API is the proven off-ramp. Schema ideas below are informed by it. |
| [Bracket](https://github.com/evroon/bracket) (evroon/bracket) | Active, self-hosted | OSS Challonge alternative: single-elim, round-robin, Swiss, stages | **Adopt its data model** (stages, groups, match slots) when designing our tournament tables. Not run as a dependency — the flow must live inside 141's client. |
| [Godot dedicated-server export](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_dedicated_servers.html) | Official Godot feature | Headless server export templates + "export as dedicated server" | **Adopt directly.** Our `scripts/server/socom_server_bootstrap.gd` already routes `--dedicated-server` into the authoritative scene. |

Community Godot FPS multiplayer templates exist but none match our
authority contracts; we keep our own slice.

## 3. Architecture — three planes

```
CONTROL PLANE (Supabase, already integrated)
  accounts ── teams ── tournaments ── bracket slots ── match registry ── results
        ▲                                                        │
        │ join tokens / bracket view                    signed results
        │                                                        ▼
CLIENT PLANE (existing Godot client)                 MATCH PLANE (VPS fleet)
  launcher → lobby → tournament UI ────── join ──► one headless Godot process
  predicts locally, validates nothing            per match (Godot dedicated-server
                                                 export, 20 Hz, full authority)
```

- The **match server is the only gameplay authority** (movement, shots,
  damage, purchases, round flow) — the existing 10-layer slice with
  `dedicated_server_mode = true`.
- **Supabase never simulates**; it stores who plays whom, where, and what
  happened. Realtime subscriptions drive the bracket UI.
- **Results flow server→Supabase only**, HMAC-signed with the server's
  private key (`SOCOM_SUPABASE_SERVER_KEY`, already an established pattern in
  `socom_server_backend.gd`). Clients cannot report outcomes.

## 4. Component design and code sketches

### 4.1 Gunfight ruleset (gameplay document, not new code paths)

The round machine already reads its rules from the map gameplay document
(`SocomMapGameplayContract.round_rules`). Gunfight is a new document mode:

```json
{
  "mode": "gunfight",
  "gameplay": {
    "round_time_seconds": 40,
    "maximum_rounds": 11,
    "rounds_to_win": 6,
    "elimination_wins_round": true,
    "bomb_detonation_wins_round": false,
    "round_timeout_result": "overtime_flag",
    "respawn_enabled": false,
    "overtime_flag_radius_m": 2.0,
    "overtime_hold_seconds": 3.0,
    "loadout_rotation": "catalog_random_pair",
    "buy_menu_enabled": false
  }
}
```

Round-machine extension (new layer `socom_multiplayer_gunfight.gd` between
`buy_phase` and `objectives`, following the chain convention):

```gdscript
extends "res://scripts/network/socom_multiplayer_buy_phase.gd"

## Gunfight ruleset: elimination rounds, overtime flag, rotating loadouts.
## All decisions remain server-side; this layer only interprets round_rules.

func _gunfight_enabled() -> bool:
	return String(mission_rules.get("mode", "demolition")) == "gunfight"


func _server_start_next_round() -> void:
	if _gunfight_enabled():
		_server_apply_round_loadouts()
	super._server_start_next_round()


# Both teams receive the IDENTICAL weapon pair for the round (COD Gunfight
# rule). The pair rotates every round, drawn deterministically from the reCOM
# catalog seeded by (match_id, round_index) so every client can predict it
# while only the server applies it.
func _server_apply_round_loadouts() -> void:
	var seed_value := hash([match_token, round_index])
	var pair := _draw_catalog_pair(seed_value)
	for raw_id: Variant in operators.keys():
		var peer_id := int(raw_id)
		peer_loadout[peer_id] = {"primary": pair[0], "secondary": pair[1]}
		server_equipped_weapon_id[peer_id] = pair[0]
		_reset_ammo_for_peer(peer_id)
		_send_loadout_state.rpc_id(int(raw_id), pair[0], pair[1])


func _advance_round_clock(delta: float) -> void:
	if _gunfight_enabled() and _overtime_active():
		_advance_overtime_flag(delta)
		return
	super._advance_round_clock(delta)


func _server_finish_round(winner_team: int, reason: String) -> void:
	if _gunfight_enabled() and winner_team < 0:
		winner_team = _server_resolve_overtime_flag()  # never draw
	super._server_finish_round(winner_team, reason)
```

Respawn suppression: `_respawn_after_delay` and mid-round respawn paths
check `respawn_enabled` and skip. Eliminated 2v2 players become the
existing safe spectators until the next round.

### 4.2 Match server lifecycle

Export (one-time, scripted):

```bash
godot --headless --export-release "Linux Dedicated Server" build/match_server
# Preset: Linux, "export as dedicated server" enabled; same project.
```

Boot contract (extends the existing bootstrap):

```bash
./match_server --dedicated-server --headless \
  --match-id=mt_01J9... --match-token=<hmac_secret> \
  --supabase-url=https://... --port=14141 --max-players=4
```

```gdscript
# scripts/server/socom_match_server_reporter.gd (new, server-only)
## Reports lifecycle and results to the control plane. Runs only when
## dedicated_server_mode is true; the client never loads this path.

const REPORT_URL := "/functions/v1/match-report"  # Supabase Edge Function


func report_match_result(result: Dictionary) -> void:
	var payload := {
		"match_id": match_id,
		"ruleset_hash": _ruleset_hash(),
		"winner_team": int(result.get("winner_team", -1)),
		"rounds": result.get("round_log", []),
		"ended_at_unix": Time.get_unix_time_from_system(),
	}
	var body := JSON.stringify(payload)
	var signature := _hmac_hex(match_token, body)  # HMACContext, Godot core
	# POST body + X-141-Signature header; Edge Function verifies before
	# touching the bracket. Idempotent on match_id — retries are safe.
	_http_post(REPORT_URL, body, {"X-141-Signature": signature})
```

The round log comes from the event-log design in the 8v8 discussion: the
server stamps every round result with tick + reason, so the report is an
audit artifact, not a claim.

### 4.3 Match-server supervisor (Agones concepts, ~200 lines)

A small Python/Go supervisor per VPS box — no Kubernetes:

```python
# supervisor.py (sketch)
# States mirror Agones: READY -> ALLOCATED -> RELEASED
#   READY      process up, registered in Supabase, waiting for peers
#   ALLOCATED  bracket assigned, players joining/playing
#   RELEASED   result reported, process reaped
while True:
    for request in db.pending_allocations():     # control plane asks
        proc = pool.acquire_ready(port=request.port)
        db.allocate(proc.id, request.match_id)   # returns addr:port+token
    for proc in pool.timed_out_health():
        db.mark_failed(proc.id); pool.reap(proc)
    time.sleep(1)
```

Health = process heartbeat row updated every 5 s. At 16 concurrent 2v2
matches a single 2 vCPU / 2 GB VPS is comfortably oversized (each match:
2 peers × 20 Hz snapshots ≈ tens of kbps; the 16-peer local soak already
measured ~15.7 ms mean frame time with 16 animated operators).

### 4.4 Control-plane schema (Supabase/Postgres)

```sql
create table teams (
  id uuid primary key default gen_random_uuid(),
  name text unique not null,
  captain uuid references auth.users not null,
  created_at timestamptz default now()
);
create table team_members (
  team_id uuid references teams not null,
  player uuid references auth.users not null,
  primary key (team_id, player)
);
create table tournaments (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  format text not null default 'single_elim',
  team_size int not null default 2,
  max_teams int not null default 16,
  ruleset_hash text not null,          -- from network timing doc policy
  state text not null default 'registration',  -- registration|running|done
  created_at timestamptz default now()
);
create table tournament_entries (
  tournament_id uuid references tournaments not null,
  team_id uuid references teams not null,
  seed int,
  checked_in boolean default false,
  primary key (tournament_id, team_id)
);
create table matches (              -- bracket slots, informed by Bracket's model
  id uuid primary key default gen_random_uuid(),
  tournament_id uuid references tournaments not null,
  bracket_round int not null,       -- 0 = first round
  slot int not null,                -- position within the round
  team_a uuid references teams, team_b uuid references teams,
  winner uuid references teams,
  server_addr text, join_token text,           -- written by supervisor alloc
  state text not null default 'pending',       -- pending|ready|live|reported
  unique (tournament_id, bracket_round, slot)
);
create table match_results (
  match_id uuid primary key references matches not null,
  winner_team int not null,        -- 0 = team_a, 1 = team_b (server numbering)
  round_log jsonb not null,
  signature text not null,         -- HMAC verified by Edge Function
  reported_at timestamptz default now()
);
create table ratings (              -- start Elo; TrueSkill later
  team_id uuid primary key references teams not null,
  rating int not null default 1200,
  games int not null default 0
);
```

Row-level security: players read brackets/matches; only the service role
(the match server key + Edge Functions) writes results and allocations.
This is the same trust boundary the project already draws for backend ops.

### 4.5 Match flow (the whole tournament, end to end)

```
register → check-in closes → bracket generated (seeded by ratings)
  → for each bracket round:
      control plane requests allocations for pending matches
      supervisor: READY server → ALLOCATED, writes server_addr + join_token
      both teams' clients poll their match row (realtime) → JOIN button
      client launches join with token (server validates token before admission
      — extends the existing session-compatibility challenge)
      match plays; server reports signed result
      Edge Function verifies signature → writes match_results
      → both slots of the next round filled; loser bracket side updated
  → final → tournament state done → ratings updated (Elo delta by team)
```

Bracket generation is a pure function over `tournament_entries` — seeded
single-elim pairing with byes, ~80 lines of SQL/plpgsql or an Edge Function;
the [Bracket](https://github.com/evroon/bracket) project's stage/match model
is the reference.

### 4.6 Client additions (small)

- Tournament browser + team management screens in the launcher (existing
  panel recipe; Supabase auth already loaded).
- "JOIN MATCH" already exists — it gains a token parameter.
- Spectator/observer slot reuses the safe-spectator reconnect path
  (phase 4; not required for the first tournament).

## 5. Phases and gates

| Phase | Deliverable | Gate |
| --- | --- | --- |
| P0 | Gunfight ruleset in the listen-server slice + one tiny 2v2 test map | Regression: no respawn, overtime flag resolves, loadout rotation deterministic; both families' weapons hold correctly |
| P1 | Dedicated-server export + signed result report to a staging Supabase | Two-client match produces a verified `match_results` row; client cannot forge a report |
| P2 | Supervisor + allocation flow on one VPS | Bracket slot goes pending → ready → live → reported with zero manual SSH |
| P3 | Bracket MVP: registration, generation, advancement, Elo | A full 8-team (16-player) bracket completes end-to-end |
| P4 | 16-team brackets, observers, TrueSkill (replace Elo) | Steam closed-alpha tournament event |
| P5 | 8v8 expansion | Same pipeline, 16-player matches, lobby-size soak re-run against the dedicated fleet |

P0–P1 are pure game code inside this repository and unblock everything else.
P2–P3 are conventional backend work (the user's home turf).

## 6. Risks and mitigations

- **Dedicated server still builds client UI** (known architecture finding) —
  must be fixed in P1 or the headless export carries dead weight and the
  AcousticPropagation autoload spins up audio. Small, contained, already
  scoped in the audit.
- **Supabase as control plane** — fine at tournament scale (hundreds of
  rows, not thousands of writes/s). If realtime or scheduling hurts,
  Nakama is the off-ramp; the schema above translates.
- **Result disputes** — the signed round log is the evidence; keep the raw
  event log for the match duration for review.
- **Clock/security** — join tokens are single-match, single-use, short-TTL;
  the existing admission timeout and compatibility challenge extend to them.
- **Region latency** — publish per-region server boxes and the ruleset hash
  (from `network_interpolation_and_shot_timing.md`) so every tournament
  match runs the identical timing model.

## 7. Decisions needed before P0

1. Buy menu in Gunfight, or pure catalog rotation (COD-identical)? The
   ruleset flag supports both; SOCOM's armory is a differentiator for a
   "SOCOM classic" bracket alongside pure Gunfight.
2. Elo first, TrueSkill later — acceptable starting point?
3. First VPS region (player base location) for P2.
4. Team size strictly 2 for launch (recommended: 32 divides cleanly),
   8v8 as the P5 expansion?
