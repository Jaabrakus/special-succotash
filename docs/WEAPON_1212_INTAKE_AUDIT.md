# 1212 weapon intake audit — 2026-09-06

## Runtime-candidate translation delta

Player intent: integrate the two confirmed family matches, 9mm_sub/Uzi and 870/pump, through the same saved visual rigs and Equipment consumer as existing firearms. Acceptance: preserve the measured meter-scale model, seven geometry contacts and weapon mechanics; produce self-contained Godot scenes without first-person arms, source-pack dependencies or a whole-project import; require physical and native standing/crouch/prone, movement/fire/recovery/reload proof before changing a runtime pointer. 12_gauge_pump remains separate pending equivalent proof. Existing AK/M4 and unmatched firearms retain their models.

Owner: GunsLab2VisualRigContract/Resolver and canonical operator Equipment presentation. Protect damage, ammunition, sounds, action clips and timing, movement, camera and server authority. The inspection/build tools create assets and immutable unassigned candidate rigs only; no alternate runtime loader or solver. Prior provisional mounting and palm rotations may change only when native model-specific evidence demonstrates their mismatch. Geometry-authored contacts are not copied from another gun to force a pass.

The Uzi's actual barrel pair is 0.0601628 m. A 0.15 m physical-length restriction incorrectly rejects a nondegenerate direction. Replace that check with an explicit 0.00001 m numerical separation floor, preserving every finite-vector, required-socket and human contact bound. Focused tests must accept this real short pair, reject zero/near-zero and nonfinite pairs, and retain long-gun validity. No fictitious root relocation.

Six-axis delta (0–5): correctness 2→4 provisional, ownership 5→5, canonical parity 4→5, editor usability 4→5, performance 4→4, regression coverage 3→5. **MERGE conditional on physical/native proof**; keep the candidates unassigned if any required pose fails. Source blend/GLB files remain unchanged; derived self-contained scenes are reproducible artifacts.

Pump fit delta: the first actual-input run at the original center-of-pump contact X=0.35 m overextends the support arm (about178 degrees, up to54.7 mm contact gap) and compresses the right elbow below42 degrees. Native source overlay `870-right.png` shows the real wood pump extends behind that center. Test a surface-ray contact at its rear third, X=0.275 m, and a modest saved ready-pocket downward adjustment0.065 m. Preserve the mesh, scale, trigger contact, barrel/stock geometry and every anatomy threshold. This changes only the unassigned pump candidate; source draft remains the original geometry witness. **MERGE only if physically/natively proven**—never move a marker off the modeled pump to make a numerical test pass.

Second pump fit delta: X=0.275 leaves the support elbow above150 degrees, so use the actual rear pump surface at X=0.25. The ready pocket API explicitly caps its additional drop at0.07 m; retain that cap instead of widening it. The grip close-up shows the original trigger-palm point lies toward the rear of the wooden wrist. Evaluate the same visible grip surface 2 cm forward (X=-0.02, Y=0.055) so the palm/finger-root anchor sits closer to the trigger, retaining original stock geometry. Both changes are ray-cast against actual original mesh triangles and require a native hand review. No off-surface targets, larger arm bounds or changed bone lengths are accepted.

## Translation card

### Bounded all-state attribution follow-up

Player intent: do not publish replacement models with a bad prone or stop transition. Acceptance: exercise the existing unconnected prone experiment through all 180 recovery frames on each prepared model; record its exact source revision and every failed floor/contact/anatomy check, without accepting only the ready frames. Attribute the pump's final reload support gap using read-only final-frame state plus an explicitly labeled, in-memory full-weight support-solve counterfactual. Compare old and new model geometry under identical candidate handling profiles through the same canonical movement fixture to separate asset effects from shared crouch-stop behavior. Owner remains the existing weapon presentation or locomotion owner; this follow-up adds only temporary derived probes, not an alternate runtime owner. Protect every runtime/config pointer, source helper owned by the root task, gameplay timing, bone length, human thresholds and native-visibility assertions. Focused proof is revision-stable JSON plus native side/rear images for the same stop states. **MERGE diagnostic evidence only; REJECT publication while required failures remain.**

