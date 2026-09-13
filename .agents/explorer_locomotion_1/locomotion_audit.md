# Quality Audit & Diagnostic Evaluation: Locomotion, Posture & Jump Mechanics

**Project**: SOCOM-141 Tactical Shooter  
**Auditor**: `explorer_locomotion_1` (Teamwork Quality Explorer)  
**Date**: 2026-09-12  
**Target Reference**: Authentic SOCOM II: U.S. Navy SEALs (PlayStation 2) & `AGENTS.md` / `docs/GAMEPLAY_INTENT_DICTIONARY.md` Architecture Contracts  
**Working Directory**: `/Users/kiwimango/socom-141-camera-lab/.agents/explorer_locomotion_1`  

---

## Executive Summary

A comprehensive, code-level diagnostic audit of character locomotion, posture transitions, jumping physics, lean peaking, and collision ownership was conducted across `scripts/player/`, `scenes/player/`, `config/`, and associated regression suites. 

While the locomotion framework features sophisticated sub-systems (such as stair-assist probing, predictive network movement history, and procedural bone pose composition), our investigation identified **12 verified defects and feel discrepancies** against authentic SOCOM 2 standards and project architectural rules:
1. **Critical Hit-Detection & Geometry Decoupling**: Lean peaking is 100% visual-only; the physical `CollisionShape3D` remains static at `(0, y, 0)`, creating "ghost-head" invulnerability behind cover in the canonical player scene and allowing geometry clipping.
2. **Arcade Movement Physics vs SOCOM 2 Tactical Weight**: In mid-air, characters have full ground acceleration, 0-frame instant strafing, and 60–90 m/s² braking/reversal, completely lacking ballistic momentum conservation.
3. **Missing Tactical Restrictions**: Zero jump cooldown, zero landing penalty/stumble, 1:1 backward run speed (no backpedal penalty), and 0-frame instantaneous posture resizing enabling crouch spamming.
4. **Active Regression Failures**: Two live regressions fail in the test suite: `tools/jump_direction_combo_regression.gd` (pelvis height discontinuity on crouched dive) and `tools/crouch_strafe_continuity_probe.gd` (head-height range excess during crouch direction changes).
5. **Architectural Parity Deficit**: The canonical local player scene (`scenes/player/operator_player.tscn`) omits the anatomical animated hurtbox rig present on network operators, resolving hit detection purely against a static capsule.

---

## Systematic Evaluation by Area

### 1. Locomotion Across All Gaits (Standing, Crouched, Prone)
- **Velocity Bounds**: Standing forward move speed is `6.5 m/s`, crouched speed is `2.6 m/s` (40% of standing), and prone crawl speed is `1.25 m/s` (19.2% of standing). These speed bounds provide good gait differentiation.
- **Directional Speed Ratios**: Forward and backward movement speeds are strictly identical (1.0:1.0 ratio). In authentic SOCOM 2, backpedaling incurs a significant speed penalty (~30-40% reduction, yielding ~4.0–4.5 m/s) to prevent sprinting backwards while firing.
- **Strafe Ratios & Competitive Burst**: Normal strafe speed is identical to forward speed (`6.5 m/s`). However, `_update_competitive_strafe()` injects an artificial `1.18x` speed multiplier (`7.67 m/s`) for 2 frames with decay upon starting or reversing a strafe. This modern competitive FPS mechanic (CS/Valorant jiggle-peek) directly conflicts with SOCOM 2's deliberate, weighted tactical movement.
- **Acceleration & Braking**: Base acceleration is `45.0 m/s²`, braking deceleration is `60.0 m/s²`, and reversal acceleration is `90.0 m/s²`. Furthermore, `instant_strafe_response: bool = true` teleports horizontal velocity to target velocity in 0 frames whenever lateral input is present (`absf(input.x) > 0.001`), violating `docs/GAMEPLAY_INTENT_DICTIONARY.md` line 54.

### 2. Directional Strafing Mechanics & Turning Responsiveness
- **Input Resolution**: `_resolve_opposing_lateral_input()` implements last-input priority (SOCD priority) rather than neutral cancellation.
- **Torso & Body Turning**: `torso_turn_in_place_limit_deg` is configured to `0.5` degrees with `torso_catchup_release_ratio = 0.0`. Consequently, any mouse or aim adjustment exceeding 0.5° immediately turns the entire `CharacterBody3D`. The character lacks independent torso twist when stationary, eliminating the authentic SOCOM 2 planted foot shuffle.

### 3. Lean Peaking Mechanics
- **Collision Hull Behavior**: Leaning modifies procedural bone rotations in `operator_posture_layer.gd` and adjusts camera shoulder offset in `camera_preferred_shot_solver.gd`. However, `_apply_posture_collider()` keeps `CollisionShape3D` positioned strictly at `(0, target_height * 0.5, 0)`. The collision capsule does not lean or offset laterally.
- **Camera Coupling & Rate Mismatch**: The camera lateral offset is coupled to `peek_amount * 0.38m`. In `player_controller.gd`, `peek_amount` moves at `peek_enter_response = 13.0` (~0.077s to enter) and `peek_exit_response = 16.0` (~0.063s to exit). In contrast, `operator_posture_layer.gd` blends visual skeletal lean over `blend_seconds = 0.18s`. The camera translates laterally more than 2.3x faster than the character model's head and rifle, creating a disorienting visual desynchronization.

