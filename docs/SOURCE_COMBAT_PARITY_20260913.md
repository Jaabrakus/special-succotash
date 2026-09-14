# Original combat parity — 2026-09-13

Camera follow-up: the user later chose “both hybrid”, superseding exact camera
parity as the default. Source scale and rifle idle remain connected in main;
camera sections below are historical. Current camera implementation is recorded
in `docs/CAMERA_HYBRID_TRANSLATION_CARD.md` and
`docs/SOURCE_CAMERA_ANCHOR_INTEGRATION.md`. Combat work below is unaffected.

The user now requests one-for-one combat behavior, superseding earlier custom
combat tuning where a verified source rule conflicts. This does not authorize
changing camera/movement ownership, releasing builds or disturbing live games.
Work is in `/Users/kiwimango/socom-141-camera-lab`, not the older skill alias.

Exact parity means comparison against the original executable with the same
inputs/state, not visual similarity or matching JSON field names. Individual
equations, their update clocks and their canonical consumers must all agree.
Do not label a partly ported pipeline one-for-one.

## Translation card — original random generator and direction arithmetic

- Intent: eliminate Godot's different random generator from the source-linked
  firearm shot sampler and match the original finite float32 direction math.
- Acceptance: the same 32-bit seed produces the same original 64-bit LCG state
  and 31-bit draws across sequences; raw draws normalize/square and produce the
  same original direction fixtures. Actual local/server accepted shots select
  this generator through the saved policy; unsupported profiles retain their
  current sampler. No random draws on rejected firing attempts.
- Owner: `SocomWeaponBallistics`; a pure integer/value helper implements math,
  not a new shot or networking authority.
- Protected: current range guards, damage/health until separately verified,
  cadence, saved weapon values, camera/reticle aim, movement, animation,
  running sessions, branch and all unrelated dirty work.
- Proof: original RNG instruction fixture, Godot exact seed/draw/state tests,
  original direction vectors, canonical local/server sampled shots, main-scene
  accepted firing, feature-contract regression.

System delta MERGE: replace the source-mode generator only. Current/candidate
scores correctness2/4, ownership5/5, canonicalparity5/5, editorusability4/4,
performance4/4, regressioncoverage3/5. Original boot `0x197740` computes
`state = state * 0x5851f42d4c957f2d + 1 (mod 2^64)` and returns
`(state >> 32) & 0x7fffffff`; seed helper `0x197728` zero-extends 32 bits.
Evidence/fixtures: `tools/source_fire_rng_audit.cjs` and
`docs/SOURCE_FIRE_RNG_DECODE.md` (parallel audit, required before completion).

Godot signed-overflow behavior is not assumed. A four-limb 16-bit product keeps
all intermediate arithmetic safely below int64 limits and assembles the low
64 bits explicitly. Direction vector operators preserve float32 intermediates.

Still a declared adapter: the multiplayer authority supplies one accepted-shot
seed, rather than sharing a global RNG with all original game effects/AI.
Identical algorithm/seed fixtures do not imply identical whole-game RNG state.
Full accuracy/recovery and damage/material paths are separate bounded changes.

## Remaining source audits in this pass

- Accuracy lifecycle: on-fire counter order, input-state reset, movement and
  recovery, clock units, stance and projection consumers.
- Damage: six region pools and armor, initialization/profile selection, kill
  conditions, range degradation and material continuation.
- Pellet loop: actual `NumProjectilesFired` consumer, per-pellet RNG/call order.

Only proven changes are promoted. An imported reference or inactive helper is
not runtime integration. Source health/armor pools will not be collapsed to a
guessed global multiplier merely to fit the current receiver.

## Translation card — verified MP firearm damage and pellets

- Intent: source-linked ordinary guns inflict original per-region armor/health
  damage and emit the original pellet count. Both teams share verified MP data.
- Acceptance: executable fixture parity for damage/falloff, armor, six pools,
  depleted-limb routing, death and weighted health; main training and server
  receivers consume the same trusted saved source policy. Four shotgun rays per
  accepted shell; no custom graze, flank, brace, headshot or limb multipliers on
  source-mode hits. Respawn resets all pools. No healing through interleaving
  source and unsupported-weapon/explosion hits. No damage on rejected RPCs.
- Owner: existing damage receiver (`SocomNetworkOperator` on the server,
  `LabLeakTargetDummy` for training). A RefCounted value helper owns no node,
  signals, physics, replication or independent update loop.
- Protected: camera/aim and CharacterBody ownership, animation, ammo/cadence,
  network validation, unsupported-weapon balance and all unrelated work.
- Proof: original instruction fixtures, Godot pure/helper and receiver tests,
  actual main accepted shots, shared local/server profile census, feature gate.

