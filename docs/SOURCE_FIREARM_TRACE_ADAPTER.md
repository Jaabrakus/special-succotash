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
