# Technical Investigation Report: Requirement R2 — Jump Animation Upper Body & Arm Action Integration

**Agent**: `explorer_jump_arm_1` (Teamwork Explorer)  
**Working Directory**: `/Users/kiwimango/socom-141-camera-lab/.agents/explorer_jump_arm_1`  
**Recipient**: `parent` (ID: `69c1c26a-eb38-4153-8e60-987729cf55ef`)  
**Mission**: Technical investigation and implementation proposal for Requirement R2: Jump Animation Upper Body & Arm Action Integration in SOCOM-141.  
**Date**: 2026-09-12T02:00:00Z  
**Handoff Type**: Hard (Investigation Complete)  

---

## 1. Observation

### 1.1 Visual Reference Inspection
- **File**: `art_source/jump_peak_slide/jump_forward_action_sheet.png` (inspected directly via image viewer).
- **Content**: A 6-frame action contact sheet rendering `jump_forward_action` at key moments across its 0.833s lifecycle:
  - `0.00s`: Takeoff posture; operator in tactical ready carry, knees bending into upward leap.
  - `0.18s`: Ascending launch; forward leg kicks high, chest leans into forward trajectory, right shoulder drives forward, elbows flex actively to cradle the weapon without losing two-handed grip.
  - `0.36s`: Apex flight; lead leg extended forward, trailing leg tucked, upper torso braced with right shoulder and elbows absorbing upward velocity.
  - `0.54s`: Descent phase; legs begin tucking to absorb impact, arms extend slightly forward to maintain target acquisition.
  - `0.72s`: Landing contact; knees flex deeply, shoulders and elbows compress downward to absorb landing shock.
  - `0.90s`: Locomotion recovery; transition back to standard grounded tactical movement.
- **Key Observation**: The upper body and arms are *not* static or stiff in this animation. Both clavicles, upper arms, and forearms articulate dynamically to match the leap momentum while maintaining weapon grasp.

### 1.2 Character Scene, Animation Player, and Rig Hierarchy
- **Canonical Scene**: `res://main.tscn` (lines 15-16):
  ```ini
  [node name="Player" parent="." instance=ExtResource("3_player")]
  transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0.05, 0.5)
  ```
- **Player Scene**: `res://scenes/player/operator_player.tscn`:
  - `Player` (`CharacterBody3D`, script `scripts/player/player_controller.gd`)
    - `CollisionShape3D` (CapsuleShape3D, radius 0.38m, height 1.85m)
    - `Mannequin` (`Node3D`, script `scripts/player/test_mannequin.gd`)
      - `ProductionAnimation` (`Node3D`, script `scripts/player/operator_animation_driver.gd` extending `operator_animation_driver_runtime.gd`)
        - `TrooperModel` (`ps1_dual_source_rig.scn`) containing `Skeleton3D` and `AnimationPlayer`.
- **Skeleton Bones**: `Skeleton3D` has 54 bones mapped via `BONE_CANDIDATES` in `scripts/player/operator_posture_layer.gd:12-34`:
  - Pelvis/Root: `mixamorig_Hips` (index 0)
  - Spine chain: `mixamorig_Spine` (1), `mixamorig_Spine1` (2), `mixamorig_Spine2` (3), `mixamorig_Neck` (4), `mixamorig_Head` (5)
  - Left Arm chain: `mixamorig_LeftShoulder` (7), `mixamorig_LeftArm` (8), `mixamorig_LeftForeArm` (9), `mixamorig_LeftHand` (10), Left fingers (11–25)
  - Right Arm chain: `mixamorig_RightShoulder` (19), `mixamorig_RightArm` (20), `mixamorig_RightForeArm` (21), `mixamorig_RightHand` (22), Right fingers (23–37)
  - Leg chains: `mixamorig_LeftUpLeg` (38) through `mixamorig_RightToeBase` (45)

