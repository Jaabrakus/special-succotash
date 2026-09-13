# Comprehensive Quality Audit: Camera & HUD Presentation
**Project:** SOCOM-141 Tactical Shooter  
**Agent:** `explorer_camera_hud_1` (teamwork_preview_explorer)  
**Date:** 2026-09-12  
**Integrity Mode:** demo (Read-Only Investigation)  
**Reference Baseline:** Authentic *SOCOM II: U.S. Navy SEALs* (PS2) & `AGENTS.md` Integration Contracts  

---

## 1. Executive Summary

A comprehensive, read-only architectural and feel audit of the Camera and HUD presentation systems in the SOCOM-141 repository was conducted. The investigation encompassed all 23 scripts in `scripts/camera/`, runtime HUD builders in `scripts/runtime/`, UI controls in `scripts/ui/`, scene files in `scenes/camera/` and `scenes/ui/`, relevant JSON manifests in `config/` and `config/feature_contracts/`, and the executable regression test suite in `tools/`.

### Core Findings Summary:
1. **Aim-Intent Ownership (Rule 5 Compliance)**: **STRICTLY PASSES**. The SOCOM camera rig (`SocomCameraRig`) and reticle remain the sole aim-intent owner. The camera rig produces sequenced network aim intent and shared 3D targets; `player_controller.gd` reads camera yaw/pitch for movement direction, and `socom_weapon_controller.gd` reads `get_shared_aim_target`. The camera rig **never** writes to player character transforms.
2. **Authentic Framing & Obstruction Avoidance**: **MIXED**. The camera rig implements centered third-person framing (distance 2.20 m, height 2.05 m, shoulder offset 0.0 m, vertical FOV 68°) matching authentic SOCOM 2 baseline perspectives. However, volume collision queries in `camera_passage_policy.gd` omit collision mask filtering (defaulting to `0xFFFFFFFF`), which allows non-world entities (such as other players or props) to obstruct and crush the camera boom. Furthermore, a 15-pixel deadzone on mouse input introduces unwanted input lag and stickiness for fine aiming on PC.
3. **Reticle Presentation & Regression Breaks**: **FAILED REGRESSIONS**. Although authentic SOCOM 2 decoded PS2 textures and custom bracket geometry exist in the repository, `config/contextual_hud.json` (`"reference_reticle": true`) redirects custom drawing to `_draw_contextual_ring()`, replacing authentic chartreuse brackets with a modern neon-cyan circle and orange center dot. This causes an immediate regression failure in `tools/ballistic_reference_reticle_regression.gd`. Additionally, `notify_shot()` suppresses cosmetic shot bounce when `source_family` is set, causing `tools/reticle_render_integration.gd` to fail.
4. **HUD Presentation & Layout Conflicts**: **DEFECTS IDENTIFIED**. The HUD enables a floating holographic 3D AR-style circular gauge following the player's spine in world space rather than the authentic fixed-corner tactical card. When standard status is visible, `SocomStanceIndicator` hardcodes offsets that directly collide with and overlap `PlayerStatusHUD` text. In the Training Range, `PublicTrainingRangeTitle` and `SocomTacticalCompass` share identical top-center screen bounds, rendering directly over each other.
5. **HUD Toggle (`H` Key) Lifecycle**: **DEFECTS IDENTIFIED**. Hiding the HUD hides `hud_toggle_button` without providing an alternate on-screen control, making HUD restoration impossible for touch or mouse-only players. Furthermore, `_update_player_status_ui()` continues running full string formatting and object binding every frame while hidden and mutates `player_status_panel.visible = true` behind the hidden canvas layer.

---

## 2. System-by-System Technical Evaluation

### A. SOCOM Third-Person Camera Rig
- **Framing & Geometry**:
  - Distance: 2.20 m (`profile.distance`).
  - Height: 2.05 m (`profile.height`).
  - Lateral Shoulder Offset: 0.0 m (`profile.shoulder_offset`). The camera is positioned dead center behind the operator, matching classic SOCOM 2 PS2 framing.
  - Peek Offset: 0.38 m lateral offset (`profile.peek_camera_lateral_offset`) dynamically applied when leaning left/right via `get_peek_amount()`.
  - Field of View: Default vertical FOV is 68.0° (`profile.vertical_fov`), adapting to 60.0° / 42.0° on steep downward aiming to preserve character legibility over parapets.
  - Pitch & Yaw Limits: Yaw wraps freely across `[-PI, PI]`. Pitch is clamped between `-60.0°` (downward crane) and `+28.0°` (upward limit), matching tactical third-person shooter constraints.