- Player intent: use correct-looking supplied weapon models while keeping the existing firearm identities and verified animation work.
- Acceptance: identify every supplied asset category, distinguish real identity evidence from resemblance, and list exact candidate paths, missing models, and integration hazards before any replacement.
- One system owner: `SocomWeaponRigContract` through `GunsLab2VisualRigResolver`; this audit reads that existing owner and creates no alternate presentation path.
- Must not change: runtime, profiles, weapon roster/names, grips, animation, camera, physics, damage, source meshes, or imported caches.
- Focused proof: all 97 FBX metadata records parsed; 13 base/prop FBX files inspected in Blender memory; all 10 primary `.blend` files opened with scripts disabled; four rendered previews; canonical Godot normalized weapon catalog read. No Godot import of `1212` was performed.

## Contents, not 97 different guns

`1212` is approximately 730 MB, containing 130 files:

| Format | Count | Meaning |
| --- | ---: | --- |
| `.fbx` | 97 | 71 first-person arm rig/animation files; 22 gun/part/projectile files; 3 FX meshes; 1 blockout file |
| `.blend` | 10 | Four guns, projectiles, first-person arm base, four first-person weapon animation scenes |
| `.blend1` | 10 | Blender backup copies, not new weapon variants |
| `.png` | 12 | Four gun albedos, four silhouettes, arm albedo, projectile albedo, two FX textures |
| `.pdf` | 1 | Pack readme; asset metadata/reference, not task instructions |

There are **four distinct base guns**. No AK-family model, sniper rifle, machine gun, launcher, throwable, or full-body player animation is supplied here.

## Exact base model paths and measured geometry

All lengths below are Blender's imported world-space bounds in meters, including the FBX object's 0.01 unit conversion. They are measurements, not desired final gameplay scale. Triangle counts exclude separately supplied magazines.

| Base asset | Exact source path | Length | Triangles | Part bones |
| --- | --- | ---: | ---: | ---: |
| Pistol_01 | `1212/RetroWeaponsPack/Guns/Pistol_01/FbxFiles/Pistol_01.fbx` | 0.224 m | 1,955 | 5 |
| Rifle_01 | `1212/RetroWeaponsPack/Guns/Rifle_01/Fbx_Files/Rifle_01.fbx` | 0.830 m | 7,177 | 9 |
| SMG_01 | `1212/RetroWeaponsPack/Guns/SMG_01/Fbx_Files/SMG_01.fbx` | 0.722 m with stock/suppressor | 2,877 | 7 |
| Shotgun_01 | `1212/RetroWeaponsPack/Guns/Shotgun_01/FbxFiles/Shotgun_01.fbx` | 0.942 m | 1,668 | 6 |

Rendered inspection shows a 1911-style hammer pistol, modern AR-pattern carbine with a full-length rail, Uzi-style grip-magazine SMG with folding stock and suppressor, and wood-stock pump shotgun. These descriptions are visual classifications, **not manufacturer-confirmed names**. Object names and the readme contain only generic pack labels.

## Existing weapon ID → candidate mapping

No source establishes a verified exact real-model identity, so none should be relabeled as an exact match without that qualification.