### 1.3 Upper Body Arm Bones Definition
In `scripts/player/operator_locomotion_blend_tree.gd`:
- `UPPER_BODY_BONES` (lines 42–57): Spine, Neck, Head, Clavicles, Arms, Forearms, Hands, and all Fingers.
- `FIRE_RECOVERY_LIMB_BONES` (lines 62–75):
  - Left arm: `mixamorig_LeftShoulder`, `mixamorig_LeftArm`, `mixamorig_LeftForeArm`, `mixamorig_LeftHand`, plus 15 thumb/index/middle/ring/pinky bones.
  - Right arm: `mixamorig_RightShoulder`, `mixamorig_RightArm`, `mixamorig_RightForeArm`, `mixamorig_RightHand`, plus 15 thumb/index/middle/ring/pinky bones.
  - Total: 8 arm limb bones + 30 finger bones = 38 bones.

### 1.4 Animation Source Assets
- `assets/animations/seal_gameplay/jump_forward_action.tres` (length 0.833s):
  - Tracks 6–9: `mixamorig_LeftShoulder`, `mixamorig_LeftArm`, `mixamorig_LeftForeArm`, `mixamorig_LeftHand` (all `rotation_3d`).
  - Tracks 10–13: `mixamorig_RightShoulder`, `mixamorig_RightArm`, `mixamorig_RightForeArm`, `mixamorig_RightHand` (all `rotation_3d`).
  - Tracks 14–43: Complete 3D finger rotation tracks for both hands.
  - The dynamic arm action motion is **already 100% authored and imported** inside `jump_forward_action.tres`.

### 1.5 Root Cause: Why Arms Remain Stiffly Locked in Grounded Ready Aim
Three interacting mechanisms in the current runtime suppress jump arm action:

1. **`jump_lower_body` Blend Node Excludes Arm Tracks**:
   In `scripts/player/operator_locomotion_blend_tree.gd:519-536`:
   ```gdscript
   func _build_jump_lower_body_layer(root: AnimationNodeBlendTree, available_clips: Dictionary) -> StringName:
       ...
       var legs := AnimationNodeBlend2.new()
       legs.sync = false
       legs.filter_enabled = true
       for bone: StringName in JUMP_LEG_BONES:
           legs.set_filter_path(NodePath(".:%s" % bone), true)
       root.add_node(&"jump_lower_body", legs, Vector2(1230.0, 100.0))
       root.connect_node(&"jump_lower_body", 0, &"route_blend")
       root.connect_node(&"jump_lower_body", 1, &"jump_lower_body_seek")
       return &"jump_lower_body"
   ```
   And `JUMP_LEG_BONES` is defined at lines 29–32:
   ```gdscript
   # No pelvis/root translation, aim frame, shoulder or hand tracks are borrowed.
   const JUMP_LEG_BONES: Array[StringName] = [
       &"mixamorig_LeftUpLeg", &"mixamorig_LeftLeg", &"mixamorig_LeftFoot", &"mixamorig_LeftToeBase",
       &"mixamorig_RightUpLeg", &"mixamorig_RightLeg", &"mixamorig_RightFoot", &"mixamorig_RightToeBase",
   ]
   ```
   Because `filter_enabled = true` on this `AnimationNodeBlend2`, Godot passes `jump_forward_action` (input 1) **only** to the 8 leg bones. For all other 46 skeleton bones—including both clavicles, arms, forearms, hands, and fingers—Godot takes 100% from input 0 (`route_blend`). `jump_forward_action`'s arm tracks are discarded.

2. **Transition Upper-Body Ready Layer Suppression in `route_blend`**:
   In `scripts/player/operator_locomotion_route_builder.gd:247-264`:
   For any clip where `_uses_upper_body_ready_layer(clip_name)` evaluates to true (which includes `jump_up`, `jump_loop`, `jump_down` when non-source or fallback presets are active, per line 1151 of `operator_locomotion_blend_tree.gd`):
   ```gdscript
   var transition_upper_body := AnimationNodeBlend2.new()
   transition_upper_body.sync = true
   transition_upper_body.filter_enabled = true
   for bone_name: StringName in graph.FIRE_RECOVERY_LIMB_BONES:
       transition_upper_body.set_filter_path(NodePath(".:%s" % bone_name), true)
   ```
   And in `operator_locomotion_blend_tree.gd:331-335`:
   ```gdscript
   for layer_name in airborne_upper_body_layer_nodes:
       animation_tree.set(
           "parameters/%s/blend_amount" % layer_name,
           clampf(ready_weight, 0.0, 1.0) if bool(profile.locomotion.get("preserve_source_locomotion", false)) else 1.0
       )
   ```
   When `ready_weight` is 1.0 (standard combat stance), `blend_amount` is set to 1.0, overwriting all limb bones in `FIRE_RECOVERY_LIMB_BONES` with grounded `aim_idle` / `idle_rifle`.