- **Rotation Smoothing & Deadzones**:
  - Orbit smoothing utilizes frame-rate-independent exponential damping (`orbit_yaw_response: 22.0`, `orbit_pitch_response: 24.0`).
  - Mouse input routes through `mouse_aim_model.gd`. A minimum threshold of `10.0 px (deadzone) + 5.0 px (marker radius) = 15.0 px` is enforced before raw mouse motion updates `intent_yaw` and `intent_pitch`. While designed to simulate analog stick tension, this creates a deadzone on raw mouse input that impairs precision micro-aiming for long-distance headshots.

### B. Obstruction Avoidance & Collision Solver
- **Collision Detection Mechanics**:
  - Uses `PhysicsShapeQueryParameters3D` with a `SphereShape3D` (radius 0.12 m, margin 0.025 m) cast along the camera boom from `target.global_position + Vector3.UP * 1.95m` to desired camera position via `SocomCameraPassagePolicy.cast_camera_motion()`.
  - Doorway and archway passability is supported via `camera_soft_occluder` metadata/groups.
- **Wall Clipping & Zoom Smoothing**:
  - `profile.hold_rendered_camera_on_obstruction = true` is currently active. When an obstruction is detected, the boom compresses immediately and flags `hold_lens = true`.
  - Downstream post-collision reframing (micro-adjustments, orbit search, surface slide) is bypassed when `hold_lens` is set.
  - Outward release from obstruction is buffered by `_stabilize_obstruction_release()` with `obstruction_release_delay = 0.14s` to prevent wall-edge pulsing/flickering.
- **Collision Mask Filtering Defect**:
  - In `camera_passage_policy.gd:35-42`, `motion_query.collision_mask` is omitted, defaulting to `0xFFFFFFFF` (all 32 layers). Only the local player RID is excluded. As a result, other characters (network operators, dummies, teammates) trigger camera obstruction collisions.

### C. Reticle Aim Tracking & Ownership (Rule 5 Audit)
- **Aim-Intent Ownership**:
  - Strictly follows Rule 5: `CharacterBody3D` owns locomotion; `SocomCameraRig` owns aim-intent; server weapon owns shots/damage.
  - Camera calculates `aim_yaw` and `aim_pitch`. `player_controller.gd:531-532` reads these values for player command generation.
  - Verification confirmed zero write statements from camera scripts to character transforms (`target.position`, `target.rotation`, `target.transform`).
- **Aim Acquisition & Projection**:
  - `camera_aim_resolver.gd:35-68` projects a ray from the camera lens through the normalized reticle coordinates (`Vector2(0.5, 0.5)` + recoil offset).
  - Ray queries physics mask `1 | (1 << 2)` with `collide_with_areas = true` to acquire damage hurtboxes on layer 3.
  - If a hurtbox is struck, the aim point penetrates `0.08 m` into the capsule (`HURTBOX_AIM_DEPTH_M`) to prevent grazing parallax misses.
  - Shot validation (`update_shot_validation`) traces from weapon muzzle to aim point; if blocked, `shot_blocked` flags true and turns the reticle orange/red.

### D. HUD Layout & Presentation
- **Loadout Card Presentation**:
  - `SocomLoadoutCardHUD` contains an authored, authentic rectangular bottom-right card with slot badge, fire mode pips (`●●● AUTO [B]`, `●●○ 3-BURST [B]`, `●○○ SEMI [B]`), ammo readout (`30 / 120`), and grenade badges (`FRAG 2`, `FLASH 1`, `SMOKE 1`).
  - However, `config/contextual_hud.json` (`"enabled": true`, `"floating_enabled": true`) overrides this layout, activating `_draw_contextual()` and `_update_floating_position()`. This turns the card into a floating circular arc gauge anchored to the operator's animated torso (`mixamorig_Spine2`) in 3D perspective.
- **Status Panels & Stance Indicator**:
  - Bottom-left status readout (`PlayerStatusHUD`) displays health, weapon state, and ammo.
  - `SocomStanceIndicator` renders posture silhouettes (`STAND`, `CROUCH`, `PRONE`, `SPRINT`).
  - In `scenes/ui/gameplay_hud.tscn`, the stance indicator is placed at `offset_left = 280.0`, but `socom_stance_indicator.gd:21-24` overrides this in `_ready()` to `offset_left = 22.0, offset_top = -140.0`, overlapping directly over the status panel text.
- **Compass & Navigation**:
  - `SocomTacticalCompass` displays a 360° horizontal tape with cardinal directions and dynamic objective anchors.
  - In public training mode, `PublicTrainingRangeTitle` is anchored at the top center (`y = 16 to 48`), sharing the exact screen space as `SocomTacticalCompass` (`y = 14 to 46`), causing visual overlap.

### E. Reticle Dynamics & Authentic SOCOM 2 Styling
- **Spread & Bloom Visualization**:
  - Reticle gap (`current_gap`) dynamically scales from `base_gap` to `max_bloom_gap` using `spread_normalized` from `SocomWeaponController.get_reticle_spread_normalized()`.
  - Movement speed ratio expands the gap and movement ticks.
  - Target lock changes reticle color to red (`target_color = Color(1.0, 0.15, 0.15, 0.95)`) when aiming at damage-receiving entities.