System delta MERGE: correctness2/4, ownership5/5, runtimeparity3/5,
editorusability4/3, performance4/4, regressioncoverage3/5. Six source pools cannot
be represented by a guessed multiplier against100HP. Existing replicated HUD
health becomes the original weighted fraction scaled to the current HUD maximum.

The saved source policy is authoritative for these source-mode fields. Existing
custom weapon JSON values remain recoverable but do not override original-mode
damage/range/pellets. Gunsmith tuning of those legacy fields is NOT source-mode
tuning; original-mode editing/UI remains a documented limitation, not a second
hidden runtime. Source values are visible in `config/source_firearm_policy.json`.

## Translation card — source material continuation in canonical shots

- Intent: stop using project thickness/HP-loss heuristics for source-linked
  bullets, and allow only explicitly identified original material responses.
- Acceptance: exact saved coefficients, unknowns stop, P=1 skips impact, all
  continuation cutoffs measured from original muzzle, source range reduction
  not HP loss; every eligible target in the ordered source impacts reaches
  existing authoritative damage receivers at most once per pellet.
- Owner: `SocomWeaponBallistics` traces; controller/server receivers apply
  damage. `SourceFirearmTrace` is a pure physics-query adapter, no Node/update,
  mutation of world state or second damage writer.
- Protected: non-source shots, map mesh/collision construction, camera/aim,
  movement/collision ownership, networking permission/cadence/ammo checks.
- Proof: original material lookup/equation fixtures, focused Godot trace tests,
  local/server actual damage routing, main scene and feature gates.

System delta MERGE: correctness1/4, ownership5/5, parity3/5, usability1/3,
performance4/4, regression2/5. Original material identity is exact `source_material`
metadata on uniform colliders, or explicit anatomical identity for PERSON. No
fuzzy texture/node-name mapping. Current untagged map surfaces remain solid.
Imported per-triangle metadata, ricochet/special callbacks and exact original
compound-surface order are unfinished. Godot closest-hit/RID exclusion and the
bounded-query safety stop are declared geometry adaptations.

Metadata propagation sub-card: saved map `properties.source_material` is an
explicit uniform-collider author choice, never inferred from appearance. Existing
map builders alone copy it to their constructed StaticBody3D nodes (including
imported detailed collision children). Acceptance: same saved object produces
same tag in editor/runtime; absent/malformed property produces no tag. No active
map is retagged, no meshes/shapes/positions are changed. Source trace validates
against the saved exact-name coefficient contract. Mixed-material assets must
be split/assigned correctly by their author, not blanket auto-classified.

Metadata proof delta: the first real-main WOOD_THIN/UNKNOWN cover test failed
because the primitive `SocomMapRuntime.build_object` branch wrote only id/type
metadata and bypassed the shared helper. Imported collision cases passed.
MERGE the existing `Geometry._set_object_meta(body, object)` call into this
branch; do not alter its geometry, appearance or collision ownership. The
saved-property intent/acceptance above is unchanged. Current/candidate scores:
correctness2/4, ownership5/5, runtimeparity2/5, editorusability2/4,
performance5/5, regressioncoverage3/5. Focused proof: rerun both main cover
shots and nine saved map/imported metadata cases, plus the feature gate.

## User scope extension — original camera and character scale

The user additionally requests the original camera, and permits character model
size changes if needed. Earlier camera-setting protection is superseded for a
separate verified camera change. Camera/aim ownership remains singular; do not
rescale CharacterBody, skeleton and weapon independently to fake framing.
Source camera update/defaults and actual current/source skinned dimensions are
being audited independently before a saved camera/scale change is chosen.

Explicit adapters: source reader range units interpreted in project meters
(the original reader stores10 internal units per reader unit); scene/hurtbox
geometry stays ours. The scene maps torso/pelvis to body and matching left/right
limbs to six original regions. Explosive/unmatched-gun damage still uses existing
rules and can only lower source pools proportionally; that bridge is not claimed
to reproduce original explosions. Unsupported receivers reject source damage
instead of silently applying the old damage model.

## Runtime checkpoint — current scope, not a complete one-for-one port

