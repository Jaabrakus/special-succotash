# Tactical courtyard kit — original art

Five original low-poly environment modules with a muted lime-plaster, stone,
timber, olive sheet-metal and rust palette. Early-console tactical town scenes
are the feel reference; no source-game meshes, textures, logos or map layout
were copied.

Open `tactical_courtyard_kit.blend` for the editable meshes, named source
collections, packed color atlas and lit courtyard preview. The source modules
are collections referenced by the preview instances; select an instance and
use **Make Instances Real**, or inspect its source collection in the Outliner.

Rebuild from the repository root:

```sh
/Applications/Blender.app/Contents/MacOS/Blender --background \
  --python tools/blender/build_tactical_courtyard_kit.py
```

Runtime interchange is the five individual `.glb` files in
`assets/environment/tactical_courtyard_kit/`. They use native meters, ground
anchors, one joined mesh per module, backface culling, matte material and a
1024×1024 original color atlas. The atlas is embedded in each GLB so each file
is self-contained; the standalone PNG supports editing. The editable source
keeps separate named details. The preview floor, flagstones, cameras and lights
are not exported into the modules.

`scenes/props/tactical_courtyard_kit.tscn` groups the assets in a static courtyard
prefab. One StaticBody3D owns its primitive collision shapes. The floor is a
simple Godot mesh; scene lighting belongs to the map. Six stairs have 0.18 m
risers and 0.32 m treads, with a 1.5 m clear tread width. The doorway's finished
stone jambs narrow its structural opening to about 1.13 m; its collision opening
is conservatively 1.05 m wide and 2.165 m tall. Decorative wear and fasteners do
not get separate collision shapes.

This is an asset delivery and reusable prefab, not a claim of canonical map
integration. No main scene, player, camera, weapon, movement, animation or
network runtime file was changed. Place it through the canonical map owner;
prove actual CharacterBody3D traversal before claiming stair gameplay is ready.

`build_report.json` records exported bounds, triangles and file sizes.
`courtyard_kit_preview.png` is the rendered Blender material/geometry proof.
`godot_import_preview.png` is the actual imported prefab rendered by Godot 4.7.1
Compatibility on Apple M4. It uses simple map-like directional/ambient light.

Import/collision proof (passed):

```sh
/Users/kiwimango/Applications/Godot-4.7.1.app/Contents/MacOS/Godot \
  --headless --path . --script res://tools/tactical_courtyard_asset_regression.gd
```

Remove `--headless` and append `-- --render` to regenerate the engine preview.
The proof loads all five GLBs, checks one mesh/surface per module, material and
ground anchor, checks the prefab's single StaticBody3D and 23 shapes, and casts
physics rays through the doorway, into a wall and onto all six stair treads.
It deliberately does not assert actual player traversal or map integration.

Godot interchange reference:
https://docs.godotengine.org/en/stable/tutorials/assets_pipeline/importing_3d_scenes/available_formats.html
