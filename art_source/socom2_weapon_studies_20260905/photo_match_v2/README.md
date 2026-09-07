# Photo-matched exterior revision — V2

Translation card, before mesh changes:

- Player/art intent: make the four referenced pistol families recognizably closer
  to the supplied real-photo sources, while preserving the SOCOM-inspired style.
- Acceptance: compare source photo / earlier mesh / revised mesh at matching side
  angles; improve silhouette landmarks, grip curvature and exterior surface
  transitions; verify editable Blender sources and clean GLB re-imports.
- One owner: this standalone art revision, not a game weapon or gameplay tool.
- Protected: original P9S and ten-pistol batch, all canonical game assets, camera,
  animation, movement, weapon/damage ownership and multiplayer.
- Focused proof: native Blender comparison renders, normalized silhouette
  landmarks traced from source photos, geometry and material re-import checks.

Scope: P9S, Mark 23, Beretta 92FS/M9-family visual study, and Desert Eagle.
The 92FS source is not claimed to be the exact M9 variant. Standard photo-matched
versions are compared without added suppressors; separate SOCOM-style suppressed
variants may be included. No internal mechanisms, real-world dimensions,
fabrication features or functioning weapon parts are supplied. These are
decorative exterior game props in arbitrary art units. Hidden surfaces remain
artistic estimates; a single side photo cannot prove full 3D accuracy.

## Delta review

Decision: MERGE a separate art candidate, KEEP previous assets and all runtime
owners. The earlier generator uses shared eight-point guard loops and almost
rectangular slide side planes (`build_pistol_batch.py`, `guard` and `slide`).
That preserves a rough silhouette but loses the photo-specific curves. V2 will
use explicit per-photo outlines and rounded depth profiles for those surfaces.

Scores are a scoped 0–5 authoring assessment, not a claimed similarity percentage:

| Criterion | Existing batch | Candidate target | Evidence / limit |
|---|---:|---:|---|
| Exterior shape correctness | 2 | 4 | Replace generic loops with photo landmarks |
| Ownership clarity | 5 | 5 | Separate art-only output, no runtime writer |
| Canonical runtime parity | N/A | N/A | Neither is integrated; unchanged |
| Editor usability | 3 | 4 | Named components and side-by-side review scene |
| Performance | 3 | 3 | One consolidated mesh per export; review budget |
| Regression coverage | 3 | 4 | Re-import checks plus visual comparison evidence |

Candidate targets require verification before being recorded as achieved.

## Result and handoff

Four separate V2 models are built. The native comparison scene is
`photo_matched_pistols_v2.blend`; `photo_comparison_v2.png` compares the published
photo orientation, earlier mesh and revised mesh. `photo_matched_threequarter.png`
shows the same new mesh geometry, not an AI-generated concept. Four individual
`*_v2.glb` exports include their own authored grip normal maps. Reference photos
are packed only into the review Blender file and are excluded from the GLBs.
No redistribution license for those source photographs is asserted.

The standard P9S is compared against an earlier P9S copy with its suppressor
hidden, because the source photograph is unsuppressed. The original suppressed
source remains intact. The six other pistol-batch entries were not revised in
this pass. This is a closer exterior interpretation, not a scan, exact replica,
or a finished optimized runtime asset. Exact lettering and hidden surfaces are
not reproduced. Reference photos and renders share the board's display transform;
the comparison is for shape, not calibrated physical material colors.

### Verified delta assessment

Decision: MERGE the V2 art candidate, KEEP the original pack and runtime owners.
Observed scores are 4 / 5 / N/A / 4 / 2 / 4 in the same order as the table above.
The performance score is lower than the target because the four exports now use
11,116–17,576 triangles. This is an explicit review-quality tradeoff; no claim of
game-ready optimization is made. Both original Blender source hashes remain
unchanged. `verification.json` records independent re-import, geometry, material,
UV, embedded-texture and editable-source checks. No gameplay gate is claimed.

### Exact implementation evidence

The [photo-coordinate conversion](</Users/kiwimango/socom-141-camera-lab/art_source/socom2_weapon_studies_20260905/photo_match_v2/build_photo_match.py:86>)
normalizes observed image coordinates into arbitrary art units:

```python
def point(p):
    s=SPECS[current];return ((p[0]-s['origin'])*s['direction']/s['width'],(s['floor']-p[1])/s['width'])
```

The [grip surface authoring](</Users/kiwimango/socom-141-camera-lab/art_source/socom2_weapon_studies_20260905/photo_match_v2/build_photo_match.py:115>)
uses six depth rings rather than a flat extruded slab:

```python
rings=[(-.5,1-roundness*2),(-.46,1-roundness),(-.30,1),(.30,1),(.46,1-roundness),(.5,1-roundness*2)]
```

Per-family contour definitions begin at
[P9S](</Users/kiwimango/socom-141-camera-lab/art_source/socom2_weapon_studies_20260905/photo_match_v2/build_photo_match.py:179>),
[Mark 23](</Users/kiwimango/socom-141-camera-lab/art_source/socom2_weapon_studies_20260905/photo_match_v2/build_photo_match.py:200>),
[Beretta](</Users/kiwimango/socom-141-camera-lab/art_source/socom2_weapon_studies_20260905/photo_match_v2/build_photo_match.py:224>)
and [Desert Eagle](</Users/kiwimango/socom-141-camera-lab/art_source/socom2_weapon_studies_20260905/photo_match_v2/build_photo_match.py:255>).
For example, the Mark 23 control plate is explicitly photo-shaped:

```python
strip('Recessed upper side plate',[(576,171),(659,171),(659,205),(647,211),(585,210),(575,204)],.120,'Edge metal')
```

The [source-preservation check](</Users/kiwimango/socom-141-camera-lab/art_source/socom2_weapon_studies_20260905/photo_match_v2/verify_photo_match.py:14>)
verifies the original files against hashes captured before the edits:

```python
for path,digest in expected.items():assert hashlib.sha256(path.read_bytes()).hexdigest()==digest,str(path)
```

### Photo attribution

- P9S: [Amoskeag auction reference photograph](https://live.amoskeagauction.com/lot-details/index/catalog/51/lot/27207/Heckler-Koch-Model-P9S-Semi-Auto-Pistol).
- Mark 23: [Guns.com reference photograph](https://www.guns.com/firearms/handguns/semi-auto/heckler-%26-koch-mark-23-45-acp-semi-auto-12-rounds-5-9-barrel-2-6-lbs-used?p=66316).
  This flatter view supplements the previously shown [Rock Island photograph](https://www.rockislandauction.com/detail/2064/2/heckler-koch-mark-23-semiautomatic-pistol-with-case).
- Beretta: [manufacturer's 92FS photograph](https://www.berettadefense.com/products/92fs-bdt/), a related reference rather than an exact M9 variant claim.
- Desert Eagle: [IMFDB reference photograph](https://www.imfdb.org/index.php?title=Image%3ADesert-Eagle.jpeg).
