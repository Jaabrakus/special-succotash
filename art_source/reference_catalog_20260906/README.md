# Lost-era tactical shooter — PSX reference catalogue

Research date: 2026-09-06. This is a proposed art checklist and reference shortlist,
not a shopping order, imported asset library, approved license register, or final
inventory of everything missing from the game.

Follow-up: the nine highlighted entries now have live public-API download/license
checks in the [asset intake queue](/Users/kiwimango/socom-141-camera-lab/art_source/sketchfab_intake_20260906/README.md).
Eight require authenticated Sketchfab downloads; the survival pack points to Fab.
Follow-up intake: the user has now supplied eight sets. Six are prepared as
editable glTF and Godot-import-tested staging copies; two have license holds.
See the [preparation report](/Users/kiwimango/socom-141-camera-lab/art_source/sketchfab_intake_20260906/prepared/README.md).
The original catalogue below remains reference research, not a production approval.

## Scope and evidence

Translation card: collect references for the user's SOCOM-inspired game-as-relic
direction; cover shared tactical assets and several biome kits; provide source
links, creator names, visible license labels, and unresolved gaps. The sole owner
is this research document. Approved weapon meshes, character rig, gameplay,
camera, collision, damage, animation, networking, and saved profiles must not
change. Proof is the linked listing evidence and a complete category checklist,
not an engine test.

