# Source trajectory integration seam

## Translation card — 2026-09-12, read-only preparation

- Player intent: use decoded original shot behavior in the playable game,
  rather than mistake source-looking scalars or tracer motion for that behavior.
- Acceptance: identify the actual local/server owners, the smallest shared
  policy seam and its required evidence; run existing focused checks without
  changing runtime behavior. Original dispatch, units and update equations must
  be verified before activating a source policy.
- Owner: this offline audit document. A future implementation remains owned by
  `SocomWeaponBallistics`, called by the existing authoritative weapon adapters.
- Must not change: CharacterBody3D movement/collision, camera/reticle aim intent,
  server damage authority, current tuning, grenade ownership, scenes, profiles,
  branches, deployed builds and the user's running game.
- Proof: current code excerpts, headless baseline regressions and a source-
  matched fixture plan. This document is not an implemented trajectory feature.

The explicit user workspace `/Users/kiwimango/socom-141-camera-lab` takes
precedence over the older path in the workflow skill. Installed engine observed
by the checks: Godot `4.7.1.stable.official.a13da4feb`.

## Existing owner chain

| Stage | Exact current location | Responsibility |
| --- | --- | --- |
| Main scene | `main.tscn`, `scenes/player/operator_player.tscn` | Main instantiates the canonical CharacterBody3D and separate camera rig |
| Main wiring | `scripts/runtime/main_weapon_runtime.gd:29` | Creates `WeaponController`, configures player/camera, connects `authoritative_shot` |
| Aim packet | `scripts/camera/camera_aim_resolver.gd:142` | Shared target to sequenced yaw/pitch/direction, stable report anchor and convergence distance |
| Local authority adapter | `scripts/weapons/socom_weapon_controller.gd:367` | Fire locks, ammo, intent and muzzle validation, shot query, local training damage |
| Server packet intake | `scripts/network/socom_multiplayer_replication.gd:84` | Server-only intake using RPC sender; bounded command queue |
| Server processing | `scripts/network/socom_multiplayer_combat.gd:120` | Validation, server muzzle, seed, shared ballistics, ammo, rewound classification, damage |
| Shared shot owner | `scripts/weapons/weapon_ballistics.gd:210` | Cadence/bloom update, seeded direction generation, synchronous projectile trace |
| Hit/material queries | `scripts/combat/socom_bullet_penetration.gd:65` | Bounded rays and material/thickness response; no health writes |
| Server health writer | `scripts/network/socom_network_operator.gd:451` | Rejects non-server/dead receiver; applies region damage and elimination |
| Presentation consumers | `scripts/runtime/main_weapon_runtime.gd:68`, `scripts/network/socom_shot_presentation.gd:13` | Effects for authorized results; not hit decisions |

The server owns one child `ServerBallistics_<peer>` per actor, constructed at
`socom_multiplayer_replication.gd:217`. The multiplayer local presentation
controller is input-disabled; prediction deliberately performs no collision,
ammo or health operation (`socom_multiplayer_combat.gd:78`).

## Current result is immediate, not a flight simulation

At `scripts/weapons/weapon_ballistics.gd:235`:

```gdscript
var direction := (ray_basis * (Vector3.FORWARD + offset)).normalized()
var projectile := _trace_projectile(muzzle_pos, direction, space_state, exclude_rids)
projectile["damage"] = (pellet_damage if count > 1 else damage_per_shot) * damage_multiplier_at(muzzle_pos.distance_to(projectile.hit_pos))
```

`_trace_projectile` at line 290 queries the entire `max_range` immediately.
Velocity contributes only `distance / muzzle_velocity_mps` to visual
`tracer_travel_seconds` at line 360. There is no firearm position/velocity state
advanced over later ticks. Current spread uses a seeded disk sample; source
spread, gravity, drag, penetration and damage equivalence are not implied.

At `scripts/network/socom_multiplayer_combat.gd:199` the server begins rewind,
calls `ballistics.try_fire_direction`, classifies all returned pellets, restores
the transforms at line 247, and writes damage at line 254. Both local and server
adapters assume the result already contains terminal `hit_pos`, `hit_collider`,
`direction`, `damage`, `normal` and `projectiles`.

## Minimal seam once decoder evidence is available

### If original direct fire is immediate

Keep the existing synchronous result shape and authority flow. A pure typed
GDScript policy under the shared ballistics owner can supply the verified trace
equation/dispatch through `_trace_projectile`; do not duplicate camera or damage
logic. If source decoding changes direction sampling, that change belongs just
before `_trace_projectile`, not inside tracer presentation. Keep source versus
current-tuned policy explicit. Add source input/output golden vectors before
changing a saved default.

### If original fire is temporal or uses distinct direct/indirect dispatch

It is not safe to return an instantaneous hit and merely delay its effect.
Separate accepted launch from terminal impact under the same shot owner:

