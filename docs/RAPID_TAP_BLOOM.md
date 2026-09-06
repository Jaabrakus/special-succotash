# Rapid-tap bloom

## Translation card

1. Intent: rapid single-fire clicks must not repeatedly earn rested accuracy.
2. Acceptance: accepted shots retain a sequence across short trigger releases;
   bloom grows from the third shot, stays capped, then recovers after a pause.
3. Owner: existing SocomWeaponBallistics, shared by local and server weapons.
4. Protected: damage, legal fire interval, fire modes, movement, animation,
   aim center and network shot authority. Keep the existing opening pair.
5. Proof: deterministic cadence/recovery/stance tests; existing bloom, fire-mode
   and composure tests; canonical reticle consumer and feature contract gate.

## Delta review

MERGE the existing shot-history/recovery path; do not add an autoclicker detector
or a second accuracy owner. Scores current/candidate (0–5): correctness 2/4,
ownership clarity 5/5, canonical parity 4/5, editor usability 3/4, performance
5/5, regression coverage 2/4. Evidence: weapon_ballistics.gd `_process` resets
count at cooldown completion after release; controller and multiplayer combat
both use that count for composure dispersion. Candidate retains count until
the saved quiet-period delay and existing bloom recovery have completed.

The proposed default quiet period is 0.30 seconds, at least 1.5 legal shot
intervals for slower weapons. Only elapsed time beyond that boundary counts
toward recovery, avoiding frame-rate-dependent early decay. Gunsmith edits the
same per-weapon `ballistics.bloom_recovery_delay_seconds` profile consumed by
both local and multiplayer `configure_projectiles` calls.

Godot 4.7.1; Node `_process(delta)` elapsed seconds checked against official
latest documentation (advisory):
https://docs.godotengine.org/en/latest/classes/class_node.html#class-node-private-method-process

## Implemented and verified

`scripts/weapons/weapon_ballistics.gd:73` now gates recovery on accepted-shot
age, not trigger-release input:

```gdscript
var recovery_delay := maxf(bloom_recovery_delay_seconds, fire_interval * 1.5)
if seconds_since_last_shot >= recovery_delay:
```

The existing shot counter resets only after that quiet period AND zero remaining
bloom. Existing per-weapon growth/caps and stance recovery rates remain intact.
The first two accepted shots retain their existing opening behavior; rapid shot
three and onward add spread. Rejected cooldown clicks add no history or bloom.

Shared profile default is normalized in `scripts/weapons/weapon_rig_contract.gd`;
`configure_projectiles` reads it for local controller and multiplayer round
configuration. Gunsmith fire panel, state, profile loader, and persistence expose
and save the same field. Legacy files get the default in memory, without bulk
rewriting users' weapon profiles. The runtime floor is 1.5 legal shot intervals.

Proof:

- New cadence regression failed 78 assertions before the repair and passes after
  it: standing/crouched/prone, release versus held cadence, caps, cooldown
  rejection, rested accuracy, slow weapons, 30/60/144 FPS recovery, local/server
  profile parity and switching-profile fallback.
- Canonical live HUD regression passes headless and rendered: gap 8.8795 px at
  rest -> 31.7856 px after rapid taps -> 8.8795 px after recovery. Captures viewed:
  `/private/tmp/rapid-tap-rest.png`, `rapid-tap-rapid.png`, `rapid-tap-recovered.png`.
  This deliberately exercises the actual configured ballistic node and HUD;
  it is not a real internet/autoclicker client test.
- Stance bloom regression passes, now checking the intended quiet period before
  comparing unchanged standing/crouching recovery slopes. Fire-mode policy,
  operator composure, shotgun projectiles and shared weapon reticle pass.
- 63 feature contracts and unchanged file budgets pass.
- The supplied recording was decoded with macOS media access and sampled at
  twelve timestamps; reviewed frames show AKS-74 and M14 in SEMI mode. No exact
  click-rate claim is inferred from sampled frames.

Existing `weapon_bloom_profile_regression.gd` fails obsolete hard-coded profile
and reticle expectations. Reinstating the old `_process` in an isolated fixture
reproduces the same failures (`/private/tmp/tap-old-profile.log` versus
`/private/tmp/weapon_bloom_profile_regression-tap.log`). Neither those authored
values nor those assertions were changed. They are not a passing gate.

The integration quick gate still refuses `codex/render-deployment` and requires
`main`; no branch switch, commit, push, or browser export was performed. Restart
the local game to load the changed script. Existing browser exports are unchanged.
