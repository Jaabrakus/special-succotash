# Original ONE_FRAME firearm policy: main-scene proof plan

## Translation card — executable proof, 2026-09-12

- Intent: prove the saved source range policy reaches accepted shots in the
  playable main scene and the existing multiplayer configuration owner.
- Acceptance: all 32 verified profiles have identical main/server policy and
  preserved numeric settings; real M4, Mark 23, 870 and unmatched-weapon fire
  consumes one round and resolves its projectiles/damage in the calling tick;
  an unmatched swap resets source policy. Optional screenshots use the actual
  player camera/HUD and target, not a manufactured result overlay.
- Owner: `tools/source_firearm_main_regression.gd`, an offline SceneTree harness.
- Protected: saved configuration, live processes, movement/camera/weapon/damage
  ownership, authored animation, fire/reload timing and map exports. Test-only
  placement occurs on a separate clear platform inside a new `main.tscn`.
- Focused proof: installed Godot headless run, JSON result, optional independent
  rendered run. Multiplayer checks configure the actual session method without
  opening a connection; they do not claim internet/remote-authority coverage.

System delta: **MERGE** this runnable proof. Correctness 3->4, ownership 5->5,
canonical parity 3->5, usability 3->4, performance 5->5, coverage 3->5. Strict
floating-point boundary fixtures remain owned by the separate policy regression.

## Translation card — read-only audit, 2026-09-12

- Intent: verify a source-derived ordinary-firearm range-query policy in the
  actual playable main scene, without conflating query extension with damage reach.
- Acceptance: identify the existing canonical shot seam, shared profile routing,
  minimum deterministic cases, and the currently identifiable native/web builds.
- Owner: this offline verification plan; runtime edits and proof execution are
  owned by the integrating task.
- Protected: current movement, camera/aim, damage, penetration, pellet counts,
  reload/fire timing, live processes, export artifacts, and unrelated changes.
- Proof: exact current code references and read-only process/build observations.
  The proposed new range cases below have not been executed by this audit.

System delta: **MERGE** focused main-scene range tests into existing verification;
**KEEP** established runtime owners. Scores 0–5, old -> proposed: correctness
3->4, ownership 5->5, canonical parity 3->5, usability 3->4, performance 5->5,
regression coverage 3->5. These scores describe the proposed test coverage, not
a completed feature or original-game visual parity.

## Existing low-cost harnesses

1. `tools/socom2_weapon_behavior_regression.gd` instantiates `main.tscn`, iterates
   32 source-matched profiles, calls the actual weapon controller's
   `_apply_weapon_config`, and checks multiplayer `_apply_ballistics_profile`.
   This is the smallest existing **configuration parity** seam. It does not
   prove that accepted shots use the new policy, because its cadence fixtures
   call `record_shot_state` on separate ballistics nodes.
2. `tools/ballistic_convergence_regression.gd` also instantiates `main.tscn`,
   positions a real anatomical target, updates the actual camera aim, and calls
   the canonical `WeaponController.request_fire`. Its accepted result includes
   immediate damage. Use this pattern for a new bounded range proof, not its
   assumptions that a particular authored map target remains on the center ray.
3. `tools/shotgun_projectile_regression.gd` covers eight pellet traces, one shell
   event/cadence, deterministic spread and saved falloff, but its shot world is
   an isolated fixture. Retain it as a preservation check, not main-scene proof.
4. `tools/main_source_motion_proof.gd` exercises movement and fire on the current
   skinned character, but is unnecessarily expensive for a range-only change
   and also gates unrelated hand contacts. Do not borrow its animation gates.

Existing invocations, from the project root:

```sh
/Users/kiwimango/Applications/Godot-4.7.1.app/Contents/MacOS/Godot --headless --path /Users/kiwimango/socom-141-camera-lab --script res://tools/socom2_weapon_behavior_regression.gd
/Users/kiwimango/Applications/Godot-4.7.1.app/Contents/MacOS/Godot --headless --path /Users/kiwimango/socom-141-camera-lab --script res://tools/ballistic_convergence_regression.gd
/Users/kiwimango/Applications/Godot-4.7.1.app/Contents/MacOS/Godot --headless --path /Users/kiwimango/socom-141-camera-lab --script res://tools/shotgun_projectile_regression.gd
/Users/kiwimango/Applications/Godot-4.7.1.app/Contents/MacOS/Godot --headless --path /Users/kiwimango/socom-141-camera-lab --script res://tools/feature_contract_regression.gd
```