| Existing ID | Candidate base above | Confidence and boundary |
| --- | --- | --- |
| `9mm_sub` | SMG_01 | Strong Uzi-family resemblance. Existing `config/weapons/9mm_sub.json:38` explicitly says `"model_name": "uzi"`. Exact variant remains unconfirmed. Pack visibly includes a separate suppressor, while current profile has `"is_silenced": false`; an unsuppressed presentation must exclude that supplied part rather than silently change gun balance. |
| `870` | Shotgun_01 | Strong generic wood-stock pump resemblance; no source text proves Remington 870 identity. Plausible replacement candidate after hand/pump/muzzle calibration. |
| `m4a1` | Rifle_01 | Strong AR-family resemblance, only moderate M4 identity confidence: the supplied gun is a modern full-rail carbine, not a documented M4A1 model. Existing AGLS M4 is already a named/calibrated model; do not replace automatically merely because this pack is new. |
| `12_gauge_pump` | Shotgun_01 | Pump-family resemblance only. Existing record specifically references Mossberg 590; no evidence establishes this mesh as a Mossberg. Retain existing until a deliberate generic-art choice. |
| `m4a1_sd`, `m4a1-m203` | Rifle_01 base only | Not complete variants: this pack supplies no matching rifle suppressor or M203. Not direct replacements. |
| `m16a2`, `m16a2-m203` | None | Supplied carbine does not represent the existing long/fixed-stock rifle or launcher variant. |
| `mark_23`, `mark_23sd`, `de__50`, `m9`, `model_18`, `f57`, `226`, `9mm_pistol` | None | Generic 1911-style pistol does not establish any of these identities. `9mm_pistol` is explicitly `hkp9s` in its existing source metadata. Do not give every pistol the same new mesh. |
| `ak-47`, `aks-74`, `552`, `m14` | None | No corresponding family/model supplied. |
| `hk5`, `hk5sd`, `f90` | None | Uzi-style SMG is not an HK5/HK5SD/F90 model. |
| `m60e3`, `m63a`, `mark_46_mod_0` | None | No machine gun supplied. |
| `m40a1`, `m82a1a`, `m87elr`, `sr-25`, `sr-25_sd` | None | No sniper rifle supplied. |
| `m3_12_gauge`, `ta_12_gauge` | None | Wood-stock pump does not match the existing Jackhammer/SPAS-12 prototype identities. |

The eight developer-only generic profiles (`assaultrifle_1` through `_4`, `bullpup_1`, `shotgun_1`, `sniperrifle_1`, `submachinegun_1`) are not additional named public guns. A generic preview could use an appropriate pack class, but that does not prove an identity match. `designator`, `mk_3-a2`, `air_to_ground_missile`, and `exploding_fuel` remain non-firearm/effect records even though old profiles reference placeholder firearm meshes.

## Canonical roster and current-model findings

At audit time, `config/weapon_roster_extensions.json:9` exposes 12 named/codenamed guns. The canonical catalog has **33 firearm records** when the three registered shotgun prototypes are included, plus equipment/explosive records. Disk contains 45 weapon-profile JSON files: 33 catalog firearms, eight developer generic guns, and four non-firearm/effect profiles. Catalog item count, sound count, and distinct firearm/model count are different quantities.

Restoring original names/all firearms belongs in the existing catalog metadata owner after pose validation. No roster changes were made by this audit.

Current normalized runtime examples, obtained through `SocomWeaponRigContract.load_config()`:

| ID | Current model | Effective visual rig |
| --- | --- | --- |
| `ak-47` | `res://assets/external/agls_intake/imported/weapons/ak47/ak47.glb` | Authored weapon profile |
| `m4a1` | `res://assets/external/agls_intake/imported/weapons/m4a1/m4a1.scn` | `m4a1_agls_v8` at audit time |
| `870` | `res://assets/weapons/modular_pack/Shotgun_2.fbx` | `family_shotgun_2_v1` |
| `9mm_sub` | `res://assets/weapons/modular_pack/SubmachineGun_4.fbx` | `family_smg_4_v1` |
| `mark_23` | `res://assets/weapons/modular_pack/Pistol_2.fbx` | Authored weapon profile |
| `m40a1` | `res://assets/weapons/modular_pack/AssaultRifle_1.fbx` | Authored profile; wrong rifle placeholder still present despite sniper category |
| `m60e3` | `res://assets/weapons/modular_pack/AssaultRifle2_1.fbx` | `family_rifle_552_v1`; placeholder rifle model remains |
| `mark_46_mod_0` | `res://assets/weapons/modular_pack/AssaultRifle2_3.fbx` | `family_rifle_aks74_v1`; placeholder rifle model remains |

