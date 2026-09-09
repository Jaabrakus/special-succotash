# Custom weapon-family reticles

## Offset revision — 2026-09-09

Translation card: replace the rejected rifle Tripod with the existing Offset concept. Preserve the original rifle sprite's stronger inner / faded outer alpha on the new strokes and their outline. Owner remains `SocomDynamicReticle`; its pure geometry helper produces points/colors only. Pistol Horizon, shotgun Split Halo, center dot, hit-X timing, aim/VRC, bloom recovery, shots, and all weapon configuration remain unchanged. Shared writer is `config/reticle_presentation.json`; main and multiplayer already read it. Proof: extend `custom_reticle_regression.gd` with exact source-alpha sampling, Offset symmetry/shape, gradient orientation, unchanged timing, canonical and multiplayer checks; render both a family card and main.

System delta: MERGE Offset and the source-derived alpha ramp into the existing renderer. Current/candidate scores (0–5): requested-design correctness 1/5, ownership 5/5, canonical parity 5/5, editor usability 4/4, performance 4/4, regression coverage 5/5. Evidence: prior solid `draw_polyline` and Tripod family config versus Offset points, saved alpha ramp and focused runtime tests. Keep Tripod available as an unused geometry option; no source assets are modified.

Fade means spatial opacity here, not a new hide timer. The source rifle floating sprite `ret_rifle_02.png`, column 30, rows 30→8 has 23 alpha samples: ten 175, five 131, three 88, five 44 (0–255). These are mapped from each stroke's closest-to-center point toward its outer extent, then multiplied by the existing source tint alpha (0.92 normally, 0.95 on target). Original source-pixel opacity is reused; the mapping to a new silhouette is a deliberate adaptation, not a claim of identical pixels or recovered game timing.

