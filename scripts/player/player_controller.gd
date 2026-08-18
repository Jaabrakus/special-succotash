class_name SocomTestPlayer
extends CharacterBody3D

const OperatorOrientationController := preload("res://scripts/player/operator_orientation_controller.gd")
const MovementCommand := preload("res://scripts/network/socom_movement_command.gd")

@export var move_speed: float = 6.5
@export var strafe_speed: float = 5.6
@export var acceleration: float = 18.0
@export var braking_acceleration: float = 26.0
@export var reversal_acceleration: float = 22.0
@export var turn_response: float = 12.0
@export var gravity: float = 22.0

@export_group("Locomotion orientation")
@export_range(1.0, 30.0, 0.5) var idle_turn_response: float = 9.0
@export_range(20.0, 85.0, 1.0) var torso_turn_in_place_limit_deg: float = 42.0
@export_range(0.45, 0.90, 0.01) var torso_catchup_release_ratio: float = 0.72
@export_range(0.25, 0.95, 0.01) var full_gait_input_threshold: float = 0.72

@export_group("Tactical mobility")
@export var crouch_speed: float = 2.6
@export var prone_speed: float = 1.25
@export var jump_velocity: float = 6.2
@export var dive_speed: float = 7.6
@export var dive_duration: float = 0.72
@export var dive_minimum_run_speed: float = 2.8
@export var roll_speed: float = 6.8
@export var roll_duration: float = 0.62
@export var landing_recovery: float = 0.18
@export_range(1.0, 30.0, 0.5) var peek_enter_response: float = 13.0
@export_range(1.0, 30.0, 0.5) var peek_exit_response: float = 16.0

enum MotionState {
    STANDING,
    CROUCHED,
    PRONE,
    AIRBORNE,
    LANDING,
    DIVING,
    ROLLING,
}

var movement_yaw: float = 0.0
var replay_override_active: bool = false
var posture: int = MotionState.STANDING
var motion_state: int = MotionState.STANDING
var action_elapsed: float = 0.0
var action_duration: float = 0.0
var action_direction: Vector3 = Vector3.FORWARD
var roll_side: float = 1.0
var was_on_floor: bool = true
var orientation := OperatorOrientationController.new()
var desired_movement_direction := Vector3.ZERO
var movement_input_strength: float = 0.0
var horizontal_response_mode: StringName = &"IDLE"
var movement_command_queue: Array = []
var last_movement_command
var local_input_enabled: bool = true

# Context-Sensitive Multi-Function Input
var stance_hold_timer: float = 0.0
var stance_held_triggered: bool = false
var stance_hold_threshold: float = 0.20
var jump_was_held: bool = false
var jump_requested: bool = false
var peek_amount: float = 0.0