The intake does not supply models to correct those last three mismatches. Preserve them as known remaining model work rather than claiming this pack fixes them.

The authoritative merge is `scripts/labs/gunsmith2/weapon_visual_rig_contract.gd:112`:

```gdscript
for field in VISUAL_FIELDS:
    if visual.has(field):
        result[field] = _clone_value(visual[field])
```

`handling_profile` is one of those complete replacement fields. Thus copying an entire rifle visual rig onto every weapon would also replace pistol/long-gun animation handling. Shared corrected motion needs a deliberate family-aware merge; new geometry needs its own calibrated visual rig.

## Import hazards and usable parts

1. **Missing textures on direct import.** Every base FBX references old nonexistent image paths/names. Actual files are `Guns/<base>/Textures/<base>_Albedo.png`. Rifle incorrectly references `Rifle_Albedo_Detailed.png`; SMG `SmallSMG_Albedo.png`; shotgun `Shotgun_Albedo.png`. Additional magazines reference nonexistent `Projectiles_Mat_2D_View.png`; use the supplied `Guns/AdditionalMeshes/Projectiles/Texture/Projectiles_Albedo.png` for that material slot. All four temporary previews explicitly rebound only these supplied albedos in memory.
2. **Separate magazines.** Pistol/rifle/SMG base FBXs contain their magazine bone but omit the magazine mesh. The gun `.blend` contains an assembled `Magazine_Mesh`; separate FBX files contain empty/one-round/full alternatives. Direct base-FBX replacement leaves the visible magazine missing. Select one assembled magazine; do not show all alternative meshes at once. Source `.blend` is the cleanest place to inspect original bone parenting/transforms before export.
3. **Units and axes differ from canonical assumptions.** All FBX metadata reports centimeter units (`UnitScaleFactor=1`), imported by Blender with root scale0.01. Gun forward is +X in the inspected Blender world. Shotgun metadata flips `FrontAxisSign` and `CoordAxisSign` relative to the other three. Measure the resulting Godot muzzle direction; do not paste existing grip/rotation values or apply an extra100×conversion.
4. **No authored canonical contacts.** Part bones are `Main`, `Trigger`, `Magazine`, etc. They are not the project's right-palm, support-palm, muzzle, barrel-base, stock, rail, ejection socket contract. Calibrate all seven existing markers to the selected complete model assembly.
5. **First-person rig is different.** FP arms have 63 bones, including `camera`, IK controls and arm twist bones, with no hips/legs. They are not the `mixamorig_*` whole-body rig. Gun part animations can be inspected for slide/pump/magazine timing; FP camera/root motion must not become player/camera authority.
6. **Gun animation files:** pistol BasePose/EmptyMagazine/Fire/Reload; rifle BasePose/Fire/Reload; SMG BasePose/Fire/Reload; shotgun BasePose/Fire/ReloadStep/ReloadEnd. These are part animations, not 14 additional gun models. Any reuse must follow accepted runtime shot/reload events.
7. **One empty rifle object.** `FrontSight_Mesh` has zero vertices; the visible front/rear sights are in `Sights_Mesh`. This is harmless authoring residue but should not be mistaken for missing sight geometry or shipped as extra draw work.
8. **Raw source packaging.** `1212` currently has no `.gdignore`. Its backups, repeated FP animation meshes, Blender files, and PDF should not be copied wholesale into runtime exports. Stage only chosen complete models/textures and preserve the supplied originals.

## System-delta decision

Decision: **REJECT blanket replacement of every current gun with the four pack models**. Keep current unmatched models; evaluate selected class/identity candidates only after the active pose gate passes. No new runtime behavior is accepted by this read-only audit.

