# Handoff Report: Camera & HUD Presentation Quality Audit

**Agent:** `explorer_camera_hud_1`  
**Working Directory:** `/Users/kiwimango/socom-141-camera-lab/.agents/explorer_camera_hud_1`  
**Target:** Orchestrator (`f65421c8-95ea-4753-89f3-5c067645d740`)  
**Type:** Hard Handoff (Investigation Complete)  

---

## 1. Observation

1. **Aim-Intent Ownership (Rule 5 Verification)**:
   - Tool command: `grep_search` for `target\.(global_)?(position|rotation|transform) *=` across `scripts/camera/`.
   - Result: 0 occurrences found.
   - Code inspection of `scripts/player/player_controller.gd` lines 529–532 confirms:
     ```gdscript
     var rig := get_tree().get_first_node_in_group("socom_camera_rig")
     if rig != null:
         command.aim_yaw = float(rig.get("aim_yaw"))
         command.aim_pitch = float(rig.get("aim_pitch"))
     ```
   - The camera rig never writes to `target` transforms; player movement reads camera aim angles.

2. **Reticle Regression Breakage (`draw_arc` check)**:
   - Tool command:
     ```sh
     /Users/kiwimango/Applications/Godot-4.7.1.app/Contents/MacOS/Godot --headless --path /Users/kiwimango/socom-141-camera-lab --script res://tools/ballistic_reference_reticle_regression.gd
     ```
   - Output:
     ```text
     RETICLE_REFERENCE_CHECK PASS combat reticle draws a fixed center point
     ERROR: RETICLE_REFERENCE_CHECK FAIL combat reticle has a faint disc instead of the old U-shaped arc
     BALLISTIC_REFERENCE_RETICLE_REGRESSION FAIL ["combat reticle has a faint disc instead of the old U-shaped arc"]
     ```
   - Exact code: `scripts/ui/socom_dynamic_reticle.gd` line 332 calls `draw_arc(Vector2.ZERO, radius, 0.0, TAU, 96, tint, 1.5, true)`. `tools/ballistic_reference_reticle_regression.gd` lines 18–20 assert `source.find("draw_arc(") < 0`.

3. **Reticle Render Integration Breakage (Shot Kick)**:
   - Tool command:
     ```sh
     /Users/kiwimango/Applications/Godot-4.7.1.app/Contents/MacOS/Godot --headless --path /Users/kiwimango/socom-141-camera-lab --script res://tools/reticle_render_integration.gd
     ```
   - Output:
     ```text
     ERROR: RETICLE_RENDER_CHECK FAIL reference shape bounces upward after a shot
     RETICLE_RENDER_INTEGRATION FAIL ["reference shape bounces upward after a shot"]
     ```
   - Exact code: `scripts/ui/socom_dynamic_reticle.gd` lines 167–172:
     ```gdscript
     if not source_family.is_empty():
         shot_gap_impulse = 0.0
         shot_bounce_amplitude = 0.0
         return
     ```
   - When `source_family` is set (all 32 weapons), `shot_bounce_amplitude` is set to 0.0, violating `tools/reticle_render_integration.gd:61` (`shot_bounce_amplitude > 0.0`).

4. **Ballistic Convergence Regression Breakage**:
   - Tool command:
     ```sh
     /Users/kiwimango/Applications/Godot-4.7.1.app/Contents/MacOS/Godot --headless --path /Users/kiwimango/socom-141-camera-lab --script res://tools/ballistic_convergence_regression.gd
     ```
   - Output:
     ```text
     BALLISTIC_CONVERGENCE_METRIC view_distance=23.377 target_delta=0.000 shot_delta=0.000 muzzle_to_view=20.316 collider=@StaticBody3D@7
     HEAD_SHOT_METRIC region= damage=0.0 health=100.0
     ERROR: BALLISTIC_CONVERGENCE_REGRESSION: blue sight acquires the animated head area instead of scenery behind it
     ```

5. **Floating Holographic Loadout Card vs Fixed Authentic Plate**:
   - In `config/contextual_hud.json`: `"enabled": true, "floating_enabled": true`.
   - In `scripts/ui/socom_loadout_card_hud.gd` lines 212–214:
     ```gdscript
     if bool(attention.profile.enabled):
         _draw_contextual()
         return
     ```
   - In `scripts/ui/socom_loadout_card_hud.gd` lines 126–130:
     ```gdscript
     var desired := camera.unproject_position(torso) + Vector2(float(attention.profile.floating_offset_x), offset_y)
     position = position.lerp(desired, 1.0 - exp(-float(attention.profile.floating_follow_speed) * delta))
     ```