func _physics_process(delta: float) -> void:
    if replay_override_active:
        velocity = Vector3.ZERO
        return
    var command = _consume_movement_command()
    last_movement_command = command.duplicate_command()
    var input: Vector2 = command.move_axis
    var automated_world_direction: Vector3 = command.world_move_override
    var authoritative_aim_yaw: float = command.aim_yaw
    var peek_target: float = clampf(command.peek_axis, -1.0, 1.0)
    if OS.get_cmdline_user_args().has("--peek-left-test"):
        peek_target = -1.0
    elif OS.get_cmdline_user_args().has("--peek-right-test"):
        peek_target = 1.0
    if motion_state in [MotionState.DIVING, MotionState.ROLLING, MotionState.AIRBORNE]:
        peek_target = 0.0
    var peek_response := peek_enter_response if absf(peek_target) > absf(peek_amount) else peek_exit_response
    peek_amount = move_toward(peek_amount, peek_target, peek_response * delta)
    if OS.get_cmdline_user_args().has("--movement-test"):
        input = Vector2(1.0, 0.0)
    elif OS.get_cmdline_user_args().has("--prone-forward-test"):
        input = Vector2(0.0, -1.0)
    elif OS.get_cmdline_user_args().has("--wall-entry-test"):
        input = Vector2.ZERO
        var test_frame := Engine.get_physics_frames()
        if test_frame < 150:
            automated_world_direction = Vector3.LEFT
        elif test_frame >= 420 and test_frame < 540:
            automated_world_direction = Vector3.RIGHT
    elif OS.get_cmdline_user_args().has("--wall-follow-test"):
        input = Vector2.ZERO
        var follow_frame := Engine.get_physics_frames()
        if follow_frame < 600:
            automated_world_direction = Vector3.RIGHT
    elif OS.get_cmdline_user_args().has("--camera-stress-test"):
        input = Vector2.ZERO
        var stress_phase: int = Engine.get_physics_frames() % 600
        if stress_phase < 150:
            automated_world_direction = Vector3.LEFT
        elif stress_phase < 300:
            automated_world_direction = Vector3.FORWARD
        elif stress_phase < 450:
            automated_world_direction = Vector3.RIGHT
        else:
            automated_world_direction = Vector3.BACK
    elif OS.get_cmdline_user_args().has("--automated-test"):
        input = Vector2.ZERO
    # Travel follows raw aim authority, never the rendered camera transform.
    # A wall post-solve can move the lens without bending WASD travel.
    var aim_basis := Basis(Vector3.UP, authoritative_aim_yaw)
    var forward: Vector3 = aim_basis * Vector3.FORWARD
    var right: Vector3 = aim_basis * Vector3.RIGHT

    var desired_dir := (right * input.x + forward * -input.y)
    if automated_world_direction != Vector3.ZERO:
        desired_dir = automated_world_direction
    if desired_dir.length_squared() > 1.0:
        desired_dir = desired_dir.normalized()
    desired_movement_direction = desired_dir
    movement_input_strength = clampf(desired_dir.length(), 0.0, 1.0)

    var actions_enabled := not (
        OS.get_cmdline_user_args().has("--automated-test")
        or OS.get_cmdline_user_args().has("--movement-test")
        or OS.get_cmdline_user_args().has("--wall-entry-test")
        or OS.get_cmdline_user_args().has("--wall-follow-test")
        or OS.get_cmdline_user_args().has("--camera-stress-test")
    )
    var jump_started: bool = jump_requested or command.jump_pressed
    jump_requested = false
    var launched_jump_this_frame := false
    if actions_enabled:
        _handle_posture_command(command, delta, desired_dir)
        launched_jump_this_frame = _try_begin_mobility_action(
            desired_dir,
            input,
            jump_started,
            command
        )

    if motion_state == MotionState.DIVING or motion_state == MotionState.ROLLING:
        _advance_committed_action(delta)
        _update_orientation(action_direction, authoritative_aim_yaw, delta)
        move_and_slide()
        _finish_committed_action_on_collision()
        was_on_floor = is_on_floor()
        return

    var speed := _directional_movement_speed(input, _movement_speed())
    var desired_velocity := desired_dir * speed
    # Accelerate as one horizontal vector. Advancing X and Z separately makes
    # diagonal response up to sqrt(2) times stronger than cardinal response.
    var horizontal_velocity := Vector2(velocity.x, velocity.z)
    var horizontal_target := Vector2(desired_velocity.x, desired_velocity.z)
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

    if launched_jump_this_frame:
        # Preserve the impulse assigned above. is_on_floor() remains true until
        # move_and_slide(), so the normal grounded branch must not erase it.
        pass
    elif not is_on_floor():
        velocity.y -= gravity * delta
    else:
        velocity.y = -0.5

    _update_orientation(desired_dir, authoritative_aim_yaw, delta)

    move_and_slide()
    _update_air_and_landing_state(delta)
    was_on_floor = is_on_floor()

func _update_orientation(
    desired_dir: Vector3,
    authoritative_aim_yaw: float,
    delta: float
) -> void:
    orientation.update(
        self,
        desired_dir,
        authoritative_aim_yaw,
        delta,
        turn_response,
        idle_turn_response,
        deg_to_rad(torso_turn_in_place_limit_deg),
        torso_catchup_release_ratio
    )
    movement_yaw = rotation.y