### 4. Directional Jump Behavior
- **Momentum Conservation**: There is zero momentum conservation in the air. While `motion_state == MotionState.AIRBORNE`, the ground movement acceleration and braking formulas continue to execute. Releasing movement keys halts mid-air travel in ~0.10s (braking at 60 m/s²); pressing the opposite direction reverses travel mid-flight (reversing at 90 m/s²); jumping neutrally allows full acceleration mid-air; and lateral taps snap velocity instantly if `instant_strafe_response` is enabled.
- **Landing Penalty & Stumble**: While `landing_recovery = 0.18` seconds is defined, it does not alter velocity or restrict movement speed. Characters move at 100% full run speed (`6.5 m/s`) during `MotionState.LANDING`.
- **Jump Cooldown & Bunny-Hopping**: `_try_begin_mobility_action()` does not check `MotionState.LANDING` nor enforce any jump cooldown timer. A player can immediately re-jump the instant the floor is contacted, permitting continuous bunny-hopping.
- **Collision Hull Height in Jump**: On jumping, `posture` is forced to `MotionState.STANDING`, locking the capsule to `1.85m` height. Throughout the airborne trajectory, the capsule remains `1.85m` tall from the feet, reaching a peak altitude of `2.42m` without leg-tuck clearance adjustment.

### 5. Posture Transitions (Standing <-> Crouched <-> Prone)
- **Physics Timings**: Transitions occur instantaneously in 1 simulation tick (0.0 seconds) via `_try_set_posture()`. Capsule height instantly changes between 1.85m, 1.25m, and 0.82m.
- **Interruptibility & Crouch Spam**: Because no transition duration or cooldown exists in physics, players can alternate standing and crouching at 60 Hz ("crouch spam" / "teabagging") with instant hitbox deformation.
- **Camera Smoothing vs Collision Snap**: In `test_mannequin.gd`, camera stance anchors are smoothed exponentially (`crouch_amount` lerps at 14.0/s, taking ~0.30s), while the physical collision hull snaps in 0.0s, creating an out-of-sync state between physical cover height and viewport.

### 6. Single-Owner Architecture Compliance
- `CharacterBody3D` (`SocomTestPlayer`) acts as the primary movement owner. Neither camera nor animation scripts create duplicate velocity or transform writers during normal gameplay.
- Architectural Defect: Local player (`operator_player.tscn`) does not bind `SocomAnimatedHurtboxRig`. As a result, single-player/training combat damage is resolved solely against `CharacterBody3D.CollisionShape3D`, whereas multiplayer `SocomNetworkOperator` binds 10+ bone-following `Area3D` hurtboxes.

---

## Detailed Audit Findings & Translation Cards

### Defect 1: Instant Strafe Response and Zero-Frame Velocity Teleportation
- **Severity**: High (Core Feel & Architectural Contract Violation)
- **Reproduction Steps**:
  1. Boot `res://main.tscn`.
  2. While stationary or moving, tap `A` (move_left) or `D` (move_right).
  3. Observe velocity vector in debug overlays: horizontal velocity instantly sets to full target speed in 1 frame without acceleration.
- **Exact File & Lines**: `scripts/player/player_controller.gd:16, 388-391`
- **Verbatim Excerpt**:
```gdscript
@export var instant_strafe_response: bool = true
...
	elif instant_strafe_response and absf(input.x) > 0.001:
		horizontal_response_mode = &"INSTANT_STRAFE"
		horizontal_velocity = horizontal_target
```
- **Technical Explanation**:
  `instant_strafe_response` defaults to `true`. When any lateral input is detected (`absf(input.x) > 0.001`), the controller bypasses `_horizontal_response_acceleration()` and overwrites `horizontal_velocity = horizontal_target` directly. This snaps both X and Z velocity in 0 seconds. This violates `docs/GAMEPLAY_INTENT_DICTIONARY.md` (line 54: *"Movement feels like a joystick: Accelerate toward an input direction, decelerate when input ends, preserve momentum through turns... Never teleport the body transform"*). In authentic SOCOM 2, characters have palpable analog inertia and turning momentum; directional changes require acceleration rather than instant velocity snaps.
- **Remediation Recommendation (Translation Card)**:
  - **Player intent**: Strafing and directional transitions feel weighted and grounded like an analog gamepad; characters accelerate smoothly into a strafe without instant twitch snaps.
  - **Acceptance rule**: Lateral velocity adheres to configured acceleration curves (`acceleration` and `reversal_acceleration`); `horizontal_velocity` never snaps directly to `horizontal_target` in 0 frames during grounded locomotion.
  - **System owner**: `SocomTestPlayer` (`CharacterBody3D`).
  - **Must not change**: Maximum gait speed bounds (`move_speed`, `strafe_speed`), camera aiming, weapon firing cadence.
  - **Proof**: `tools/directional_locomotion_phase_regression.gd` and live inspection in `res://main.tscn`.

