# Shared weapon reticle implementation

Intent: weapon-specific kick limits and one reticle presentation in training and multiplayer.
Acceptance: nested stance parsing retains complete fields; reviewed standing
kick/return/maximum values reach existing weapon JSONs; confirmed local-player
shots trigger the same dynamic reticle online, never remote shots or dry fire.
Owner: SocomDynamicReticle presentation; WeaponContract saved data. Multiplayer
only forwards accepted visual events. Server remains sole shot/damage owner.
Protected: ballistic balance, cadence, reloads, camera aim, poses, unrelated
weapon tuning, browser ZIP and deployment. Do not run the blanket importer.
Proof: importer regression, shared-reticle regression, rendered HUD sequence,
connected warm-up shooting and feature contracts.
MERGE: correctness 2->4, ownership 3->4, runtime parity 1->4, editor usability
3->4, performance 4->4, coverage 2->4. Evidence: importer line149 truncated
stance blocks, static multiplayer Label, existing dynamic reticle runtime.

Only the standing kick triplet is migrated in this pass; stance-specific
ballistic conversion and original rifle mesh-kick curves remain separate work.
The old importer treats original reticle values as pixels; retained for this
bounded repair, not a claim of original-game or video visual equivalence.
The video could not be retrieved; no extracted audio assets were installed.

## Verification and limitations

31 firearm JSON profiles updated only in the standing reticle triplet and
`cadence_driven_return:false`. Ballistic values and grip/pose data preserved.
Gunsmith slider ranges now accommodate the original values; load/preview/save
preserves whether recovery is authored or cadence-derived.

PASS: nested-parser tests and four original reference triplets; shared online
reticle type, saved M4 kick/cap/return, remote-shot exclusion, confirmed local
bounce and unchanged authoritative center; existing ballistic reticle suite;
architecture; connected ENet warm-up damage/respawn/live transition; 46 contracts.
Rendered ready/kick/recovered frames saved to /private/tmp/shared-reticle-*.png;
ready and kick inspected: ticks rise while center dot remains fixed.

The new online path supplies confirmed-shot bounce, not full training-mode
movement/composure bloom parity. No new server spread payload was introduced.
Original stance-specific mesh kick and functional camera climb were not changed.
No browser export/deployment. Full integration still requires main.

Relevant runtime excerpts:
`scripts/network/socom_multiplayer_rounds.gd`, `_present_shot`:
```gdscript
if shooter_peer_id == multiplayer.get_unique_id():
    if reticle != null and not dedicated_server_mode:
        reticle.notify_shot()
```
`scripts/network/socom_multiplayer_world_ui.gd`, `_refresh_player_state`:
```gdscript
var profile: Dictionary = equipped_config.get("reticle", {}).duplicate(true)
profile["fire_interval_seconds"] = _configured_fire_interval()
reticle.apply_profile(profile)
```