func get_aim_relative_yaw() -> float:
    return orientation.aim_relative_yaw

func _directional_movement_speed(move_axis: Vector2, forward_speed: float) -> float:
    if move_axis.length_squared() < 0.000001:
        return forward_speed
    var standing_ratio := clampf(strafe_speed / maxf(move_speed, 0.001), 0.10, 2.0)
    var lateral_weight := absf(move_axis.x) / maxf(move_axis.length(), 0.001)
    return lerpf(forward_speed, forward_speed * standing_ratio, lateral_weight)

func get_desired_movement_direction() -> Vector3:
    return desired_movement_direction

func get_peek_amount() -> float:
    return peek_amount

func is_turning_in_place() -> bool:
    return orientation.is_turning_in_place

func request_jump() -> void:
    # Public one-shot command used by replay/network input snapshots and tests.
    # Local keyboard/controller input still enters through the same latch above.
    jump_requested = true

func queue_movement_command(command) -> void:
    # Network/replay code may enqueue immutable per-tick commands. The queue is
    # deliberately independent from camera nodes and local device state.
    if command != null:
        movement_command_queue.push_back(command.duplicate_command())

func set_local_input_enabled(enabled: bool) -> void:
    local_input_enabled = enabled

func get_last_movement_command():
    return last_movement_command.duplicate_command() if last_movement_command != null else null

func _consume_movement_command():
    if not movement_command_queue.is_empty():
        return movement_command_queue.pop_front()
    return _capture_local_movement_command()

func _capture_local_movement_command():
    var command = MovementCommand.new()
    command.simulation_tick = Engine.get_physics_frames()
    command.aim_yaw = global_rotation.y
    var rig := get_tree().get_first_node_in_group("socom_camera_rig")
    if rig != null:
        command.aim_yaw = float(rig.get("aim_yaw"))
    if not local_input_enabled:
        return command
    command.move_axis = Input.get_vector(
        "move_left", "move_right", "move_forward", "move_back"
    )
    command.jump_pressed = Input.is_action_just_pressed("jump")
    command.dive_pressed = Input.is_action_just_pressed("dive")
    command.roll_pressed = Input.is_action_just_pressed("roll")
    command.prone_pressed = Input.is_action_just_pressed("prone")
    command.crouch_held = Input.is_action_pressed("crouch")
    command.crouch_released = Input.is_action_just_released("crouch")
    command.peek_axis = Input.get_axis("peek_left", "peek_right")
    return command

func _movement_speed() -> float:
    if posture == MotionState.PRONE:
        return prone_speed
    if posture == MotionState.CROUCHED:
        return crouch_speed
    return move_speed

func _horizontal_response_acceleration(current: Vector2, target: Vector2) -> float:
    if target.length_squared() < 0.0001:
        horizontal_response_mode = &"BRAKING" if current.length_squared() > 0.0001 else &"IDLE"
        return braking_acceleration
    if current.length_squared() > 0.0001:
        var alignment := current.normalized().dot(target.normalized())
        if alignment < -0.20:
            horizontal_response_mode = &"REVERSING"
            return reversal_acceleration
    horizontal_response_mode = &"ACCELERATING"
    return acceleration

func get_horizontal_response_mode() -> StringName:
    return horizontal_response_mode

func get_movement_gait_name() -> StringName:
    # SOCOM has no sprint command. The locomotion gait follows analog stick
    # magnitude: a partial stick walks and a full stick uses the quick tactical
    # gait. Keyboard WASD naturally reports full magnitude.
    return (
        &"FULL"
        if posture == MotionState.STANDING
        and movement_input_strength >= full_gait_input_threshold
        else &"WALK"
    )

