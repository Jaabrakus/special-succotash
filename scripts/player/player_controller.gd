class_name SocomTestPlayer
extends CharacterBody3D

const OperatorOrientationController := preload("res://scripts/player/operator_orientation_controller.gd")

@export var walk_speed: float = 4.0
@export var run_speed: float = 6.5
@export var acceleration: float = 18.0
@export var turn_response: float = 12.0
@export var gravity: float = 22.0

@export_group("Locomotion orientation")
@export_range(1.0, 30.0, 0.5) var idle_turn_response: float = 9.0
@export_range(20.0, 85.0, 1.0) var torso_turn_in_place_limit_deg: float = 52.0

@export_group("Tactical mobility")
@export var crouch_speed: float = 2.6
@export var prone_speed: float = 1.25
@export var jump_velocity: float = 6.2
@export var dive_speed: float = 7.6
@export var dive_duration: float = 0.72
@export var roll_speed: float = 6.8
@export var roll_duration: float = 0.62
@export var landing_recovery: float = 0.18

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

func _physics_process(delta: float) -> void:
    if replay_override_active:
        velocity = Vector3.ZERO
        return
    var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
    var automated_world_direction := Vector3.ZERO
    if OS.get_cmdline_user_args().has("--movement-test"):
        input = Vector2(1.0, 0.0)
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
    var camera := get_viewport().get_camera_3d()

    var forward := Vector3.FORWARD
    var right := Vector3.RIGHT
    if camera:
        forward = -camera.global_basis.z
        forward.y = 0.0
        forward = forward.normalized()
        right = camera.global_basis.x
        right.y = 0.0
        right = right.normalized()

    var desired_dir := (right * input.x + forward * -input.y)
    if automated_world_direction != Vector3.ZERO:
        desired_dir = automated_world_direction
    if desired_dir.length_squared() > 1.0:
        desired_dir = desired_dir.normalized()
    desired_movement_direction = desired_dir

    var actions_enabled := not (
        OS.get_cmdline_user_args().has("--automated-test")
        or OS.get_cmdline_user_args().has("--movement-test")
        or OS.get_cmdline_user_args().has("--wall-entry-test")
        or OS.get_cmdline_user_args().has("--wall-follow-test")
        or OS.get_cmdline_user_args().has("--camera-stress-test")
    )
    if actions_enabled:
        _handle_posture_input()
        _try_begin_mobility_action(desired_dir, input)

    if motion_state == MotionState.DIVING or motion_state == MotionState.ROLLING:
        _advance_committed_action(delta)
        _update_orientation(action_direction, delta)
        move_and_slide()
        was_on_floor = is_on_floor()
        return

    var speed := _movement_speed()
    var desired_velocity := desired_dir * speed
    velocity.x = move_toward(velocity.x, desired_velocity.x, acceleration * delta)
    velocity.z = move_toward(velocity.z, desired_velocity.z, acceleration * delta)

    if actions_enabled and Input.is_action_just_pressed("jump") and is_on_floor() and posture != MotionState.PRONE:
        posture = MotionState.STANDING
        _apply_posture_collider()
        velocity.y = jump_velocity
        motion_state = MotionState.AIRBORNE
    elif not is_on_floor():
        velocity.y -= gravity * delta
    else:
        velocity.y = -0.5

    _update_orientation(desired_dir, delta)

    move_and_slide()
    _update_air_and_landing_state(delta)
    was_on_floor = is_on_floor()

func _update_orientation(desired_dir: Vector3, delta: float) -> void:
    var rig := get_tree().get_first_node_in_group("socom_camera_rig")
    var authoritative_aim_yaw := global_rotation.y
    if rig != null:
        authoritative_aim_yaw = float(rig.get("aim_yaw"))
    orientation.update(
        self,
        desired_dir,
        authoritative_aim_yaw,
        delta,
        turn_response,
        idle_turn_response,
        deg_to_rad(torso_turn_in_place_limit_deg)
    )
    movement_yaw = rotation.y

func get_aim_relative_yaw() -> float:
    return orientation.aim_relative_yaw

func get_desired_movement_direction() -> Vector3:
    return desired_movement_direction

func is_turning_in_place() -> bool:
    return orientation.is_turning_in_place

func _movement_speed() -> float:
    if posture == MotionState.PRONE:
        return prone_speed
    if posture == MotionState.CROUCHED:
        return crouch_speed
    return run_speed if Input.is_action_pressed("run") else walk_speed

func _handle_posture_input() -> void:
    if motion_state == MotionState.DIVING or motion_state == MotionState.ROLLING:
        return
    if Input.is_action_just_pressed("crouch"):
        posture = (
            MotionState.STANDING
            if posture == MotionState.CROUCHED
            else MotionState.CROUCHED
        )
        motion_state = posture
        _apply_posture_collider()
    if Input.is_action_just_pressed("prone"):
        posture = (
            MotionState.CROUCHED
            if posture == MotionState.PRONE
            else MotionState.PRONE
        )
        motion_state = posture
        _apply_posture_collider()

func _try_begin_mobility_action(desired_dir: Vector3, input: Vector2) -> void:
    if not is_on_floor() or motion_state == MotionState.DIVING or motion_state == MotionState.ROLLING:
        return
    if Input.is_action_just_pressed("dive") and posture != MotionState.PRONE:
        action_direction = _safe_action_direction(desired_dir)
        action_elapsed = 0.0
        action_duration = dive_duration
        motion_state = MotionState.DIVING
        posture = MotionState.STANDING
        _apply_posture_collider()
        velocity.y = 1.2
        return
    if Input.is_action_just_pressed("roll") and posture != MotionState.PRONE:
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