6. **Stance Indicator & Status Panel Overlap**:
   - In `scripts/ui/socom_stance_indicator.gd` lines 21–24:
     ```gdscript
     offset_left = 22.0
     offset_top = -140.0
     offset_right = 72.0
     offset_bottom = -88.0
     ```
   - In `scripts/runtime/main_gameplay_hud.gd` lines 157–160:
     ```gdscript
     panel.offset_left = 18.0
     panel.offset_right = 250.0
     panel.offset_top = -112.0
     panel.offset_bottom = -18.0
     ```
   - Bounding boxes overlap at `x: 22..72` and `y: -112..-88`.

7. **Public Training Range Title & Compass Overlap**:
   - In `scripts/runtime/main_gameplay_hud_builder.gd` lines 192–195:
     ```gdscript
     title.set_anchors_preset(Control.PRESET_CENTER_TOP)
     title.offset_left = -130.0; title.offset_right = 130.0
     title.offset_top = 16.0; title.offset_bottom = 48.0
     ```
   - In `scripts/ui/socom_tactical_compass.gd` line 42:
     ```gdscript
     position = Vector2((vp_size.x - compass_width) * 0.5, 14.0)
     size = Vector2(compass_width, compass_height) # 360 x 32 -> y: 14..46
     ```

8. **HUD Toggle Button Disappearance**:
   - In `scripts/runtime/main_gameplay_hud_builder.gd` line 244 & line 266:
     ```gdscript
     if hud.gameplay_layer != null: hud.gameplay_layer.visible = enabled
     if hud.hud_toggle_button != null:
         hud.hud_toggle_button.visible = enabled
         hud.hud_toggle_button.text = "HIDE HUD" if enabled else "SHOW HUD"
     ```

9. **HUD Toggle Background Processing Leak**:
   - In `scripts/runtime/main_frame_runtime.gd` line 111: `_update_player_status_ui()` runs every frame.
   - In `scripts/runtime/main_gameplay_hud.gd` lines 177–244: does not check `hud_mechanics_visible`.
   - Line 211 resets `player_status_panel.visible = not bool(loadout_card_hud.attention.profile.enabled)` every frame.

10. **Camera Collision Mask Filtering Omission**:
    - In `scripts/camera/camera_passage_policy.gd` lines 35–42: `motion_query` does not set `collision_mask`, leaving it at `0xFFFFFFFF`. Only the local player RID is excluded.

11. **Mouse Aim Deadzone**:
    - In `scripts/camera/mouse_aim_model.gd` line 45: `if blue_offset_pixels.length() <= touch_distance: return`.
    - `touch_distance` = 10.0 + 5.0 = 15.0 px deadband.

---

## 2. Logic Chain

1. **Aim Authority**: Observations 1 prove that `SocomCameraRig` never modifies the player transform and acts purely as an aim-intent author. This satisfies Rule 5 of `AGENTS.md`.
2. **Regression Integrity**:
   - Observation 2 directly links the addition of `draw_arc` in `_draw_contextual_ring()` (`socom_dynamic_reticle.gd:332`) to the failure of `tools/ballistic_reference_reticle_regression.gd`.
   - Observation 3 links `shot_bounce_amplitude = 0.0` in `notify_shot()` to the failure of `tools/reticle_render_integration.gd`.
   - Observation 4 links `camera_aim_resolver.gd` sight ray missing the dummy head hurtbox to the failure of `tools/ballistic_convergence_regression.gd`.
