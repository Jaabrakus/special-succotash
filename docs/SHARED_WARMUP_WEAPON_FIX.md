# Shared lobby warm-up and missing weapon families

## Translation cards — before edits

Warm-up intent: connected lobby players choose firearms with B and shoot one
another while waiting. Acceptance: existing server operators spawn before the
match; free selections are server-validated; deaths respawn without scores;
countdown ends practice and live play receives fresh health/ammo and the existing
shared random weapon. Owner: existing multiplayer session, with a bounded
warm-up policy layer. Preserve the tournament admission count, bracket, camera,
movement, throwable inventory, and live match damage/selection restrictions.
Proof: isolated warm-up regression, lifecycle test, browser lobby inspection.

Weapon intent: shotguns fire pellets, long/heavy weapons fit the hands, and
saved cadence/range settings actually reach local and server ballistics.
Acceptance: deterministic multiple pellet directions, one shell/cadence event,
per-pellet hits on both authority paths, spread widening with distance, bounded
short-range shotgun tuning, saved slow sniper cadence honored, and rendered
contact proof for the additional model categories. Owners: shared weapon
contract, server/local authoritative weapon consumers, existing presentation
resolver. Preserve pistol/rifle/SMG authored poses, camera intent, recoil state,
and the 1.2-second recovery behavior. Proof: pellet/cadence/profile tests,
family-contact tests, network combat tests, and rendered weapon checks.

## System delta

MERGE existing owners, not a second training simulation. Current -> candidate
scores (0–5): correctness 1 -> 5, ownership 4 -> 5, runtime parity 2 -> 5,
editor usability 4 -> 4, performance 5 -> 4 (bounded extra shotgun rays),
regression coverage 2 -> 5. Evidence: `socom_multiplayer_session.gd`,
`socom_multiplayer_round_loadout.gd`, `weapon_ballistics.gd`,
`weapon_rig_contract.gd`, `weapon_family_visual_assignments.json`, and the
focused tests added alongside the implementation. Scores are acceptance
targets, not a claim that unrun tests already pass.

## Browser packaging delta

Browser execution exposed a parse-time preload of the experimental native-IK
player in `main_training_world.gd`, although `main.tscn` already owns the
canonical `operator_player.tscn`. REPLACE that fallback preload with the same
canonical scene. Acceptance: browser Training Grounds initializes its player
and B armory without shipping native-IK editor dependencies. No live player
node, movement script, animation rig, or camera changes. Correctness/parity
improve from 1 to 5; ownership and performance remain unchanged. Proof:
`browser_training_entry_regression.gd` and the actual exported browser page.

## Verification record — 2026-09-05

### Exported model validation delta

Player intent: the browser must show the same calibrated weapons as native.
Acceptance: imported FBX resources validate in the exported game; missing
resources still fail. Owner: `GunsLab2VisualRigContract.validate`, line 167.
Do not change sockets, scale, animation, aim or damage. Proof: rig contract
regression plus exported-browser shotgun equip/fire.

REPLACE raw `FileAccess.file_exists(model_path)` with
`ResourceLoader.exists(model_path, "PackedScene")`. Browser logs rejected the
published shotgun rig because the source FBX is converted at export, causing
oversized profile fallback. Scores (current -> candidate): correctness 1 -> 5,
ownership 5 -> 5, runtime parity 1 -> 5, editor usability 5 -> 5,
performance 5 -> 5, regression coverage 2 -> 4. This checks the same model
through Godot's imported-resource mapping without loading another scene.
Official reference: https://docs.godotengine.org/en/stable/classes/class_fileaccess.html
recommends ResourceLoader for converted resources in exported packages.

- PASS: `shotgun_projectile_regression.gd`: eight deterministic spread rays,
  one accepted-shot event, cadence, configured range/falloff, single-projectile
  reset, and the 29 RPM M82 setting.
- PASS: `lobby_warmup_regression.gd`: two real ENet peers; client armory request,
  invalid peer/path rejection, one shell for eight pellets, real other-player
  damage, host-to-client and client-to-host shooting, respawn without score,
  shared live loadout, restored movement input, and stale-respawn cancellation.
- PASS: `firearm_family_live_contact_regression.gd --long-guns-only`: nine
  profiles, 18 standing/crouched cases. The first run found a 2 cm support-hand
  error for crouched MK 3-A2; a new immutable shotgun rig revision resolved it.
- PASS: display-backed `firearm_family_visual_proof.gd --long-guns-only`:
  nine profiles, four states each; contacts, square shoulders, bore alignment
  and recovery ownership. Images: `/private/tmp/socom-long-gun-visual-proof/`.
- PASS: ballistic convergence, shared random round weapon, tournament session,
  tournament replication scope, multiplayer inheritance/architecture, and all
  41 feature-contract graphs.
- PASS: browser entry regression with `--restricted-web-preview`, including
  canonical player, targets, free B armory and return-to-menu.
- PASS: imported model validation and missing-resource rejection; Guns Lab 2
  profile regression passes with permission to create isolated user-data files.
  The initial restricted run could not create its test directory and failed;
  no gameplay change was made to bypass that permissions failure.
- Browser visual PASS: exported Training Grounds loads the player and targets,
  B opens the armory, and equipping the 870 uses the calibrated normal-size
  model. The new session no longer reports the rejected shotgun visual rig.
  Browser firing remains UNVERIFIED: automated click encounters Chromium's
  `UnknownError` during mouse capture, and ammo stays at 12. This is not
  evidence of successful browser firing; native shooting proofs are separate.
- FAIL: current Mark23 movement-transition regression: early transition-frame
  support contact exceeds 1 cm; settled/fire contact passes. No pistol pose or
  animation source edits were made by this pass. This remains unresolved.
- BLOCKED: aggregate integration gate requires `main`; this dirty working
  checkout remains on `codex/render-deployment` and was not reset or moved.
- Browser export rebuilt as `0.1.1-warmup`; archive/hash checks pass. Public
  WebRTC lobby entry remained at connecting. Local signaling was rejected by
  the browser client's WSS-only rule; that security rule was not weakened.
  Native two-player proof is not a claim of browser WebRTC or 32-peer load proof.

Final rebuilt archive: `builds/SOCOM-141-browser-tournament.zip`.
SHA256: `94ac357702f891f911efe20c6a031f9b406c33ac063a1ab925206d5ab65da34a`.
Local preview remains running at http://127.0.0.1:8060/ for manual playtesting.
No public service deployment, Git push or shutdown was performed.

Shotgun values (8 x 12 damage, 3-degree half-angle, falloff 12–40 m, 60 m trace
limit) are initial game tuning, not a claim of authentic SOCOM II balance.
Muzzle velocity remains each saved profile's value. Machine-gun/sniper models
remain the existing catalog meshes; this pass calibrates their contacts, not
new historically accurate art or bespoke reload animations.

## Runtime excerpts

`scripts/weapons/weapon_ballistics.gd`, `try_fire_direction`:

```gdscript
var count := clampi(pellet_count, 1, 32)
for index in count:
```

`scripts/network/socom_multiplayer_warmup.gd`, elimination boundary:

```gdscript
if is_lobby_warmup_active():
    if multiplayer.is_server():
        _respawn_warmup(victim, warmup_generation, operators.get(victim))
    return
super._on_operator_eliminated(victim, attacker)
```

The return above prevents practice kills from entering live round/tournament
scoring. `receive_warmup_end` clears practice operators before the existing
round owner creates the fresh match and shared weapon assignment.