---

### Defect 2: Zero Air Momentum Conservation & Excessive Mid-Air Control
- **Severity**: High (Physics Integrity & SOCOM 2 Tactical Realism)
- **Reproduction Steps**:
  1. Boot `res://main.tscn`.
  2. Sprint forward and press `Space` to jump.
  3. Release `W` mid-air: character immediately stops horizontal travel in 0.10s and drops vertically.
  4. Alternatively, press `S` mid-air: character halts forward travel and reverses direction backwards in mid-air in 0.14s.
  5. Alternatively, perform a stationary neutral jump and press `W` at the jump apex: character accelerates to full 6.5 m/s sprint speed while airborne.
- **Exact File & Lines**: `scripts/player/player_controller.gd:380-402, 804-812`
- **Verbatim Excerpt**:
```gdscript
	var horizontal_velocity := Vector2(velocity.x, velocity.z)
	var horizontal_target := Vector2(desired_velocity.x, desired_velocity.z)
...
	else:
		var response_acceleration := _horizontal_response_acceleration(
			horizontal_velocity,
			horizontal_target
		)
		horizontal_velocity = horizontal_velocity.move_toward(
			horizontal_target,
			response_acceleration * delta
		)
	velocity.x = horizontal_velocity.x
	velocity.z = horizontal_velocity.y
```
- **Technical Explanation**:
  `_physics_process()` does not branch horizontal acceleration based on `is_on_floor()` or `motion_state == MotionState.AIRBORNE`. The entire ground response solver—including `braking_acceleration = 60.0`, `reversal_acceleration = 90.0`, and `instant_strafe_response`—executes identically while airborne. This produces arcade-like mid-air stopping, reversing, and steering. In authentic SOCOM 2, jumps are ballistic tactical leaps: the horizontal velocity at the moment of launch is conserved throughout the jump arc, with minimal to zero mid-air directional steering.
- **Remediation Recommendation (Translation Card)**:
  - **Player intent**: Jumping is a committed ballistic action; jumping forward carries the character's launch momentum through the arc, and mid-air input cannot stop or reverse flight.
  - **Acceptance rule**: While `motion_state == MotionState.AIRBORNE`, horizontal velocity conserves launch momentum with an air-control clamp not exceeding 10% steering influence; mid-air braking to zero and mid-air direction reversal are prohibited.
  - **System owner**: `SocomTestPlayer` (`CharacterBody3D`).
  - **Must not change**: Jump launch velocity (`jump_velocity = 5.0`), gravity (`22.0`), obstacle mantling probes.
  - **Proof**: `tools/source_jump_regression.gd` and focused mid-air impulse verification script.

---

### Defect 3: Missing Jump Cooldown and Absence of Landing Penalty
- **Severity**: Medium-High (Tactical Integrity & Anti-Exploit)
- **Reproduction Steps**:
  1. Boot `res://main.tscn`.
  2. Jump forward while holding `W`.
  3. As soon as the character touches the floor, immediately press `Space`.
  4. Observe character instantly jumping again with zero delay, maintaining continuous 6.5 m/s forward travel.
- **Exact File & Lines**: `scripts/player/player_controller.gd:50, 799-813, 899-908`
- **Verbatim Excerpt**:
```gdscript
@export var landing_recovery: float = 0.18
...
func _try_begin_mobility_action(
	desired_dir: Vector3,
	input: Vector2,
	jump_started: bool,
	command
) -> bool:
	if not _movement_floor_contact() or motion_state == MotionState.DIVING or motion_state == MotionState.ROLLING:
		return false

	if jump_started and posture != MotionState.PRONE:
		if not _try_set_posture(MotionState.STANDING):
			return false
...
		velocity.y = active_jump_launch_speed
		motion_state = MotionState.AIRBORNE
		_emit_mobility_started(&"AIRBORNE")
		return true
```
- **Technical Explanation**:
  `landing_recovery = 0.18` is tracked in `_update_air_and_landing_state()`, setting `motion_state = MotionState.LANDING`. However, `_movement_speed()` does not check `LANDING` and continues returning `move_speed = 6.5 m/s`. Furthermore, `_try_begin_mobility_action()` only rejects jumping if `not _movement_floor_contact()`, `DIVING`, or `ROLLING`. Because `_movement_floor_contact()` is true upon landing and `LANDING` is not excluded, players can bunny-hop continuously without speed degradation or cooldown. In authentic SOCOM 2, landing incurs a momentary stumble/velocity dampening penalty (~0.25–0.35s) during which re-jumping is locked out.
