# Contributing code, skins, and map assets

Start with `AGENTS.md`. The supported target is Godot 4.7.1, Compatibility renderer.
`main.tscn` is the playable game. A lab or alternate player scene is not automatically integrated.
Use a separate branch for your contribution; do not overwrite someone else's dirty worktree.
On this machine `/Users/kiwimango/Documents/SOCOM-141` resolves to the canonical project.
Use your own checkout path on another machine.

## Pick a lane

| Contribution | Work here | Do not change |
| --- | --- | --- |
| Map prop | New named folder under `assets/environment/`, embedded-texture GLB, Blender source under `art_source/` | Player, camera, weapon or network scripts |
| Full map | Map Lab / `SocomMapCommandService`; saved map JSON and referenced assets | Match coordinator, RPCs, damage or movement to make the map work |
| Character outfit | Copy `art_source/ps1_skin_template/ps1_skin_template.blend`; new named asset folder | Original FBX, native rest rig, hands/grips, collision body, default character selection |
| Gameplay code | One named existing owner, translation card, focused test and feature contract | Unrelated owners or generated caches |

These are reviewed source contributions, not arbitrary executable mod packages.
Do not open an unreviewed third-party Godot project or install its scripts/plugins
as an asset. Asset validation is not a security sandbox or a licensing approval.

## Map props: existing editor-to-game path

1. Export a self-contained `.glb`, including textures. Keep pivots intentional;
   map `size` is a scale multiplier, not a requested bounding-box dimension.
2. In Map Lab, use **Import Self-Contained GLB…**. The imported copy is stored in
   the local `user://map_assets/` library. Local library paths alone are not
   portable to another player's computer or a browser export.
3. Choose collision deliberately: `none` for decoration, `box` for simple solid
   props, or `detailed_mesh` for static geometry. Check collision in Play; an
   editor selection box exists even when gameplay collision is `none`.
4. Save the map. **Save + Play Map** opens `res://main.tscn`, not another motor.
5. For a distributable contribution, include the reviewed GLB in a uniquely
   named `res://assets/environment/<your_pack>/` folder and use that exact path
   in map JSON. Include all assets with the build. Match clients and server must
   use the same approved map/collision data; there is no automatic asset download.

Existing file limits are 128 MB, 512 mesh instances and 1,000,000 vertices per
asset. These are rejection ceilings, **not performance targets**. Prefer much
smaller props and measure a real browser map with repeated instances.

Check a reviewed, imported prop without changing the active map:

```sh
godot --headless --path /path/to/checkout --script res://tools/check_contributed_map_prop.gd -- --asset=res://assets/environment/your_pack/your_prop.glb
```

One reusable saved command is `config/contributor_examples/place_map_prop.json`.
`SocomMapCommandService.apply(document, command)` returns a new document; the
Map Lab owns saving it. The command's existing crate is an example, not a new
asset. Change its path and ID for your own contribution.

Construction has these boundaries:

```text
Map Lab / command service -> saved map objects
  -> SocomMapRuntime.build_object
     -> SocomImportedMapAssetBuilder.build
        -> SocomMapAssetLibrary.instantiate_asset
```

The library owns loading. The builder owns imported geometry, bounds and static
collision construction. The runtime owns dispatch and whole-map collision/
camera policies. None of these components owns character movement or damage.

## Character outfits: authoring is not activation

Read `docs/PS1_SKIN_AUTHORING.md` and `art_source/ps1_skin_template/README.md`.
Copy the template; keep the original reference protected. Clothing and modeled
gear may change. Preserve the native 41-bone rig, hierarchy, rest pose, scale,
skin binds and hand contact regions. Runtime rig expansion is not a reason to
replace the native authoring skeleton. Do not add a second animation controller.

For a template-derived outfit that retains its BaseBody and modular gear:

```sh
godot --headless --path /path/to/checkout --script res://tools/ps1_skin_template_asset_regression.gd -- --sample=/absolute/path/to/outfit.glb
```

This is a strict template regression, not a universal skin validator. It checks
unchanged base geometry, native rests/binds, and the expected separate gear.
A redesigned body needs additional reviewed deformation/weight tests; do not
weaken this test merely to get a pass. Capture front, back and side views during
idle, fire/recovery, reload, run, crouch, prone and stance transitions. Check both
hands against every supported weapon family and preserve team readability.

The canonical game still uses the blue/green original character through
`scenes/player/operator_player.tscn`, `SocomOperatorAssetRuntime`, and
`SocomOperatorTeamAppearance`. A general skin registry/selector and multiplayer
skin-ID replication are **not implemented by this pass**. Submit the outfit for
review; do not replace the live mesh or edit camera/IK to make it appear to fit.

## Handoff checklist

- Unique asset/package name, author, source URLs, license/permission and required attribution.
- Editable source, final GLB, textures if needed, and exact import settings.
- Screenshots/video plus scale, mesh/triangle/material/texture counts.
- Exact map object command or proposed skin path; no absolute author-machine paths in saved game data.
- List changed files and focused test results; state visual limitations honestly.
- No `.godot` cache, credentials, unrelated code, blanket project settings, or automatic plugins.
- Maintainer verifies collisions, weapon contacts, browser size/performance and multiplayer parity before activation/export.

For code contributions, write the five-line translation card first, record the
six-score system delta, and update `config/feature_contracts/`. Run the focused
gate and `tools/feature_contract_regression.gd`. The aggregate integration gate
currently requires `main`; do not change branches or weaken gates to hide a
failure. No claim of full modularity follows from a passing file-count check.

## Remaining boundaries

The map runtime still contains procedural environment builders; Map Lab remains
large; operator asset setup and inherited multiplayer coordination need further
extraction. Keep each follow-up behavior-preserving with one declared owner.
Quick Match's proposed ten-second per-round individual loadout phase is also
still pending; see `docs/CONTRIBUTOR_BOUNDARY_PASS.md` for the verified mode audit.