These commands were identified, not run by this audit. Omit `--automated-test`:
the input-driven main harness explicitly rejects it because it disables actions.
Disable automatic mouse capture before attaching the new scene, and set
`socom/playtest/use_active_bundle=false` so a prior editor bundle cannot shadow
the saved policy. Do not reload the user's currently running scene.

## Canonical ownership and exact test seam

`main.tscn` uses `scripts/main.gd`. `scripts/runtime/main_weapon_runtime.gd`,
`build_weapon_controller`, creates the one `WeaponController`, configures it with
the actual player/camera, and connects its `authoritative_shot` signal.
`scripts/weapons/socom_weapon_controller.gd:request_fire` validates camera intent
and muzzle clearance before this call:

```gdscript
var result: Dictionary = ballistics.try_fire_direction(
    muzzle,
    resolved_shot_direction,
    player.get_world_3d().direct_space_state,
    exclude,
    seed,
    posture_name,
    retained_instability,
    not player.is_on_floor(),
    dispersion_multiplier
)
```

The same method consumes one inventory round, applies damage to each projectile,
and publishes the accepted result. Check this return value and signal on the
same physics tick to prove ONE_FRAME resolution; visible tracers are a separate
presentation path in `main_weapon_runtime.gd:on_authoritative_shot` and should
not be mistaken for delayed simulation.

Use `apply_authorized_weapon_pickup("res://config/weapons/mark_23.json")` for the
main shot case. It loads `WeaponContract.load_config`, equips the real mannequin,
applies ballistics, and initializes ammunition through the existing inventory.
Calling only `_apply_weapon_config` is adequate for a 32-profile routing census,
but does not demonstrate complete presentation/inventory equip integration.

## Smallest proposed new proof

Boot main once, settle the real player on a distant clear test platform, preserve
camera ownership, and let normal physics frames establish the muzzle/aim before
firing. Avoid changing saved range or timing just to make testing faster.

- **Routing census:** load each of the exact 32 matched profiles and compare
  normalized policy in main and multiplayer. Verify switching to an unmatched
  profile resets to the legacy default. Include absent/malformed policy inputs.
- **Primary live shot:** Mark 23 has a saved 125 m maximum. Place a thin target
  with its nearest surface safely inside that limit, aim through the real camera,
  fire, and require `fired=true`, one ammo consumed, one accepted-shot signal and
  immediate accepted damage. Assert final aim direction was not rewritten by
  the range adapter.
- **Out-of-range candidate:** place the target at 1.01 times maximum range,
  within the 1.1-times query segment. The shot is accepted but target damage and
  target-hit identity are absent. Assert both query distance and acceptance
  distance diagnostics rather than inferring query length from a rendered tracer.
- **No hit:** the policy reports the extended query while keeping the original
  damage cutoff. Its desired miss endpoint should be specified in the shared
  contract instead of guessed by this test.
- **Shotgun preservation:** one real 870 fire retains 8 projectiles, one shell
  consumption/event and saved damage/falloff settings. Do not pretend this alone
  verifies the original game's pellet-generation equation.
- **Boundary helper fixtures:** use exact scalar inputs for `d²=0`, just above
  zero, just below `R²`, equal to `R²`, and above it. Require exactly
  `0 < d² < R²`. Physics collision surfaces have tolerances, so an exact-radius
  collider test cannot replace these deterministic predicate fixtures.

Before the shot fixtures, reset test composure/cooldown only through the existing
test seam, or await the real cadence. Do not mutate live/save files. Capture a
small result row per case: weapon/config hash, actual policy, origin, aim direction,
query distance, acceptance distance, hit distance squared, frame/tick, damage,
ammo before/after, and accepted signal count. JSON should omit live object/RID
values and use names or stable identifiers instead.

### Two candidate paths must obey the same strict predicate