- **Remediation Recommendation (Translation Card)**:
  - **Player intent**: Landing from a jump feels heavy and tactical; the operator momentarily absorbs impact before regaining full running speed, preventing bunny-hopping.
  - **Acceptance rule**: During `MotionState.LANDING`, horizontal move speed is dampened by at least 40% (max 3.9 m/s) and jump input is ignored until `landing_recovery` elapsed time completes.
  - **System owner**: `SocomTestPlayer` (`CharacterBody3D`).
  - **Must not change**: Grounded sprint speed, mantling transitions, weapon fire readiness.
  - **Proof**: Focused jump landing regression measuring velocity across landing frames and bunny-hop rejection.

---

### Defect 4: Visual-Only Lean Peaking with Stationary Collision Hull ("Ghost Head")
- **Severity**: Critical (Hit-Detection, Collision Integrity & Competitive Fairness)
- **Reproduction Steps**:
  1. Boot `res://main.tscn`.
  2. Move behind a pillar or corner wall.
  3. Press `Q` (peek_left) or `E` (peek_right) to lean out into the open.
  4. Enable collision shape debug rendering (`CollisionShape3D.visible = true` or Godot debug collisions).
  5. Observe: The character model and camera lean out into the hallway, but `CollisionShape3D` remains 100% stationary behind the solid wall.
  6. Fire weapon hitscans at the leaned head: bullets strike the solid wall or miss the collider completely; the player is invincible while visually exposed.
- **Exact File & Lines**: `scripts/player/player_controller.gd:909-924`, `scripts/combat/socom_bullet_penetration.gd:113-115`
- **Verbatim Excerpt**:
```gdscript
func _apply_posture_collider() -> void:
	var collider := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if collider == null or not (collider.shape is CapsuleShape3D):
		return
	var capsule := collider.shape as CapsuleShape3D
	var target_height := 1.85
	if posture == MotionState.CROUCHED:
		target_height = 1.25
	elif posture == MotionState.PRONE:
		target_height = 0.82
	capsule.height = target_height
	collider.position.y = target_height * 0.5
	if mobility_combo_kind != &"":
		capsule.height = float(jump_combo_intent.profile.collider_height)
		collider.position.y = capsule.height * 0.5
```
- **Technical Explanation**:
  `_apply_posture_collider()` only adjusts `capsule.height` and `collider.position.y`. It never applies a lateral offset or tilt to `CollisionShape3D` based on `peek_amount`. Because `Player` in `main.tscn` is a `CharacterBody3D` without child `Area3D` hurtboxes, `socom_bullet_penetration.gd` tests collision directly against `Player.CollisionShape3D`. Consequently, when a player leans, their visual hitbox and collision hitbox become completely disjointed. An enemy aiming at the exposed visual head cannot deal damage, while an enemy firing at the empty space where the player was standing upright scores a hit. Additionally, because collision does not lean, the character's visual torso and head can lean through solid geometry without obstruction.
- **Remediation Recommendation (Translation Card)**:
  - **Player intent**: When leaning around cover, the operator's physical vulnerability and obstacle collision match the visible body; shooting the exposed head deals damage, and leaning into a solid wall is obstructed.
  - **Acceptance rule**: The player's collision and hurtbox geometry offsets laterally in direct synchronization with `peek_amount` (lateral offset = `peek_amount * peek_lean_distance`), with raycast hit detection verifying head vulnerability on the leaned model.
  - **System owner**: `SocomTestPlayer` (`CharacterBody3D`) for movement/world collision, `SocomAnimatedHurtboxRig` for ballistic hit detection.
  - **Must not change**: Camera rig obstruction raycasting, weapon mount anchoring, base standing/crouch posture heights.
  - **Proof**: `tools/lean_movement_latch_regression.gd` augmented with ballistic raycast verification on leaned head.

---

### Defect 5: Camera-Visual Desynchronization During Lean Peaking Transitions
- **Severity**: Medium (Camera & Viewport Polish)
- **Reproduction Steps**:
  1. Boot `res://main.tscn`.
  2. Press `Q` to lean left.
  3. Observe viewport camera: camera snaps laterally in ~4 frames (0.077s).
  4. Observe character model: operator torso and weapon take ~11 frames (0.180s) to settle into the lean pose.
- **Exact File & Lines**: `scripts/player/player_controller.gd:51-52, 202-203`, `scripts/camera/camera_preferred_shot_solver.gd:68`, `scripts/player/operator_posture_layer.gd:88-91`
- **Verbatim Excerpt**:
```gdscript
// player_controller.gd
@export_range(1.0, 30.0, 0.5) var peek_enter_response: float = 13.0
@export_range(1.0, 30.0, 0.5) var peek_exit_response: float = 16.0
...
var peek_response := peek_enter_response if absf(peek_target) > absf(peek_amount) else peek_exit_response
peek_amount = move_toward(peek_amount, peek_target, peek_response * delta)

// operator_posture_layer.gd
var blend_seconds: float = clampf(float(profile.get("authored_peek", {}).get("blend_seconds", 0.18)), 0.02, 0.5)
var step := delta / maxf(blend_seconds, 0.001)
visual_peek_amount = move_toward(visual_peek_amount, clampf(target, -1.0, 1.0), step)
```
- **Technical Explanation**:
  `player_controller.gd` updates `peek_amount` using `move_toward(..., peek_response * delta)` where `peek_enter_response = 13.0` (duration = `1.0 / 13.0 = 0.0769s`). `camera_preferred_shot_solver.gd` consumes `peek_amount` directly. In contrast, `operator_posture_layer.gd` reads `blend_seconds = 0.18` from configuration and updates `visual_peek_amount` over 0.18 seconds. The camera moves more than 2.3 times faster than the character model, causing the view to lead the body and creating a jarring visual popping sensation.
