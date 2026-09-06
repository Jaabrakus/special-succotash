# Relic Depot and ORIGINAL operator palette

## White addition — 2026-09-06

Translation card before edit: intent = add white beside black/green/blue;
acceptance = four distinct cloth colors on the same original visible body;
one owner = SocomOperatorTeamAppearance, consuming the shared appearance JSON;
protected = mesh, rig, animation, dark gear, map, solo default and team colors;
focused proof = four-color rendered palette regression and feature contract gate.

System delta: MERGE one palette entry and white-only brightness, with no new runtime owner.
Current / candidate scores (1–5): correctness 4/5, ownership clarity 5/5,
canonical runtime parity 5/5, editor usability 4/4, performance 5/5,
regression coverage 4/5. Evidence: `config/operator_team_appearance.json`
and `tools/operator_palette_regression.gd`; the existing appearance owner
already accepts arbitrary named palette entries. First rendered check showed
gray instead of white: `assets/shaders/operator_team_cloth.gdshader:11` multiplied
the color by dark source luminance. The bounded correction uses this same owner
and cloth mask, with brightness 4 only for white and 1 for all existing colors.
Regression now also checks that switching white back to either team resets brightness.
Verification: parse PASS after fixing a two-line indentation error; four-color
rendered regression PASS including team brightness reset; blue/green regression
PASS. Render inspected: white cloth with dark equipment, all four original bodies
intact. Headless runs still emit the previously observed macOS certificate warning
(`ret != noErr`); this does not fail the appearance assertions.
API reference: [Godot ShaderMaterial.set_shader_parameter](https://docs.godotengine.org/en/stable/classes/class_shadermaterial.html#class-shadermaterial-method-set-shader-parameter), verified on installed Godot 4.7.1.

Exact shared setting in `config/operator_team_appearance.json`:

```json
"palette_brightness": {"white": 4.0}
```

Exact owner in `scripts/player/operator_team_appearance.gd`:

```gdscript
material.set_shader_parameter("cloth_brightness", float(profile().get("palette_brightness", {}).get(color_name, 1.0)))
```

## Current decision — supersedes the NVG experiment below

The user rejected the replacement character. The original character is restored;
the temporary skin-loader method and active skin_scene setting were removed.
The depot map remains. Four cloth colors are saved in
`config/operator_team_appearance.json`: black (`34383d`), green (`6daf58`), blue
(`579fe8`) and white (`f2f2ed`, cloth brightness 4). `solo_color` defaults to black; network team identity still applies
blue/green through the existing owner. No new player mesh, skeleton or animation
is used. The rejected derivative is preserved in an ignored art folder, not active.

Translation card: intent = original character with color variants; acceptance =
original visible FBX body, zero RelicNVG mesh pieces, 65 runtime bones, four cloth
palette colors; owner = SocomOperatorTeamAppearance; protected = all model geometry,
rig, animation, equipment and game authority; proof = operator_palette_regression,
blue_green_operator_regression, canonical depot regression and rendered lineup.

Exact runtime integration: `scripts/player/operator_asset_runtime.gd`:

```gdscript
TeamAppearance.apply(model_root, 0, String(TeamAppearance.profile().get("solo_color", "")))
```

Exact color owner: `scripts/player/operator_team_appearance.gd`:

```gdscript
material.set_shader_parameter("team_color", palette_color(color_name) if not color_name.is_empty() else color_for(team))
```

The existing shader masks original blue cloth, not neutral straps/mask/gloves.
BoneAttachment3D equipment is excluded. Palette changes are authored through the
shared JSON file; no new in-game color-picker UI is claimed. The palette lineup
is `art_source/relic_depot_integration/original_character_palette.png`.

Current tests: original-body canonical depot regression PASS (126 objects, zero
replacement skin pieces, 65 bones, previous run); four-color rendered regression PASS after
waiting for network initialization; blue/green team regression PASS; feature
contract gate PASS (65 contracts). Rendered lineup inspected: black, green and
blue and white are distinct on the original model. Relic Depot was selected through the
normal local library (`user://maps/relic_depot.json`), with the previous selection
backed up at `art_source/relic_depot_integration/previous_active_map.json`.
The broad quick gate remains blocked by the existing non-main
branch; no branch change is authorized. Earlier NVG screenshots below are
historical evidence only, NOT the current player.

## Historical NVG experiment and map construction record

First playable development version, 2026-09-06. Not a release certification.

Bounded environment delta: `scripts/runtime/main_training_world.gd` owns fallback
world retirement. Acceptance: exactly one WorldEnvironment after authored map
load and no retained fallback collider. `scripts/maps/socom_map_runtime.gd` owns
bomb-site text; acceptance: surface lettering uses world units, not fixed screen
size. Protected motion/aim/damage owners remain unchanged. Focused regression
checks both plus rendered overview. Initial screenshots exposed both issues:
hiding the fallback root did not unregister its WorldEnvironment; fixed-size
Label3D site letters became huge overhead. The map authoring script also now
uses the runtime's actual surface_kind/uv_scale keys, not unused preset aliases.

Translation card: player intent = play the supplied art as a worn tropical depot
and new character; acceptance = shared map selected through the library and loaded
by main.tscn, clear spawns/routes, seven character meshes on the existing rig;
owners = SocomMapRuntime for map geometry and SocomOperatorAssetRuntime for asset
binding; protected = movement, aim, shots/damage, native bone rests, animation
library, weapon attachments, original files and published builds; proof = focused
regression, canonical render, team appearance test and feature contract gate.

Map authoring: `tools/build_relic_depot_map.py` writes
`config/maps/relic_depot.json`. The ordinary Map Creation Lab edits library copies
of this same schema and enters `res://main.tscn` through its existing Play path.
`scripts/maps/socom_map_document.gd` includes the map in BUNDLED_LIBRARY_MAPS.
No change to current_map.json (the deterministic camera-regression range).

Art authoring: `tools/build_relic_depot_assets.gd` splits 21 logical props,
normalizes size, moves pivots to bottom center and preserves multipart props.
The user-supplied scene groups are the source; no license-held buildings are used.
`assets/environment/relic_depot/asset_manifest.json` records source and dimensions.

Skin binding owner: `scripts/player/operator_asset_runtime.gd`:

```gdscript
skeleton = _find_skeleton(model_root)
_apply_authored_character_skin()
TeamAppearance.apply(model_root, 0)
```

The guarded loader validates every target bind, hides the old mesh only after
validation, and attaches seven MeshInstance3D pieces to the SAME skeleton:

```gdscript
skeleton.add_child(piece)
piece.owner = model_root
piece.skeleton = piece.get_path_to(skeleton)
```

No replacement Skeleton3D, AnimationPlayer, IK controller or weapon is installed.
The source's body weights are anatomically mapped offline to the native rest rig;
source UVs, topology and materials remain, but rest vertex positions are fitted
to existing joints. The original nine animations remain in the untouched intake,
not competing with the game's existing animation library. Model fitting requires
visual motion review, not merely matching bone names.

Restore appearance: remove/clear `skin_scene` in
`config/operator_team_appearance.json`; previous appearance values are preserved
in `art_source/relic_depot_integration/previous_appearance.json`.
Existing map documents remain unchanged. Select the previous map in the library
to restore its layout. No commit or public deployment requested/performed.

Verification so far: 126 objects build through the existing runtime; canonical
main consumes relic_depot; seven skin pieces, 65 runtime bones, equipped weapon,
ground contact, all spawns and east flank capsule clearance pass. Render and
broader checkpoint status below. Initial owner-reparent warning was fixed by clearing
the detached scene owner and assigning the canonical model owner after reparent.

Observed environment warnings: macOS certificate access in sandbox; audio capture
disabled; three ObjectDB instances at shutdown. Editor import completed but could
not save editor preferences outside writable directories. Existing duplicate UID
and modular weapon filename-case warnings were not changed by this task.

System delta scores and evidence: see
`config/feature_contracts/relic_depot_and_nvg_operator.json`. Candidate performance
score is provisional: no frame budget certification or multiplayer soak claimed.

Official API references:
[Godot 4.7 GLTFDocument](https://docs.godotengine.org/en/4.7/classes/class_gltfdocument.html),
[Godot 4.7 Skin](https://docs.godotengine.org/en/4.7/classes/class_skin.html).

## Final verification

- Godot 4.7.1 editor import: all 21 props imported; no script parse failure.
- `tools/relic_depot_regression.gd -- --render`: PASS, 126 objects, 7 character
  pieces, 65 runtime bones, equipped canonical weapon, floor contact, all spawn
  volumes and continuous east-flank capsule route. Canonical forward input moves
  the player with the new skin. Exactly one authored WorldEnvironment remains.
- Standing, three walking frames, and crouched character renders inspected:
  body stays together, weapon stays with the hands, boots contact the ground.
  Dark source clothing remains dark. Full aim/reload/prone/dive and every weapon
  combination are not visually certified; this is an initial bound-skin pass.
- `tools/blue_green_operator_regression.gd`: PASS, original model/skeleton and
  team-color material path remain in place.
- `tools/map_creation_lab_regression.gd`: PASS.
- `tools/feature_contract_regression.gd`: PASS, 65 integration graphs.
- `tools/run_integration_gate.sh quick`: BLOCKED before tests: current branch
  is `codex/render-deployment`, while the gate requires `main`. No branch switch,
  worktree reset, commit or gate bypass performed. Full integration/promotion is
  not claimed.

Evidence images and result JSON:
`art_source/relic_depot_integration/`. Game screenshots were rendered in the real
main.tscn; temporary inspection cameras exist only in the regression process.

All source downloads remain untouched. Environment and character CREDITS.md files
retain authors, source links, CC BY notices and modifications. Commercial register
records the new sets as review-required, not blanket rights clearance.