func _handle_posture_command(command, delta: float, desired_dir: Vector3) -> void:
    if motion_state == MotionState.DIVING or motion_state == MotionState.ROLLING:
        # A stance-hold dive can finish after C has already been released. Consume
        # that release while the committed action owns movement so the hold latch
        # cannot remain stuck and poison the next stance command.
        if command.crouch_released:
            stance_hold_timer = 0.0
            stance_held_triggered = false
        return

    # Direct Prone shortcut (Z)
    if command.prone_pressed:
        _try_set_posture(
            MotionState.CROUCHED if posture == MotionState.PRONE else MotionState.PRONE
        )
        return

    # Multi-function Stance Button (C / Crouch): Tap = Crouch/Stand, Hold = Drop to Prone
    if command.crouch_held:
        stance_hold_timer += delta
        if stance_hold_timer >= stance_hold_threshold and not stance_held_triggered:
            stance_held_triggered = true
            if _can_stance_hold_dive(desired_dir):
                _begin_dive(desired_dir)
            else:
                _try_set_posture(MotionState.PRONE)

    if command.crouch_released:
        if not stance_held_triggered:
            # Quick Tap action
            var target_posture := MotionState.CROUCHED
            if posture == MotionState.PRONE:
                target_posture = MotionState.CROUCHED
            elif posture == MotionState.CROUCHED:
                target_posture = MotionState.STANDING
            _try_set_posture(target_posture)
        stance_hold_timer = 0.0
        stance_held_triggered = false

func _can_stance_hold_dive(desired_dir: Vector3) -> bool:
    if posture == MotionState.PRONE or not is_on_floor():
        return false
    return (
        desired_dir.length() >= full_gait_input_threshold
        and Vector2(velocity.x, velocity.z).length() >= dive_minimum_run_speed
    )

func _begin_dive(desired_dir: Vector3) -> void:
    action_direction = _safe_action_direction(desired_dir)
    action_elapsed = 0.0
    action_duration = dive_duration
    motion_state = MotionState.DIVING
    posture = MotionState.STANDING
    _apply_posture_collider()
    velocity.y = 2.4

func _try_begin_mobility_action(
    desired_dir: Vector3,
    input: Vector2,
    jump_started: bool,
    command
) -> bool:
    if not is_on_floor() or motion_state == MotionState.DIVING or motion_state == MotionState.ROLLING:
        return false

    # Jump owns one action only. Travel input must never reinterpret Space as a
    # dive; that would make the same network command produce two outcomes.
    if jump_started and posture != MotionState.PRONE:
        if not _try_set_posture(MotionState.STANDING):
            return false
        velocity.y = jump_velocity
        motion_state = MotionState.AIRBORNE
        return true

    # Z is the independent dive-to-prone action.
    if command.dive_pressed and posture != MotionState.PRONE:
        _begin_dive(desired_dir)
        return false

    # Roll shortcut (E / Alt)
    if command.roll_pressed and posture != MotionState.PRONE:
        roll_side = -1.0 if input.x < -0.1 else 1.0
        if absf(input.x) > 0.1:
            action_direction = global_basis.x * signf(input.x)
        else:
            action_direction = _safe_action_direction(desired_dir)
        action_direction.y = 0.0
        action_direction = action_direction.normalized()
        action_elapsed = 0.0
        action_duration = roll_duration
        motion_state = MotionState.ROLLING
        posture = MotionState.CROUCHED
        _apply_posture_collider()
    return false

func _safe_action_direction(desired_dir: Vector3) -> Vector3:
    var result := desired_dir
    if result.length_squared() < 0.01:
        result = -global_basis.z
    result.y = 0.0
    return result.normalized()

func _advance_committed_action(delta: float) -> void:
    action_elapsed = minf(action_elapsed + delta, action_duration)
    var phase := get_action_phase()
    var base_speed := dive_speed if motion_state == MotionState.DIVING else roll_speed
    var speed_scale := lerpf(1.0, 0.32, phase)
    velocity.x = action_direction.x * base_speed * speed_scale
    velocity.z = action_direction.z * base_speed * speed_scale
    if not is_on_floor():
        velocity.y -= gravity * delta
    else:
        velocity.y = -0.5
    if action_elapsed >= action_duration:
        if motion_state == MotionState.DIVING:
            posture = MotionState.PRONE
        else:
            posture = MotionState.CROUCHED
        motion_state = posture
        _apply_posture_collider()

