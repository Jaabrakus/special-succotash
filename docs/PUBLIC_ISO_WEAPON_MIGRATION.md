# Public weapon visual migration — 2026-09-13

## Translation card

- Intent: default and competitive guns use extracted SOCOM II meshes rather
  than the earlier AGLS/placeholder models.
- Acceptance: all twelve existing public identities resolve to their explicitly
  matched source mesh and complete calibrated sockets in canonical main.
  No original profile/rig is deleted. The current M4 default stays M4.
- Owner: existing Gunsmith visual-rig repository/resolver, not a new asset override.
- Must not change: weapon identity, server ballistics/ammo/fire modes, reload
  duration, animation slots, camera/aim, CharacterBody movement, multiplayer pool.
- Proof: compare before/after protected profile fields, source geometry metadata,
  actual main equip and fire, source-arsenal regressions and feature contracts;
  inspect multiple rendered views. Skin-level grip perfection is not assumed.

## Cause and scope

`config/weapons/operator_loadout.json` points at `m4a1.json`, whose published
visual rig still used the AGLS M4. The earlier source-arsenal integration added
43 separate `s2_` selections while explicitly preserving the twelve competitive
IDs. This pass replaces the twelve **visual assignments**, not gameplay IDs or
their balance. Source extras remain selectable. Non-public archived legacy
profiles are not deleted or silently remapped to unrelated source guns.

## System delta

MERGE source mesh/calibration into newly named published visual rigs consumed
by the existing resolver. Before: correctness 2, ownership 5, parity 3, editor 4,
performance 5, coverage 3. Candidate: correctness 4, ownership 5, parity 5,
editor 4, performance 5, coverage 4. Evidence: default loadout, original public
profiles, source arsenal recipes, and canonical equipment regression.

The M4 contact-surface prototype is tied to the AGLS mesh by `expected_model`.
Its correction was not visually accepted and is off. Do not reuse that collider
on the differently shaped ISO M4; source contact geometry needs a fresh fit.

## Applied inventory and exact files

The only edits to each existing `config/weapons/<id>.json` are
`visual_rig_id` and, where absent, `visual_rig_schema_version`. All twelve
authored profiles were compared against HEAD with only those keys removed:
every other key and value is unchanged. Older published rig files remain intact.

| Existing ID | New published visual rig (config/weapon_visual_rigs/) | Source selection |
| --- | --- | --- |
| mark_23 | iso_public_mark_23_v1.json | s2_mark_23 |
| de__50 | iso_public_de__50_v1.json | s2_de_50 |
| m9 | iso_public_m9_v1.json | s2_m9 |
| m4a1 | iso_public_m4a1_v1.json | s2_m4a1 |
| m16a2 | iso_public_m16a2_v1.json | s2_m16a2 |
| ak-47 | iso_public_ak_47_v1.json | s2_ak47 |
| aks-74 | iso_public_aks_74_v1.json | s2_aks74 |
| hk5 | iso_public_hk5_v1.json | s2_hk5 |
| m14 | iso_public_m14_v1.json | s2_m14 |
| m40a1 | iso_public_m40a1_v1.json | s2_m40a1 |
| 870 | iso_public_870_v1.json | s2_870 |
| m60e3 | iso_public_m60e3_v1.json | s2_m60e3 |

Inventory/provenance: `config/public_iso_weapon_migration.json`. Read-only
patch producer: `tools/prepare_public_iso_weapon_migration.cjs`; it accepts one
ID or `--manifest`, never writes files itself, and refuses overwriting new rigs.
Existing family fallback assignments were included in the before-state,
not just explicit weapon assignments. New rigs retain that resolved handling
dictionary while using the matching source mesh and its socket calibration.

Integration contract: `config/feature_contracts/public_iso_weapon_visuals.json`.
Focused proof: `tools/public_iso_weapon_migration_regression.gd`.
The old contact experiment's contract/test now verify ISO-model isolation:
`config/feature_contracts/m4_grip_surface_probe.json` and
`tools/m4_grip_surface_main_regression.gd`.

Exact active chain:

```json
// config/weapons/m4a1.json:2
"visual_rig_id": "iso_public_m4a1_v1"
// config/weapon_visual_rigs/iso_public_m4a1_v1.json:9
"model_fbx": "res://assets/weapons/socom2_arsenal/s2_m4a1.scn"
```

```gdscript
# scripts/weapons/weapon_rig_contract.gd:62
var config := VisualRigResolver.resolve_for_presentation(raw)
# tools/public_iso_weapon_migration_regression.gd:70, actual main owner
_expect(controller.apply_authorized_weapon_pickup("res://config/weapons/" + weapon_id + ".json"), "main equip " + weapon_id)
```

## Verified outcome / limits

- DONE: native main and headless main each pass 436 checks. Each equips all 12
  public IDs and accepts firing standing, crouched and prone. Default spawn
  independently verifies source M4 before any test equip. Headless records 108
  early/middle/late samples; native captures 27 samples / 54 images for M4, AK,
  Mark 23. No saved animation, camera or gameplay profile is overridden.
- DONE: source arsenal 1506 checks; public roster PASS; armory loadout selection
  PASS; protected source-animation clocks 3507 checks; feature contracts 162 PASS.
  ISO-vs-AGLS contact-surface guard passes 7 main-scene checks. Scoped diff check
  is clean. Headless macOS certificate warning and voice-input warnings are not
  weapon failures; the native test completed without script errors.
  The short legacy-proxy guard also emitted a resource-in-use warning during
  process teardown (after its PASS); cleanup of that diagnostic harness is not
  treated as proof that gameplay contact fitting is complete.
- PARTIAL: reviewed 27 of the 54 images (nine per weapon, alternating rear/side
  across early/middle/late standing/crouched/prone fire). Source geometry is
  visible, but fingers/thumbs still clip, and stock/shoulder contact is not
  consistently correct. Mesh migration does not fix the current skinned grip.
  M4/AK sampled trigger/support marker gaps stay below 1 mm; those marker
  measurements demonstrably do NOT prove skin contact. The Mark 23's early
  crouched raise shows about 20 degrees of barrel/reticle mismatch, settling to
  about 0.46 degrees at the late sample. This pass does not claim instantaneous
  pistol raise/aim parity or alter its action timing to mask that limitation.
- NOT DONE: migration of non-public archived profiles, world-colliding guns,
  full physical finger grasp, remote multiplayer testing, export/deployment.
- Aggregate integration gate remains unavailable on `codex/render-deployment`:
  `FAIL: this is codex/render-deployment; canonical integration is main`.
  Branch and dirty worktree preserved; no Git push/branch switch performed.

Proof archive: `art_source/public_iso_weapon_migration_20260913/` contains native
images, measured JSON and test logs. It is excluded from Godot import/export.
The initial test compared raw/normalized socket dictionaries and failed;
comparing actual Vector3 coordinates resolved that test representation issue.

## Play the actual updated build

Open `/Users/kiwimango/socom-141-camera-lab/project.godot` in Godot and run the
project (F6/current-scene is not the main-game proof; use F5/main). Start Training
and select an existing public gun: the M4 default already resolves to source.
Restart the running game process when ready so cached published rigs reload.
The user's running game was not restarted by these tests. Existing browser
ZIPs, itch uploads and dedicated server exports were NOT rebuilt or deployed.
`/Users/kiwimango/Documents/SOCOM-141` is a symlink to this same main folder.
