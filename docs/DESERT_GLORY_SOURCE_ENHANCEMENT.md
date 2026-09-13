# Desert Glory source-assets variant

Translation card: use the user's SOCOM II map assets, then enhance textures while
preserving the layout. Acceptance: same 10 source architecture sectors and 13217
structural triangles with original UVs; 95 supported static source placements; no
Relic Depot substitute props; one explicit hashed AI wall-texture override; clear
spawn tests and canonical main rendering. Owner: existing SocomMapRuntime. Protect
active map, prior recreation, player movement, camera, animation and server shots.

MERGE a source-assets export option into the existing map pipeline. The previous
project-texture recreation is preserved. The source option installs a separate
`user://maps/desert_glory_source_enhanced.json`. The Desert Glory preview prefers
this variant when installed; `--replacement-assets` selects the old version.
Both select a shared saved map document and enter `res://main.tscn`.

## Build / provenance

Run `node tools/socom_geometry/desert_glory_source.cjs ISO MP6_LIBRARY NEW_OUTPUT
ENHANCEMENT_MANIFEST`, then Godot `--script res://tools/build_desert_glory.gd --
--source=NEW_OUTPUT/geometry`. Fresh output required. The existing compare-and-
replace guard applies if rebuilding a previously installed map. Every raw config,
geometry, model, palette and texture archive is SHA256-checked against the supplied
ISO before conversion. The original decoded textures remain unmodified.

The local enhancement manifest is
`private_assets/desert_glory/enhancements.json`; this ignored directory is not a
release asset. It records the source/output hashes, prompt, method and variant.
Built-in image generation enhanced `afghan2r_wall_dirty.tif` from a 128-square
source: aged plaster detail, muted gray-beige, original damage/band/seam placement,
flat opaque albedo, no new large forms or lighting. It is an AI interpretation,
not a pixel-exact upscale. Only this wall texture is enhanced so far. Other
recovered map textures remain original. No AI-generated geometry is substituted.

65 base textures decode; four unsupported texture formats are deferred. 44 prop
meshes pass independent source bounding-box checks and match 95 of 138 source
placements. The remaining 43 placements are not fabricated or replaced. Deferred
items include some crate/pallet variants, utilities, small effects and a truck
variant. Per-packet origins did not resolve those remaining bounds mismatches;
keep the checks. Source alpha cards excluded by the existing structural pass
remain excluded. This is not a complete mission/dynamics/lightmap reconstruction.

Source and AI-derived source assets remain local research material. No publication
rights are established by extraction or AI enhancement. Do not commit or package
the local asset library for a release.

## Proof

`tools/desert_glory_regression.gd -- --local-map --source-assets` checks installed
sectors, source-prop census, provenance, saved grain and supported spawns through
the canonical runtime. `tools/desert_glory_visual_check.gd -- --source-assets`
captures actual main-scene player, overhead and street views. Structural extraction
retains the original full packet/draw-key/bounds assertions. Run the feature
contract gate as well. These do not certify original camera or renderer parity.

Installed variant passed the local map and real-renderer checks (main scene,
supported spawns, single grain owner). Source rendering measured 70,795 primitives
and 572 draw calls in the inspection view, not a performance certification.
Visual inspection found the source-UV map still overly bright under the retained
approximate ambience. Lighting and further texture enhancement remain unfinished.