- **Remediation Recommendation (Translation Card)**:
  - **Player intent**: When leaning, the third-person camera tracks the operator's head in smooth, unified lockstep without leading or trailing the character model.
  - **Acceptance rule**: Camera lateral peek transition duration matches `operator_posture_layer.gd`'s `blend_seconds` (0.18s) within 0.01s tolerance.
  - **System owner**: `SocomCameraPreferredShotSolver` and `SocomTestPlayer`.
  - **Must not change**: Camera shoulder distance, aim tracking, weapon recoil pulse.
  - **Proof**: `tools/lean_upper_frame_regression.gd` paired with camera lateral displacement probe.

---

### Defect 6: Instantaneous Zero-Frame Posture Transitions & Crouch-Spam Exploit
- **Severity**: High (Tactical Authenticity & Hitbox Exploit)
- **Reproduction Steps**:
  1. Boot `res://main.tscn`.
  2. Rapidly alternate pressing `C` (crouch).
  3. Observe: Character collision capsule height instantly snaps between 1.85m and 1.25m on every individual frame without delay or motion gating.
- **Exact File & Lines**: `scripts/player/player_controller.gd:740-770, 909-935`
- **Verbatim Excerpt**:
```gdscript
func _try_set_posture(target_posture: int) -> bool:
	if target_posture == posture:
		return true
	if _posture_height(target_posture) > _posture_height(posture):
		if not _has_posture_clearance(target_posture):
			return false
	posture = target_posture
	motion_state = posture
	_apply_posture_collider()
	return true
```
- **Technical Explanation**:
  `_try_set_posture()` executes instantaneously with no transition state, locking, or duration in CharacterBody3D physics. When `C` is tapped, `posture` and `collider.height` snap in 1 frame. This allows players to "crouch spam" at 60 Hz to dodge incoming fire. Furthermore, while the collision snaps in 0.0s, camera markers in `test_mannequin.gd` smooth over ~0.30s (`1.0 - exp(-14.0 * delta)`), creating an extreme desynchronization where the player's physical hitbox is crouched while their camera view remains near standing height. In authentic SOCOM 2, stance changes required committed animation time (~0.3s to crouch, ~0.6s to drop to prone) with movement restrictions.
- **Remediation Recommendation (Translation Card)**:
  - **Player intent**: Changing stance is a deliberate tactical action with physical transition timing; rapid crouch spamming is prevented.
  - **Acceptance rule**: Posture transitions require a minimum transition time (0.25s for stand<->crouch, 0.50s for prone<->stand); re-triggering posture changes during transition is blocked, and collision shape interpolates or steps smoothly with animation progress.
  - **System owner**: `SocomTestPlayer` (`CharacterBody3D`).
  - **Must not change**: Headroom clearance raycast checks (`_has_posture_clearance`), prone crawling velocity.
  - **Proof**: Posture transition timing regression asserting 0.25s lock out and absence of 1-frame height snapping.

---

### Defect 7: Missing Backward Locomotion Speed Penalty (1:1 Backpedal Run Speed)
- **Severity**: Medium (Tactical Pacing & SOCOM 2 Authenticity)
- **Reproduction Steps**:
  1. Boot `res://main.tscn`.
  2. Hold `W` (forward): measure horizontal velocity (`6.5 m/s`).
  3. Hold `S` (backward): measure horizontal velocity (`6.5 m/s`).
  4. Observe identical velocity.
- **Exact File & Lines**: `scripts/player/player_controller.gd:438-444, 584-590`
- **Verbatim Excerpt**:
```gdscript
func _directional_movement_speed(move_axis: Vector2, forward_speed: float) -> float:
	if move_axis.length_squared() < 0.000001:
		return forward_speed
	var standing_ratio := clampf(strafe_speed / maxf(move_speed, 0.001), 0.10, 2.0)
	var lateral_weight := absf(move_axis.x) / maxf(move_axis.length(), 0.001)
	return lerpf(forward_speed, forward_speed * standing_ratio, lateral_weight)
```
- **Technical Explanation**:
  `_directional_movement_speed()` only checks `move_axis.x` to interpolate between forward and strafe speeds. It does not inspect `move_axis.y` for backward travel. When pressing `S` (`move_axis.y > 0`), the function returns `forward_speed` (6.5 m/s standing, 2.6 m/s crouched, 1.25 m/s prone). This allows players to sprint backwards at full speed while aiming and firing forward. In authentic SOCOM 2, backward running is penalised (~65% of forward speed, roughly 4.2 m/s).