Scores (0–5) compare the current canonical presentation path with a proposed uncalibrated all-gun replacement:

| Criterion | Current | Blanket candidate | Evidence |
| --- | ---: | ---: | --- |
| Correctness | 2 | 1 | Current normalized `m40a1`/MG placeholders already mismatch; four generic supplied models cannot represent33 firearm identities. |
| Ownership clarity | 5 | 3 | Current `weapon_rig_contract.gd:59` resolves one visual contract; replacing full handling profiles risks losing family distinctions. |
| Runtime parity | 5 | 0 | Current resolver loads published rigs; `1212` has no authored contacts or runtime mapping. |
| Editor usability | 4 | 1 | Existing published visual rigs are explicit/revisioned; supplied models have missing texture paths and separate magazines. |
| Performance | 3 | 1 | Existing runtime uses selected imported models; raw intake is730MB with97FBX repeated actor/weapon assets. |
| Regression coverage | 3 | 0 | Existing family/weapon regressions exist; no new model has passed canonical stance/contact/shot/reload checks. |

## Evidence artifacts

- `/private/tmp/weapon_1212_inventory.py` and `/private/tmp/weapon_1212_inventory.log`: full FBX metadata and measured geometry.
- `/private/tmp/weapon_1212_preview.py` and `/private/tmp/weapon_1212_preview.log`: four base renders and all10 source `.blend` inventories; autoexec disabled.
- `/private/tmp/1212-Pistol_01-review.png`, `/private/tmp/1212-Rifle_01-review.png`, `/private/tmp/1212-SMG_01-review.png`, `/private/tmp/1212-Shotgun_01-review.png`: supplied textures on base FBXs; separate magazines intentionally not invented/assembled for this inspection.
- `/private/tmp/weapon_1212_roster.gd` and `/private/tmp/weapon_1212_roster.log`: actual canonical normalized IDs/models/rigs and armory eligibility.

Blender5.2.1 native inspection completed. The first sandboxed launch crashed before the audit script executed; native retry succeeded. Godot4.7.1 catalog inspection completed with the environment's known CA-certificate warning. Neither an engine import nor a visual/palm correctness pass for replacement models is claimed.

## Follow-up: two isolated candidates prepared

The root task authorized offline preparation under `docs/WEAPON_1212_CANDIDATE_EXPORT_TRANSLATION.md`. No weapon config, visual-rig assignment, animation policy, or roster was changed. The new `1212/.gdignore` prevents automatic import of the raw pack; the supplied originals remain unchanged.

| Candidate | Artifact | Godot world length | Triangles | Meshes / skins / materials | Embedded images | File bytes |
| --- | --- | ---: | ---: | --- | ---: | ---: |
| Unsuppressed Uzi-style | `assets/weapons/retro_1212/uzi_candidate.glb` | 0.606676 m | 2,907 | 6 / 1 / 1 | 1 | 279,008 |
| Pump shotgun | `assets/weapons/retro_1212/pump_candidate.glb` | 0.942457 m | 1,712 | 6 / 1 / 2 | 2 | 306,960 |

The reusable exporter is `tools/blender/export_retro_1212_weapons.py`. Source mesh vertices, UVs, part skinning, and one assembled magazine are preserved; materials rebind the provided albedos with nearest filtering, roughness1, metallic0, specular0. No FP arms, cameras, lights, custom-script data, alternate magazines, or animation tracks are exported. The source `.blend` SHA256 is checked before/after each export.

Selected Uzi objects: `SMG_01_Armature`, `Main_Mesh`, `Magazine_Mesh`, `Stock_Mesh`, `Trigger_Mesh`, `Knob_Mesh`, `EjectionCover_Mesh`. The separable `Silencer_Mesh` is omitted because existing `9mm_sub` is unsuppressed. Its unused original part bone remains harmlessly in the original skeleton.