- **Authentic Styling vs Modern Deviation**:
  - Authentic SOCOM 2 uses chartreuse brackets (`#d5e7ac`) with decoded PS2 textures (`ret_rifle_01.png`, etc.).
  - `contextual_hud.json` enforces `"reference_reticle": true`, which activates `_draw_contextual_ring()`. This renders a cyan circular ring (`#55e8f2`) with 4 spikes and an orange dot, breaking SOCOM 2 feel and failing regression tests.
  - `notify_shot()` resets `shot_bounce_amplitude = 0.0` when `source_family` is present, breaking the vertical reticle kick and failing `reticle_render_integration.gd`.

### F. HUD Toggle Functionality (`H` Key)
- Handled via `main_gameplay_hud.gd:432-440` and `HudBuilder.set_hud_mechanics_visible()`.
- Hides canvas layer, reticle, compass, loadout card, stance indicator, and status panels.
- Defect 1: Hiding the HUD also hides `hud_toggle_button` (`visible = false`), preventing non-keyboard users from restoring the HUD.
- Defect 2: In `main_frame_runtime.gd:111`, `_update_player_status_ui()` runs every frame unconditionally, continuing CPU string formatting and mutating `player_status_panel.visible = true` behind the hidden layer.

---

## 3. Prioritized Defect Catalog

### Defect 1: Modern Cyan Ring Overrides Authentic Chartreuse Reticle & Breaks Regression
- **Severity**: HIGH (Feel Discrepancy & Regression Failure)
- **File & Line**: `scripts/ui/socom_dynamic_reticle.gd:290-294`, `scripts/ui/socom_dynamic_reticle.gd:325-345`, `config/contextual_hud.json:11`
- **Verbatim Excerpt**:
```gdscript
func _draw_custom_reference() -> void:
    var geometry := get_custom_reference_geometry()
    if bool(contextual_style.get("reference_reticle", false)):
        _draw_contextual_ring(geometry)
        return
```
```gdscript
func _draw_contextual_ring(geometry: Dictionary) -> void:
    var outline := float(_custom_settings.get("outline_extra_px", 2.0))
    var radius := BloomEnvelope.inner_radius(geometry.strokes, float(geometry.width) + outline) + 0.75
    radius = maxf(radius, 1.0)
    var tint := target_color if is_target_acquired else Color.from_string(String(contextual_style.reticle_color), Color.CYAN)
    draw_set_transform(geometry.center)
    draw_arc(Vector2.ZERO, radius, 0.0, TAU, 96, tint, 1.5, true)
    var tick_gap := radius * float(contextual_style.get("reticle_tick_gap_ratio", 0.22))
    var tick_length := radius * float(contextual_style.get("reticle_tick_length_ratio", 0.65))
    for direction in [Vector2.UP, Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT]:
        var near_color := Color(tint, tint.a * 0.7)
        var far_color := Color(tint, tint.a * 0.12)
        var start: Vector2 = direction * (radius + tick_gap)
        var end: Vector2 = direction * (radius + tick_gap + tick_length)
        var side: Vector2 = direction.orthogonal() * 0.5
        draw_polygon(PackedVector2Array([start - side, start + side, end + side, end - side]),
            PackedColorArray([near_color, near_color, far_color, far_color]))
    draw_circle(Vector2.ZERO, 1.2, Color.from_string(String(contextual_style.center_color), Color.ORANGE), true, -1, true)
    draw_set_transform(Vector2.ZERO)
```
- **Technical Explanation**:
  `config/contextual_hud.json` sets `"reference_reticle": true`. This redirects all custom reticle drawing to `_draw_contextual_ring()`, drawing a neon-cyan ring (`#55e8f2`) with four radial polygon spikes and an orange dot (`#ffc04d`). This completely overrides the authentic SOCOM 2 chartreuse brackets (`#d5e7ac`) and decoded PS2 textures. Furthermore, calling `draw_arc(` causes `tools/ballistic_reference_reticle_regression.gd` line 19 (`source.find("draw_arc(") < 0`) to FAIL.
- **Reproduction Steps**:
  1. Boot `res://main.tscn`.
  2. Observe the reticle is a cyan ring with an orange center dot.
  3. Run Godot headless on `res://tools/ballistic_reference_reticle_regression.gd`.
  4. See failure: `BALLISTIC_REFERENCE_RETICLE_REGRESSION FAIL ["combat reticle has a faint disc instead of the old U-shaped arc"]`.