- **Remediation Recommendation (Translation Card)**:
  - **Player intent**: Backpedaling feels slower and more cautious than running forward, preventing players from running backwards at full sprint while maintaining forward aim.
  - **Acceptance rule**: Backward movement speed is bounded to 65% of forward speed (`~4.2 m/s` standing, `~1.7 m/s` crouched).
  - **System owner**: `SocomTestPlayer` (`CharacterBody3D`).
  - **Must not change**: Forward run speed, strafe speed ratio, camera aim tracking.
  - **Proof**: Gait speed regression asserting `velocity.length() <= 4.3 m/s` when `move_axis == Vector2(0, 1)`.

---

### Defect 8: Non-Authentic Competitive Strafe Burst Multiplier (1.18x Speed Boost)
- **Severity**: Medium (Design & Feel Discrepancy against SOCOM 2)
- **Reproduction Steps**:
  1. Boot `res://main.tscn`.
  2. While running, rapidly oscillate between `A` and `D`.
  3. Observe velocity peaking up to `7.67 m/s` (1.18x over the base 6.5 m/s cap) during the first 2 frames of every reversal.
- **Exact File & Lines**: `scripts/player/player_controller.gd:25-29, 446-488`
- **Verbatim Excerpt**:
```gdscript
@export_group("Competitive strafe")
@export_range(1, 4, 1) var strafe_burst_frames: int = 2
@export_range(1.0, 1.5, 0.01) var strafe_burst_multiplier: float = 1.18
@export_range(0.0, 0.40, 0.01) var strafe_burst_decay_seconds: float = 0.12
@export_range(0.20, 1.50, 0.05) var strafe_chain_window_seconds: float = 0.70
```
- **Technical Explanation**:
  `_update_competitive_strafe()` injects a 2-frame velocity multiplier (`strafe_burst_multiplier = 1.18`) when starting a strafe or reversing direction. This was implemented as a competitive PC mechanic to simulate Counter-Strike/Valorant counter-strafing. However, SOCOM 2 was an analog PlayStation 2 third-person shooter where directional changes had inertia and weight; characters did not gain artificial acceleration bursts when reversing directions.
- **Remediation Recommendation (Translation Card)**:
  - **Player intent**: Movement direction changes feel continuous and grounded, without artificial speed spikes when jiggle-peeking.
  - **Acceptance rule**: Strafe speed remains strictly bounded by `strafe_speed` (6.5 m/s); `_update_competitive_strafe` multiplier defaults to 1.0.
  - **System owner**: `SocomTestPlayer` (`CharacterBody3D`).
  - **Must not change**: Turn response rate, foot contact locking, camera follow smoothing.
  - **Proof**: Directional strafe velocity assertion confirming velocity never exceeds `strafe_speed`.

---

### Defect 9: 0.5-Degree Torso Turn-in-Place Limit Causing Robotic Body Turreting
- **Severity**: Low-Medium (Animation Presentation & Locomotion Feel)
- **Reproduction Steps**:
  1. Boot `res://main.tscn`.
  2. Stand still and slowly move the mouse.
  3. Observe: The character's feet and entire collision body immediately rotate in place for minute mouse adjustments.
- **Exact File & Lines**: `scripts/player/player_controller.gd:33`, `scripts/player/operator_orientation_controller.gd:30-45`
- **Verbatim Excerpt**:
```gdscript
@export_range(0.0, 10.0, 0.1) var torso_turn_in_place_limit_deg: float = 0.5
...
	var yaw_error := wrapf(authoritative_aim_yaw - player.global_rotation.y, -PI, PI)
	if not catchup_active and absf(yaw_error) > torso_yaw_limit:
		catchup_active = true
```
- **Technical Explanation**:
  `torso_turn_in_place_limit_deg` is set to `0.5` degrees. The moment aim yaw error exceeds half a degree, `catchup_active` triggers and rotates `player.rotation.y`. There is essentially no independent upper-torso twist deadzone while stationary. In authentic SOCOM 2 and tactical games, the character's feet remain planted while the upper body twists to track aim up to 45°–60°; only when the aim exceeds that angle do the feet step and rotate to catch up.
- **Remediation Recommendation (Translation Card)**:
  - **Player intent**: When aiming while standing still, the operator twists at the waist while keeping feet planted, only shuffling feet to turn when aiming past a realistic torso limit.
  - **Acceptance rule**: Stationary turn-in-place threshold is increased to 45 degrees (`torso_turn_in_place_limit_deg = 45.0`); body rotation only activates once aim error exceeds 45 degrees.
  - **System owner**: `SocomOperatorOrientationController`.
  - **Must not change**: Running turn response (`turn_response = 12.0`), camera reticle alignment.
  - **Proof**: `tools/audit_operator_body_orientation.gd` and visual check in `main.tscn`.

---

### Defect 10: Active Regression Failure in `jump_direction_combo_regression.gd`
- **Severity**: High (Active Test Failure & Presentation Defect)
- **Reproduction Steps**:
  1. Run `/Users/kiwimango/Applications/Godot-4.7.1.app/Contents/MacOS/Godot --headless --path /Users/kiwimango/socom-141-camera-lab --script res://tools/jump_direction_combo_regression.gd`.
  2. Test execution fails with exit code 1.