The original [Sketchfab PSX search](https://sketchfab.com/search?q=psx&type=models)
did not load in the research browser. Individual-page opening attempts also
encountered 403 responses, cache misses, or a JavaScript verification screen.
This catalogue therefore uses searchable, indexed Sketchfab listing text. Model
titles, creators, counts, and license labels below are reported by those listings;
they have not been independently checked in downloaded files or the live 3D
viewer. The search index may be stale. No model or texture was downloaded.

Delta decision: KEEP the approved art and runtime; MERGE a reference catalogue
only. There is no candidate runtime implementation to score, so correctness,
ownership, parity, editor usability, performance, and regression scores are N/A.
No gameplay feature contract or integration gate is claimed.

## Art direction

- A lost late-1990s/early-2000s tactical shooter rediscovered, not a literal copy
  of a commercial game's assets, branding, or maps.
- Readable silhouettes, modest geometric detail, restrained color, and compact
  texture detail. PSX is a visual reference, not a new mandatory hardware budget.
- Keep the approved gun shapes. Study real blue-brown patina, surviving black
  finish, rubbed edges, and worn grips. These photos remain the surface anchors:
  [aged Colt](https://collectorsfirearms.com/80058-colt-1911-45-acp-caliber-pistol-with-blue-brown-patina-and-fair-bore-wwi-u-s-army-issue-c3686.html/),
  [used Beretta](https://www.sportsmansoutdoorsuperstore.com/products2.cfm/ID/247745/ber178942z/beretta-92fs-9mm-police-trade-in-pistol),
  and [heavily deteriorated Luger](https://www.gettysburgmuseumofhistory.com/gettysburg-battle/world-war-ii-militaria/original-wwii-german-p-08-luger-eastern-front-battlefield-relic-certified-3/).
- Suggested wear variants: maintained-but-old equipment, long-stored equipment,
  and heavily deteriorated scenery. Use different wear on metal, cloth, wood,
  and polymer; avoid making every object equally damaged.
- Desert and jungle/coast are the user's requested priorities. Urban and
  woodland/snow are proposed extensions, not new approved map commitments.

## Master checklist

Unchecked means a production requirement to track or audit, not proof the asset
does not already exist. Counts and the final map roster still need an art audit.

### A. Characters and wearable equipment — first playable set

- [ ] One canonical operator body and compatible hands; retain the existing rig.
- [ ] Two readable team identities with distinct silhouettes or large color areas.
- [ ] Desert and jungle clothing/gear variants; woodland and cold-weather later.
- [ ] Helmet, soft headwear, vest, pouches, holster, backpack, gloves, boots.
- [ ] Optional night-vision equipment if that visual direction is selected.
- [ ] Matching carried, holstered, and dropped equipment appearances.
- [ ] Civilian/hostage variants only if an escort/rescue mode is approved.
- [ ] Animation coverage audit: idle, walk/run, crouch, prone, aim, fire, reload,
  swap, grenade throw, hit/death, and existing mobility actions. References do
  not establish rig compatibility or authorize animation replacement.

References: R01, R08. A reference operator is not a drop-in replacement skeleton.

### B. Weapons and field equipment — preserve current work

- [ ] Approved pistol families and finish variants; do not rebuild them by default.
- [ ] Rifle/carbine, SMG, shotgun, precision rifle, and machine-gun families.
- [ ] Suppressed and attachment variants where the chosen roster requires them.
- [ ] Separate magazines and relevant animated exterior parts.
- [ ] Frag, flash, and smoke grenade exterior props with distinct silhouettes.
- [ ] Carried/world/pickup versions and matching inventory silhouettes.
- [ ] Radio, flashlight, binocular/designator-style equipment if used by the game.
- [ ] Weapon-family animation/attachment review after any future import.

References: R02–R08. The existing
[43-entry weapon build queue](/Users/kiwimango/socom-141-camera-lab/art_source/socom2_weapon_studies_20260905/WEAPON_BUILD_LIST.md)
remains separate: this catalogue does not claim to find a matching model for
every variant. It also does not make all 43 a mandatory launch roster.

### C. Objectives and training

- [ ] Fictional demolition objective case/device and a clear dropped/carried form.
- [ ] Readable objective-site dressing and original team/site identifiers.
- [ ] Training targets, range tables, target frames, and instructional signage.
- [ ] Objective interaction presentation and HUD icons.
- [ ] Extraction markers and hostage dressing only for a later approved mode.

References: R09, R08, R10. These are exterior art references only, not real-device
construction references or gameplay implementations.

### D. Shared modular architecture

- [ ] Walls: solid, doorway, window, corner, damaged, low cover, and retaining.
- [ ] Floors, flat roofs, sloped roofs, ceiling pieces, ledges, and parapets.
- [ ] Stairs, ramps, landings, ladders, railings, and bridge/deck sections.
- [ ] Separate doors, shutters, gates, frames, bars, and fence pieces.
- [ ] Interior partitions, corridor corners, rooms, and reusable trim.
- [ ] Playable openings and simple collision authored to the map's actual layout.
- [ ] Distant facade shells distinct from enterable buildings.

References: R18–R22, R28. None of the linked building listings proves it is a
complete modular, enterable tactical-map kit. Original modules remain a key gap.

### E. Shared cover, infrastructure, and clutter

- [ ] Wood crates, equipment cases, pallets, and stacked cargo.
- [ ] Metal/plastic drums, fuel cans, tanks, tires, and dumpsters.
- [ ] Shipping containers with closed/open/battered appearances.
- [ ] Sandbag segments, concrete barriers, checkpoint gates, and fence corners.
- [ ] Generators, lockers, pipes, electrical boxes, cables, and utility poles.
- [ ] Signs, street lamps, wall lamps, drains, vents, and rooftop water tanks.
- [ ] Corrugated sheets, broken boards, masonry debris, and sparse trash piles.
- [ ] Camouflage netting, tarps, rope, and tent pieces where a map needs them.

References: R10–R12, R20, R25–R27. Not all clutter should become physical cover.

### F. Desert reconnaissance kit — priority biome

- [ ] Sand/compacted dirt ground surfaces and transitions.
- [ ] Dry rock formations, cliffs, boulders, scree, and distant ridgelines.
- [ ] Sparse scrub, dry grass, dead wood, and selective oasis palms.
- [ ] Original sun-faded plaster/stone compounds with flat roofs and courtyards.
- [ ] Doors, shutters, shade cloth, market/storage props, and corrugated sheds.
- [ ] Weathered checkpoint, communications outpost, and abandoned equipment.
- [ ] Warm daylight, dusk/night palette, dusty air, and an original horizon.

References: R13, R14, R20, R10, R28. The current shortlist does not establish a
suitable desert compound kit or terrain kit; these should be built or researched
specifically, not substituted with unrelated apartment blocks.

### G. Jungle/coastal kit — priority biome

- [ ] Broadleaf trees, palms, ferns, bushes, vines, roots, and ground foliage.
- [ ] Mossy rocks, damp soil, leaf litter, riverbank, and beach transitions.
- [ ] Water surface, shoreline foam, waterfall/stream accents only where needed.
- [ ] Timber huts, corrugated outbuildings, piers, bridges, and dock posts.
- [ ] Boats, mooring ropes, buoys, nets, crates, and coastal storage props.
- [ ] Ruined walls or temple fragments only where they fit the original map.
- [ ] Tropical sky/horizon, humidity haze, and wet-surface variants.

References: R13–R15, R17, R20, R24. R14 supplies a tropical starting point, not
all the broadleaf canopy, vines, and ferns required for a jungle.

### H. Urban/industrial kit — proposed extension

- [ ] Low-rise houses, shops, apartments, warehouse, and utility outbuilding.
- [ ] Alleys, walls, balconies, exterior stairs, roof access, and awnings.
- [ ] Roads, sidewalks, curbs, drains, fences, gates, and utility lines.
- [ ] Containers, parked vehicles, barriers, industrial machinery, and signage.
- [ ] Sparse furnished interiors: desks, shelves, chairs, beds, lockers.
- [ ] Dirty plaster, concrete, brick, asphalt, rusted metal, and broken glass.

References: R10–R12, R18–R23, R25–R26. Existing Morro do Sol art is not replaced
by this research. Background-only shells are unsuitable for playable doorways.

### I. Woodland/cold-weather kit — proposed extension

- [ ] Pine/broadleaf variants, undergrowth, stumps, logs, and exposed roots.
- [ ] Dark rocks, leaf-covered soil, mud, gravel, and snow/ice transitions.
- [ ] Cabin, timber bridge, bunker/outpost, and fencing modules.
- [ ] Snow-cap variants for selected roofs, foliage, props, and rocks.
- [ ] Distinct overcast/cold lighting and distant forest/ridge silhouettes.

References: R13, R15–R16, R28. Snow meshes/materials and cold-weather clothing
remain gaps; a green pine model is not a complete winter asset pack.

### J. Vehicles — scenery first

- [ ] Parked pickup/truck, utility vehicle, civilian car/van, and wreck variants.
- [ ] Coastal fishing boat or small workboat; optional insertion boat.
- [ ] Helicopter or aircraft silhouette only if a chosen map or presentation needs it.
- [ ] Separated wheel/door parts only where visible animation is needed.

References: R23–R24. This checklist does not authorize drivable vehicles, moving
cover, aircraft gameplay, or new movement/network systems.

### K. Surface library, lighting, and effects

- [ ] Consistent texture density, palettes, and filtering across imported/original art.
- [ ] Blue-black steel, patina, scratched paint, aged polymer, cloth, and leather.
- [ ] Desert stone/plaster; jungle wood/moss; urban concrete/brick; snow/ice.
- [ ] Original decals for grime, scuffs, wear, bullet impacts, and fictional signage.
- [ ] Muzzle flash, impact dust/sparks, smoke, grenade effects, and debris sprites.
- [ ] Water splashes, foliage motion, dust/rain/snow where selected.
- [ ] Day/night skies, fog, lighting presets, and distant scenery.

The real photos above anchor wear. Sketchfab model links do not provide a
complete effects, shader, terrain-material, or lighting solution.

### L. UI, audio, and presentation — not supplied by this model search

- [ ] Original title treatment, menu/lobby/loadout art, and team marks.
- [ ] Weapon/equipment icons, reticle, objective markers, and scoreboard elements.
- [ ] Map thumbnails, loading art, briefing imagery, and control prompts.
- [ ] Readable fonts, color-blind-safe team/objective cues, and settings screens.
- [ ] Footsteps by surface, movement/cloth, gunfire, reloads, impacts, and grenades.
- [ ] Biome ambience, radios/communications, match cues, UI audio, and music.
- [ ] Source/creator/license/attribution records for every shipped asset.

These require separate original art/audio or properly licensed sourcing. A
complete game's visual identity cannot be assembled from 3D model links alone.

## Linked shortlist — 28 references

All links below are source citations. Triangles are the listing's displayed
counts, often for a whole pack rather than one asset. They are NOT project
performance targets or measured import costs.

Status legend:

- **Candidate**: worth a later license and file review, not approved for import.
- **Study**: use as a visual reference; no direct production reuse assumed.
- **Hold**: missing or conflicting terms must be resolved before reuse.
- **Store**: the listing points to a separate store; terms/files not verified.

| ID | Source and creator | Use in our checklist | Listing evidence / status |
|---|---|---|---|
| R01 | [PS1/Low Poly Night Vision Special Forces Soldier](https://sketchfab.com/3d-models/ps1low-poly-night-vision-special-forces-soldier-afb42573fa5f4fd2af09c9929d9ccd93) — Jellypack | Operator proportions, equipment silhouette, pose reference | ~1k tris; basic poses/animations described; CC Attribution displayed. **Candidate**, rig compatibility untested. |
| R02 | [Low Poly M4](https://sketchfab.com/3d-models/low-poly-m4-5362b3171e0f422785c0f458f0ce48b1) — AdamKokrito | Carbine silhouette and separate exterior animation parts | ~1.2k tris; Free Standard displayed. **Hold** for exact terms and texture/rig inspection. |
| R03 | [MP5 Navy w/ Flashlight, PS1 Style](https://sketchfab.com/3d-models/mp5-navy-w-flashlight-ps1-style-6d948323e2554b6b8c07dcef08099804) — J | Compact SMG readability and low-resolution detail | 404 tris; 256² texture; CC Attribution-NonCommercial displayed. **Study**, not a cleared commercial asset. |
| R04 | [PSX/PS1 Weapons Pack 1](https://sketchfab.com/3d-models/psxps1-weapons-pack-1-007c85168c494dc287592b288f5eef10) — MelonMan | Consistent low-detail weapon-family treatment | 901 tris displayed for four-weapon pack; separate parts described. No license established. **Study / Hold**. |
| R05 | [PSX Old MAC-10](https://sketchfab.com/3d-models/psx-old-mac-10-1828855ed1744c909d6503bd71a00a6b) — Charckes | Worn weapon finish translated into a tiny texture | 304 tris; 256² texture; Free Standard displayed. **Hold**. No change to our approved meshes implied. |
| R06 | [PSX FN FAL](https://sketchfab.com/3d-models/psx-fn-fal-9c39c3bd93bd459aa1bbf357c90e6d5c) — Charckes | Long-rifle readability and material separation | 490 tris; 256² texture; Free Standard displayed. **Hold**. Style reference, not an addition to the weapon roster. |
| R07 | [Hand Grenade \| PS1 Low Poly](https://sketchfab.com/3d-models/hand-grenade-ps1-low-poly-806cff5378814e1387e5754c2799af99) — youpzdev | Small carried prop with readable silhouette | 327 tris; CC Attribution displayed. **Candidate**. One grenade is not a full frag/flash/smoke set. |
| R08 | [PSX Low-Poly Survival Props Pack](https://sketchfab.com/3d-models/psx-low-poly-survival-props-pack-2d6da94d97a2485189bfc8db5f87f312) — Aquicor | Flashlights, radios, medical/field equipment | ~3.5k tris displayed; author describes a free Fab pack. **Store**, exact license and included files not checked. |
| R09 | [PSX C4 Explosive](https://sketchfab.com/3d-models/psx-c4-explosive-eafe8e0078c14a568dbc76f1715c73fc) — apispride00 | Fictional demolition-objective prop styling only | ~12.3k tris; Free Standard displayed. **Study / Hold**; much denser than a tiny objective prop needs to be. |
| R10 | [PSX Industrial Pack](https://sketchfab.com/3d-models/psx-industrial-pack-12cb749961974f94a4063e67dafb2d76) — Tomitos | Shared crates, barrels, tires, debris, generators, lockers, pipes, containers | ~8.6k tris displayed; 512² texture; CC Attribution displayed. **Candidate**. Strongest shared-prop lead by listed contents. |
| R11 | [psx shipping containers 2](https://sketchfab.com/3d-models/psx-shipping-containers-2-c4a68cee7a184f15a553a9d53d66f94e) — Arrangemonk | Cargo yard/coastal cover and photo-textured wear | 128 tris; photo-derived textures described; CC Attribution displayed. **Candidate**; verify texture provenance and openable parts. |
| R12 | [PSX Style Barricade Pack](https://sketchfab.com/3d-models/psx-style-barricade-pack-e0b5922b28094417863b31614ce5a48f) — wooolvie | Checkpoint/barrier silhouettes | ~69.5k tris displayed; author attributes most density to barbed wire. CC Attribution displayed. **Candidate**, simplify wire if later selected; not performance-approved. |
| R13 | [Rocks - PSX Low Poly](https://sketchfab.com/3d-models/rocks-psx-low-poly-4a9020e1803444c7aa79a6272a7d09b9) — Drops | Shared rock family; mossy examples for jungle | 224 tris displayed; five rocks, three mossy. CC Attribution label conflicts with prose saying credit optional. **Hold**; retain attribution and confirm terms. |
| R14 | [PSX Tropical Pack V1](https://sketchfab.com/3d-models/psx-tropical-pack-v1-831f5ce303354977a6acb695571ac01b) — PROJEKTSANSSTUDIOS | Jungle/coast/oasis starting vegetation | ~3.8k tris displayed; palm/coconut tree, coconut, rock, bush, grass. CC Attribution displayed. **Candidate**. |
| R15 | [PSX Low-Poly Trees, Rocks & Vegetation Pack](https://sketchfab.com/3d-models/psx-low-poly-trees-rocks-vegetation-pack-c633acf5a84344feaddd62ecb6cb3bb5) — Aquicor | Broader foliage family and consistent outdoor style | ~20.3k tris displayed; linked paid Fab pack. **Store**; species, terms, and per-object cost need review. |
| R16 | [Psx Tree Low Poly (No black Background)](https://sketchfab.com/3d-models/psx-tree-low-poly-no-black-background-7ac44f5eb88e4eb6a3fe9b20e626de35) — RoyalGeek | Woodland pine and foliage-card reference | 72 tris displayed; Free Standard displayed. **Hold**; alpha handling and winter variants untested. |
| R17 | [PSX Temple Island](https://sketchfab.com/3d-models/psx-temple-island-2ed1d1300b3a41e28009efe369262baf) — Seifert | Coastal terrain, ruins, caves, vegetation composition | ~57k tris for full scene; GLB described; CC Attribution displayed. **Study** for art composition, not a preapproved playable map. |
| R18 | [PSX Houses](https://sketchfab.com/3d-models/psx-houses-c535b11378194028b5410e4e60afdad5) — domi | Small-building proportions and town variety | ~2.7k tris displayed. Description says CC0; license field says Free Standard. **Hold** until the mismatch is resolved. |
| R19 | [PSX - Normal Building](https://sketchfab.com/3d-models/psx-normal-building-3418208ac2814d8fb443317848e5c8d8) — Kasugay | Distant urban facade/background scale | 12 tris displayed; background scenery described; CC Attribution displayed. **Candidate for background only**, not enterable architecture. |
| R20 | [Small Abandoned House (PSX)](https://sketchfab.com/3d-models/small-abandoned-house-psx-010461005f534c559f71421505e605ed) — Kasugay | Corrugated sheds and aged outbuilding vocabulary | 262 tris; creator says commercial/personal use allowed and links a pack. No formal terms established. **Study / Hold**. |
| R21 | [PSX/PS1 Big Warehouse](https://sketchfab.com/3d-models/psxps1-big-warehouse-4cdf4bf29db040c793278263a5807026) — Wardster | Industrial space and low-resolution surface reference | 750 tris; 256² texture; custom collision described. CC Attribution-NonCommercial displayed. **Study**, not cleared for commercial reuse. |
| R22 | [PSX Soviet Panel Building (Khrushchyovka)](https://sketchfab.com/3d-models/psx-soviet-panel-building-khrushchyovka-5a1115e851054a468fc19fdefdf4726e) — Kasugay | Cold urban district/backdrop scale | 28 tris; L-shaped apartment shell described; external pack link. No license established. **Study / Hold**, background only. |
| R23 | [Truck Psx \| Low Poly](https://sketchfab.com/3d-models/truck-psx-low-poly-b5aece830f74464a89f239d656d9b4b3) — liltoba | Parked vehicle silhouette and map dressing | 568 tris; CC Attribution displayed. **Candidate**; no rig, interior, or drivable behavior established. |
| R24 | [Low Poly Old Rusty Fishing Boat](https://sketchfab.com/3d-models/low-poly-old-rusty-fishing-boat-3713c37983ea4c04b87fe173e2631b76) — Ottto3d | Coastal workboat and localized weathering | ~10.5k tris; 2K/4K PBR maps; CC Attribution displayed. **Study / Candidate for adaptation**; not a native PSX match. |
| R25 | [PSX - Radio](https://sketchfab.com/3d-models/psx-radio-e01f21b49c4f438497770ef01e319462) — Kasugay | Old communications-room dressing | 224 tris; creator says commercial/personal use allowed with credit. Formal license not established. **Study / Hold**. |
| R26 | [PSX Computer Case](https://sketchfab.com/3d-models/psx-computer-case-c57492c2b6684fecad9617257ea86474) — Voidy Entertainment | Old command-room computer appearance | 20 tris; CC Attribution-NonCommercial displayed. **Study**. Case only, not a complete workstation. |
| R27 | [Sandbags - Defense line](https://sketchfab.com/3d-models/sandbags-defense-line-e1a4c79a1c5e49bc830746be10dbe1c6) — Evan | Defensive-cover arrangements and fabric shape | ~165.1k tris across the displayed set; CC Attribution-ShareAlike displayed. **Study**; geometry density and license obligations need separate review. |
| R28 | [WW2 Field Bunkers Pack](https://sketchfab.com/3d-models/ww2-field-bunkers-pack-f7077ed4ad494b31a50c691c12d13a71) — Golden | Concrete outpost/fortification massing | ~1.3k tris displayed; realistic low-poly bunkers described. Store listing, no current license confirmed. **Study / Store**; adapt period/style only if selected. |

## What to inspect first

1. R10 industrial props: broad reusable coverage for all biomes.
2. R14 tropical pack plus R13 rocks: a compact starting point for jungle/coast.
3. R01 operator: silhouette reference while preserving the canonical rig.
4. R05 worn MAC-10 and R03 MP5: study how age/detail reads at small texture sizes.
5. R11 containers and R12 barricades: cargo/outpost dressing with clear caveats.
6. R18 houses and R20 shed: style leads; build original playable modules to fit maps.

## Gaps to resolve before claiming a complete art set

- A coherent, enterable desert-compound kit is not found/approved here.
- Dense jungle needs broadleaf canopy, ferns, vines, roots, and ground transitions.
- Snow/cold-weather assets, river/shoreline surfaces, and horizon art are not covered.
- Flash/smoke grenade references, complete team kits, and matching civilian assets
  need a focused follow-up if their game roles are confirmed.
- No matching reference has been checked for each entry in the 43-weapon queue.
- Bridges/piers, utility poles/cables, team signage, and training fixtures still
  need a coherent selection rather than unrelated one-off downloads.
- UI, audio, animation compatibility, FX, and all engine integration remain separate.

## Reuse review before any future import

The license column records visible labels only; it is not legal clearance.
For a selected model, check the live listing and actual downloaded terms,
creator identity, texture provenance, permitted use, required attribution,
and any non-commercial, ShareAlike, NoDerivatives, or NoAI restrictions.
Do not treat Free Standard as CC0 or an unknown label as permission.
Do not use ripped commercial-game characters/maps merely because an uploader
offers a download. Do not feed NoAI-tagged art into image-generation workflows.

Only after selection and rights review: inspect scale/origin, textures, material
count, mesh density, UVs, separate parts, collisions, and rig compatibility.
Test selected art beside the existing character and weapons in the actual game
camera. No single triangle count or 'game-ready' claim proves suitability.

## Existing project context used for scope, not runtime verification

- [Production roadmap](/Users/kiwimango/socom-141-camera-lab/docs/COMMERCIAL_PRODUCTION_ROADMAP.md):
  planning context for a canonical operator, focused weapons, demolition, maps,
  training, and asset provenance. No completion status is inferred here.
- [Morro do Sol art-direction note](/Users/kiwimango/socom-141-camera-lab/docs/maps/MORRO_DO_SOL_V2_ART_DIRECTION.md):
  context for original compound architecture and protected playable routes.
- [Approved weapon study](/Users/kiwimango/socom-141-camera-lab/art_source/socom2_weapon_studies_20260905/photo_match_v2/README.md)
  and [optional finish study](/Users/kiwimango/socom-141-camera-lab/art_source/socom2_weapon_studies_20260905/relic_finish_v3/README.md):
  retained art work, not replaced by the external references above.