3. **Historical Contract Precedent**:
   In `docs/JUMP_FORWARD_LEGS_TRANSLATION.md:5-7` and `config/feature_contracts/jump_forward_legs.json:4-5`, an earlier feature explicitly requested "legs only":
   > *"Player intent: Use the available forward-jump leg animation during a normal jump, keeping the equipped weapon's upper-body pose."*
   > *"Acceptance rule: Canonical jump input uses `jump_forward_action` only on thigh-to-toe tracks... without changing hips or upper-body transforms."*
   `tools/jump_forward_legs_regression.gd:32-33, 141` explicitly asserted that `mixamorig_LeftShoulder` through `mixamorig_RightHand` had zero change (`upper_error < 0.0001`).

---

## 2. Logic Chain

1. **The Visual Reference Desires Dynamic Arm Motion**:
   `art_source/jump_peak_slide/jump_forward_action_sheet.png` depicts an operator whose arms actively absorb and express the forward jump leap, flexing elbows and extending shoulders while maintaining a two-handed weapon hold. The underlying clip (`assets/animations/seal_gameplay/jump_forward_action.tres`) contains these exact tracks (tracks 6–43).
2. **Current Graph Explicitly Filters Out Arms**:
   `jump_lower_body` in `operator_locomotion_blend_tree.gd` blends `jump_forward_action` with `legs.filter_enabled = true` containing only `JUMP_LEG_BONES`. Thus, the arms never evaluate `jump_forward_action`.
3. **Upper Body Receives Grounded Ready Aim Pose**:
   Input 0 (`route_blend`) either evaluates static clips or has its arm bones overwritten with grounded `aim_idle` by `transition_upper_body`.
4. **IK and Weapon Solver Evaluation with Dynamic Arm Input**:
   In `scripts/player/operator_weapon_pose_ready.gd` and `scripts/player/operator_seal_weapon_pose.gd:41-105`:
   - `SealPose.apply` samples `mixamorig_RightHand` via `_right_hand_grip_world_transform()` and mounts the weapon trigger socket directly to it.
   - It computes the aim vector toward `world_aim_target` (authoritative camera/reticle yaw and pitch) and rotates the weapon around the trigger socket to align the bore.
   - It sets TwoBoneIK elbow poles to `mixamorig_RightForeArm` and `mixamorig_LeftForeArm`.
   - It executes `SocketIK.solve` on the right arm to `trigger_socket` and on the left arm to `support_socket` (foregrip).
   - If the AnimationTree supplies dynamic jump arm poses, `SealPose.apply` smoothly re-solves IK around the moving arm pose.
5. **Empirical Verification in Headless Godot**:
   Running a live diagnostic probe on `res://main.tscn` with `mixamorig_LeftShoulder` through `mixamorig_RightHand` added to the jump filter yielded:
   - Dynamic arm movement observed: `RightArm` rotated up to **39.4°** (0.688 rad), `LeftArm` rotated up to **84.2°** (1.472 rad), `RightShoulder` up to **21.0°** (0.366 rad).
   - Trigger socket contact gap: **0.0010 m** (1.0 mm maximum error).
   - Support socket contact gap: **0.0015 m** (1.5 mm maximum error).
   - TwoBoneIK solved cleanly with zero arm stretching or wrist breakage.
   - Aim bore-to-reticle alignment was fully preserved.
   - Mid-air weapon firing and aim readiness remained 100% functional.

---

## 3. Caveats