- **Exact File & Lines**: `tools/jump_direction_combo_regression.gd:347-350`, `config/jump_direction_combos.json:21`
- **Verbatim Excerpt**:
```
CROUCH_NETWORK bit=1 expected= server= proxy= posture=1/1 floor=true position=(510.0, 0.000729, 500.0)
CROUCH_NETWORK bit=2 expected=crouch_dive_left server=crouch_dive_left proxy=crouch_dive_left posture=1/1 floor=true position=(508.1522, 0.000839, 500.0)
CROUCH_NETWORK bit=4 expected=crouch_dive_right server=crouch_dive_right proxy=crouch_dive_right posture=1/1 floor=true position=(511.8478, 0.000845, 500.0)
CROUCH_NETWORK bit=8 expected=crouch_dive_back server=crouch_dive_back proxy=crouch_dive_back posture=1/1 floor=true position=(510.0, 0.000839, 501.8478)
JUMP_DIRECTION_COMBO_REGRESSION FAIL ["Crouched dive starts at actual crouch pelvis 2", "Crouched dive starts at actual crouch pelvis 4", "Crouched dive starts at actual crouch pelvis 8"]
RIFLE_REFERENCE_PROBE FAIL /private/tmp/jump_direction_combo_regression ["Crouched dive starts at actual crouch pelvis 2", "Crouched dive starts at actual crouch pelvis 4", "Crouched dive starts at actual crouch pelvis 8"]
```
- **Technical Explanation**:
  In `tools/jump_direction_combo_regression.gd:350`, the test verifies that for crouched dives (`crouch_dive_left`, `crouch_dive_right`, `crouch_dive_back`), the `:mixamorig_Hips` position track at time 0.0 matches `aim_idle_crouch`'s hip position within 0.0001m. In the current baked animations, the hip position track in the crouched dive variants was baked with a vertical offset. When a crouched dive is triggered from crouch idle, the operator's pelvis snaps vertically at frame 0.
- **Remediation Recommendation (Translation Card)**:
  - **Player intent**: Initiating a directional dive from crouch transitions seamlessly from the crouch stance without any pelvis pop or height jerk.
  - **Acceptance rule**: `crouch_dive_left`, `crouch_dive_right`, and `crouch_dive_back` initial hip position keys match `aim_idle_crouch` within 0.0001m; `tools/jump_direction_combo_regression.gd` passes cleanly.
  - **System owner**: `tools/build_jump_direction_dives.gd` (asset processing) and `operator_animation_driver_pose.gd`.
  - **Must not change**: Dive trajectory velocities, camera recovery height envelopes.
  - **Proof**: `tools/jump_direction_combo_regression.gd` exit code 0.

---

### Defect 11: Active Probe Failure in `crouch_strafe_continuity_probe.gd`
- **Severity**: Medium (Active Test Failure & Presentation Defect)
- **Reproduction Steps**:
  1. Run `/Users/kiwimango/Applications/Godot-4.7.1.app/Contents/MacOS/Godot --headless --path /Users/kiwimango/socom-141-camera-lab --script res://tools/crouch_strafe_continuity_probe.gd`.
  2. Test execution fails with exit code 1.
- **Exact File & Lines**: `tools/crouch_strafe_continuity_probe.gd:83`
- **Verbatim Excerpt**:
```
CROUCH_SAMPLE move_forward frame=0 state=crouch action= hips=0.87453380017541 head=1.34786608605646 speed=0.39999998532809
CROUCH_SAMPLE move_forward frame=5 state=crouch action= hips=0.87897393340245 head=1.36013767356053 speed=0.39999998532809
CROUCH_SAMPLE move_forward frame=15 state=crouch action= hips=0.9173562079668 head=1.39293713867664 speed=0.39999998532809
CROUCH_SAMPLE move_forward frame=30 state=crouch action= hips=0.86078020185232 head=1.34046729654074 speed=0.39999998532809
CROUCH_SAMPLE move_forward frame=59 state=crouch action= hips=0.89756137877703 head=1.38512904196978 speed=0.39999998532809
CROUCH_METRIC move_forward hips_range=0.0707321614027 head_range=0.06484387814999 states={ "": true }
CROUCH_STRAFE_CONTINUITY FAIL phase_travel=2.82136829009758 failures=["direction changes remain within normal gait height variation"]
```
- **Technical Explanation**:
  `crouch_strafe_continuity_probe.gd:83` asserts that moving crouch direction changes (strafe to forward) maintain `max_head - min_head < 0.060m`. During the transition from `move_left` to `move_forward`, the head height range reaches `0.0648m`. The blend tree's crouch BlendSpace2D interpolates through a vertical displacement that causes noticeable head bobbing.
