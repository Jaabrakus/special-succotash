class_name SocomTestPlayer
extends CharacterBody3D

@export var walk_speed: float = 4.0
@export var run_speed: float = 6.5
@export var acceleration: float = 18.0
@export var turn_response: float = 12.0
@export var gravity: float = 22.0

var movement_yaw: float = 0.0
var replay_override_active: bool = false

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

    var speed := run_speed if Input.is_action_pressed("run") else walk_speed
    var desired_velocity := desired_dir * speed
    velocity.x = move_toward(velocity.x, desired_velocity.x, acceleration * delta)
    velocity.z = move_toward(velocity.z, desired_velocity.z, acceleration * delta)

    if not is_on_floor():
        velocity.y -= gravity * delta
    else:
        velocity.y = -0.5

    if desired_dir.length_squared() > 0.001:
        movement_yaw = atan2(-desired_dir.x, -desired_dir.z)
        rotation.y = lerp_angle(rotation.y, movement_yaw, 1.0 - exp(-turn_response * delta))

    move_and_slide()
