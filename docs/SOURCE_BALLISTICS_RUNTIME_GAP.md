# Original ballistics extraction versus current Godot behavior

## Translation card — read-only comparison

Intent: identify what must actually be recovered to port bullet behavior, not
mistake imported scalar settings or visible tracers for an original trajectory.
Acceptance: name the current runtime consumers and actual equations, distinguish
verified source data from unknown executable behavior, and leave gameplay tuning
and all authority owners unchanged. Owner: offline research/report only.
Proof: inspect the active ballistics, server combat, penetration and presentation
call chain alongside the lossless ISO weapon/ammo report.

System delta: **KEEP** the current working runtime pending source-matched code
evidence; **MERGE** the separate lossless reference and executable inventory.
Scores (correctness/ownership/runtime parity/editor/performance/regression),
current runtime 3/5/5/4/4/4, hypothetical scalar-only "1:1 port" 1/5/2/4/4/1.
The lower candidate score comes from missing timestep/units/equations, not from
preferring the existing design. No candidate runtime implementation was made.

## Current code is immediate hit resolution with visual travel

`scripts/weapons/weapon_ballistics.gd:210` accepts a shot, constructs seeded
spread directions and synchronously traces each projectile:

```gdscript
var random_angle := random.randf() * TAU
var random_radius := sqrt(random.randf()) * cone_radius
var offset := Vector3(cos(random_angle), sin(random_angle), 0.0) * random_radius
var direction := (ray_basis * (Vector3.FORWARD + offset)).normalized()
var projectile := _trace_projectile(muzzle_pos, direction, space_state, exclude_rids)
```

`scripts/weapons/weapon_ballistics.gd:289` delegates to
`scripts/combat/socom_bullet_penetration.gd:65`. That routine directly calls
`space_state.intersect_ray(ray_query)` at line 92 in a bounded penetration loop.
There is no projectile position/velocity integration over simulation ticks in
this firing path.

`scripts/network/socom_multiplayer_combat.gd:200` calls that shared routine during
the server's rewound shot evaluation, restores the poses, then calls
`receiver.take_bullet_damage_region(...)` at line 254. It does not wait for
bullet flight time before resolving this damage. Character movement, camera aim
and server shot/damage ownership remain unchanged.

Velocity appears in the result at `weapon_ballistics.gd:357`:

```gdscript
"tracer_travel_seconds": (
    hit_pos.distance_to(muzzle_pos) / maxf(muzzle_velocity_mps, 1.0)
),
```

`scripts/network/socom_shot_presentation.gd:16` separately passes the configured
velocity to `Tracers.spawn_tracer(...)` for an already-authorized visual event.
Thus a moving bright tracer does not prove a moving damage-carrying projectile.
This is code evidence about OUR implementation; it does not establish whether
the original SOCOM II rifle path is immediate or time-integrated.

## Recovered data is not yet recovered equations

Exact source values and archive checksums are in
`art_source/socom2_ballistics_reference_20260912/weapon_reader_full.json`;
`docs/BALLISTICS_SOURCE_AUDIT.md` documents the extractor and executable identity.
The full weapon reader includes 86 weapon/gear and 39 ammunition records.

| Component | ISO evidence | Current Godot implementation | Port status |
| --- | --- | --- | --- |
| Initial speed / range | Explicit muzzle, effective and maximum range fields | Configured values; ray maximum range plus visual tracer speed | Data extracted; units/application not verified |
| Flight | Some acceleration/gravity-tagged records | Immediate ray path for firearms | Original integrator or direct-fire dispatch not recovered |
| Shotgun | `12 Gauge` has `NumProjectilesFired [4]` | Configured eight independent pellet rays; disk sampling | Data extracted; source distribution/semantics unknown |
| Damage | Impact, piercing, stun and other raw fields | Tuned shot/pellet damage, regional multipliers and linear distance falloff | Original complete mapping not recovered |
| Penetration | Raw ammo penetration-related fields | Project material table and dual-ray thickness logic | Not source-matched |
| Accuracy / recoil | Stance, burst, dilation and constriction settings preserved | Project spread, burst bloom and reticle envelope equations | Scalars recovered; original executable equations not recovered |

The source four-pellet field was NOT used to overwrite the user's current
eight-pellet/13-damage tuning. Likewise, realistic-looking source speed values
were not treated as proof of physical units or bullet drop defaults.

## Next evidence required before changing gameplay

Locate the original firing/update routine in the supplied disc's actual runtime
image, using file identity and code/data references. If static analysis cannot
isolate it, record a narrowly scoped original-game shot trace with emulated
simulation-step timestamps, ammo writes, target-health writes and candidate
projectile-position writes. Then verify dispatch, units, timestep, collision,
spread and damage against repeatable trials before adding a shared saved model
consumed by the existing authoritative weapon owner. No memory addresses or
equations should be guessed from a different game/build's reconstruction.

**Not done:** original trajectory extraction and a one-for-one Godot port of it.
This report and the raw reference do not claim those milestones.