1. Validate and consume one shot/ammo unit at launch. Snapshot the normalized
   weapon policy, muzzle, seeded directions, shooter/round/respawn identity,
   source reference and server tick once; later weapon swaps cannot mutate it.
2. Keep a bounded active-shot collection under the authoritative owner, not
   physics bodies that decide their own damage. An explicitly stepped shared
   pure policy computes the verified source update. Queries test each traveled
   segment against the authority's world. Do not add guessed gravity or drag.
3. Drive that step exactly once from the existing physics loop. Server seam:
   `socom_multiplayer_session.gd:18`/line 46; training seam:
   `socom_weapon_controller.gd:274`. Existing cooldown/bloom `_process` at
   `weapon_ballistics.gd:80` is an idle/render callback and is not a suitable
   new projectile clock. Local fire intake currently runs from `_process` at
   controller line 318, so temporal launches must be queued for the physics
   consumer rather than advancing a projectile there.
4. Apply damage through the existing adapters only at accepted collision.
   Revalidate receiver lifetime, team/arena eligibility and respawn epoch.
   Do not keep unvalidated collider references across frames. Cap lifetime,
   distance, active shots and per-tick query work; define round/reset/disconnect
   cleanup beside existing `socom_multiplayer_replication.gd:293`.
5. Publish separate launch/impact IDs if needed. Existing shot-effect receipt
   deduplicates by shot sequence; an impact must not be discarded as the same
   already-presented launch, nor replay recoil/audio. Client presentation never
   sends or decides impact damage.