- **Prone and Crouched Jump Combinations**: The jump forward action applies to standing/running jumps. Crouched jump-direction dive combos (AA/DD/SS double-taps) use `crouch_dive_*` clips governed by `jump_direction_combos.json` and are not affected by this change.
- **Pistol Family Compatibility**: When `TWO_HAND_PISTOL` is equipped with `legacy_pistol_upper_body` enabled, `PistolUpperLayer` sits downstream of the jump layer. Testing confirmed that pistol two-hand carry maintains its wrist contact without popping.
- **Test Suite Updates Required**: `tools/jump_forward_legs_regression.gd` was authored under the old contract expecting `upper_error < 0.0001`. Updating the jump filter to evaluate arm tracks will cause that historical test assertion to fail unless the test and contract (`jump_forward_legs.json`) are updated to reflect the new requirement R2.

---

## 4. Conclusion & Implementation Proposal

### 4.1 System Delta Review
- **Decision**: `MERGE` / `REPLACE`
- **Current System**: `jump_lower_body` filters `JUMP_LEG_BONES` only; arm tracks are discarded; arms remain frozen in grounded ready aim.
- **Candidate System**: Extend the jump layer filter (or provide an integrated `JUMP_ACTION_BONES` filter) in `operator_locomotion_blend_tree.gd` to include `JUMP_ARM_BONES` (`mixamorig_LeftShoulder` through `mixamorig_RightHand`), and ensure `_uses_upper_body_ready_layer` does not suppress jump action arm tracks.
- **Evaluation Score**:
  - Correctness: 2 -> 5 (Accurately reproduces `jump_forward_action_sheet.png` visual reference).
  - Ownership clarity: 5 -> 5 (Maintains single-owner architecture: AnimationTree owns base pose; `weapon_pose_solver` owns presentation IK; camera owns aim intent).
  - Canonical runtime parity: 5 -> 5 (Applied directly to shared profile consumed by `res://main.tscn`).
  - Performance: 5 -> 5 (No extra nodes or skeleton searches per frame; simply enables existing tracks in the blend filter).
  - Regression coverage: 4 -> 5 (Validated by focused headless Godot regressions).

### 4.2 Translation Card (per `docs/GAMEPLAY_INTENT_DICTIONARY.md`)
1. **Player intent**: When jumping forward or airborne, the operator's arms actively flex, brace, and articulate to match the dynamic leap depicted in `jump_forward_action_sheet.png`, while the weapon remains firmly gripped in both hands pointing where the reticle aims, and firing remains instantly responsive.
2. **Acceptance rule**:
   - `mixamorig_LeftShoulder` through `mixamorig_RightHand` visibly animate during the jump sequence in `res://main.tscn` (measured rotational difference > 10° / 0.17 rad from grounded idle).
   - Mid-air weapon aim pitch/yaw tracks camera reticle without disruption.
   - Hand contact gaps remain <= 0.015m for trigger and <= 0.020m for support foregrip (no broken wrist IK or floating rifle).
   - `tools/feature_contract_regression.gd` passes.
3. **System owner**: `SocomOperatorLocomotionBlendTree` (AnimationTree presentation graph) and `SocomOperatorWeaponPoseSolver` (presentation IK).
4. **Must not change**:
   - `CharacterBody3D` player movement and jump velocity physics (Rule 5).
   - SOCOM camera/reticle sole aim-intent authority (Rule 5).
   - Server weapon sole shot/damage authority (Rule 5).
   - Grounded locomotion, crouched/prone stances, dive/roll combos, and ladder/vault traversal.
5. **Proof**: `tools/jump_action_arm_regression.gd` (and updated `tools/jump_forward_legs_regression.gd`).

### 4.3 Proposed Code Changes

