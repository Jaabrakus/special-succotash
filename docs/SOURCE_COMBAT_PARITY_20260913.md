# Original combat parity — 2026-09-13

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