- **Translation Card**:
  - **Player intent**: The player sees the iconic SOCOM II chartreuse reticle brackets that expand with spread and turn red on enemy acquisition, with no modern neon-cyan ring or orange center dot.
  - **Acceptance rule**: `socom_dynamic_reticle.gd` renders authentic chartreuse brackets/textures (`#d5e7ac`), does not call `_draw_contextual_ring()`, and passes `tools/ballistic_reference_reticle_regression.gd`.
  - **System owner**: `SocomDynamicReticle`.
  - **Must not change**: Ballistic spread calculations, camera aim ownership, server shot verification.
  - **Proof**: `tools/ballistic_reference_reticle_regression.gd` passes with exit code 0.

---

### Defect 2: Source Family Suppresses Shot Bounce Amplitude, Breaking Reticle Render Integration
- **Severity**: MEDIUM (Regression Failure / Broken Shot Kick Presentation)
- **File & Line**: `scripts/ui/socom_dynamic_reticle.gd:167-172`, `tools/reticle_render_integration.gd:58-63`
- **Verbatim Excerpt**:
```gdscript
func notify_shot(shot_index: int = 1, intensity: float = 1.0) -> void:
    if not source_family.is_empty():
        # Camera VRC already supplies the moving aim center. Weapon bloom
        # supplies spread. Do not add our unverified second kick/opening layer.
        shot_gap_impulse = 0.0
        shot_bounce_amplitude = 0.0
        return
```
```gdscript
    var bounced_center: Vector2 = dynamic_reticle.call("get_visual_center")
    _expect(
        bounced_center.y < authoritative_center.y
        and float(dynamic_reticle.get("shot_bounce_amplitude")) > 0.0,
        "reference shape bounces upward after a shot"
    )
```
- **Technical Explanation**:
  `tools/reticle_render_integration.gd` tests canonical `main.tscn` play and asserts that firing a shot produces a transient upward cosmetic kick on the reticle (`shot_bounce_amplitude > 0.0` and `bounced_center.y < authoritative_center.y`). Because `notify_shot()` clears `shot_bounce_amplitude = 0.0` whenever `source_family` is set (which is true for all 32 weapons), the visual center never kicks upward, causing `tools/reticle_render_integration.gd` to fail.
- **Reproduction Steps**:
  1. Run `/Users/kiwimango/Applications/Godot-4.7.1.app/Contents/MacOS/Godot --headless --path /Users/kiwimango/socom-141-camera-lab --script res://tools/reticle_render_integration.gd`.
  2. Test fails on line 59: `RETICLE_RENDER_INTEGRATION FAIL ["reference shape bounces upward after a shot"]`.
- **Translation Card**:
  - **Player intent**: Firing a weapon produces a crisp, transient cosmetic upward bounce on the reticle ticks without altering ballistic shot trajectory.
  - **Acceptance rule**: `notify_shot()` provides an upward visual kick for all active weapon configurations while keeping authoritative aim centered, and `tools/reticle_render_integration.gd` passes.
  - **System owner**: `SocomDynamicReticle`.
  - **Must not change**: Ballistic convergence, camera aim intent, weapon rate of fire.
  - **Proof**: `tools/reticle_render_integration.gd` passes with exit code 0.

---

### Defect 3: Floating 3D Holographic Loadout Card Replaces Authentic Screen-Space Tactical Plate
- **Severity**: HIGH (Feel Discrepancy Against Authentic SOCOM 2)
- **File & Line**: `scripts/ui/socom_loadout_card_hud.gd:92-137`, `scripts/ui/socom_loadout_card_hud.gd:212-214`, `config/contextual_hud.json:3,12`
- **Verbatim Excerpt**:
```gdscript
func _draw() -> void:
    if not visible or not _anchor_valid:
        return
    if bool(attention.profile.enabled):
        _draw_contextual()
        return
```
```gdscript
func _update_floating_position(delta: float) -> void:
    if not bool(attention.profile.get("floating_enabled", false)):
        return
    var camera := get_viewport().get_camera_3d()
...
    var torso := _follow_player.global_position + Vector3.UP * height * 0.8
    torso = _animated_torso_anchor(torso)
...
    var desired := camera.unproject_position(torso) + Vector2(
        float(attention.profile.floating_offset_x), offset_y)
    position = position.lerp(desired, 1.0 - exp(-float(attention.profile.floating_follow_speed) * delta)) if _floating_initialized else desired
```
- **Technical Explanation**:
  In authentic *SOCOM II*, weapon ammunition, fire mode, and grenades are presented in a fixed screen-space tactical HUD plate anchored to the screen corner. `SocomLoadoutCardHUD` contains a fully functional, authentic tactical card implementation in `_draw()` (lines 216–284). However, `config/contextual_hud.json` enables `"floating_enabled": true`, which continuously projects the player's 3D spine bone to float the HUD around the screen in world perspective. This creates an unauthentic, distracting floating holographic effect.
