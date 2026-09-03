# Morro do Sol — 2v2 Demolition

Morro do Sol is an original fictional Brazilian hillside demolition layout. It translates proven
small-map patterns into SOCOM-141 without copying another game's dimensions,
silhouette, asset placement, or encounter sequence.

## Tactical plan

```text
                         BRAVO SPAWN (GROUND)
                  ┌──── North Gate Inn ────┐
             west exit                   east exit
                 │                           │
        ┌─ A Community ┐   north cross   ┌─ B Workshop ─┐
        │ SITE A +1.8m ├──── fountain ───┤ SITE B +1.8m │
        └─ ramp + east ┘   ruined cover   └ ramp + west ┘
                 │       Cafe Azul roof       │
           west terrace  / center doors  east terrace
                 │      staggered stalls      │
                  └──── BOMB / ALPHA SPAWN ──┘
```

- West lane is the protected A route. Two offset carts break the spawn-to-site
  sightline before the Community Hall's south entrance.
- East lane mirrors the travel budget but not every object. Its Workshop has a
  different interior cover angle and a west connector.
- Center is the fastest and most exposed rotation. The fountain and two broken
  walls prevent one player from holding both sites from a single pixel angle.
- The Cafe Azul roof is the highest vertical power position. It overlooks center,
  but its parapets and stair exposure prevent it from safely watching both bomb
  interiors.
- Each plant building has two full-size door approaches plus two windows and sits
  on a +1.8 m structural tier. South site ramps and side terraces provide
  distinct climbing routes. The 4.1–4.8 m interiors keep the third-person camera
  readable and make the stacked architecture feel intentional. The
  attacking duo can split; the defending duo cannot cover every entry from one
  corner.

## Reference translations

| Reference pattern | Morro do Sol implementation | Originality boundary |
| --- | --- | --- |
| *King* and *Stack*: compact 2v2 maps with a risky elevated center | Cafe Azul roof and one exposed staircase | No copied measurements, warehouse geometry, tunnels, or prop placement |
| *Speedball*: staggered cover that interrupts direct spawn lanes | West/east carts, market stalls, and offset masonry | Cover is integrated into asymmetric village streets, not a mirrored firing range |
| *Atrium*: an open center that is easy to understand but dangerous to occupy | Fountain courtyard and cross-site connector | The courtyard connects two demolition sites and a roof route instead of an overtime flag |
| *Lake*: a small building whose doors, windows, interior, and roof create layered decisions | Complete Community Hall, Workshop, Cafe, and Inn interiors | Multiple original structures replace the single estate layout |
| SOCOM *Desert Glory*: plaster buildings, cafe/ruin callouts, alleys, and cross-building rotations | Warm stucco palette, Cafe Azul, broken market walls, and outer alleys | No original map footprint, objective locations, or recognizable building arrangement is reproduced |
| *Favela*: sloped streets, tight interiors, roof power positions, and perimeter counter-routes | Six original ramps, two side terraces, tall rooms, water tanks, and one exposed center roof | No original route graph, building footprint, callout arrangement, or objective placement is reproduced |

Reference sources:

- Activision, [2v2 Gunfight Tournament map guidance](https://blog.activision.com/call-of-duty/2019-11/2v2-Gunfight-Tournament-Beta)
- Activision, [Tactical Map Intel: Atrium](https://blog.activision.com/ca/en/call-of-duty/2019-12/Modern-Warfare-Tactical-Map-Intel-Atrium)
- Valve community listing, [official Lake map entry](https://steamcommunity.com/workshop/filedetails/?id=1289637214)
- Community archival reference, [SOCOM Desert Glory tactical map](https://vclan3.tripod.com/id5.html)
- Activision, [Favela tactical map guide](https://www.callofduty.com/guides/multiplayer-maps/call-of-duty-modern-warfare-iii-play-maps-core-multiplayer-map-guide-favela)
- Inside Favela, [self-built architecture of Rio's morros](https://insidefavela.com/en/magazine/self-built-architecture-favelas)

## Art and readability rules

- Warm and cool building families identify routes without HUD arrows.
- Painted-cloud contrast stays above the roofline; enemy silhouettes must not
  disappear into high-frequency cloud texture near ground level.
- Materials use broad color masses, low specular response, high roughness, and
  restrained normal strength. The environment remains readable at combat speed.
- Decorative trees and shrubs stay at boundary corners or outside primary aim
  corridors.
- The geometry is authored once in the map JSON. Runtime collision, editor
  preview, training, and multiplayer all consume the same objects.
- The beach and ocean are original distant matte art on an unlit ambience card
  beyond the downhill boundary. It has no collision, navigation, objective, or
  movement ownership, and the playable village remains fully modeled in 3D.