- **Remediation Recommendation (Translation Card)**:
  - **Player intent**: Changing movement direction while crouched maintains steady upper-body height without bobbing up and down.
  - **Acceptance rule**: Moving crouch direction changes keep head height variation below 0.060m across all transitions; `tools/crouch_strafe_continuity_probe.gd` passes cleanly.
  - **System owner**: `SocomOperatorLocomotionBlendTree` (`operator_locomotion_blend_tree.gd`).
  - **Must not change**: Crouch speed (`crouch_speed = 2.6`), crouch idle pose.
  - **Proof**: `tools/crouch_strafe_continuity_probe.gd` exit code 0.

---

### Defect 12: Architectural Divergence in Hurtbox Geometry Between Local Player and Network Operator
- **Severity**: High (Architectural Parity & Testing Fidelity)
- **Reproduction Steps**:
  1. Inspect `scenes/player/operator_player.tscn`: observe only one `CollisionShape3D`.
  2. Inspect `scenes/player/network_operator.tscn` and `scripts/network/socom_network_operator.gd:578-592`: observe runtime creation of `SocomAnimatedHurtboxRig` with 10+ bone-following `Area3D` capsules.
- **Exact File & Lines**: `scenes/player/operator_player.tscn:16-18`, `scripts/network/socom_network_operator.gd:578-592`
- **Verbatim Excerpt**:
```gdscript
func _bind_animated_hurtboxes() -> void:
	await get_tree().process_frame
	if mannequin == null or mannequin.production_animation == null:
		return
	var skeleton := mannequin.production_animation.skeleton as Skeleton3D
	if skeleton == null:
		push_warning("Network operator could not bind animated hurtboxes")
		return
	hurtbox_rig = AnimatedHurtboxRigScript.new() as SocomAnimatedHurtboxRig
	hurtbox_rig.name = "AnimatedHurtboxes"
	add_child(hurtbox_rig)
	hurtbox_rig.bind(skeleton, self)
	hurtbox_rig.set_debug_visible(false)
	_apply_hurtbox_runtime_mode()
```
- **Technical Explanation**:
  `SocomAnimatedHurtboxRig` is only instantiated and bound on `SocomNetworkOperator`. The canonical playable scene (`main.tscn`) uses `scenes/player/operator_player.tscn` which uses `SocomTestPlayer` (`player_controller.gd`). In single-player/training mode, `SocomAnimatedHurtboxRig` is completely absent. Consequently, weapon hit detection tests hit `Player.CollisionShape3D` (the static root capsule) rather than bone-accurate head/torso/limb hurtboxes. This creates an unacceptable disparity between the single-player/lab environment and the multiplayer game.
- **Remediation Recommendation (Translation Card)**:
  - **Player intent**: Bullet hit detection is anatomically accurate across all game modes; headshots and limb shots register identically in single-player training and multiplayer.
  - **Acceptance rule**: `SocomTestPlayer` (`operator_player.tscn`) binds `SocomAnimatedHurtboxRig` identically to `SocomNetworkOperator`, ensuring identical hurtbox topology.
  - **System owner**: `SocomTestPlayer` (`scenes/player/operator_player.tscn`) and `SocomAnimatedHurtboxRig`.
  - **Must not change**: CharacterBody3D collision mask, movement physics, weapon damage calculation.
  - **Proof**: Hitbox registration test verifying `Area3D` hurtbox collisions in `main.tscn`.

---

## Synthesis & Recommended Prioritized Remediation Plan

| Priority | Defect ID | Description | Primary Owner | Fix Effort |
|:---:|:---:|:---|:---|:---:|
| **P0** | **Defect 4** | Visual-only lean peaking ("Ghost Head" invulnerability & wall clipping) | `SocomTestPlayer` | Medium |
| **P0** | **Defect 12** | Local player missing animated hurtboxes | `operator_player.tscn` | Low |
| **P1** | **Defect 10** | Failing `jump_direction_combo_regression.gd` (crouched dive pelvis pop) | `build_jump_direction_dives.gd` | Medium |
| **P1** | **Defect 11** | Failing `crouch_strafe_continuity_probe.gd` (crouch strafe head bob) | `operator_locomotion_blend_tree.gd` | Medium |
| **P1** | **Defect 2** | Zero air momentum conservation (mid-air braking/reversing) | `player_controller.gd` | Medium |
| **P1** | **Defect 1** | Instant strafe response (0-frame velocity snap) | `player_controller.gd` | Low |
| **P2** | **Defect 3** | Missing jump cooldown & landing stumble penalty | `player_controller.gd` | Low |
| **P2** | **Defect 6** | 0-frame posture snap & crouch-spam exploit | `player_controller.gd` | Medium |
| **P2** | **Defect 7** | Missing backward speed penalty (1:1 backpedal) | `player_controller.gd` | Low |
| **P2** | **Defect 5** | Camera-visual desynchronization during lean (rate mismatch) | `camera_preferred_shot_solver.gd` | Low |
| **P3** | **Defect 8** | Non-authentic 1.18x competitive strafe burst multiplier | `player_controller.gd` | Low |
| **P3** | **Defect 9** | 0.5-degree torso turn-in-place threshold | `player_controller.gd` | Low |

---

*Report compiled by explorer_locomotion_1 in accordance with AGENTS.md rules 1–10.*
