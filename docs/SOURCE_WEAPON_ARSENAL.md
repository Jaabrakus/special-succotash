# Extracted SOCOM II arsenal

## Translation card

- Player intent: select and use all extracted firearm meshes and their original textures.
- Acceptance: explicit source firearm entries equip in `main.tscn` through the existing armory/controller/attachment chain. All 59 converted models are accounted for; LODs and alternate optics are not piled together.
- Owner: `SocomWeaponCatalog` for selectable identity; existing `SocomWeaponRigContract`/`OperatorAssetRuntime` consume saved presentation. The builder is offline only.
- Protected: existing weapon profiles, loadout, twelve-weapon competitive pool, camera, movement, animation state ownership, shot/damage authority and concurrent source damage/camera work.
- Proof: `source_weapon_arsenal_regression.gd`, catalog/armory regressions, feature contract gate, canonical equipment loop and rendered contact sheet.

## Scope and evidence

`config/source_weapon_arsenal.json` is an explicit identity and calibration recipe, not a fuzzy name mapper. `tools/build_source_weapon_arsenal.gd` produces native scenes with embedded converted meshes/materials, source markers, one high-detail body and only selected scope/silencer parts. Raw v2 files and their manifest remain untouched. The runtime never decodes GLBs or measures meshes every frame.

New `s2_` IDs preserve the existing armory and calibrated weapons. They use existing family animation/gameplay profiles, source cadence/magazine/range metadata, and newly fitted presentation contacts. These are asset integrations, **not verified original shot/damage/animation parity**. The existing source firearm policy is deliberately not expanded by this asset-only work. Standalone launchers, explosive/equipment models, low LODs and thermal scopes remain preserved in the extraction; they are not advertised as functional primary rifles. Underbarrel-equipped rifle geometry does not imply secondary launcher firing.

Source `aimpoint` is sometimes behind the stock or off the bore. It stays an inspection marker; it does not steer the camera. The presented bore uses source +X and the physical muzzle end at the firepoint's height. Grip/support contacts are newly authored on source geometry, not recovered source hand markers. They need human polish across all animations.

## System delta

Warm-up delta: `socom_multiplayer_warmup.gd` previously used the competitive pool for both server selection and received visual updates. Both now use the same `SocomEconomyRules.is_armory_weapon` predicate as the menu. Host/player identity, alive state, lobby phase, selection cooldown, ammo ownership and the twelve-ID tournament pool stay unchanged. Proof: the arsenal's multiplayer receiver/equipment checks plus the focused warm-up eligibility regression. This is an eligibility correction, not a new networking or weapon owner.

Decision: MERGE. Add saved profiles and scenes to the existing catalog; reject a new equipment or damage owner.

| Criterion (0–5) | Before | Candidate | Evidence |
| --- | --- | --- | --- |
| Correctness | 1 | 4 | v2 manifest says runtime mounts not integrated; new recipes identify exact model/part selections |
| Ownership | 5 | 5 | existing catalog, weapon contract, attachment and controller stay owners |
| Runtime parity | 1 | 5 | armory -> saved profile -> canonical equipment consumer |
| Editor usability | 2 | 4 | saved complete profiles are editable through existing Gunsmith |
| Performance | 5 | 5 | offline native scenes; no runtime mesh search or GLB conversion |
| Regression coverage | 2 | 4 | extraction proof plus new coverage/equip regression |

Godot 4.7.1 used. Scene generation follows the official [GLTFDocument](https://docs.godotengine.org/en/stable/classes/class_gltfdocument.html) and [PackedScene ownership](https://docs.godotengine.org/en/stable/classes/class_packedscene.html) contracts.

## Verification, 2026-09-13

- `source_weapon_arsenal_regression.gd -- --runtime`: PASS, 1,420 checks, all 43 canonical equips. All 39 firearm models plus 20 explicit non-firearm/launcher exclusions cover the 59-model manifest.
- `source_weapon_arsenal_network_regression.gd`: PASS, all 43 selections traverse real local ENet request -> server validation -> client receive. Both network actors use the source mesh; server magazine/cadence agree with the saved profiles. Unknown IDs/peers, cooldown and live-match lock remain enforced.
- `core_weapon_roster_regression.gd`: PASS. `armory_loadout_selection_regression.gd`: PASS, 55 actual menu entries. Existing twelve competitive choices unchanged.
- `source_firearm_policy_regression.gd`: PASS, 4,216 checks; existing 32 policy identities preserved, asset variants explicitly use project tuning.
- `feature_contract_regression.gd`: PASS, 148 contracts.
- Rendered all-weapon sheet and 56 canonical side/rear frames across seven representative weapons, standing/crouched idle/fire. Capture preservation passed. This is **not** a universal hand-fit pass: source Mark23 support-hand marker gaps reached 0.158 m in crouched fire; the inherited source-pistol pose bypasses the generic contact solve. Rifle fingers also need visual polish despite submillimetre palm-marker errors. No source animation/IK owner was replaced to hide this.
- Canonical headless baseline boot passed. Existing voice-capture and shutdown object-leak warnings remain. The quick integration gate refused the current `codex/render-deployment` branch because it requires `main`; no branch switch, commit, push or deployment performed.

Representative implementation excerpts:

```gdscript
# scripts/weapons/socom_weapon_catalog.gd::_append_source_arsenal
profile["armory_eligible"] = true
profile["competitive_eligible"] = false
records.append(profile)

# scripts/network/socom_multiplayer_warmup.gd::_server_choose_warmup_weapon
if not operators[peer_id].alive or not ArmoryRules.is_armory_weapon(ArmoryRules.weapon_record(weapon_id)):
    return false
```

Restart the game to refresh the cached catalog. Open the equipment picker and choose a `SOCOM II · ...` item under its normal weapon category. Existing equipped loadout remains unchanged. Native arsenal scenes total approximately 1.9 MB; raw source parts remain available separately.