func _finish_committed_action_on_collision() -> void:
    if get_slide_collision_count() <= 0:
        return
    for collision_index in range(get_slide_collision_count()):
        var collision := get_slide_collision(collision_index)
        if absf(collision.get_normal().y) < 0.55:
            action_elapsed = action_duration
            posture = (
                MotionState.PRONE
                if motion_state == MotionState.DIVING
                else MotionState.CROUCHED
            )
            motion_state = posture
            velocity.x = 0.0
            velocity.z = 0.0
            _apply_posture_collider()
            return

func _update_air_and_landing_state(delta: float) -> void:
    if not is_on_floor():
        motion_state = MotionState.AIRBORNE
        return
    if not was_on_floor and motion_state == MotionState.AIRBORNE:
        motion_state = MotionState.LANDING
        action_elapsed = 0.0
        action_duration = landing_recovery
    elif motion_state == MotionState.LANDING:
        action_elapsed += delta
        if action_elapsed >= action_duration:
            motion_state = posture
    elif motion_state != MotionState.DIVING and motion_state != MotionState.ROLLING:
        motion_state = posture

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

func _posture_height(target_posture: int) -> float:
    if target_posture == MotionState.PRONE:
        return 0.82
    if target_posture == MotionState.CROUCHED:
        return 1.25
    return 1.85

func _has_posture_clearance(target_posture: int) -> bool:
    var collider := get_node_or_null("CollisionShape3D") as CollisionShape3D
    if collider == null or not (collider.shape is CapsuleShape3D):
        return true
    var current_capsule := collider.shape as CapsuleShape3D
    var current_height: float = _posture_height(posture)
    var target_height: float = _posture_height(target_posture)
    var space := get_world_3d().direct_space_state
    var ray_offsets: Array[Vector3] = [
        Vector3.ZERO,
        Vector3.RIGHT * current_capsule.radius * 0.65,
        Vector3.LEFT * current_capsule.radius * 0.65,
        Vector3.FORWARD * current_capsule.radius * 0.65,
        Vector3.BACK * current_capsule.radius * 0.65,
    ]
    for offset in ray_offsets:
        var ray := PhysicsRayQueryParameters3D.create(
            global_position + offset + Vector3.UP * (current_height + 0.01),
            global_position + offset + Vector3.UP * (target_height + 0.03),
            collision_mask,
            [get_rid()]
        )
        ray.collide_with_areas = false
        var clearance_hit := space.intersect_ray(ray)
        if not clearance_hit.is_empty():
            return false
    var probe := CapsuleShape3D.new()
    probe.radius = current_capsule.radius
    probe.height = target_height
    var query := PhysicsShapeQueryParameters3D.new()
    query.shape = probe
    query.transform = Transform3D(
        global_basis,
        global_position + Vector3.UP * (probe.height * 0.5 + 0.015)
    )
    query.collision_mask = collision_mask
    query.collide_with_areas = false
    query.exclude = [get_rid()]
    return space.intersect_shape(query, 1).is_empty()

func get_action_phase() -> float:
    if action_duration <= 0.0:
        return 0.0
    return clampf(action_elapsed / action_duration, 0.0, 1.0)

func get_motion_state_name() -> StringName:
    match motion_state:
        MotionState.CROUCHED:
            return &"CROUCHED"
        MotionState.PRONE:
            return &"PRONE"
        MotionState.AIRBORNE:
            return &"AIRBORNE"
        MotionState.LANDING:
            return &"LANDING"
        MotionState.DIVING:
            return &"DIVING"
        MotionState.ROLLING:
            return &"ROLLING"
        _:
            return &"STANDING"

func get_posture_name() -> StringName:
    if posture == MotionState.PRONE:
        return &"PRONE"
    if posture == MotionState.CROUCHED:
        return &"CROUCHED"
    return &"STANDING"