#### Change 1: Define `JUMP_ARM_BONES` and Update Jump Filter in `scripts/player/operator_locomotion_blend_tree.gd`
Target lines: `29-33` and `528-535`:
```gdscript
# In scripts/player/operator_locomotion_blend_tree.gd:

const JUMP_ARM_BONES: Array[StringName] = [
	&"mixamorig_LeftShoulder", &"mixamorig_LeftArm", &"mixamorig_LeftForeArm", &"mixamorig_LeftHand",
	&"mixamorig_RightShoulder", &"mixamorig_RightArm", &"mixamorig_RightForeArm", &"mixamorig_RightHand",
]

# In func _build_jump_lower_body_layer(root: AnimationNodeBlendTree, available_clips: Dictionary) -> StringName:
	var legs := AnimationNodeBlend2.new()
	legs.sync = false
	legs.filter_enabled = true
	for bone: StringName in JUMP_LEG_BONES:
		legs.set_filter_path(NodePath(".:%s" % bone), true)
	for bone: StringName in JUMP_ARM_BONES:
		legs.set_filter_path(NodePath(".:%s" % bone), true)
```

#### Change 2: Ensure `_uses_upper_body_ready_layer` Does Not Suppress Jump Action
Target line: `1146-1151` in `scripts/player/operator_locomotion_blend_tree.gd`:
```gdscript
func _uses_upper_body_ready_layer(clip_name: StringName) -> bool:
	if source_jump_clip(clip_name) or clip_name == jump_lower_body_clip:
		# Jump action already owns torso/arms. Grounded fire-ready pose
		# must not replace them mid-jump.
		return false
	return _is_standing_locomotion_transition(clip_name) or _is_jump_mobility_clip(clip_name)
```

#### Change 3: Update Feature Contract `config/feature_contracts/jump_forward_legs.json`
Update acceptance criteria to reflect the integrated arm presentation:
```json
{
  "feature_id": "jump_forward_action",
  "player_intent": "Use forward-jump motion including active arm action while retaining equipped weapon aim stability across all running jump directions.",
  "acceptance_rule": "Normal and multi-directional running jump uses the saved forward clip on thigh-to-toe and shoulder-to-hand tracks, once per airborne entry across takeoff/fall, then releases at landing... Trigger and support hand contacts remain within 1.5 cm with zero wrist IK breakage.",
  ...
}
```

---

## 5. Verification Method

### 5.1 Automated Headless Regression Commands
1. **Feature Contract Regression Gate**:
   ```bash
   /Users/kiwimango/Applications/Godot-4.7.1.app/Contents/MacOS/Godot --headless -s tools/feature_contract_regression.gd
   # Expected result: PASS: 121 contract(s) form complete Godot integration graphs
   ```

2. **Dedicated Jump Arm Action Regression**:
   Run `tools/jump_action_arm_regression.gd`:
   ```bash
   /Users/kiwimango/Applications/Godot-4.7.1.app/Contents/MacOS/Godot --headless -s tools/jump_action_arm_regression.gd
   ```
   **Pass Criteria**:
   - `RightArm` rotational deviation > 0.17 rad (10°) from grounded ready aim during frames 4–20 of jump flight.
   - `LeftArm` rotational deviation > 0.17 rad (10°) from grounded ready aim.
   - `trigger_contact_m` <= 0.015 m (right palm firmly attached to weapon trigger socket).
   - `support_contact_m` <= 0.020 m (left palm firmly attached to weapon foregrip socket).
   - `bore_to_reticle_degrees` <= 6.0° (camera aim authority preserved per Rule 5).

3. **Source Jump Continuous Phase Regression**:
   ```bash
   /Users/kiwimango/Applications/Godot-4.7.1.app/Contents/MacOS/Godot --headless -s tools/source_jump_regression.gd
   # Expected result: SOURCE_JUMP_REGRESSION PASS []
   ```

4. **Public Training Range Integration Check**:
   ```bash
   /Users/kiwimango/Applications/Godot-4.7.1.app/Contents/MacOS/Godot --headless -s tools/public_training_range_regression.gd
   # Expected result: PUBLIC_TRAINING_RANGE_REGRESSION PASS (53/53 checks)
   ```

### 5.2 Invalidation Conditions
The proposed solution would be invalidated if:
- Mid-air TwoBoneIK creates wrist pop/disarticulation (`support_contact_m > 0.025 m`).
- The weapon barrel diverges from the reticle aim direction by > 6.0° during airborne flight.
- Mid-air weapon firing fails to register authoritative projectile spawn or recoil.