| Area | Status | Actual boundary |
| --- | --- | --- |
| Explicit source weapon selection | Done for 32 linked profiles | Trusted saved identity, not category/name guessing; unsupported profiles reset to legacy |
| Ordinary shot query/cutoff | Done for verified equations | Synchronous 1.1 padded query; strict damaging range |
| RNG and raw direction arithmetic | Done for finite original fixtures | Per-accepted-shot server seed is still a project adapter, not the original global effects/AI RNG history |
| Source damage, range, armor and region HP | Done for ordinary source firearms | Six verified MP pools, original death/HUD fraction, existing receiver authority |
| Source shotgun projectile count | Done | Four original 12-gauge pellets, not the previously customized eight |
| Material continuation | Partial | Exact scalar rules integrated; Godot collider/region ordering differs and existing maps are not automatically classified |
| Accuracy, recoil and reticle lifecycle | Partial | Original routines decoded/tested offline; authored live bloom and shot-only network timing retained pending verified state/projection mapping |
| Selected character skeleton scale | Done for measured rest dimensions | 60.48790231 only on modern_soldier_iso.scn; other scenes keep64 and capsules are unchanged |
| Character poses and surface contacts | Partial | Native multi-angle proof still shows rifle support-finger fit and crouch/prone ground penetration |
| Original camera | Partial, candidate OFF | Verified70-degree horizontal lens and clear-path math are available, but lens-only native rendering cropped the character with current offsets. Do not promote it. Exact posed camera-root channel was discarded by retargeting; no guessed hips substitute |
| All original movement/animations, explosions, special projectiles | Not completed by this pass | Earlier animation acceptance and unsupported weapon behavior remain separately documented |
| Browser ZIP, remote load test and release | Not started in this pass | Fresh local main-scene tests do not update a running native process or an old itch build |

The user-authorized scale implementation and rendered proof are detailed in
`docs/SOURCE_CHARACTER_SCALE_AUDIT.md`. Original camera evidence/limits are in
`docs/SOURCE_CAMERA_RUNTIME_PARITY.md`. The exact-root channel is independently
animated beneath the original actor; recovering it from our hips would mix in
hip bob, and blindly replaying raw root travel could move the camera away from
the CharacterBody. Keeping that position branch disabled is deliberate.

Native camera acceptance overrode the earlier numeric lens PASS: at level aim,
the source lens with existing authored offsets put the standing head near the
bottom and the crouched body off-screen. Both source lens and source position
remain disabled in the saved default. Current camera settings remain active;
the opt-in test enables only the candidate in its own scene instance. The
failed renders are evidence, not an approved camera replacement. Root-channel
retention feasibility is recorded in `docs/SOURCE_ROOT_CHANNEL_FEASIBILITY.md`.

### Relevant shared runtime excerpts

`scripts/weapons/weapon_ballistics.gd:try_fire_direction` selects original draws
inside the existing accepted-shot owner, once per pellet:

```gdscript
var draw_x := source_random.next_raw()
var draws := SourceRng.signed_draw_pair(draw_x, source_random.next_raw())
direction = SourceDispersion.direction_in_envelope(forward_dir, cone_radius, draws)
```

`direction_in_envelope` explicitly retains the authored cone; raw equation
parity is not full source accuracy timing. The source-only trace produces
`damage_impacts`, which the existing local and server adapters apply once each.
`scripts/combat/source_firearm_damage.gd:apply_projectile` retains independent
regional death rules rather than treating the HUD's100 scale as one HP pool:

```gdscript
var changed := _apply_region_damage(damage, _f32(piercing), index)
alive = _health[0] > 0.0 and _health[3] > 0.0
```

The canonical map primitive branch now calls the same metadata helper as
compound pieces, `scripts/maps/socom_map_runtime.gd:build_object`:

```gdscript
Geometry._set_object_meta(body, object)
```

### File-by-file change map

- Saved original constants/identity: `config/source_firearm_policy.json`,
  `tools/build_source_firearm_policy.cjs`, `scripts/weapons/source_firearm_policy.gd`.
- Shared accepted shot/RNG/direction/query: `scripts/weapons/weapon_ballistics.gd`,
  `scripts/weapons/source_firearm_rng.gd`, `scripts/weapons/source_firearm_dispersion.gd`,
  `scripts/combat/source_firearm_trace.gd`.
- Damage state/math and existing receiver wiring:
  `scripts/combat/source_firearm_damage.gd`, `scripts/combat/lab_leak_target_dummy.gd`,
  `scripts/network/socom_network_operator.gd`,
  `scripts/weapons/socom_weapon_controller.gd`,
  `scripts/network/socom_multiplayer_combat.gd`.
- Explicit saved-map material propagation: `scripts/maps/socom_map_geometry.gd`,
  `scripts/maps/socom_map_runtime.gd`, `scripts/maps/socom_imported_map_asset_builder.gd`.
- Selected scale/editor chain: `config/operator_movement_tuning.json`,
  `scripts/runtime/operator_tuning_profile.gd`, `scripts/runtime/main_animation_studio.gd`.