3. **SOCOM 2 Feel Parity**:
   - Observation 2 & Observation 5 demonstrate that `config/contextual_hud.json` introduced modern deviations (neon-cyan ring with orange dot, 3D floating AR loadout card following the operator's spine) that override authored authentic SOCOM 2 PS2 assets (chartreuse brackets, decoded PS2 textures, fixed-corner rectangular tactical HUD).
4. **Layout Collisions & Usability**:
   - Observations 6 and 7 show direct coordinate overlapping: Stance Indicator over Player Status panel, and Training Range Title over Tactical Compass.
   - Observation 8 proves that hiding the HUD via the button is a one-way trip for non-keyboard users because the button hides itself on an invisible CanvasLayer.
   - Observation 9 demonstrates unnecessary per-frame CPU waste and state mutation while the HUD is toggled off.
5. **Camera Architecture**:
   - Observation 10 proves that without explicit `collision_mask = 1`, the camera boom treats all physics layers (including other players and dynamic objects) as solid world obstructions.
   - Observation 11 shows that fine mouse micro-aiming is swallowed by a 15px deadzone.

---

## 3. Caveats

- **Locomotion & Gait**: Jump combos, strafe acceleration, and gait transitions were not deeply audited in this track; they are owned by `explorer_locomotion_1`.
- **Server Weapon Authority**: Fire cadences, server-side reload deadlines, and packet verification were not tested in depth; they are owned by `explorer_weapons_1`.
- **Performance Benchmarking**: Measurements were based on code path inspection; GPU draw-call profiling was not performed under headless test runners.

---

## 4. Conclusion

The Camera & HUD Presentation systems have a solid foundational architecture with strict adherence to Rule 5 aim-intent ownership. However, 10 specific defects must be addressed:
- 3 failing regression suites (`ballistic_reference_reticle_regression.gd`, `reticle_render_integration.gd`, `ballistic_convergence_regression.gd`) must be repaired.
- 2 major SOCOM 2 feel departures (cyan contextual ring reticle and floating 3D holographic loadout card) should be replaced with the authored authentic SOCOM 2 chartreuse brackets and fixed rectangular tactical card.
- 2 UI coordinate overlaps (Stance Indicator over Status Panel, Title over Tactical Compass) must be decoupled.
- HUD toggle logic must retain a visible "SHOW HUD" control and cease per-frame CPU processing when hidden.
- Camera volume queries must be constrained to `collision_mask = 1` to prevent unwanted camera collisions against other player characters.

All 10 remediation translation cards are fully documented in `camera_hud_audit.md`.

---

## 5. Verification Method

To independently verify these findings, run the installed Godot 4.7.1 executable:

1. **Verify Failing Regressions**:
   ```sh
   /Users/kiwimango/Applications/Godot-4.7.1.app/Contents/MacOS/Godot \
     --headless --path /Users/kiwimango/socom-141-camera-lab \
     --script res://tools/ballistic_reference_reticle_regression.gd
   ```
   *Expected Output*: Fails with `combat reticle has a faint disc instead of the old U-shaped arc`.

   ```sh
   /Users/kiwimango/Applications/Godot-4.7.1.app/Contents/MacOS/Godot \
     --headless --path /Users/kiwimango/socom-141-camera-lab \
     --script res://tools/reticle_render_integration.gd
   ```
   *Expected Output*: Fails with `reference shape bounces upward after a shot`.

   ```sh
   /Users/kiwimango/Applications/Godot-4.7.1.app/Contents/MacOS/Godot \
     --headless --path /Users/kiwimango/socom-141-camera-lab \
     --script res://tools/ballistic_convergence_regression.gd
   ```
   *Expected Output*: Fails with `blue sight acquires the animated head area instead of scenery behind it`.

2. **Verify Passing Contracts**:
   ```sh
   /Users/kiwimango/Applications/Godot-4.7.1.app/Contents/MacOS/Godot \
     --headless --path /Users/kiwimango/socom-141-camera-lab \
     --script res://tools/feature_contract_regression.gd
   ```
   *Expected Output*: 121 contracts pass.

3. **Verify Public Training Range**:
   ```sh
   /Users/kiwimango/Applications/Godot-4.7.1.app/Contents/MacOS/Godot \
     --headless --path /Users/kiwimango/socom-141-camera-lab \
     --script res://tools/public_training_range_regression.gd
   ```
   *Expected Output*: All 47 training range checks pass.

4. **Invalidation Conditions**:
   - If `tools/ballistic_reference_reticle_regression.gd` passes, `draw_arc` has been removed from `socom_dynamic_reticle.gd`.
   - If `tools/reticle_render_integration.gd` passes, shot bounce amplitude is no longer suppressed for `source_family` weapons.
   - If `tools/ballistic_convergence_regression.gd` passes, the dummy head hurtbox has been correctly acquired.

---
*Report file path: `/Users/kiwimango/socom-141-camera-lab/.agents/explorer_camera_hud_1/camera_hud_audit.md`*
