# SOCOM II weapon reference studies

Standalone Blender review assets only. No player, weapon profile, socket, scene,
animation or multiplayer code is changed.

Reference: https://www.youtube.com/watch?v=oI3NiRLeRhs — Feral Cat,
"SOCOM II PS2 All Weapons Demonstration", 0:05, labelled P9S Silenced.
The bottom-left HUD provides a low-resolution side silhouette. Hidden surfaces,
width and small details are approximations, not recovered original geometry.

Intent: begin modeling the weapons seen in the HUD as editable visual game props.
Acceptance: first P9S-inspired study preserves the compact slide, swept grip,
open trigger guard and elongated suppressor visible in the reference. Review in
side and three-quarter views before considering game integration.
Owner: this standalone Blender asset; all game owners remain unchanged.
Proof: Blender renders and geometry export checks. No runtime integration claim.

These are nonfunctional exterior visual models, without internal mechanisms or
manufacturing information. The source video and HUD art are reference only.

## Full roster / pistol batch continuation

Intent: continue the accepted P9S art direction and keep a complete weapon build
checklist. Acceptance: a 43-entry roster with separate variants and honest
built/queued status; a ten-pistol review sheet with editable Blender geometry.
The accepted P9S source and its exports remain unchanged. Owner: standalone art
collections in this folder. Protected: all game assets, runtime code, weapon
profiles, animation, camera, damage and networking. Proof: native Blender renders,
finite-geometry checks, and an independent GLB re-import check for each pistol.

The remaining weapons are a build queue, not finished models. Roster references
are cross-checked against the video and the linked game-weapon lists; items
without a verified video label are explicitly marked pending close-up. The new
pistols are first-pass interpretations, not recovered original SOCOM meshes.
The 226, M11 and SP-10 use one related visual family in this first pass; M11 and
SP-10 need closer HUD confirmation before approval. No gameplay integration.

See `WEAPON_BUILD_LIST.md` for the human-readable roster and
`weapon_build_list.json` for per-item status. `video_reference/verified_*.png`
are loaded video frames (the requested seek time in the filename is approximate).
Earlier `frame_*.png` pilot captures are unverified and must not be used as
timestamp evidence. The saved original P9S reference remains authoritative for
that accepted study.

Completed deliverables: `pistol_batch/socom2_pistols_review.blend`,
`pistol_batch/pistol_contact_sheet.png`, and ten individual `.glb` files in
`pistol_batch/`. The saved Blender collection retains editable exterior parts;
exports consolidate them into one mesh object per pistol and discard zero-area
faces on export copies only. `pistol_batch/verification.json` records ten passing
empty-scene re-import checks, including triangle counts, finite coordinates,
positive triangle areas, material assignments and three-axis extents. This is
an art/export check, not a gameplay integration test. The original P9S `.blend`,
`.glb` and renders have not been overwritten.

## Photo-matched revision

`photo_match_v2/photo_matched_pistols_v2.blend` is a separate, newer four-family
review: P9S, Mark 23, Beretta 92FS/M9-family, and Desert Eagle. The comparison
image `photo_match_v2/photo_comparison_v2.png` shows real source photo / original
mesh / revised mesh. `photo_match_v2/photo_matched_threequarter.png` shows the
same revised geometry in three-quarter views. Original models remain unchanged.
The other six entries of the pistol batch have not been photo-refined in this
pass. P9S is shown without its suppressor for comparison with the standard photo;
the original suppressed version remains available in the starting batch.

## Optional relic finish

`relic_finish_v3/field_relic_pistols.blend` adds worn material variants to the
four approved photo-matched families without changing their geometry. See
`relic_finish_v3/relic_pistols_preview.png` and that directory's README for
the clarified lost-game art direction, deliverables, and passing export checks.
The approved V2 files remain unchanged. These variants are not installed in
the playable game.