- Contracts: `config/feature_contracts/source_firearm_policy.json`,
  `source_firearm_damage.json`, `source_firearm_materials.json`,
  `source_character_scale.json` in the same directory.
- Focused tests: `tools/source_firearm_policy_regression.gd`,
  `source_firearm_rng_regression.gd`, `source_firearm_damage_regression.gd`,
  `source_damage_authority_regression.gd`, `source_firearm_trace_regression.gd`,
  `source_firearm_main_regression.gd`, `source_character_scale_regression.gd`,
  `shotgun_projectile_regression.gd`, `muzzle_obstruction_regression.gd` in `tools/`.
- Research fixtures, provenance and decoder audit documents are not shipped
  gameplay assets. `export_presets.cfg`, `config/web_release_policy.json` and
  `tools/web_release_audit.gd` exclude/test the research-vector files.

### Final focused verification

These are scoped test results, not a declaration that every gameplay feature
or animation passes. Source camera promotion explicitly failed rendered checks.

| Check | Result |
| --- | --- |
| Saved policy generator `--check` | PASS32 profiles |
| Source RNG / source policy | PASS250 / 4173 checks |
| Source damage math / receiver authority | PASS253 / 199 checks |
| Source material physics queries | PASS91 checks |
| Real main scene firearm/material routing | PASS1060 checks:33 local/server profile mappings, four ordinary shots, two cover shots, nine map metadata cases |
| Real server muzzle/material packets | PASS43 checks: original obstruction/security cases plus thin/unknown cover, exact source health, single ammo spend and replay rejection |
| Shotgun / rapid-tap / shared reticle / network feedback | PASS |
| Existing bloom envelope | PASS45 profiles,21114 direction/projection checks; still the authored envelope |
| Character scale | PASS72 headless and native checks,24 multi-angle images |
| Original camera fixtures / Godot candidate math | PASS29 / 52; numerical parity is not framing approval |
| Source lens candidate rendered framing | FAIL4 standing/crouched head/chest checks; candidate disabled |
| Existing default camera rendered framing | FAIL1 crouched-chest visibility check; reported baseline, not hidden or changed to pass |
| Camera obstruction guard | PASS; existing collision/aim ownership retained |
| Feature graph | PASS147 contracts; graph validity does not override a failing focused/rendered test |
| Web release audit self-test | PASS; no new browser package built or audited |

Latest combat reports/logs: `/private/tmp/source-firearm-main-materials-v2.json`
records the first passing material integration; see the later final paths in
`docs/SOURCE_FIREARM_TRACE_ADAPTER.md` for completed-case guards and server cover
proof. Root reruns are `/private/tmp/source_firearm_rng_regression-final.log`,
`source_firearm_policy_regression-final.log`, `source_firearm_damage_regression-final.log`,
`source_damage_authority_regression-final.log`, `shotgun_projectile_regression-final.log`,
`rapid_tap_bloom_regression-final.log`, `bloom_shot_envelope_regression-final.log`,
`source-combat-feature-contracts-final.log`, `source-combat-export-policy-final.log`
in `/private/tmp/`. Character proof is durable in
`art_source/source_character_scale_verified_20260913/`; camera candidate/default
reports and failing images are linked in `docs/SOURCE_CAMERA_RUNTIME_PARITY.md`.

The extra server material fixture initially had a wrong test-only actor property
and then missed its target because its floorless actors fell during cadence
waits. Completed-case guards now prevent an aborted async case from appearing
to pass. Only that fixture's actors are held stationary; production movement,
source damage, recoil, ammo/cadence and muzzle security were not relaxed.

Known diagnostic noise remains: macOS CA certificate warning, disabled audio
input warning, unconnected-client ENet warning in authority tests, intermittent
audio playback/resource shutdown leaks. The existing aggregate integration
script requires branch `main`; current `codex/render-deployment` was preserved.
The earlier multiplayer-slice spawn-side baseline failure is not repaired by
these scoped tests. No real internet/32-player load test is claimed.

### Playing this work

Open `/Users/kiwimango/socom-141-camera-lab/project.godot` in Godot4.7.1 and run
`res://main.tscn`. Relaunch an old game when ready to load the changed scripts
and saved profiles. This task did not reload the user's game, build/upload a
browser ZIP, restart Render, switch branch or push to GitHub. A separate client
checkpointed/merged the worktree during the turn; its conflicts were cleared
externally before final checks. That Git operation is not attributed to this
task and unrelated changes were preserved.

The user subsequently clarified "main" means this local project folder, not
GitHub. The remote refs were refreshed during clarification, but there was no
commit, push, branch switch or Git merge by this task. No copy from a temporary
project is needed: all runtime changes are already in this canonical folder.