- **Reproduction Steps**:
  1. Boot `res://main.tscn`.
  2. Move or strafe the operator.
  3. Observe the health arc and ammo readouts floating and bobbing beside the operator's body instead of resting firmly in the screen corner.
- **Translation Card**:
  - **Player intent**: The player sees a crisp, tactical military loadout card anchored permanently in the bottom-right corner of the screen, displaying weapon name, ammo count, fire mode pips, and grenade badges.
  - **Acceptance rule**: The loadout card is fixed in screen space (`PRESET_BOTTOM_RIGHT`), does not unproject or follow the operator's 3D spine, and renders the standard rectangular tactical card.
  - **System owner**: `SocomLoadoutCardHUD`.
  - **Must not change**: Weapon ammo reporting, grenade inventory counting, fire mode selection.
  - **Proof**: Live inspection in `main.tscn` and `tools/loadout_hud_scorecard_regression.gd`.

---

### Defect 4: Stance Indicator Hardcoded Position Collides with Player Status Panel
- **Severity**: MEDIUM (UI Layout Collision)
- **File & Line**: `scripts/ui/socom_stance_indicator.gd:20-24`, `scripts/runtime/main_gameplay_hud.gd:156-160`, `scenes/ui/gameplay_hud.tscn:26-34`
- **Verbatim Excerpt**:
```gdscript
func _ready() -> void:
    custom_minimum_size = Vector2(44, 52)
    set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
    offset_left = 22.0
    offset_top = -140.0
    offset_right = 72.0
    offset_bottom = -88.0
```
```gdscript
func _build_player_status_ui(layer: CanvasLayer) -> void:
    var panel := PanelContainer.new()
    panel.name = "PlayerStatusHUD"
...
    panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
    panel.offset_left = 18.0
    panel.offset_right = 250.0
    panel.offset_top = -112.0
    panel.offset_bottom = -18.0
```
- **Technical Explanation**:
  `scenes/ui/gameplay_hud.tscn` authored `StanceIndicator` at `offset_left = 280.0, offset_right = 340.0`, positioning it neatly to the right of the status panel. However, `socom_stance_indicator.gd:21-24` overrides these offsets in `_ready()` to `offset_left = 22.0, offset_right = 72.0, offset_top = -140.0, offset_bottom = -88.0`. Because `PlayerStatusHUD` spans `offset_left = 18.0` to `250.0` and `offset_top = -112.0` to `-18.0`, the stance icon renders directly on top of the "HEALTH 100 / 100" text.
- **Reproduction Steps**:
  1. Boot `res://main.tscn` with standard status UI visible.
  2. Look at the bottom-left corner.
  3. The stance silhouette overlaps the top lines of the status text.
- **Translation Card**:
  - **Player intent**: The player clearly reads health, ammo, and grenade text in the status panel, with the operator stance silhouette positioned adjacent to the panel without clipping.
  - **Acceptance rule**: `SocomStanceIndicator` offsets are positioned to the right of `PlayerStatusHUD` (`offset_left >= 256.0`), eliminating visual overlap.
  - **System owner**: `SocomStanceIndicator`.
  - **Must not change**: Stance state mapping (`STAND`, `CROUCH`, `PRONE`, `SPRINT`), player posture synchronization.
  - **Proof**: Live inspection in `main.tscn` verifying zero bounding-box intersection.

---

### Defect 5: Public Training Range Title and Tactical Compass Render on Top of Each Other
- **Severity**: MEDIUM (UI Layout Collision / Text Legibility)
- **File & Line**: `scripts/runtime/main_gameplay_hud_builder.gd:184-197`, `scripts/ui/socom_tactical_compass.gd:40-44`
- **Verbatim Excerpt**:
```gdscript
static func _build_public_training_navigation(hud: Node, layer: CanvasLayer) -> void:
    var title := Label.new()
    title.name = "PublicTrainingRangeTitle"
    title.text = "TRAINING RANGE"
    title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    title.add_theme_font_size_override("font_size", 18)
    title.add_theme_color_override("font_color", Color("8bc5ae"))
    title.set_anchors_preset(Control.PRESET_CENTER_TOP)
    title.offset_left = -130.0
    title.offset_right = 130.0
    title.offset_top = 16.0
    title.offset_bottom = 48.0
    layer.add_child(title)
```
```gdscript
func _center_on_screen() -> void:
    var vp_size := get_viewport_rect().size
    position = Vector2((vp_size.x - compass_width) * 0.5, 14.0)
    size = Vector2(compass_width, compass_height)
```
- **Technical Explanation**:
  `PublicTrainingRangeTitle` is anchored at top center with `y = 16.0 to 48.0`. `SocomTacticalCompass` centers itself at `y = 14.0, height = 32.0` (`y = 14.0 to 46.0`). Both elements occupy the exact same top-center screen region, drawing the green text "TRAINING RANGE" directly across the yellow compass tape and tick marks.