API: Godot 4.7.1, [CanvasItem.draw_polyline_colors](https://docs.godotengine.org/en/stable/classes/class_canvasitem.html#class-canvasitem-method-draw-polyline-colors) supports per-point color gradients and positive-width antialiasing. The unchanged families use the original uniform-color path.

Revision verification: PASS headless parse; PASS custom regression headless and rendered (45 profiles, eight canonical/multiplayer equips and accepted shots); all 23 saved alpha values match the original source image. Offset side brackets are mirrored and its lower datum stays below aim. Alpha is invariant across ready/opened bloom; the hit X retains its 0.15-second fade. PASS shared-HUD and legacy-reticle regressions, 110 feature contracts, and diff whitespace check. Render inspection confirms the faded Offset is visible in main; Horizon and Split Halo retain their previous drawing. Native test closed normally. The headless canonical test reported 16 ObjectDB instances/eight resources at shutdown; existing macOS certificate and disabled voice-capture warnings also remain. No clean headless-shutdown claim or full integration promotion. No live game was reloaded, and no browser ZIP was rebuilt.

## Translation card — 2026-09-09

- Player intent: Split Halo for shotguns, Horizon for pistols, Tripod for rifles; keep the current shooting feel.
- Acceptance: canonical main and multiplayer HUDs select the same saved family design on equip and retain it through posture changes. Marks respond to existing bloom; the center follows camera aim. Hit X and interaction feedback remain.
- One presentation owner: `SocomDynamicReticle` on the existing HUD Control. `custom_reticle_geometry.gd` is a stateless point generator, not another node/state owner.
- Shared contract: `config/reticle_presentation.json`. Weapon controllers forward existing category as presentation metadata only. Rifle-style grouping retains SMGs, machine guns and unscoped sniper rifles. This does not add ADS.
- Must not change: fire input, camera/aim/VRC, weapon spread/pellet equations, reloads, damage, movement, animation, server authority, live sessions or published builds.
- Focused proof: `tools/custom_reticle_regression.gd` checks geometry, equip/posture parity in main and multiplayer, fixed aim center, bloom recovery and feedback. `--render` captures actual Godot family drawings and canonical HUD. Source-art, legacy-reticle and shared-HUD regressions remain relevant.

## System-delta review

MERGE custom geometry into the existing presentation owner; keep source artwork as a selectable fallback (`custom.enabled = false`). Scores use 0–5 and measure this request, not original-game accuracy.

| Criterion | Source-only default | Custom family drawing |
| --- | ---: | ---: |
| Correctness for requested silhouette | 1 | 5 |
| Ownership clarity | 5 | 5 |
| Canonical/runtime parity | 5 | 5 |
| Editor usability | 4 | 4 |
| Performance | 5 | 4 |
| Regression coverage | 5 | 5 |

Evidence: existing `socom_dynamic_reticle.gd` source assembly; new pure geometry generator; shared JSON family map; focused canonical/multiplayer regression. Custom arcs use bounded polylines (at most 68 points), with no new node, animation clock, shot calculation or texture imports.

## Bloom is an accuracy indicator, not a containment guarantee

The existing HUD converts normalized spread into a pixel gap and interpolates it. It does not project the full ballistic cone through the active camera. `weapon_ballistics.gd::try_fire_direction` adds `pellet_spread_deg` for buckshot; `get_normalized_spread` does not include that term. Camera/muzzle parallax and display interpolation also prevent treating the outline as a strict hit boundary. The open Horizon and Tripod designs do not enclose a literal region.

This pass neither clamps bullets to artwork nor changes damage/spread to make the artwork look correct. Exact containment needs a separate projected-cone presentation contract, including pellet spread, muzzle origin and camera projection.

## Sniper proposal (not implemented)

Current weapon input uses fire press/hold; `camera_frame_pipeline.gd` reserves scoped response for a future state. A shared tap/hold button must delay a quick shot until release to know it was not a scope hold. Suggested experiment: tap-release fires; a 0.2-second hold scopes; release fires while scoped; a separate cancel input exits without firing. Reload may also leave scope, but must not be the only cancellation path. No sniper input/camera changes are part of this pass.

## Verification

- PASS `custom_reticle_regression.gd`, headless and OpenGL native render: 45 category-bearing profiles resolve; eight representative equipped weapons fire through canonical main and select the same family in multiplayer. Includes an unmatched machine gun and shotgun, not only source-name matches. Tests leave weapon JSON and ballistic source hashes unchanged.
- PASS actual render inspection: Split Halo fragments retain curvature while separating; Horizon leaves the upper sightline open; Tripod retains three non-spinning hooks. Center dot, target coloring and red hit X render. Actual main captures show the selected art after M4A1, Mark 23 and 870 shots.
- PASS `socom2_reticle_regression.gd`: 32 source-art fallback profiles, with custom mode disabled in that test process only. Its existing shutdown reports remain: 19 ObjectDB instances and eight resources still in use. This is not a clean-shutdown claim.
- PASS `shared_weapon_reticle_regression.gd` and `ballistic_reference_reticle_regression.gd`.
- PASS `feature_contract_regression.gd`: 110 contracts. PASS `git diff --check`.
- BLOCKED aggregate quick gate: `tools/run_integration_gate.sh:18` reports `FAIL: this is codex/render-deployment; canonical integration is main`. No branch switch or promotion was performed.
- Environment: sandbox headless runs report the macOS certificate lookup warning; main reports microphone capture disabled. Native rendering completed with no script/assertion failures. An initial check without an explicit writable log crashed before parsing; all subsequent checks use `/private/tmp` logs.
- Captures: `/private/tmp/custom-reticle-families.png`, `/private/tmp/custom-reticle-main-m4a1.png`, `/private/tmp/custom-reticle-main-mark_23.png`, `/private/tmp/custom-reticle-main-870.png`.

No current shooting, sniper ADS, exact pellet containment, browser export, deployment, or animation change is claimed by this pass. New sessions load the saved presentation; an already-running game was not restarted.
