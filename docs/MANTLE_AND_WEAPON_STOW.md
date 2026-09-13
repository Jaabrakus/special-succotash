# Existing AGLS mantle and traversal weapon stow

Canonical project: `/Users/kiwimango/socom-141-camera-lab`, Godot 4.7.1,
`res://main.tscn`. Preserve current branch and unrelated work.

## Translation card: mantle

- Intent: use the already imported authored mantle instead of lateral vault on low thick platforms.
- Acceptance: main-scene player enters low mantle through normal commands, uses the saved AGLS Walking clip, supporting hands contact the validated edge, exits once on the platform; tall hang and running jump retain their tests.
- Owner: existing operator animation driver plus its traversal-only SkeletonModifier. Existing CharacterBody motor still owns all movement/collision.
- Must not change: jump physics, collision/reach safety, camera/aim, weapon damage/reload timing, original animation assets.
- Proof: main mantle contact regression, original hang/contact and ledge regressions, rendered early/middle/late frames, feature graph.

## Translation card: weapon stow

- Intent: equipped rifle is visibly carried against the body while both hands climb, then returns to the hands. User confirmed rifle sling, not rope swinging.
- Acceptance: one visible cosmetic weapon during traversal; actual equipped weapon remains on canonical hand mount with unchanged ammo and ownership; body-attached copy has no gameplay scripts/collision; clean exit/death cleanup.
- Owner: operator animation driver coordinates a dedicated cosmetic stow helper, with saved attachment offsets. BoneAttachment follows the skeleton without overriding it.
- Must not change: inventory/loadout, firing/reload authority, movement, camera, original weapon parenting.
- Proof: helper regression plus real-main hang/mantle rendered stow/restore.

## System delta

Decision: MERGE. Existing low-mantle slot references the lateral1mLH vault;
existing two-handed traversal hides the held weapon entirely. Candidate uses
the existing ground-mantle source and a non-gameplay stowed visual. Scores0–5,
current→candidate: correctness1→3 (pending proof), ownership5→5,
runtime parity5→5, editor usability3→4, performance5→4, regression3→4.
Evidence: `config/operator_animation_map.json`,
`scripts/player/operator_animation_driver_runtime.gd`,
`tools/main_vault_presentation_regression.gd`.
Do not upgrade visual acceptance based on importing or naming a clip alone.

## Implemented runtime changes

- `config/operator_animation_map.json`: low mantle now reads
  `ALSv2_Mantle_2m_Walking_01.scn`; original source remains unchanged.
- `config/ledge_climb.json`: saved source segment .30→1.0; separately sampled
  root curves, bounded support offset and acquire/release windows for low mantle.
- `scripts/player/operator_animation_driver_runtime.gd`: seeks that segment from
  authoritative phase; begins cosmetic stow and ends it on exit, death or removal.
- `scripts/player/operator_traversal_hand_modifier.gd`: low-mantle slot has its
  own contact/root settings, fails closed if absent, converts actual evaluated
  source time into action phase. It never writes CharacterBody movement.
- `scripts/player/operator_traversal_stow.gd` and
  `config/traversal_weapon_stow.json`: mesh-only back/hip follower.
- `tools/main_mantle_contact_regression.gd`: real commands through main scene,
  supporting-wrist tolerance 3cm, early/middle/late two-angle render, safe one-shot landing.
- `tools/traversal_hand_contact_regression.gd`: existing tall traversal proof now
  also checks visible stow, canonical animation mount and restored held weapon.
- `tools/traversal_contact_input_regression.gd`: missing-slot/source guards,
  per-slot bounds, modern/legacy evaluated-time segment mapping.
- `tools/agls_mantle_timing_review.gd` and
  `art_source/agls_traversal_review/mantle_timing.json`: offline source measurements.
- Feature contracts: `agls_traversal_presentation.json` updated;
  `traversal_weapon_stow.json` added. Helper checks and limits are in
  `docs/TRAVERSAL_WEAPON_STOW.md`.

Relevant runtime excerpts:

```gdscript
time = lerpf(segment_start, segment_end, float(presentation.phase)) * (animation.length - 0.001)
traversal_stow.begin(skeleton, weapon_node, equipped_weapon_family)
```

## Scope and remaining work

The 1.1m thick-platform mantle is the reviewed fixture, not proof for every map
surface or height. Low-vault palm contact remains partial. All imported AGLS clips
are not wired to unsupported states. There is no physical sling strap or authored
hand-to-back stow transition; equipped geometry switches attachment visually.
No browser ZIP was rebuilt, server deployed, or Git branch changed.

The real weapon's pre-existing presentation owner may switch between solver and
animation mounts (`operator_weapon_presentation_owner.gd::use_animation_parent`).
The new helper never reparents the real weapon; tests assert the canonical
animation mount during traversal rather than the pre-traversal aiming mount.

Open this project's `main.tscn` in Godot and enter training to use these changes.
To reproduce the checked map regardless of a stale saved map, launch the installed
Godot with `--path /Users/kiwimango/socom-141-camera-lab --scene res://main.tscn`
and user arguments `-- --camera-regression-map --public-training`.

## Final verification

- Rendered main mantle PASS, supported wrists below3cm, six full-support samples;
  `/private/tmp/mantle-final-clean.log`, early/middle/late/landed images under
  `art_source/traversal_runtime_proof/mantle-*`.
- Rendered actual jump/hang/pull-up/stow/restore PASS, max supported wrist error
  0.0001143m; `/private/tmp/stow-tall-contact-verified.log`.
- Contact input/segment, primary/Mark23 helper, source jump, reload handoff and
  ledge controls regressions PASS. Feature graph gate PASS124contracts.
- Aggregate quick integration stops at branch precondition:
  `FAIL: this is codex/render-deployment; canonical integration is main`.
- Known macOS certificate warning occurs on headless boot; final visual runs
  have no script/parse errors. No multiplayer/full-gate approval is claimed.
