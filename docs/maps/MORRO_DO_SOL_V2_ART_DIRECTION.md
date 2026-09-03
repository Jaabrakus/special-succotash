# Morro do Sol V2 architecture and art-direction delta

V2 keeps V1 bundled as the restore point and preserves its non-building 2v2
demolition graph. The foreground is no longer a texture pass over disconnected
building boxes: six compound base structures now own the original footprints,
floor levels, tall interiors, doors, and windows. Two smaller occupied modules
are stacked above the objective-side roofs. The supplied plaster and exposed
wood are material inputs on this constructed geometry; they do not replace it.
The reference artwork remains mood and visual-language guidance only; V2 does
not copy its compositions, buildings, landscape, or identifiable details.

## Reference translation

| Observed quality | Original V2 translation | Gameplay boundary |
| --- | --- | --- |
| Large green terrain masses and thick vegetation | Three procedural perimeter hills, twelve bushes, and four trees outside primary aim corridors | No new terrain is traversable or collidable |
| Monumental white cloud against saturated blue | New V2 sky shader plus an original wide coastal matte with one dominant tropical cloud tower | Ambience only; no effect on visibility rules or lighting authority |
| Exposed, unfinished construction silhouette | Thirteen timber posts, beams, and braces above the defender-side homes | Unreachable and collision-free; no new roof power position |
| Damaged pastel plaster and loose architectural edges | Supplied damaged-plaster albedo on constructed wall masses, plus irregular polygon plaster meshes, raised foundation courses, pilasters, cornices, and eight-piece brick relief generated as geometry | Large collision remains on the wall masses; small presentation pieces do not become cover |
| Believable lived-in facades | Recessed openings, jambs, lintels, sills, glass panes, timber sash and mullions, bars, shutters, open door leaves, corrugated awnings, physical signs on the three public buildings, gutters, downspouts, meter boxes, and conduits | Presentation details do not own traversal or ballistics |
| Timber, collapsed floors, and broken framing | Exposed wood on the roof frame plus a nine-object collapse beyond the south retaining wall | The collapse is outside play and cannot become cover |
| Dense overhead linework | Six cylindrical tapered utility-pole assemblies and four segmented Bezier cable curves | Cables are above player height and collision-free |
| Dense hillside verticality | Mirrored crate pyramids and supported two-stage ramps reach the Alpha and Bravo roofs, where smaller occupied modules create stacked silhouettes | All 18 route objects are runtime-collidable; ramp endpoints meet authored terrace, landing, and roof heights; existing routes remain unchanged |

## Material and geometry rule

The rejected blockout used flat facade overlays, box awnings, box-wire segments,
and thirty-six disconnected building pieces. The correction is not to remove
texture; it is to apply the supplied plaster and wood to compound architecture.
Walls retain openings and collision masses, windows add panes and frames, doors
and shutters remain separate parts, and crates have panels, posts, rails, and
diagonal braces.

## V2 acceptance limits

- V1 stays bundled and selectable as a restore point.
- Every V1 non-building route, objective, and collision object keeps the same
  type, position, rotation, and size in V2.
- Thirty-six disconnected floor, roof, and wall pieces are removed from V2 and
  replaced by six base `favela_building` assemblies at the original footprints.
- Two smaller occupied `favela_building` modules sit above the Alpha and Bravo
  roofs, bringing the total to eight constructed building assemblies.
- Every assembly has real opening collision plus door/window trim, an open door
  leaf, corrugated awning, glass, timber sash, mullions, shutters, grille,
  foundation, cornice, pilaster, irregular plaster geometry, exposed bricks,
  drainage, and electrical service.
- All eight buildings save and consume both the supplied damaged-plaster and
  exposed-wood paths through `SocomMapRuntime`.
- V2 adds exactly 18 objects tagged `v2_vertical_route`: two upper buildings,
  four wedge ramps, two intermediate landings, four timber supports, and six
  constructed climb crates.
- The lower ramps start at the retained `1.975 m` terrace height, both landings
  top out at `4.375 m`, and the upper ramps terminate at the respective `6.95 m`
  and `6.75 m` roof heights. Every ramp remains below a 30-degree slope.
- V2 keeps exactly 51 objects tagged `v2_detail`.
- Every tagged V2 detail saves `collision_enabled = false`.
- Every tagged V2 vertical-route object saves and builds collision.
- The object count stays at 138 to bound runtime and editor cost.
- Six `utility_pole` objects replace pole boxes, and four `cable_curve` objects
  replace twelve disconnected wire boxes.
- The canonical `res://main.tscn` consumer builds the map, sky, and coast.
- No player, camera, weapon, animation, damage, objective, or network owner changes.