- **Reproduction Steps**:
  1. Boot `res://main.tscn` in public training mode.
  2. Inspect top center of viewport.
  3. Text and compass tape are superimposed.
- **Translation Card**:
  - **Player intent**: The player reads both the Tactical Compass heading tape and the Training Range title without visual collision.
  - **Acceptance rule**: `PublicTrainingRangeTitle` is positioned either above or below the compass (e.g. `offset_top >= 52.0` or compass positioned below title), eliminating overlap.
  - **System owner**: `SocomMainGameplayHudBuilder`.
  - **Must not change**: Compass yaw calculation, objective waypoint markers.
  - **Proof**: Live inspection in public training mode.

---

### Defect 6: HUD Toggle Button Disappears When HUD is Hidden (Irreversible via Mouse/Touch)
- **Severity**: HIGH (Usability & Accessibility Defect)
- **File & Line**: `scripts/runtime/main_gameplay_hud_builder.gd:243-244`, `scripts/runtime/main_gameplay_hud_builder.gd:265-267`
- **Verbatim Excerpt**:
```gdscript
static func set_hud_mechanics_visible(hud: Node, enabled: bool) -> void:
    if hud.gameplay_layer != null:
        hud.gameplay_layer.visible = enabled
...
    if hud.hud_toggle_button != null:
        hud.hud_toggle_button.visible = enabled
        hud.hud_toggle_button.text = "HIDE HUD" if enabled else "SHOW HUD"
```
- **Technical Explanation**:
  When `set_hud_mechanics_visible(hud, false)` is called, line 244 hides `hud.gameplay_layer` and line 266 sets `hud.hud_toggle_button.visible = false`. Even though line 267 updates the button text to `"SHOW HUD"`, the button is invisible and parented to an invisible `CanvasLayer`. A player on mouse or touch controls cannot click the button to restore the HUD.
- **Reproduction Steps**:
  1. In the Training Range, click the "HIDE HUD" button.
  2. The HUD hides, and the button vanishes.
  3. It is impossible to unhide the HUD using the mouse.
- **Translation Card**:
  - **Player intent**: Clicking the HUD toggle button hides gameplay HUD elements while keeping a small, unobtrusive "SHOW HUD" button accessible for mouse/touch restoration.
  - **Acceptance rule**: When HUD mechanics are hidden, `hud_toggle_button` remains visible and interactive on a dedicated top-level canvas layer, displaying "SHOW HUD". Clicking it restores full HUD visibility.
  - **System owner**: `SocomMainGameplayHudBuilder`.
  - **Must not change**: `H` key input binding, clean hiding of reticle and tactical cards.
  - **Proof**: `tools/public_training_range_regression.gd` and interactive mouse click verification.

---

### Defect 7: HUD Toggle Leaves Active Per-Frame Processing and Mutates Panel Visibility
- **Severity**: MEDIUM (Performance Waste & Leaky State Mutation)
- **File & Line**: `scripts/runtime/main_frame_runtime.gd:111`, `scripts/runtime/main_gameplay_hud.gd:177-244`
- **Verbatim Excerpt**:
```gdscript
func process(delta: float) -> void:
    _update_player_status_ui()
```
```gdscript
func _update_player_status_ui() -> void:
    if player_status_label == null or player == null:
        return
...
    player_status_label.text = (...)
...
    if loadout_card_hud != null:
        loadout_card_hud.bind_player(player)
        player_status_panel.visible = not bool(loadout_card_hud.attention.profile.enabled)
        loadout_card_hud.update_weapon_state(...)
        loadout_card_hud.update_grenade_state(...)
        loadout_card_hud.update_health(...)
```
- **Technical Explanation**:
  `main_frame_runtime.gd` calls `_update_player_status_ui()` every frame during `process()`. Unlike `_update_crosshair()`, `_update_player_status_ui()` does not check `hud_mechanics_visible`. It continuously performs string allocations, dictionary lookups, and loadout card updates while the HUD is toggled off. Moreover, line 211 resets `player_status_panel.visible = true` on every frame, violating the hidden state.
- **Reproduction Steps**:
  1. Toggle HUD mechanics off with `H`.
  2. Step one frame in the debugger.
  3. Observe `_update_player_status_ui()` still executing and setting `player_status_panel.visible = true`.
- **Translation Card**:
  - **Player intent**: Toggling the HUD off stops all HUD UI processing overhead on the CPU and keeps all HUD element nodes cleanly hidden.
  - **Acceptance rule**: `_update_player_status_ui()` returns immediately if `not hud_mechanics_visible`, avoiding per-frame string formatting and preserving hidden panel visibility.
  - **System owner**: `SocomMainGameplayHud`.
  - **Must not change**: Live gameplay state (health, ammo, weapon controller).
  - **Proof**: Profile frame execution with HUD off and verify zero calls to string formatting.

