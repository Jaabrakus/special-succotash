class_name SocomOperatorOrientationController
extends RefCounted

## Separates camera-relative travel from mouse/right-stick aim authority.
## Movement never rewrites aim. The lower body catches up only after torso twist
## reaches its limit, preserving true strafing and backpedaling.

var movement_direction := Vector3.ZERO
var aim_relative_yaw: float = 0.0
var is_turning_in_place: bool = false
var catchup_active: bool = false

func update(
    player: CharacterBody3D,
    desired_direction: Vector3,
    authoritative_aim_yaw: float,
    delta: float,
    moving_turn_response: float,
    idle_turn_response: float,
    torso_yaw_limit: float,
    catchup_release_ratio: float = 0.72
) -> void:
    movement_direction = desired_direction
    movement_direction.y = 0.0
    var is_moving := movement_direction.length_squared() > 0.001
    if is_moving:
        movement_direction = movement_direction.normalized()

    var yaw_error := wrapf(authoritative_aim_yaw - player.global_rotation.y, -PI, PI)
    if not catchup_active and absf(yaw_error) > torso_yaw_limit:
        catchup_active = true

    var release_limit := torso_yaw_limit * clampf(catchup_release_ratio, 0.45, 0.90)
    if catchup_active:
        # Finish the hip catch-up inside the limit. Stopping directly on the
        # limit caused rapid enter/exit chatter under tiny mouse corrections.
        var permitted_twist := signf(yaw_error) * release_limit
        var catchup_yaw := player.rotation.y + yaw_error - permitted_twist
        var response := moving_turn_response if is_moving else idle_turn_response
        player.rotation.y = lerp_angle(
            player.rotation.y,
            catchup_yaw,
            1.0 - exp(-response * delta)
        )
        var remaining_error := wrapf(
            authoritative_aim_yaw - player.global_rotation.y,
            -PI,
            PI
        )
        if absf(remaining_error) <= release_limit + deg_to_rad(0.35):
            catchup_active = false
        is_turning_in_place = not is_moving
    else:
        is_turning_in_place = false

    aim_relative_yaw = wrapf(authoritative_aim_yaw - player.global_rotation.y, -PI, PI)

func reset(player: CharacterBody3D, authoritative_aim_yaw: float) -> void:
    movement_direction = Vector3.ZERO
    aim_relative_yaw = wrapf(authoritative_aim_yaw - player.global_rotation.y, -PI, PI)
    is_turning_in_place = false
    catchup_active = false
