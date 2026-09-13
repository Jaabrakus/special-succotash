# Animated torso HUD tracking

Translation card: keep the split status HUD with the visible torso during left/right leans, dives, slides and recovery. Acceptance: the existing HUD reads the canonical Spine2 world position during each action, smooths screen translation, remains upright and clamped, and never writes player, camera or skeleton transforms. Owner: SocomLoadoutCardHUD. Protected: movement, camera, animation, shots/bloom and networking. Proof: action_hud_tracking_regression plus existing contextual/stance regressions and rendered canonical action captures.

MERGE: the old stance-height approximation correctly handled static crouch/prone but could not represent horizontal animated displacement or action recovery height. Read the existing driver skeleton, cache the chest bone lookup, and use actual height to blend the existing saved vertical offsets. Retain existing smoothing, left/right placement, size, attention, hidden-HUD behavior and missing-rig fallback. No new BoneAttachment, camera marker writer or replicated bone data.

The saved `config/contextual_hud.json` enables `follow_animated_torso` and names `mixamorig_Spine2`. `scripts/ui/socom_loadout_card_hud.gd::_animated_torso_anchor` reads:

```gdscript
return skeleton.global_transform * skeleton.get_bone_global_pose(_torso_bone_index).origin
```

This follows the [Godot Skeleton3D contract](https://docs.godotengine.org/en/stable/classes/class_skeleton3d.html#class-skeleton3d-method-get-bone-global-pose): the bone's global pose is relative to the skeleton, so the world transform must be applied. Only screen translation follows the animation, not roll/rotation. Both local and multiplayer HUD consumers already bind their canonical local actor to this same Control.

Verification: `ACTION_HUD_TRACKING PASS []` in the rendered canonical actor fixture, including both leans, slide, left/right/back dives and recovery; HUD visibility and protected transforms asserted at early/middle/late samples. The inherited weapon fixture originally hid all CanvasLayers and retained lean-toggle state; the test now keeps HUD visible and resets lean between cases. Contextual HUD and stance/bloom regressions also pass; all 120 feature contracts pass. Changed HUD script passes headless syntax check. Rendered captures were inspected for leans, slide and side dives. Quick integration gate remains blocked by the current `codex/render-deployment` branch rather than `main`; no merge or deployment performed. Existing disabled voice-capture warning remains outside scope.