---

### Defect 8: Camera Obstruction Query Lacks Collision Mask Filtering
- **Severity**: MEDIUM (Camera Collision Architecture Defect)
- **File & Line**: `scripts/camera/camera_passage_policy.gd:35-42`, `scripts/camera/camera_collision_solver.gd:79-83`
- **Verbatim Excerpt**:
```gdscript
    var motion_query := PhysicsShapeQueryParameters3D.new()
    motion_query.shape = shape
    motion_query.transform = Transform3D(Basis.IDENTITY, anchor)
    motion_query.motion = motion
    motion_query.margin = margin
    motion_query.exclude = effective_exclude
    motion_query.collide_with_areas = false
    var result: PackedFloat32Array = space.cast_motion(motion_query)
```
- **Technical Explanation**:
  In `camera_passage_policy.gd`, `motion_query.collision_mask` is not explicitly assigned, leaving it at Godot's default `0xFFFFFFFF` (all 32 layers). Furthermore, `camera_collision_solver.gd` only adds the local player RID to `exclude`. If an NPC, teammate, enemy player, or dynamic physics body passes behind the player, the camera treats it as a solid wall and zooms into the player's neck.
- **Reproduction Steps**:
  1. Place a target dummy or network player on collision layer 1 immediately behind the player.
  2. Orbit the camera through the dummy.
  3. The camera collides with the character mesh and aggressively compresses.
- **Translation Card**:
  - **Player intent**: The camera smoothly glides through other player characters and dynamic props, colliding only with static world architecture.
  - **Acceptance rule**: `camera_passage_policy.gd` sets `motion_query.collision_mask = 1` (world geometry only), ignoring character bodies and dynamic non-world layers.
  - **System owner**: `SocomCameraPassagePolicy`.
  - **Must not change**: Player collision mask, bullet collision mask, hurtbox detection.
  - **Proof**: Spawn dummy behind player and orbit camera; camera does not compress.

---

### Defect 9: 15-Pixel Mouse Aim Deadzone Impairs Precision Micro-Aiming
- **Severity**: MEDIUM (Aim Feel Defect on Mouse Input)
- **File & Line**: `scripts/camera/mouse_aim_model.gd:37-46`, `scripts/camera/camera_profile.gd:40-41`
- **Verbatim Excerpt**:
```gdscript
    var touch_distance: float = (
        (
            deadzone_radius_px
            if deadzone_radius_px >= 0.0
            else profile.mouse_string_deadzone_radius_px
        )
        + profile.mouse_string_blue_radius_px
    )
    if blue_offset_pixels.length() <= touch_distance:
        return
```
- **Technical Explanation**:
  `mouse_string_deadzone_radius_px` defaults to 10.0 px, and `mouse_string_blue_radius_px` is 5.0 px, establishing a 15.0 px deadzone. Any fine mouse displacement under 15 pixels is discarded (`return`). In tactical PC shooting, this introduces noticeable input stickiness, preventing micro-adjustments for distant headshots.
- **Reproduction Steps**:
  1. Aim at a distant target using a mouse.
  2. Slowly nudge the mouse by 5–10 pixels.
  3. The crosshair remains stationary until the 15-pixel threshold is crossed.
- **Translation Card**:
  - **Player intent**: The player experiences responsive 1:1 mouse input where subtle hand movements accurately adjust crosshair aim without a deadzone deadband.
  - **Acceptance rule**: When mouse input is active, fine movements directly update `intent_yaw` and `intent_pitch` (deadzone = 0 for mouse or configurable), while controller stick deadzone remains preserved.
  - **System owner**: `SocomMouseAimModel`.
  - **Must not change**: Controller stick deadzone, camera orbit drag smoothing.
  - **Proof**: Micro-motion test in `mouse_aim_string_regression.gd`.

---

### Defect 10: Ballistic Convergence Regression Failure on Range Target Headshots
- **Severity**: HIGH (Regression Failure in Authored Ballistics Test)
- **File & Line**: `tools/ballistic_convergence_regression.gd:86-117`, `scripts/camera/camera_aim_resolver.gd:47-56`
- **Verbatim Excerpt**:
```gdscript
ERROR: BALLISTIC_CONVERGENCE_REGRESSION: blue sight acquires the animated head area instead of scenery behind it
ERROR: BALLISTIC_CONVERGENCE_REGRESSION: settled muzzle shot aimed at the blue head sight registers HEAD
ERROR: BALLISTIC_CONVERGENCE_REGRESSION: clean rifle headshot puts the 100 HP target down
```
- **Technical Explanation**:
  `tools/ballistic_convergence_regression.gd` tests whether a target dummy aligned on the camera sight line registers a headshot. Running the test in Godot 4.7.1 fails because the ray query in `camera_aim_resolver.gd` penetrates the dummy's head area and hits the background static wall (`@StaticBody3D@7`), resulting in 0 damage.