Selected shotgun objects: `Shotgun_01_Armature`, `Main_Mesh`, `Forearm_Mesh`, `Trigger_Mesh`, `MagazineLoadingPort_Mesh`, `LoadingPort_Mesh`, `BuckShot_Projectile_Mesh`. The last item is the original chamber cartridge part, not a new gameplay projectile spawner.

**Unit correction lesson:** source `.blend` coordinates were centimeters, unlike already-converted FBX inspection coordinates. A first GLB was oversized; a root-only0.01 correction then exposed inconsistent skinned/unskinned bounds. The final exporter scales the copied assembly by0.01 and applies that scale to the armature and each inherited child in memory before GLB export. This leaves meter-space bones/vertices and consistent Godot world bounds; the two failed preliminary artifacts were replaced. No source was saved.

Final axes: +X barrel forward, +Y up in Godot/glTF. The Blender-to-glTF mapping is `(x,y,z) -> (x,z,-y)`. Each `.intake.json` sidecar includes every source bone head/tail in normalized Blender meters, exact mesh bounds, original source hash, final GLB hash, object selection, and exported triangle/material checks. Convert those bone landmark coordinates with that mapping when designing the canonical sockets; do not mistake the part `Trigger`/`Forearm` bones for a fully calibrated palm contact.

Verification: `tools/retro_1212_asset_regression.gd` **PASS** in headless and native Godot4.7.1. It uses `GLTFDocument.append_from_file()` / `generate_scene()` for only the two selected GLBs, validating embedded textures, all meshes/part bones, skins, no camera/FP content, exact triangle totals, and meter-scale bounds. This is an isolated asset check, not whole-project editor import or canonical operator contact certification. API reference: <https://docs.godotengine.org/en/latest/classes/class_gltfdocument.html>; the invoked methods were verified by the installed4.7.1 runtime.

Independent final views inspected: `/private/tmp/retro1212-preview/uzi_candidate.png`, `/private/tmp/retro1212-preview/pump_candidate.png` (Blender GLB re-import), and corresponding `*-godot.png` native Godot images. Full stock, barrel, wood pump, and SMG magazine are visible and textured. Native proof log: `/private/tmp/retro1212-asset-native.log`; export log: `/private/tmp/retro1212-export.log`.

System delta for **these isolated artifacts only**: **MERGE** with scores correctness4, ownership5, runtime_parity0 (unassigned), editor_usability4, performance4, regression_coverage3. Evidence: exporter allowlists/hashes, sidecar geometry, and the passing artifact regression above. Exact manufacturer identity and canonical hand/contact/reload proof remain outside this acceptance. Existing AK/M4 models and all unmatched weapons are retained.

## Follow-up: seven-socket offline drafts

`art_source/retro1212_calibration/9mm_sub.visual_rig.draft.json` and `870.visual_rig.draft.json` now contain geometry-authored seven-socket drafts, **not runtime assignments**. See the adjacent `README.md` for the exact coordinate table, mesh-ray witnesses, original-bone reasoning, native marker overlays and publication blockers. Existing per-family handling/mount/action data remains provisional and unchanged; no M4 contacts were copied.

`tools/retro_1212_socket_review.gd` passes exact native Godot surface-ray and bore-ring checks against the selected GLBs, with +X bore/+Y sight-up and normalized scale1. Native side/opposite/top/close-up proof is in `/private/tmp/retro1212-calibration/`; the full log is `/private/tmp/retro1212-socket-review-native.log`. No broad source import, profile pointer, canonical rig, animation or source mesh was changed.

The unmodified visual-rig validator passes the pump draft against its actual generated in-memory PackedScene but rejects the Uzi's real60 mm modeled barrel because it currently demands at least150 mm between muzzle and barrel-root sockets (`weapon_visual_rig_contract.gd:225`). The truthful measured root is retained. On-disk GLB import and character-palm/shoulder fitting remain pending for both. **MERGE the offline geometry calibration, REJECT claiming runtime-ready character contact.**