At audit time `scripts/weapons/weapon_ballistics.gd:_trace_projectile` first calls
`scripts/combat/socom_bullet_penetration.gd:trace_bullet`, then uses an independent
anatomical fallback:

```gdscript
var result := AnatomicalHitResolver.trace(
    space_state,
    muzzle_pos,
    hit_pos + final_dir * 0.05,
    exclude_rids
)
```

The fallback can otherwise restore an out-of-range target after the primary hit
was rejected. Guard both sources and every damaging entry in returned penetration
traces. Keep the existing material/penetration calculation; query extension must
not authorize extra penetration damage, and a beyond-range target must not
remain in `hit_collider`, `hit_region` or damage events after rejection.

## The 32-profile saved mapping

`config/feature_contracts/socom2_weapon_settings.json` documents 29 internal-name
matches plus three aliases. The saved identifier is
`reticle.socom2_source_name`; `reticle.socom2_stances` identifies the existing
32-profile settings census. Neither field alone is evidence of a decoded
projectile mode: the integrating task must connect its verified source mode
through an explicit shared policy, not a fuzzy display-name/category match.

Profiles in `config/weapons/`:

```text
12_gauge_pump 226 552 870 9mm_pistol 9mm_sub ak-47 aks-74 de__50
f57 f90 hk5 hk5sd m14 m16a2-m203 m16a2 m3_12_gauge m40a1 m4a1-m203
m4a1 m4a1_sd m60e3 m63a m82a1a m87elr m9 mark_23 mark_23sd model_18
sr-25 sr-25_sd ta_12_gauge
```

`config/reference/socom2_weapon_aliases.json` maps `12_gauge_pump` to `870`,
`m3_12_gauge` to `JACKHAMMER`, and `ta_12_gauge` to `Spas 12`.
The current saved startup loadout is `m4a1`, from
`config/weapons/operator_loadout.json`. `WeaponRigContract` can prefer an active
playtest bundle or CLI override, so the proof must record what was actually loaded.

## Build identification — observed, not assumed

Read-only process observation found native PID 49612 running:

```text
/Users/kiwimango/Applications/Godot-4.7.1.app/Contents/MacOS/Godot --path /Users/kiwimango/socom-141-camera-lab
```

Its working directory matches the project, but it had already been running for
over an hour before this range integration. This proves the project location,
not that its loaded scripts contain new edits. Another Godot process (PID 1144)
had no project argument; its role was not inferred. No listener was found on the
known local game ports 8060, 8073, 8080 or 8081. Processes can change after this
snapshot; no process was stopped or restarted.

The existing browser export is explicitly old:

- `builds/web/BUILD_ID.txt`: `141 restricted web build caac1fe200d9`.
- `builds/web/index.pck`: 99,582,464 bytes; modified September 7, 2026 01:52:55 EDT.
- `builds/SOCOM-141-browser-tournament.zip`: 100,011,755 bytes; modified September 7,
  2026 01:52:59 EDT.
- Its saved checksum file lists PCK SHA-256
  `e6dc44337e14337f84082a425019e2f54fcfae74d7a01086f006862a7e872032`;
  this audit read that manifest and did not recompute the whole package hash.

`tools/export_restricted_web.sh` runs release gates, exports the restricted web
preset, writes `BUILD_ID.txt`/`SHA256SUMS.txt`, then creates that tournament ZIP.
It was not run here. Editing local source cannot update this existing package or
an already deployed itch.io upload. A fresh separate native launch after the
integration is verified is the fastest build that can actually contain the changes.

## Implemented result — September 12, 2026

The integrating task also connected the verified signed-square axis dispersion
shape. The same proof now asserts its accepted-shot diagnostic
`source_signed_square_axes_v1` for the three matched live shots. This is a test
of the source-distribution adapter, not a claim that the current random seed,
spread amplitude, reticle envelope or whole original weapon simulation is 1:1.
System delta: **MERGE** the diagnostic assertion; keep all protected owners.

`tools/source_firearm_main_regression.gd:32` disables stale playtest-bundle
shadowing in this process and instantiates `main.tscn`; line 36 prevents automatic
mouse capture. The user's pre-existing game process is not modified. Lines 61–105
check the exact 32 policy identities plus an unmatched reset through the main
controller and the actual multiplayer configuration method:

```gdscript
weapon.call("_apply_weapon_config", config)
session.call("_apply_ballistics_profile", server_ballistics, config)
_expect(actual == server_ballistics.trajectory_policy, id + " main/server policy parity")
```

The census also compares range, pellet count/damage, shot damage, velocity,
headshot multiplier, falloff and cadence to the saved numeric values. It is
configuration coverage, not 32 fully rendered equips or network transport.

Lines 130–176 then use full authorized equip and the canonical fire request:

```gdscript
var ok: bool = weapon.call("apply_authorized_weapon_pickup", path)
# ... settle normal player, mannequin and camera frames ...
var tick_before := Engine.get_physics_frames()
var result: Dictionary = weapon.call("request_fire")
var tick_after := Engine.get_physics_frames()
_expect(tick_before == tick_after, id + " shot resolves in requesting tick")
_expect(target.current_health < health_before, id + " actual target damaged before request returns")
```

Both the headless v2 and separate rendered runs passed all 33 routing cases and
four live shots. Rendered observations (saved settings, ordinary torso modifier):

| Live equip | Ammo | Projectile / accepted damage entries | Target HP after | Request / completion physics tick |
| --- | --- | --- | --- | --- |
| M4A1 | 30 -> 29 | 1 / 1 | 73.36 | 274 / 274 |
| Mark 23 | 12 -> 11 | 1 / 1 | 65.44 | 394 / 394 |
| 870 | 12 -> 11 | 8 / 8 | 25.12 | 500 / 500 |
| Unmatched assault-rifle trainer | 30 -> 29 | 1 / 1 | 73.36 | 609 / 609 |

Every case emitted exactly one accepted-shot signal. The unmatched shot recorded
`project_hitscan` / `project_uniform_disk`, not stale source policy. The shotgun
does not kill this torso target despite 8 * 13 base damage: the existing 0.72
flank torso modifier yields 74.88 total damage. This proof did not change that
damage calculation.

The rendered run records policy SHA-256
`2db6df475541e1d4819d0674b7cd72ef7e5931ef1b756191c64a0bfb10ef1235`
and ballistics script SHA-256
`9b26e49b7db3e8e77138ae0696b0f688e7e35305992d84397d623f9150dbe1f9`.

Artifacts:

- `/private/tmp/source-firearm-main-v2.json` and corresponding `-run-v2.log`.
- `/private/tmp/source-firearm-main-render.json` and `-capture.log`.
- `/private/tmp/source-firearm-main-render-m4a1.png`.
- `/private/tmp/source-firearm-main-render-mark_23.png`.
- `/private/tmp/source-firearm-main-render-870.png`.
- `/private/tmp/source-firearm-main-render-assaultrifle_1.png`.

All four images were inspected. They show the actual player camera, ammo HUD,
hit confirmation and target damage feedback. The test-only target uses the
existing static training-dummy A-pose and is vertically positioned so its real
torso hurtbox lies on the center sightline; its feet therefore float. This is
not an animation, foot-contact, authored-map or final-art-quality proof.

The first invocation failed before script parsing because sandbox access to
`user://logs` failed and Godot crashed; specifying an explicit `/private/tmp`
log path avoided that startup failure. Headless runs then passed but reported
the existing macOS certificate/audio-capture warnings and an ObjectDB shutdown
warning (9 instances on v2). The separate graphical run passed with the audio
warning and no script errors. No unrelated shutdown/audio fix was attempted.

Reproduce the current proof without touching the open game:

```sh
/Users/kiwimango/Applications/Godot-4.7.1.app/Contents/MacOS/Godot --headless --path /Users/kiwimango/socom-141-camera-lab --log-file /private/tmp/source-firearm-main-run.log --script res://tools/source_firearm_main_regression.gd
```

For optional screenshots, omit `--headless` and add
`-- --capture --output=/private/tmp/source-firearm-main-render`.
Strict terminal-boundary, extended-query and golden distribution fixtures belong
to the integrating task's policy regression; this main harness does not replace
them. The feature-contract aggregate gate is owned by that task. Browser export
and real remote multiplayer testing remain separate, unperformed steps here.
