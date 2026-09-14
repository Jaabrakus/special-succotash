# Source-only firearm collision adapter

## Translation card — 2026-09-13

- Intent: source-linked bullets obey verified material/range continuation,
  rather than invented thickness-dependent HP multipliers.
- Acceptance: unknown/malformed solids stop; explicit thin materials continue
  under the original range equation; all contacts use strict original-origin
  distance; overlapping hurtboxes cannot damage one receiver twice per bullet.
- Owner: existing authoritative ballistics caller. New `SourceFirearmTrace` is
  a stateless query/value helper, not a node or independent damage owner.
- Protected: current live processes, source assets, maps, branch, camera/aim,
  CharacterBody movement, animations, damage methods and networking.
- Proof: new real-physics `tools/source_firearm_trace_regression.gd`; original
  scalar equation/getter fixtures; root-owned main/server integration gate.

System delta MERGE: current dual-ray guessing / new source-only helper scores
correctness1/4, ownership5/5, runtimeparity5/2 until root wiring, editorusability1/2
until saved tags propagate, performance4/4, regressioncoverage2/4. Evidence:
`socom_bullet_penetration.gd`, `SOURCE_MATERIAL_PENETRATION_AUDIT.md`, new helper
and focused physics proof. No existing runtime file is edited by this subtask.
Root owns the shared source policy, canonical caller integration and feature
contract. An unwired helper is not a completed gameplay feature.

The user's explicit project root overrides the workflow skill's older alias.
Installed engine: `4.7.1.stable.official.a13da4feb`.

## API and deliberate adapter boundaries

`SourceFirearmTrace.trace(space, origin, direction, maxrange, piercing, exclude,
materials) -> Array[Dictionary]` performs queries only. No health writes/signals.
`materials` is the trusted shared name→P dictionary supplied by the caller.
Only explicit `source_material` collider metadata selects an exact original name
(case/outer whitespace normalized). Unsupported names/types/coefficients use
UNKNOWN=P0; UNKNOWN cannot be overridden with a permissive coefficient.
Anatomical hurtbox methods identify PERSON and the existing damage receiver.

Each result includes entry_pos, exit_pos (same point, no invented back face),
normal, collider, rid, receiver, is_target, source_material, coefficient,
range_limit (before contact), range_after, distance_squared, and continues.
P=1 candidates are excluded and skipped without an impact, matching the source
ordinary candidate branch. Other impacts are published before their continuation
test, matching the source's separate impact and post-impact range reduction.

Queries retain one fixed global origin and the original 1.1× search endpoint.
Contacts must have `0 < distance² < current_range²`, face the query direction,
and progress strictly past the prior contact. Range reduction preserves finite
float32 operation order. No thickness measurement or penetration HP factor.

Geometry is deliberately **not** a 1:1 original collision engine: Godot returns
the nearest contact; the helper excludes a processed collider RID and queries
again. Therefore a compound/multi-material collider must not be labelled as one
uniform thin surface. Author separate colliders or provide a later verified
per-shape adapter. Excluding a collider skips its exit/back face; original
triangle/contact ordering and ricochet are not reproduced by this helper.

One physical bullet records at most one target impact per valid receiver. Its
remaining known hurtboxes and receiver body RID are excluded without another
range reduction. This project safety rule is explicit, not a claimed original
anatomical contact-order reconstruction. Receiver descendant scanning is bounded
to 512 nodes; exceeding it stops continuation. A 128-query bound prevents
unbounded processing and is **not** the original game's penetration count.

`hit_from_inside=true` detects solid origin overlap; a zero-distance contact
stops with no impact. Inputs with nonfinite coordinates/range/piercing, negative
range/piercing or zero direction return no impacts. Origin `(0,0,0)` is valid.

Official API contracts consulted:

- [PhysicsDirectSpaceState3D.intersect_ray](https://docs.godotengine.org/en/stable/classes/class_physicsdirectspacestate3d.html#class-physicsdirectspacestate3d-method-intersect-ray): impact fields and inside-hit normal.
- [PhysicsRayQueryParameters3D](https://docs.godotengine.org/en/stable/classes/class_physicsrayqueryparameters3d.html): explicit area/body flags, RID exclusions, fixed world-space endpoints, and inside-hit behavior.

The online stable API reference may move; installed-engine regression determines
actual 4.7.1 behavior here. No live game/browser is restarted for this proof.

## Canonical collision-ownership delta

Initial focused proof passed 87 checks. Reviewing the canonical network actor
then showed its movement capsule also participates in ray queries. The existing
`SocomAnatomicalHitResolver.trace` skips that broad damage-receiver body so the
animated hurtboxes determine anatomy. Without that same body-only exclusion,
the new helper could stop at the capsule as UNKNOWN before reaching a hurtbox.

MERGE that existing ownership distinction, not the old arm→core heuristic:
physics bodies with `take_bullet_damage_region` but no `get_hit_region` are
excluded without material impact or range cost. No collision shape/layer is
changed. Add a real CharacterBody fixture enclosing hurtboxes and a plain
unclassified body that must remain blocking. Correctness improves 4→4.5;
ownership/performance remain 5/4. The earlier guessed dummy source filename was
absent during inspection; it was a lookup miss, not a runtime/parser failure.

## Historical verification and concurrent merge stop

- Helper parse: PASS, `/private/tmp/source-firearm-trace-parse.log`.
- Focused script parse: PASS, `/private/tmp/source-firearm-trace-test-parse.log`.
- v1 isolated real-physics run: PASS 87 checks, no assertion/runtime error in
  the trace path; existing macOS CA-certificate warning only.
  `/private/tmp/source-firearm-trace-regression-v1.log`.
- v2, with movement capsule cases: all 91 trace assertions PASS, **but not a
  clean project boot**. Concurrent merge conflict marker in
  `scripts/network/socom_supabase_client.gd:99` caused the SupabaseClient autoload
  to fail. `/private/tmp/source-firearm-trace-regression-v2.log`.
- Both test processes exited. No user's game, display session or browser was
  restarted. On root's report of widespread concurrent unresolved merge
  conflicts, gameplay edits/testing stopped; those conflicts were not resolved
  by this subtask. This was a historical stop; the merge owner subsequently
  resolved the conflicts, and the clean post-merge results are recorded below.

Read-only integration observation immediately before that stop: the root's
`weapon_ballistics.gd:_trace_source_projectile` called this helper and created
one `damage_impacts` record per target. Local controller iterated those records;
server flattened them while retaining the first solid visual. This structure
avoids applying both the top-level projectile and its same first contact. Its
then-present first-target `AnatomicalHitResolver` refinement remained a project
arm/core arbitration rule, not recovered original contact ordering. The merge
was changing those files concurrently; this is not a tested final snapshot.

## Post-merge canonical material proof — 2026-09-13

The external merge was resolved at reported HEAD `5340bb8b`; the dirty worktree
and branch were preserved. The helper is now wired into production ballistics,
not just an isolated fixture. Its call remains:

```gdscript
var traces := SourceTrace.trace(space, muzzle, direction, max_range, combat.piercing, excludes, source_materials)
```

Location: `scripts/weapons/weapon_ballistics.gd::_trace_source_projectile`.
Existing local/server adapters consume `damage_impacts`; neither the trace nor
the test writes receiver health. The local application is explicitly:

```gdscript
for impact: Dictionary in projectile.damage_impacts:
    var damage_result := _apply_projectile_damage(impact.hit_collider, impact, 1.0, muzzle)
```

Location: `scripts/weapons/socom_weapon_controller.gd::request_fire`.

The bounded proof/contract translation card and six-axis system delta precede
the test edit in `config/feature_contracts/source_firearm_materials.json`.
New runtime evidence triggered a second MERGE by the runtime owner, recorded
in `docs/SOURCE_COMBAT_PARITY_20260913.md`: ordinary primitive map bodies had
their own id/type-only metadata handoff and lost `properties.source_material`.

The first actual main run failed correctly: WOOD_THIN became UNKNOWN, both
targets stayed at 100, while imported box/detailed-mesh propagation passed.
`/private/tmp/source-firearm-main-materials-v1.json` preserves that failure.
The test also used `get_meta(..., null)` for deliberately absent tags, producing
Godot diagnostics; it now checks `has_meta` before reading an absent value.
No damage assertion was relaxed. Root fixed the canonical primitive handoff:

```gdscript
Geometry._set_object_meta(body, object)
```

Location: `scripts/maps/socom_map_runtime.gd::build_object`. This delegates to
the existing `scripts/maps/socom_map_geometry.gd::_set_object_meta`, while
`scripts/maps/socom_imported_map_asset_builder.gd::build` propagates the same
explicit uniform tag to its actual imported collision bodies.

Clean post-fix checks:

- Main: PASS **1,060 checks**, 33 local/server profile mappings, four ordinary
  shots, two material shots and nine saved-document metadata cases.
  `/private/tmp/source-firearm-main-materials-verified.json` and `.log`.
  The four added completion guards prevent aborted async cases from being
  mistaken for a pass. Earlier v2 passed 1,056 before those guards were added.
- M4 through WOOD_THIN: three ordered contacts (cover, target1, target2); both
  real receivers went from 100 to **66.8762922286987**. Exact source-equation
  replay matched every health/armor pool and reported damage, without a cover
  HP multiplier.
- M4 through UNKNOWN: one blocking contact; both targets remained at 100 and
  allocated no source health state.
- M4, Mark23 and four-pellet 870 real shots check receiver deduplication per
  projectile. The shotgun's later hits are rejected after source-pool death;
  no duplicate hurtbox damage is applied within a pellet.
- Primitive, imported box and imported detailed-mesh collision owners were
  tested through serialized map documents, normalization and runtime build.
  Explicit strings propagate; absent and malformed values are not inferred.
- Trace: PASS **91**, `/private/tmp/source-firearm-trace-final.log`.
- Muzzle/server baseline: PASS **15**,
  `/private/tmp/source-firearm-material-muzzle-final.log`; extended authoritative
  material packet proof passes **43** as detailed below.
- Source receiver authority: PASS **199**,
  `/private/tmp/source-firearm-material-authority-final.log`.
- Material feature contract passes. An intermediate aggregate run caught the
  separately in-progress camera contract before its proof script existed.
  After that proof landed, the aggregate gate passed all **147** contracts:
  `/private/tmp/source-firearm-material-contract-v3.log`.

Only existing macOS CA-certificate/audio-input warnings appeared in main v2.
Later runs intermittently reported headless audio shutdown resource warnings:
verbose inspection identified WAV/microphone/generator playback references,
not gameplay-node exceptions. A 150ms test-only teardown drain reduced main
warnings to two audio instances/one resource; server reported four/one. These
warnings remain disclosed, not a claimed clean shutdown. No production audio
code changed. The source-authority fixture also logged an ENet send warning from
its deliberate unconnected client branch; assertions passed, and no remote
network interoperability is claimed. All these proof processes exited. No
open user game, browser or deployed ZIP was restarted or replaced. Main tests
use a new scene instance and temporary test geometry, not the saved map.

The then-current first-target anatomical refinement remains a documented
project arbitration rule. Passing these tests proves the scoped canonical
material/damage adapter, **not** original triangle ordering, ricochet, mixed
material meshes, visual animation quality, or full-engine 1:1 parity.

## Translation card — authoritative material packet extension

- Intent: prove the already integrated source material policy through the real
  authoritative packet handler, not only local main shots/configuration parity.
- Acceptance: reuse the existing two-actor muzzle-obstruction fixture. Cover
  sits three metres beyond the authoritative muzzle, never between the report
  anchor and muzzle. WOOD_THIN accepts a shot and applies the exact source MP
  body pools once; UNKNOWN accepts firing but leaves target pools untouched.
  Both consume one round; replay changes neither health nor ammunition.
- Owner: unchanged multiplayer shot/damage owner. Only
  `tools/muzzle_obstruction_regression.gd` and this report are edited.
- Protected: obstruction rejection, sequence security, shared policy, source
  trace, damage equations, camera, character, maps and all running user sessions.
- Focused proof: existing 15 muzzle/server checks remain, plus two ordered
  source-material packet cases. This is a local authority fixture, not a
  remote internet transport test.

System delta MERGE: current/candidate correctness4/4, ownership5/5,
runtimeparity4/5, editorusability4/4, performance4/4, regressioncoverage4/5.
Evidence: `scripts/network/socom_multiplayer_combat.gd::_server_process_shot`,
existing muzzle test and `tools/source_firearm_main_regression.gd`. The latter
already proves two-receiver collateral; avoid duplicating a separate server
arena or weakening muzzle validation merely to reuse that scenario.

### Extension failures and final result

The first extension incorrectly read a nonexistent `peer_id` property. Godot
aborted both added coroutines, while the old end-of-test message misleadingly
printed PASS19. That run is **not** a pass. The helper now receives the already
known peer ID as an argument, and the final check requires both material cases
to complete. The real actor field, where used for diagnostics, is
`network_peer_id`.

The next probe missed the thin-cover target before packet processing. A
read-only trace showed WOOD_THIN reduced range 1000→325m correctly, and team
damage was permitted; history was empty, target alive, hurtboxes enabled.
The floorless fixture's actors were falling during cadence waits: the desired
torso dropped from y=-3.49 to -5.35 between cases. Holding only these test actors
stationary after the original 15 checks stabilized the physics query. The
ballistics node still advances its real cooldown. No gravity, aim, geometry
query, rewind, receiver or damage implementation was changed.

Final `/private/tmp/source-material-server-packets-v5.log`: **PASS43**.
The actual first physical impact is the cover plane at approximately 2.95m;
the thin-cover continuation reaches the torso near 7.87m. A genuine
`_server_process_shot` packet spends one round, emits one ballistics signal and
produces the exact single-body-hit original health/armor state. UNKNOWN spends
one round but never allocates target damage state. Each packet's replay is
STALE_SEQUENCE and cannot alter ammunition, shot count or health/armor pools.

Code locations: `tools/muzzle_obstruction_regression.gd::_cover_packet` and
`::_make_cover_beyond`; the new helper is a **stationary collision/authority
fixture**, not a locomotion or remote latency test. Its diagnostic query is
read-only; only the subsequent real packet handler applies the measured damage.
All proof processes have exited; the project remains in the user's main folder.
