# Traversal and animation completion

Scope: September 12 request and reference screenshots (Relic Depot rocks and
warehouse awning). Active project: `/Users/kiwimango/socom-141-camera-lab`.
No existing browser ZIP is updated by these source edits.

| Task | Status | Evidence / required remaining proof |
| --- | --- | --- |
| Airborne hold/second-tap capture on tested map rocks | Done | Main-scene physical approach on rocks 038 and 040 passes, unsupported 039 north face safely rejects |
| Tall hang, fresh W/Jump-forward climb, S drop, A/D shimmy and one-shot exit | Done | Ledge regression and actual-main jump/contact/landing test pass; broader geometry remains below |
| All requested rocks/containers/awnings | Partial | Safe fixture awning works; actual warehouse front awning at 3.8–3.96m exceeds ground jump+reach ~3.41m, raised-approach gameplay still needs proof |
| AGLS inventory and current-character review workbench | Done | 409 relevant imported AGLS actions, all in 519-action skinned Blender workbench with 110 SOCOM slot actions |
| AGLS runtime integration | Partial | Hang/pull-up now FreeHang; 4 traversal slots use 3 assets. Grab03 reviewed, not wired; ladder retains SOCOM; rope/zipline/narrow ledge states not implemented by importing clips |
| Tall hang/pull-up wrist alignment and body-root timing | Done for tested fixture | Evaluated-time correction, authored-metre residual, per-hand release; two serial rendered contact passes, latest max supported-wrist error 0.000133m against 0.03m limit |
| Thick-platform AGLS mantle | Done for tested 1.1m fixture | Walking01 .30→1.0 segment, per-slot root/contact, real-main input, supported wrist contact below3cm, two-angle early/middle/late and one-shot landing pass |
| Low-vault palm contact | Partial | Real-main vault crosses and lands, but supporting hand floats; separate vault-root/contact calibration still required |
| Equipped rifle stow during traversal | Done for tested rifle | Back-mounted cosmetic copy during hang/pull-up/mantle; restored held weapon, real weapon owner unchanged. Actual Mark23 helper test passes; pistol placement not separately rendered. No strap simulation or authored stow-hand animation |
| Universal feet/palm contact and oblique/irregular geometry | Partial | Tall fixture inspected both sides; no universal foot collision/hand-top solver or every-rock guarantee |
| SOCOM source conversion and current-skin editable actions | Partial | Original 264 source Actions preserved; current saved SOCOM references covered in workbench. Editable retarget is not a new authored recreation or approved runtime replacement; exact Godot parity remains false (22/16mm wrist difference) |
| Shared traversal timing | Partial | Hang/pull-up and Walking01 mantle segment/acquire/release saved and tested; no combat/jump physics changes. Low-vault contact timing still unfinished |
| Browser export / actual user build verification | Not started | Current native sources tested; no refreshed ZIP, no confirmation of the user's running build |

Owners: CharacterBody3D movement/collision; existing animation driver and its
post-animation pipeline for presentation. Camera, server weapons/damage,
reload timing and jump physics are protected. No unrelated branch or file reset.

## Play the changed native build

This launches canonical main and explicitly selects the checked-in Relic Depot
map. It bypasses an older saved map or playtest bundle without overwriting either.

```sh
/Users/kiwimango/Applications/Godot-4.7.1.app/Contents/MacOS/Godot \
  --path /Users/kiwimango/socom-141-camera-lab \
  --log-file /private/tmp/socom-traversal-play.log \
  --scene res://main.tscn \
  -- --camera-regression-map --public-training
```

The map flag is implemented in `scripts/main.gd:112` using
`MapDocumentScript.load_path("res://config/maps/current_map.json")` and a session
selection. This is not a browser URL; an old itch ZIP will not contain these edits.

## Editable files and proof

- Current-character workbench: `art_source/traversal_character_workbench/traversal_character_actions.blend`.
- Validation and per-action source list: `art_source/traversal_character_workbench/blender_validation.json`, `inventory.json`, `runtime_inventory.json`.
- Source-only library: `tools/blender/workbenches/seal_full_source_library/socom_source_actions.blend`. Do not confuse its source-bone precision with current-skin interchange parity.
- Real-main frames: `art_source/traversal_runtime_proof/contact-airborne-approach-angle0.png`, `contact-hang-1-angle0.png`, `contact-pullup-5-angle0.png`, `contact-pullup-15-angle1.png`, `contact-pullup-25-angle0.png`, `contact-landing-angle1.png`. Opposite angles also saved.
- Vault evidence: `tools/main_vault_presentation_regression.gd` and `docs/MAP_TRAVERSAL_PROOF.md`; known supporting-palm failure is not hidden by the movement pass.
- Exact file-by-file changes, code excerpts and failure history: `docs/AGLS_RUNTIME_INTEGRATION.md`.
- Full inventory/limitations: `docs/TRAVERSAL_ANIMATION_INVENTORY.md` and `docs/AGLS_TRAVERSAL_CLIP_REVIEW.md`.

## Verification record

Passed individually on installed Godot 4.7.1:

- `tools/traversal_hand_contact_regression.gd`: actual-main physical jump, correct authored full-body pose, 3cm supported-wrist bound, body held stable, single pull-up/landing and weapon restore; final graphical logs `/private/tmp/agls-aligned-forced-render.log` and `/private/tmp/agls-final-two-angle.log`.
- `tools/traversal_contact_input_regression.gd`: absent/invalid contacts, per-hand release, wrong-source guard, bounded residual and exit clear.
- `tools/map_jump_ledge_regression.gd`: held and second-tap actual-map capture plus supported landing and safe rejection.
- `tools/main_vault_presentation_regression.gd`: movement and presentation lifecycle only, not palm-contact acceptance.
- `tools/ledge_climb_regression.gd`: hang controls, ceiling/unsupported/awning safety and ladder lifecycle.
- `tools/source_jump_regression.gd`: source running/scissor-jump contract preserved.
- `tools/reload_handoff_regression.gd`: reload handoff regression preserved.
- `tools/feature_contract_regression.gd`: 124 connected contract graphs.
- `tools/main_mantle_contact_regression.gd`: current 1.1m thick-platform fixture rendered pass, log `/private/tmp/mantle-final-clean.log`.
- `tools/traversal_weapon_stow_regression.gd`: cosmetic-only primary/Mark23, idempotence, unchanged source and clean exit pass. Integrated tall stow/contact passes `/private/tmp/stow-tall-contact-verified.log`.

Aggregate `tools/run_integration_gate.sh quick` stops with
`FAIL: this is codex/render-deployment; canonical integration is main`.
The branch was preserved, not switched to manufacture a green gate. Full
multiplayer/network regression and internet load testing are not claimed.

## Next bounded work

1. Calibrate low-vault source root displacement and supporting palm against the actual obstacle; do not change physics to conceal it.
2. Extend the verified Walking01 low mantle to additional heights and floor-blocked short-ledges, retaining safe eligibility checks.
3. Add reviewed Grab03 entry only with authoritative grab/settle timing and supported hand contact.
4. Prove oblique and raised-platform approaches to real awnings and irregular rocks, then remaining ladder and traversal variants.
5. Resolve Blender/Godot interchange mismatch before claiming exact current-character replacements; export a new browser build only after remaining visual acceptance.