These are integration requirements, not recovered SOCOM algorithms. Fixed-step
policy math with the same seed/input can be reproducible; Godot world physics is
not guaranteed cross-machine deterministic. Keep the server collision result
authoritative. See the official [physics callback and determinism notes](https://docs.godotengine.org/en/stable/tutorials/physics/physics_introduction.html)
and [direct-space ray query result contract](https://docs.godotengine.org/en/stable/classes/class_physicsdirectspacestate3d.html).

## Shared saved contract, without an extra tuning owner

Authored weapon data remains `config/weapons/<weapon>.json`, written by
`scripts/labs/gunsmith/gunsmith_weapon_profile_repository.gd:25` and normalized
by `scripts/weapons/weapon_rig_contract.gd:58`/ballistics section at line 213.
The repository preserves unknown `ballistics` keys at line 41; preservation
alone is not semantic validation or runtime integration.

Use one validated policy selector/reference within that shared contract, with
legacy behavior retained when absent. Source policy IDs must resolve only to
verified project-owned definitions; reject unknown/non-finite/unbounded inputs.
Store source disc/build/routine identity, evidence hash and any proven unit/
timestep conversion alongside the definition. Never infer a temporal policy
from a nonzero velocity field. Normalize once on equip/round setup, not per tick.

Training currently calls `ballistics.configure_projectiles(values)` at
`socom_weapon_controller.gd:187`; server does so at
`socom_multiplayer_rounds.gd:243`. This is the common configuration seam. The
server loads/caches its own weapon config (`socom_multiplayer_round_loadout.gd:88`)
and never accepts a client-supplied trajectory definition. A future feature must
name both readers and its saved profile in `config/feature_contracts/` and pass
the feature gate; this audit intentionally adds no pretend implemented contract.

## Rewind constraints that matter for integration

Current bounds: `MAX_TRANSPORT_COMPENSATION_MS = 80`, history one second, remote
render delay `0.130s` (`socom_multiplayer_state.gd:53`). The combat call includes
both transit and render delay. The current restoration scope must never span
an `await` or leave actors displaced between simulation ticks.

`socom_multiplayer_replication.gd:396` records position, yaw and posture, but the
interpolated history result at line 428 returns position/yaw only. Rewind at
line 485 applies position/yaw, then forces the **current** hurtbox pose update.
It does not restore historical animation bones or posture. Thus the existing
code is not full historical skeletal rewind, despite the broad comment in
the combat caller. Current tests verify root-position restoration, not bone
history fidelity.

For temporal fire, explicitly decide and test the launch compensation/catch-up
timeline from source evidence plus multiplayer fairness requirements. Do not
reapply the whole RTT/render delay on every projectile step or freeze the target
at launch pose for its entire flight. A bounded catch-up cannot rely on a history
older than the retained window. Client `simulation_tick` is not authoritative
server time: server validation currently passes `-1` at combat line 151, so
its tick-age check is skipped. Existing measured server transport must not be
silently replaced with the untrusted client timestamp.

## Source evidence currently available

`art_source/socom2_ballistics_reference_20260912/weapon_reader_full.json` contains
86 weapon/gear and 39 ammo records, full node coverage and 105 explicit tags.
Source `RUN/ZWEAPON.ZAR` SHA-256:
`496d80a9dbb12e288465fe2ee45744cc53a3450fa97bf912cfc98c5c54c74372`.
Decoded reader SHA-256:
`8f1027edc1e3d0d6a936e13f3bcc2f2ee785148d1acbe550776e3b844058d67b`.
Report SHA-256 observed during this pass:
`13bfadb2417ebb98e877b35fd3dcae205caa61bf4c8201ee293ad108574678dc`.

This is data evidence, not verified executable equations. The report explicitly
marks direct-versus-flyout dispatch, unit meaning, timestep and integration as
not recovered. Its community `SetProjectile` reconstruction is not an original
SOCOM II disassembly match. Parent/decoder work may add stronger evidence; use
that new output before promotion rather than guessing from these names.

## System delta decision

KEEP current runtime pending verified equations; MERGE this evidence and focused
test plan. Scores, 0–5:

| Criterion | Current path | Unverified generic temporal replacement |
| --- | ---: | ---: |
| Correctness against requested source | 2 | 0 |
| Ownership clarity | 5 | 3 |
| Canonical runtime parity | 5 | 0 |
| Editor usability | 4 | 1 |
| Performance | 4 | 1 |
| Regression coverage | 3 | 0 |

Current evidence is the owner table and executed checks below. The hypothetical
replacement has no recovered dispatch, saved consumer or fixture, hence cannot
outscore the working path yet. Score a verified candidate again when it exists;
this decision does not defend current equations as original behavior.

## Focused acceptance plan and reusable tests

- Decoder fixture: original build/routine identity plus source input/output
  vectors for dispatch, range end, acceleration/gravity when applicable, direct
  and indirect cases; recover units and timestep rather than assume animation Hz.
- Shared policy fixture: same input/seed/step sequence gives same result; invalid
  fields fail closed; renderer frame-rate does not drive flight. Source and
  current tuning remain named and separable.
- Collision fixture: near cover, thin obstruction, start-inside, segment crossing,
  max range, shooter exclusion and moved target. Temporal path needs health
  unchanged before arrival and exactly one impact after arrival.
- Multi-pellet fixture: independent deterministic paths, one ammo unit per shell,
  one launch recoil event; preserve user eight-pellet tuning until explicitly
  replacing it with a separately verified source policy.
- Authority fixture: replay/flood/invalid intent rejected, no client damage,
  restoration on failure, no delayed damage to a respawned/new-round actor,
  no twice-applied transport compensation.
- Main proof: adapt `tools/bloom_shot_envelope_regression.gd:140` for saved policy
  consumption by `main.tscn` with rifle, pistol and shotgun, then a moving target.
  `tools/ballistic_convergence_regression.gd:12` is a main aim/target fixture but
  has map-specific initial target assumptions; do not call it source trajectory
  proof without new golden checks.
- Existing reusable server fixtures: `tools/muzzle_obstruction_regression.gd:15`,
  `tools/network_shot_feedback_regression.gd:20`,
  `tools/multiplayer_slice_regression.gd:329` (root rewind/restore).

### Baseline execution in this pass

- PASS `tools/muzzle_obstruction_regression.gd`: fourteen checks including
  obstruction, rejected ammo/damage effects, replay and accepted server damage.
- PASS `tools/network_shot_feedback_regression.gd`: prediction presentation only,
  authoritative impacts, no duplicate acknowledgement recoil/audio.
- PASS `tools/bloom_shot_envelope_regression.gd`: 45 profiles and 21,978 sampled
  directions; shared local/server cap and the real `main.tscn` rifle/pistol/
  shotgun firing checks. This remains a bloom/aim-envelope proof, not proof of
  original trajectory equations. Exit also reported seven ObjectDB leaks and
  two resources still in use; keep these teardown diagnostics separate from
  the passing behavioral assertions.
- FAIL `tools/multiplayer_slice_regression.gd:281`: `team 1 spawn side is
  invalid`, the single failed assertion in the run. The root history rewind/
  restore assertions passed, but the aggregate run is not clean. A headless
  dummy-renderer null-material warning also appeared. No map was changed or
  spawn failure repaired by this trajectory audit.
- FAIL `tools/shotgun_projectile_regression.gd:61`: expects `60 / 29 RPM` while
  saved `config/weapons/m82a1a.json` contains `28.57142986894471 RPM`. Actual
  server formula at `socom_multiplayer_rounds.gd:245` uses `60 / saved RPM`
  (about 2.1s), not the assertion's roughly 2.069s. All other assertions in that
  run passed. Do not change weapon cadence merely to satisfy the stale constant.

Logs use `/private/tmp/source-trajectory-audit-<script_basename>.log`.
The headless runs also emit the environment's known macOS certificate warning;
it is separate from gameplay assertions. No profile, runtime or source asset was
changed by this audit. No new trajectory feature or original-game parity is
claimed.