- **Reproduction Steps**:
  1. Run `/Users/kiwimango/Applications/Godot-4.7.1.app/Contents/MacOS/Godot --headless --path /Users/kiwimango/socom-141-camera-lab --script res://tools/ballistic_convergence_regression.gd`.
  2. Test fails on line 87 with 3 logged errors.
- **Translation Card**:
  - **Player intent**: When the player aligns the reticle with an enemy's head, the camera aim resolver correctly identifies the head hurtbox and shots converge cleanly on the head.
  - **Acceptance rule**: The camera aim ray reliably intersects animated hurtbox areas on layer 3 (1 << 2) before background geometry, and `tools/ballistic_convergence_regression.gd` passes.
  - **System owner**: `SocomCameraAimResolver`.
  - **Must not change**: Hurtbox collision layers, server damage validation.
  - **Proof**: `tools/ballistic_convergence_regression.gd` passes with exit code 0.

---

## 4. Regression Test Suite Execution Summary

| Test Script | Status | Log / Output Summary |
|---|---|---|
| `tools/feature_contract_regression.gd` | **PASS** | 121 feature contracts validated forming complete Godot graphs. |
| `tools/public_training_range_regression.gd` | **PASS** | All 47 training range checks passed (HUD toggle, loadout, bomb, dummies). |
| `tools/camera_obstruction_guard_regression.gd` | **PASS** | Obstruction hold, release guard, and sustained clearance pass. |
| `tools/camera_passage_perception_regression.gd` | **PASS** | Doorway soft occluders and frustum perception pass. |
| `tools/loadout_hud_scorecard_regression.gd` | **PASS** | Wheel inputs, fire mode cycles, and roster HUD pass. |
| `tools/stance_hud_bloom_regression.gd` | **PASS** | Stationary, moving, and stance bloom caps pass. |
| `tools/action_hud_tracking_regression.gd` | **PASS** | Spine anchor tracking and direction combo sampling pass. |
| `tools/shared_aim_chain_regression.gd` | **PASS** | Torso pitch/yaw from shared target and muzzle alignment pass. |
| `tools/mouse_aim_string_regression.gd` | **PASS** | String guide toggling and aim leash bounds pass. |
| `tools/mouse_cursor_cage_regression.gd` | **PASS** | Cage edge turning and clamping pass. |
| `tools/contextual_hud_regression.gd` | **PASS** | Snapshot deduplication, fades, and glances pass. |
| `tools/socom2_reticle_regression.gd` | **PASS** | 32 weapon profiles pass (forced `custom.enabled = false` in test fixture). |
| `tools/custom_reticle_regression.gd` | **PASS** | Custom geometry strokes and alpha profiles pass. |
| `tools/ballistic_reference_reticle_regression.gd` | **FAIL** | `combat reticle has a faint disc instead of the old U-shaped arc` (failed due to `draw_arc(` in `socom_dynamic_reticle.gd:332`). |
| `tools/reticle_render_integration.gd` | **FAIL** | `reference shape bounces upward after a shot` (failed due to `shot_bounce_amplitude = 0.0` in `socom_dynamic_reticle.gd:171`). |
| `tools/ballistic_convergence_regression.gd` | **FAIL** | `blue sight acquires the animated head area instead of scenery behind it` (failed to acquire dummy head). |

---

## 5. Architectural Compliance & Integration Graph Analysis

Per `docs/GODOT_FEATURE_INTEGRATION_CONTRACT.md`:
1. **Single Responsibility**:
   - `SocomCameraRig` owns camera positioning, collision recovery, and aim-intent resolution.
   - `SocomDynamicReticle` owns reticle drawing and bloom expansion presentation.
   - `SocomLoadoutCardHUD` owns weapon/ammo status presentation.
   - `CharacterBody3D` owns movement and collision.
   - No conflicting writers were found on player transforms.
2. **Canonical Scene Parity**:
   - Both `res://main.tscn` and `res://game_launcher.tscn` wire into canonical camera and HUD nodes.
   - Training Range in `main.tscn` consumes identical camera profiles as multiplayer modes.
3. **Identified Architectural Violations**:
   - In `socom_dynamic_reticle.gd`, `_draw_custom_reference()` reads `contextual_hud.json` directly from disk rather than receiving configuration through the weapon contract or profile, bypassing the shared contract boundary.
   - In `socom_stance_indicator.gd`, `_ready()` hardcodes local offsets that overwrite scene-configured layout parameters.

---
*Report compiled by `explorer_camera_hud_1`. Read-only investigation complete.*
